// Toolbar popup: save this page, or every tab in this window, to Stello or onto a canvas.
// Links dragged onto a row are saved there too.
const $ = (s) => document.querySelector(s);
const send = (msg) => browser.runtime.sendMessage(msg);
const isWeb = (u) => /^https?:\/\//i.test(u || "");
const host = (u) => { try { return new URL(u).hostname.replace(/^www\./, ""); } catch { return ""; } };
const shortName = (title, url) => (String(title || "").split(/\s[|·–—-]\s/)[0].trim() || host(url)).slice(0, 40) || "From Safari";

let scope = "page";
let tab = null, tabs = [];

function pageEntries() {
  if (scope === "tabs") return tabs.filter((t) => isWeb(t.url)).map((t) => ({ kind: "link", url: t.url, title: t.title || "" }));
  return tab && isWeb(tab.url) ? [{ kind: "link", url: tab.url, title: tab.title || "" }] : [];
}

function describe() {
  const n = pageEntries().length;
  if (scope === "tabs") {
    $(".title").textContent = `${n} ${n === 1 ? "tab" : "tabs"} in this window`;
    $(".sub").textContent = [...new Set(tabs.filter((t) => isWeb(t.url)).map((t) => host(t.url)))].slice(0, 4).join(", ");
  } else {
    $(".title").textContent = (tab && tab.title) || "This page";
    $(".sub").textContent = tab ? host(tab.url) : "";
  }
}

function targetsHTML(canvases) {
  const rows = [
    `<li><button class="is-main" data-id=""><span class="label">Save to Stello</span><span class="hint">On its own</span></button></li>`,
  ];
  if (canvases.length) rows.push(`<li class="group">Add to a canvas</li>`);
  for (const c of canvases.slice(0, 6)) rows.push(`<li><button data-id="${c.id}"><span class="label"></span></button></li>`);
  rows.push(`<li><button class="is-new" data-id="new"><span class="label">New canvas</span><span class="hint">Name it</span></button></li>`);
  return rows.join("");
}

function renderTargets(canvases) {
  const ul = $(".targets");
  ul.innerHTML = targetsHTML(canvases);
  ul.querySelectorAll("button[data-id]").forEach((b) => {
    const c = canvases.find((x) => x.id === b.dataset.id);
    if (c) b.querySelector(".label").textContent = c.name;
    b.addEventListener("click", () => pick(b.dataset.id, c ? c.name : ""));
    // Links dragged onto a row from a page or another app.
    b.addEventListener("dragover", (e) => { e.preventDefault(); b.classList.add("is-over"); });
    b.addEventListener("dragleave", () => b.classList.remove("is-over"));
    b.addEventListener("drop", (e) => {
      e.preventDefault();
      b.classList.remove("is-over");
      const urls = (e.dataTransfer.getData("text/uri-list") || e.dataTransfer.getData("text/plain") || "")
        .split(/\r?\n/).map((l) => l.trim()).filter((l) => isWeb(l));
      if (!urls.length) return;
      const entries = [...new Set(urls)].map((url) => ({ kind: /\.(jpe?g|png|webp|gif|avif)(\?|#|$)/i.test(url) ? "image" : "link", url, title: "" }));
      const id = b.dataset.id;
      save(entries, id === "new" ? "new" : id || null, c ? c.name : "", shortName(tab && tab.title, tab && tab.url));
    });
  });
}

function pick(id, name) {
  if (id === "new") {
    const form = $(".name");
    form.hidden = false;
    const input = form.querySelector("input");
    input.value = shortName(scope === "tabs" ? "" : tab && tab.title, tab && tab.url);
    input.focus();
    input.select();
    return;
  }
  save(pageEntries(), id || null, name);
}

$(".name").addEventListener("submit", (e) => {
  e.preventDefault();
  const name = $(".name input").value.trim() || "Untitled canvas";
  save(pageEntries(), "new", name, name);
});

function result(text, state) {
  const r = $(".result");
  r.hidden = false;
  r.className = "result is-" + state;
  r.querySelector(".text").textContent = text;
}

async function save(entries, canvas, name, newName) {
  if (!entries.length) return result("Nothing to save on this page", "error");
  $(".targets").hidden = true; $(".name").hidden = true; $(".switch").hidden = true;
  const n = entries.length;
  const where = !canvas ? "" : canvas === "new" ? ` to ${newName}` : ` to ${name}`;
  result(`Saving${n > 1 ? ` ${n} links` : ""}${where}…`, "busy");
  const groupName = scope === "tabs" ? (newName || "Tabs from Safari") : shortName(tab && tab.title, tab && tab.url);
  let reply = null;
  try {
    reply = await send({ stelloSave: "save", entries, canvas, newName: newName || groupName, groupName, from: "safari-popup" });
  } catch {}
  if (!reply || reply.error) return result((reply && reply.error) || "Stello couldn't be reached", "error");
  if (reply.app === "later") { result("Saved. It shows in Stello when you open the app.", "done"); return setTimeout(() => window.close(), 1800); }
  const started = Date.now();
  const check = async () => {
    let r = null;
    try { r = await send({ stelloSave: "status", id: reply.id }); } catch {}
    if (r && r.done) { result(r.text, /^Couldn/.test(r.text) ? "error" : "done"); return setTimeout(() => window.close(), 1400); }
    if (Date.now() - started > 20000) { result("Saved. Stello is still adding it.", "done"); return setTimeout(() => window.close(), 1800); }
    setTimeout(check, 600);
  };
  check();
}

document.querySelectorAll(".switch button").forEach((b) => b.addEventListener("click", () => {
  scope = b.dataset.scope;
  document.querySelectorAll(".switch button").forEach((x) => x.setAttribute("aria-selected", String(x === b)));
  describe();
}));

$(".test").addEventListener("click", async () => {
  await browser.tabs.create({ url: browser.runtime.getURL("test.html") });
  window.close();
});

(async () => {
  try {
    [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    tabs = await browser.tabs.query({ currentWindow: true });
  } catch {}
  const web = tabs.filter((t) => isWeb(t.url)).length;
  if (web > 1) {
    $(".switch").hidden = false;
    $('.switch [data-scope="tabs"]').textContent = `All ${web} tabs`;
  }
  describe();
  renderTargets([]);
  let canvases = [];
  try { canvases = ((await send({ stelloSave: "canvases" })) || {}).canvases || []; } catch {}
  renderTargets(canvases);
})();
