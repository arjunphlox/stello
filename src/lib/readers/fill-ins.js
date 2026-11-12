/**
 * Enrich fill-ins per kind, as on the Mac (EnrichmentService.apply…IfNeeded +
 * EnrichmentPrompts.swift): when the page readers left a kind's own fields empty,
 * rules fill what they can and ONE model call fills the rest.
 *
 *   product  Instagram / bare-image products: name + brand (rule: the image filename)
 *   tool     platforms + pricing                (rule: download buttons, pricing words)
 *   book     authors + year                     (model only)
 *   course   format, length, topics             (rule: cohort / self-paced, lessons, hours)
 *   article  summary + a tutorial's tech stack  (rule: known tech names)
 *   post     AI-art flag + model (rules), then the prompt (rule-read, else the model)
 *   music    a YouTube compound title: clean track, artist, film (rules ran at read time)
 *
 * Guesses carry the Mac's `…IsGuess` flags and never replace a read value. Runs only on a
 * user-run Enrich (never on capture or import). Pure except for the injected `callModel`.
 */
import * as Tool from './tool.js';
import * as Book from './book.js';
import * as Course from './course.js';
import * as Article from './article.js';
import * as Post from './post.js';
import { titleFromImageFilename, brandRef } from './product.js';

const nullable = (type) => ({ type: [type, 'null'] });
const strings = { type: 'array', items: { type: 'string' } };
const obj = (properties) => ({
  type: 'object', properties, required: Object.keys(properties), additionalProperties: false,
});

const NEVER_INVENT = 'Never invent a value: use null (or an empty list) when the text does not say. Answer with the JSON object only.';

