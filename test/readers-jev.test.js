// Jev client: only link, title and description leave the Worker.
import { test } from 'node:test';
import { eq } from './readers-helpers.js';
import { jevState, jevRequestBody, parseJevAnswer, askJev, JEV_URL } from '../src/lib/readers/jev.js';

test('The state holds the link, title and description only', () => {
  const s = jevState({ url: 'https://x.com/a', title: 'T', description: 'D', notes: 'secret', snippets: ['s'], whySaved: 'w', pageText: 'p' });
  eq(s, 'Link: https://x.com/a\nTitle: T\nDescription: D');
  const body = JSON.stringify(jevRequestBody({ url: 'https://x.com/a', title: 'T', notes: 'secret' }));
  eq(body.includes('secret'), false);
});

test('Answer parsing follows the documented choice shape', () => {
  eq(parseJevAnswer({ model: 'jev-1.13.0', answers: { kind: { type: 'choice', choice: 'book', confidence: 0.9, probabilities: { book: 0.95 } } }, usage: { input_tokens: 40 } }),
    { kind: 'book', confidence: 0.9, probabilities: { book: 0.95 }, model: 'jev-1.13.0', inputTokens: 40 });
  eq(parseJevAnswer({ answers: { kind: { choice: 'spaceship' } } }), null);
  eq(parseJevAnswer(null), null);
});

test('askJev: off without a key; never throws; sends the bearer key', async () => {
  eq(await askJev({ url: 'https://a.b' }, {}), null);
  eq(await askJev({ url: 'https://a.b' }, { apiKey: 'k', fetchImpl: async () => { throw new Error('down'); } }), null);
  let seen;
  const r = await askJev({ url: 'https://a.b', title: 'x' }, { apiKey: 'k', fetchImpl: async (url, init) => { seen = { url, auth: init.headers.Authorization }; return new Response(JSON.stringify({ answers: { kind: { choice: 'tool', confidence: 0.7 } } })); } });
  eq(seen, { url: JEV_URL, auth: 'Bearer k' });
  eq(r.kind, 'tool');
});
