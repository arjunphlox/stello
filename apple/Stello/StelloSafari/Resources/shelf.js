// Stello in every page: the drop shelf, the small "Saved" note, and what a right-click was on.
//
// Drop shelf: start dragging a link or a picture (or drag one in from another window) and a
// small panel slides in at the right edge: "Save to Stello", your canvases, "New canvas".
// Drop on one to save it there. Nothing shows for other drags (text, files, the page's own
// drag and drop), and nothing shows inside Stello itself.
(() => {
  if (window.top !== window || window.__stelloShelf) return;
  window.__stelloShelf = true;
  const isStello = /^(https:\/\/stello\.arjunphlox\.workers\.dev|http:\/\/localhost:8787)$/.test(location.origin);

  const send = (msg) => browser.runtime.sendMessage(msg);
  const pageTitle = () => (document.title || "").trim();
  const shortName = (t) => {
    const s = String(t || "").split(/\s[|·–—-]\s/)[0].trim();
    return (s || location.hostname.replace(/^www\./, "")).slice(0, 40);
  };
  const IMG_EXT = /\.(jpe?g|png|webp|gif|avif|heic)(\?|#|$)/i;
  const abs = (u) => { try { return new URL(u, location.href).href; } catch { return ""; } };
  const isWeb = (u) => /^https?:\/\//i.test(u);
  // The picture a srcset or lazy loader really shows.
  const imgURL = (img) => abs(img.currentSrc || img.src || img.dataset.src || "");

  // ---------- UI root (its own styles, so pages can't restyle it) ----------
  let root, shadow;
  function ui() {
    if (shadow) return shadow;
    root = document.createElement("stello-shelf");
    root.style.cssText = "all: initial; position: fixed; inset: 0; pointer-events: none; z-index: 2147483647;";
    shadow = root.attachShadow({ mode: "closed" });
    shadow.innerHTML = `<style>${css()}</style><div class="shelf" role="list" aria-label="Save to Stello"></div><div class="note" role="status" aria-live="polite"></div>`;
    document.documentElement.appendChild(root);
    return shadow;
  }

  // ---------- The note (bottom centre) ----------
  let noteTimer = 0, pollTimer = 0;
  function note({ text, busy, error, done, id }) {
    const el = ui().querySelector(".note");
    clearTimeout(noteTimer); clearTimeout(pollTimer);
    el.className = "note is-on" + (busy ? " is-busy" : "") + (error ? " is-error" : "") + (done ? " is-done" : "");
    el.innerHTML = `<span class="mark"></span><span class="text"></span>`;
    el.querySelector(".text").textContent = text;
    if (id) poll(id, Date.now());
    else if (!busy) noteTimer = setTimeout(() => { el.className = "note"; }, error ? 4000 : 2600);
  }
  // The Mac app usually finishes within a few seconds; after 20 s, say it's on its way.
  function poll(id, started) {
    pollTimer = setTimeout(async () => {
      let r = null;
      try { r = await send({ stelloSave: "status", id }); } catch {}
      if (r && r.done) return note({ text: r.text, done: !/^Couldn/.test(r.text), error: /^Couldn/.test(r.text) });
      if (Date.now() - started > 20000) return note({ text: "Saved. Stello is still adding it.", done: true });
      poll(id, started);
    }, 600);
  }

  browser.runtime.onMessage.addListener((msg, _sender, reply) => {
    if (!msg || !msg.stello) return false;
    if (msg.stello === "toast") { note(msg); reply({ ok: true }); return false; }
    if (msg.stello === "context") { reply(context()); return false; }
    return false;
  });

  // ---------- Right-click: what was under the pointer, and links in a selection ----------
  let lastTarget = null;
  document.addEventListener("contextmenu", (e) => { lastTarget = e.target; }, true);
  function context() {
    const t = lastTarget && lastTarget.closest ? lastTarget : null;
    const a = t && t.closest("a[href]");
    const img = t && (t.closest("img") || (a && a.querySelector("img")));
    const out = {
      pageTitle: pageTitle(),
      linkText: a ? (a.getAttribute("aria-label") || a.textContent || "").trim().replace(/\s+/g, " ").slice(0, 200) : "",
      imageAlt: img ? (img.alt || "").trim().slice(0, 200) : "",
      selectionLinks: [],
    };
    const sel = window.getSelection();
    if (sel && !sel.isCollapsed && sel.rangeCount) {
      const seen = new Set();
      for (let i = 0; i < sel.rangeCount; i++) {
        const range = sel.getRangeAt(i);
        const box = range.commonAncestorContainer.nodeType === 1 ? range.commonAncestorContainer : range.commonAncestorContainer.parentElement;
        const scope = box.closest("a[href]") ? [box.closest("a[href]")] : [...box.querySelectorAll("a[href]")];
        for (const link of scope) {
          if (!sel.containsNode(link, true)) continue;
          const url = abs(link.getAttribute("href"));
          if (!isWeb(url) || seen.has(url) || url.split("#")[0] === location.href.split("#")[0]) continue;
          seen.add(url);
          out.selectionLinks.push({ kind: IMG_EXT.test(url) ? "image" : "link", url, title: (link.textContent || "").trim().replace(/\s+/g, " ").slice(0, 200) });
          if (out.selectionLinks.length >= 200) break;
        }
      }
    }
    return out;
  }

  // ---------- Drop shelf ----------
  if (isStello) return;
  let dragged = null;      // what a drag that started in this page carries
  let shown = false, hideTimer = 0, canvases = null;

  // A drag that starts here: a link, or a picture (alone or inside a link).
  document.addEventListener("dragstart", (e) => {
    dragged = null;
    const t = e.target && e.target.nodeType === 1 ? e.target : e.target && e.target.parentElement;
    if (!t || !t.closest) return;
    const img = t.closest("img");
    const a = t.closest("a[href]");
    if (img && imgURL(img) && isWeb(imgURL(img))) {
      dragged = { kind: "image", url: imgURL(img), page: location.href, title: (img.alt || "").trim() || pageTitle(), link: a ? abs(a.getAttribute("href")) : "" };
    } else if (a && isWeb(abs(a.getAttribute("href")))) {
      dragged = { kind: "link", url: abs(a.getAttribute("href")), title: (a.textContent || "").trim().replace(/\s+/g, " ").slice(0, 200) };
    }
    if (dragged) show();
  }, true);

  // A drag from another window or app that carries a web address.
  const carriesLink = (dt) => !!dt && [...(dt.types || [])].includes("text/uri-list");
  window.addEventListener("dragenter", (e) => {
    if (!dragged && carriesLink(e.dataTransfer)) show();
    if (shown) keep();
  }, true);
  window.addEventListener("dragover", () => { if (shown) keep(); }, true);
  // Left the window: hide soon unless the drag comes back.
  window.addEventListener("dragleave", (e) => { if (shown && !e.relatedTarget) hideSoon(250); }, true);
  window.addEventListener("dragend", () => { dragged = null; hideSoon(0); }, true);
  window.addEventListener("drop", () => { if (shown) hideSoon(400); }, true);

  function keep() { clearTimeout(hideTimer); }
  function hideSoon(ms) {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => {
      shown = false;
      const shelf = shadow && shadow.querySelector(".shelf");
      if (shelf) shelf.classList.remove("is-on");
    }, ms);
  }

  async function show() {
    keep();
    if (shown) return;
    shown = true;
    render(canvases || []);
    try { canvases = ((await send({ stelloSave: "canvases" })) || {}).canvases || []; } catch { canvases = canvases || []; }
    if (shown) render(canvases);
  }

  function render(list) {
    const shelf = ui().querySelector(".shelf");
    const targets = [
      { id: "", label: "Save to Stello", hint: "On its own" },
      ...list.slice(0, 5).map((c) => ({ id: c.id, label: c.name, hint: "" })),
      { id: "new", label: "New canvas", hint: shortName(pageTitle()) },
    ];
    shelf.innerHTML = `<div class="head"><span class="logo"></span>Drop to save</div>` + targets.map((t, i) => `
      ${i === 1 && list.length ? '<div class="group">Add to a canvas</div>' : ""}<div class="target${t.id === "new" ? " is-new" : ""}" role="listitem" data-id="${t.id}" style="--i:${i}">
        <span class="label"></span><span class="hint"></span>
      </div>`).join("");
    shelf.querySelectorAll(".target").forEach((el, i) => {
      el.querySelector(".label").textContent = targets[i].label;
      el.querySelector(".hint").textContent = targets[i].hint;
      el.addEventListener("dragenter", (e) => { e.preventDefault(); el.classList.add("is-over"); keep(); });
      el.addEventListener("dragover", (e) => { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; keep(); });
      el.addEventListener("dragleave", () => el.classList.remove("is-over"));
      el.addEventListener("drop", (e) => { e.preventDefault(); e.stopPropagation(); dropOn(targets[i], e.dataTransfer, el); });
    });
    requestAnimationFrame(() => shelf.classList.add("is-on"));
  }

  function entriesFrom(dt) {
    if (dragged) return [dragged];
    const raw = (dt.getData("text/uri-list") || dt.getData("text/plain") || "")
      .split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith("#") && isWeb(l));
    return [...new Set(raw)].slice(0, 200).map((url) => ({ kind: IMG_EXT.test(url) ? "image" : "link", url, title: "" }));
  }

  async function dropOn(target, dt, el) {
    const entries = entriesFrom(dt).map(({ link, ...e }) => e);
    dragged = null;
    el.classList.remove("is-over");
    if (!entries.length) { hideSoon(0); return note({ text: "Nothing to save in that", error: true }); }
    el.classList.add("is-picked");
    const canvas = target.id || null;
    const where = !canvas ? "" : canvas === "new" ? " to a new canvas" : ` to ${target.label}`;
    const what = entries.length > 1 ? ` ${entries.length} links` : "";
    note({ text: `Saving${what}${where}…`, busy: true });
    hideSoon(350);
    const name = shortName(pageTitle());
    let reply = null;
    try { reply = await send({ stelloSave: "save", entries, canvas, newName: name, groupName: name, from: "safari-drop" }); } catch {}
    if (!reply || reply.error) return note({ text: (reply && reply.error) || "Stello couldn't be reached", error: true });
    if (reply.app === "later") return note({ text: "Saved. It shows in Stello when you open the app.", done: true });
    note({ text: `Saving${what}${where}…`, busy: true, id: reply.id });
  }

  function css() { return `
    :host { all: initial; }
    * { box-sizing: border-box; }
    .shelf, .note { font: 14px/1.25 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; -webkit-font-smoothing: antialiased; color: #fff; }
    .shelf {
      position: fixed; top: 50%; right: 16px; width: 232px; padding: 8px;
      display: flex; flex-direction: column; gap: 4px;
      background: rgba(20, 20, 18, 0.82); backdrop-filter: blur(24px) saturate(1.4); -webkit-backdrop-filter: blur(24px) saturate(1.4);
      border: 1px solid rgba(255, 255, 255, 0.10); border-radius: 18px;
      box-shadow: 0 18px 50px rgba(0, 0, 0, 0.28), 0 2px 8px rgba(0, 0, 0, 0.18);
      transform: translate(calc(100% + 32px), -50%); opacity: 0;
      transition: transform 260ms cubic-bezier(.2, .9, .25, 1.05), opacity 180ms ease;
      pointer-events: none;
    }
    .shelf.is-on { transform: translate(0, -50%); opacity: 1; pointer-events: auto; }
    .head { display: flex; align-items: center; gap: 8px; padding: 6px 8px 8px; color: rgba(255, 255, 255, 0.6); font-size: 12px; letter-spacing: .01em; }
    .logo { width: 14px; height: 14px; background: currentColor; -webkit-mask: url("${browser.runtime.getURL("icon-32.png")}") center / contain no-repeat; mask: url("${browser.runtime.getURL("icon-32.png")}") center / contain no-repeat; }
    .target {
      min-height: 48px; padding: 8px 12px; border-radius: 12px;
      display: flex; flex-direction: column; justify-content: center; gap: 2px;
      background: rgba(255, 255, 255, 0.06); border: 1px solid transparent;
      transition: background 120ms ease, border-color 120ms ease, transform 120ms ease;
      animation: rise 240ms calc(var(--i) * 28ms) both cubic-bezier(.2, .9, .25, 1);
    }
    .target.is-new { background: transparent; border: 1px dashed rgba(255, 255, 255, 0.22); }
    .target.is-over { background: rgba(255, 255, 255, 0.18); border-color: rgba(255, 255, 255, 0.35); transform: scale(1.02); }
    .target.is-picked { background: rgba(255, 255, 255, 0.24); }
    .label { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .hint { font-size: 12px; color: rgba(255, 255, 255, 0.55); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .target * { pointer-events: none; }
    .hint:empty { display: none; }
    .group { padding: 10px 8px 2px; color: rgba(255, 255, 255, 0.55); font-size: 12px; }
    @keyframes rise { from { opacity: 0; transform: translateY(6px); } }
    .note {
      position: fixed; left: 50%; bottom: 28px; max-width: min(440px, calc(100vw - 32px));
      display: flex; align-items: center; gap: 10px; padding: 11px 16px 11px 14px;
      background: rgba(20, 20, 18, 0.86); backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px);
      border-radius: 999px; box-shadow: 0 10px 30px rgba(0, 0, 0, 0.25);
      transform: translate(-50%, 16px); opacity: 0; transition: transform 220ms cubic-bezier(.2, .9, .25, 1.05), opacity 160ms ease;
    }
    .note.is-on { transform: translate(-50%, 0); opacity: 1; }
    .mark { width: 16px; height: 16px; flex: none; border-radius: 50%; }
    .note.is-busy .mark { border: 2px solid rgba(255, 255, 255, 0.3); border-top-color: #fff; animation: spin 800ms linear infinite; }
    .note.is-done .mark { background: #fff; -webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cpath d='M3.5 8.5l3 3 6-7' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E") center / contain no-repeat; mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cpath d='M3.5 8.5l3 3 6-7' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E") center / contain no-repeat; }
    .note.is-error .mark { background: #ff9f6b; width: 8px; height: 8px; margin: 0 4px; }
    .text { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    @keyframes spin { to { transform: rotate(360deg); } }
    @media (prefers-reduced-motion: reduce) { .shelf, .note, .target { transition: none; animation: none; } }
  `; }
})();
