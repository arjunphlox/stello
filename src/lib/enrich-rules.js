/**
 * Rule-based text enrichment for Stello.
 *
 * Ports the keyword dictionaries and platform maps from the archived
 * scripts/archive/enrich.py + scripts/archive/analyze.py so capture-time
 * enrichment in api/capture.js matches what the Python pipeline produced.
 *
 * Pure string matching — no network calls, safe to run synchronously
 * inside the capture handler.
 */

// ─── Platform → format tag (by URL hostname) ──────────────────────────
const FORMAT_MAP = {
  'instagram.com': 'instagram',
  'x.com': 'tweet',
  'twitter.com': 'tweet',
  'pinterest.com': 'pinterest',
  'behance.net': 'behance',
  'dribbble.com': 'dribbble',
  'youtube.com': 'youtube',
  'youtu.be': 'youtube',
  'vimeo.com': 'vimeo',
  'codepen.io': 'codepen',
  'codesandbox.io': 'codesandbox',
  'github.com': 'github',
  'medium.com': 'article',
  'substack.com': 'article',
  'figma.com': 'figma',
  'tiktok.com': 'tiktok',
  'linkedin.com': 'linkedin',
  'reddit.com': 'reddit',
  'producthunt.com': 'producthunt',
  'awwwards.com': 'awwwards',
  'are.na': 'arena',
  'notion.so': 'notion',
  'notion.site': 'notion',
};

// ─── Tool tags (keyword in text → tool slug) ──────────────────────────
const TOOL_RULES = {
  figma: 'figma',
  framer: 'framer',
  webflow: 'webflow',
  'sketch app': 'sketch',
  'sketch design': 'sketch',
  'adobe illustrator': 'illustrator',
  illustrator: 'illustrator',
  photoshop: 'photoshop',
  'after effects': 'after-effects',
  aftereffects: 'after-effects',
  premiere: 'premiere',
  'final cut': 'final-cut-pro',
  procreate: 'procreate',
  blender: 'blender',
  'cinema 4d': 'cinema-4d',
  cinema4d: 'cinema-4d',
  c4d: 'cinema-4d',
  midjourney: 'midjourney',
  'stable diffusion': 'stable-diffusion',
  'dall-e': 'dall-e',
  dalle: 'dall-e',
  chatgpt: 'chatgpt',
  openai: 'openai',
  spline: 'spline',
  rive: 'rive',
  lottie: 'lottie',
  gsap: 'gsap',
  'three.js': 'three-js',
  threejs: 'three-js',
  react: 'react',
  nextjs: 'nextjs',
  'next.js': 'nextjs',
  tailwind: 'tailwind',
  swift: 'swift',
  swiftui: 'swiftui',
  visionos: 'visionos',
  'vision pro': 'vision-pro',
  unity: 'unity',
  unreal: 'unreal-engine',
  notion: 'notion',
  obsidian: 'obsidian',
  linear: 'linear',
  airtable: 'airtable',
  zapier: 'zapier',
  wordpress: 'wordpress',
  shopify: 'shopify',
  vercel: 'vercel',
  supabase: 'supabase',
  firebase: 'firebase',
  claude: 'claude',
  cursor: 'cursor',
  'p5.js': 'p5-js',
  'd3.js': 'd3-js',
  'anime.js': 'anime-js',
  origami: 'origami-studio',
  principle: 'principle',
  protopie: 'protopie',
  marvel: 'marvel',
  invision: 'invision',
  zeplin: 'zeplin',
  github: 'github',
  lightroom: 'lightroom',
  'davinci resolve': 'davinci-resolve',
  capcut: 'capcut',
  canva: 'canva',
};

// ─── Style tags ───────────────────────────────────────────────────────
const STYLE_RULES = {
  minimalist: 'minimalist',
  minimal: 'minimalist',
  brutalist: 'brutalist',
  editorial: 'editorial',
  retro: 'retro',
  vintage: 'vintage',
  futuristic: 'futuristic',
  geometric: 'geometric',
  organic: 'organic',
  flat: 'flat',
  skeuomorphic: 'skeuomorphic',
  neumorphic: 'neumorphism',
  glassmorphism: 'glassmorphism',
  gradient: 'gradient',
  monochrome: 'monochrome',
  isometric: 'isometric',
  '3d': '3d',
  'hand-drawn': 'hand-drawn',
  'hand drawn': 'hand-drawn',
  handwritten: 'handwritten',
  grunge: 'grunge',
  clean: 'clean',
  bold: 'bold',
  serif: 'serif',
  'sans-serif': 'sans-serif',
  display: 'display',
  script: 'script',
  calligraphy: 'calligraphic',
  pixel: 'pixel-art',
  voxel: 'voxel',
  wireframe: 'wireframe',
  'low-poly': 'low-poly',
  abstract: 'abstract',
  swiss: 'swiss-style',
  bauhaus: 'bauhaus',
  'art deco': 'art-deco',
  'art nouveau': 'art-nouveau',
  psychedelic: 'psychedelic',
  neon: 'neon',
  glitch: 'glitch',
  halftone: 'halftone',
  stipple: 'stipple',
  watercolor: 'watercolor',
  collage: 'collage',
  photorealistic: 'photorealistic',
  cinematic: 'cinematic',
  animated: 'animated',
  interactive: 'interactive',
  responsive: 'responsive',
  modular: 'modular',
  grid: 'grid-based',
  typographic: 'typographic',
  experimental: 'experimental',
  generative: 'generative',
  procedural: 'procedural',
  parametric: 'parametric',
  'data-driven': 'data-driven',
};

