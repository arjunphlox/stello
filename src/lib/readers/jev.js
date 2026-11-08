/**
 * Jev (typesafe.ai) second opinion for links the rules couldn't sort.
 *
 * Privacy rule (Arjun, Nov 8 2026): Jev gets the link, the title and the description,
 * nothing else (never notes, snippets, why-saved or page text). `jevState` is the only
 * place a state is built, so that rule lives in one function.
 *
 * Not wired into saves yet: it goes live only after the 200-item bake-off against
 * Claude Haiku (scripts/sort-bakeoff.mjs). Off unless JEV_API_KEY is set.
 */

export const JEV_URL = 'https://api.typesafe.ai/v1/systemone';
export const JEV_MODEL = 'jev-latest';
/** A Jev answer below this goes to Needs review instead. */
export const JEV_MIN_CONFIDENCE = 0.6;

/** The kinds a second opinion may pick, with the description each is judged by. */
export const KIND_CRITERIA = {
  article: 'An article, blog post, essay, news story or tutorial to read.',
  tool: 'Software: an app, web app, browser extension, code library, repository or AI model.',
  product: 'A physical product page in a shop, something to buy.',
  post: 'A single social media post (X/Twitter, Instagram, Dribbble, Behance, Pinterest, Threads).',
  resource: 'A design or code asset to use: template, UI kit, icon set, mockup, Figma plugin or file, font pack.',
  book: 'A single book: a book page, a store listing for a book, or a book record.',
  course: 'A course, class, workshop, bootcamp or learning programme.',
  music: 'Music: a track, album, playlist, artist page or DJ mix.',
  link: 'None of these: a website home page, a portfolio, a list, or anything else.',
};

/** The only data Jev ever sees. */
export function jevState({ url, title, description }) {
  const clip = (s, n) => (typeof s === 'string' ? s.trim().slice(0, n) : '');
  return `Link: ${clip(url, 500)}\nTitle: ${clip(title, 300)}\nDescription: ${clip(description, 500)}`;
}

export function jevRequestBody(page) {
  return {
    model: JEV_MODEL,
    state: jevState(page),
    questions: {
      kind: {
        type: 'choice',
        instructions: 'What kind of saved item is this link? Judge from the link, title and description.',
        criteria: KIND_CRITERIA,
      },
    },
  };
}

/** Reads the `kind` answer; null when the response isn't the documented shape. */
export function parseJevAnswer(body) {
  const a = body?.answers?.kind;
  if (!a || typeof a.choice !== 'string' || !(a.choice in KIND_CRITERIA)) return null;
  return {
    kind: a.choice,
    confidence: typeof a.confidence === 'number' ? a.confidence : 0,
    probabilities: a.probabilities ?? null,
    model: body.model ?? null,
    inputTokens: body.usage?.input_tokens ?? null,
  };
}

/**
 * Asks Jev for the kind. Never throws: null on a missing key, network error, non-200
 * or unknown shape.
 */
export async function askJev(page, { apiKey, fetchImpl = globalThis.fetch, timeout = 10000 } = {}) {
  if (!apiKey) return null;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeout);
  try {
    const res = await fetchImpl(JEV_URL, {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(jevRequestBody(page)),
      signal: ctrl.signal,
    });
    if (res.status !== 200) return null;
    return parseJevAnswer(await res.json());
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}
