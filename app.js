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
    'dots-three': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M140,128a12,12,0,1,1-12-12A12,12,0,0,1,140,128ZM48,116a12,12,0,1,0,12,12A12,12,0,0,0,48,116Zm160,0a12,12,0,1,0,12,12A12,12,0,0,0,208,116Z"/></svg>',
  };
  function icon(name) { return ICONS[name] || ''; }

  // --- State ---
  let allItems = [];
  let itemsBySlug = {};      // slug -> item lookup
  let activeTags = [];      // [{tag, category}]
  let searchQuery = '';
  let relatedIndex = {};     // slug -> Set of related slugs
  let loadedWeeks = new Set(); // track which weeks have been rendered

  // --- Category colors (for pills) ---
  const CAT_CLASS = {
    format: 'tag-format',
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
  const ThemeManager = {
    STORAGE_KEY: 'stello.theme',
    defaults: { mode: 'dark', accent: 'amber' },

    load() {
      try {
        const raw = localStorage.getItem(this.STORAGE_KEY);
        return raw ? { ...this.defaults, ...JSON.parse(raw) } : { ...this.defaults };
      } catch { return { ...this.defaults }; }
    },

    apply(prefs) {
      document.documentElement.setAttribute('data-theme', prefs.mode);
      document.documentElement.setAttribute('data-accent', prefs.accent);
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
      const prefs = this.load();
      this.apply(prefs);
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

    // Load items from Supabase, paging through results (default limit is 1000).
    // First-page-first: render with the most recent 1000 items immediately,
    // then stream older history in the background. Subsequent pages cover
    // older weeks that are collapsed by default, so their headers can be
    // appended without disturbing the already-rendered first weeks.
    const client = Stello.getClient();
    const userId = Stello.getUserId();
    const PAGE = 1000;

    async function fetchItemsPage(from) {
      const { data, error } = await client
        .from('items')
        .select('*')
        .eq('user_id', userId)
        .order('added_at', { ascending: false })
        .range(from, from + PAGE - 1);
      if (error) {
        console.error('Failed to load items from Supabase:', error.message);
        return [];
      }
      return data || [];
    }

    const firstPage = await fetchItemsPage(0);
    allItems = firstPage.map(normalizeItem);
    sortItemsByAddedAt(allItems);
    itemsBySlug = {};
    allItems.forEach(item => { itemsBySlug[item.slug] = item; });

    buildRelatedIndex();
    renderStats();
    renderGrid();
    injectHeaderIcons();
    bindEvents();
    PanelManager.init();
    startGridColsObserver();

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
        // probes + Supabase writes), so an idle callback can be starved.
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
          const client = Stello.getClient();
          const { data } = await client.from('items').select('*')
            .eq('slug', item.slug).eq('user_id', Stello.getUserId())
            .single();
          if (!data) continue;

          const refreshed = normalizeItem(data);
          const idx = allItems.findIndex(i => i.slug === item.slug);
          if (idx >= 0) allItems[idx] = refreshed;
          itemsBySlug[item.slug] = refreshed;

          const cardEl = $grid.querySelector(`.card[data-slug="${item.slug}"]:not(.card-question)`);
          if (cardEl) cardEl.outerHTML = renderCard(refreshed, 0);
          PanelManager.refreshItem(item.slug);

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
  // 50 items per session to avoid hammering Supabase on first visit.
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
    const client = Stello.getClient();
    const userId = Stello.getUserId();
    if (!client || !userId) return;

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
    // the whole queue drain. 4 concurrent fetches is well below Supabase
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
          const { error } = await client.from('items')
            .update({ images: JSON.stringify(imgs) })
            .eq('slug', item.slug)
            .eq('user_id', userId);
          if (error) continue;

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

  /** Normalize a Supabase item row to match the frontend shape */
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

  // Default: only the first category (domain) is expanded; everything else collapsed.
  let expandedCategories = new Set(['domain']);
  let tagSearchQuery = '';

  const CATEGORY_LABELS = {
    domain: 'Domains', subject: 'Subjects', format: 'Formats',
    tool: 'Tools', style: 'Styles', mood: 'Moods',
    location: 'Locations', color: 'Colors',
  };

  function renderTagDrawer() {
    const el = $drawer();
    if (!el) return;
    const map = collectTags();
    const order = ['domain', 'subject', 'format', 'tool', 'style', 'mood', 'location', 'color'];
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

  // --- Grid ---
  function getFilteredItems() {
    return allItems.filter(item => {
      if (searchQuery) {
        const q = searchQuery.toLowerCase();
        const inTitle = item.title.toLowerCase().includes(q);
        const inSummary = (item.summary || '').toLowerCase().includes(q);
        const inTags = item.tags.some(t => t.tag.toLowerCase().includes(q));
        if (!inTitle && !inSummary && !inTags) return false;
      }
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

  function renderWeekCards(weekKey) {
    const container = $grid.querySelector(`.masonry-section[data-week="${weekKey}"]`);
    const header = $grid.querySelector(`.date-section-header[data-week="${weekKey}"]`);
    const toggleLink = header?.querySelector('.week-show-link');
    if (!container) return;

    const items = getFilteredItems();
    const weekItems = items.filter(i => getWeekKey(i.added_at) === weekKey);
    const entries = weekItems.map((item, idx) => ({ item, idx }));

    container.innerHTML = renderColumnsHTML(entries, currentGridCols());
    container.style.display = '';
    loadedWeeks.add(weekKey);
    header?.classList.add('is-expanded');
    if (header) {
      header.setAttribute('aria-expanded', 'true');
      header.setAttribute('aria-label', 'Collapse week');
    }
    if (toggleLink) toggleLink.innerHTML = icon('caret-up');
    PanelManager.refreshAfterGridRender();
  }

  function collapseWeek(weekKey) {
    const container = $grid.querySelector(`.masonry-section[data-week="${weekKey}"]`);
    const header = $grid.querySelector(`.date-section-header[data-week="${weekKey}"]`);
    const toggleLink = header?.querySelector('.week-show-link');
    if (!container) return;
    container.innerHTML = '';
    container.style.display = 'none';
    loadedWeeks.delete(weekKey);
    header?.classList.remove('is-expanded');
    if (header) {
      header.setAttribute('aria-expanded', 'false');
      header.setAttribute('aria-label', 'Expand week');
    }
    if (toggleLink) toggleLink.innerHTML = icon('caret-down');
    PanelManager.refreshAfterGridRender();
  }

  const isSearchActive = () => searchQuery || activeTags.length > 0;

  // ---- Grid column-count observer + flex-masonry distribution ----
  // The grid is N flex columns (`.masonry-col`), each a vertical stack of
  // cards. `distributeIntoColumns` packs cards greedily into the
  // currently-shortest column so the column heights end up balanced —
  // same visual result as column-count masonry, but with rock-solid
  // flex layout instead of WebKit's flicker-prone column engine.
  //
  // `updateGridCols` watches `.main-content`'s width via ResizeObserver
  // and re-renders loaded weeks when the column count changes.
  function computeGridCols(width) {
    if (width <= 500) return 2;
    if (width <= 768) return 3;
    if (width <= 1200) return 4;
    return 5;
  }
  const COL_WIDTH_ESTIMATE = 250; // px; rough enough for column-balance
  function estimateCardHeight(item) {
    if (item.image_width && item.image_height) {
      return COL_WIDTH_ESTIMATE * (item.image_height / item.image_width);
    }
    if (item.has_image) {
      // OG default 1200/630 aspect ratio
      return COL_WIDTH_ESTIMATE * (630 / 1200);
    }
    // Text/placeholder cards are clamped by CSS to ~242px regardless of width.
    return 242;
  }
  function distributeIntoColumns(entries, colCount) {
    const cols = Array.from({ length: colCount }, () => ({ entries: [], height: 0 }));
    for (const entry of entries) {
      let shortest = cols[0];
      for (const c of cols) if (c.height < shortest.height) shortest = c;
      shortest.entries.push(entry);
      shortest.height += estimateCardHeight(entry.item);
    }
    return cols.map(c => c.entries);
  }
  function renderColumnsHTML(entries, colCount) {
    const cols = distributeIntoColumns(entries, colCount);
    return cols
      .map(colEntries => `<div class="masonry-col">${colEntries.map(e => renderCard(e.item, e.idx)).join('')}</div>`)
      .join('');
  }
  function currentGridCols() {
    const v = document.documentElement.style.getPropertyValue('--grid-cols');
    const n = parseInt(v, 10);
    return Number.isFinite(n) && n > 0 ? n : 5;
  }
  function redistributeLoadedWeeks() {
    const colCount = currentGridCols();
    const items = getFilteredItems();
    loadedWeeks.forEach(weekKey => {
      const section = $grid.querySelector(`.masonry-section[data-week="${weekKey}"]`);
      if (!section) return;
      const weekItems = items.filter(i => getWeekKey(i.added_at) === weekKey);
      const entries = weekItems.map((item, idx) => ({ item, idx }));
      section.innerHTML = renderColumnsHTML(entries, colCount);
    });
    PanelManager.refreshAfterGridRender();
    // refreshAfterGridRender re-applies .card-active for the open item,
    // but not .card-focused (related-card outlines). Reapply those too —
    // otherwise the first panel-open at a viewport where the column
    // count drops would wipe the freshly-applied highlights, because
    // ResizeObserver fires AFTER PanelManager.render() has already set
    // them on the previous DOM nodes that we just rewrote.
    const openSlug = PanelManager.getOpenSlug();
    syncHighlightsToOpenPanels(openSlug ? [openSlug] : []);
  }
  let lastGridCols = null;
  function updateGridCols() {
    const mc = document.querySelector('.main-content');
    if (!mc) return;
    const cols = computeGridCols(mc.offsetWidth);
    if (cols === lastGridCols) return;
    lastGridCols = cols;
    document.documentElement.style.setProperty('--grid-cols', String(cols));
    redistributeLoadedWeeks();
  }
  function startGridColsObserver() {
    updateGridCols();
    const mc = document.querySelector('.main-content');
    if (!mc) return;
    if (typeof ResizeObserver === 'function') {
      const ro = new ResizeObserver(updateGridCols);
      ro.observe(mc);
    } else {
      window.addEventListener('resize', updateGridCols);
    }
  }

  function sortItemsByAddedAt(arr) {
    arr.sort((a, b) => {
      const da = a.added_at ? new Date(a.added_at).getTime() : 0;
      const db = b.added_at ? new Date(b.added_at).getTime() : 0;
      return db - da;
    });
  }

  // Append week headers for any week not yet present in the grid DOM. Used
  // after background-loaded older pages land — extends history downward
  // without re-rendering (and thus visually disturbing) the already-painted
  // first weeks. Skipped while a search/filter is active because that mode
  // re-renders the whole grid through renderGrid() anyway.
  function appendOlderWeeks() {
    if (isSearchActive()) { renderGrid(); return; }
    const items = getFilteredItems();
    const weeks = groupByWeek(items);
    const colCount = currentGridCols();
    let html = '';
    weeks.forEach(week => {
      if ($grid.querySelector(`.date-section-header[data-week="${week.key}"]`)) return;
      const isLoaded = loadedWeeks.has(week.key);
      const caret = icon(isLoaded ? 'caret-up' : 'caret-down');
      const aria = isLoaded ? 'Collapse week' : 'Expand week';
      const headerClass = 'date-section-header' + (isLoaded ? ' is-expanded' : '');
      html += `<div class="${headerClass}" data-week="${week.key}" role="button" tabindex="0" aria-expanded="${isLoaded}" aria-label="${aria}" style="grid-column: 1 / -1"><span>${week.label}</span><span class="week-show-link" aria-hidden="true">${caret}</span></div>`;
      html += `<div class="masonry-section" data-week="${week.key}" style="${isLoaded ? '' : 'display:none'}">${isLoaded ? renderColumnsHTML(week.items, colCount) : ''}</div>`;
    });
    if (html) $grid.insertAdjacentHTML('beforeend', html);
  }

  function renderGrid() {
    const items = getFilteredItems();

    if (items.length === 0) {
      $grid.innerHTML = '<div class="no-results">No items match your filters.</div>';
      return;
    }

    const weeks = groupByWeek(items);
    const searching = isSearchActive();

    // When searching/filtering, reset lazy state and show all results
    if (searching) {
      loadedWeeks = new Set(weeks.map(w => w.key));
    } else {
      // Default: only first week is loaded
      loadedWeeks = new Set();
      if (weeks.length > 0) loadedWeeks.add(weeks[0].key);
    }

    const colCount = currentGridCols();
    let html = '';
    weeks.forEach((week, wi) => {
      const isLoaded = loadedWeeks.has(week.key);
      const caret = isLoaded ? icon('caret-up') : icon('caret-down');
      const aria = isLoaded ? 'Collapse week' : 'Expand week';
      const headerClass = 'date-section-header' + (isLoaded ? ' is-expanded' : '');
      html += `<div class="${headerClass}" data-week="${week.key}" role="button" tabindex="0" aria-expanded="${isLoaded}" aria-label="${aria}" style="grid-column: 1 / -1"><span>${week.label}</span><span class="week-show-link" aria-hidden="true">${caret}</span></div>`;
      html += `<div class="masonry-section" data-week="${week.key}" style="${isLoaded ? '' : 'display:none'}">`;
      if (isLoaded) {
        html += renderColumnsHTML(week.items, colCount);
      }
      html += '</div>';
    });

    $grid.innerHTML = html;

    // Tag each direct child with a --idx so the post-login stagger reveal
    // (style.css) can cascade in. Cheap enough to run on every render.
    // Cards now live inside `.masonry-col` wrappers — walk descendants
    // instead of direct children.
    const children = $grid.children;
    for (let i = 0; i < children.length; i++) {
      children[i].style.setProperty('--idx', i);
      const cards = children[i].querySelectorAll('.card');
      for (let j = 0; j < cards.length; j++) {
        cards[j].style.setProperty('--idx', j);
      }
    }

    PanelManager.refreshAfterGridRender();
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

  function renderCard(item, idx) {
    let thumbHtml;
    const hasImage = item.has_image && item.image_path;
    const vtName = `card-${cssSlug(item.slug)}`;

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
    } else if (hasTextContent) {
      const hue = PLACEHOLDER_HUES[idx % PLACEHOLDER_HUES.length];
      const truncated = escHtml(truncateWords(cleanSummary(item.summary), 200));
      const light = ThemeManager.load().mode === 'light';
      thumbHtml = `<div class="card-text-content" style="view-transition-name:${vtName};background:hsl(${hue},${light ? '12%,92%' : '15%,13%'})">${truncated}</div>`;
    } else {
      const hue = PLACEHOLDER_HUES[idx % PLACEHOLDER_HUES.length];
      const letter = (item.title || '?')[0].toUpperCase();
      const light = ThemeManager.load().mode === 'light';
      thumbHtml = `<div class="card-placeholder" style="view-transition-name:${vtName};background:hsl(${hue},${light ? '10%,93%' : '20%,16%'})">${letter}</div>`;
    }

    // URL pill — bottom-right. Default: 20% color bg + white text.
    // Hover: fully opaque bg + color-tinted text (or dark if no color tag).
    const pillColor = dominantColor(item);
    const hasColorTag = pillColor !== '#ffffff';
    const pillBg = hasColorTag ? hexToRgba(pillColor, 0.2) : 'rgba(255, 255, 255, 0.2)';
    const pillBgHover = '#ffffff';
    const pillColorHover = hasColorTag ? pillColor : '#1a1a17';
    const urlPill = item.domain
      ? `<a class="card-url-pill"${item.source_url ? ` href="${escHtml(item.source_url).replace(/"/g, '&quot;')}" target="_blank" rel="noopener"` : ''} style="--pill-bg:${pillBg};--pill-bg-hover:${pillBgHover};--pill-color-hover:${pillColorHover}" onclick="event.stopPropagation()">${escHtml(item.domain)}</a>`
      : '';

    const cardClass = hasImage ? ' card-visual' : (hasTextContent ? ' card-text' : '');

    return `<div class="card${cardClass}" data-slug="${item.slug}" tabindex="-1">
      <div class="card-visual-area">
        ${thumbHtml}
        <div class="card-title-badge">${escHtml(item.title || '')}</div>
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

  // Preset why-saved reasons. Suggested reasons from enrichment_candidates
  // are merged alongside these at render time.
  const PRESET_REASONS = [
    { value: 'visual-inspiration', label: 'Visual inspiration' },
    { value: 'useful-tool', label: 'Useful tool' },
    { value: 'knowledge-reference', label: 'Knowledge reference' },
    { value: 'style-catalog', label: 'Style catalog' },
    { value: 'conceptual-reference', label: 'Conceptual reference' },
    { value: 'practical-benchmark', label: 'Practical benchmark' },
  ];

  // Builds the expanded-body HTML used inside a side panel.
  // Order: slider → description (summary + markdown) → capture form
  // (only for items still pending review) → snippets.
  // `sharedTagSet`: optional Set<string> of "category:tag" keys to highlight with .tag-shared.
  function buildPanelBodyHTML(item, sharedTagSet) {
    return [
      renderPanelSliderHTML(item),
      `<div class="card-expanded-body">
        ${item.summary ? `<div class="card-expanded-summary">${escHtml(cleanSummary(item.summary))}</div>` : ''}
        <div class="card-expanded-md" data-slug="${item.slug}"></div>
      </div>`,
      renderPanelCaptureFormHTML(item),
      renderPanelSnippetsHTML(item),
    ].join('');
  }

  // ---- Panel slider (main image + thumbnails + upload tile) ----
  // Two independent states:
  //  - cover:   which image is item.images[*].is_primary (server truth)
  //  - preview: which thumb is currently shown in the main area (client only)
  // On load preview == cover. Clicking a thumb swaps preview only. Setting
  // cover happens via (a) clicking an already-previewed thumb again OR
  // (b) the "Set as cover" pill on the main image (only shown when
  // preview != cover).
  function renderPanelSliderHTML(item) {
    const images = Array.isArray(item.images) ? item.images : [];
    const candidates = (item.enrichment_candidates && Array.isArray(item.enrichment_candidates.images))
      ? item.enrichment_candidates.images : [];

    // Seed from og_image_path when images[] is empty (legacy items).
    const seeded = images.length === 0 && item.image_path
      ? [{ path: item.image_path, source: 'og', is_primary: true }]
      : images;

    const cover = seeded.find(i => i.is_primary) || seeded[0];
    const coverPath = cover?.path || '';
    // Preview defaults to cover on initial render; click handlers keep
    // it in sync with whichever thumb the user chose.
    const previewPath = coverPath;

    if (!coverPath && !candidates.length) {
      return `<div class="panel-image-slider" data-slug="${item.slug}" data-cover-path="">
        <div class="panel-image-main panel-image-empty"></div>
        <div class="panel-image-thumbs">${renderUploadTileHTML()}</div>
      </div>`;
    }

    const thumbs = [
      ...seeded.map(img => renderThumbHTML(img, {
        isPreview: img.path === previewPath,
        isCover: img.path === coverPath,
      })),
      ...candidates
        .filter(c => !seeded.some(i => i.path === c.path))
        .map(c => renderCandidateThumbHTML(c)),
      renderUploadTileHTML(),
    ].join('');

    return `<div class="panel-image-slider" data-slug="${item.slug}" data-cover-path="${escAttr(coverPath)}">
      <div class="panel-image-main">
        ${coverPath ? `<img src="${escAttr(previewPath)}" alt="${escAttr(cover?.label || '')}" data-preview-path="${escAttr(previewPath)}">` : ''}
        ${renderPanelImageActionsHTML()}
      </div>
      <div class="panel-image-thumbs">${thumbs}</div>
    </div>`;
  }

  function renderThumbHTML(img, state) {
    const { isPreview, isCover } = state || {};
    const cls = [
      'panel-image-thumb',
      isPreview && 'is-active',
      isCover && 'is-cover',
    ].filter(Boolean).join(' ');
    return `<button type="button" class="${cls}" data-path="${escAttr(img.path)}" data-source="${escAttr(img.source || 'og')}" title="${escAttr(img.label || '')}"><img src="${escAttr(img.path)}" alt=""></button>`;
  }

  function renderCandidateThumbHTML(cand) {
    const path = cand.path || cand.url || '';
    if (!path) return '';
    return `<button type="button" class="panel-image-thumb is-candidate" data-path="${escAttr(path)}" data-source="extracted" title="${escAttr(cand.label || 'Suggested image')}"><img src="${escAttr(path)}" alt=""><span class="panel-image-thumb-add">+</span></button>`;
  }

  // Action buttons at bottom-right of the main image: "Set as cover"
  // (crosshair) and "Remove image" (trash, red). 20px circles, 16px
  // icons, same translucent-dark backdrop as .card-url-pill.
  function renderPanelImageActionsHTML() {
    return `<div class="panel-image-actions">
      <button type="button" class="panel-image-action-btn js-set-cover" title="Set as cover" aria-label="Set as cover">${icon('crosshair')}</button>
      <button type="button" class="panel-image-action-btn is-danger js-remove-image" title="Remove Image" aria-label="Remove Image">${icon('trash')}</button>
    </div>`;
  }

  function renderUploadTileHTML() {
    // Use a <label> so the native file picker opens on click without a
    // programmatic .click() (which can get flaky under event delegation).
    return `<label class="panel-image-upload-tile" aria-label="Upload image">
      <span>+</span>
      <input type="file" accept="image/*" class="sr-only">
    </label>`;
  }

  // ---- Capture form (why-saved + what-works) ----
  // Only rendered while the item is still pending review. Once the user
  // clicks Save (or Skip), the server flips needs_review=false and this
  // section disappears on the next refresh.
  function renderPanelCaptureFormHTML(item) {
    if (item.needs_review !== true) return '';

    const activeIntents = new Set(
      (item.tags || []).filter(t => t.category === 'intent').map(t => t.tag)
    );
    const suggested = (item.enrichment_candidates && Array.isArray(item.enrichment_candidates.reasons))
      ? item.enrichment_candidates.reasons : [];
    const suggestedNotInPreset = suggested.filter(r =>
      !PRESET_REASONS.some(p => p.value === r)
    );

    const whatWorks = extractSection(item.body_markdown, 'What Makes It Work');

    const presetChips = PRESET_REASONS.map(r =>
      `<button type="button" class="q-toggle${activeIntents.has(r.value) ? ' active' : ''}" data-value="${escAttr(r.value)}">${escHtml(r.label)}</button>`
    ).join('');

    const suggestedChips = suggestedNotInPreset.map(r =>
      `<button type="button" class="q-toggle q-toggle-suggested${activeIntents.has(r) ? ' active' : ''}" data-value="${escAttr(r)}" title="Suggested">${escHtml(humanizeReason(r))}</button>`
    ).join('');

    return `<div class="panel-capture-form">
      <p class="question-label">Why did you save this?</p>
      <div class="question-options">
        ${presetChips}
        ${suggestedChips}
        <input class="q-custom-reason" type="text" placeholder="Other reason…">
      </div>
      <p class="question-label">What makes it work?</p>
      <textarea class="question-text" placeholder="Optional — what caught your eye?">${escHtml(whatWorks || '')}</textarea>
      <div class="question-actions">
        <button type="button" class="q-save">Save</button>
        <button type="button" class="q-skip">Skip</button>
      </div>
    </div>`;
  }

  function humanizeReason(r) {
    return String(r || '').replace(/-/g, ' ').replace(/^\w/, c => c.toUpperCase());
  }

  // ---- Snippets ----
  function renderPanelSnippetsHTML(item) {
    const snippets = Array.isArray(item.snippets) ? item.snippets : [];
    const candidateSnippets = (item.enrichment_candidates && Array.isArray(item.enrichment_candidates.snippets))
      ? item.enrichment_candidates.snippets : [];
    const takenSet = new Set(snippets.map(s => s.text));
    const addableCandidates = candidateSnippets.filter(s => !takenSet.has(s));

    const selected = snippets.map((s, i) =>
      `<div class="panel-snippet-row" data-index="${i}">
        <blockquote>${escHtml(s.text)}</blockquote>
        <button type="button" class="panel-snippet-remove" aria-label="Remove snippet">&times;</button>
      </div>`
    ).join('');

    const candidateChips = addableCandidates.map(text =>
      `<button type="button" class="panel-snippet-candidate" data-text="${escAttr(text)}"><span class="plus">+</span>${escHtml(text)}</button>`
    ).join('');

    return `<div class="panel-snippets">
      <p class="question-label">Key snippets</p>
      <div class="panel-snippet-list">${selected || '<div class="panel-snippet-empty">No snippets yet.</div>'}</div>
      ${candidateChips ? `<div class="panel-snippet-candidates">${candidateChips}</div>` : ''}
      <div class="panel-snippet-add">
        <textarea placeholder="Paste or type a snippet…"></textarea>
        <button type="button" class="panel-snippet-add-btn">+ Add</button>
      </div>
    </div>`;
  }

  function escAttr(str) {
    return String(str == null ? '' : str).replace(/[&<>"']/g, c =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
    );
  }

  function extractSection(md, heading) {
    if (!md) return '';
    const re = new RegExp(`(^|\\n)##\\s+${heading}\\s*\\n([\\s\\S]*?)(?=\\n##\\s|$)`, 'i');
    const m = md.match(re);
    return m ? m[2].trim() : '';
  }

  // Builds the sticky footer with tags (left) + date/week (right)
  function buildPanelFooterHTML(item, sharedTagSet) {
    const tagPills = item.tags
      .slice()
      .sort((a, b) => b.weight - a.weight)
      .slice(0, 16)
      .map(t => {
        const shared = sharedTagSet && sharedTagSet.has(t.category + ':' + t.tag);
        return renderTagPill(t.tag, t.category, shared);
      }).join('');

    const date = formatHumanDate(item.added_at);
    const week = formatWeekTag(item.added_at);

    return `<div class="panel-footer-tags">${tagPills}</div>
      <div class="panel-footer-date">
        <div class="panel-footer-menu">
          <button type="button" class="panel-footer-menu-trigger" aria-label="Item actions" aria-haspopup="true" aria-expanded="false">${icon('dots-three')}</button>
          <div class="panel-footer-menu-popover" role="menu" hidden>
            <button type="button" class="panel-footer-menu-item js-enrich" role="menuitem">Enrich</button>
            <button type="button" class="panel-footer-menu-item is-danger js-delete" role="menuitem" data-step="0">Delete</button>
          </div>
        </div>
        ${date ? `<div class="panel-footer-date-main">${date}</div>` : ''}
        ${week ? `<div class="panel-footer-date-week">${week}</div>` : ''}
      </div>`;
  }

  // Loads and renders the markdown body into a panel's .card-expanded-md element.
  // Summary / snippets / what-makes-it-work are rendered elsewhere in the panel,
  // so they're stripped from the raw markdown to avoid duplication.
  function loadMarkdownInto(container) {
    if (!container || container.dataset.loaded) return;
    container.dataset.loaded = 'true';
    const slug = container.dataset.slug;
    const item = itemsBySlug[slug];
    if (!item || !item.body_markdown) return;
    const body = stripSections(item.body_markdown, [
      'Summary', 'Key Details', 'Visual Assets', 'Key Snippets', 'What Makes It Work',
    ]);
    if (body) container.innerHTML = renderMarkdown(body);
  }

  // ---- Panel body binding (slider, capture form, snippets) ----
  // Wires up interactions in a freshly-rendered .panel-body. Each mutation
  // posts a delta to /api/item-update, then updates local itemsBySlug and
  // refreshes the grid card. The panel body itself is only re-rendered on
  // explicit refreshItem calls (from enrichment polling) to avoid stomping
  // the user's in-flight form input.
  function bindPanelBody(bodyEl, item) {
    if (!bodyEl || !item) return;
    const slug = item.slug;

    // Compute cover-dot luminance after initial render so the dot sits
    // in either black or white depending on the thumb's brightness.
    updateCoverDotColor(bodyEl.querySelector('.panel-image-slider'));

    // --- Slider: thumb click is always preview-only. Cover is set
    // exclusively by the "Set as cover" pill. Candidate thumbs are
    // silently promoted into images[] on click so they survive refresh. ---
    bodyEl.addEventListener('click', async (e) => {
      const setCoverBtn = e.target.closest('.js-set-cover');
      if (setCoverBtn) {
        e.preventDefault();
        const previewImg = bodyEl.querySelector('.panel-image-main img');
        const path = previewImg?.dataset.previewPath;
        if (path) await setAsCover(bodyEl, slug, path);
        return;
      }

      const removeBtn = e.target.closest('.js-remove-image');
      if (removeBtn) {
        e.preventDefault();
        const previewImg = bodyEl.querySelector('.panel-image-main img');
        const path = previewImg?.dataset.previewPath;
        if (path) await removeImage(bodyEl, slug, path);
        return;
      }

      const thumb = e.target.closest('.panel-image-thumb');
      if (!thumb) return;
      if (thumb.classList.contains('panel-image-upload-tile')) return;
      const path = thumb.dataset.path;
      if (!path) return;
      e.preventDefault();

      // Swap preview only — never touch cover from a thumb click.
      previewThumb(bodyEl, path);

      // Promote candidates to images[] so they stick (without changing cover).
      if (thumb.dataset.source === 'extracted') {
        thumb.classList.remove('is-candidate');
        const addBadge = thumb.querySelector('.panel-image-thumb-add');
        if (addBadge) addBadge.remove();
        postItemUpdate(slug, { add_image_paths: [path] });
      }
    });

    // --- Upload: delegated change handler survives slider refreshes.
    // Previously bound directly to the input, which was lost after
    // refreshSliderFrom() replaced the slider's HTML. ---
    bodyEl.addEventListener('change', async (e) => {
      if (!e.target.matches('.panel-image-upload-tile input[type="file"]')) return;
      const file = e.target.files && e.target.files[0];
      if (!file) return;
      const base64 = await fileToBase64(file);
      if (!base64) return;
      const updated = await postItemUpdate(slug, {
        manual_image_upload: { base64, mime: file.type || 'image/jpeg' },
      });
      if (updated) {
        refreshSliderFrom(bodyEl, updated);
        // Preview the newly uploaded image (not the cover) so the user
        // immediately sees what they just added, without overriding cover.
        const newestManual = [...updated.images].reverse()
          .find(i => i.source === 'manual');
        if (newestManual) previewThumb(bodyEl, newestManual.path);
      }
      e.target.value = '';
    });

    // --- Capture form: chips toggle locally; Save/Skip commit to server. ---
    const form = bodyEl.querySelector('.panel-capture-form');
    if (form) {
      form.addEventListener('click', (e) => {
        const btn = e.target.closest('.q-toggle');
        if (btn) {
          e.preventDefault();
          btn.classList.toggle('active');
          return;
        }
        const save = e.target.closest('.q-save');
        if (save) { e.preventDefault(); commitCaptureForm(slug, form); return; }
        const skip = e.target.closest('.q-skip');
        if (skip) { e.preventDefault(); commitCaptureForm(slug, form, { skip: true }); return; }
      });
    }

    // --- Snippets: candidate chip adds, ✕ removes, "+ Add" appends manual ---
    const snipWrap = bodyEl.querySelector('.panel-snippets');
    if (snipWrap) {
      snipWrap.addEventListener('click', async (e) => {
        const cand = e.target.closest('.panel-snippet-candidate');
        if (cand) {
          e.preventDefault();
          const text = cand.dataset.text;
          cand.remove();
          const updated = await postItemUpdate(slug, { new_snippets: [text] });
          if (updated) refreshSnippetsFrom(bodyEl, updated);
          return;
        }
        const rm = e.target.closest('.panel-snippet-remove');
        if (rm) {
          e.preventDefault();
          const row = rm.closest('.panel-snippet-row');
          const idx = row ? Number(row.dataset.index) : -1;
          if (idx >= 0) {
            row.remove();
            const updated = await postItemUpdate(slug, { removed_snippet_ids: [idx] });
            if (updated) refreshSnippetsFrom(bodyEl, updated);
          }
          return;
        }
        const addBtn = e.target.closest('.panel-snippet-add-btn');
        if (addBtn) {
          e.preventDefault();
          const ta = snipWrap.querySelector('.panel-snippet-add textarea');
          const text = ta?.value.trim();
          if (!text) return;
          ta.value = '';
          const updated = await postItemUpdate(slug, { new_snippets: [text] });
          if (updated) refreshSnippetsFrom(bodyEl, updated);
        }
      });
    }
  }

  // Explicit commit of the capture form (why_saved + what_works). Save
  // persists whatever the user selected; Skip commits an empty intent so
  // the server flips needs_review=false and the form stops appearing.
  async function commitCaptureForm(slug, form, opts) {
    const skip = opts && opts.skip;
    let why_saved = [];
    let what_works = '';
    if (!skip) {
      const activeBtns = form.querySelectorAll('.q-toggle.active');
      why_saved = [...activeBtns].map(b => b.dataset.value);
      const custom = form.querySelector('.q-custom-reason')?.value.trim();
      if (custom) why_saved.push(custom.toLowerCase().replace(/\s+/g, '-'));
      what_works = form.querySelector('.question-text')?.value || '';
    }
    const updated = await postItemUpdate(slug, { why_saved, what_works });
    // After a commit the server will have flipped needs_review=false;
    // refresh the panel so the capture form section disappears cleanly.
    if (updated) PanelManager.refreshItem(slug);
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
      // Merge server truth into local state and update the grid card.
      const prev = itemsBySlug[slug];
      const next = normalizeItem({
        ...(prev || {}),
        ...data,
      });
      itemsBySlug[slug] = next;
      // Update the grid card thumb if primary image changed.
      const card = document.querySelector(`.card[data-slug="${CSS.escape(slug)}"]`);
      if (card) {
        const newThumb = card.querySelector('.card-thumb');
        if (newThumb && next.image_path) {
          newThumb.src = next.image_path;
        }
      }
      return next;
    } catch (err) {
      console.warn('postItemUpdate failed', slug, err.message);
      return null;
    }
  }

  function refreshSliderFrom(bodyEl, item) {
    const slider = bodyEl.querySelector('.panel-image-slider');
    if (!slider) return;
    slider.outerHTML = renderPanelSliderHTML(item);
    updateCoverDotColor(bodyEl.querySelector('.panel-image-slider'));
  }

  // Swap the main preview image locally (no server call). Marks the
  // matching thumb .is-active. The "Set as cover" pill is always visible
  // (even when previewing the current cover) so the action is consistent
  // for every image in the slider.
  function previewThumb(bodyEl, path) {
    const slider = bodyEl.querySelector('.panel-image-slider');
    if (!slider) return;
    const main = slider.querySelector('.panel-image-main');
    if (main) {
      const img = main.querySelector('img');
      if (img) {
        img.src = path;
        img.dataset.previewPath = path;
      } else {
        main.insertAdjacentHTML('afterbegin',
          `<img src="${escAttr(path)}" alt="" data-preview-path="${escAttr(path)}">`);
      }
    }
    slider.querySelectorAll('.panel-image-thumb').forEach(t =>
      t.classList.toggle('is-active', t.dataset.path === path));
  }

  async function setAsCover(bodyEl, slug, path) {
    const updated = await postItemUpdate(slug, { primary_image_path: path });
    if (updated) refreshSliderFrom(bodyEl, updated);
  }

  async function removeImage(bodyEl, slug, path) {
    const updated = await postItemUpdate(slug, { remove_image_paths: [path] });
    if (updated) refreshSliderFrom(bodyEl, updated);
  }

  // ---- Cover-dot color: black on bright images, white on dark ones.
  // Results are cached by image URL since thumbnails never change their
  // pixel data, only their .is-cover membership.
  const _brightnessCache = new Map();

  function updateCoverDotColor(slider) {
    if (!slider) return;
    const coverThumb = slider.querySelector('.panel-image-thumb.is-cover');
    if (!coverThumb) return;
    const src = coverThumb.querySelector('img')?.src;
    if (!src) return;

    const apply = (luminance) => {
      // WCAG says 128 on a 0-255 scale is the naive midpoint; in practice
      // dot visibility flips a bit earlier against busy backgrounds, so
      // err toward white at moderate brightness.
      const color = luminance > 140 ? '#000' : '#fff';
      coverThumb.style.setProperty('--dot-color', color);
    };

    if (_brightnessCache.has(src)) { apply(_brightnessCache.get(src)); return; }

    // Use a fresh crossOrigin image so we can read canvas pixels. If the
    // storage CDN doesn't send CORS headers, the load will fail and we
    // just leave the default color.
    const probe = new Image();
    probe.crossOrigin = 'anonymous';
    probe.onload = () => {
      try {
        const w = 16, h = 16;
        const canvas = document.createElement('canvas');
        canvas.width = w; canvas.height = h;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(probe, 0, 0, w, h);
        const data = ctx.getImageData(0, 0, w, h).data;
        let r = 0, g = 0, b = 0, n = 0;
        for (let i = 0; i < data.length; i += 4) {
          r += data[i]; g += data[i + 1]; b += data[i + 2]; n++;
        }
        // Rec. 601 luma coefficients — matches how the eye weights channels.
        const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / n;
        _brightnessCache.set(src, luminance);
        apply(luminance);
      } catch { /* tainted canvas, leave default */ }
    };
    probe.onerror = () => { /* CORS or 404 — leave default */ };
    probe.src = src;
  }

  // ---- Three-dot footer menu (Enrich + Delete) ----
  function bindPanelFooterMenu(footerEl, item) {
    const trigger = footerEl.querySelector('.panel-footer-menu-trigger');
    const popover = footerEl.querySelector('.panel-footer-menu-popover');
    const deleteBtn = footerEl.querySelector('.js-delete');
    const enrichBtn = footerEl.querySelector('.js-enrich');
    if (!trigger || !popover) return;

    const slug = item.slug;

    const closeMenu = () => {
      popover.hidden = true;
      trigger.setAttribute('aria-expanded', 'false');
      // Reset the delete two-step any time the menu closes.
      if (deleteBtn) {
        deleteBtn.dataset.step = '0';
        deleteBtn.textContent = 'Delete';
      }
    };

    const openMenu = () => {
      popover.hidden = false;
      trigger.setAttribute('aria-expanded', 'true');
    };

    trigger.addEventListener('click', (e) => {
      e.stopPropagation();
      if (popover.hidden) openMenu(); else closeMenu();
    });

    // Outside click / Escape dismiss the menu without firing destructive steps.
    const outsideHandler = (e) => {
      if (popover.hidden) return;
      if (footerEl.contains(e.target)) return;
      closeMenu();
    };
    document.addEventListener('click', outsideHandler);
    document.addEventListener('keydown', (e) => {
      if (!popover.hidden && e.key === 'Escape') closeMenu();
    });

    if (enrichBtn) {
      enrichBtn.addEventListener('click', async (e) => {
        e.stopPropagation();
        closeMenu();
        showToast('Enriching…');
        try {
          const res = await apiFetch('/api/reenrich', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ slug }),
          });
          if (!res.ok) throw new Error('Enrich request failed');
          // Poll for enrichment completion so the panel + grid update live.
          if (typeof pollForEnrichment === 'function') pollForEnrichment(slug);
          showToast('Enriching in background…');
        } catch (err) {
          showToast('Enrich failed: ' + (err.message || 'unknown'));
        }
      });
    }

    if (deleteBtn) {
      deleteBtn.addEventListener('click', async (e) => {
        e.stopPropagation();
        if (deleteBtn.dataset.step !== '1') {
          // First click -> arm for confirmation.
          deleteBtn.dataset.step = '1';
          deleteBtn.textContent = 'Confirm delete';
          return;
        }
        // Second click -> execute.
        try {
          const res = await apiFetch('/api/item-delete', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ slug }),
          });
          if (!res.ok) throw new Error('Delete failed');
          // Locally remove: card, lookups, open panel.
          const card = document.querySelector(`.card[data-slug="${CSS.escape(slug)}"]`);
          if (card) card.remove();
          const idx = allItems.findIndex(i => i.slug === slug);
          if (idx >= 0) allItems.splice(idx, 1);
          delete itemsBySlug[slug];
          renderStats();
          PanelManager.close();
          showToast('Deleted');
        } catch (err) {
          showToast('Delete failed: ' + (err.message || 'unknown'));
          closeMenu();
        }
      });
    }
  }

  function refreshSnippetsFrom(bodyEl, item) {
    const wrap = bodyEl.querySelector('.panel-snippets');
    if (!wrap) return;
    wrap.outerHTML = renderPanelSnippetsHTML(item);
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
    if (!captureFlowSlugs.has(slug)) return;
    captureFlowSlugs.delete(slug);
    if (captureFlowSlugs.size === 0) advanceCaptureQueue();
  }

  // --- Active filter pills ---
  function renderActiveFilters() {
    if (activeTags.length === 0) {
      $activeFilters.innerHTML = '';
      return;
    }
    $activeFilters.innerHTML = activeTags.map((at, i) =>
      `<span class="active-filter-pill" data-idx="${i}">${at.tag} <span class="x">&times;</span></span>`
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
    $search.addEventListener('input', function () {
      searchQuery = this.value.trim();
      renderGrid();
    });

    // Scrollbar auto-hide for the grid column: flash in while actively
    // scrolling, fade out ~700ms after the last scroll event.
    const mainContent = document.querySelector('.main-content');
    if (mainContent) {
      let scrollTimer;
      mainContent.addEventListener('scroll', () => {
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
        renderTagDrawer();
        renderActiveFilters();
        renderGrid();
        return;
      }
      const pill = e.target.closest('.active-filter-pill');
      if (!pill) return;
      const idx = parseInt(pill.dataset.idx, 10);
      activeTags.splice(idx, 1);
      renderTagDrawer();
      renderActiveFilters();
      renderGrid();
    });

    // Week Expand/Collapse toggle — entire bar is clickable (and keyboard-activatable)
    $grid.addEventListener('click', function (e) {
      const bar = e.target.closest('.date-section-header');
      if (!bar) return;
      e.stopPropagation();
      const key = bar.dataset.week;
      if (loadedWeeks.has(key)) collapseWeek(key);
      else renderWeekCards(key);
    });
    $grid.addEventListener('keydown', function (e) {
      if (e.key !== 'Enter' && e.key !== ' ') return;
      const bar = e.target.closest('.date-section-header');
      if (!bar) return;
      e.preventDefault();
      const key = bar.dataset.week;
      if (loadedWeeks.has(key)) collapseWeek(key);
      else renderWeekCards(key);
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

    const stop = () => {
      cancelled = true;
      if (timer) { clearTimeout(timer); timer = null; }
      activePolls.delete(slug);
    };

    const tick = async () => {
      if (cancelled) return;
      attempts++;
      try {
        const client = Stello.getClient();
        const { data } = await client
          .from('items')
          .select('*')
          .eq('slug', slug)
          .eq('user_id', Stello.getUserId())
          .single();
        if (!data) { stop(); return; }

        const item = normalizeItem(data);
        const idx = allItems.findIndex(i => i.slug === slug);
        if (idx >= 0) allItems[idx] = item;
        itemsBySlug[slug] = item;

        // Rebuild the related-items index so tag-based recommendations
        // reflect the new vision tags immediately.
        buildRelatedIndex();

        // Re-render the in-grid card (image + text content may have changed)
        const cardEl = $grid.querySelector(`.card[data-slug="${slug}"]`);
        if (cardEl) cardEl.outerHTML = renderCard(item, 0);

        // Push live updates into any open panel for this slug.
        PanelManager.refreshItem(slug);

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
  function bindFilterPanelBody() {
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
    const prefs = ThemeManager.load();

    // Mode toggle
    const $modeToggle = $panel.querySelector('#theme-mode-toggle');
    if ($modeToggle) {
      $modeToggle.querySelectorAll('.theme-toggle-option').forEach(opt => {
        opt.classList.toggle('active', opt.dataset.mode === prefs.mode);
      });
      $modeToggle.addEventListener('click', (e) => {
        const opt = e.target.closest('[data-mode]');
        if (!opt) return;
        ThemeManager.setMode(opt.dataset.mode);
        $modeToggle.querySelectorAll('.theme-toggle-option').forEach(o =>
          o.classList.toggle('active', o.dataset.mode === opt.dataset.mode)
        );
      });
    }

    // Accent swatches
    $panel.querySelectorAll('.accent-swatch').forEach(swatch => {
      swatch.classList.toggle('active', swatch.dataset.accent === prefs.accent);
      swatch.addEventListener('click', () => {
        ThemeManager.setAccent(swatch.dataset.accent);
        $panel.querySelectorAll('.accent-swatch').forEach(s =>
          s.classList.toggle('active', s.dataset.accent === swatch.dataset.accent)
        );
      });
    });

    // Logout — signs out of Supabase and redirects to the login page
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
    function computePanelWidth() {
      return Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, Math.round(window.innerWidth * 0.25)));
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

      const panel = document.createElement('aside');
      panel.className = 'panel';
      panel.dataset.slug = state.slug;
      panel.setAttribute('role', 'region');
      panel.setAttribute('aria-label', `Item detail: ${item.title || state.slug}`);
      panel.setAttribute('tabindex', '-1');
      panel.style.setProperty('--panel-width', computePanelWidth() + 'px');

      const header = document.createElement('header');
      header.className = 'panel-header';

      const info = document.createElement('div');
      info.className = 'panel-header-info';
      const titleEl = document.createElement('div');
      titleEl.className = 'panel-header-title';
      titleEl.textContent = item.title || '';
      info.appendChild(titleEl);
      if (item.domain) {
        const sourceEl = document.createElement('div');
        sourceEl.className = 'panel-header-source';
        sourceEl.textContent = item.domain;
        info.appendChild(sourceEl);
      }
      header.appendChild(info);

      const actions = document.createElement('div');
      actions.className = 'panel-header-actions';

      const shuffleBtn = document.createElement('button');
      shuffleBtn.className = 'panel-shuffle';
      shuffleBtn.type = 'button';
      shuffleBtn.setAttribute('aria-label', 'Shuffle to related item');
      shuffleBtn.title = 'Shuffle to related item';
      shuffleBtn.innerHTML = icon('shuffle');
      shuffleBtn.addEventListener('click', shuffle);
      actions.appendChild(shuffleBtn);

      if (item.source_url) {
        const openBtn = document.createElement('button');
        openBtn.className = 'panel-open-source';
        openBtn.type = 'button';
        openBtn.setAttribute('aria-label', 'Open source in new tab');
        openBtn.title = 'Open source';
        openBtn.innerHTML = icon('arrow-up-right');
        openBtn.addEventListener('click', () => {
          window.open(item.source_url, '_blank', 'noopener');
        });
        actions.appendChild(openBtn);
      }

      const expandBtn = document.createElement('button');
      expandBtn.className = 'panel-expand';
      expandBtn.type = 'button';
      expandBtn.setAttribute('aria-label', 'Open full page');
      expandBtn.title = 'Full page';
      expandBtn.innerHTML = icon('frame-corners');
      expandBtn.addEventListener('click', () => {
        syncToStorage();
        window.location.href = 'detail.html?slug=' + encodeURIComponent(state.slug);
      });
      actions.appendChild(expandBtn);

      const closeBtn = document.createElement('button');
      closeBtn.className = 'panel-close';
      closeBtn.type = 'button';
      closeBtn.setAttribute('aria-label', 'Close panel');
      closeBtn.title = 'Close';
      closeBtn.innerHTML = icon('x');
      closeBtn.addEventListener('click', close);
      actions.appendChild(closeBtn);

      header.appendChild(actions);
      panel.appendChild(header);

      const body = document.createElement('div');
      body.className = 'panel-body';
      body.innerHTML = buildPanelBodyHTML(item, null);
      panel.appendChild(body);

      const footer = document.createElement('div');
      footer.className = 'panel-footer';
      footer.innerHTML = buildPanelFooterHTML(item, null);
      panel.appendChild(footer);

      $container.appendChild(panel);

      const mdEl = body.querySelector('.card-expanded-md');
      loadMarkdownInto(mdEl);

      bindPanelBody(body, item);
      bindPanelFooterMenu(footer, item);

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

    function replace(newSlug) {
      if (!state.slug || !itemsBySlug[newSlug]) return;
      state.slug = newSlug;
      syncToURL(false);
      syncToStorage();
      render();
      updateActiveCards();
      announce(`Panel shuffled to: ${itemsBySlug[newSlug].title || newSlug}`);
    }

    // Find a random slug that shares ≥1 tag with the open item.
    function randomRelatedSlug(currentSlug) {
      const item = itemsBySlug[currentSlug];
      if (!item) return null;
      const tagKeys = new Set(item.tags.map(t => t.category + ':' + t.tag));
      const candidates = [];
      for (const other of allItems) {
        if (other.slug === currentSlug) continue;
        for (const t of other.tags) {
          if (tagKeys.has(t.category + ':' + t.tag)) { candidates.push(other.slug); break; }
        }
      }
      if (candidates.length === 0) return null;
      return candidates[Math.floor(Math.random() * candidates.length)];
    }

    function shuffle() {
      if (!state.slug) return;
      const next = randomRelatedSlug(state.slug);
      if (!next) { announce('No related items available to shuffle to'); return; }
      replace(next);
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
      if (!item) return;
      const panel = $container.querySelector('.panel');
      if (!panel) return;
      const body = panel.querySelector('.panel-body');
      const footer = panel.querySelector('.panel-footer');

      // Diff-aware refresh: don't stomp sections the user is actively
      // editing. The slider, the candidate chips, and the footer tags are
      // safe to re-render whenever the data changes. The capture form
      // (q-toggle chips, q-custom-reason, question-text) holds in-flight
      // input — only re-render it if it doesn't exist yet.
      if (body) {
        // Slider: rebuild whenever images[] or candidate images change.
        const slider = body.querySelector('.panel-image-slider');
        if (slider) {
          const nextHtml = renderPanelSliderHTML(item);
          if (slider.outerHTML !== nextHtml) slider.outerHTML = nextHtml;
        } else {
          // First render didn't have a slider (no image + no candidates).
          // Prepend one if we now have something to show.
          const nextHtml = renderPanelSliderHTML(item);
          if (nextHtml) body.insertAdjacentHTML('afterbegin', nextHtml);
        }

        // Capture form: only shown while needs_review=true. Remove it
        // when the item no longer needs review; merge suggested chips in
        // when the form is already present and enrichment adds more.
        const form = body.querySelector('.panel-capture-form');
        if (item.needs_review !== true) {
          if (form) form.remove();
        } else if (!form) {
          const snipWrap = body.querySelector('.panel-snippets');
          const html = renderPanelCaptureFormHTML(item);
          if (html) {
            if (snipWrap) snipWrap.insertAdjacentHTML('beforebegin', html);
            else body.insertAdjacentHTML('beforeend', html);
          }
        } else {
          mergeSuggestedReasonChips(form, item);
        }

        // Snippets: re-render list + candidate chips. The "add" textarea
        // gets wiped — capture its value first and restore.
        const snipWrap = body.querySelector('.panel-snippets');
        if (snipWrap) {
          const pendingDraft = snipWrap.querySelector('.panel-snippet-add textarea')?.value || '';
          snipWrap.outerHTML = renderPanelSnippetsHTML(item);
          const restored = body.querySelector('.panel-snippet-add textarea');
          if (restored && pendingDraft) restored.value = pendingDraft;
        } else {
          body.insertAdjacentHTML('beforeend', renderPanelSnippetsHTML(item));
        }

        // Markdown body: re-load if the raw markdown changed.
        const mdEl = body.querySelector('.card-expanded-md');
        if (mdEl && !mdEl.dataset.loaded) loadMarkdownInto(mdEl);

        // Re-bind handlers because we replaced DOM nodes.
        bindPanelBody(body, item);
      }
      if (footer) {
        footer.innerHTML = buildPanelFooterHTML(item, null);
      }
    }

    // Merge any reason chips from enrichment_candidates.reasons that
    // aren't already shown in the form. Preserves the active state of
    // existing chips and any text typed into q-custom-reason / textarea.
    function mergeSuggestedReasonChips(form, item) {
      const reasons = (item.enrichment_candidates && Array.isArray(item.enrichment_candidates.reasons))
        ? item.enrichment_candidates.reasons : [];
      if (!reasons.length) return;
      const options = form.querySelector('.question-options');
      if (!options) return;
      const have = new Set(
        [...options.querySelectorAll('.q-toggle')].map(b => b.dataset.value)
      );
      const customInput = options.querySelector('.q-custom-reason');
      for (const r of reasons) {
        if (have.has(r)) continue;
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'q-toggle q-toggle-suggested';
        btn.dataset.value = r;
        btn.title = 'Suggested';
        btn.textContent = humanizeReason(r);
        if (customInput) options.insertBefore(btn, customInput);
        else options.appendChild(btn);
      }
    }

    return {
      init, open, close, focus, shuffle,
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