// ─── Mood tags ────────────────────────────────────────────────────────
const MOOD_RULES = {
  dark: 'dark',
  light: 'light',
  vibrant: 'vibrant',
  colorful: 'vibrant',
  calm: 'calm',
  serene: 'calm',
  peaceful: 'calm',
  elegant: 'elegant',
  luxurious: 'luxurious',
  luxury: 'luxurious',
  premium: 'premium',
  playful: 'playful',
  fun: 'playful',
  whimsical: 'whimsical',
  energetic: 'energetic',
  dynamic: 'dynamic',
  professional: 'professional',
  corporate: 'corporate',
  friendly: 'friendly',
  warm: 'warm',
  cool: 'cool',
  moody: 'moody',
  dramatic: 'dramatic',
  mysterious: 'mysterious',
  dreamy: 'dreamy',
  nostalgic: 'nostalgic',
  techy: 'techy',
  craft: 'crafted',
  artisan: 'crafted',
  handmade: 'crafted',
  raw: 'raw',
  subtle: 'subtle',
  delicate: 'delicate',
};

// ─── Location tags (city/country words in free text) ─────────────────
const LOCATION_RULES = {
  tokyo: 'japan',
  japan: 'japan',
  japanese: 'japan',
  india: 'india',
  indian: 'india',
  mumbai: 'india',
  bangalore: 'india',
  delhi: 'india',
  london: 'uk',
  british: 'uk',
  england: 'uk',
  berlin: 'germany',
  german: 'germany',
  paris: 'france',
  french: 'france',
  'new york': 'usa',
  nyc: 'usa',
  'san francisco': 'usa',
  california: 'usa',
  'los angeles': 'usa',
  seattle: 'usa',
  portland: 'usa',
  brooklyn: 'usa',
  vancouver: 'canada',
  toronto: 'canada',
  canada: 'canada',
  amsterdam: 'netherlands',
  dutch: 'netherlands',
  copenhagen: 'denmark',
  danish: 'denmark',
  stockholm: 'sweden',
  swedish: 'sweden',
  helsinki: 'finland',
  finnish: 'finland',
  milan: 'italy',
  italian: 'italy',
  zurich: 'switzerland',
  swiss: 'switzerland',
  seoul: 'south-korea',
  korean: 'south-korea',
  singapore: 'singapore',
  sydney: 'australia',
  australian: 'australia',
  melbourne: 'australia',
  oslo: 'norway',
  norwegian: 'norway',
  barcelona: 'spain',
  spanish: 'spain',
  lisbon: 'portugal',
  portuguese: 'portugal',
  prague: 'czech-republic',
  jakarta: 'indonesia',
  bangkok: 'thailand',
  dubai: 'uae',
  'são paulo': 'brazil',
  'sao paulo': 'brazil',
  brazilian: 'brazil',
  mexico: 'mexico',
  china: 'china',
  chinese: 'china',
  beijing: 'china',
  shanghai: 'china',
  taiwan: 'taiwan',
  taipei: 'taiwan',
};

// ─── TLD → location (weak signal, lower weight) ──────────────────────
const TLD_LOCATION = {
  '.jp': 'japan',
  '.de': 'germany',
  '.fr': 'france',
  '.uk': 'uk',
  '.co.uk': 'uk',
  '.it': 'italy',
  '.nl': 'netherlands',
  '.se': 'sweden',
  '.dk': 'denmark',
  '.no': 'norway',
  '.fi': 'finland',
  '.ch': 'switzerland',
  '.kr': 'south-korea',
  '.au': 'australia',
  '.br': 'brazil',
  '.mx': 'mexico',
  '.cn': 'china',
  '.tw': 'taiwan',
  '.sg': 'singapore',
  '.pt': 'portugal',
};

// ─── Stop words for subject-keyword mining ───────────────────────────
const STOP_WORDS = new Set([
  'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
  'of', 'with', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been',
  'has', 'have', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
  'should', 'may', 'might', 'can', 'this', 'that', 'it', 'its', 'not',
  'no', 'so', 'if', 'as', 'into', 'about', 'up', 'out', 'all', 'more',
  'also', 'how', 'what', 'when', 'where', 'who', 'which', 'than', 'then',
  'just', 'like', 'over', 'such', 'very', 'your', 'my', 'our', 'their',
  'new', 'one', 'two', 'three', 'four', 'five', 'first', 'last', 'most',
  'other', 'some', 'any', 'each', 'every', 'both', 'few', 'many',
  'inside', 'story', 'part', 'page', 'view', 'click', 'here', 'see',
  'use', 'using', 'used', 'make', 'made', 'get', 'got', 'know',
  'www', 'http', 'https', 'com', 'net', 'org',
  // HTML artifacts (shouldn't surface after entity decode, defence in depth)
  'middot', 'nbsp', 'amp', 'quot',
]);