/** One job per kind: system prompt (the Mac's instructions + worked example) and output schema. */
export const JOBS = {
  product: {
    schema: obj({ productName: nullable('string'), brand: nullable('string') }),
    system: `You are Stello's product reader. The user saved a product from an Instagram post or a bare image file, so there is no shop data, only a caption and/or a filename. Guess the product's name and its brand.

Rules:
- productName is what a shop would list: short, plain words, no emoji, hashtags, prices or calls to action ("link in bio", "shop now").
- brand only when the text names the maker (often an @mention or a capitalised name); never use the posting account as the brand unless the text says it makes the product.
- A filename slug reads as words: hyphens and underscores are spaces, trailing numbers are image counters.
- ${NEVER_INVENT}

Worked example. Caption: "Desk upgrade 🔥 the @stuffcool Mag Dock keeps every cable in place. Link in bio! #desksetup" gives {"productName": "Mag Dock", "brand": "Stuffcool"}.`,
  },
  tool: {
    schema: obj({ platforms: strings, pricing: nullable('string') }),
    system: `You are Stello's tool reader. The user saved a software tool's web page that has no structured data. From the page text, say which platforms the tool runs on and how it is priced.

Rules:
- platforms only from what the text states (download buttons, "available on", system requirements, "works in your browser"), each one of: macOS, iOS, iPadOS, watchOS, visionOS, Windows, Linux, Android, Web. "Download for Mac" means macOS; a sign-up-and-use web app means Web.
- pricing is exactly one of: free, paid, freemium, open source. freemium = a free plan plus paid plans; open source = the code is published under an open licence.
- ${NEVER_INVENT}

Worked example. Page text: "Raycast, your shortcut to everything. Download for Mac. Free for personal use. Pro: $8/month for AI and cloud sync." gives {"platforms": ["macOS"], "pricing": "freemium"}.`,
  },
  book: {
    schema: obj({ authors: strings, year: nullable('integer') }),
    system: `You are Stello's book reader. The user saved a page about one book (a store, catalogue or publisher page). From its text, say who wrote the book and the year it was published.

Rules:
- authors are the people who wrote the book, full names as the page gives them, at most 4 in page order; never the publisher, translator, illustrator, foreword writer, reviewer or the store.
- year only as the text states it (a publication date or "first published 2009"); never estimate it, and never use a review or copyright-notice date for another book.
- Ignore navigation, recommendations ("customers also bought"), reviews and ads.
- ${NEVER_INVENT}

Worked example. Page text: "Introduction to Algorithms, third edition. By Thomas H. Cormen, Charles E. Leiserson, Ronald L. Rivest and Clifford Stein. The MIT Press, July 2009. Customers also bought: Clean Code by Robert C. Martin." gives {"authors": ["Thomas H. Cormen", "Charles E. Leiserson", "Ronald L. Rivest", "Clifford Stein"], "year": 2009}.`,
  },
  course: {
    schema: obj({ format: nullable('string'), durationText: nullable('string'), topics: strings }),
    system: `You are Stello's course reader. The user saved an online course's page. From its text, say how the course is run, how long it is and what it teaches.

Rules:
- format is exactly one of: self-paced, cohort, program, video series, workshop. cohort = a group starts together with live sessions on set dates; self-paced = recorded lessons you take any time; program = a multi-course track or certificate; workshop = a single live session or short hands-on event.
- durationText only as the text states it, short ("5 hours", "6 weeks", "3 days"); never estimate it.
- topics are the skills or subjects taught, as short names (Figma, Auto layout, Typography, React), at most 5, most central first.
- Ignore navigation, testimonials, refund FAQs and instructor bios.
- ${NEVER_INVENT}

Worked example. Page text: "Design Systems in Figma. Join the next cohort on March 3: six weeks of live sessions covering variables, components and auto layout." gives {"format": "cohort", "durationText": "6 weeks", "topics": ["Design systems", "Figma", "Variables", "Components", "Auto layout"]}.`,
  },
  article: {
    schema: obj({ summary: nullable('string'), techStack: strings }),
    system: `You are Stello's article reader. The user saved an article, essay, news story or tutorial. From its text, write a short summary and, only for a tutorial, list the technologies it uses.

Rules:
- summary is 2 or 3 plain sentences in your own words: the main point and the takeaway. No "This article…" opener, no marketing tone, no quotes, at most 400 characters.
- techStack only for a tutorial or how-to: the libraries, languages and tools it builds with, as their usual names (three.js, GSAP, React, WebGL, GLSL, CSS, SwiftUI), at most 5, most central first. Empty for an essay, news story or opinion piece.
- Ignore navigation, cookie notices, newsletter sign-ups, comments and author bios.
- ${NEVER_INVENT}

Worked example. Article text: "In this tutorial we build an infinite image slider with GSAP and a bit of CSS. We'll use GSAP's Observer plugin for drag and wheel input, then add a WebGL shader for the distortion…" gives {"summary": "Builds an infinite, draggable image slider, using GSAP's Observer plugin for drag and wheel input and a WebGL shader for a distortion effect on movement.", "techStack": ["GSAP", "CSS", "WebGL"]}.`,
  },
  post: {
    schema: obj({ prompt: nullable('string') }),
    system: `You are Stello's prompt reader. The user saved an AI-generated image post (Midjourney, Stable Diffusion and similar) whose text doesn't spell out the prompt. Guess the prompt the artist most likely used.

Rules:
- Write it the way image prompts are written: short comma-separated phrases for the subject, style, medium, lighting and palette, plus any parameters the post shows (e.g. --ar 3:2).
- Use only what the post text says or clearly implies. No hashtags, emoji, @mentions or calls to action.
- ${NEVER_INVENT}

Worked example. Model: Midjourney. Post text: "Brutalist library at dusk, made with #midjourney v6 🔥 #aiart #architecture" gives {"prompt": "brutalist library at dusk, concrete architecture, soft dusk light, cinematic"}.`,
  },
  music: {
    schema: obj({ artist: nullable('string'), track: nullable('string'), version: nullable('string'), film: nullable('string') }),
    system: `You are Stello's music-title parser. YouTube uploads pack several facts into one title; pull out the artist, the clean track title, the version and (for Indian film music) the film.

Rules:
- "Artist - Track" is the Western convention: everything before " - " is the artist.
- Indian film-music titles follow "Track - Video Song | Film | Cast | Singers | Composer": the pipe segments are metadata, not an artist; the first pipe segment is the film and artist is null.
- track drops descriptors such as "Official Video", "Video Song", "Official Audio", "Lyrical Video".
- version is live, cover, remaster, acoustic or remix when the title marks one.
- ${NEVER_INVENT}

Worked example. Title: "Thassadiya - Video Song | Maa Inti Bangaaram | Samantha | Chinmayi | Punya | Santhosh Narayanan" gives {"artist": null, "track": "Thassadiya", "version": null, "film": "Maa Inti Bangaaram"}.`,
  },
};

