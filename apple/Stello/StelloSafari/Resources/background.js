// Stello Safari extension.
// 1. Folder test: passes folder requests from the Stello web page to the native handler.
//    Messages: { stelloFolder: true, route: "direct" | "relay", cmd: "list" | "read" | "image", folder?, path? }
// 2. Saves: the right-click menu (Mac), the drop shelf (shelf.js) and the popup send links and
//    pictures to Stello, on their own or onto a canvas. The app does the saving.
const native = (msg) => browser.runtime.sendNativeMessage("com.arjunphlox.Stello", msg);

// ---------- Canvases ----------
// The app shares its canvases (open one first). Ones you used from Safari lately go first.
let canvases = [];
async function recentIDs() {
  try { return (await browser.storage.local.get("recent")).recent || []; } catch { return []; }
}
async function useCanvas(id) {
  if (!id || id === "new") return;
  const recent = (await recentIDs()).filter((x) => x !== id);
  recent.unshift(id);
  try { await browser.storage.local.set({ recent: recent.slice(0, 8) }); } catch {}
}
async function loadCanvases() {
  try {
    const r = await native({ cmd: "canvases" });
    const list = (r && r.canvases) || [];
    const recent = await recentIDs();
    const rank = (c) => { const i = recent.indexOf(c.id); return i < 0 ? 100 + list.indexOf(c) : i; };
    canvases = [...list].sort((a, b) => rank(a) - rank(b));
  } catch { /* the app hasn't shared any yet */ }
  buildMenus();
  return canvases;
}

// ---------- Saving ----------
const shortName = (title, url) => {
  let t = String(title || "").split(/\s[|·–—-]\s/)[0].trim();
  if (!t) { try { t = new URL(url).hostname.replace(/^www\./, ""); } catch { t = ""; } }
  return t.slice(0, 40) || "From Safari";
};

async function save({ entries, canvas, newName, groupName, from }) {
  const reply = await native({ cmd: "save", entries, canvas: canvas || null, newName, groupName, from });
  if (reply && reply.queued) useCanvas(canvas);
  return reply;
}

// ---------- Right-click menu (Mac Safari; iPhone and iPad have no menu, they use Share) ----------
const MENU = browser.contextMenus || browser.menus;
let building = Promise.resolve();
function buildMenus() {
  if (!MENU) return;
  building = building.then(async () => {
    await MENU.removeAll();
    const contexts = ["link", "image", "page", "selection"];
    MENU.create({ id: "stello", title: "Stello", contexts });
    MENU.create({ id: "save", parentId: "stello", title: "Save to Stello", contexts });
    MENU.create({ id: "sep", parentId: "stello", type: "separator", contexts });
    for (const c of canvases.slice(0, 6)) {
      MENU.create({ id: "canvas:" + c.id, parentId: "stello", title: "Add to " + c.name, contexts });
    }
    MENU.create({ id: "new", parentId: "stello", title: "Add to a new canvas", contexts });
  }).catch(() => {});
}

// What the click was on: a picture, a link, links in a selection, or the page.
async function entriesFor(info, tab) {
  let ctx = {};
  try { ctx = (await browser.tabs.sendMessage(tab.id, { stello: "context" })) || {}; } catch {}
  const page = info.pageUrl || tab.url;
  const title = ctx.pageTitle || tab.title || "";
  if (info.mediaType === "image" && info.srcUrl) {
    return [{ kind: "image", url: info.srcUrl, page, title: ctx.imageAlt || title }];
  }
  if (info.linkUrl) return [{ kind: "link", url: info.linkUrl, title: ctx.linkText || "" }];
  if (info.selectionText && ctx.selectionLinks && ctx.selectionLinks.length) {
    return ctx.selectionLinks.map((l) => ({ kind: l.kind, url: l.url, page, title: l.title || "" }));
  }
  return [{ kind: "link", url: page, title }];
}

async function toast(tab, msg) {
  try { await browser.tabs.sendMessage(tab.id, { stello: "toast", ...msg }); } catch {}
}

if (MENU) {
  MENU.onClicked.addListener(async (info, tab) => {
    const id = String(info.menuItemId);
    if (!tab || !(id === "save" || id === "new" || id.startsWith("canvas:"))) return;
    const entries = (await entriesFor(info, tab)).filter((e) => /^https?:/.test(e.url));
    if (!entries.length) return toast(tab, { text: "Nothing to save here", error: true });
    const canvas = id === "save" ? null : id === "new" ? "new" : id.slice(7);
    const name = canvas && canvas !== "new" ? (canvases.find((c) => c.id === canvas) || {}).name : null;
    const groupName = shortName(tab.title, tab.url);
    await toast(tab, { text: savingText(entries.length, canvas, name), busy: true });
    try {
      const reply = await save({ entries, canvas, newName: groupName, groupName, from: "safari-menu" });
      await toast(tab, afterSave(reply, entries.length, canvas, name));
    } catch (e) {
      await toast(tab, { text: "Stello couldn't be reached", error: true });
    }
  });
}

function savingText(n, canvas, name) {
  const what = n > 1 ? `${n} links` : "";
  if (!canvas) return n > 1 ? `Saving ${what}…` : "Saving…";
  if (canvas === "new") return n > 1 ? `Saving ${what} to a new canvas…` : "Saving to a new canvas…";
  return n > 1 ? `Saving ${what} to ${name || "the canvas"}…` : `Saving to ${name || "the canvas"}…`;
}
function afterSave(reply, n, canvas, name) {
  if (!reply || reply.error) return { text: (reply && reply.error) || "Couldn't save", error: true };
  // iPhone and iPad: the app saves it when it next opens.
  if (reply.app === "later") return { text: "Saved. It shows in Stello when you open the app.", done: true };
  return { text: savingText(n, canvas, name), busy: true, id: reply.id };
}

// ---------- Messages from the page (shelf.js) and the popup ----------
browser.runtime.onMessage.addListener((msg, _sender, reply) => {
  if (!msg) return false;
  if (msg.stelloFolder === true) {
    const { stelloFolder, ...request } = msg;
    native(request).then(reply, (e) => reply({ error: String((e && e.message) || e) }));
    return true;
  }
  if (msg.stelloSave === "canvases") {
    loadCanvases().then((list) => reply({ canvases: list }));
    return true;
  }
  if (msg.stelloSave === "save") {
    save(msg).then(reply, (e) => reply({ error: "Stello couldn't be reached" }));
    return true;
  }
  if (msg.stelloSave === "status") {
    native({ cmd: "status", id: msg.id }).then(
      (r) => { if (r && r.done) { useCanvas(r.canvas); loadCanvases(); } reply(r); },
      () => reply({ done: false }),
    );
    return true;
  }
  return false;
});

loadCanvases();
