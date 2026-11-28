const out = document.getElementById("out");
const ask = (request) => browser.runtime.sendMessage({ stelloFolder: true, ...request });

function section(title) {
  const h = document.createElement("h2"); h.textContent = title; out.append(h);
  const pre = document.createElement("pre"); out.append(pre); return pre;
}
function line(pre, ok, text) {
  const span = document.createElement("span");
  span.className = ok ? "ok" : "bad";
  span.textContent = (ok ? "✓ " : "✗ ") + text + "\n";
  pre.append(span);
}

async function tryRoute(route) {
  const pre = section(route === "direct" ? "1. Extension reads the folder itself" : "2. Extension asks the running Stello app");
  const t0 = performance.now();
  const list = await ask({ route, cmd: "list" });
  const ms = Math.round(performance.now() - t0);
  if (list.error || !list.folders) { line(pre, false, `List: ${list.error || "no answer"}`); return; }
  if (list.resolveErrors) line(pre, false, `Bookmarks: ${list.resolveErrors.join("; ")}`);
  if (!list.folders.length) { line(pre, false, "No folders came back"); return; }
  for (const f of list.folders) {
    line(pre, !f.error && f.itemCount > 0, `${f.name}: ${f.itemCount} items listed in ${ms} ms${f.error ? ` (${f.error})` : ""}`);
    if (f.firstItems.length) {
      const r0 = performance.now();
      const read = await ask({ route, cmd: "read", folder: f.id, path: f.firstItems[0] });
      const rms = Math.round(performance.now() - r0);
      if (read.error) line(pre, false, `Read ${f.firstItems[0]}: ${read.error}`);
      else {
        line(pre, true, `Read ${f.firstItems[0]} (${read.bytes} bytes) in ${rms} ms`);
        pre.append(document.createTextNode(read.text.slice(0, 600) + "\n…\n"));
      }
    }
    if (f.firstImages.length) {
      const i0 = performance.now();
      const img = await ask({ route, cmd: "image", folder: f.id, path: f.firstImages[0] });
      const ims = Math.round(performance.now() - i0);
      if (img.error) line(pre, false, `Picture ${f.firstImages[0]}: ${img.error}`);
      else {
        line(pre, true, `Picture ${f.firstImages[0]} (${Math.round(img.bytes / 1024)} KB) in ${ims} ms`);
        const el = document.createElement("img"); el.src = `data:${img.type};base64,${img.base64}`; pre.append(el);
      }
    }
  }
}

async function run() {
  out.textContent = "";
  for (const route of ["direct", "relay"]) {
    try { await tryRoute(route); } catch (e) { line(section(route), false, String(e)); }
  }
}
document.getElementById("run").addEventListener("click", run);
run();
