/* Stello canvas export: Figma, PDF, HTML, Claude Design, Markdown folder,
   JSON, Images. Everything runs in the browser from the canvas model that
   canvas.js hands over (cards with positions, group pills, links, notes), so
   nothing new is needed on the server. Zips are written uncompressed (store),
   which keeps this file small and is fine for images that are already
   compressed. */
(function () {
  'use strict';

  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const slugName = (s) => String(s || 'canvas').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60) || 'canvas';
  const abs = (p) => (p ? new URL(p, location.origin).href : '');
  const urlOf = (it) => it.source_url || '';
  const tagsOf = (it, cat) => (it.tags || []).filter(t => !cat || t.category === cat).map(t => t.tag);

  // ---------- Files ----------
  function download(name, data, type) {
    const blob = data instanceof Blob ? data : new Blob([data], { type: type || 'application/octet-stream' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob); a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 4000);
  }
  async function copyText(text) {
    try { await navigator.clipboard.writeText(text); return true; } catch { return false; }
  }

  // ---------- Zip (store only) ----------
  const CRC = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
  function crc32(u8) { let c = 0xFFFFFFFF; for (let i = 0; i < u8.length; i++) c = CRC[(c ^ u8[i]) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
  function zip(files) {
    const enc = new TextEncoder(), parts = [], central = [];
    let off = 0;
    files.forEach(f => {
      const name = enc.encode(f.name), data = typeof f.data === 'string' ? enc.encode(f.data) : f.data;
      const crc = crc32(data);
      const h = new DataView(new ArrayBuffer(30));
      h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint16(6, 0x0800, true); h.setUint16(8, 0, true);
      h.setUint32(14, crc, true); h.setUint32(18, data.length, true); h.setUint32(22, data.length, true); h.setUint16(26, name.length, true);
      parts.push(new Uint8Array(h.buffer), name, data);
      const c = new DataView(new ArrayBuffer(46));
      c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true);
      c.setUint32(16, crc, true); c.setUint32(20, data.length, true); c.setUint32(24, data.length, true); c.setUint16(28, name.length, true);
      c.setUint32(42, off, true);
      central.push(new Uint8Array(c.buffer), name);
      off += 30 + name.length + data.length;
    });
    const csize = central.reduce((s, p) => s + p.length, 0);
    const e = new DataView(new ArrayBuffer(22));
    e.setUint32(0, 0x06054b50, true); e.setUint16(8, files.length, true); e.setUint16(10, files.length, true);
    e.setUint32(12, csize, true); e.setUint32(16, off, true);
    return new Blob([...parts, ...central, new Uint8Array(e.buffer)], { type: 'application/zip' });
  }

  // ---------- Images ----------
  async function fetchBytes(path) {
    try { const r = await fetch(path, { credentials: 'same-origin' }); if (!r.ok) return null; return { bytes: new Uint8Array(await r.arrayBuffer()), type: r.headers.get('content-type') || '' }; } catch { return null; }
  }
  const extFor = (type, path) => /png/.test(type) ? 'png' : /webp/.test(type) ? 'webp' : /gif/.test(type) ? 'gif' : /jpe?g/.test(type) ? 'jpg' : ((String(path).match(/\.(png|webp|gif|jpe?g)(\?|$)/i) || [])[1] || 'jpg').toLowerCase();
  // A downscaled JPEG data URL, so an SVG or HTML file carries its own pictures.
  function dataUrl(path, maxW) {
    return new Promise((resolve) => {
      if (!path) return resolve(null);
      const im = new Image();
      im.crossOrigin = 'anonymous';
      im.onload = () => {
        try {
          const s = Math.min(1, maxW / im.naturalWidth), c = document.createElement('canvas');
          c.width = Math.max(1, Math.round(im.naturalWidth * s)); c.height = Math.max(1, Math.round(im.naturalHeight * s));
          c.getContext('2d').drawImage(im, 0, 0, c.width, c.height);
          resolve(c.toDataURL('image/jpeg', 0.82));
        } catch { resolve(null); }
      };
      im.onerror = () => resolve(null);
      im.src = path;
    });
  }
  async function pool(list, n, fn) {
    const out = new Array(list.length); let i = 0;
    await Promise.all(new Array(Math.min(n, list.length)).fill(0).map(async () => { while (i < list.length) { const j = i++; out[j] = await fn(list[j], j); } }));
    return out;
  }

  // ---------- Markdown ----------
  function itemMd(c) {
    const it = c.item, fm = ['---', `title: ${JSON.stringify(it.title || it.domain || c.slug)}`];
    if (urlOf(it)) fm.push(`url: ${urlOf(it)}`);
    if (it.domain) fm.push(`domain: ${it.domain}`);
    if (it.kind) fm.push(`kind: ${it.kind}`);
    if (it.added_at) fm.push(`saved: ${String(it.added_at).slice(0, 10)}`);
    if (c.state) fm.push(`state: ${c.state}`);
    const tags = tagsOf(it).slice(0, 30);
    if (tags.length) fm.push(`tags: [${tags.map(t => JSON.stringify(t)).join(', ')}]`);
    if (c.groups.length) fm.push(`groups: [${c.groups.map(g => JSON.stringify(g)).join(', ')}]`);
    fm.push(`canvas_position: { x: ${Math.round(c.x)}, y: ${Math.round(c.y)} }`, '---', '');
    const body = [`# ${it.title || it.domain || c.slug}`, ''];
    if (c.imageFile) body.push(`![cover](../images/${c.imageFile})`, '');
    if (c.reason) body.push(`> ${c.reason}`, '');
    if (it.summary) body.push(it.summary, '');
    (it.snippets || []).slice(0, 5).forEach(sn => { const t = typeof sn === 'string' ? sn : sn && sn.text; if (t) body.push(`> ${t}`, ''); });
    return fm.join('\n') + body.join('\n');
  }
  function overviewMd(m) {
    const L = [`# ${m.name}`, '', `${m.cards.length} items · exported from Stello ${new Date().toISOString().slice(0, 10)}`, '', 'In this folder: `items/` (one Markdown file per item), `images/` (covers), `canvas.json` (the canvas and item data).', ''];
    if (m.groups.length) {
      L.push('## Groups', '');
      m.groups.forEach(g => { L.push(`### ${g.pills.join(' · ')}`, ''); g.slugs.forEach(s => { const c = m.bySlug.get(s); if (c) L.push(`- [${c.item.title || c.item.domain || s}](items/${c.file})`); }); L.push(''); });
    }
    const loose = m.cards.filter(c => !c.groups.length);
    if (loose.length) { L.push('## Not in a group', ''); loose.forEach(c => L.push(`- [${c.item.title || c.item.domain || c.slug}](items/${c.file})`)); L.push(''); }
    if (m.links.length) {
      L.push('## Links', '');
      m.links.forEach(l => L.push(`- ${m.label(l.a)} → ${m.label(l.b)} (${l.kind}${l.label ? ': ' + l.label : ''})`));
      L.push('');
    }
    if (m.notes.length) { L.push('## Notes', ''); m.notes.forEach(n => L.push(`- **${n.kind}**: ${n.text || ''}`)); L.push(''); }
    return L.join('\n');
  }

  // ---------- HTML / SVG ----------
  // One static page: the canvas at its true layout, scaled to fit the width.
  function pageHTML(m, img, opts) {
    const P = 60, b = m.bounds, Wd = b.w + P * 2, Ht = b.h + P * 2 + 40;
    const x = (v) => v - b.x + P, y = (v) => v - b.y + P + 40;
    const tints = m.groups.map(g => `<div class="t" style="left:${x(g.x)}px;top:${y(g.y)}px;width:${g.w}px;height:${g.h}px;background:${g.tint}"></div><div class="pl" style="left:${x(g.x)}px;top:${y(g.y) - 34}px">${g.pills.map((p, i) => `<span class="p${i === 0 && g.user ? ' n' : ''}">${esc(p)}</span>`).join('')}</div>`).join('');
    const cards = m.cards.map(c => `<a class="c" href="${esc(urlOf(c.item))}" style="left:${x(c.x)}px;top:${y(c.y)}px;width:${c.w}px;height:${c.h}px">${img(c) ? `<img src="${esc(img(c))}" alt="">` : `<span class="tt">${esc(c.item.title || c.item.domain || '')}</span>`}<span class="d">${esc(c.item.domain || '')}</span>${c.state ? `<span class="s ${c.state}">${c.state === 'use' ? 'Use' : 'Rejected'}</span>` : ''}</a>`).join('');
    const notes = m.notes.map(n => `<div class="nt" style="left:${x(n.x || 0)}px;top:${y(n.y || 0)}px"><small>${esc(n.kind)}</small>${esc(n.text || '')}</div>`).join('');
    const lines = m.links.map(l => { const a = m.centre(l.a), bb = m.centre(l.b); if (!a || !bb) return ''; return `<line x1="${x(a.x)}" y1="${y(a.y)}" x2="${x(bb.x)}" y2="${y(bb.y)}" stroke="${l.color}" stroke-width="2.5" stroke-dasharray="${l.kind === 'related' ? '4 6' : ''}"/>`; }).join('');
    return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(m.name)}</title><style>
*{box-sizing:border-box}body{margin:0;background:#111;color:#eee;font:14px/1.3 -apple-system,BlinkMacSystemFont,Inter,system-ui,sans-serif}
.wrap{width:${Wd}px;height:${Ht}px;position:relative;transform-origin:0 0}
h1{position:absolute;left:${P}px;top:16px;margin:0;font-size:22px;font-weight:400}
.t{position:absolute;border-radius:22px}.pl{position:absolute;display:flex;gap:4px}
.p{height:26px;line-height:24px;padding:0 11px;border-radius:13px;border:1px solid #333;background:#1c1c1c;color:#bbb;font-size:13px;white-space:nowrap}.p.n{background:#ffc53d;border-color:#ffc53d;color:#222}
.c{position:absolute;border-radius:10px;overflow:hidden;background:#262626;color:inherit;text-decoration:none}.c img{width:100%;height:100%;object-fit:cover;display:block}
.c .tt{position:absolute;left:12px;top:12px;right:12px}.c .d{position:absolute;right:8px;bottom:8px;height:22px;line-height:22px;padding:0 9px;border-radius:11px;background:rgba(20,20,18,.78);font-size:12px}
.c .s{position:absolute;left:8px;top:8px;padding:2px 8px;border-radius:6px;font-size:11px;background:#2b8a3e}.c .s.rejected{background:#e03131}
.nt{position:absolute;width:220px;padding:10px 12px;border-radius:10px;background:#ffe58f;color:#222}.nt small{display:block;text-transform:uppercase;letter-spacing:.1em;font-size:10px;opacity:.7;margin-bottom:4px}
svg{position:absolute;left:0;top:0;pointer-events:none}
@media print{body{background:#fff}.wrap{transform:scale(var(--ps))}}
${opts && opts.print ? `@page{size:${Wd > Ht ? 'landscape' : 'portrait'};margin:10mm}` : ''}
</style></head><body><div class="wrap" id="w"><h1>${esc(m.name)}</h1>${tints}<svg width="${Wd}" height="${Ht}">${lines}</svg>${cards}${notes}</div>
<script>(function(){var w=document.getElementById('w');function f(){var s=Math.min(1,(innerWidth-0)/${Wd});w.style.transform='scale('+s+')';document.body.style.height=(${Ht}*s)+'px';w.style.setProperty('--ps',s)}f();addEventListener('resize',f)})();</script>
</body></html>`;
  }
  function svgDoc(m, img) {
    const P = 60, b = m.bounds, Wd = b.w + P * 2, Ht = b.h + P * 2 + 40;
    const x = (v) => Math.round(v - b.x + P), y = (v) => Math.round(v - b.y + P + 40);
    const font = 'font-family="Inter, system-ui, sans-serif"';
    let s = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${Wd}" height="${Ht}" viewBox="0 0 ${Wd} ${Ht}">`;
    s += `<rect width="${Wd}" height="${Ht}" fill="#111111"/><text x="${P}" y="38" ${font} font-size="22" fill="#eeeeee">${esc(m.name)}</text>`;
    m.groups.forEach(g => {
      s += `<g><rect x="${x(g.x)}" y="${y(g.y)}" width="${g.w}" height="${g.h}" rx="22" fill="${g.tint}"/>`;
      let px = x(g.x);
      g.pills.forEach((p, i) => { const w = Math.round(22 + p.length * 7.2); const name = i === 0 && g.user; s += `<rect x="${px}" y="${y(g.y) - 34}" width="${w}" height="26" rx="13" fill="${name ? '#ffc53d' : '#1c1c1c'}" stroke="${name ? '#ffc53d' : '#333333'}"/><text x="${px + 11}" y="${y(g.y) - 16}" ${font} font-size="13" fill="${name ? '#222222' : '#bbbbbb'}">${esc(p)}</text>`; px += w + 4; });
      s += '</g>';
    });
    m.links.forEach(l => { const a = m.centre(l.a), bb = m.centre(l.b); if (a && bb) s += `<line x1="${x(a.x)}" y1="${y(a.y)}" x2="${x(bb.x)}" y2="${y(bb.y)}" stroke="${l.color}" stroke-width="2.5"${l.kind === 'related' ? ' stroke-dasharray="4 6"' : ''}/>`; });
    m.cards.forEach((c, i) => {
      const id = 'c' + i;
      s += `<g><clipPath id="${id}"><rect x="${x(c.x)}" y="${y(c.y)}" width="${c.w}" height="${c.h}" rx="10"/></clipPath><rect x="${x(c.x)}" y="${y(c.y)}" width="${c.w}" height="${c.h}" rx="10" fill="#262626"/>`;
      if (img(c)) s += `<image clip-path="url(#${id})" x="${x(c.x)}" y="${y(c.y)}" width="${c.w}" height="${c.h}" preserveAspectRatio="xMidYMid slice" href="${img(c)}" xlink:href="${img(c)}"/>`;
      else s += `<text x="${x(c.x) + 12}" y="${y(c.y) + 26}" ${font} font-size="14" fill="#eeeeee">${esc((c.item.title || c.item.domain || '').slice(0, 34))}</text>`;
      const d = c.item.domain || ''; if (d) { const w = Math.round(18 + d.length * 6.6); s += `<rect x="${x(c.x) + c.w - w - 8}" y="${y(c.y) + c.h - 30}" width="${w}" height="22" rx="11" fill="#141412" fill-opacity="0.78"/><text x="${x(c.x) + c.w - w - 8 + 9}" y="${y(c.y) + c.h - 15}" ${font} font-size="12" fill="#eeeeee">${esc(d)}</text>`; }
      s += '</g>';
    });
    m.notes.forEach(n => { s += `<g><rect x="${x(n.x || 0)}" y="${y(n.y || 0)}" width="220" height="70" rx="10" fill="#ffe58f"/><text x="${x(n.x || 0) + 12}" y="${y(n.y || 0) + 24}" ${font} font-size="10" fill="#555555">${esc(String(n.kind).toUpperCase())}</text><text x="${x(n.x || 0) + 12}" y="${y(n.y || 0) + 46}" ${font} font-size="14" fill="#222222">${esc((n.text || '').slice(0, 30))}</text></g>`; });
    return s + '</svg>';
  }
  function designBrief(m) {
    const L = [`# ${m.name}`, '', 'A Stello canvas: saved references arranged and grouped by hand. Use it as the reference board for a design.', ''];
    m.groups.forEach(g => {
      L.push(`## ${g.pills.join(' · ')}`, '');
      g.slugs.forEach(s => { const c = m.bySlug.get(s); if (!c) return; const it = c.item; L.push(`- ${it.title || it.domain}${urlOf(it) ? ` (${urlOf(it)})` : ''}${c.image ? `\n  image: ${abs(c.image)}` : ''}${tagsOf(it, 'style').length ? `\n  style: ${tagsOf(it, 'style').slice(0, 5).join(', ')}` : ''}${tagsOf(it, 'color').length ? `\n  colours: ${tagsOf(it, 'color').slice(0, 4).join(', ')}` : ''}${c.state ? `\n  marked: ${c.state}${c.reason ? ' (' + c.reason + ')' : ''}` : ''}`); });
      L.push('');
    });
    const loose = m.cards.filter(c => !c.groups.length);
    if (loose.length) { L.push('## Also on the canvas', ''); loose.forEach(c => L.push(`- ${c.item.title || c.item.domain}${urlOf(c.item) ? ` (${urlOf(c.item)})` : ''}${c.image ? `\n  image: ${abs(c.image)}` : ''}`)); L.push(''); }
    if (m.links.length) { L.push('## How they relate', ''); m.links.forEach(l => L.push(`- ${m.label(l.a)} → ${m.label(l.b)}: ${l.kind}${l.label ? ', ' + l.label : ''}`)); L.push(''); }
    if (m.notes.length) { L.push('## Questions and notes', ''); m.notes.forEach(n => L.push(`- ${n.text || ''}`)); }
    return L.join('\n');
  }

  // ---------- Formats ----------
  const FORMATS = {
    figma: { label: 'Figma', hint: 'Copy as SVG, paste with ⌘V' },
    pdf: { label: 'PDF', hint: 'Print, then Save as PDF' },
    html: { label: 'HTML', hint: 'One web page' },
    claude: { label: 'Claude Design', hint: 'Copy a design brief' },
    package: { label: 'Package', hint: 'Markdown, JSON, images' },
  };
  async function run(fmt, m, toast) {
    const base = slugName(m.name);
    const json = () => JSON.stringify({ format: 'stello-canvas', version: 2, exported_at: new Date().toISOString(), canvas: m.doc, items: m.cards.map(c => ({ slug: c.slug, title: c.item.title, url: urlOf(c.item), domain: c.item.domain, kind: c.item.kind, image: c.image ? abs(c.image) : null, tags: c.item.tags, summary: c.item.summary, x: c.x, y: c.y, w: c.w, h: c.h, groups: c.groups, file: c.file ? 'items/' + c.file : null, image_file: c.imageFile ? 'images/' + c.imageFile : null })) }, null, 2);
    if (fmt === 'package') {
      toast(`Preparing ${m.cards.length} items…`);
      const files = [];
      const imgs = await pool(m.cards, 6, async (c, i) => { if (!c.image) return null; const r = await fetchBytes(c.image); if (!r) return null; const name = `${String(i + 1).padStart(3, '0')}-${slugName(c.item.title || c.item.domain || c.slug).slice(0, 40)}.${extFor(r.type, c.image)}`; c.imageFile = name; return { name, bytes: r.bytes }; });
      m.cards.forEach((c, i) => { c.file = `${String(i + 1).padStart(3, '0')}-${slugName(c.item.title || c.item.domain || c.slug).slice(0, 50)}.md`; });
      files.push({ name: `${base}/README.md`, data: overviewMd(m) });
      m.cards.forEach(c => files.push({ name: `${base}/items/${c.file}`, data: itemMd(c) }));
      files.push({ name: `${base}/canvas.json`, data: json() });
      imgs.forEach(f => f && files.push({ name: `${base}/images/${f.name}`, data: f.bytes }));
      download(base + '.zip', zip(files));
      const n = imgs.filter(Boolean).length;
      return toast(`Package downloaded: ${m.cards.length} items, ${n} image${n === 1 ? '' : 's'}`);
    }
    if (fmt === 'html' || fmt === 'pdf' || fmt === 'figma') {
      toast('Preparing images…');
      const urls = await pool(m.cards, 6, c => dataUrl(c.image, fmt === 'figma' ? 560 : 820));
      const map = new Map(m.cards.map((c, i) => [c, urls[i]]));
      const img = (c) => map.get(c) || (fmt === 'figma' ? null : (c.image ? abs(c.image) : null));
      if (fmt === 'html') { download(base + '.html', pageHTML(m, img), 'text/html'); return toast('HTML downloaded'); }
      if (fmt === 'figma') {
        const svg = svgDoc(m, img);
        // Figma turns pasted SVG markup into editable layers, pictures included.
        const ok = await copyText(svg);
        download(base + '.svg', svg, 'image/svg+xml');
        return toast(ok ? 'Copied for Figma: paste with ⌘V (an .svg was saved too)' : 'Saved an .svg: drag it into Figma');
      }
      // PDF: the same page in a hidden frame, through the print dialog.
      const fr = document.createElement('iframe');
      fr.style.cssText = 'position:fixed;right:0;bottom:0;width:1px;height:1px;border:0;opacity:0;';
      document.body.appendChild(fr);
      fr.srcdoc = pageHTML(m, img, { print: true });
      fr.onload = () => { setTimeout(() => { try { fr.contentWindow.focus(); fr.contentWindow.print(); } catch { toast('Printing was blocked'); } setTimeout(() => fr.remove(), 60000); }, 300); };
      return toast('Choose Save as PDF in the print dialog');
    }
    if (fmt === 'claude') {
      const ok = await copyText(designBrief(m));
      if (!ok) download(base + '-brief.md', designBrief(m), 'text/markdown');
      return toast(ok ? 'Copied: paste it into Claude Design as the brief' : 'Brief downloaded: attach it in Claude Design');
    }
  }

  window.StelloCanvasExport = { FORMATS, run, zip, crc32 };
})();