// Extra stops only applied to description mining (keeps title mining tighter)
const STOP_WORDS_EXT = new Set([
  'this', 'that', 'with', 'from', 'have', 'been', 'will', 'about',
  'more', 'also', 'your', 'their', 'which', 'when', 'what', 'where',
  'years', 'building', 'based', 'tool', 'looking', 'find', 'work',
  'best', 'need', 'help', 'want', 'take', 'give', 'keep', 'thing',
]);

// Platform words derived from FORMAT_MAP (so we don't re-surface "behance" etc.)
const PLATFORM_NOISE = new Set(
  Object.keys(FORMAT_MAP).map(d => d.split('.')[0]).concat([
    'codesandbox', 'codepen', 'github', 'medium',
  ])
);

// ─── Core matcher ─────────────────────────────────────────────────────

function wordBoundary(pattern) {
  // re-escape regex metacharacters in the pattern
  const escaped = pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`\\b${escaped}\\b`, 'i');
}

/**
 * Run the rule tables against free text and return new tag objects.
 * Does NOT mutate existingNames — returns only the delta to add.
 */
function runRuleEnrichment(text, existingNames, { domain } = {}) {
  const added = new Set(existingNames);
  const tags = [];
  const lower = (text || '').toLowerCase();

  function addTag(tag, category, weight) {
    if (added.has(tag)) return;
    added.add(tag);
    tags.push({ tag, category, weight });
  }

  for (const [pattern, tool] of Object.entries(TOOL_RULES)) {
    if (wordBoundary(pattern).test(lower)) addTag(tool, 'tool', 0.7);
  }
  for (const [pattern, style] of Object.entries(STYLE_RULES)) {
    if (wordBoundary(pattern).test(lower)) addTag(style, 'style', 0.65);
  }
  for (const [pattern, mood] of Object.entries(MOOD_RULES)) {
    if (wordBoundary(pattern).test(lower)) addTag(mood, 'mood', 0.55);
  }
  for (const [pattern, loc] of Object.entries(LOCATION_RULES)) {
    if (wordBoundary(pattern).test(lower)) addTag(loc, 'location', 0.6);
  }

  // TLD fallback (weaker)
  if (domain) {
    for (const [tld, loc] of Object.entries(TLD_LOCATION)) {
      if (domain.endsWith(tld)) addTag(loc, 'location', 0.3);
    }
  }

  return tags;
}

/**
 * Mine subject keywords from free text.
 *   text        — title or description, already entity-decoded
 *   minLen      — minimum word length (3 for title, 4 for description)
 *   limit       — how many keywords to keep
 *   weightStart — first keyword's weight (tapers down)
 *   weightStep  — per-keyword decay
 *   weightFloor — min weight
 *   extraStops  — set of extra words to reject (existing tags, platform noise…)
 */
function mineSubjectKeywords(text, {
  minLen = 3,
  limit = 5,
  weightStart = 0.8,
  weightStep = 0.1,
  weightFloor = 0.5,
  extraStops = new Set(),
} = {}) {
  if (!text) return [];
  const pattern = new RegExp(`[a-zA-Z]{${minLen},}`, 'g');
  const words = (text.toLowerCase().match(pattern) || []);
  const seen = new Set();
  const out = [];
  for (const w of words) {
    if (seen.has(w)) continue;
    if (STOP_WORDS.has(w) || extraStops.has(w) || PLATFORM_NOISE.has(w)) continue;
    seen.add(w);
    const weight = Math.max(weightFloor, +(weightStart - out.length * weightStep).toFixed(2));
    out.push({ tag: w, category: 'subject', weight });
    if (out.length >= limit) break;
  }
  return out;
}

/**
 * Pick the format tag for a source URL.
 * Falls back to 'website' for any URL we don't recognize, 'text-note' for
 * pure text captures.
 */
function formatTagFor({ sourceUrl, domain }) {
  if (!sourceUrl) return { tag: 'text-note', category: 'format', weight: 0.4 };
  if (domain) {
    const hit = FORMAT_MAP[domain.replace(/^www\./, '')];
    if (hit) return { tag: hit, category: 'format', weight: 0.5 };
  }
  return { tag: 'website', category: 'format', weight: 0.4 };
}

module.exports = {
  FORMAT_MAP,
  TOOL_RULES,
  STYLE_RULES,
  MOOD_RULES,
  LOCATION_RULES,
  TLD_LOCATION,
  STOP_WORDS,
  STOP_WORDS_EXT,
  PLATFORM_NOISE,
  runRuleEnrichment,
  mineSubjectKeywords,
  formatTagFor,
};
