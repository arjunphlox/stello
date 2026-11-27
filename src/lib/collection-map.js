/**
 * Collections are retired (Arjun, Nov 27 2026): kind and tags already organise the
 * library, so each old collection folds into a kind, a place or a tag, or is dropped
 * where an existing kind or tag already says the same thing. The list Arjun approved is
 * /mnt/project-files/stello/collections-mapping.md; this is the same list as data.
 *
 * Used by the one-time D1 fold (scripts/fold-collections.mjs), the Cosmos import and the
 * folder converter, so a collection label always lands in the same place.
 */

import { collectionSlug } from './cosmos.js';

const K = (kind) => ({ kind });
const T = (category, tag) => ({ tag: { category, tag } });
const P = (place) => ({ place });
const DROP = { drop: true };

export const COLLECTION_MAP = {
  // Existing collections.
  websites: K('website'),
  midjourney: T('tool', 'midjourney'),
  wishlist: T('intent', 'wishlist'),
  'digital-tools': K('tool'),
  'gen-ai': T('subject', 'generative-ai'),
  figma: T('tool', 'figma'),
  firms: K('studio'),
  framer: T('tool', 'framer'),
  technology: T('subject', 'technology'),
  branding: T('subject', 'branding'),
  education: T('subject', 'education'),
  'data-visualisation': T('subject', 'data-visualisation'),
  'design-systems': T('subject', 'design-systems'),
  'digital-resources': K('resource'),
  'visual-development': T('subject', 'visual-development'),
  'adobe-illustrator': T('tool', 'adobe-illustrator'),
  'type-foundries': K('foundry'),
  'user-interface-design': T('subject', 'ui-design'),
  'packaging-design': T('subject', 'packaging-design'),
  'digital-productivity': T('subject', 'productivity'),
  'work-shots': T('format', 'work-shot'),
  books: K('book'),
  'web-design': T('subject', 'web-design'),
  vancouver: P('vancouver'),
  'industrial-design': T('subject', 'industrial-design'),
  'spatial-computing': T('subject', 'spatial-computing'),
  'visual-design': T('subject', 'visual-design'),
  'motion-graphics': T('subject', 'motion-design'),
  'health-and-wellbeing': T('subject', 'health-and-wellbeing'),
  news: K('article'),
  rive: T('tool', 'rive'),
  music: T('subject', 'music'),
  'user-research': T('subject', 'user-research'),
  copywriting: T('subject', 'copywriting'),
  'information-design': T('subject', 'information-design'),
  spline: T('tool', 'spline'),
  'formula-1': T('subject', 'formula-1'),
  marketing: T('subject', 'marketing'),
  cinema: T('subject', 'cinema'),
  cinematography: T('subject', 'cinema'),
  '3d-graphics': T('subject', '3d'),
  'type-design': T('subject', 'type-design'),
  'photo-manipulation': T('subject', 'photo-manipulation'),
  'web-interactions': T('subject', 'interaction-design'),
  'generative-graphics': T('style', 'generative'),
  'ai-art': T('subject', 'generative-ai'),
  'product-design': T('subject', 'product-design'),
  'digital-illustration': T('subject', 'illustration'),
  typography: T('subject', 'typography'),
  finance: T('subject', 'finance'),
  business: T('subject', 'business'),
  'reference-source': K('resource'),
  'women-s-accessories': DROP,
  'display-typeface': DROP,
  'creator-stories': DROP,

  // Cosmos note names not covered above.
  typefaces: K('typeface'),
  'apple-os-26': T('subject', 'apple-os'),
  'business-design': T('subject', 'business-design'),
  calligraphy: T('subject', 'calligraphy'),
  'career-growth': T('subject', 'career'),
  'conceptual-interfaces': T('subject', 'ui-design'),
  'craft-work': T('subject', 'craft'),
  'design-by-nature': T('subject', 'nature'),
  'digital-product-design': T('subject', 'product-design'),
  'graphic-design': T('subject', 'graphic-design'),
  home: T('subject', 'home'),
  'icon-design': T('subject', 'icon-design'),
  illustration: T('subject', 'illustration'),
  'isometric-graphics': T('style', 'isometric'),
  'market-research': T('subject', 'market-research'),
  photography: T('subject', 'photography'),
  procreate: T('tool', 'procreate'),
  webflow: T('tool', 'webflow'),
  quotes: T('format', 'quote'),
  'simple-graphics': T('style', 'minimalist'),
  sound: T('subject', 'sound'),
  travel: T('subject', 'travel'),
  'color-inspiration': DROP,
  'unsorted-elements': DROP,
};

/** Kinds a collection may set; only a plain link (or no kind) takes one. */
const OPEN_KINDS = new Set(['link', '', null, undefined]);

/** One collection label → its rule, or null when the list doesn't name it. */
export function collectionRule(label) {
  return COLLECTION_MAP[collectionSlug(label)] || null;
}

/**
 * Fold an item's collection tags (and any extra labels, such as a Cosmos note name)
 * into kind / tags. Tags are [{ tag, category, weight }]. Returns
 * { kind, tags, unknown: [labels the list doesn't name] }; nothing else changes.
 * A label the list doesn't name keeps its meaning as a subject tag, so nothing is lost.
 */
export function foldCollections({ kind = null, tags = [] }, extraLabels = []) {
  const labels = [...tags.filter((t) => t && t.category === 'collection').map((t) => t.tag), ...extraLabels];
  const out = tags.filter((t) => t && t.category !== 'collection').map((t) => ({ ...t }));
  const has = (category, tag) => out.some((t) => t.category === category && t.tag === tag);
  const unknown = [];
  let newKind = kind;
  for (const label of labels) {
    const rule = collectionRule(label);
    if (!rule) {
      unknown.push(label);
      const tag = collectionSlug(label);
      if (tag && !has('subject', tag)) out.push({ tag, category: 'subject', weight: 0.6 });
      continue;
    }
    if (rule.drop) continue;
    if (rule.kind) { if (OPEN_KINDS.has(newKind)) newKind = rule.kind; continue; }
    const t = rule.place ? { category: 'location', tag: rule.place } : rule.tag;
    if (!has(t.category, t.tag)) out.push({ tag: t.tag, category: t.category, weight: 0.6 });
  }
  return { kind: newKind, tags: out, unknown };
}

/**
 * The page classifier used collection labels as hints (wishlist → product, education →
 * course, midjourney → not a tool). With collections gone, the same hints come from the
 * tags they folded into.
 */
export function classifierHints(tags = []) {
  const hints = [];
  for (const t of tags) {
    if (!t) continue;
    if (t.category === 'collection') hints.push(t.tag);
    else if (t.category === 'intent' && t.tag === 'wishlist') hints.push('wishlist');
    else if (t.category === 'subject' && t.tag === 'education') hints.push('education');
    else if (t.category === 'tool' && t.tag === 'midjourney') hints.push('midjourney');
  }
  return [...new Set(hints)];
}
