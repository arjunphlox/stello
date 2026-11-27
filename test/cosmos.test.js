import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseNote, cellURL, collectionSlug } from '../src/lib/cosmos.js';

test('table notes: bare, markdown, scheme-less links and image rows', () => {
  const text = `# Books
Total items: 3
| Item | Source URL |
|------|-----------|
| Exercised by Daniel E. Lieberman | https://app.thestorygraph.com/books/ec7?utm_source=DenseDiscovery-304 |
| Ezra&#x27;s Bookshelf | [link](https://example.com/ezra) |
| Tips | rwt.io/typography-tips/x |
| A poster | [View Image](images/p.webp) |
| No link | just text |`;
  const out = parseNote(text, 'Books');
  assert.equal(out.length, 4);
  assert.equal(out[0].url, 'https://app.thestorygraph.com/books/ec7?utm_source=DenseDiscovery-304');
  assert.equal(out[1].title, "Ezra's Bookshelf");
  assert.equal(out[2].url, 'https://rwt.io/typography-tips/x');
  assert.deepEqual([out[3].url, out[3].image], [null, 'images/p.webp']);
});

test('"| # | Title | URL |" tables', () => {
  const out = parseNote('## Articles\n| # | Title | URL |\n|---|---|---|\n| 1 | Prompting | https://a.com/p |', 'Midjourney');
  assert.deepEqual(out.map((e) => [e.title, e.url]), [['Prompting', 'https://a.com/p']]);
});

test('card notes: image, caption with names, tags, source; bare cards skipped', () => {
  const text = `# Huegrid Gifts
*Collection from [Cosmos.so](https://www.cosmos.so/arjunphlox/huegrid-gifts) --- 12 items*
## 1. The <n>Solstice</n> clock by <n>Animaro</n>, a kinetic timep...
![The <n>Solstice</n> clock](images/001_674716720.webp)
> The <n>Solstice</n> clock by <n>Animaro</n>, a kinetic timepiece.
**Type:** INSTAGRAM | **Source:** [https://www.instagram.com/reel/C2KcSGpsDav/](https://www.instagram.com/reel/C2KcSGpsDav/) | **Tags:** \`clock\`, \`wall clock\`
## 6. Item 6
**Type:** ProductElement
### 1. Jackson Alves
![Jackson Alves](images/1260751033_b74f0215a4.webp)
> Artistic logo by <n>Jackson Alves</n> for <n>Apple</n>.
[Source](https://jacksonalves.com/work)`;
  const out = parseNote(text, 'Huegrid Gifts');
  assert.equal(out.length, 2);
  assert.equal(out[0].title, 'The Solstice clock by Animaro, a kinetic timep');
  assert.equal(out[0].url, 'https://www.instagram.com/reel/C2KcSGpsDav/');
  assert.equal(out[0].image, 'images/001_674716720.webp');
  assert.equal(out[0].caption, 'The Solstice clock by Animaro, a kinetic timepiece.');
  assert.deepEqual(out[0].tags, ['clock', 'wall clock']);
  assert.equal(out[1].url, 'https://jacksonalves.com/work');
});

test('helpers', () => {
  assert.equal(cellURL('just text'), null);
  assert.equal(collectionSlug('Digital Tools'), 'digital-tools');
  assert.equal(collectionSlug('Apple OS 26'), 'apple-os-26');
});

test('"| Item | Source |" tables and escaped pipes in titles', () => {
  const out = parseNote('# Typography\n| Item | Source |\n|---|---|\n| CMYK Halftone \\| Figma | https://figma.com/x |\n| Plain | [link](https://a.com/b) |', 'Typography');
  assert.deepEqual(out.map((e) => [e.title, e.url]), [['CMYK Halftone | Figma', 'https://figma.com/x'], ['Plain', 'https://a.com/b']]);
});
