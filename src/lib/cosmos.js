/**
 * Reader for the Cosmos notes (exports of cosmos.so collections, kept in
 * iCloud Drive/Stello/Cosmos). Pure: text in, entries out.
 *
 * Three shapes appear:
 *   tables  "| Item | Source URL |", "| Item | Source |" or "| # | Title | URL |", bare or [md](links),
 *           sometimes scheme-less, sometimes "[View Image](images/x.webp)" instead of a URL
 *   cards   "## 1. Title" / "### 1. Title" with an image embed, "> caption",
 *           **Type:**, **Tags:** `a`, `b`, and **Source:** [url](url) or [Source](url)
 *   bare cards with only a heading and a type (skipped: nothing to keep)
 * Captions mark names as <n>Name</n>; the tags are dropped, the names kept as text.
 *
 * Entry: { collection, title, url|null, image|null (path relative to the note), caption|null, tags: [] }
 */

const stripN = (s) => String(s || '').replace(/<\/?n>/g, '').replace(/&#x27;|&#39;/g, "'").replace(/&amp;/g, '&').replace(/&quot;/g, '"').trim();

/** A table cell or link target → an absolute http(s) URL, or null. */
export function cellURL(cell) {
  let s = String(cell || '').trim();
  const md = /\[[^\]]*\]\(([^)\s]+)\)/.exec(s);
  if (md) s = md[1];
  if (!s || /\s/.test(s)) return null;
  if (/^https?:\/\//i.test(s)) return s;
  // Scheme-less "rwt.io/typography-tips/…": a host with a dot, then a path or nothing.
  if (/^[a-z0-9-]+(\.[a-z0-9-]+)+(\/|$)/i.test(s)) return `https://${s}`;
  return null;
}

const imageIn = (s) => {
  const m = /!\[[^\]]*\]\(([^)]+)\)/.exec(s) || /\[View Image\]\(([^)]+)\)/i.exec(s);
  return m && !/^https?:/i.test(m[1]) ? m[1].trim() : null;
};

/** Cells of a table row; an escaped "\\|" inside a cell is text, not a divider. */
function splitRow(line) {
  return line.trim().replace(/^\|/, '').replace(/(?<!\\)\|$/, '')
    .split(/(?<!\\)\|/).map((c) => c.replace(/\\\|/g, '|').trim());
}
const URL_HEADS = ['source url', 'url', 'source', 'link'];

export function parseNote(text, collection) {
  const out = [];
  const lines = String(text).split(/\r?\n/);

  // Tables.
  let cols = null;
  for (const line of lines) {
    if (!line.trim().startsWith('|')) { cols = null; continue; }
    const cells = splitRow(line);
    if (cells.every((c) => /^:?-{2,}:?$/.test(c) || c === '')) continue; // separator
    const lower = cells.map((c) => c.toLowerCase());
    if (!cols && lower.some((c) => URL_HEADS.includes(c))) {
      cols = { title: lower.findIndex((c) => c === 'item' || c === 'title' || c === 'name'), url: lower.findIndex((c) => URL_HEADS.includes(c)) };
      continue;
    }
    if (!cols) continue;
    const raw = cells[cols.url] ?? '';
    const title = stripN(cols.title >= 0 ? cells[cols.title] : '') || null;
    const image = imageIn(raw);
    const url = image ? null : cellURL(raw);
    if (url || image) out.push({ collection, title, url, image, caption: null, tags: [] });
  }

  // Cards: a numbered heading starts one; it runs to the next heading.
  let card = null;
  const flush = () => {
    if (card && (card.url || card.image)) out.push(card);
    card = null;
  };
  for (const line of lines) {
    const h = /^#{2,3}\s+\d+\.\s+(.*)$/.exec(line);
    if (h) { flush(); card = { collection, title: stripN(h[1]).replace(/\.\.\.$/, '').trim() || null, url: null, image: null, caption: null, tags: [] }; continue; }
    if (/^#{1,3}\s/.test(line)) { flush(); continue; }
    if (!card) continue;
    if (!card.image) card.image = imageIn(line);
    const cap = /^>\s?(.*)$/.exec(line);
    if (cap && !card.caption) card.caption = stripN(cap[1]) || null;
    const tags = /\*\*Tags:\*\*\s*(.*)$/.exec(line);
    if (tags) card.tags = [...tags[1].matchAll(/`([^`]+)`/g)].map((m) => m[1].trim()).filter(Boolean);
    const src = /\*\*Source:\*\*\s*(\[[^\]]*\]\([^)]+\)|\S+)/.exec(line) || /\[Source\]\(([^)]+)\)/.exec(line);
    if (src && !card.url) card.url = cellURL(src[1].startsWith('[') ? src[1] : src[1]);
    const desc = /\*\*Description:\*\*\s*(.+)$/.exec(line);
    if (desc && !card.caption) card.caption = stripN(desc[1]) || null;
  }
  flush();
  return out;
}

/** "Digital Tools" → "digital-tools" (the library's collection tag style). */
export function collectionSlug(name) {
  return String(name).normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/&/g, 'and').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}
