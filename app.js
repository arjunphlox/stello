/* === Stello — App Logic === */

(function () {
  'use strict';

  // --- Icons (Phosphor regular, 16x16) ---
  const ICONS = {
    'gear': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M128,80a48,48,0,1,0,48,48A48.05,48.05,0,0,0,128,80Zm0,80a32,32,0,1,1,32-32A32,32,0,0,1,128,160Zm88-29.84q.06-2.16,0-4.32l14.92-18.64a8,8,0,0,0,1.48-7.06,107.21,107.21,0,0,0-10.88-26.25,8,8,0,0,0-6-3.93l-23.72-2.64q-1.48-1.56-3-3L186,40.54a8,8,0,0,0-3.94-6,107.71,107.71,0,0,0-26.25-10.87,8,8,0,0,0-7.06,1.49L130.16,40Q128,40,125.84,40L107.2,25.11a8,8,0,0,0-7.06-1.48A107.6,107.6,0,0,0,73.89,34.51a8,8,0,0,0-3.93,6L67.32,64.27q-1.56,1.49-3,3L40.54,70a8,8,0,0,0-6,3.94,107.71,107.71,0,0,0-10.87,26.25,8,8,0,0,0,1.49,7.06L40,125.84Q40,128,40,130.16L25.11,148.8a8,8,0,0,0-1.48,7.06,107.21,107.21,0,0,0,10.88,26.25,8,8,0,0,0,6,3.93l23.72,2.64q1.49,1.56,3,3L70,215.46a8,8,0,0,0,3.94,6,107.71,107.71,0,0,0,26.25,10.87,8,8,0,0,0,7.06-1.49L125.84,216q2.16.06,4.32,0l18.64,14.92a8,8,0,0,0,7.06,1.48,107.21,107.21,0,0,0,26.25-10.88,8,8,0,0,0,3.93-6l2.64-23.72q1.56-1.48,3-3L215.46,186a8,8,0,0,0,6-3.94,107.71,107.71,0,0,0,10.87-26.25,8,8,0,0,0-1.49-7.06Zm-16.1-6.5a73.93,73.93,0,0,1,0,8.68,8,8,0,0,0,1.74,5.48l14.19,17.73a91.57,91.57,0,0,1-6.23,15L187,173.11a8,8,0,0,0-5.1,2.64,74.11,74.11,0,0,1-6.14,6.14,8,8,0,0,0-2.64,5.1l-2.51,22.58a91.32,91.32,0,0,1-15,6.23l-17.74-14.19a8,8,0,0,0-5-1.75h-.48a73.93,73.93,0,0,1-8.68,0,8,8,0,0,0-5.48,1.74L100.45,215.8a91.57,91.57,0,0,1-15-6.23L82.89,187a8,8,0,0,0-2.64-5.1,74.11,74.11,0,0,1-6.14-6.14,8,8,0,0,0-5.1-2.64L46.43,170.6a91.32,91.32,0,0,1-6.23-15l14.19-17.74a8,8,0,0,0,1.74-5.48,73.93,73.93,0,0,1,0-8.68,8,8,0,0,0-1.74-5.48L40.2,100.45a91.57,91.57,0,0,1,6.23-15L69,82.89a8,8,0,0,0,5.1-2.64,74.11,74.11,0,0,1,6.14-6.14A8,8,0,0,0,82.89,69L85.4,46.43a91.32,91.32,0,0,1,15-6.23l17.74,14.19a8,8,0,0,0,5.48,1.74,73.93,73.93,0,0,1,8.68,0,8,8,0,0,0,5.48-1.74L155.55,40.2a91.57,91.57,0,0,1,15,6.23L173.11,69a8,8,0,0,0,2.64,5.1,74.11,74.11,0,0,1,6.14,6.14,8,8,0,0,0,5.1,2.64l22.58,2.51a91.32,91.32,0,0,1,6.23,15l-14.19,17.74A8,8,0,0,0,199.87,123.66Z"/></svg>',
    'plus': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M224,128a8,8,0,0,1-8,8H136v80a8,8,0,0,1-16,0V136H40a8,8,0,0,1,0-16h80V40a8,8,0,0,1,16,0v80h80A8,8,0,0,1,224,128Z"/></svg>',
    'funnel': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M230.6,49.53A15.81,15.81,0,0,0,216,40H40A16,16,0,0,0,28.19,66.76l.08.09L96,139.17V216a16,16,0,0,0,24.87,13.32l32-21.34A16,16,0,0,0,160,194.66V139.17l67.74-72.32.08-.09A15.8,15.8,0,0,0,230.6,49.53ZM40,56h0Zm106.18,74.58A8,8,0,0,0,144,136v58.66L112,216V136a8,8,0,0,0-2.16-5.47L40,56H216Z"/></svg>',
    'x': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M205.66,194.34a8,8,0,0,1-11.32,11.32L128,139.31,61.66,205.66a8,8,0,0,1-11.32-11.32L116.69,128,50.34,61.66A8,8,0,0,1,61.66,50.34L128,116.69l66.34-66.35a8,8,0,0,1,11.32,11.32L139.31,128Z"/></svg>',
    'frame-corners': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M200,80v32a8,8,0,0,1-16,0V88H160a8,8,0,0,1,0-16h32A8,8,0,0,1,200,80ZM96,168H72V144a8,8,0,0,0-16,0v32a8,8,0,0,0,8,8H96a8,8,0,0,0,0-16ZM232,56V200a16,16,0,0,1-16,16H40a16,16,0,0,1-16-16V56A16,16,0,0,1,40,40H216A16,16,0,0,1,232,56ZM216,200V56H40V200H216Z"/></svg>',
    'arrow-up-right': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M200,64V168a8,8,0,0,1-16,0V83.31L69.66,197.66a8,8,0,0,1-11.32-11.32L172.69,72H88a8,8,0,0,1,0-16H192A8,8,0,0,1,200,64Z"/></svg>',
    'magnifying-glass': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M229.66,218.34l-50.07-50.06a88.11,88.11,0,1,0-11.31,11.31l50.06,50.07a8,8,0,0,0,11.32-11.32ZM40,112a72,72,0,1,1,72,72A72.08,72.08,0,0,1,40,112Z"/></svg>',
    'caret-down': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M213.66,101.66l-80,80a8,8,0,0,1-11.32,0l-80-80A8,8,0,0,1,53.66,90.34L128,164.69l74.34-74.35a8,8,0,0,1,11.32,11.32Z"/></svg>',
    'caret-up': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M213.66,165.66a8,8,0,0,1-11.32,0L128,91.31,53.66,165.66a8,8,0,0,1-11.32-11.32l80-80a8,8,0,0,1,11.32,0l80,80A8,8,0,0,1,213.66,165.66Z"/></svg>',
    'shuffle': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M237.66,178.34a8,8,0,0,1,0,11.32l-24,24a8,8,0,0,1-11.32-11.32L212.69,192H200.94a72.12,72.12,0,0,1-58.59-30.15l-41.72-58.4A56.1,56.1,0,0,0,55.06,80H32a8,8,0,0,1,0-16H55.06a72.12,72.12,0,0,1,58.59,30.15l41.72,58.4A56.1,56.1,0,0,0,200.94,176h11.75l-10.35-10.34a8,8,0,0,1,11.32-11.32ZM143,107a8,8,0,0,0,11.16-1.86l1.2-1.67A56.1,56.1,0,0,1,200.94,80h11.75L202.34,90.34a8,8,0,0,0,11.32,11.32l24-24a8,8,0,0,0,0-11.32l-24-24a8,8,0,0,0-11.32,11.32L212.69,64H200.94a72.12,72.12,0,0,0-58.59,30.15l-1.2,1.67A8,8,0,0,0,143,107Zm-30,42a8,8,0,0,0-11.16,1.86l-1.2,1.67A56.1,56.1,0,0,1,55.06,176H32a8,8,0,0,0,0,16H55.06a72.12,72.12,0,0,0,58.59-30.15l1.2-1.67A8,8,0,0,0,113,149Z"/></svg>',
    'crosshair': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M232,120H215.63a88.13,88.13,0,0,0-79.63-79.63V24a8,8,0,0,0-16,0V40.37A88.13,88.13,0,0,0,40.37,120H24a8,8,0,0,0,0,16H40.37A88.13,88.13,0,0,0,120,215.63V232a8,8,0,0,0,16,0V215.63A88.13,88.13,0,0,0,215.63,136H232a8,8,0,0,0,0-16ZM128,200a72,72,0,1,1,72-72A72.08,72.08,0,0,1,128,200Zm0-112a40,40,0,1,0,40,40A40,40,0,0,0,128,88Zm0,64a24,24,0,1,1,24-24A24,24,0,0,1,128,152Z"/></svg>',
    'trash': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M216,48H176V40a24,24,0,0,0-24-24H104A24,24,0,0,0,80,40v8H40a8,8,0,0,0,0,16h8V208a16,16,0,0,0,16,16H192a16,16,0,0,0,16-16V64h8a8,8,0,0,0,0-16ZM96,40a8,8,0,0,1,8-8h48a8,8,0,0,1,8,8v8H96Zm96,168H64V64H192ZM112,104v64a8,8,0,0,1-16,0V104a8,8,0,0,1,16,0Zm48,0v64a8,8,0,0,1-16,0V104a8,8,0,0,1,16,0Z"/></svg>',
    'user-circle': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24ZM74.08,197.5a64,64,0,0,1,107.84,0,87.83,87.83,0,0,1-107.84,0ZM96,120a32,32,0,1,1,32,32A32,32,0,0,1,96,120Zm97.76,66.41a79.66,79.66,0,0,0-36.06-28.75,48,48,0,1,0-59.4,0,79.66,79.66,0,0,0-36.06,28.75,88,88,0,1,1,131.52,0Z"/></svg>',
    'sparkle': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M128 20c6 50 28 74 80 80-52 6-74 28-80 80-6-52-28-74-80-80 52-6 74-30 80-80Z"/><path d="M204 156c3 22 12 31 32 34-20 3-29 12-32 34-3-22-12-31-32-34 20-3 29-12 32-34Z"/></svg>',
    'copy': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="none" stroke="currentColor" stroke-width="16" stroke-linejoin="round"><rect x="88" y="88" width="128" height="128" rx="12"/><path d="M168 88V52a12 12 0 0 0-12-12H52a12 12 0 0 0-12 12v104a12 12 0 0 0 12 12h36"/></svg>',
    'warning': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="none" stroke="currentColor" stroke-width="16" stroke-linejoin="round" stroke-linecap="round"><path d="M128 32 16 216h224Z"/><path d="M128 104v48"/><circle cx="128" cy="184" r="4" fill="currentColor"/></svg>',
    'share': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="none" stroke="currentColor" stroke-width="16" stroke-linecap="round" stroke-linejoin="round"><path d="M176 96h24a8 8 0 0 1 8 8v104a8 8 0 0 1-8 8H56a8 8 0 0 1-8-8V104a8 8 0 0 1 8-8h24"/><path d="M128 24v112M88 64l40-40 40 40"/></svg>',
    'link': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="none" stroke="currentColor" stroke-width="16" stroke-linecap="round"><path d="M136 72l14-14a44 44 0 0 1 62 62l-30 30a44 44 0 0 1-62 0"/><path d="M120 184l-14 14a44 44 0 0 1-62-62l30-30a44 44 0 0 1 62 0"/></svg>',
    'download': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="none" stroke="currentColor" stroke-width="16" stroke-linecap="round" stroke-linejoin="round"><circle cx="128" cy="128" r="96"/><path d="M128 80v88M92 132l36 36 36-36"/></svg>',
    'eye': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M247.31 124.76c-.35-.79-8.82-19.58-27.65-38.41C194.57 61.26 162.88 48 128 48S61.43 61.26 36.34 86.35C17.51 105.18 9 124 8.69 124.76a8 8 0 0 0 0 6.5c.35.79 8.82 19.57 27.65 38.4C61.43 194.74 93.12 208 128 208s66.57-13.26 91.66-38.34c18.83-18.83 27.3-37.61 27.65-38.4a8 8 0 0 0 0-6.5ZM128 168a40 40 0 1 1 40-40 40 40 0 0 1-40 40Z"/></svg>',
    'play': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M232.4 114.49 88.32 26.35a16 16 0 0 0-16.2-.3A15.86 15.86 0 0 0 64 39.87v176.26a15.94 15.94 0 0 0 16 15.87 16.12 16.12 0 0 0 8.32-2.35l144.08-88.14a15.68 15.68 0 0 0 0-27Z"/></svg>',
    'stack': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="none" stroke="currentColor" stroke-width="18" stroke-linejoin="round"><rect x="72" y="72" width="144" height="144" rx="16"/><path d="M184 40H56a16 16 0 0 0-16 16v128"/></svg>',
    'dots-three': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M140,128a12,12,0,1,1-12-12A12,12,0,0,1,140,128ZM48,116a12,12,0,1,0,12,12A12,12,0,0,0,48,116Zm160,0a12,12,0,1,0,12,12A12,12,0,0,0,208,116Z"/></svg>',
  };
  function icon(name) { return ICONS[name] || ''; }

  // --- State ---
  let allItems = [];
  let itemsBySlug = {};      // slug -> item lookup
  let activeTags = [];      // [{tag, category}]
  let needsReviewOnly = false;
  let searchQuery = '';
  let relatedIndex = {};     // slug -> Set of related slugs

  // --- Category colors (for pills) ---
  const CAT_CLASS = {
    format: 'tag-format',
    collection: 'tag-domain',
    domain: 'tag-domain',
    style: 'tag-style',
    subject: 'tag-subject',
    tool: 'tag-tool',
    location: 'tag-location',
    mood: 'tag-mood',
    color: 'tag-color',
  };

  // Warm earthy hues for placeholders
  const PLACEHOLDER_HUES = [18, 80, 38, 140, 25, 45, 12, 100];

  // Color name → CSS color for tag swatches
  const COLOR_MAP = {
    // Reds / pinks
    red: '#c0392b', crimson: '#dc143c', burgundy: '#800020', maroon: '#800000',
    scarlet: '#ff2400', ruby: '#e0115f', cherry: '#de3163', rose: '#ff007f',
    blush: '#de5d83', coral: '#ff7f50', salmon: '#fa8072', pink: '#e8909c',
    magenta: '#c20078', fuchsia: '#c154c1', mauve: '#e0b0ff', dusty_rose: '#dcae96',
    'dusty-rose': '#dcae96', raspberry: '#e30b5c', wine: '#722f37', terracotta: '#e2725b',
    // Oranges
    orange: '#e67e22', tangerine: '#ff9966', peach: '#ffcba4', apricot: '#fbceb1',
    amber: '#ffbf00', rust: '#b7410e', copper: '#b87333', burnt_orange: '#cc5500',
    'burnt-orange': '#cc5500', sienna: '#a0522d',
    // Yellows
    yellow: '#f1c40f', gold: '#ffd700', golden: '#daa520', mustard: '#e1ad01',
    lemon: '#fff44f', cream: '#fffdd0', butter: '#ffff99', saffron: '#f4c430',
    honey: '#eb9605', wheat: '#f5deb3', sand: '#c2b280',
    // Greens
    green: '#27ae60', emerald: '#50c878', lime: '#32cd32', olive: '#808000',
    sage: '#bcb88a', mint: '#98ff98', teal: '#008080', forest: '#228b22',
    'forest-green': '#228b22', jade: '#00a86b', chartreuse: '#7fff00',
    moss: '#8a9a5b', avocado: '#568203', pistachio: '#93c572', seafoam: '#93e9be',
    // Blues
    blue: '#2980b9', navy: '#001f3f', cobalt: '#0047ab', royal: '#4169e1',
    'royal-blue': '#4169e1', sky: '#87ceeb', 'sky-blue': '#87ceeb',
    azure: '#007fff', cerulean: '#007ba7', turquoise: '#40e0d0', aqua: '#00ffff',
    indigo: '#4b0082', periwinkle: '#ccccff', slate: '#708090', 'slate-blue': '#6a5acd',
    steel: '#4682b4', 'steel-blue': '#4682b4', powder: '#b0e0e6', 'powder-blue': '#b0e0e6',
    // Purples
    purple: '#8e44ad', violet: '#7f00ff', lavender: '#b57edc', plum: '#8e4585',
    lilac: '#c8a2c8', amethyst: '#9966cc', orchid: '#da70d6', grape: '#6f2da8',
    eggplant: '#614051', mulberry: '#c54b8c',
    // Browns
    brown: '#795548', chocolate: '#7b3f00', coffee: '#6f4e37', mocha: '#967969',
    tan: '#d2b48c', taupe: '#483c32', caramel: '#ffd59a', cinnamon: '#d2691e',
    walnut: '#773f1a', chestnut: '#954535', espresso: '#3c1414', umber: '#635147',
    // Neutrals
    black: '#1a1a1a', charcoal: '#36454f', 'dark-gray': '#555555',
    gray: '#888888', grey: '#888888', silver: '#c0c0c0', 'light-gray': '#d3d3d3',
    white: '#f5f5f5', ivory: '#fffff0', bone: '#e3dac9', pearl: '#eae0c8',
    beige: '#f5f5dc', off_white: '#faf0e6', 'off-white': '#faf0e6',
  };

  // Returns the hex color of an item's highest-weighted `color` tag, or '#ffffff'.
  function dominantColor(item) {
    if (!item || !item.tags) return '#ffffff';
    const colorTags = item.tags.filter(t => t.category === 'color');
    if (!colorTags.length) return '#ffffff';
    const top = colorTags.reduce((a, b) => (b.weight > a.weight ? b : a));
    const key = top.tag;
    return COLOR_MAP[key] || COLOR_MAP[key.replace(/[-_\s]/g, '_')] || '#ffffff';
  }

  function hexToRgba(hex, a) {
    const clean = hex.replace('#', '');
    const r = parseInt(clean.slice(0, 2), 16);
    const g = parseInt(clean.slice(2, 4), 16);
    const b = parseInt(clean.slice(4, 6), 16);
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  }

  // --- Theme Manager ---
  // Mirrors the Mac's Theme.swift: mode is System / Light / Dark (System follows
  // the OS), and each mode has its own six accents: bright ones in dark, muted
  // ones in light. One accent is stored; when it isn't in the current mode's
  // set, that mode's default shows (amber in dark, iris in light).
  const ThemeManager = {
    STORAGE_KEY: 'stello.theme',
    defaults: { mode: 'dark', accent: 'amber' },
    ACCENTS: {
      dark: ['amber', 'lime', 'yellow', 'grass', 'cyan', 'orange'],
      light: ['iris', 'violet', 'plum', 'indigo', 'teal', 'bronze'],
    },
    // Picker dots: step 9 of each accent (the same in both modes).
    SWATCH: {
      amber: '#ffc53d', lime: '#bdee63', yellow: '#ffe629', grass: '#46a758', cyan: '#00a2c7', orange: '#f76b15',
      iris: '#5b5bd6', violet: '#6e56cf', plum: '#ab4aba', indigo: '#3e63dd', teal: '#12a594', bronze: '#a18072',
    },
    _mql: window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null,

    load() {
      try {
        const raw = localStorage.getItem(this.STORAGE_KEY);
        return raw ? { ...this.defaults, ...JSON.parse(raw) } : { ...this.defaults };
      } catch { return { ...this.defaults }; }
    },

    // 'light' | 'dark' — what the page paints right now.
    resolvedMode(prefs = this.load()) {
      if (prefs.mode === 'light' || prefs.mode === 'dark') return prefs.mode;
      return this._mql && !this._mql.matches ? 'light' : 'dark';
    },

    resolvedAccent(prefs = this.load(), mode = this.resolvedMode(prefs)) {
      const set = this.ACCENTS[mode];
      return set.includes(prefs.accent) ? prefs.accent : set[0];
    },

    apply(prefs) {
      const mode = this.resolvedMode(prefs);
      document.documentElement.setAttribute('data-theme', mode);
      document.documentElement.setAttribute('data-accent', this.resolvedAccent(prefs, mode));
    },

    save(prefs) {
      try { localStorage.setItem(this.STORAGE_KEY, JSON.stringify(prefs)); } catch {}
    },

    setMode(mode) {
      const prefs = this.load();
      prefs.mode = mode;
      this.save(prefs);
      this.apply(prefs);
    },

    setAccent(accent) {
      const prefs = this.load();
      prefs.accent = accent;
      this.save(prefs);
      this.apply(prefs);
    },

    init() {
      this.apply(this.load());
      // System mode follows the OS live, like the Mac app.
      if (this._mql) {
        const onChange = () => {
          const prefs = this.load();
          if (prefs.mode !== 'system') return;
          this.apply(prefs);
          document.dispatchEvent(new CustomEvent('stello:themechange'));
        };
        if (this._mql.addEventListener) this._mql.addEventListener('change', onChange);
        else if (this._mql.addListener) this._mql.addListener(onChange);
      }
    }
  };

  // --- Auth-aware fetch wrapper ---
  function apiFetch(url, opts = {}) {
    if (window.Stello) return Stello.apiFetch(url, opts);
    return fetch(url, opts); // local dev fallback
  }

  // --- Login arrival fallback (GSAP) ---
  // When the inline <head> gate in index.html detects a browser without
  // cross-document view-transition support, it adds .arriving-from-login
  // to <html>. This helper measures the natural compact state, then tweens
  // the header's hero footprint back to compact — mimicking the native
  // @view-transition morph (see ::view-transition-* rules in style.css).
  function runLoginArrivalFallback() {
    const html = document.documentElement;
    if (!html.classList.contains('arriving-from-login')) return;

    const header = document.querySelector('.header');
    if (!header) { html.classList.remove('arriving-from-login'); return; }

    // Reduced motion — or GSAP failed to load: snap straight to the
    // compact state, skip the tween.
    const reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced || typeof window.gsap === 'undefined') {
      html.classList.remove('arriving-from-login');
      return;
    }

    // Measure the natural compact state by briefly removing the hero class.
    // Same tick, no paint between — offsetHeight forces layout only.
    html.classList.remove('arriving-from-login');
    const naturalHeight = header.offsetHeight;
    const naturalPad = parseFloat(getComputedStyle(header).paddingTop) + 'px';
    html.classList.add('arriving-from-login');

    // Parallel tween matching ::view-transition-old/new durations in
    // style.css: header 275ms, root (body opacity) 225ms, same ease.
    const ease = 'cubic-bezier(0.2, 0, 0, 1)';
    const tl = window.gsap.timeline({
      onComplete: () => {
        window.gsap.set([header, document.body], { clearProps: 'all' });
        html.classList.remove('arriving-from-login');
      }
    });
    tl.to(header, { height: naturalHeight, padding: naturalPad, duration: 0.275, ease }, 0);
    tl.to(document.body, { opacity: 1, duration: 0.225, ease }, 0);
  }

  // --- DOM refs ---
  const $grid = document.getElementById('masonry-grid');
  const $search = document.getElementById('search-input');
  const $activeFilters = document.getElementById('active-filters');
  const $headerCount = document.getElementById('header-count');
  // Filter UI elements live inside the tool panel when open; looked up dynamically.
  const $drawer = () => document.getElementById('filter-tag-drawer');

  // --- Version ---
  const APP_VERSION = '2026.001';

  // --- Boot ---
  async function init() {
    ThemeManager.init();

    // One-shot "just logged in" flag from ?welcome=1. Drives the post-login
    // stagger reveal defined in style.css. Stripped from the URL so a reload
    // doesn't replay the animation.
    try {
      const params = new URLSearchParams(window.location.search);
      if (params.has('welcome')) {
        // If the inline <head> gate in index.html flagged this browser as
        // lacking cross-document view-transition support, drive the header
        // morph with GSAP instead. Runs before .just-logged-in so the hero
        // footprint is in place while the stagger timers tick.
        runLoginArrivalFallback();
        document.body.classList.add('just-logged-in');
        params.delete('welcome');
        const qs = params.toString();
        const clean = window.location.pathname + (qs ? '?' + qs : '') + window.location.hash;
        window.history.replaceState(null, '', clean);
        // Remove the flag after the longest animation finishes so it doesn't
        // linger on future grid re-renders.
        setTimeout(() => document.body.classList.remove('just-logged-in'), 900);
      }
    } catch (e) { /* ignore — animation is nice-to-have */ }

    // Auth guard — Stello client is required for multi-tenant data
    if (!window.Stello) {
      console.error('Stello auth module failed to load');
      return;
    }
    const session = await Stello.requireAuth();
    if (!session) return; // redirecting to login
    Stello.initAuthListener();

    // Load items from the Worker (/api/items), paging through results.
    // First-page-first: render with the most recent 1000 items immediately,
    // then stream older history in the background. Subsequent pages cover
    // older weeks that are collapsed by default, so their headers can be
    // appended without disturbing the already-rendered first weeks.
    const PAGE = 1000;

    async function fetchItemsPage(from) {
      const body = await Stello.apiGet(`/api/items?offset=${from}&limit=${PAGE}`);
      if (!body) {
        console.error('Failed to load items');
        return [];
      }
      return body.items || [];
    }

    const firstPage = await fetchItemsPage(0);
    allItems = firstPage.map(normalizeItem);
    sortItemsByAddedAt(allItems);
    itemsBySlug = {};
    allItems.forEach(item => { itemsBySlug[item.slug] = item; });

    buildRelatedIndex();
    renderStats();
    injectHeaderIcons();
    bindEvents();
    startGridColsObserver();   // sizes the columns, then renders the grid
    PanelManager.init();
    CardMenu.init();

    // Background-stream remaining pages. Only runs if the first page hit the
    // limit — small libraries are done in a single round trip.
    if (firstPage.length === PAGE) {
      (async () => {
        for (let from = PAGE; ; from += PAGE) {
          const page = await fetchItemsPage(from);
          if (page.length === 0) break;
          const normalized = page.map(normalizeItem);
          allItems = allItems.concat(normalized);
          normalized.forEach(item => { itemsBySlug[item.slug] = item; });
          if (page.length < PAGE) break;
        }
        sortItemsByAddedAt(allItems);
        buildRelatedIndex();
        renderStats();
        appendOlderWeeks();
        // Re-run dimensions backfill now that older pages are in memory.
        // Use setTimeout rather than requestIdleCallback because the
        // initial backfill keeps the main thread fairly busy (image
        // probes + dimension writes), so an idle callback can be starved.
        // backfillImageDimensions is idempotent and self-locking so
        // overlapping calls coalesce safely.
        setTimeout(() => backfillImageDimensions(), 500);
      })();
    }

    // Kick off silent backfill for items that predate the entity-decode
    // and rule-enrichment fixes. Runs in the background, two concurrent
    // requests at a time, so it doesn't compete with the initial render.
    if (typeof requestIdleCallback === 'function') {
      requestIdleCallback(() => backfillEnrichment(), { timeout: 4000 });
    } else {
      setTimeout(() => backfillEnrichment(), 2500);
    }

    // Backfill image dimensions for legacy items (captured before sharp
    // started storing width/height). Sniffs naturalWidth/naturalHeight
    // from the loaded image and persists via the user's session — the
    // RLS policy `Users can update own items` covers this. After enough
    // sessions every card has explicit width/height, eliminating the
    // column-count reflow that caused thumbnails to fragment across
    // columns.
    if (typeof requestIdleCallback === 'function') {
      requestIdleCallback(() => backfillImageDimensions(), { timeout: 8000 });
    } else {
      setTimeout(() => backfillImageDimensions(), 6000);
    }
  }

  // --- Silent re-enrichment drip for pre-fix items ---
  // Flags an item as needing reprocessing if it's stuck in text_done / pending
  // or if its stored title/summary still contain HTML-entity artifacts from
  // before the decode fix landed.
  function itemNeedsBackfill(item) {
    const status = item.enrichment_status;
    if (status === 'error') return false;            // give up
    // vision_done = image+vision finished; candidates_done = terminal for
    // imageless pages (nothing left to fetch). Anything earlier still has work.
    if (status && status !== 'vision_done' && status !== 'candidates_done') return true;
    const text = (item.title || '') + ' ' + (item.summary || '');
    if (/&#\d|&#x|&amp;|&quot;|&lt;|&gt;/i.test(text)) return true;
    // Vision-done items with no image → nothing to do
    return false;
  }

  async function backfillEnrichment() {
    const queue = allItems.filter(itemNeedsBackfill);
    if (queue.length === 0) return;

    console.log(`[stello] backfill: re-enriching ${queue.length} items`);

    const CONCURRENCY = 2;
    let next = 0;
    let processed = 0;

    async function worker() {
      while (!worker.stop) {
        const slot = next++;
        if (slot >= queue.length) return;
        const item = queue[slot];
        try {
          const res = await apiFetch('/api/reprocess', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ slug: item.slug }),
          });
          if (!res.ok) continue;

          // Refetch the updated row so the UI shows the new tags/image
          // without another round trip.
          const data = (await Stello.apiGet(`/api/item?slug=${encodeURIComponent(item.slug)}`))?.item;
          if (!data) continue;

          const refreshed = normalizeItem(data);
          const idx = allItems.findIndex(i => i.slug === item.slug);
          if (idx >= 0) allItems[idx] = refreshed;
          itemsBySlug[item.slug] = refreshed;

          const cardEl = $grid.querySelector(`.card[data-slug="${item.slug}"]:not(.card-question)`);
          if (cardEl && cardEl.dataset.renderSig !== cardRenderSig(refreshed)) {
            cardEl.outerHTML = renderCard(refreshed, 0);
          }
          PanelManager.refreshItem(item.slug);   // diff-aware; safe to call every pass

          // If reprocess downloaded an image, kick off vision enrichment
          // too. Fire-and-forget; pollForEnrichment handles the UI update.
          if (refreshed.enrichment_status === 'text_done' && refreshed.has_image) {
            apiFetch('/api/enrich', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ slug: item.slug }),
            }).catch(() => {});
            pollForEnrichment(item.slug, { maxAttempts: 12, interval: 4000 });
          }
        } catch { /* move on to the next slot */ }
        processed++;
      }
    }

    const workers = [];
    for (let i = 0; i < CONCURRENCY; i++) workers.push(worker());
    await Promise.all(workers);

    buildRelatedIndex();
    console.log(`[stello] backfill: done (${processed}/${queue.length})`);
  }

  // --- Lazy image-dimensions backfill ---
  // Sniffs naturalWidth/naturalHeight from each legacy image and persists
  // them into items.images[] so subsequent renders emit <img width=W
  // height=H> and the column-count engine never reflows on image-load.
  // Runs at idle priority, two concurrent fetches at a time, capped at
  // 50 items per session to avoid hammering the API on first visit.
  function loadImageDimensions(url) {
    return new Promise(resolve => {
      const probe = new Image();
      let done = false;
      const finish = (val) => { if (done) return; done = true; resolve(val); };
      probe.onload = () => finish({ width: probe.naturalWidth || 0, height: probe.naturalHeight || 0 });
      probe.onerror = () => finish(null);
      probe.src = url;
      // Guard against images that never resolve so we don't hold a worker forever.
      setTimeout(() => finish(null), 8000);
    });
  }

  let dimsBackfillRunning = false;
  let dimsBackfillPending = false;
  async function backfillImageDimensions() {
    if (dimsBackfillRunning) {
      // A call arrived mid-run — likely after background pages added more
      // items. Mark for re-run once the current pass releases the lock.
      dimsBackfillPending = true;
      return;
    }
    if (!window.Stello) return;
    if (!Stello.getUserId()) return;

    // Items qualify if they have a renderable image (either an entry in
    // images[] or just og_image_path from a legacy capture) and that
    // image lacks dimensions. Legacy rows often have only og_image_path,
    // so we synthesise an images[] entry here — same shape as the seeding
    // step in api/item-update.js.
    const queue = allItems.filter(item => {
      if (!item.has_image) return false;
      const imgs = item.images || [];
      const primary = imgs.find(i => i && i.is_primary) || imgs[0];
      if (primary && primary.path) {
        return !(primary.width && primary.height);
      }
      // No images[] entry — fall back to og_image_path. Caller will seed.
      return !!item.og_image_path;
    });
    if (queue.length === 0) return;
    dimsBackfillRunning = true;

    // No per-session cap — runs at idle priority so it's harmless to let
    // the whole queue drain. 4 concurrent fetches is well below R2
    // storage's per-IP rate limits.
    const work = queue;
    const CONCURRENCY = 4;
    let next = 0;
    let processed = 0;

    async function worker() {
      while (true) {
        const slot = next++;
        if (slot >= work.length) return;
        const item = work[slot];
        try {
          let imgs = (item.images || []).slice();
          let primaryIdx = imgs.findIndex(i => i && i.is_primary);
          // Legacy row: synthesise the OG entry into images[] so the
          // dimensions can ride along on the same JSON shape we use for
          // every other image source.
          if (primaryIdx < 0 && (!imgs.length || !imgs[0]?.path)) {
            if (!item.og_image_path) continue;
            imgs = [{ path: item.og_image_path, source: 'og', is_primary: true }];
            primaryIdx = 0;
          }
          const idx = primaryIdx >= 0 ? primaryIdx : 0;
          const entry = imgs[idx];
          if (!entry || !entry.path) continue;

          const dims = await loadImageDimensions(entry.path);
          if (!dims || !dims.width || !dims.height) continue;

          imgs[idx] = { ...entry, width: dims.width, height: dims.height };
          const saved = await Stello.apiFetch('/api/item-dims', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ slug: item.slug, images: imgs }),
          });
          if (!saved.ok) continue;

          // Update in-memory state so subsequent renders pick up the dims.
          item.images = imgs;
          item.image_width = dims.width;
          item.image_height = dims.height;
          itemsBySlug[item.slug] = item;

          // Patch the live <img> attrs in case the card is currently mounted —
          // doesn't change layout (image already loaded), but keeps the DOM
          // accurate and helps tools that introspect it.
          const cardEl = $grid.querySelector(`.card[data-slug="${cssSelectorEscape(item.slug)}"] .card-thumb`);
          if (cardEl) {
            cardEl.setAttribute('width', String(dims.width));
            cardEl.setAttribute('height', String(dims.height));
          }
          processed++;
        } catch { /* keep working */ }
      }
    }

    const workers = [];
    for (let i = 0; i < CONCURRENCY; i++) workers.push(worker());
    await Promise.all(workers);
    dimsBackfillRunning = false;

    if (processed > 0) console.log(`[stello] image-dims backfill: ${processed}/${work.length} items`);

    // If another call arrived mid-run (likely from the background-page
    // loader handing off more items), pick those up now.
    if (dimsBackfillPending) {
      dimsBackfillPending = false;
      backfillImageDimensions();
    }
  }

  function cssSelectorEscape(s) {
    if (window.CSS && CSS.escape) return CSS.escape(s);
    return String(s).replace(/([^a-zA-Z0-9_-])/g, '\\$1');
  }

  /** Normalize an item row from /api/items to match the frontend shape */
  function normalizeItem(row) {
    const tags = parseJsonField(row.tags, []);
    const images = parseJsonField(row.images, []);
    const snippets = parseJsonField(row.snippets, []);
    const enrichment_candidates = parseJsonField(row.enrichment_candidates, {});
    const primary = images.find(i => i && i.is_primary) || images[0] || null;
    const image_path = primary?.path || row.og_image_path || null;
    // When the primary image entry carries width/height (populated by the
    // server-side sharp pipeline), surface them so renderCard can emit them
    // as <img width=W height=H> — locks the card's aspect-ratio slot before
    // pixels arrive, preventing column-count reflow on load.
    const image_width = primary?.width || null;
    const image_height = primary?.height || null;
    return {
      ...row,
      tags,
      images,
      snippets,
      enrichment_candidates,
      has_image: !!image_path,
      image_path,
      image_width,
      image_height,
    };
  }

  function parseJsonField(v, fallback) {
    if (v == null) return fallback;
    if (typeof v === 'string') {
      try { return JSON.parse(v); } catch { return fallback; }
    }
    return v;
  }

  function injectHeaderIcons() {
    document.querySelectorAll('[data-icon]').forEach(el => {
      const name = el.dataset.icon;
      if (name && ICONS[name]) el.innerHTML = icon(name);
    });
  }

  // --- Relatedness Index ---
  // Item B is related to item A if BOTH:
  //   • A and B share a tag in category `format` OR `domain` (category match)
  //   • A and B share ≥ 3 tags with weight ≥ 0.5 (any category)
  // A category match alone isn't enough; tag overlap alone isn't enough.
  function buildRelatedIndex() {
    const slugsByFormat = {};
    const slugsByDomain = {};
    const slugsByHeavyTag = {};

    allItems.forEach(item => {
      item.tags.forEach(t => {
        if (t.category === 'format') {
          (slugsByFormat[t.tag] || (slugsByFormat[t.tag] = [])).push(item.slug);
        }
        if (t.category === 'domain') {
          (slugsByDomain[t.tag] || (slugsByDomain[t.tag] = [])).push(item.slug);
        }
        if (t.weight >= 0.5) {
          const key = t.category + ':' + t.tag;
          (slugsByHeavyTag[key] || (slugsByHeavyTag[key] = [])).push(item.slug);
        }
      });
    });

    relatedIndex = {};
    allItems.forEach(item => {
      // Candidate pool: items sharing the item's format or domain.
      const candidates = new Set();
      item.tags.forEach(t => {
        if (t.category === 'format') {
          (slugsByFormat[t.tag] || []).forEach(slug => {
            if (slug !== item.slug) candidates.add(slug);
          });
        }
        if (t.category === 'domain') {
          (slugsByDomain[t.tag] || []).forEach(slug => {
            if (slug !== item.slug) candidates.add(slug);
          });
        }
      });

      // Tag-overlap counts, scoped to the candidate pool.
      const overlap = {};
      item.tags.forEach(t => {
        if (t.weight < 0.5) return;
        const key = t.category + ':' + t.tag;
        (slugsByHeavyTag[key] || []).forEach(slug => {
          if (slug === item.slug || !candidates.has(slug)) return;
          overlap[slug] = (overlap[slug] || 0) + 1;
        });
      });

      const related = new Set();
      for (const [slug, count] of Object.entries(overlap)) {
        if (count >= 3) related.add(slug);
      }
      relatedIndex[item.slug] = related;
    });
  }

  // --- Stats (inline count) ---
  function renderStats() {
    $headerCount.textContent = allItems.length.toLocaleString();
  }


  // --- Tag Drawer ---
  function collectTags() {
    const map = {};
    allItems.forEach(i => {
      i.tags.forEach(t => {
        if (!map[t.category]) map[t.category] = {};
        map[t.category][t.tag] = (map[t.category][t.tag] || 0) + 1;
      });
    });
    return map;
  }

  // Default: only the first category (collection) is expanded; everything else collapsed.
  let expandedCategories = new Set(['collection']);
  let tagSearchQuery = '';

  const CATEGORY_LABELS = {
    collection: 'Collections', domain: 'Domains', subject: 'Subjects', format: 'Formats',
    tool: 'Tools', style: 'Styles', mood: 'Moods',
    location: 'Locations', color: 'Colors',
  };

  function renderTagDrawer() {
    const el = $drawer();
    if (!el) return;
    const map = collectTags();
    const order = ['collection', 'domain', 'subject', 'format', 'tool', 'style', 'mood', 'location', 'color'];
    const categories = order.filter(c => map[c]);
    Object.keys(map).forEach(c => { if (!categories.includes(c)) categories.push(c); });

    const q = tagSearchQuery.trim().toLowerCase();

    el.innerHTML = categories.map(cat => {
      const entries = Object.entries(map[cat]).sort((a, b) => b[1] - a[1]);
      const filtered = q ? entries.filter(([tag]) => tag.toLowerCase().includes(q)) : entries;
      if (q && filtered.length === 0) return ''; // hide empty sections during search

      // When searching, auto-expand any matching section; otherwise respect toggle state
      const isExpanded = q ? true : expandedCategories.has(cat);
      const label = CATEGORY_LABELS[cat] || (cat.charAt(0).toUpperCase() + cat.slice(1));
      const caret = isExpanded ? icon('caret-up') : icon('caret-down');
      const count = filtered.length;

      const chipsHtml = filtered.map(([tag, count]) => {
        const cls = CAT_CLASS[cat] || 'tag-format';
        const isActive = activeTags.some(a => a.tag === tag && a.category === cat);
        const dot = cat === 'color' ? `<span class="color-dot" style="background:${COLOR_MAP[tag] || COLOR_MAP[tag.replace(/[-_\s]/g, '_')] || '#888'}"></span>` : '';
        return `<span class="tag-chip ${cls}${isActive ? ' active' : ''}" data-tag="${tag}" data-cat="${cat}">${dot}${tag} <span class="chip-count">${count}</span></span>`;
      }).join('');

      return `<div class="tag-category-group${isExpanded ? ' is-expanded' : ''}" data-cat="${cat}">
        <button type="button" class="tag-category-header" data-cat="${cat}" aria-expanded="${isExpanded}">
          <span class="tag-category-label">${label}</span>
          <span class="tag-category-count">${count}</span>
          <span class="tag-category-caret">${caret}</span>
        </button>
        <div class="tag-chips">${chipsHtml}</div>
      </div>`;
    }).join('');
  }

  // --- Search + review (the Mac's ItemSearchBlob / AwaitingReviewFilter) ---
  // Every text the item holds, metadata included, lowercased once per item
  // object (normalizeItem makes a new object on change, so the cache never
  // goes stale).
  const _searchBlobs = new WeakMap();
  function collectStrings(v, out) {
    if (v == null) return;
    if (typeof v === 'string') { if (v) out.push(v); return; }
    if (typeof v === 'number') return;
    if (Array.isArray(v)) { for (const x of v) collectStrings(x, out); return; }
    if (typeof v === 'object') for (const k in v) collectStrings(v[k], out);
  }
  function searchBlob(item) {
    let b = _searchBlobs.get(item);
    if (b !== undefined) return b;
    const parts = [item.title, item.summary, item.author, item.domain, item.body_markdown];
    for (const t of item.tags || []) parts.push(t.tag);
    for (const sn of item.snippets || []) parts.push(sn && sn.text);
    collectStrings(item.enrichment_candidates && item.enrichment_candidates.reasons, parts);
    collectStrings(window.StelloPanel.metaOf(item), parts);
    b = parts.filter(Boolean).join(' ').toLowerCase();
    _searchBlobs.set(item, b);
    return b;
  }

  // Awaiting review: enrichment has run, the item still needs review, and
  // there is something to review (why-save suggestions, or text-only results).
  function isAwaitingReview(item) {
    if (item.needs_review !== true || item.enrichment_status === 'pending') return false;
    if (item.enrichment_status === 'text_done') return true;
    return whySavedSuggestions(item).length > 0;
  }

  // --- Grid ---
  function getFilteredItems() {
    return allItems.filter(item => {
      if (searchQuery && !searchBlob(item).includes(searchQuery.toLowerCase())) return false;
      if (needsReviewOnly && !isAwaitingReview(item)) return false;
      if (selectedWeek && getWeekKey(item.added_at) !== selectedWeek) return false;
      if (activeTags.length > 0) {
        return activeTags.every(at =>
          item.tags.some(t => t.tag === at.tag && t.category === at.category)
        );
      }
      return true;
    });
  }

  function getISOWeek(date) {
    const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
    d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
    const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
    return Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
  }

  function formatWeekLabel(dateStr) {
    if (!dateStr) return null;
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return null;
    const week = getISOWeek(d);
    const month = d.toLocaleDateString('en-US', { month: 'long' });
    return `Week ${week} — ${month}`;
  }

  function getWeekKey(dateStr) {
    if (!dateStr) return 'undated';
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return 'undated';
    const week = getISOWeek(d);
    return `${d.getFullYear()}-W${String(week).padStart(2, '0')}`;
  }

  function groupByWeek(items) {
    const weeks = [];
    let currentWeekKey = null;
    let currentWeek = null;

    items.forEach((item, idx) => {
      const weekKey = getWeekKey(item.added_at);
      if (weekKey !== currentWeekKey) {
        currentWeekKey = weekKey;
        currentWeek = {
          key: weekKey,
          label: formatWeekLabel(item.added_at) || 'Undated',
          items: [],
        };
        weeks.push(currentWeek);
      }
      currentWeek.items.push({ item, idx });
    });
    return weeks;
  }

  // ---- Continuous masonry + week timeline (Mac app parity) ----
  // The grid is one continuous masonry (no per-week sections), rendered in
  // batches as you scroll. Week grouping lives in the left-gutter timeline:
  // one bar per ISO week, spanning that week's cards. Hover shows the week,
  // click filters the grid to it — same model as the native app.
  //
  // Card size is set by the column count you get at full width (auto by
  // breakpoint, or your pinch choice). Opening the side panel keeps that
  // card width and drops columns instead of squeezing cards; the panel
  // absorbs the leftover strip so the grid stays edge to edge.
  const BATCH = 120;
  const ZOOM_KEY = 'stello.gridColumns';   // 0 = auto; 1…12 = pinch choice
  const MIN_COLS = 1, MAX_COLS = 12;
  let zoomCols = (() => {
    const n = parseInt(localStorage.getItem(ZOOM_KEY) || '0', 10);
    return Number.isFinite(n) && n >= MIN_COLS && n <= MAX_COLS ? n : 0;
  })();
  let selectedWeek = null;        // 'YYYY-Wnn' week filter, or null
  let filteredCache = [];          // getFilteredItems() snapshot for the current render
  let renderedCount = 0;
  let gridCols = 0;
  let gridColsAtFullWidth = 0;    // column count with no panel open (sets card width)
  let cardWidth = 0;
  let panelExtra = 0;              // px the open panel grows to absorb leftover space
  let colHeights = [];             // running estimated column heights (px)
  let weekScrollMemory = null;     // { scrollTop, count } to restore after clearing a week filter

  const isSearchActive = () => !!(searchQuery || activeTags.length > 0 || selectedWeek);

  function computeGridCols(width) {
    if (width <= 500) return 2;
    if (width <= 768) return 3;
    if (width <= 1200) return 4;
    return 5;
  }
  function gridGap() {
    const sec = $grid.querySelector('.masonry-section');
    const g = sec ? parseFloat(getComputedStyle(sec).columnGap) : NaN;
    return Number.isFinite(g) ? g : (window.innerWidth <= 768 ? 12 : 24);
  }
  function isOverlayPanelMode() { return window.innerWidth <= 768; }

  // Grid width with no panel open — the width card size is derived from.
  function fullGridWidth() {
    const mc = document.querySelector('.main-content');
    const inner = document.querySelector('.content-inner');
    const cs = getComputedStyle(inner);
    const padL = parseFloat(cs.paddingLeft) || 0;
    const maxW = parseFloat(cs.maxWidth);
    const sb = mc ? (mc.offsetWidth - mc.clientWidth) : 0;
    const innerW = Math.min(window.innerWidth - sb, Number.isFinite(maxW) ? maxW : Infinity);
    return Math.max(0, innerW - 2 * padL);
  }
  function fitCols(avail, cw, gap) {
    return Math.max(1, Math.floor((avail + gap + 0.5) / (cw + gap)));
  }
  function colsWidth(cols, cw, gap) { return cols * cw + (cols - 1) * gap; }

  function estimateCardHeight(item) {
    const w = cardWidth || 250;
    if (item.image_width && item.image_height) return w * (item.image_height / item.image_width);
    if (item.has_image) return w * (630 / 1200);
    return Math.min(242, w);
  }

  function scaffoldHTML(cols) {
    let html = '<div class="masonry-section">';
    for (let i = 0; i < cols; i++) html += '<div class="masonry-col"></div>';
    return html + '</div>';
  }

  // Append the next batch of filtered items, packed into the shortest column.
  function appendBatch(n) {
    const section = $grid.querySelector('.masonry-section');
    if (!section) return;
    const cols = section.children;
    if (!cols.length) return;
    // Re-sync the running heights with real layout once per batch, so
    // estimate drift from earlier batches doesn't accumulate.
    for (let i = 0; i < cols.length; i++) colHeights[i] = cols[i].offsetHeight;
    const end = Math.min(filteredCache.length, renderedCount + n);
    const buckets = Array.from({ length: cols.length }, () => []);
    for (let i = renderedCount; i < end; i++) {
      const item = filteredCache[i];
      let best = 0;
      for (let c = 1; c < colHeights.length; c++) if (colHeights[c] < colHeights[best]) best = c;
      buckets[best].push(renderCard(item, i));
      colHeights[best] += estimateCardHeight(item) + gridGap();
    }
    buckets.forEach((b, i) => { if (b.length) cols[i].insertAdjacentHTML('beforeend', b.join('')); });
    renderedCount = end;
  }

  // Render (or re-render) the grid from scratch. `minCount` keeps at least
  // that many cards rendered — used to hold scroll position on reflow.
  function renderGrid(opts) {
    opts = opts || {};
    filteredCache = getFilteredItems();
    if (filteredCache.length === 0) {
      $grid.innerHTML = '<div class="no-results">No items match your filters.</div>';
      renderedCount = 0;
      scheduleTimeline();
      PanelManager.refreshAfterGridRender();
      return;
    }
    const cols = gridCols || 1;
    $grid.innerHTML = scaffoldHTML(cols);
    colHeights = new Array(cols).fill(0);
    renderedCount = 0;
    const want = Math.max(BATCH, opts.minCount || 0);
    while (renderedCount < Math.min(want, filteredCache.length)) appendBatch(BATCH);

    if (opts.stagger !== false) {
      $grid.querySelectorAll('.card').forEach((c, j) => { if (j < 60) c.style.setProperty('--idx', j); });
    }
    PanelManager.refreshAfterGridRender();
    const openSlug = PanelManager.getOpenSlug();
    syncHighlightsToOpenPanels(openSlug ? [openSlug] : []);
    scheduleTimeline();
    updateFilterButtonState();
    requestAnimationFrame(fillViewport);
  }

  // Keep rendering until the sentinel is past the viewport bottom.
  function fillViewport() {
    const mc = document.querySelector('.main-content');
    const sentinel = document.getElementById('grid-sentinel');
    if (!mc || !sentinel) return;
    let guard = 0;
    while (renderedCount < filteredCache.length && guard++ < 40) {
      const r = sentinel.getBoundingClientRect();
      if (r.top > mc.getBoundingClientRect().bottom + 1500) break;
      appendBatch(BATCH);
      PanelManager.refreshAfterGridRender();
    }
    scheduleTimeline();
  }

  // Older pages streamed in after first paint: extend the list in place.
  function appendOlderWeeks() {
    filteredCache = getFilteredItems();
    if (renderedCount === 0) { renderGrid(); return; }
    fillViewport();
  }

  // Reflow for a column-count change, keeping the first visible card in place.
  function reflowGrid() {
    const mc = document.querySelector('.main-content');
    let anchor = null, anchorTop = 0;
    if (mc && mc.scrollTop > 0) {
      const top = mc.getBoundingClientRect().top + 140;
      for (const card of $grid.querySelectorAll('.card')) {
        const r = card.getBoundingClientRect();
        if (r.bottom > top) { anchor = card.dataset.slug; anchorTop = r.top; break; }
      }
    }
    renderGrid({ minCount: renderedCount, stagger: false });
    if (anchor && mc) {
      const el = $grid.querySelector(`.card[data-slug="${cssSelectorEscape(anchor)}"]`);
      if (el) mc.scrollTop += el.getBoundingClientRect().top - anchorTop;
    }
  }

  // Recompute card width + column count. Called on resize, panel
  // open/close and pinch. Re-renders only when the column count changes.
  function updateGridCols() {
    const mc = document.querySelector('.main-content');
    const inner = document.querySelector('.content-inner');
    if (!mc || !inner) return;
    const gap = gridGap();
    const full = fullGridWidth();
    // A pinch choice made on a wide window shouldn't crush cards on a
    // narrow one: keep cards at least 110px wide.
    const maxFit = Math.max(1, Math.floor((full + gap) / (110 + gap)));
    const baseCols = Math.min(zoomCols || computeGridCols(full), maxFit);
    cardWidth = Math.max(60, (full - gap * (baseCols - 1)) / baseCols);
    gridColsAtFullWidth = baseCols;
    document.documentElement.style.setProperty('--card-w', cardWidth + 'px');
    applyCardDensity(baseCols);

    const panelOpen = !!document.querySelector('#panels-container .panel');
    const avail = $grid.clientWidth || full;
    let cols;
    if (!panelOpen || isOverlayPanelMode()) {
      cols = baseCols;
      setPanelExtra(0);
    } else {
      // Width the grid would have at the panel's base width. If the
      // content column is capped by max-width, growing the panel won't
      // reclaim space, so leave the strip instead.
      const capped = inner.offsetWidth < mc.clientWidth - 1;
      const baseAvail = capped ? avail : avail + panelExtra;
      cols = Math.min(baseCols, fitCols(baseAvail, cardWidth, gap));
      setPanelExtra(capped ? 0 : Math.max(0, baseAvail - colsWidth(cols, cardWidth, gap)));
    }
    document.documentElement.style.setProperty('--grid-cols', String(cols));
    if (cols !== gridCols) {
      gridCols = cols;
      reflowGrid();
    } else {
      scheduleTimeline();
    }
  }
  // The Mac card's zoom rules (ItemCardView.swift): past 5 columns the title
  // shrinks 16 → 12 pt and the link pill 11 → 9 pt; past 9 columns the card
  // overlays (title, link pill, review mark, post marks) hide. Keyed to the
  // card size (base columns), which stays fixed when the panel opens.
  function applyCardDensity(cols) {
    const title = cols <= 5 ? 16 : Math.max(12, 16 - (cols - 5));
    const pill = cols <= 5 ? 11 : Math.max(9, 11 - 0.5 * (cols - 5));
    const root = document.documentElement;
    root.style.setProperty('--card-title-scale', (title / 16).toFixed(4));
    root.style.setProperty('--card-pill-scale', (pill / 11).toFixed(4));
    root.classList.toggle('cards-dense', cols > 9);
  }
  function setPanelExtra(px) {
    px = Math.round(px);
    if (Math.abs(px - panelExtra) < 1) return;
    panelExtra = px;
    PanelManager.applyWidth && PanelManager.applyWidth();
  }
  function getPanelExtra() { return isOverlayPanelMode() ? 0 : panelExtra; }

  function startGridColsObserver() {
    updateGridCols();
    const mc = document.querySelector('.main-content');
    if (!mc) return;
    let raf = 0;
    const kick = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(updateGridCols); };
    if (typeof ResizeObserver === 'function') {
      new ResizeObserver(kick).observe(mc);
      // Card heights settle as images load — keep timeline bars in step.
      new ResizeObserver(scheduleTimeline).observe($grid);
    } else {
      window.addEventListener('resize', kick);
    }
    // Progressive rendering as the sentinel nears the viewport.
    const sentinel = document.getElementById('grid-sentinel');
    if (sentinel && typeof IntersectionObserver === 'function') {
      new IntersectionObserver((entries) => {
        if (entries.some(e => e.isIntersecting)) fillViewport();
      }, { root: mc, rootMargin: '0px 0px 1500px 0px' }).observe(sentinel);
    }
    mc.addEventListener('scroll', () => {
      if (!spyRaf) spyRaf = requestAnimationFrame(() => { spyRaf = 0; updateScrollSpy(); });
    }, { passive: true });
    bindTimeline();
    bindPinchZoom();
  }

  // ---- Pinch zoom (trackpad pinch, Ctrl/⌘+scroll, touch pinch, +/− keys) ----
  // Spread → fewer, bigger cards. Pinch → more, smaller cards. Same
  // direction and 1…12 range as the Mac app. Saved per browser.
  function currentBaseCols() { return gridColsAtFullWidth || zoomCols || computeGridCols(fullGridWidth()); }
  function setZoomCols(n) {
    n = Math.max(MIN_COLS, Math.min(MAX_COLS, n));
    if (n === currentBaseCols() && zoomCols) return;
    zoomCols = n;
    try { localStorage.setItem(ZOOM_KEY, String(n)); } catch { /* silent */ }
    updateGridCols();
  }
  function stepZoom(delta) { setZoomCols(currentBaseCols() + delta); }
  // Settings stepper (Mac: Grid section, 0 = Auto, 1…12 columns).
  function setGridColumns(n) {
    if (n <= 0) {
      zoomCols = 0;
      try { localStorage.removeItem(ZOOM_KEY); } catch { /* silent */ }
      updateGridCols();
    } else setZoomCols(n);
  }

  function bindPinchZoom() {
    const mc = document.querySelector('.main-content');
    if (!mc) return;
    // Chrome/Firefox/Edge (and Safari 17+) report trackpad pinch as a
    // ctrlKey wheel event. ⌘+scroll on a mouse is treated the same way.
    let wheelAccum = 0, wheelTimer = 0;
    mc.addEventListener('wheel', (e) => {
      if (!(e.ctrlKey || e.metaKey)) return;
      e.preventDefault();
      wheelAccum += e.deltaY;
      clearTimeout(wheelTimer);
      wheelTimer = setTimeout(() => { wheelAccum = 0; }, 250);
      const STEP = 40;
      while (wheelAccum <= -STEP) { wheelAccum += STEP; stepZoom(-1); }
      while (wheelAccum >= STEP) { wheelAccum -= STEP; stepZoom(1); }
    }, { passive: false });

    // Safari's proprietary gesture events (older Safari, no ctrl-wheel).
    let gestureBase = null;
    const onGesture = (scale) => {
      if (gestureBase == null) gestureBase = currentBaseCols();
      const target = Math.round(gestureBase / Math.max(0.2, scale));
      if (target !== currentBaseCols()) setZoomCols(target);
    };
    mc.addEventListener('gesturestart', (e) => { e.preventDefault(); gestureBase = currentBaseCols(); });
    mc.addEventListener('gesturechange', (e) => { e.preventDefault(); onGesture(e.scale); });
    mc.addEventListener('gestureend', (e) => { e.preventDefault(); gestureBase = null; });

    // Two-finger touch pinch (iPad, phones, touchscreens).
    let touchStart = null;
    const dist = (t) => Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
    mc.addEventListener('touchstart', (e) => {
      if (e.touches.length === 2) touchStart = { d: dist(e.touches), cols: currentBaseCols() };
    }, { passive: true });
    mc.addEventListener('touchmove', (e) => {
      if (!touchStart || e.touches.length !== 2) return;
      e.preventDefault();
      const scale = dist(e.touches) / Math.max(1, touchStart.d);
      const target = Math.round(touchStart.cols / Math.max(0.2, scale));
      if (target !== currentBaseCols()) setZoomCols(target);
    }, { passive: false });
    mc.addEventListener('touchend', (e) => { if (e.touches.length < 2) touchStart = null; });

    document.addEventListener('keydown', (e) => {
      if (e.target && e.target.matches && e.target.matches('input, textarea, [contenteditable]')) return;
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === '+' || e.key === '=') { e.preventDefault(); stepZoom(-1); }
      else if (e.key === '-' || e.key === '_') { e.preventDefault(); stepZoom(1); }
      else if (e.key === '/') { e.preventDefault(); $search.focus(); }
    });
  }

  // ---- Week timeline ----
  const BAR_GAP = 4, BAR_MIN = 6;
  let timelineRaf = 0, spyRaf = 0;
  let barLayouts = [];            // [{ key, label, top, bottom }] sorted by top, grid-container coords
  let hoverWeek = null;
  let spyWeek = null;

  function weekLabelFor(key) {
    const it = filteredCache.find(i => getWeekKey(i.added_at) === key);
    return (it && formatWeekLabel(it.added_at)) || 'Undated';
  }

  function scheduleTimeline() {
    if (timelineRaf) return;
    timelineRaf = requestAnimationFrame(() => { timelineRaf = 0; layoutTimeline(); });
  }

  function layoutTimeline() {
    const container = document.querySelector('.grid-container');
    const $bars = document.getElementById('timeline-bars');
    if (!container || !$bars) return;
    const base = container.getBoundingClientRect().top;
    const ranges = new Map();
    for (const card of $grid.querySelectorAll('.card[data-slug]')) {
      const item = itemsBySlug[card.dataset.slug];
      if (!item) continue;
      const key = getWeekKey(item.added_at);
      const r = card.getBoundingClientRect();
      if (r.height === 0) continue;
      const top = r.top - base, bottom = r.bottom - base;
      const cur = ranges.get(key);
      if (!cur) ranges.set(key, { top, bottom });
      else { if (top < cur.top) cur.top = top; if (bottom > cur.bottom) cur.bottom = bottom; }
    }
    const raw = [...ranges.entries()].map(([key, r]) => ({ key, top: r.top, bottom: r.bottom }))
      .sort((a, b) => a.top - b.top);
    // Masonry interleaves weeks across columns, so ranges overlap; stack
    // bars top-to-bottom with a small gap, like the Mac timeline does.
    let prevBottom = -Infinity;
    barLayouts = raw.map(b => {
      let top = b.top;
      if (top < prevBottom + BAR_GAP) top = prevBottom + BAR_GAP;
      const bottom = Math.max(top + BAR_MIN, b.bottom);
      prevBottom = bottom;
      return { key: b.key, top, bottom };
    });
    $bars.innerHTML = barLayouts.map(b =>
      `<div class="timeline-bar" data-week="${b.key}" style="top:${b.top}px;height:${b.bottom - b.top}px"></div>`
    ).join('');
    applyTimelineStates();
    updateScrollSpy();
  }

  // Bands split at the middle of each inter-bar gap, so every point over
  // a bar (or just around it) resolves to that bar.
  function weekAtY(y) {
    if (!barLayouts.length) return null;
    for (let i = 0; i < barLayouts.length; i++) {
      const next = barLayouts[i + 1];
      if (!next) return barLayouts[i].key;
      if (y < (barLayouts[i].bottom + next.top) / 2) return barLayouts[i].key;
    }
    return barLayouts[barLayouts.length - 1].key;
  }

  function applyTimelineStates() {
    const $bars = document.getElementById('timeline-bars');
    if (!$bars) return;
    for (const el of $bars.children) {
      const k = el.dataset.week;
      el.classList.toggle('is-hover', k === hoverWeek);
      el.classList.toggle('is-selected', k === selectedWeek);
      el.classList.toggle('is-spy', k === spyWeek && k !== hoverWeek && k !== selectedWeek);
    }
    const $label = document.getElementById('timeline-label');
    if (!$label) return;
    const bar = hoverWeek && barLayouts.find(b => b.key === hoverWeek);
    if (!bar) { $label.hidden = true; return; }
    // Top-aligned with the bar, but kept below the sticky header so long
    // weeks that start above the fold still show their label.
    const container = document.querySelector('.grid-container');
    const header = document.querySelector('.header');
    const visibleTop = header
      ? header.getBoundingClientRect().bottom - container.getBoundingClientRect().top + 8
      : 0;
    $label.textContent = weekLabelFor(hoverWeek);
    $label.style.top = Math.min(bar.bottom - 10, Math.max(bar.top, visibleTop)) + 'px';
    $label.hidden = false;
  }

  function updateScrollSpy() {
    const container = document.querySelector('.grid-container');
    const header = document.querySelector('.header');
    if (!container || !barLayouts.length) { spyWeek = null; return; }
    const line = (header ? header.getBoundingClientRect().bottom : 0) + 16 - container.getBoundingClientRect().top;
    const next = weekAtY(line);
    if (next !== spyWeek) { spyWeek = next; applyTimelineStates(); }
    else if (hoverWeek) applyTimelineStates();
  }

  function setWeekFilter(key) {
    const mc = document.querySelector('.main-content');
    if (key && !selectedWeek && mc) weekScrollMemory = { scrollTop: mc.scrollTop, count: renderedCount };
    selectedWeek = key;
    hoverWeek = null;
    renderActiveFilters();
    if (key) {
      renderGrid({ stagger: false });
      if (mc) mc.scrollTop = 0;
    } else {
      const mem = weekScrollMemory;
      weekScrollMemory = null;
      renderGrid({ stagger: false, minCount: mem ? mem.count : 0 });
      if (mc && mem) mc.scrollTop = mem.scrollTop;
    }
  }

  function bindTimeline() {
    const tl = document.getElementById('timeline');
    const container = document.querySelector('.grid-container');
    if (!tl || !container) return;
    const yOf = (e) => e.clientY - container.getBoundingClientRect().top;
    tl.addEventListener('pointermove', (e) => {
      const k = weekAtY(yOf(e));
      if (k !== hoverWeek) { hoverWeek = k; applyTimelineStates(); }
    });
    tl.addEventListener('pointerleave', (e) => {
      if (e.pointerType === 'touch') return;
      hoverWeek = null; applyTimelineStates();
    });
    // Touch: drag along the bars to scrub weeks (the label follows the
    // finger); lifting the finger toggles that week's filter, like the
    // iPhone app's scrub gesture. The click that follows is swallowed.
    let touchScrub = false;
    tl.addEventListener('pointerdown', (e) => {
      if (e.pointerType !== 'touch') return;
      touchScrub = true;
      try { tl.setPointerCapture(e.pointerId); } catch {}
      hoverWeek = weekAtY(yOf(e)); applyTimelineStates();
    });
    const endScrub = (e, commit) => {
      if (!touchScrub) return;
      touchScrub = false;
      const k = commit ? weekAtY(yOf(e)) : null;
      hoverWeek = null; applyTimelineStates();
      if (k) setWeekFilter(selectedWeek === k ? null : k);
      suppressClick = true;
      setTimeout(() => { suppressClick = false; }, 400);
    };
    let suppressClick = false;
    tl.addEventListener('pointerup', (e) => endScrub(e, true));
    tl.addEventListener('pointercancel', (e) => endScrub(e, false));
    tl.addEventListener('click', (e) => {
      if (suppressClick) { suppressClick = false; return; }
      const k = weekAtY(yOf(e));
      if (!k) return;
      setWeekFilter(selectedWeek === k ? null : k);
    });
  }

  function updateFilterButtonState() {
    const btn = document.getElementById('filter-panel-btn');
    if (btn) btn.classList.toggle('has-filters', activeTags.length > 0 || !!selectedWeek || needsReviewOnly);
  }

  function sortItemsByAddedAt(arr) {
    arr.sort((a, b) => {
      const da = a.added_at ? new Date(a.added_at).getTime() : 0;
      const db = b.added_at ? new Date(b.added_at).getTime() : 0;
      return db - da;
    });
  }

  function cleanSummary(text) {
    if (!text) return text;
    // Strip leading/trailing quotes and whitespace first
    let cleaned = text.replace(/^[''""\s]+/, '').replace(/[''""\s]+$/, '');
    // Strip Instagram pattern: "14K likes, 35 comments - username on Date: 'actual content"
    cleaned = cleaned.replace(/^\d[\d,.KkMm]*\s*likes?,\s*\d[\d,.KkMm]*\s*comments?\s*-\s*\S+\s+on\s+\w+\s+\d{1,2},?\s+\d{4}[\s\u200E:]*[''""]?\s*/i, '');
    // Strip "Saved from domain:" prefix
    cleaned = cleaned.replace(/^Saved from \S+:\s*/i, '');
    // Strip any remaining leading quotes/whitespace
    cleaned = cleaned.replace(/^[''""\s]+/, '');
    return cleaned.trim();
  }

  function truncateWords(text, maxWords) {
    const words = text.split(/\s+/);
    if (words.length <= maxWords) return text;
    return words.slice(0, maxWords).join(' ') + '...';
  }

  function cssSlug(slug) {
    return slug.replace(/[^a-zA-Z0-9-]/g, '-');
  }

  // Signature of everything that affects a card's rendered appearance. Used to
  // skip DOM replacement during enrichment polling when nothing visible
  // changed — re-rendering an unchanged card re-creates its <img> (a flash)
  // and, because re-renders pass idx=0, flips placeholder hues. Excludes idx
  // deliberately so a no-op re-render is a true no-op.
  function hashStr(s) {
    let h = 5381;
    for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
    return h.toString(36);
  }
  function cardRenderSig(item) {
    return hashStr([
      (item.has_image && item.image_path) || '',
      item.image_width || '', item.image_height || '',
      item.title || '', item.domain || '',
      item.has_image ? '' : (item.summary || '').slice(0, 200),
      dominantColor(item),
      cardExtrasSig(item),
    ].join('|'));
  }

  // Post marks (top-right of an image card), as on the Mac: play for a
  // video, "GIF", a count for a carousel, "AI" for AI art.
  function postBadgesHTML(item) {
    if (item.kind !== 'post') return '';
    const m = window.StelloPanel.metaOf(item);
    if (!m) return '';
    const count = m.mediaCount || 0;
    const b = [];
    if (m.mediaType === 'video') b.push(`<span class="card-badge" aria-label="Video">${icon('play')}</span>`);
    if (m.mediaType === 'gif') b.push('<span class="card-badge">GIF</span>');
    if (count > 1) b.push(`<span class="card-badge" aria-label="${count} media">${icon('stack')}${count}</span>`);
    if (m.isAIArt === true) b.push('<span class="card-badge" aria-label="AI art">AI</span>');
    return b.length ? `<div class="card-badges">${b.join('')}</div>` : '';
  }
  function cardExtrasSig(item) {
    const m = item.metadata ? JSON.stringify(item.metadata).length : 0;
    return [item.kind || '', m, isAwaitingReview(item) ? 'r' : ''].join(':');
  }

  // Imageless Tool / Resource cards: an accent tile with a type glyph and the
  // item's name, as on the Mac (ItemCardView.glyphTile; SF Symbols → Phosphor).
  const GLYPH_SVG = {
    'code': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M69.12,94.15,28.5,128l40.62,33.85a8,8,0,1,1-10.24,12.29l-48-40a8,8,0,0,1,0-12.29l48-40a8,8,0,0,1,10.24,12.3Zm176,27.7-48-40a8,8,0,1,0-10.24,12.3L227.5,128l-40.62,33.85a8,8,0,1,0,10.24,12.29l48-40a8,8,0,0,0,0-12.29ZM162.73,32.48a8,8,0,0,0-10.25,4.79l-64,176a8,8,0,0,0,4.79,10.26A8.14,8.14,0,0,0,96,224a8,8,0,0,0,7.52-5.27l64-176A8,8,0,0,0,162.73,32.48Z"/></svg>',
    'puzzle-piece': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M220.27,158.54a8,8,0,0,0-7.7-.46,20,20,0,1,1,0-36.16A8,8,0,0,0,224,114.69V72a16,16,0,0,0-16-16H171.78a35.36,35.36,0,0,0,.22-4,36.11,36.11,0,0,0-11.36-26.24,36,36,0,0,0-60.55,23.62,36.56,36.56,0,0,0,.14,6.62H64A16,16,0,0,0,48,72v32.22a35.36,35.36,0,0,0-4-.22,36.12,36.12,0,0,0-26.24,11.36,35.7,35.7,0,0,0-9.69,27,36.08,36.08,0,0,0,33.31,33.6,35.68,35.68,0,0,0,6.62-.14V208a16,16,0,0,0,16,16H208a16,16,0,0,0,16-16V165.31A8,8,0,0,0,220.27,158.54ZM208,208H64V165.31a8,8,0,0,0-11.43-7.23,20,20,0,1,1,0-36.16A8,8,0,0,0,64,114.69V72h46.69a8,8,0,0,0,7.23-11.43,20,20,0,1,1,36.16,0A8,8,0,0,0,161.31,72H208v32.23a35.68,35.68,0,0,0-6.62-.14A36,36,0,0,0,204,176a35.36,35.36,0,0,0,4-.22Z"/></svg>',
    'cpu': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M152,96H104a8,8,0,0,0-8,8v48a8,8,0,0,0,8,8h48a8,8,0,0,0,8-8V104A8,8,0,0,0,152,96Zm-8,48H112V112h32Zm88,0H216V112h16a8,8,0,0,0,0-16H216V56a16,16,0,0,0-16-16H160V24a8,8,0,0,0-16,0V40H112V24a8,8,0,0,0-16,0V40H56A16,16,0,0,0,40,56V96H24a8,8,0,0,0,0,16H40v32H24a8,8,0,0,0,0,16H40v40a16,16,0,0,0,16,16H96v16a8,8,0,0,0,16,0V216h32v16a8,8,0,0,0,16,0V216h40a16,16,0,0,0,16-16V160h16a8,8,0,0,0,0-16Zm-32,56H56V56H200v95.87s0,.09,0,.13,0,.09,0,.13V200Z"/></svg>',
    'app-window': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M216,40H40A16,16,0,0,0,24,56V200a16,16,0,0,0,16,16H216a16,16,0,0,0,16-16V56A16,16,0,0,0,216,40Zm0,160H40V56H216V200ZM80,84A12,12,0,1,1,68,72,12,12,0,0,1,80,84Zm40,0a12,12,0,1,1-12-12A12,12,0,0,1,120,84Z"/></svg>',
    'globe': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M128,24h0A104,104,0,1,0,232,128,104.12,104.12,0,0,0,128,24Zm88,104a87.61,87.61,0,0,1-3.33,24H174.16a157.44,157.44,0,0,0,0-48h38.51A87.61,87.61,0,0,1,216,128ZM102,168H154a115.11,115.11,0,0,1-26,45A115.27,115.27,0,0,1,102,168Zm-3.9-16a140.84,140.84,0,0,1,0-48h59.88a140.84,140.84,0,0,1,0,48ZM40,128a87.61,87.61,0,0,1,3.33-24H81.84a157.44,157.44,0,0,0,0,48H43.33A87.61,87.61,0,0,1,40,128ZM154,88H102a115.11,115.11,0,0,1,26-45A115.27,115.27,0,0,1,154,88Zm52.33,0H170.71a135.28,135.28,0,0,0-22.3-45.6A88.29,88.29,0,0,1,206.37,88ZM107.59,42.4A135.28,135.28,0,0,0,85.29,88H49.63A88.29,88.29,0,0,1,107.59,42.4ZM49.63,168H85.29a135.28,135.28,0,0,0,22.3,45.6A88.29,88.29,0,0,1,49.63,168Zm98.78,45.6a135.28,135.28,0,0,0,22.3-45.6h35.66A88.29,88.29,0,0,1,148.41,213.6Z"/></svg>',
    'squares-four': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M104,40H56A16,16,0,0,0,40,56v48a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V56A16,16,0,0,0,104,40Zm0,64H56V56h48v48Zm96-64H152a16,16,0,0,0-16,16v48a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V56A16,16,0,0,0,200,40Zm0,64H152V56h48v48Zm-96,32H56a16,16,0,0,0-16,16v48a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V152A16,16,0,0,0,104,136Zm0,64H56V152h48v48Zm96-64H152a16,16,0,0,0-16,16v48a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V152A16,16,0,0,0,200,136Zm0,64H152V152h48v48Z"/></svg>',
    'file': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M213.66,82.34l-56-56A8,8,0,0,0,152,24H56A16,16,0,0,0,40,40V216a16,16,0,0,0,16,16H200a16,16,0,0,0,16-16V88A8,8,0,0,0,213.66,82.34ZM160,51.31,188.69,80H160ZM200,216H56V40h88V88a8,8,0,0,0,8,8h48V216Z"/></svg>',
    'layout': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M216,40H40A16,16,0,0,0,24,56V200a16,16,0,0,0,16,16H216a16,16,0,0,0,16-16V56A16,16,0,0,0,216,40Zm0,16V96H40V56ZM40,112H96v88H40Zm176,88H112V112H216v88Z"/></svg>',
    'copy': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M216,32H88a8,8,0,0,0-8,8V80H40a8,8,0,0,0-8,8V216a8,8,0,0,0,8,8H168a8,8,0,0,0,8-8V176h40a8,8,0,0,0,8-8V40A8,8,0,0,0,216,32ZM160,208H48V96H160Zm48-48H176V88a8,8,0,0,0-8-8H96V48H208Z"/></svg>',
    'image': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M216,40H40A16,16,0,0,0,24,56V200a16,16,0,0,0,16,16H216a16,16,0,0,0,16-16V56A16,16,0,0,0,216,40Zm0,16V158.75l-26.07-26.06a16,16,0,0,0-22.63,0l-20,20-44-44a16,16,0,0,0-22.62,0L40,149.37V56ZM40,172l52-52,80,80H40Zm176,28H194.63l-36-36,20-20L216,181.38V200ZM144,100a12,12,0,1,1,12,12A12,12,0,0,1,144,100Z"/></svg>',
    'star': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M239.18,97.26A16.38,16.38,0,0,0,224.92,86l-59-4.76L143.14,26.15a16.36,16.36,0,0,0-30.27,0L90.11,81.23,31.08,86a16.46,16.46,0,0,0-9.37,28.86l45,38.83L53,211.75a16.38,16.38,0,0,0,24.5,17.82L128,198.49l50.53,31.08A16.4,16.4,0,0,0,203,211.75l-13.76-58.07,45-38.83A16.43,16.43,0,0,0,239.18,97.26Zm-15.34,5.47-48.7,42a8,8,0,0,0-2.56,7.91l14.88,62.8a.37.37,0,0,1-.17.48c-.18.14-.23.11-.38,0l-54.72-33.65a8,8,0,0,0-8.38,0L69.09,215.94c-.15.09-.19.12-.38,0a.37.37,0,0,1-.17-.48l14.88-62.8a8,8,0,0,0-2.56-7.91l-48.7-42c-.12-.1-.23-.19-.13-.5s.18-.27.33-.29l63.92-5.16A8,8,0,0,0,103,91.86l24.62-59.61c.08-.17.11-.25.35-.25s.27.08.35.25L153,91.86a8,8,0,0,0,6.75,4.92l63.92,5.16c.15,0,.24,0,.33.29S224,102.63,223.84,102.73Z"/></svg>',
    'books': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M231.65,194.55,198.46,36.75a16,16,0,0,0-19-12.39L132.65,34.42a16.08,16.08,0,0,0-12.3,19l33.19,157.8A16,16,0,0,0,169.16,224a16.25,16.25,0,0,0,3.38-.36l46.81-10.06A16.09,16.09,0,0,0,231.65,194.55ZM136,50.15c0-.06,0-.09,0-.09l46.8-10,3.33,15.87L139.33,66Zm6.62,31.47,46.82-10.05,3.34,15.9L146,97.53Zm6.64,31.57,46.82-10.06,13.3,63.24-46.82,10.06ZM216,197.94l-46.8,10-3.33-15.87L212.67,182,216,197.85C216,197.91,216,197.94,216,197.94ZM104,32H56A16,16,0,0,0,40,48V208a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V48A16,16,0,0,0,104,32ZM56,48h48V64H56Zm0,32h48v96H56Zm48,128H56V192h48v16Z"/></svg>',
    'package': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M223.68,66.15,135.68,18a15.88,15.88,0,0,0-15.36,0l-88,48.17a16,16,0,0,0-8.32,14v95.64a16,16,0,0,0,8.32,14l88,48.17a15.88,15.88,0,0,0,15.36,0l88-48.17a16,16,0,0,0,8.32-14V80.18A16,16,0,0,0,223.68,66.15ZM128,32l80.34,44-29.77,16.3-80.35-44ZM128,120,47.66,76l33.9-18.56,80.34,44ZM40,90l80,43.78v85.79L40,175.82Zm176,85.78h0l-80,43.79V133.82l32-17.51V152a8,8,0,0,0,16,0V107.55L216,90v85.77Z"/></svg>',
    'stack': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M230.91,172A8,8,0,0,1,228,182.91l-96,56a8,8,0,0,1-8.06,0l-96-56A8,8,0,0,1,36,169.09l92,53.65,92-53.65A8,8,0,0,1,230.91,172ZM220,121.09l-92,53.65L36,121.09A8,8,0,0,0,28,134.91l96,56a8,8,0,0,0,8.06,0l96-56A8,8,0,1,0,220,121.09ZM24,80a8,8,0,0,1,4-6.91l96-56a8,8,0,0,1,8.06,0l96,56a8,8,0,0,1,0,13.82l-96,56a8,8,0,0,1-8.06,0l-96-56A8,8,0,0,1,24,80Zm23.88,0L128,126.74,208.12,80,128,33.26Z"/></svg>',
  };
  const TOOL_GLYPH = { library: 'code', extension: 'puzzle-piece', 'AI model': 'cpu', app: 'app-window' };
  const RESOURCE_GLYPH = {
    plugin: 'puzzle-piece', widget: 'squares-four', file: 'file', template: 'layout',
    component: 'copy', pen: 'code', mockup: 'image', 'icon set': 'star',
    'reading list': 'books', library: 'package',
  };
  function glyphTileFor(item) {
    if (item.kind !== 'tool' && item.kind !== 'resource') return null;
    const m = window.StelloPanel.metaOf(item);
    if (!m) return null;
    const icon = item.kind === 'tool'
      ? (TOOL_GLYPH[m.subtype] || 'globe')
      : (RESOURCE_GLYPH[m.subtype] || 'stack');
    const name = (typeof m.name === 'string' && m.name.trim()) || item.title || '';
    return { icon, name };
  }

  function renderCard(item, idx) {
    let thumbHtml;
    const hasImage = item.has_image && item.image_path;
    const vtName = `card-${cssSlug(item.slug)}`;

    const glyph = hasImage ? null : glyphTileFor(item);
    const hasTextContent = !hasImage && item.summary
      && item.summary.length > 30
      && !item.summary.startsWith('Saved from');

    if (hasImage) {
      // Emit width/height when known so the browser reserves the exact slot
      // before the image loads — eliminates the column-count reflow that
      // can otherwise visually fragment cards across columns. Falls back to
      // the CSS aspect-ratio: auto rule for items that predate dimension
      // capture.
      const dims = (item.image_width && item.image_height)
        ? ` width="${item.image_width}" height="${item.image_height}"` : '';
      thumbHtml = `<img class="card-thumb" src="${item.image_path}" alt=""${dims} loading="lazy" style="view-transition-name:${vtName}" onerror="this.parentElement.classList.add('img-error')">`;
    } else if (glyph) {
      thumbHtml = `<div class="card-glyph-tile" style="view-transition-name:${vtName}"><span class="card-glyph" aria-hidden="true">${GLYPH_SVG[glyph.icon] || ''}</span><span class="card-glyph-name">${escHtml(glyph.name)}</span></div>`;
    } else if (hasTextContent) {
      const hue = PLACEHOLDER_HUES[idx % PLACEHOLDER_HUES.length];
      const truncated = escHtml(truncateWords(cleanSummary(item.summary), 200));
      thumbHtml = `<div class="card-text-content" style="view-transition-name:${vtName};--ph-hue:${hue}">${truncated}</div>`;
    } else {
      const hue = PLACEHOLDER_HUES[idx % PLACEHOLDER_HUES.length];
      const letter = (item.title || '?')[0].toUpperCase();
      thumbHtml = `<div class="card-placeholder" style="view-transition-name:${vtName};--ph-hue:${hue}">${letter}</div>`;
    }

    // URL pill — bottom-right. Default: 20% color bg + white text.
    // Hover: fully opaque bg + color-tinted text (or dark if no color tag).
    const pillColor = dominantColor(item);
    const hasColorTag = pillColor !== '#ffffff';
    const pillBg = hasColorTag ? hexToRgba(pillColor, 0.2) : 'rgba(255, 255, 255, 0.2)';
    const pillBgHover = '#ffffff';
    const pillColorHover = hasColorTag ? pillColor : '#1a1a17';
    const linkLabel = window.StelloPanel.displayLink(item);
    const urlPill = linkLabel
      ? `<a class="card-url-pill"${item.source_url ? ` href="${escHtml(item.source_url).replace(/"/g, '&quot;')}" target="_blank" rel="noopener"` : ''} style="--pill-bg:${pillBg};--pill-bg-hover:${pillBgHover};--pill-color-hover:${pillColorHover}" onclick="event.stopPropagation()">${escHtml(linkLabel)}</a>`
      : '';
    const kindLine = window.StelloPanel.kindLineFor(item);
    const reviewBadge = isAwaitingReview(item)
      ? `<span class="card-review-badge" style="--pill-bg:${pillBg}" title="Awaiting review" aria-label="Awaiting review">${icon('eye')}<span class="card-review-label">Review</span></span>`
      : '';

    const cardClass = hasImage ? ' card-visual' : (glyph ? ' card-glyph-card' : (hasTextContent ? ' card-text' : ''));

    return `<div class="card${cardClass}" data-slug="${item.slug}" data-render-sig="${cardRenderSig(item)}" tabindex="-1">
      <div class="card-visual-area">
        ${thumbHtml}
        <div class="card-title-badge">${escHtml(item.title || '')}${kindLine ? `<span class="card-kind-line">${escHtml(kindLine)}</span>` : ''}</div>
        ${hasImage ? postBadgesHTML(item) : ''}
        ${reviewBadge}
        ${urlPill}
      </div>
    </div>`;
  }

  // Format date as "16 Jun 2026"
  function formatHumanDate(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
  }

  // Format week as "W16 2026" (ISO week)
  function formatWeekTag(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return `W${String(getISOWeek(d)).padStart(2, '0')} ${d.getFullYear()}`;
  }

  // ==== Item detail panel — exact copy of the Mac app's panel ==============
  // Card for card, the same as apple/…/Views/CardSubcards.swift (Arjun's
  // call, 2026-11-07: "exact Mac copy", no web-only extras). The layout and
  // the "every value shows once" rules live in panel-layout.js
  // (window.StelloPanel); this file only turns its cards into HTML and wires
  // the few edits the Mac panel allows: set cover, add image, accept /
  // dismiss a why-save suggestion, remove an AI tag, remove a snippet, Enrich.

  // Which image the open panel is previewing (client only; cover is server truth).
  const panelPreview = { slug: null, path: null };

  function panelLayoutFor(item) {
    return window.StelloPanel.layout(item, { resolveSlug: (s) => !!itemsBySlug[s] });
  }

  function subCardHTML(title, inner, extraClass) {
    return `<section class="sub-card${extraClass ? ' ' + extraClass : ''}">
      ${title ? `<h3 class="sub-card-title">${escHtml(title)}</h3>` : ''}
      ${inner}
    </section>`;
  }

  function factsBodyHTML(rows) {
    return `<dl class="sub-facts">${rows.map(r => `<div class="sub-fact">
      <dt>${escHtml(r.label)}</dt>
      <dd>${r.url
        ? `<a href="${escAttr(r.url)}" target="_blank" rel="noopener" title="${escAttr(r.url)}">${escHtml(r.value)}</a>`
        : escHtml(r.value)}</dd>
    </div>`).join('')}</dl>`;
  }

  function chipsBodyHTML(chips, caption) {
    return `${caption ? `<div class="sub-caption">${escHtml(caption)}</div>` : ''}
      ${chips.length ? `<div class="sub-chips">${chips.map(c => `<span class="sub-chip">${escHtml(c)}</span>`).join('')}</div>` : ''}`;
  }

  function refsBodyHTML(refs) {
    return `<div class="sub-chips">${refs.map(r => {
      const target = r.slug && itemsBySlug[r.slug] ? r.slug : null;
      return target
        ? `<button type="button" class="sub-ref js-open-ref" data-slug="${escAttr(target)}">${escHtml(r.name)}</button>`
        : `<span class="sub-ref">${escHtml(r.name)}</span>`;
    }).join('')}</div>`;
  }

  function imagesWithRoles(item, roles) {
    return (item.images || []).filter(i => i && i.path && roles.includes(i.role || 'cover'));
  }

  // Main image + thumbnails, no edits (typed panels' top media and galleries).
  function galleryBodyHTML(item, images, height, showThumbs, key) {
    const shown = (panelPreview.slug === item.slug && images.find(i => i.path === panelPreview.path)) || images[0];
    return `<div class="sub-gallery" data-gallery="${escAttr(key)}">
      <div class="sub-gallery-main" style="height:${height}px"><img src="${escAttr(shown.path)}" alt="${escAttr(shown.label || '')}"></div>
      ${showThumbs && images.length > 1 ? `<div class="sub-thumbs">${images.map(img =>
        `<button type="button" class="sub-thumb js-preview${img.path === shown.path ? ' is-active' : ''}" data-path="${escAttr(img.path)}"><img src="${escAttr(img.path)}" alt=""></button>`
      ).join('')}</div>` : ''}
    </div>`;
  }

  // The Mac DetailImageStrip: cover (or a tinted placeholder), "Set as cover"
  // on a non-cover preview, thumbnails with a cover dot, and an Add tile.
  function imageStripHTML(item) {
    const images = (item.images || []).filter(i => i && i.path);
    const seeded = images.length === 0 && item.image_path
      ? [{ path: item.image_path, source: 'og', is_primary: true }] : images;
    const cover = seeded.find(i => i.is_primary) || seeded[0] || null;
    const shown = (panelPreview.slug === item.slug && seeded.find(i => i.path === panelPreview.path)) || cover;
    const hues = [18, 80, 38, 140, 25, 45, 12, 100];
    let h = 0; for (const ch of item.slug || '') h = (h * 31 + ch.charCodeAt(0)) | 0;
    const hue = hues[Math.abs(h) % hues.length];
    const main = shown
      ? `<img src="${escAttr(shown.path)}" alt="">`
      : `<div class="sub-strip-placeholder" style="--hue:${hue}"></div>`;
    const setCover = shown && cover && shown.path !== cover.path
      ? `<button type="button" class="sub-set-cover js-set-cover" data-path="${escAttr(shown.path)}">${icon('crosshair')}Set as cover</button>` : '';
    const thumbs = seeded.map(img => `<button type="button" class="sub-thumb js-preview${shown && img.path === shown.path ? ' is-active' : ''}" data-path="${escAttr(img.path)}" aria-label="${img === cover ? 'Cover image' : 'Image thumbnail'}">
        <img src="${escAttr(img.path)}" alt="">${img === cover ? '<span class="sub-cover-dot"></span>' : ''}
      </button>`).join('');
    return `<div class="sub-strip">
      <div class="sub-strip-main${shown ? '' : ' is-empty'}">${main}${setCover}</div>
      <div class="sub-thumbs">${thumbs}
        <label class="sub-thumb sub-add-tile" aria-label="Add image">${icon('plus')}<span>Add</span>
          <input type="file" accept="image/*" class="sr-only">
        </label>
      </div>
    </div>`;
  }

  function topImagesHTML(item, panel) {
    const typed = panel.isTyped ? imagesWithRoles(item, panel.topRoles) : [];
    const inner = typed.length
      ? galleryBodyHTML(item, typed, 220, true, 'top')
      : imageStripHTML(item);
    return `<section class="sub-card is-bleed is-full">${inner}</section>`;
  }

  function headerCardHTML(h) {
    return subCardHTML('', `<div class="sub-header">
      <h2 class="sub-header-title">${escHtml(h.title)}</h2>
      ${h.kindLine ? `<div class="sub-kind-line">${escHtml(h.kindLine)}</div>` : ''}
      ${h.showsAIArtBadge ? '<span class="sub-badge">AI art</span>' : ''}
      ${h.mainText ? `<div class="sub-main-text">
        ${h.mainIsAISummary ? '<div class="sub-ai-label">AI summary</div>' : ''}
        <p>${escHtml(h.mainText)}</p>
      </div>` : ''}
      ${h.extraTexts.map(t => `<p class="sub-extra-text">${escHtml(t)}</p>`).join('')}
    </div>`, 'is-full');
  }

  function notesBody(item) {
    if (!item.body_markdown) return '';
    const body = stripSections(item.body_markdown, [
      'Summary', 'Key Details', 'Visual Assets', 'Key Snippets', 'What Makes It Work',
    ]);
    return body ? renderMarkdown(body) : '';
  }

  function cardHTML(item, c) {
    switch (c.type) {
      case 'facts':
        return c.rows.length ? subCardHTML(c.title, factsBodyHTML(c.rows)) : '';
      case 'chips':
        return c.chips.length || c.caption ? subCardHTML(c.title, chipsBodyHTML(c.chips, c.caption)) : '';
      case 'refs':
        return subCardHTML(c.title, refsBodyHTML(c.refs));
      case 'text':
        return subCardHTML(c.title, `<p class="sub-text">${escHtml(c.text)}</p>`);
      case 'gallery': {
        const imgs = imagesWithRoles(item, c.roles);
        return imgs.length ? subCardHTML(c.title, galleryBodyHTML(item, imgs, 140, false, c.title)) : '';
      }
      case 'faqs':
        return subCardHTML(c.title, `<div class="sub-faqs">${c.items.map(f =>
          `<details><summary>${escHtml(f.question)}</summary><p>${escHtml(f.answer)}</p></details>`).join('')}</div>`);
      case 'chipsFacts':
      case 'github':
        return subCardHTML(c.title, (c.type === 'github'
          ? factsBodyHTML(c.rows) + (c.chips.length ? chipsBodyHTML(c.chips) : '')
          : (c.chips.length ? chipsBodyHTML(c.chips) : '') + (c.rows.length ? factsBodyHTML(c.rows) : '')));
      case 'tracklist':
        return subCardHTML(c.title, `<ol class="sub-tracks">${c.tracks.map(t =>
          `<li><span>${escHtml(t.name)}</span>${t.duration ? `<span class="sub-track-time">${t.duration}</span>` : ''}</li>`).join('')}</ol>`);
      case 'aiArt':
        return subCardHTML(c.title, `<dl class="sub-facts">
          ${c.model ? `<div class="sub-fact"><dt>Model</dt><dd>${escHtml(c.model)}</dd></div>` : ''}
          ${c.prompt ? `<div class="sub-fact sub-fact-copy"><div><dt>${escHtml(c.promptLabel)}</dt><dd>${escHtml(c.prompt)}</dd></div>
            <button type="button" class="sub-icon-btn js-copy-prompt" data-text="${escAttr(c.prompt)}" title="Copy prompt" aria-label="Copy prompt">${icon('copy')}</button></div>` : ''}
        </dl>`);
      case 'notes': {
        const html = notesBody(item);
        return html ? subCardHTML('Notes', `<div class="sub-notes">${html}</div>`) : '';
      }
      default: return '';
    }
  }

  function humanizeReason(r) {
    return String(r || '').replace(/[-_]/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  }

  // Why save? — the enrichment's suggested reasons not yet accepted.
  function whySavedSuggestions(item) {
    const reasons = (item.enrichment_candidates && Array.isArray(item.enrichment_candidates.reasons))
      ? item.enrichment_candidates.reasons : [];
    const have = new Set((item.tags || []).map(t => String(t.tag).toLowerCase()));
    return reasons.filter(r => r && !have.has(String(r).toLowerCase()));
  }

  function enrichmentCardsHTML(item, panel) {
    const S = window.StelloPanel;
    const tags = S.visibleTags(item.tags, panel);
    const snippets = S.visibleSnippets(item.snippets, panel);
    const suggestions = whySavedSuggestions(item);
    let out = '';

    if (suggestions.length) {
      out += subCardHTML('Why save?', `<div class="sub-chips">${suggestions.map(s => `<span class="sub-why">
        <button type="button" class="js-accept-reason" data-reason="${escAttr(s)}" aria-label="Accept ${escAttr(humanizeReason(s))}">${escHtml(humanizeReason(s))}</button>
        <button type="button" class="js-dismiss-reason" data-reason="${escAttr(s)}" aria-label="Dismiss suggestion">${icon('x')}</button>
      </span>`).join('')}</div>`);
    }

    if (tags.length) {
      out += subCardHTML('Tags', `<div class="sub-chips">${tags.map(t => {
        const ai = t.source === 'ai';
        return `<span class="sub-tag${ai ? ' is-ai' : ''}" style="opacity:${Math.max(0.55, Number(t.weight) || 0)}">
          ${ai ? '<span class="sub-tag-dot"></span>' : ''}${escHtml(t.tag)}
          ${ai ? `<button type="button" class="js-remove-tag" data-tag="${escAttr(t.tag)}" data-category="${escAttr(t.category)}" aria-label="Remove tag">${icon('x')}</button>` : ''}
        </span>`;
      }).join('')}</div>`);
    }

    if (panel.kind !== 'post') {
      const linkEmpty = panel.kind === 'link' && !panel.header.mainText && !notesBody(item)
        && !tags.length && !suggestions.length;
      if (snippets.length) {
        out += subCardHTML('Key snippets', `<div class="sub-snippets">${snippets.map(s => `<div class="sub-snippet" data-index="${s.index}">
          <p>${escHtml(s.text)}</p>
          <button type="button" class="js-remove-snippet" aria-label="Remove snippet">${icon('x')}</button>
        </div>`).join('')}</div>`);
      } else if (linkEmpty) {
        out += subCardHTML('Key snippets', '<div class="sub-empty">No snippets yet.</div>');
      }
    }

    if (item.enrichment_status !== 'pending') {
      out += subCardHTML('Actions', `<button type="button" class="sub-enrich js-enrich">${icon('sparkle')}Enrich</button>
        ${item.enrichment_error ? `<div class="sub-error">${icon('warning')}${escHtml(item.enrichment_error)}</div>` : ''}`);
    }
    return out;
  }

  // The whole panel body: top images, header, Summary, the kind's cards,
  // then Why save? / Tags / Key snippets / Actions.
  function buildPanelBodyHTML(item) {
    const panel = panelLayoutFor(item);
    return `<div class="sub-grid">
      ${topImagesHTML(item, panel)}
      ${headerCardHTML(panel.header)}
      ${panel.cards.map(c => cardHTML(item, c)).join('')}
      ${enrichmentCardsHTML(item, panel)}
    </div>`;
  }

  function escAttr(str) {
    return String(str == null ? '' : str).replace(/[&<>"']/g, c =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
    );
  }

  // Re-render the open panel body from itemsBySlug, keeping scroll.
  function rerenderPanelBody(bodyEl, item) {
    const html = buildPanelBodyHTML(item);
    if (bodyEl.dataset.html === html) return;
    const top = bodyEl.scrollTop;
    bodyEl.innerHTML = html;
    bodyEl.dataset.html = html;
    bodyEl.scrollTop = top;
  }

  // Wires the panel body once (delegated, so re-renders keep working).
  function bindPanelBody(bodyEl, slug) {
    if (!bodyEl || bodyEl.dataset.bound) return;
    bodyEl.dataset.bound = '1';
    const refresh = (updated) => { if (updated) rerenderPanelBody(bodyEl, updated); };

    bodyEl.addEventListener('click', async (e) => {
      const item = itemsBySlug[slug];
      if (!item) return;
      const t = e.target;

      const preview = t.closest('.js-preview');
      if (preview) {
        panelPreview.slug = slug; panelPreview.path = preview.dataset.path;
        rerenderPanelBody(bodyEl, item);
        return;
      }
      const setCover = t.closest('.js-set-cover');
      if (setCover) {
        refresh(await postItemUpdate(slug, { primary_image_path: setCover.dataset.path }));
        return;
      }
      const ref = t.closest('.js-open-ref');
      if (ref) { PanelManager.open(ref.dataset.slug); return; }

      const accept = t.closest('.js-accept-reason');
      if (accept) { refresh(await postItemUpdate(slug, { add_intents: [accept.dataset.reason] })); return; }
      const dismiss = t.closest('.js-dismiss-reason');
      if (dismiss) { refresh(await postItemUpdate(slug, { dismiss_reasons: [dismiss.dataset.reason] })); return; }

      const rmTag = t.closest('.js-remove-tag');
      if (rmTag) {
        refresh(await postItemUpdate(slug, { removed_tags: [{ tag: rmTag.dataset.tag, category: rmTag.dataset.category }] }));
        return;
      }
      const rmSnip = t.closest('.js-remove-snippet');
      if (rmSnip) {
        const idx = Number(rmSnip.closest('.sub-snippet')?.dataset.index);
        if (idx >= 0) refresh(await postItemUpdate(slug, { removed_snippet_ids: [idx] }));
        return;
      }
      const copy = t.closest('.js-copy-prompt');
      if (copy) {
        try { await navigator.clipboard.writeText(copy.dataset.text); showToast('Prompt copied'); } catch { /* blocked */ }
        return;
      }
      if (t.closest('.js-enrich')) enrichItem(slug);
    });

    bodyEl.addEventListener('change', async (e) => {
      if (!e.target.matches('.sub-add-tile input[type="file"]')) return;
      const file = e.target.files && e.target.files[0];
      e.target.value = '';
      if (!file) return;
      const base64 = await fileToBase64(file);
      if (!base64) return;
      const updated = await postItemUpdate(slug, {
        manual_image_upload: { base64, mime: file.type || 'image/jpeg' },
      });
      if (updated) {
        const newest = [...updated.images].reverse().find(i => i.source === 'manual');
        if (newest) { panelPreview.slug = slug; panelPreview.path = newest.path; }
        rerenderPanelBody(bodyEl, updated);
      }
    });
  }

  async function postItemUpdate(slug, payload) {
    try {
      const res = await apiFetch('/api/item-update', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ slug, ...payload }),
      });
      if (!res.ok) return null;
      const data = await res.json();
      const next = normalizeItem({ ...(itemsBySlug[slug] || {}), ...data });
      itemsBySlug[slug] = next;
      const i = allItems.findIndex(x => x.slug === slug);
      if (i >= 0) allItems[i] = next;
      const card = document.querySelector(`.card[data-slug="${CSS.escape(slug)}"]`);
      const thumb = card && card.querySelector('.card-thumb');
      if (thumb && next.image_path) thumb.src = next.image_path;
      return next;
    } catch (err) {
      console.warn('postItemUpdate failed', slug, err.message);
      return null;
    }
  }

  function fileToBase64(file) {
    return new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => {
        const dataUrl = reader.result || '';
        const comma = dataUrl.indexOf(',');
        resolve(comma >= 0 ? dataUrl.slice(comma + 1) : null);
      };
      reader.onerror = () => resolve(null);
      reader.readAsDataURL(file);
    });
  }

  // ==== Card context menu — the Mac card's right-click menu ================
  // Same items, same order as ItemCardView.swift `cardContextMenu`: Open,
  // Enrich, Share, Copy Link, Copy ▸ (Title / Details (Markdown) / Image),
  // Download ▸ (Markdown / Image / Full Item), Delete.

  async function enrichItem(slug) {
    showToast('Enriching…');
    try {
      const res = await apiFetch('/api/reenrich', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ slug }),
      });
      if (!res.ok) throw new Error('Enrich request failed');
      pollForEnrichment(slug);
    } catch (err) {
      showToast('Enrich failed: ' + (err.message || 'unknown'));
    }
  }

  async function deleteItem(slug) {
    try {
      const res = await apiFetch('/api/item-delete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ slug }),
      });
      if (!res.ok) throw new Error('Delete failed');
      if (PanelManager.getOpenSlug() === slug) PanelManager.close();
      const card = document.querySelector(`.card[data-slug="${CSS.escape(slug)}"]`);
      if (card) card.remove();
      const idx = allItems.findIndex(i => i.slug === slug);
      if (idx >= 0) allItems.splice(idx, 1);
      delete itemsBySlug[slug];
      renderStats();
      showToast('Deleted');
    } catch (err) {
      showToast('Delete failed: ' + (err.message || 'unknown'));
    }
  }

  function exportBaseName(item) {
    const base = (item.slug || item.title || '').replace(/\//g, '-').trim();
    return base || 'item';
  }

  // The Mac `markdownExport()`: title, summary, URL / domain / saved / tags, notes.
  function itemMarkdown(item) {
    const lines = [];
    if (item.title) lines.push(`# ${item.title}`, '');
    if (item.summary) lines.push(item.summary, '');
    const meta = [];
    if (item.source_url) meta.push(`- **URL:** ${item.source_url}`);
    if (item.domain) meta.push(`- **Domain:** ${item.domain}`);
    const saved = item.added_at ? new Date(item.added_at) : null;
    if (saved && !isNaN(saved)) {
      meta.push(`- **Saved:** ${saved.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })}`);
    }
    const tagNames = (item.tags || []).map(t => t.tag).filter(Boolean);
    if (tagNames.length) meta.push(`- **Tags:** ${tagNames.join(', ')}`);
    if (meta.length) lines.push(...meta, '');
    const snippets = (item.snippets || []).filter(s => s && s.text);
    if (snippets.length) {
      lines.push('## Notes', '');
      for (const s of snippets) lines.push(`- ${s.text}`);
    }
    return lines.join('\n').trim();
  }

  async function copyText(text, label) {
    try { await navigator.clipboard.writeText(text); showToast(`${label} copied`); }
    catch { showToast('Copy failed'); }
  }

  async function fetchBlob(path) {
    const res = await fetch(path, { credentials: 'same-origin' });
    if (!res.ok) throw new Error('Image fetch failed');
    return res.blob();
  }

  // The clipboard takes PNG everywhere; other types are re-encoded through a canvas.
  async function toPngBlob(blob) {
    if (blob.type === 'image/png') return blob;
    const bmp = await createImageBitmap(blob);
    const canvas = document.createElement('canvas');
    canvas.width = bmp.width; canvas.height = bmp.height;
    canvas.getContext('2d').drawImage(bmp, 0, 0);
    return new Promise((resolve, reject) => canvas.toBlob(b => (b ? resolve(b) : reject(new Error('encode'))), 'image/png'));
  }

  async function copyImage(item) {
    try {
      const png = await toPngBlob(await fetchBlob(item.image_path));
      await navigator.clipboard.write([new ClipboardItem({ 'image/png': png })]);
      showToast('Image copied');
    } catch { showToast('Copy image failed'); }
  }

  function downloadBlob(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function imageExt(blob) {
    const t = ((blob.type || '').split('/')[1] || 'png').split('+')[0];
    return t === 'jpeg' ? 'jpg' : t.replace(/[^a-z0-9]/gi, '') || 'png';
  }

  async function downloadImage(item) {
    try {
      const blob = await fetchBlob(item.image_path);
      downloadBlob(blob, `${exportBaseName(item)}.${imageExt(blob)}`);
    } catch { showToast('Download failed'); }
  }

  // ---- Minimal zip writer (stored, no compression) for "Download Full Item" ----
  const CRC_TABLE = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();
  function crc32(bytes) {
    let c = 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  }
  function zipFiles(files) {
    const enc = new TextEncoder();
    const parts = [];
    const central = [];
    let offset = 0;
    for (const f of files) {
      const name = enc.encode(f.name);
      const data = f.data;
      const crc = crc32(data);
      const local = new DataView(new ArrayBuffer(30));
      local.setUint32(0, 0x04034b50, true); local.setUint16(4, 20, true); local.setUint16(6, 0x0800, true);
      local.setUint32(14, crc, true); local.setUint32(18, data.length, true); local.setUint32(22, data.length, true);
      local.setUint16(26, name.length, true);
      parts.push(new Uint8Array(local.buffer), name, data);
      const cen = new DataView(new ArrayBuffer(46));
      cen.setUint32(0, 0x02014b50, true); cen.setUint16(4, 20, true); cen.setUint16(6, 20, true); cen.setUint16(8, 0x0800, true);
      cen.setUint32(16, crc, true); cen.setUint32(20, data.length, true); cen.setUint32(24, data.length, true);
      cen.setUint16(28, name.length, true); cen.setUint32(42, offset, true);
      central.push(new Uint8Array(cen.buffer), name);
      offset += 30 + name.length + data.length;
    }
    const cenSize = central.reduce((n, p) => n + p.length, 0);
    const end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
    end.setUint32(12, cenSize, true); end.setUint32(16, offset, true);
    return new Blob([...parts, ...central, new Uint8Array(end.buffer)], { type: 'application/zip' });
  }

  // The Mac `ItemBundleExporter`: <name>/<name>.md, snippets/snippet-N.txt, images/image-N.ext.
  async function downloadFullItem(item) {
    const name = exportBaseName(item);
    const enc = new TextEncoder();
    const files = [{ name: `${name}/${name}.md`, data: enc.encode(itemMarkdown(item)) }];
    (item.snippets || []).filter(s => s && s.text).forEach((s, i) =>
      files.push({ name: `${name}/snippets/snippet-${i + 1}.txt`, data: enc.encode(s.text) }));
    const paths = (item.images || []).map(i => i && i.path).filter(Boolean);
    if (!paths.length && item.image_path) paths.push(item.image_path);
    let n = 0;
    for (const p of paths) {
      try {
        const blob = await fetchBlob(p);
        n++;
        files.push({ name: `${name}/images/image-${n}.${imageExt(blob)}`, data: new Uint8Array(await blob.arrayBuffer()) });
      } catch { /* skip an image that won't load */ }
    }
    downloadBlob(zipFiles(files), `${name}.zip`);
  }

  const CardMenu = (function () {
    let $menu = null;
    let slug = null;

    const ICON_FOR = {
      open: 'arrow-up-right', enrich: 'sparkle', share: 'share', 'copy-link': 'link',
      copy: 'copy', download: 'download', delete: 'trash',
    };

    function entries(item) {
      const hasURL = !!item.source_url;
      const hasImage = !!item.image_path;
      const list = [
        { id: 'open', label: 'Open' },
        { id: 'enrich', label: 'Enrich' },
      ];
      if (hasURL && navigator.share) list.push({ id: 'share', label: 'Share' });
      if (hasURL) list.push({ id: 'copy-link', label: 'Copy Link' });
      list.push({ id: 'copy', label: 'Copy', sub: [
        { id: 'copy-title', label: 'Copy Title' },
        { id: 'copy-md', label: 'Copy Details (Markdown)' },
        ...(hasImage ? [{ id: 'copy-image', label: 'Copy Image' }] : []),
      ] });
      list.push({ id: 'download', label: 'Download', sub: [
        { id: 'dl-md', label: 'Download Markdown' },
        ...(hasImage ? [{ id: 'dl-image', label: 'Download Image' }] : []),
        { id: 'dl-full', label: 'Download Full Item' },
      ] });
      list.push({ divider: true }, { id: 'delete', label: 'Delete', danger: true });
      return list;
    }

    function itemHTML(e) {
      if (e.divider) return '<div class="card-menu-divider" role="separator"></div>';
      const ic = ICON_FOR[e.id] ? `<span class="card-menu-icon">${icon(ICON_FOR[e.id])}</span>` : '<span class="card-menu-icon"></span>';
      if (e.sub) {
        return `<div class="card-menu-group">
          <button type="button" class="card-menu-item has-sub" role="menuitem" aria-haspopup="true" data-action="${e.id}">${ic}<span>${escHtml(e.label)}</span><span class="card-menu-chevron">›</span></button>
          <div class="card-menu card-menu-sub" role="menu">${e.sub.map(itemHTML).join('')}</div>
        </div>`;
      }
      return `<button type="button" class="card-menu-item${e.danger ? ' is-danger' : ''}" role="menuitem" data-action="${e.id}">${ic}<span>${escHtml(e.label)}</span></button>`;
    }

    function close() {
      if ($menu) { $menu.remove(); $menu = null; slug = null; }
    }

    function openAt(cardSlug, x, y) {
      const item = itemsBySlug[cardSlug];
      if (!item) return;
      close();
      slug = cardSlug;
      $menu = document.createElement('div');
      $menu.className = 'card-menu';
      $menu.setAttribute('role', 'menu');
      $menu.innerHTML = entries(item).map(itemHTML).join('');
      document.body.appendChild($menu);
      const r = $menu.getBoundingClientRect();
      const left = Math.min(x, window.innerWidth - r.width - 8);
      const top = Math.min(y, window.innerHeight - r.height - 8);
      $menu.style.left = Math.max(8, left) + 'px';
      $menu.style.top = Math.max(8, top) + 'px';
      if (left + r.width * 2 > window.innerWidth) $menu.classList.add('subs-left');
      $menu.querySelector('.card-menu-item')?.focus();
      $menu.addEventListener('click', onClick);
    }

    async function onClick(e) {
      const btn = e.target.closest('.card-menu-item');
      if (!btn || btn.classList.contains('has-sub')) return;
      const item = itemsBySlug[slug];
      const action = btn.dataset.action;
      close();
      if (!item) return;
      switch (action) {
        case 'open': PanelManager.open(item.slug); break;
        case 'enrich': enrichItem(item.slug); break;
        case 'share': navigator.share({ title: item.title || '', url: item.source_url }).catch(() => {}); break;
        case 'copy-link': copyText(item.source_url, 'Link'); break;
        case 'copy-title': copyText(item.title || '', 'Title'); break;
        case 'copy-md': copyText(itemMarkdown(item), 'Details'); break;
        case 'copy-image': copyImage(item); break;
        case 'dl-md': downloadBlob(new Blob([itemMarkdown(item)], { type: 'text/markdown' }), `${exportBaseName(item)}.md`); break;
        case 'dl-image': downloadImage(item); break;
        case 'dl-full': downloadFullItem(item); break;
        case 'delete': deleteItem(item.slug); break;
        default: break;
      }
    }

    function init() {
      document.addEventListener('contextmenu', (e) => {
        const card = e.target.closest && e.target.closest('.card[data-slug]');
        if (!card) { close(); return; }
        e.preventDefault();
        openAt(card.dataset.slug, e.clientX, e.clientY);
      });
      // Keyboard: the Menu key or Shift+F10 on a focused card.
      document.addEventListener('keydown', (e) => {
        if ($menu && e.key === 'Escape') { e.stopPropagation(); close(); return; }
        if (e.key === 'ContextMenu' || (e.shiftKey && e.key === 'F10')) {
          const card = document.activeElement && document.activeElement.closest && document.activeElement.closest('.card[data-slug]');
          if (!card) return;
          e.preventDefault();
          const r = card.getBoundingClientRect();
          openAt(card.dataset.slug, r.left + 16, r.top + 16);
        }
      }, true);
      document.addEventListener('mousedown', (e) => { if ($menu && !$menu.contains(e.target)) close(); });
      window.addEventListener('scroll', close, true);
      window.addEventListener('resize', close);
      window.addEventListener('blur', close);
    }

    return { init, close };
  })();

  // ---- Capture queue (sequential panel curation) ----
  // Slugs of freshly captured items that deserve a curation panel. We
  // open the first immediately; when its panel closes, notifyCaptureSlugClosed
  // pulls the next off the queue.
  const captureQueue = [];
  const captureFlowSlugs = new Set();

  function enqueueForCuration(slug) {
    if (!slug) return;
    captureQueue.push(slug);
    if (captureFlowSlugs.size === 0) advanceCaptureQueue();
  }

  function advanceCaptureQueue() {
    const next = captureQueue.shift();
    if (!next) return;
    captureFlowSlugs.add(next);
    PanelManager.open(next);
    // Existing poller refreshes the panel live as enrichment lands.
    if (typeof pollForEnrichment === 'function') pollForEnrichment(next);
    if (captureQueue.length) {
      showToast(`${captureQueue.length} more to curate`);
    }
  }

  function notifyCaptureSlugClosed(slug) {
    // Mac parity: leaving an item's panel marks it reviewed.
    const closedItem = itemsBySlug[slug];
    if (closedItem && closedItem.needs_review === true) postItemUpdate(slug, { mark_reviewed: true });
    if (!captureFlowSlugs.has(slug)) return;
    captureFlowSlugs.delete(slug);
    if (captureFlowSlugs.size === 0) advanceCaptureQueue();
  }

  // --- Active filter pills ---
  function renderActiveFilters() {
    updateFilterButtonState();
    if (activeTags.length === 0 && !selectedWeek && !needsReviewOnly) {
      $activeFilters.innerHTML = '';
      return;
    }
    const reviewPill = needsReviewOnly
      ? `<span class="active-filter-pill active-filter-review" data-review="1">Needs review <span class="x">&times;</span></span>`
      : '';
    const weekPill = selectedWeek
      ? `<span class="active-filter-pill active-filter-week" data-week="${selectedWeek}">${escHtml(weekLabelFor(selectedWeek))} <span class="x">&times;</span></span>`
      : '';
    $activeFilters.innerHTML = reviewPill + weekPill + activeTags.map((at, i) =>
      `<span class="active-filter-pill" data-idx="${i}">${escHtml(at.tag)} <span class="x">&times;</span></span>`
    ).join('') + `<button class="clear-filters-btn" id="clear-filters">Clear all</button>`;
  }

  // --- Related card highlighting ---
  // Triggered on panel open/close only (no hover-delayed highlight) to keep
  // class mutations rare and predictable. Updates are diff-based — only the
  // cards whose focused state actually changes get touched — so Safari
  // can't blame the highlight for a mass DOM mutation that would otherwise
  // briefly invalidate its column-count layout.
  function highlightRelated(slugs) {
    if (!Array.isArray(slugs)) slugs = [slugs];
    const next = new Set();
    slugs.forEach(s => {
      if (!s) return;
      next.add(s);
      (relatedIndex[s] || new Set()).forEach(r => next.add(r));
    });
    const prev = new Set();
    $grid.querySelectorAll('.card.card-focused').forEach(c => {
      if (c.dataset.slug) prev.add(c.dataset.slug);
    });
    // Remove cards that fell out of the related set.
    prev.forEach(slug => {
      if (next.has(slug)) return;
      const card = $grid.querySelector(`.card[data-slug="${cssSelectorEscape(slug)}"]`);
      if (card) card.classList.remove('card-focused');
    });
    // Add cards that newly entered the related set.
    next.forEach(slug => {
      if (prev.has(slug)) return;
      const card = $grid.querySelector(`.card[data-slug="${cssSelectorEscape(slug)}"]`);
      if (card) card.classList.add('card-focused');
    });
  }

  function clearHighlight() {
    $grid.querySelectorAll('.card-focused').forEach(c => c.classList.remove('card-focused'));
  }

  // Re-highlight based on open panels (called after panel open/close)
  function syncHighlightsToOpenPanels(panelSlugs) {
    if (panelSlugs && panelSlugs.length > 0) {
      highlightRelated(panelSlugs);
    } else {
      clearHighlight();
    }
  }

  // --- Markdown helpers ---
  function stripSections(md, names) {
    const pattern = new RegExp('^##\\s+(' + names.join('|') + ')\\s*$', 'i');
    const lines = md.split('\n');
    const result = [];
    let skipping = false;
    for (const line of lines) {
      if (/^##\s/.test(line)) {
        skipping = pattern.test(line);
      }
      if (!skipping) result.push(line);
    }
    return result.join('\n').trim();
  }

  function renderMarkdown(md) {
    let html = md;
    html = html.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1">');
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
    html = html.replace(/^#### (.+)$/gm, '<h4>$1</h4>');
    html = html.replace(/^### (.+)$/gm, '<h3>$1</h3>');
    html = html.replace(/^## (.+)$/gm, '<h2>$1</h2>');
    html = html.replace(/^# (.+)$/gm, '<h1>$1</h1>');
    html = html.replace(/^---$/gm, '<hr>');
    html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
    html = html.replace(/^- (.+)$/gm, '<li>$1</li>');
    html = html.replace(/((?:<li>.*<\/li>\n?)+)/g, '<ul>$1</ul>');
    html = html.split('\n\n').map(block => {
      block = block.trim();
      if (!block) return '';
      if (block.startsWith('<')) return block;
      return `<p>${block.replace(/\n/g, '<br>')}</p>`;
    }).join('\n');
    return html;
  }

  // --- Events ---
  function bindEvents() {
    let searchTimer = 0;
    $search.addEventListener('input', function () {
      const v = this.value.trim();
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => {
        if (v === searchQuery) return;
        searchQuery = v;
        renderGrid({ stagger: false });
      }, 120);
    });
    $search.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') { this.value = ''; this.dispatchEvent(new Event('input')); this.blur(); }
    });

    // Scrollbar auto-hide for the grid column: flash in while actively
    // scrolling, fade out ~700ms after the last scroll event.
    const mainContent = document.querySelector('.main-content');
    if (mainContent) {
      let scrollTimer;
      // Header glass thins over the first 48px of scroll, as on the Mac.
      const setHeaderScroll = () => {
        const p = Math.min(Math.max(mainContent.scrollTop, 0) / 48, 1);
        document.documentElement.style.setProperty('--header-scroll', p.toFixed(3));
      };
      setHeaderScroll();
      mainContent.addEventListener('scroll', () => {
        setHeaderScroll();
        mainContent.classList.add('is-scrolling');
        clearTimeout(scrollTimer);
        scrollTimer = setTimeout(() => mainContent.classList.remove('is-scrolling'), 700);
      }, { passive: true });
    }

    // Tool panel toggles (Filters, Import, Settings)
    document.getElementById('filter-panel-btn')?.addEventListener('click', () => PanelManager.openTool('filters'));
    document.getElementById('import-btn')?.addEventListener('click', () => PanelManager.openTool('import'));
    document.getElementById('settings-btn')?.addEventListener('click', () => PanelManager.openTool('settings'));

    // Render tool bodies when the tool panel opens
    document.addEventListener('toolpanel:rendered', (e) => {
      const { type } = e.detail;
      if (type === 'filters') {
        renderTagDrawer();
        bindFilterPanelBody();
      } else if (type === 'settings') {
        loadSettingsIntoPanel();
      } else if (type === 'import') {
        bindImportPanelBody();
      }
    });

    // Delegated clicks for tag chips + category headers (tool panel bodies re-render)
    document.addEventListener('click', (e) => {
      const header = e.target.closest('.tag-category-header');
      if (header) {
        const cat = header.dataset.cat;
        if (expandedCategories.has(cat)) expandedCategories.delete(cat);
        else expandedCategories.add(cat);
        renderTagDrawer();
        return;
      }
      const chipInDrawer = e.target.closest('#filter-tag-drawer .tag-chip');
      if (!chipInDrawer) return;
      const tag = chipInDrawer.dataset.tag;
      const cat = chipInDrawer.dataset.cat;
      const idx = activeTags.findIndex(a => a.tag === tag && a.category === cat);
      if (idx >= 0) activeTags.splice(idx, 1);
      else activeTags.push({ tag, category: cat });
      renderTagDrawer();
      renderActiveFilters();
      renderGrid();
    });

    $activeFilters.addEventListener('click', function (e) {
      if (e.target.id === 'clear-filters' || e.target.closest('#clear-filters')) {
        activeTags = [];
        needsReviewOnly = false;
        syncReviewToggle();
        renderTagDrawer();
        if (selectedWeek) { setWeekFilter(null); return; }
        renderActiveFilters();
        renderGrid();
        return;
      }
      const pill = e.target.closest('.active-filter-pill');
      if (!pill) return;
      if (pill.dataset.week) { setWeekFilter(null); return; }
      if (pill.dataset.review) { setNeedsReview(false); return; }
      const idx = parseInt(pill.dataset.idx, 10);
      activeTags.splice(idx, 1);
      renderTagDrawer();
      renderActiveFilters();
      renderGrid();
    });

    // Card click -> open item in the side panel
    $grid.addEventListener('click', function (e) {
      if (e.target.closest('a')) return;
      const card = e.target.closest('.card');
      if (!card || !card.dataset.slug) return;
      PanelManager.open(card.dataset.slug, { originCard: card });
    });
  }

  // --- Utility ---
  function renderTagPill(tag, category, shared) {
    const cls = CAT_CLASS[category] || 'tag-format';
    const sharedCls = shared ? ' tag-shared' : '';
    if (category === 'color') {
      const hex = COLOR_MAP[tag] || COLOR_MAP[tag.replace(/[-_\s]/g, '_')] || '#888';
      return `<span class="card-tag ${cls}${sharedCls}"><span class="color-dot" style="background:${hex}"></span>${tag}</span>`;
    }
    return `<span class="card-tag ${cls}${sharedCls}">${tag}</span>`;
  }

  function escHtml(str) {
    const d = document.createElement('div');
    d.textContent = str;
    return d.innerHTML;
  }

  // --- Capture: Paste handler ---
  function bindPasteHandler() {
    document.addEventListener('paste', (e) => {
      // Skip if any input or textarea is focused (search, settings, import modal)
      const active = document.activeElement;
      if (active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA')) return;
      // Skip if any tool panel is open (user might be interacting with it)
      if (document.querySelector('.panel-tool')) return;

      const text = e.clipboardData.getData('text/plain');
      const files = e.clipboardData.files;

      const urls = text ? text.match(/https?:\/\/[^\s<>"']+/g) : null;

      if (files && files.length > 0) {
        for (const file of files) {
          if (file.type.startsWith('image/')) captureImage(file);
        }
        e.preventDefault();
      } else if (urls && urls.length > 0) {
        e.preventDefault();
        if (urls.length === 1) captureURL(urls[0]);
        else captureBulkURLs(urls);
      } else if (text && text.trim() && text.trim().length > 5) {
        e.preventDefault();
        captureText(text.trim());
      }
    });
  }

  function insertPlaceholder(id) {
    // Target the first `.masonry-col` so the placeholder sits inside a
    // flex column track (correct width). Direct prepend onto the section
    // would make the card a sibling flex-track with no `flex: 1 1 0`
    // constraint \u2014 it then consumes its image's natural width, visible
    // as an oversized "Adding\u2026" card.
    const firstCol = $grid.querySelector('.masonry-section .masonry-col');
    if (!firstCol) return;
    const ph = document.createElement('div');
    ph.className = 'card card-adding';
    ph.dataset.placeholderId = id;
    ph.innerHTML = `<div class="card-visual-area"><div class="card-placeholder adding-pulse"><span>Adding\u2026</span></div></div>`;
    firstCol.prepend(ph);
  }

  function replacePlaceholder(id, rawItem) {
    // Always normalize so the grid card, panel, and refresh paths see
    // the same shape (tags array, images[], snippets[], image_path).
    const item = normalizeItem(rawItem || {});

    const ph = $grid.querySelector(`[data-placeholder-id="${id}"]`);
    if (ph) {
      ph.outerHTML = renderCard(item, 0);
    } else {
      // Fallback: prepend to the first masonry column (same reason as
      // insertPlaceholder — must live inside a .masonry-col, not directly
      // under .masonry-section).
      const firstCol = $grid.querySelector('.masonry-section .masonry-col');
      if (firstCol) firstCol.insertAdjacentHTML('afterbegin', renderCard(item, 0));
    }
    // Keep both the array and the lookup in sync
    allItems.unshift(item);
    itemsBySlug[item.slug] = item;
    renderStats();
  }

  async function captureURL(urlStr) {
    const id = 'ph-' + Date.now();
    insertPlaceholder(id);
    try {
      const res = await apiFetch('/api/capture', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'url', content: urlStr }),
      });
      const item = await res.json();
      if (res.status === 409) {
        removePlaceholder(id);
        showToast('Item already exists: ' + (item.existing?.title || urlStr));
        return;
      }
      if (!res.ok) {
        removePlaceholder(id);
        showToast('Capture failed');
        return;
      }
      replacePlaceholder(id, item);
      showToast('Added: ' + item.title);
      enqueueForCuration(item.slug);
    } catch (err) {
      removePlaceholder(id);
      showToast('Error: ' + err.message);
    }
  }

  async function captureImage(file) {
    const id = 'ph-' + Date.now() + Math.random();
    insertPlaceholder(id);
    try {
      const buf = await file.arrayBuffer();
      const res = await apiFetch('/api/upload-image', {
        method: 'POST',
        headers: { 'Content-Type': file.type },
        body: buf,
      });
      const item = await res.json();
      if (!res.ok) { removePlaceholder(id); showToast('Image capture failed'); return; }
      replacePlaceholder(id, item);
      showToast('Added image');
      enqueueForCuration(item.slug);
    } catch (err) {
      removePlaceholder(id);
      showToast('Error: ' + err.message);
    }
  }

  async function captureText(text) {
    const id = 'ph-' + Date.now();
    insertPlaceholder(id);
    try {
      const res = await apiFetch('/api/capture', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'text', content: text }),
      });
      const item = await res.json();
      if (!res.ok) { removePlaceholder(id); showToast('Text capture failed'); return; }
      replacePlaceholder(id, item);
      showToast('Added note: ' + item.title);
      enqueueForCuration(item.slug);
    } catch (err) {
      removePlaceholder(id);
      showToast('Error: ' + err.message);
    }
  }

  function removePlaceholder(id) {
    const ph = $grid.querySelector(`[data-placeholder-id="${id}"]`);
    if (ph) ph.remove();
  }

  // --- Bulk capture (polling-based for serverless) ---
  async function captureBulkURLs(urls) {
    const ids = urls.map((_, i) => 'bulk-' + Date.now() + '-' + i);
    ids.forEach(id => insertPlaceholder(id));
    showToast(`Adding ${urls.length} items...`);

    try {
      const res = await apiFetch('/api/capture-bulk', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ urls }),
      });
      const { batchId, completed: initialCompleted, status: initialStatus } = await res.json();

      // Handle results from inline processing
      if (initialCompleted > 0) {
        const statusRes = await apiFetch(`/api/batch-status?id=${batchId}`);
        const statusData = await statusRes.json();
        processResults(statusData.results, ids);
      }

      // If all done inline, no need to poll
      if (initialStatus === 'completed') {
        showToast(`Done! Added ${urls.length} items.`);
        return;
      }

      // Poll for remaining items
      const processed = new Set();
      const poll = setInterval(async () => {
        try {
          const statusRes = await apiFetch(`/api/batch-status?id=${batchId}`);
          const data = await statusRes.json();
          processResults(data.results, ids, processed);

          if (data.status === 'completed' || data.status === 'failed') {
            clearInterval(poll);
            showToast(`Done! Added ${data.completed} items.`);
            // Clean any remaining placeholders
            ids.forEach(id => removePlaceholder(id));
          }
        } catch {
          clearInterval(poll);
          ids.forEach(id => removePlaceholder(id));
        }
      }, 3000);
    } catch (err) {
      ids.forEach(id => removePlaceholder(id));
      showToast('Bulk capture failed');
    }
  }

  function processResults(results, ids, processed) {
    if (!results) return;
    const seen = processed || new Set();
    for (const r of results) {
      if (seen.has(r.index)) continue;
      seen.add(r.index);
      const phId = ids[r.index];
      if (r.item && !r.item.is_duplicate && !r.error) {
        const item = normalizeItem(r.item);
        replacePlaceholder(phId, item);
        enqueueForCuration(item.slug);
      } else {
        removePlaceholder(phId);
      }
    }
  }

  // --- Enrichment polling ---
  // Active polls, keyed by slug, so we don't stack them when a panel
  // re-renders or an item is captured twice in quick succession.
  const activePolls = new Map();

  /**
   * Watch an item in the DB until enrichment lands (or times out).
   *
   * The capture API returns with `enrichment_status='text_done'`. As the
   * server runs vision and candidate extraction, the status advances to
   * 'vision_done' and finally 'candidates_done'. Each tick re-renders the
   * grid card and diffs any open panel so new tags, image candidates, and
   * snippet candidates appear without a reload.
   *
   * Polls every 3s up to maxAttempts (default 14 → ~42s, generous to cover
   * the extra HTML-fetch + Claude call the candidates phase adds). Stops
   * early on `candidates_done` / `error`, or if the item is deleted.
   */
  function pollForEnrichment(slug, { maxAttempts = 14, interval = 3000 } = {}) {
    if (!slug) return null;
    const existing = activePolls.get(slug);
    if (existing) return existing;

    let attempts = 0;
    let timer = null;
    let cancelled = false;
    // Track the appearance we last rendered so ticks that don't change the
    // card skip the DOM replacement — the unconditional per-tick re-render was
    // re-creating each <img> every few seconds, i.e. the grid "blinking".
    let lastRenderedSig = $grid.querySelector(`.card[data-slug="${slug}"]`)?.dataset.renderSig ?? null;

    const stop = () => {
      cancelled = true;
      if (timer) { clearTimeout(timer); timer = null; }
      activePolls.delete(slug);
    };

    const tick = async () => {
      if (cancelled) return;
      attempts++;
      try {
        const data = (await Stello.apiGet(`/api/item?slug=${encodeURIComponent(slug)}`))?.item;
        if (!data) { stop(); return; }

        const item = normalizeItem(data);
        const idx = allItems.findIndex(i => i.slug === slug);
        if (idx >= 0) allItems[idx] = item;
        itemsBySlug[slug] = item;

        // Only mutate the DOM when the card's visible state actually changed.
        const sig = cardRenderSig(item);
        if (sig !== lastRenderedSig) {
          lastRenderedSig = sig;

          // Rebuild the related-items index so tag-based recommendations
          // reflect the new vision tags immediately.
          buildRelatedIndex();

          // Re-render the in-grid card (image + text content may have changed)
          const cardEl = $grid.querySelector(`.card[data-slug="${slug}"]`);
          if (cardEl) cardEl.outerHTML = renderCard(item, 0);

          // Push live updates into any open panel for this slug.
          PanelManager.refreshItem(slug);
        }

        const status = item.enrichment_status;
        if (status === 'candidates_done' || status === 'error' || attempts >= maxAttempts) {
          stop();
          return;
        }
      } catch {
        // Transient — keep polling until maxAttempts.
      }
      if (!cancelled) timer = setTimeout(tick, interval);
    };

    timer = setTimeout(tick, interval);
    const controller = { slug, stop };
    activePolls.set(slug, controller);
    return controller;
  }

  // Back-compat alias retained in case legacy call sites exist.
  const pollForReview = pollForEnrichment;

  // --- Toast notifications ---
  function showToast(msg) {
    let toast = document.getElementById('toast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'toast';
      toast.className = 'toast';
      document.body.appendChild(toast);
    }
    toast.textContent = msg;
    toast.classList.add('toast-visible');
    clearTimeout(toast._timer);
    toast._timer = setTimeout(() => toast.classList.remove('toast-visible'), 3000);
  }

  // --- Import tool panel body (wired when the panel opens) ---
  // --- Filters tool panel body (wire the search input when the panel opens) ---
  function setNeedsReview(on) {
    needsReviewOnly = !!on;
    syncReviewToggle();
    renderActiveFilters();
    renderGrid();
  }
  function syncReviewToggle() {
    const t = document.getElementById('filter-needs-review');
    if (!t) return;
    t.classList.toggle('is-on', needsReviewOnly);
    t.setAttribute('aria-pressed', needsReviewOnly ? 'true' : 'false');
  }

  function bindFilterPanelBody() {
    const $review = document.getElementById('filter-needs-review');
    if ($review) {
      syncReviewToggle();
      $review.addEventListener('click', () => setNeedsReview(!needsReviewOnly));
    }
    const $search = document.getElementById('filter-search');
    if (!$search) return;
    $search.value = tagSearchQuery;
    $search.addEventListener('input', () => {
      tagSearchQuery = $search.value;
      renderTagDrawer();
    });
  }

  function bindImportPanelBody() {
    const $importSubmit = document.querySelector('.panel-tool[data-tool="import"] .import-submit');
    const $importText = document.querySelector('.panel-tool[data-tool="import"] .import-textarea');
    if ($importSubmit && $importText) {
      $importSubmit.addEventListener('click', () => {
        const text = $importText.value;
        const urls = text.match(/https?:\/\/[^\s<>"']+/g);
        if (urls && urls.length > 0) {
          captureBulkURLs(urls);
          $importText.value = '';
          PanelManager.closeTool();
        } else {
          showToast('No URLs found');
        }
      });
    }

    const $fileInput = document.querySelector('.panel-tool[data-tool="import"] .import-file');
    if ($fileInput) {
      $fileInput.addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = () => {
          const text = reader.result;
          const urls = text.match(/https?:\/\/[^\s<>"')]+/g);
          if (urls && urls.length > 0) {
            const unique = [...new Set(urls)];
            captureBulkURLs(unique);
            PanelManager.closeTool();
            showToast(`Importing ${unique.length} URLs from file...`);
          } else {
            showToast('No URLs found in file');
          }
        };
        reader.readAsText(file);
        e.target.value = '';
      });
    }

    const $dropZone = document.querySelector('.panel-tool[data-tool="import"] .import-drop-zone');
    if ($dropZone) {
      $dropZone.addEventListener('dragover', (e) => { e.preventDefault(); $dropZone.classList.add('drag-over'); });
      $dropZone.addEventListener('dragleave', () => $dropZone.classList.remove('drag-over'));
      $dropZone.addEventListener('drop', (e) => {
        e.preventDefault();
        $dropZone.classList.remove('drag-over');
        const file = e.dataTransfer.files[0];
        if (file) {
          const reader = new FileReader();
          reader.onload = () => {
            const urls = reader.result.match(/https?:\/\/[^\s<>"')]+/g);
            if (urls) {
              const unique = [...new Set(urls)];
              captureBulkURLs(unique);
              PanelManager.closeTool();
            }
          };
          reader.readAsText(file);
        }
      });
    }
  }

  // --- Settings tool panel body (wired when the panel opens) ---
  async function loadSettingsIntoPanel() {
    const $panel = document.querySelector('.panel-tool[data-tool="settings"]');
    if (!$panel) return;
    const $keyInput = $panel.querySelector('.settings-key');
    const $profileInput = $panel.querySelector('.settings-profile');
    const $status = $panel.querySelector('.settings-status');

    try {
      const res = await apiFetch('/api/config');
      const config = await res.json();
      if (config.active_profile && config.profiles[config.active_profile]) {
        const p = config.profiles[config.active_profile];
        $keyInput.placeholder = p.has_key ? `Key: ${p.key_preview}` : 'Enter API key...';
        $profileInput.value = config.active_profile;
      }
      $status.textContent = config.active_profile ? `Active: ${config.active_profile}` : 'No API key configured';
    } catch { /* silent */ }

    const $save = $panel.querySelector('.settings-save');
    if ($save) {
      $save.addEventListener('click', async () => {
        const key = $keyInput.value;
        const profile = $profileInput.value || 'default';
        if (!key) { showToast('Enter an API key'); return; }
        try {
          await apiFetch('/api/config', {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ profile, key }),
          });
          $keyInput.value = '';
          $status.textContent = `Saved! Active: ${profile}`;
          showToast('API key saved');
        } catch {
          showToast('Failed to save key');
        }
      });
    }

    // --- Theme controls ---

    // Mode toggle (System / Light / Dark) + the current mode's six accents.
    const $modeToggle = $panel.querySelector('#theme-mode-toggle');
    const $swatches = $panel.querySelector('#accent-swatches');
    const renderThemeControls = () => {
      const p = ThemeManager.load();
      if ($modeToggle) {
        const mode = p.mode === 'light' || p.mode === 'dark' ? p.mode : 'system';
        $modeToggle.querySelectorAll('.theme-toggle-option').forEach(o =>
          o.classList.toggle('active', o.dataset.mode === mode));
      }
      if ($swatches) {
        const current = ThemeManager.resolvedAccent(p);
        $swatches.innerHTML = ThemeManager.ACCENTS[ThemeManager.resolvedMode(p)].map(a => {
          const label = a.charAt(0).toUpperCase() + a.slice(1);
          return `<button class="accent-swatch${a === current ? ' active' : ''}" data-accent="${a}" type="button" style="background:${ThemeManager.SWATCH[a]}" aria-label="${label} accent" aria-pressed="${a === current}" title="${label}"></button>`;
        }).join('');
      }
    };
    renderThemeControls();
    if ($modeToggle) {
      $modeToggle.addEventListener('click', (e) => {
        const opt = e.target.closest('[data-mode]');
        if (!opt) return;
        ThemeManager.setMode(opt.dataset.mode);
        renderThemeControls();
      });
    }
    if ($swatches) {
      $swatches.addEventListener('click', (e) => {
        const sw = e.target.closest('.accent-swatch');
        if (!sw) return;
        ThemeManager.setAccent(sw.dataset.accent);
        renderThemeControls();
      });
    }
    const onThemeChange = () => {
      if (!$panel.isConnected) { document.removeEventListener('stello:themechange', onThemeChange); return; }
      renderThemeControls();
    };
    document.addEventListener('stello:themechange', onThemeChange);

    // Grid columns stepper.
    const $cols = $panel.querySelector('#grid-columns');
    if ($cols) {
      const $label = $cols.querySelector('.grid-columns-label');
      const paint = () => {
        $label.textContent = zoomCols === 0 ? 'Auto' : `${zoomCols} column${zoomCols === 1 ? '' : 's'}`;
        $cols.querySelector('[data-step="-1"]').disabled = zoomCols === 0;
        $cols.querySelector('[data-step="1"]').disabled = zoomCols === MAX_COLS;
      };
      paint();
      $cols.addEventListener('click', (e) => {
        const b = e.target.closest('[data-step]');
        if (!b) return;
        setGridColumns(Math.max(0, Math.min(MAX_COLS, zoomCols + Number(b.dataset.step))));
        paint();
      });
    }

    // Account: which sign-in methods are linked, link Apple ID.
    (async () => {
      const session = await Stello.getSession();
      const cfg = await Stello.getAuthConfig();
      if (!session) return;
      const $email = $panel.querySelector('.settings-account-email');
      const $link = $panel.querySelector('.settings-link-apple');
      const $acctStatus = $panel.querySelector('.settings-account-status');
      const providers = new Set((session.identities || []).map(i => i.provider));
      if ($email) $email.textContent = session.user.email || 'Apple ID';
      if ($acctStatus) $acctStatus.textContent = providers.has('apple') ? 'Apple ID linked' : '';
      if ($link && cfg.apple && !providers.has('apple')) {
        $link.hidden = false;
        $link.addEventListener('click', () => Stello.signInWithApple({ link: true }));
      }
    })();

    // Logout — ends the session and redirects to the login page
    const $logout = $panel.querySelector('.settings-logout');
    if ($logout) {
      $logout.addEventListener('click', () => {
        if (window.Stello && Stello.signOut) Stello.signOut();
      });
    }

    // Version check
    if (window.Stello && Stello.checkForUpdate) {
      const update = await Stello.checkForUpdate(APP_VERSION);
      if (update && update.available) {
        const banner = document.createElement('div');
        banner.className = 'settings-update-banner';
        banner.innerHTML = `
          <div class="update-title">Update available: ${escHtml(update.latest)}</div>
          <div class="update-changelog">${escHtml(update.changelog || '')}</div>
          ${update.migration ? '<div class="update-migration">Migration required — see changelog</div>' : '<div class="update-migration">No migration needed</div>'}
          <div class="update-instructions"><code>git pull upstream main && git push</code></div>
          <div class="update-versions">Current: ${escHtml(update.current)} &middot; Latest: ${escHtml(update.latest)}</div>
        `;
        $panel.prepend(banner);

        // Show badge on settings button
        const $settingsBtn = document.getElementById('settings-btn');
        if ($settingsBtn && !$settingsBtn.querySelector('.update-badge')) {
          const badge = document.createElement('span');
          badge.className = 'update-badge';
          $settingsBtn.appendChild(badge);
        }
      }
    }
  }

  // =========================================================================
  // === PanelManager — owns ONE side panel (item OR tool) ===================
  // Dual-panel comparison was removed; it'll return on the item detail page
  // later (see BACKLOG.md). Item and tool panels are mutually exclusive on
  // the home grid — opening either implicitly closes the other so the grid
  // never has to compete with two panels for width.
  // =========================================================================
  const PanelManager = (function () {
    const MIN_WIDTH = 360;
    const MAX_WIDTH = 480;
    const STORAGE_KEY = 'stello.panels';

    const state = {
      slug: null,         // open item slug, or null
      tool: null,         // 'filters' | 'settings' | 'import' | null
      originSlug: null,   // card slug that triggered the item panel (for focus return)
    };

    let $container, $announcer;

    // Panel width is always 25% of viewport (rounded), clamped to [320, 480].
    // No user-resize affordance — viewport drives it, simple and predictable.
    // Plus `getPanelExtra()`: with fixed card sizes the grid drops a column
    // when the panel opens, and the panel absorbs the leftover strip.
    function computePanelWidth() {
      return Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, Math.round(window.innerWidth * 0.25))) + getPanelExtra();
    }
    function applyWidth() {
      const panel = $container && $container.querySelector('.panel');
      if (panel) panel.style.setProperty('--panel-width', computePanelWidth() + 'px');
    }

    // ---- State <-> URL ----
    // `panel1` is read for back-compat with bookmarks from the dual-panel era;
    // writes only ever emit the new `panel` key.
    function syncFromURL() {
      const params = new URLSearchParams(window.location.search);
      const s = params.get('panel') || params.get('panel1');
      if (s && itemsBySlug[s]) { state.slug = s; return true; }
      return false;
    }
    function syncToURL(push) {
      const params = new URLSearchParams(window.location.search);
      params.delete('panel'); params.delete('panel1'); params.delete('panel2');
      if (state.slug) params.set('panel', state.slug);
      const query = params.toString();
      const newURL = window.location.pathname + (query ? '?' + query : '') + window.location.hash;
      history[push ? 'pushState' : 'replaceState']({ panel: state.slug }, '', newURL);
    }

    // ---- State <-> localStorage ----
    // Stores only the open slug now — panel width is derived from viewport
    // at render time. Tolerates legacy keys (`slugs[]`, `width`, `widths[]`,
    // `toolWidth`) on read so old localStorage entries rehydrate cleanly.
    function syncFromStorage() {
      try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (!raw) return false;
        const data = JSON.parse(raw);
        if (typeof data.slug === 'string' && itemsBySlug[data.slug]) {
          state.slug = data.slug;
        } else if (Array.isArray(data.slugs) && data.slugs[0] && itemsBySlug[data.slugs[0]]) {
          state.slug = data.slugs[0];
        }
        return !!state.slug;
      } catch { return false; }
    }
    function syncToStorage() {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify({
          slug: state.slug,
        }));
      } catch { /* silent */ }
    }

    // ---- Active card color line ----
    function updateActiveCards() {
      document.querySelectorAll('.card').forEach(card => {
        const slug = card.dataset.slug;
        if (!slug) return;
        const isActive = slug === state.slug;
        card.classList.toggle('card-active', isActive);
        if (isActive) {
          const color = dominantColor(itemsBySlug[slug]);
          card.style.setProperty('--card-active-color', color);
        } else {
          card.style.removeProperty('--card-active-color');
        }
      });
    }

    // ---- Render ----
    function render() {
      if (!$container) return;

      // Tear down whatever's currently mounted. At most one panel can be open
      // at a time (item OR tool), so this is a single create-and-replace pass.
      Array.from($container.children).forEach(el => el.remove());

      if (state.tool) {
        const toolPanel = renderToolPanel(state.tool);
        if (toolPanel) $container.appendChild(toolPanel);
        syncHighlightsToOpenPanels([]);
        return;
      }

      if (!state.slug) { syncHighlightsToOpenPanels([]); return; }
      const item = itemsBySlug[state.slug];
      if (!item) { syncHighlightsToOpenPanels([]); return; }

      // Mac panel: no header bar. The cover bleeds to the top and a
      // floating glass close button sits over it (top-right).
      const panel = document.createElement('aside');
      panel.className = 'panel panel-item';
      panel.dataset.slug = state.slug;
      panel.setAttribute('role', 'region');
      panel.setAttribute('aria-label', `Item detail: ${item.title || state.slug}`);
      panel.setAttribute('tabindex', '-1');
      panel.style.setProperty('--panel-width', computePanelWidth() + 'px');

      const closeBtn = document.createElement('button');
      closeBtn.className = 'panel-float-close';
      closeBtn.type = 'button';
      closeBtn.setAttribute('aria-label', 'Close panel');
      closeBtn.title = 'Close';
      closeBtn.innerHTML = icon('x');
      closeBtn.addEventListener('click', close);
      panel.appendChild(closeBtn);

      const body = document.createElement('div');
      body.className = 'panel-body';
      panel.appendChild(body);
      $container.appendChild(panel);

      if (panelPreview.slug !== state.slug) { panelPreview.slug = state.slug; panelPreview.path = null; }
      rerenderPanelBody(body, item);
      bindPanelBody(body, state.slug);

      syncHighlightsToOpenPanels([state.slug]);
    }

    // ---- Tool panel rendering ----
    const TOOL_TITLES = { filters: 'Filters', settings: 'Settings', import: 'Import URLs' };
    const TOOL_TEMPLATES = { filters: 'tpl-filters', settings: 'tpl-settings', import: 'tpl-import' };

    function renderToolPanel(type) {
      const tpl = document.getElementById(TOOL_TEMPLATES[type]);
      if (!tpl) return null;

      const panel = document.createElement('aside');
      panel.className = 'panel panel-tool';
      panel.dataset.tool = type;
      panel.setAttribute('role', 'region');
      panel.setAttribute('aria-label', TOOL_TITLES[type]);
      panel.setAttribute('tabindex', '-1');
      panel.style.setProperty('--panel-width', computePanelWidth() + 'px');

      const header = document.createElement('header');
      header.className = 'panel-header';
      const title = document.createElement('div');
      title.className = 'panel-tool-title';
      title.textContent = TOOL_TITLES[type];
      header.appendChild(title);

      const actions = document.createElement('div');
      actions.className = 'panel-header-actions';
      const closeBtn = document.createElement('button');
      closeBtn.className = 'panel-close';
      closeBtn.type = 'button';
      closeBtn.setAttribute('aria-label', 'Close panel');
      closeBtn.innerHTML = icon('x');
      closeBtn.addEventListener('click', closeTool);
      actions.appendChild(closeBtn);
      header.appendChild(actions);
      panel.appendChild(header);

      const body = document.createElement('div');
      body.className = 'panel-body';
      body.appendChild(tpl.content.cloneNode(true));
      panel.appendChild(body);

      // Notify listeners the tool body was freshly rendered
      requestAnimationFrame(() => {
        document.dispatchEvent(new CustomEvent('toolpanel:rendered', { detail: { type, body } }));
      });

      return panel;
    }

    function openTool(type) {
      if (state.tool === type) { closeTool(); return; }
      // Mutually exclusive with item panels.
      const previousItem = state.slug;
      state.slug = null;
      state.originSlug = null;
      state.tool = type;
      syncToURL(true);
      syncToStorage();
      render();
      updateActiveCards();
      updateToolButtons();
      announce(`${TOOL_TITLES[type]} opened`);
      if (previousItem) notifyCaptureSlugClosed(previousItem);
    }

    function closeTool() {
      if (!state.tool) return;
      state.tool = null;
      syncToStorage();
      render();
      updateToolButtons();
      announce('Tool panel closed');
    }

    function updateToolButtons() {
      ['filter-panel-btn', 'import-btn', 'settings-btn'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.classList.remove('is-active');
      });
      const activeId = state.tool === 'filters' ? 'filter-panel-btn'
        : state.tool === 'import' ? 'import-btn'
        : state.tool === 'settings' ? 'settings-btn'
        : null;
      if (activeId) document.getElementById(activeId)?.classList.add('is-active');
    }

    // ---- Announce ----
    function announce(msg) {
      if (!$announcer) return;
      $announcer.textContent = '';
      // Force re-read
      requestAnimationFrame(() => { $announcer.textContent = msg; });
    }

    // ---- Open / close / replace ----
    function open(slug, opts) {
      opts = opts || {};
      if (!itemsBySlug[slug]) return;

      // Same item already open? Flash + focus.
      if (state.slug === slug) {
        const card = document.querySelector(`.card[data-slug="${cssSelectorEscape(slug)}"]`);
        if (card) {
          card.classList.add('card-flash');
          setTimeout(() => card.classList.remove('card-flash'), 400);
        }
        focus();
        return;
      }

      // Opening an item closes any open tool panel (mutually exclusive).
      if (state.tool) {
        state.tool = null;
        updateToolButtons();
      }

      const previousSlug = state.slug;
      state.slug = slug;
      state.originSlug = opts.originCard ? opts.originCard.dataset.slug : null;

      syncToURL(true);
      syncToStorage();
      render();
      updateActiveCards();
      announce(`Panel opened: ${itemsBySlug[slug].title || slug}`);
      focus();

      if (previousSlug && previousSlug !== slug) notifyCaptureSlugClosed(previousSlug);
      recordOpen(slug);
    }

    // Revisit tracking, once per item per page load (Apple: StelloStore.recordOpen).
    const openedThisSession = new Set();
    function recordOpen(slug) {
      if (openedThisSession.has(slug)) return;
      openedThisSession.add(slug);
      postItemUpdate(slug, { record_open: true });
    }

    function close() {
      if (!state.slug) return;
      const closedSlug = state.slug;
      const originSlug = state.originSlug;
      state.slug = null;
      state.originSlug = null;

      syncToURL(true);
      syncToStorage();
      render();
      updateActiveCards();
      announce('Panel closed');

      if (originSlug) {
        const card = document.querySelector(`.card[data-slug="${cssSelectorEscape(originSlug)}"]`);
        if (card) card.focus({ preventScroll: false });
      }

      notifyCaptureSlugClosed(closedSlug);
    }

    function closeFocused() {
      if (state.tool) { closeTool(); return; }
      if (state.slug) close();
    }

    function focus() {
      const panel = $container && $container.querySelector('.panel');
      if (panel) panel.focus({ preventScroll: false });
    }

    // ---- Keyboard shortcuts ----
    function bindKeys() {
      document.addEventListener('keydown', (e) => {
        if (e.target && e.target.matches && e.target.matches('input, textarea')) return;
        if (e.key === 'Escape') { closeFocused(); return; }
        if (e.key === '1') { focus(); return; }
        if (e.key === '0') {
          const first = document.querySelector('.card');
          if (first) first.focus();
        }
      });
    }

    // ---- Window resize ----
    // Panel width is 25% of viewport (clamped to [320, 480]). When the
    // viewport changes, recompute and apply to whatever panel is open.
    let resizeTimeout = null;
    function onWindowResize() {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(() => {
        const panel = $container && $container.querySelector('.panel');
        if (panel) panel.style.setProperty('--panel-width', computePanelWidth() + 'px');
      }, 120);
    }

    // ---- Init ----
    function init() {
      $container = document.getElementById('panels-container');
      $announcer = document.getElementById('panel-announcer');
      if (!$container) return;

      // Load precedence: URL first, else localStorage. Tool panel is
      // session-ephemeral and never auto-restored.
      if (!syncFromURL()) syncFromStorage();

      render();
      updateActiveCards();

      window.addEventListener('popstate', () => {
        if (!syncFromURL()) { state.slug = null; state.tool = null; }
        render();
        updateActiveCards();
        updateToolButtons();
      });
      window.addEventListener('resize', onWindowResize);
      bindKeys();
    }

    function cssSelectorEscape(s) {
      if (window.CSS && CSS.escape) return CSS.escape(s);
      return String(s).replace(/([^a-zA-Z0-9_-])/g, '\\$1');
    }

    function refreshAfterGridRender() {
      updateActiveCards();
      // Also re-apply the related-items outline. `highlightRelated` only
      // ran inside `render()` (panel open/close), so cards that came into
      // existence later — when a week is expanded for the first time or a
      // capture inserts a fresh card — never picked up `.card-focused`.
      // The highlight algorithm is already diff-based, so re-running it
      // on every grid render is cheap.
      syncHighlightsToOpenPanels(state.slug ? [state.slug] : []);
    }

    function getOpenSlug() { return state.slug; }

    // Re-renders the open panel's body + footer from the current
    // itemsBySlug snapshot. Called by pollForEnrichment when background
    // vision writes land — lets tag pills and the image update live
    // without re-mounting the whole panel.
    function refreshItem(slug) {
      if (!$container || state.slug !== slug) return;
      const item = itemsBySlug[slug];
      const body = $container.querySelector('.panel-item .panel-body');
      if (item && body) rerenderPanelBody(body, item);
    }

    return {
      init, open, close, focus, applyWidth,
      openTool, closeTool,
      getOpenSlug,
      refreshAfterGridRender, refreshItem,
      state, // expose for debugging
    };
  })();

  // --- Start ---
  document.addEventListener('DOMContentLoaded', () => {
    init();
    bindPasteHandler();
  });
})();
