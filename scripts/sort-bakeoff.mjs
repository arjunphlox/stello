#!/usr/bin/env node
/**
 * Bake-off: Jev vs Claude Haiku 5.5 at picking an item's kind from the link, title and
 * description only (the data Arjun allowed Jev to see).
 *
 * Ground truth is the kind the rules + Apple readers already gave each typed item.
 * Usage:
 *   1. Signed in on the web app, save https://<site>/api/items?limit=2000 as items.json
 *   2. JEV_API_KEY=... ANTHROPIC_API_KEY=... node scripts/sort-bakeoff.mjs items.json [n=200]
 * Writes bakeoff-results.json next to items.json and prints the summary.
 * Nothing is written to the library.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import Anthropic from '@anthropic-ai/sdk';
import { askJev, KIND_CRITERIA, jevState } from '../src/lib/readers/jev.js';

const KINDS = Object.keys(KIND_CRITERIA);
const HAIKU = 'claude-haiku-5-5';

const [file, nArg] = process.argv.slice(2);
if (!file) { console.error('usage: node scripts/sort-bakeoff.mjs items.json [n]'); process.exit(1); }
const n = parseInt(nArg || '200', 10);
const jevKey = process.env.JEV_API_KEY;
if (!jevKey) { console.error('JEV_API_KEY is not set'); process.exit(1); }

const raw = JSON.parse(readFileSync(file, 'utf8'));
const items = (raw.items ?? raw).filter((i) => i.source_url && i.kind && KINDS.includes(i.kind));

/** Up to n items, spread across kinds so rare kinds are tested too (seeded shuffle). */
function sample(list, count) {
  let seed = 42;
  const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
  const byKind = new Map();
  for (const i of [...list].sort(() => rnd() - 0.5)) {
    if (!byKind.has(i.kind)) byKind.set(i.kind, []);
    byKind.get(i.kind).push(i);
  }
  const out = [];
  while (out.length < count && [...byKind.values()].some((v) => v.length)) {
    for (const v of byKind.values()) if (v.length && out.length < count) out.push(v.shift());
  }
  return out;
}

const client = process.env.ANTHROPIC_API_KEY ? new Anthropic() : null;
const SYSTEM = `You sort saved links into one kind. Kinds:\n${KINDS.map((k) => `- ${k}: ${KIND_CRITERIA[k]}`).join('\n')}\nAnswer with the kind only.`;

async function askHaiku(page) {
  if (!client) return null;
  try {
    const res = await client.messages.create({
      model: HAIKU,
      max_tokens: 256,
      system: SYSTEM,
      output_config: {
        effort: 'low',
        format: { type: 'json_schema', schema: { type: 'object', properties: { kind: { type: 'string', enum: KINDS } }, required: ['kind'], additionalProperties: false } },
      },
      messages: [{ role: 'user', content: jevState(page) }],
    });
    if (res.stop_reason === 'refusal') return null;
    const text = res.content.find((b) => b.type === 'text')?.text;
    return { kind: JSON.parse(text).kind, inputTokens: res.usage?.input_tokens ?? null };
  } catch (err) {
    if (err instanceof Anthropic.RateLimitError) { await new Promise((r) => setTimeout(r, 5000)); return askHaiku(page); }
    console.warn('haiku error', err?.status ?? '', err?.message);
    return null;
  }
}

const picked = sample(items, n);
console.log(`${picked.length} items (${items.length} typed in the file)`);
const results = [];
for (const [idx, item] of picked.entries()) {
  const page = { url: item.source_url, title: item.title, description: item.summary };
  const t0 = Date.now();
  const jev = await askJev(page, { apiKey: jevKey });
  const jevMs = Date.now() - t0;
  const haiku = await askHaiku(page);
  results.push({ url: item.source_url, truth: item.kind, jev: jev?.kind ?? null, jevConfidence: jev?.confidence ?? null, jevMs, haiku: haiku?.kind ?? null });
  if ((idx + 1) % 20 === 0) console.log(`  ${idx + 1}/${picked.length}`);
}

const pct = (a, b) => (b ? `${Math.round((100 * a) / b)}%` : 'n/a');
const right = (k) => results.filter((r) => r[k] === r.truth).length;
const answered = (k) => results.filter((r) => r[k] != null).length;
const sure = results.filter((r) => (r.jevConfidence ?? 0) >= 0.6);
console.log(`\nJev:   ${pct(right('jev'), results.length)} right (${answered('jev')} answered)`);
console.log(`       ${pct(sure.filter((r) => r.jev === r.truth).length, sure.length)} right when confidence ≥ 0.6 (${sure.length} items)`);
console.log(`Haiku: ${pct(right('haiku'), results.length)} right (${answered('haiku')} answered)`);
const ms = results.map((r) => r.jevMs).sort((a, b) => a - b);
console.log(`Jev latency median ${ms[Math.floor(ms.length / 2)]} ms`);
for (const k of KINDS) {
  const of = results.filter((r) => r.truth === k);
  if (of.length) console.log(`  ${k.padEnd(9)} n=${String(of.length).padStart(3)}  jev ${pct(of.filter((r) => r.jev === k).length, of.length).padStart(4)}  haiku ${pct(of.filter((r) => r.haiku === k).length, of.length).padStart(4)}`);
}
const out = join(dirname(file), 'bakeoff-results.json');
writeFileSync(out, JSON.stringify(results, null, 2));
console.log(`\nDetails: ${out}`);