const clip = (s, n) => String(s).slice(0, n);
const blank = (s) => s == null || !String(s).trim();
const cleanStr = (s) => (typeof s === 'string' && s.trim() ? s.trim() : null);

/** Collection labels (wishlist, digital-tools, …) and the other tag names of an item. */
function tagNames(tags) {
  const list = Array.isArray(tags) ? tags : [];
  return {
    labels: list.filter((t) => t && t.category === 'collection').map((t) => t.tag),
    others: list.filter((t) => t && t.category !== 'collection').map((t) => t.tag),
  };
}

function filenameOf(sourceURL) {
  try { return new URL(sourceURL).pathname.split('/').filter(Boolean).pop() || null; } catch { return null; }
}

/**
 * What the model would be asked for this item, or null when nothing is missing / there is
 * no text to read. `meta` is the item's dossier after the rule steps (see fillIns).
 * @returns {{ kind: string, user: string } | null}
 */
export function plan({ kind, meta, title, summary, text, sourceURL }) {
  if (!meta) return null;
  const body = !blank(text) ? text : null;
  switch (kind) {
    case 'product': {
      if (meta.source !== 'instagram' && meta.source !== 'image') return null;
      const needsName = meta.productName == null || meta.productNameIsGuess === true;
      const needsBrand = meta.brand == null || meta.brandIsGuess === true;
      if (!needsName && !needsBrand) return null;
      const lines = [];
      if (!blank(meta.caption)) lines.push(`Caption: ${clip(meta.caption, 1500)}`);
      const filename = meta.source === 'image' ? filenameOf(sourceURL) : null;
      if (filename) lines.push(`Filename: ${filename}`);
      return lines.length ? { kind, user: lines.join('\n') } : null;
    }
    case 'tool': {
      if (!Tool.needsGuess(meta)) return null;
      const t = body ?? cleanStr(summary) ?? cleanStr(meta.tagline);
      return t ? { kind, user: `Page text: ${clip(t, 1500)}` } : null;
    }
    case 'book': {
      if (!Book.needsGuess(meta)) return null;
      const t = body ?? cleanStr(summary);
      return t ? { kind, user: `Page text: ${clip(t, 2000)}` } : null;
    }
    case 'course': {
      if (!Course.needsGuess(meta)) return null;
      const t = body ?? cleanStr(summary);
      return t ? { kind, user: `Page text: ${clip(t, 2000)}` } : null;
    }
    case 'article':
      // The model only writes a missing summary; a tutorial's stack falls back to the rules.
      if (!Article.needsDigest(meta) || meta.summary != null || !body) return null;
      return { kind, user: `Article text: ${clip(body, 3000)}` };
    case 'post': {
      if (!meta.isAIArt || meta.prompt != null || blank(meta.text)) return null;
      const lines = [];
      if (meta.aiModel) lines.push(`Model: ${meta.aiModel}`);
      lines.push(`Post text: ${clip(meta.text, 1500)}`);
      return { kind, user: lines.join('\n') };
    }
    case 'music': {
      if (meta.platform !== 'youtube' && meta.platform !== 'youtube-music') return null;
      if (blank(title) || !(title.includes(' - ') || title.includes('|'))) return null;
      const channel = meta.artists?.[0]?.name;
      return { kind, user: `Title: ${title}${channel ? `\nChannel: ${channel}` : ''}` };
    }
    default:
      return null;
  }
}

/** Parses the model's reply text into an object (tolerates a ```json fence). */
export function parseReply(text) {
  if (typeof text !== 'string') return null;
  const raw = text.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  try {
    const v = JSON.parse(raw);
    return v && typeof v === 'object' && !Array.isArray(v) ? v : null;
  } catch {
    return null;
  }
}

