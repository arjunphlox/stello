#!/usr/bin/env node
/**
 * Writes test/fixtures/folder-ingest.json (sample files + what the web reader takes from
 * them) and the Swift copy apple/Stello/StelloTests/FolderIngestFixtures.swift, so the web
 * reader (src/lib/folder-ingest.js) and the Mac one (Store/FolderIngest.swift) are checked
 * against the same expected links, ids and new items. Run after changing either reader:
 *   node scripts/make-folder-ingest-fixtures.mjs
 * Review the diff of the JSON before committing: it is the expected output.
 */
import { writeFileSync } from 'node:fs';
import { readLinks, linkItemId, linkChange, ingestType, ownWords, isWrittenNote, noteItemId, noteItem } from '../src/lib/folder-ingest.js';

const NOW = '2026-11-28T09:00:00.000Z';
const MODIFIED = Date.parse('2025-11-28T08:00:00.000Z');

const files = [
  { path: 'Reading notes/links.md', text: [
    '---', 'title: Front matter is skipped', 'url: https://skip.example/front', '---',
    '# Reading list', '## Type & Lettering',
    '- [Atlas of Type](https://atlasoftype.com/?utm_source=tw) — great index of foundries',
    '- https://kometa.xyz/fonts. Lovely futuristic ones',
    '* [ ] Check <https://example.org/a_(b)> later',
    '![a picture](https://img.example/x.png)',
    '```', 'https://code.example/skip', '```',
    '## Tools',
    '1. Use (https://linear.app) for planning',
    '2. [Atlas again](https://www.atlasoftype.com/) dupes merge',
    'Two on a line: https://a.example/one and https://b.example/two',
  ].join('\n') },
  { path: 'plain.txt', text: 'Café notes\nhttps://cafe.example/menu?ref=nav great coffee!\n' },
  { path: 'Raindrop export.csv', text: '﻿title,note,excerpt,url,folder,tags,created\n"Hello, world","my ""note""",A description,https://a.com/x,Design/Type,"serif, display",2025-03-01T10:00:00Z\nB,,,https://b.com,Unsorted,,1700000000\nNo link,,,,,,\n' },
  { path: 'pocket.csv', text: 'title;url;time_added;tags;status\nArticle;https://pocket.example/a;1600000000;read|later;unread\n' },
  { path: 'sheet.csv', text: 'Name,Where\nShop,https://shop.example\nSite,https://site.example/\n' },
  { path: 'bookmarks.html', text: [
    '<!DOCTYPE NETSCAPE-Bookmark-file-1>', '<TITLE>Bookmarks</TITLE><H1>Bookmarks</H1>', '<DL><p>',
    '<DT><H3 ADD_DATE="1">Bookmarks bar</H3>', '<DL><p>', '<DT><H3>Design &amp; Type</H3>', '<DL><p>',
    '<DT><A HREF="https://fonts.google.com/" ADD_DATE="1600000000" TAGS="fonts,free">Google Fonts</A>',
    '<DD>Free fonts &amp; more', '</DL><p>', '<DT><A HREF="https://x.com/">X</A>', '</DL><p>', '</DL><p>',
  ].join('\n') },
  { path: 'page.html', text: '<html><body><a href="https://not-bookmarks.example">x</a></body></html>' },
  { path: 'Atlas of type.webloc', text: '<?xml version="1.0"?><plist><dict><key>URL</key><string>https://atlasoftype.com/?a=1&amp;b=2</string></dict></plist>' },
  { path: 'Binary.webloc', text: 'bplist00Ñ\u0001\u0002SURL_\u0010\u0018https://binary.example/p\u0008\u000b' },
  { path: 'Shortcut.url', text: '[InternetShortcut]\r\nURL=https://foo.com/bar\r\n' },
  { path: 'image.png', text: '' },
  // Written notes: about 50 words or more of the person's own writing make the note an item.
  { path: 'Journal/Trip to Kyoto.md', text: [
    '---', 'title: "Kyoto, spring"', 'tags: [travel, Japan, "#temples"]', 'aliases:', '  - Kyoto trip', "created: '2024-03-02'", 'cssclass: wide', '---',
    '# Day one', '',
    'We walked from the station to the old wooden houses near the river. The light at dusk was soft and orange,',
    'and every lane seemed to end in a small shrine. I want to come back in autumn when the maples turn red,',
    'and stay longer near Arashiyama so the mornings are quiet before the crowds arrive. Café notes: try the',
    'matcha place by the bridge — it was the best of the trip.', '',
    'Map: https://maps.example/kyoto', '```', 'not counted words here inside code', '```',
  ].join('\n') },
  { path: 'Ideas/short.md', text: 'Just a few words here.\n- https://short.example\n' },
  { path: 'Ideas/nested.md', text: ['---', 'meta:', '  deep: 1', '---', ...Array(13).fill('Writing words five here.')].join('\n') },
  { path: 'Ideas/plain note.md', text: Array(14).fill('Plain writing with no header at all.').join(' ') + '\n' },
  { path: 'Ideas/long.txt', text: Array(14).fill('A text file is never a note item.').join(' ') },
];

const cases = [];
for (const f of files) {
  const links = readLinks(f.path, f.text, { modified: MODIFIED });
  const items = [];
  for (const l of links) {
    const id = await linkItemId(l.key);
    items.push({ id, change: linkChange(l, { id, now: NOW }) });
  }
  const written = isWrittenNote(f.path, f.text);
  const noteId = await noteItemId(f.path);
  const n = written ? noteItem(f.path, f.text, { id: noteId, modified: MODIFIED, now: NOW }) : null;
  const note = { words: ownWords(f.text), written, item: n && { id: n.id, extra: n.extra, body: n.body, change: n.change } };
  cases.push({ ...f, modified: MODIFIED, now: NOW, expect: { type: ingestType(f.path), links, items, note } });
}

const json = JSON.stringify({ cases });
writeFileSync(new URL('../test/fixtures/folder-ingest.json', import.meta.url), JSON.stringify({ cases }, null, 1) + '\n');
writeFileSync(new URL('../apple/Stello/StelloTests/FolderIngestFixtures.swift', import.meta.url),
  `// Generated by scripts/make-folder-ingest-fixtures.mjs from test/fixtures/folder-ingest.json. Don't edit.
// The web reader's expected output; FolderIngestTests checks FolderIngest.swift gives the same.
enum FolderIngestFixtures {
    static let json = #"""
${json}
"""#
}
`);
console.log(`${cases.length} files, ${cases.reduce((n, c) => n + c.expect.links.length, 0)} links`);