/**
 * Runs the fill-ins for one item and returns the fields to write ({ metadata, title? }),
 * or null when nothing changed.
 * @param {object} p
 * @param {object} p.item       { kind, metadata, title, summary, source_url, tags }
 * @param {string|null} p.text  the page's main text from this Enrich's read (post text / caption for posts and social products)
 * @param {(job: {system: string, schema: object, user: string}) => Promise<object|null>} [p.callModel]
 *        one model call; absent (no API key) means rules only
 */
export async function fillIns({ item, text = null, callModel = null }) {
  const kind = item.kind;
  if (!JOBS[kind]) return null;
  let meta = item.metadata;
  if (typeof meta === 'string') { try { meta = JSON.parse(meta); } catch { meta = null; } }
  if (!meta || typeof meta !== 'object') return null;
  const before = JSON.stringify(meta);
  meta = structuredClone(meta);
  const fields = {};

  // Posts: the AI-art flag + model and a rule-read prompt come first (labels and tags).
  if (kind === 'post') {
    const { labels, others } = tagNames(typeof item.tags === 'string' ? safeJSON(item.tags) : item.tags);
    Post.applyAIArt(meta, labels, others);
  }

  const p = plan({ kind, meta, title: item.title, summary: item.summary, text, sourceURL: item.source_url });
  let out = null;
  if (p && callModel) {
    try {
      out = await callModel({ system: JOBS[kind].system, schema: JOBS[kind].schema, user: p.user });
    } catch {
      out = null;
    }
  }
  const t = !blank(text) ? text : (cleanStr(item.summary) ?? (kind === 'tool' ? cleanStr(meta.tagline) : null));

  switch (kind) {
    case 'product': {
      if (!p) break;
      const filename = meta.source === 'image' ? filenameOf(item.source_url) : null;
      const ruleName = filename ? titleFromImageFilename(item.source_url) : null;
      const name = cleanStr(out?.productName) ?? ruleName;
      const brand = cleanStr(out?.brand);
      const previousName = meta.productName ?? null;
      if (name && (meta.productName == null || meta.productNameIsGuess === true)) {
        meta.productName = name;
        meta.productNameIsGuess = true;
      }
      if (brand && (meta.brand == null || meta.brandIsGuess === true)) {
        meta.brand = brandRef(brand);
        meta.brandIsGuess = true;
      }
      // A title that was itself the old guess follows the new one.
      if (previousName && item.title === previousName && meta.productName && meta.productName !== previousName) {
        fields.title = meta.productName;
      }
      break;
    }
    case 'tool': {
      if (!Tool.needsGuess(meta) || !t) break;
      const facts = (out && (out.platforms?.length || out.pricing)) ? out : Tool.ruleBasedFacts(t);
      if (facts) Tool.applyGuess(facts, meta);
      break;
    }
    case 'book':
      if (out && Book.needsGuess(meta)) Book.applyGuess({ authors: out.authors || [], year: out.year ?? null }, meta);
      break;
    case 'course': {
      if (!Course.needsGuess(meta) || !t) break;
      const rule = Course.ruleBasedFacts(t);
      const guess = out ? { format: out.format, durationText: out.durationText, topics: out.topics || [] } : rule;
      if (!guess) break;
      if (guess.lessons == null) guess.lessons = rule?.lessons ?? null;
      Course.applyGuess(guess, meta);
      break;
    }
    case 'article':
      if (Article.needsDigest(meta) && !blank(text)) Article.applyDigest(out, text, meta);
      break;
    case 'post': {
      const prompt = out ? Post.cleanPrompt(out.prompt) : null;
      if (prompt && meta.isAIArt && meta.prompt == null) {
        meta.prompt = prompt;
        meta.promptIsGuess = true;
      }
      break;
    }
    case 'music': {
      if (!out) break;
      const track = cleanStr(out.track);
      const artist = cleanStr(out.artist);
      const film = cleanStr(out.film);
      if (track) meta.cleanTitle = track;
      if (artist && !meta.artists?.length) meta.artists = [{ name: artist, kind: 'individual' }];
      if (film) meta.film = film;
      break;
    }
    default:
      break;
  }

  if (JSON.stringify(meta) !== before) fields.metadata = meta;
  return Object.keys(fields).length ? fields : null;
}

function safeJSON(s) {
  try { return JSON.parse(s); } catch { return []; }
}
