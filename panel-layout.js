/**
 * Stello — item detail panel layout (web port of the Mac app's panel).
 *
 * Mirrors apple/Stello/Stello/Views/CardSubcards.swift (`panelLayout()` +
 * `kindPanelInput()`) and PanelDedupe.swift: the same cards, in the same
 * order, with the same labels and the same "every value shows once" rules.
 * Pure data in, card descriptors out — app.js turns them into HTML. Keep the
 * two in step: when the Mac panel gains a row, add it here too.
 *
 * Browser: `window.StelloPanel`. Node (tests): `require('./panel-layout')`.
 */
(function (root) {
  'use strict';

  // ---------------------------------------------------------------- helpers

  const ENTITIES = [
    ['&nbsp;', ' '], ['&amp;', '&'], ['&lt;', '<'], ['&gt;', '>'],
    ['&quot;', '"'], ['&#39;', "'"], ['&apos;', "'"],
    ['&mdash;', '—'], ['&ndash;', '–'],
    ['&rsquo;', '’'], ['&lsquo;', '‘'], ['&rdquo;', '”'], ['&ldquo;', '“'],
  ];
  function decodeEntities(s) {
    let out = String(s);
    for (const [e, r] of ENTITIES) out = out.split(e).join(r);
    return out;
  }

  /** Trimmed string, or null when blank / not a string-ish value. */
  function nb(v) {
    if (v == null) return null;
    if (typeof v !== 'string') v = String(v);
    const t = v.trim();
    return t ? t : null;
  }
  const arr = (v) => (Array.isArray(v) ? v : []);
  const strs = (v) => arr(v).map(nb).filter(Boolean);
  const refList = (v) => arr(v).filter((r) => r && nb(r.name));
  const refName = (r) => (r && nb(r.name)) || null;
  const capFirst = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);
  const capWords = (s) => (s ? s.replace(/\b\w/g, (c) => c.toUpperCase()) : s);
  const names = (refs) => {
    const n = refList(refs).map((r) => nb(r.name));
    return n.length ? n.join(', ') : null;
  };
  const yesNo = (b, yes = 'Yes', no = 'No') => (b === true ? yes : b === false ? no : null);

  // ---------------------------------------------------------- PanelDedupe

  function normalize(value) {
    let s = decodeEntities(value == null ? '' : value).toLowerCase();
    s = s.replace(/[a-z][a-z0-9+.\-]*:\/\//g, ' ');
    s = s.replace(/(^|[^a-z0-9])www\./g, '$1');
    s = s.trim();
    while (s.endsWith('/')) s = s.slice(0, -1);
    if (s.startsWith('@')) s = s.slice(1);
    s = s.replace(/[^\p{L}\p{N}\p{M}]/gu, ' ');
    return s.split(/\s+/).filter(Boolean).join(' ');
  }

  function isRedundant(value, shown) {
    const needle = normalize(value);
    if (!needle) return false;
    const isText = needle.split(' ').length >= 4;
    for (const raw of shown) {
      const hay = normalize(raw);
      if (!hay) continue;
      if (hay === needle) return true;
      if (needle.length <= 2 || hay.length <= needle.length) continue;
      const padded = ` ${hay} `;
      if (padded.includes(` ${needle} `)) return true;
      if (isText && padded.includes(` ${needle}`)) return true;
    }
    return false;
  }

  function isSameValue(value, shown) {
    const needle = normalize(value);
    if (!needle) return false;
    return shown.some((s) => normalize(s) === needle);
  }

  function factKey(label, value) {
    const v = normalize(value);
    const labelDependent = !v || !/\p{L}/u.test(v) || v === 'yes' || v === 'no';
    if (!labelDependent) return v;
    const raw = v || String(value).trim().toLowerCase();
    return `${normalize(label)}|${raw}`;
  }

  function filterTags(list, shown) {
    const values = new Set();
    const words = new Set();
    for (const raw of shown) {
      const n = normalize(raw);
      if (!n) continue;
      values.add(n);
      const parts = n.split(' ');
      if (parts.length <= 4) for (const w of parts) if (w.length > 2) words.add(w);
    }
    return list.filter((name) => {
      const n = normalize(name);
      if (!n) return false;
      if (values.has(n)) return false;
      if (!n.includes(' ') && words.has(n)) return false;
      return true;
    });
  }

  function primaryAndRest(candidates) {
    const texts = candidates.map(nb).filter(Boolean);
    if (!texts.length) return { primary: null, rest: [] };
    const kept = [texts[0]];
    for (const t of texts.slice(1)) if (!isRedundant(t, kept)) kept.push(t);
    return { primary: texts[0], rest: kept.slice(1) };
  }

  function namesSameSite(value, host) {
    const v = normalize(value);
    const h = normalize(host);
    if (!v || !h) return false;
    if (v === h) return true;
    const hostParts = h.split(' ');
    const bare = hostParts.length > 1 ? hostParts.slice(0, -1).join('') : h;
    const squashed = v.replace(/ /g, '');
    return squashed === bare || squashed === h.replace(/ /g, '');
  }

  function isSameURL(a, b) {
    if (!a || !b) return false;
    const na = normalize(a);
    return !!na && na === normalize(b);
  }

  function webURL(s) {
    const t = nb(s);
    if (!t) return null;
    try {
      const u = new URL(t);
      if ((u.protocol === 'http:' || u.protocol === 'https:') && u.hostname) return u.href;
    } catch { /* not a URL */ }
    return null;
  }

  // ---------------------------------------------------------- formatting

  // Swift's JSONEncoder writes a Date as seconds since 2001-01-01 by default.
  const APPLE_EPOCH = 978307200;
  function toDate(v) {
    if (v == null || v === '') return null;
    if (typeof v === 'number') return new Date((v + APPLE_EPOCH) * 1000);
    const d = new Date(v);
    return isNaN(d) ? null : d;
  }
  function fmtDate(v) {
    const d = toDate(v);
    return d ? d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' }) : null;
  }

  const CURRENCY = {
    INR: '₹', USD: '$', EUR: '€', GBP: '£', JPY: '¥', CNY: '¥',
    KRW: '₩', AUD: 'A$', CAD: 'CA$', SGD: 'S$', NZD: 'NZ$', HKD: 'HK$',
  };
  /** ("2699.00", "INR") → "₹2,699"; ("19.5", "USD") → "$19.50". */
  function formattedPrice(price, currency) {
    const raw = nb(price);
    if (!raw) return null;
    const cleaned = raw.replace(/,/g, '');
    if (!/^-?\d+(\.\d+)?$/.test(cleaned)) return raw;
    const frac = cleaned.split('.')[1] || '';
    const whole = /^0*$/.test(frac);
    const number = Number(cleaned).toLocaleString('en-US', {
      minimumFractionDigits: whole ? 0 : 2, maximumFractionDigits: whole ? 0 : 2,
    });
    const code = nb(currency) && currency.trim().toUpperCase();
    if (!code) return number;
    return CURRENCY[code] ? CURRENCY[code] + number : `${code} ${number}`;
  }

  /** 12_400 → "12.4k", 1_250_000 → "1.3M". */
  function compactCount(v) {
    const t = (x) => { const s = x.toFixed(1); return s.endsWith('.0') ? s.slice(0, -2) : s; };
    if (v >= 1e6) return t(v / 1e6) + 'M';
    if (v >= 1e3) return t(v / 1e3) + 'k';
    return String(v);
  }

  function duration(seconds) {
    if (!(seconds > 0)) return null;
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
  }

  /** ISO week label "W45 2026" (the Mac panel's Added row). */
  function weekLabel(iso) {
    const d0 = iso ? new Date(iso) : null;
    if (!d0 || isNaN(d0)) return 'Undated';
    const d = new Date(Date.UTC(d0.getFullYear(), d0.getMonth(), d0.getDate()));
    const day = d.getUTCDay() || 7;
    d.setUTCDate(d.getUTCDate() + 4 - day);
    const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
    const week = Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
    return `W${String(week).padStart(2, '0')} ${d.getUTCFullYear()}`;
  }

  function hostOf(url) {
    try {
      let h = new URL(url).hostname.toLowerCase();
      if (h.startsWith('www.')) h = h.slice(4);
      return h || null;
    } catch { return null; }
  }

  // ------------------------------------------------------------ kind lines

  function platformsLine(meta, maxShown, short) {
    const n = strs(meta.platforms);
    if (!n.length) return null;
    const shown = maxShown ? n.slice(0, maxShown) : n;
    let line = shown.map((p) => (short && p === 'macOS' ? 'Mac' : p)).join(', ');
    if (n.length > shown.length) line += ` +${n.length - shown.length}`;
    return line;
  }
  function toolPriceLineShort(m) {
    if (m.pricing === 'paid' || (m.pricing == null && m.price != null)) {
      const f = formattedPrice(m.price, m.currency);
      if (f) return f;
    }
    return { free: 'Free', freemium: 'Freemium', paid: 'Paid', 'open source': 'Open source' }[m.pricing] || null;
  }
  function resourceTypeLine(m) {
    const sub = nb(m.subtype);
    if (sub === 'reading list') return 'Reading list';
    const host = nb(strs(m.worksWith)[0]);
    if (host && sub) return `${host} ${sub}`;
    if (host) return host;
    if (sub) return capFirst(sub);
    return null;
  }
  function resourcePriceLine(m) {
    if (m.pricing === 'free') return 'Free';
    const f = formattedPrice(m.price, m.currency);
    if (f) return f;
    return m.pricing === 'paid' ? 'Paid' : null;
  }
  function courseDurationLine(m) {
    const mins = m.durationMinutes;
    if (mins > 0) {
      const h = Math.floor(mins / 60), r = mins % 60;
      if (h === 0) return `${r} min`;
      if (r === 0) return `${h} h`;
      return `${h} h ${r} min`;
    }
    return nb(m.durationText);
  }
  function coursePriceLine(m) {
    if (m.isFree === true) return 'Free';
    const f = formattedPrice(m.price, m.currency);
    if (f) return f;
    return m.isFree === false ? 'Paid' : null;
  }
  function bookAuthorsLine(m) {
    const n = refList(m.authors).map((a) => nb(a.name));
    return n.length ? n.join(', ') : null;
  }
  const join = (parts) => { const p = parts.filter(Boolean); return p.length ? p.join(' · ') : null; };

  function cardKindLine(kind, m) {
    switch (kind) {
      case 'product': {
        const line = join([formattedPrice(m.price, m.currency), refName(m.brand)]);
        if (line) return line;
        return nb(m.creatorHandle) ? `via @${m.creatorHandle.trim()}` : null;
      }
      case 'post': return nb(m.authorHandle) ? `@${m.authorHandle.trim()}` : null;
      case 'tool':
        if (m.repoURL != null) {
          return join([m.pricing === 'open source' ? 'Open source' : null, m.stars > 0 ? `★ ${compactCount(m.stars)}` : null]);
        }
        return join([platformsLine(m, 2, true), toolPriceLineShort(m)]);
      case 'resource': {
        const users = m.users > 0 ? (m.users === 1 ? '1 user' : `${compactCount(m.users)} users`) : null;
        return join([resourceTypeLine(m), resourcePriceLine(m) || users]);
      }
      case 'book': {
        const n = refList(m.authors).map((a) => nb(a.name));
        const first = n.length ? (n.length > 1 ? `${n[0]} +${n.length - 1}` : n[0]) : null;
        return join([first, m.publishedYear != null ? String(m.publishedYear) : null]);
      }
      case 'course': {
        const fmt = nb(m.format) ? capFirst(m.format.trim()) : null;
        return join([refName(m.provider), fmt || courseDurationLine(m) || coursePriceLine(m)]);
      }
      case 'article': return join([nb(m.publication), m.readingMinutes != null ? `${m.readingMinutes} min` : null]);
      default: return null;
    }
  }

  // ------------------------------------------------------------- per kind

  const RICH_KINDS = new Set([
    'typeface', 'website', 'individual', 'studio', 'foundry', 'place', 'music',
    'product', 'post', 'tool', 'resource', 'book', 'course', 'article',
  ]);

  function metaOf(item) {
    let m = item.metadata;
    if (typeof m === 'string') { try { m = JSON.parse(m); } catch { m = null; } }
    return m && typeof m === 'object' && !Array.isArray(m) ? m : null;
  }

  /** The kind whose typed panel shows; 'link' when there's no metadata. */
  function panelKind(item) {
    const k = item.kind;
    return RICH_KINDS.has(k) && metaOf(item) ? k : 'link';
  }

  function typedTopMediaRoles(kind) {
    if (kind === 'typeface') return ['specimen', 'cover'];
    if (kind === 'website' || kind === 'product' || kind === 'post') return ['cover', 'gallery'];
    return ['cover'];
  }

  const MUSIC_PLATFORMS = {
    spotify: 'Spotify', 'apple-music': 'Apple Music', 'youtube-music': 'YouTube Music',
    youtube: 'YouTube', soundcloud: 'SoundCloud', bandcamp: 'Bandcamp', tidal: 'Tidal',
    mixcloud: 'Mixcloud', deezer: 'Deezer',
  };
  function musicPlatformLabel(p) {
    if (!p || p === 'unknown') return null;
    return MUSIC_PLATFORMS[p] || capWords(p.replace(/-/g, ' '));
  }
  /** Album artist, hidden when it equals the track's artist(s) (Arjun's call, 2026-11-07). */
  function musicAlbumArtistRow(m) {
    if (m.subtype === 'album') return null;
    const aa = nb(m.albumArtist);
    if (!aa) return null;
    const artists = refList(m.artists).map((a) => nb(a.name)).join(', ');
    return artists.toLowerCase() === aa.toLowerCase() ? null : aa;
  }

  const POST_PLATFORMS = { x: 'X', instagram: 'Instagram', behance: 'Behance', dribbble: 'Dribbble', pinterest: 'Pinterest' };
  function postAuthorLine(m) {
    const name = refName(m.author);
    const handle = nb(m.authorHandle) ? `@${m.authorHandle.trim()}` : null;
    if (name && handle) return name === handle ? name : `${name} · ${handle}`;
    return name || handle || null;
  }
  function postTitleIsFromText(item, m) {
    if (!nb(m.text)) return false;
    const title = (item.title || '').trim();
    const handle = nb(m.authorHandle);
    const name = refName(m.author);
    if (handle && title.startsWith(`@${handle}:`)) return true;
    if (name && title.startsWith(`${name}:`)) return true;
    const words = m.text.replace(/https?:\/\/\S+/g, ' ').split(/\s+/).filter(Boolean);
    return words.length > 0 && title.startsWith(words.slice(0, Math.min(3, words.length)).join(' '));
  }
  function postMediaLine(m) {
    switch (m.mediaType) {
      case 'carousel': return `${m.mediaCount || 2} items`;
      case 'video': return 'Video';
      case 'gif': return 'GIF';
      case 'image': return 'Image';
      default: return null;
    }
  }

  const TOOL_SUBTYPES = { app: 'App', 'web app': 'Web app', library: 'Library', extension: 'Extension', 'AI model': 'AI model' };
  function toolPriceLine(m) {
    const label = { free: 'Free', paid: 'Paid', freemium: 'Freemium', 'open source': 'Open source' }[m.pricing] || null;
    const price = formattedPrice(m.price, m.currency);
    if (label && price) return m.pricing === 'freemium' ? `${label} · from ${price}` : `${label} · ${price}`;
    return label || price || null;
  }
  function isAppStoreURL(url) {
    try {
      const u = new URL(url);
      if (['macappstore:', 'itms-apps:', 'itms-appss:'].includes(u.protocol)) return true;
      const h = u.hostname.replace(/^www\./, '');
      if (h !== 'apps.apple.com' && h !== 'itunes.apple.com') return false;
      return u.pathname.toLowerCase().split('/').includes('app');
    } catch { return false; }
  }
  function isAmazonURL(url) {
    const h = hostOf(url);
    if (!h) return false;
    const labels = h.split('.');
    return labels.includes('amazon') || labels[0] === 'amzn';
  }
  function languageLabel(lang) {
    const l = nb(lang);
    if (!l) return null;
    const code = l.split('-')[0];
    if (code.length <= 3 && /^[a-z]+$/i.test(code) && typeof Intl !== 'undefined' && Intl.DisplayNames) {
      try {
        const n = new Intl.DisplayNames(['en'], { type: 'language' }).of(code.toLowerCase());
        if (n && n.toLowerCase() !== code.toLowerCase()) return n;
      } catch { /* unknown code */ }
    }
    return l;
  }
  function upcomingStart(v) {
    const d = toDate(v);
    return d && d >= new Date() ? fmtDate(v) : null;
  }

  function typefaceSections(m) {
    const weightCount = nb(m.weightsCount) || (m.weightCount != null ? String(m.weightCount) : null);
    const styleCount = nb(m.stylesCount) || (m.styleCount != null ? String(m.styleCount) : null);
    const langCount = nb(m.languagesCount) || (m.languageSupport != null ? String(m.languageSupport) : null);
    const foundryDesigner = [];
    if (m.typeFoundry) foundryDesigner.push(m.typeFoundry);
    foundryDesigner.push(...arr(m.typeDesigner));
    return [
      { title: 'Classification', type: 'chips', chips: [...strs(m.classification), ...strs(m.personality)] },
      { title: 'Weights', type: 'chips', chips: strs(m.weightTypes), caption: weightCount && `${weightCount} weights` },
      { title: 'Styles', type: 'chips', chips: strs(m.styleTypes), caption: styleCount && `${styleCount} styles` },
      { title: 'Languages', type: 'chips', chips: strs(m.languagesRegion), caption: langCount && `${langCount} languages` },
      { title: 'Formats & tech', type: 'chipsFacts', chips: strs(m.availableFormats), rows: [
        ['Variable font', yesNo(m.variableFontSupport)],
        ['OpenType features', strs(m.openTypeFeatures).join(', ') || null],
      ] },
      { title: 'Licensing & pricing', type: 'facts', rows: [
        ['License', m.license], ['Paid / free', m.paidOrFree], ['Starting price', m.startingPrice],
        ['Trial', yesNo(m.trialAvailability, 'Available', 'No')], ['Student discount', yesNo(m.studentDiscount)],
      ] },
      { title: 'Distributed on', type: 'refs', refs: arr(m.distributedOn) },
      { title: 'Foundry & designer', type: 'refs', refs: foundryDesigner },
      { title: 'Designer', type: 'facts', rows: [['Name', m.typeDesignerFallback]] },
      { title: 'Technical', type: 'facts', rows: [
        ['Release year', m.releaseYear], ['Last update', m.lastUpdate], ['Version', m.version],
        ['Family count', m.familyCount], ['Family fonts', names(m.familyFontNames)],
      ] },
      { title: 'Letterform graphics', type: 'gallery', roles: ['graphic'] },
      { title: 'Insights', type: 'facts', rows: [
        ['Highlights', m.highlights], ['Use case', m.useCase], ['Design features', m.designFeatures],
      ] },
      { title: 'Related fonts', type: 'facts', rows: [
        ['Pairing', m.pairingFonts], ['Similar', m.similarFonts], ['Fork', m.forkFonts],
      ] },
      { title: 'Previews', type: 'gallery', roles: ['preview'] },
      { title: 'FAQs', type: 'faqs', items: arr(m.faqs) },
      { title: 'Appears in', type: 'refs', refs: [...arr(m.creatives), ...arr(m.websites)] },
    ];
  }

  function typefacePrice(m) {
    const p = (m.paidOrFree || '').toLowerCase();
    if (p.includes('free') && !p.includes('paid')) return 'Free';
    return nb(m.startingPrice) || m.paidOrFree;
  }

  function websiteSections(m) {
    const s = [
      { title: 'Category', type: 'chips', chips: strs(m.categories) },
      { title: 'Traits', type: 'chips', chips: strs(m.traits) },
      { title: 'Focus areas', type: 'chips', chips: strs(m.focusAreas) },
      { title: 'Review', type: 'text', text: m.review || '' },
      { title: 'Platform', type: 'chips', chips: strs(m.platform) },
      { title: 'Tech stack', type: 'dedupedChips', chips: strs(m.techStack) },
      { title: 'Founders', type: 'refs', refs: arr(m.founders) },
      { title: 'Founder', type: 'facts', rows: [['Name', m.founderName]] },
      { title: 'Branding by', type: 'refs', refs: arr(m.brandingMadeBy) },
      { title: 'Site designer', type: 'refs', refs: arr(m.siteDesignerAgency) },
    ];
    if (nb(m.agencyName)) s.push({ title: 'Agency', type: 'facts', rows: [['Name', m.agencyName], ['URL', m.agencyURL]] });
    s.push(
      { title: 'Creatives', type: 'refs', refs: arr(m.creatives) },
      { title: 'Typography', type: 'refs', refs: arr(m.typography) },
      { title: 'Typeface count', type: 'facts', rows: [['Count', m.typefaceCount]] },
      { title: 'Foundries', type: 'refs', refs: arr(m.typeFoundries) },
      { title: 'Web pages', type: 'chips', chips: strs(m.webPages), caption: m.webPagesCount },
      { title: 'Key components', type: 'chips', chips: strs(m.keyComponents), caption: m.keyComponentsCount },
      { title: 'Timeline', type: 'facts', rows: [
        ['First published', m.firstPublished], ['Date added', m.dateAdded], ['Date updated', m.dateUpdated],
      ] },
    );
    return s;
  }

  function individualSections(m) {
    return [
      { title: 'Identity', type: 'facts', rows: [['Pronouns', m.pronouns], ['Bio', m.bio], ['Location', refName(m.location)]] },
      { title: 'Professions', type: 'chips', chips: strs(m.professions) },
      { title: 'Traits', type: 'chips', chips: strs(m.traits) },
      { title: 'Professional', type: 'facts', rows: [
        ['Experience', m.professionalExperience != null ? `${m.professionalExperience} years` : null],
        ['Current role', m.currentRole], ['Employer', m.currentEmployer],
        ['Notable works', m.notableWorks], ['Signature style', m.signatureStyle],
      ] },
      { title: 'Work & community', type: 'facts', rows: [
        ['Own products', m.ownProductsList], ['Speaking', m.speaking], ['Workshops', m.workshops],
        ['Community', m.communityWork], ['Tools & stack', m.toolsAndTechStack],
      ] },
      { title: 'Contact & social', type: 'facts', rows: [
        ['Email', m.email], ['X', m.xURL], ['Instagram', m.instagramURL], ['LinkedIn', m.linkedInURL],
        ['Behance', m.behanceURL], ['Bluesky', m.bluesky], ['Mastodon', m.mastodon], ['Threads', m.threads],
        ['Blog', m.blogLink], ['Shop', m.shopLink],
      ] },
      { title: 'Personals', type: 'facts', rows: [
        ['Favourite book', m.favouriteBook], ['Fun fact', m.funFact], ['Hobbies', m.hobbies],
      ] },
      { title: 'Typefaces', type: 'refs', refs: arr(m.typefaces) },
      { title: 'Foundries', type: 'refs', refs: arr(m.typeFoundries) },
    ];
  }

  function foundrySections(m) {
    return [
      { title: 'About', type: 'facts', rows: [['Description', m.description], ['Category', m.category]] },
      { title: 'Origin & team', type: 'facts', rows: [['Geography', refName(m.geography)], ['Founded', m.foundedYear]] },
      { title: 'Founders & designers', type: 'refs', refs: arr(m.foundersDesigners) },
      { title: 'Pricing & licensing', type: 'facts', rows: [
        ['Price range', m.priceRange], ['Trial fonts', yesNo(m.trialFonts)], ['Student discount', yesNo(m.studentDiscount)],
      ] },
      { title: 'Licensing types', type: 'chips', chips: strs(m.licensingTypes) },
      { title: 'Design approach', type: 'facts', rows: [['Philosophy', m.designPhilosophy]] },
      { title: 'Popular fonts', type: 'chips', chips: strs(m.popularFonts) },
      { title: 'Specialisation', type: 'chips', chips: strs(m.specialisation) },
      { title: 'Custom services', type: 'chips', chips: strs(m.customServices) },
      { title: 'Presence', type: 'facts', rows: [['Social', m.social], ['Email', m.email], ['Thoughts', m.thoughts]] },
      { title: 'Distribution', type: 'chips', chips: strs(m.distribution) },
      { title: 'Typefaces', type: 'refs', refs: arr(m.typefaces) },
      { title: 'Websites', type: 'refs', refs: arr(m.websites) },
      { title: 'Creatives', type: 'refs', refs: arr(m.creatives) },
    ];
  }

  /** What one kind contributes before de-duplication (Mac `kindPanelInput`). */
  function kindInput(item, kind, m, refsResolve) {
    const input = {
      titleOverride: null, mainCandidates: [item.summary], showsExtraTexts: false,
      mainIsAISummary: false, showsAIArtBadge: false, identityRow: null, facts: [],
      keepsSiteRows: false, factAliases: [], links: [], sections: [],
      dedupedChips: {}, plainChips: {}, extraShown: [], canonicalURL: null,
    };
    if (!m) return input;
    switch (kind) {
      case 'typeface':
        input.mainCandidates = [item.summary, m.overview, m.description];
        input.showsExtraTexts = true;
        input.facts = [
          ['Release year', m.releaseYear], ['License', m.license],
          ['Price', typefacePrice(m)], ['Specimen link', m.specimenLink || m.specimenURL],
        ];
        input.factAliases = [['Price', 'Starting price'], ['Price', 'Paid / free']];
        input.sections = typefaceSections(m);
        break;
      case 'website':
        input.mainCandidates = [m.tagline, item.summary, m.description];
        input.showsExtraTexts = true;
        input.sections = websiteSections(m);
        break;
      case 'individual':
        input.mainCandidates = [m.bio, item.summary];
        input.facts = [
          ['Current role', m.currentRole], ['Employer', m.currentEmployer], ['Location', refName(m.location)],
          ['Pronouns', m.pronouns],
          ['Experience', m.professionalExperience != null ? `${m.professionalExperience} years` : null],
        ];
        input.sections = individualSections(m);
        break;
      case 'studio':
        input.sections = [
          { title: 'Work', type: 'refs', refs: arr(m.work) },
          { title: 'Team', type: 'refs', refs: arr(m.team) },
        ];
        break;
      case 'foundry':
        input.mainCandidates = [m.description, item.summary];
        input.facts = [
          ['Category', m.category], ['Location', refName(m.geography)],
          ['Founded', m.foundedYear], ['Price range', m.priceRange],
        ];
        input.factAliases = [['Location', 'Geography']];
        input.sections = foundrySections(m);
        break;
      case 'place':
        input.facts = [['City', m.city], ['Country', m.country]];
        break;
      case 'music': {
        const artists = refList(m.artists);
        const artistNames = artists.map((a) => nb(a.name));
        const artistsRow = refsResolve(artists) ? null : names(artists);
        const curatorRow = m.curator ? (refsResolve([m.curator]) ? null : refName(m.curator)) : null;
        input.identityRow = [nb(m.subtype) ? capFirst(m.subtype.trim()) : 'Title', nb(m.cleanTitle) || item.title];
        const tracks = arr(m.trackList);
        input.facts = [
          [artistNames.length > 1 ? 'Artists' : 'Artist', artistsRow],
          ['Album', m.subtype === 'album' ? null : nb(m.album)],
          ['Album artist', musicAlbumArtistRow(m)],
          ['Type', nb(m.subtype) ? capWords(m.subtype) : null],
          ['Edition', m.edition], ['Year', m.releaseYear], ['Label', m.label], ['Film', m.film],
          ['Duration', duration(m.totalDurationSeconds)],
          ['Tracks', tracks.length ? String(tracks.length) : null],
          [m.isOwnPlaylist === true ? 'Curator (you)' : 'Curator', curatorRow],
          ['Platform', musicPlatformLabel(m.platform)],
          ['UPC', m.upc],
        ];
        input.keepsSiteRows = true;
        input.plainChips.genres = strs(m.genres);
        input.extraShown = [refName(m.curator), m.platform, ...artistNames, names(artists)].filter(Boolean);
        input.links = [['Canonical', m.canonicalURL]];
        break;
      }
      case 'product': {
        input.identityRow = [m.productNameIsGuess === true ? 'Name (guess)' : 'Name', m.productName];
        let range = null;
        const lo = formattedPrice(m.priceMin, m.currency), hi = formattedPrice(m.priceMax, m.currency);
        if (lo && hi) range = `${lo} – ${hi}`;
        let when = formattedPrice(m.price, m.currency);
        if (when && m.pricedAt != null) when = `${when} · ${fmtDate(m.pricedAt)}`;
        input.facts = [
          [m.brandIsGuess === true ? 'Brand (guess)' : 'Brand', refName(m.brand)],
          ['Price range', range], ['Price when saved', when],
          ['Availability', nb(m.availability) ? capWords(m.availability.toLowerCase()) : null],
          ['Shop', m.shop], ['Category', m.category],
        ];
        input.links = [['Buy', m.buyURL], ['Original post', m.originalPostURL]];
        input.extraShown = [refName(m.creator), m.creatorHandle].filter(Boolean);
        input.canonicalURL = m.canonicalURL;
        break;
      }
      case 'post': {
        const authorLine = postAuthorLine(m);
        if (authorLine && postTitleIsFromText(item, m)) input.titleOverride = authorLine;
        input.mainCandidates = [m.text, item.summary];
        input.showsAIArtBadge = m.isAIArt === true && !nb(m.aiModel) && !nb(m.prompt);
        input.facts = [
          ['Platform', POST_PLATFORMS[m.platform] || (m.platform ? capWords(m.platform) : null)],
          ['Author', authorLine], ['Posted', fmtDate(m.postedAt)], ['Media', postMediaLine(m)],
        ];
        input.extraShown = [m.aiModel, m.authorHandle, refName(m.author)].filter(Boolean);
        input.canonicalURL = m.canonicalURL;
        break;
      }
      case 'tool': {
        input.mainCandidates = [m.tagline, item.summary];
        input.identityRow = ['Name', m.name];
        input.facts = [
          ['Type', TOOL_SUBTYPES[m.subtype] || m.subtype],
          [m.platformsAreGuess ? 'Platforms (guess)' : 'Platforms', platformsLine(m)],
          ['Category', m.category],
          [m.pricingIsGuess ? 'Price (guess)' : 'Price', toolPriceLine(m)],
          ['Maker', refName(m.maker)],
        ];
        const fromAppStore = item.source_url ? isAppStoreURL(item.source_url) : false;
        const website = (m.repoURL != null || fromAppStore)
          ? m.homepageURL
          : (nb(m.canonicalURL) ? null : m.homepageURL);
        input.links = [['Website', website], ['App Store', m.appStoreURL], ['Repository', m.repoURL]];
        input.dedupedChips.topics = strs(m.topics);
        input.extraShown = [m.language, m.name, ...strs(m.platforms)].filter(Boolean);
        input.canonicalURL = m.canonicalURL;
        break;
      }
      case 'resource':
        input.facts = [
          ['Type', nb(m.subtype) ? capFirst(m.subtype.trim()) : null],
          ['Works with', strs(m.worksWith).join(', ') || null],
          ['Maker', refName(m.maker)], ['Price', resourcePriceLine(m)],
          ['Users', m.users != null ? compactCount(m.users) : null],
          ['Likes', m.likes != null ? compactCount(m.likes) : null],
        ];
        input.links = [["Maker's page", m.maker && m.maker.url]];
        input.extraShown = [m.name, ...strs(m.worksWith)].filter(Boolean);
        input.canonicalURL = m.canonicalURL;
        break;
      case 'book': {
        const bt = nb(m.title);
        if (bt && !isSameValue(bt, [item.title || ''])) input.identityRow = ['Title', bt];
        const authorLabel = refList(m.authors).length > 1 ? 'Authors' : 'Author';
        input.facts = [
          [m.authorsAreGuess ? `${authorLabel} (guess)` : authorLabel, bookAuthorsLine(m)],
          ['Published', m.publishedYear != null ? String(m.publishedYear) : null],
          ['Publisher', m.publisher],
          ['Pages', m.pages > 0 ? String(m.pages) : null],
          ['Format', nb(m.format) ? capFirst(m.format.trim()) : null],
          ['ISBN', nb(m.isbn13) || nb(m.isbn10)],
          ['Language', languageLabel(m.language)],
        ];
        const amazon = m.amazonURL && !(item.source_url && isAmazonURL(item.source_url)) ? m.amazonURL : null;
        input.links = [['Open Library', m.openLibraryURL], ['Goodreads', m.goodreadsURL], ['Amazon', amazon]];
        input.dedupedChips.subjects = strs(m.subjects);
        input.extraShown = [m.title, ...refList(m.authors).map((a) => a.name)].filter(Boolean);
        input.canonicalURL = m.canonicalURL;
        break;
      }
      case 'course': {
        input.identityRow = ['Course', m.name];
        let lessons = m.lessons > 0 ? (m.lessons === 1 ? '1 lesson' : `${m.lessons} lessons`) : null;
        input.facts = [
          ['Provider', refName(m.provider)], ['Instructor', refName(m.instructor)],
          [m.formatIsGuess ? 'Format (guess)' : 'Format', nb(m.format) ? capFirst(m.format.trim()) : null],
          [m.durationIsGuess || m.lessonsIsGuess ? 'Length (guess)' : 'Length', join([lessons, courseDurationLine(m)])],
          ['Level', m.level], ['Price', coursePriceLine(m)], ['Starts', upcomingStart(m.startsAt)],
        ];
        input.links = [['Instructor page', m.instructor && m.instructor.url]];
        input.dedupedChips.teaches = strs(m.topics);
        input.extraShown = [m.name].filter(Boolean);
        input.canonicalURL = m.canonicalURL;
        break;
      }
      case 'article':
        input.mainCandidates = [m.summary, item.summary];
        input.mainIsAISummary = m.summaryIsGuess === true && !!nb(m.summary);
        input.facts = [
          ['Publication', m.publication], ['Author', refName(m.author)],
          ['Published', fmtDate(m.publishedAt)],
          ['Reading time', m.readingMinutes != null ? `${m.readingMinutes} min read` : null],
        ];
        input.links = [["Author's page", m.author && m.author.url]];
        if (m.isTutorial) input.dedupedChips.techStack = strs(m.techStack);
        input.canonicalURL = m.canonicalURL;
        break;
      default: break;
    }
    return input;
  }

  function sectionValues(sections) {
    const out = [];
    for (const s of sections) {
      if (s.type === 'facts') out.push(...s.rows.map((r) => nb(r[1])).filter(Boolean));
      else if (s.type === 'chips' || s.type === 'dedupedChips') out.push(...s.chips);
      else if (s.type === 'refs') { out.push(...refList(s.refs).map((r) => r.name)); const n = names(s.refs); if (n) out.push(n); }
      else if (s.type === 'text') out.push(s.text);
      else if (s.type === 'chipsFacts') out.push(...s.chips, ...s.rows.map((r) => nb(r[1])).filter(Boolean));
    }
    return out;
  }

  /** Rows → [{label, value, url}], empty values dropped; `links[label]` or an http(s) value opens. */
  function factRows(rows, links) {
    return rows
      .map(([label, value]) => {
        const v = nb(value);
        if (!v) return null;
        return { label, value: v, url: webURL((links && links[label]) || v) };
      })
      .filter(Boolean);
  }

  // ------------------------------------------------------------- layout

  /**
   * The de-duplicated panel for `item`.
   * `opts.resolveSlug(slug)` → true when a ref's slug opens an item in the library.
   * Returns { kind, header, cards: [...], tagShown, snippetTexts, topRoles, isTyped }.
   * Card shapes: facts {rows}, chips {chips, caption}, refs {refs}, text {text},
   * gallery {roles}, faqs {items}, chipsFacts {chips, rows}, tracklist {tracks},
   * aiArt {model, prompt, promptLabel}, github {rows, chips}, notes {}.
   */
  function layout(item, opts) {
    const resolveSlug = (opts && opts.resolveSlug) || (() => false);
    const refsResolve = (refs) => refList(refs).some((r) => r.slug && resolveSlug(r.slug));
    const kind = panelKind(item);
    const m = kind === 'link' ? null : metaOf(item);
    const input = kindInput(item, kind, m, refsResolve);
    const dec = (s) => decodeEntities(s);

    // Header
    const title = dec(nb(input.titleOverride) || nb(item.title) || 'Untitled');
    let kindLine = m ? cardKindLine(kind, m) : null;
    if (kindLine) kindLine = dec(kindLine);
    if (kindLine && isSameValue(kindLine, [title])) kindLine = null;
    const texts = primaryAndRest(input.mainCandidates.map((c) => (nb(c) ? dec(c) : null)));
    let main = texts.primary;
    if (main && isSameValue(main, [title])) main = null;
    const extras = input.showsExtraTexts ? texts.rest.filter((t) => !isSameValue(t, [title])) : [];
    const first = nb(input.mainCandidates[0]) ? dec(nb(input.mainCandidates[0])) : null;
    const header = {
      title, kindLine, mainText: main,
      mainIsAISummary: input.mainIsAISummary && !!main && main === first,
      extraTexts: extras, showsAIArtBadge: input.showsAIArtBadge,
    };
    const headerShown = [title, kindLine, main, ...extras].filter(Boolean);
    const headerTexts = [main, ...extras].filter(Boolean);

    // Source host: the canonical page's host for tool/resource/article/course/book.
    const canonicalHostKinds = new Set(['tool', 'resource', 'article', 'course', 'book']);
    let host = '';
    if (item.source_url) {
      host = (canonicalHostKinds.has(kind) && m && nb(m.canonicalURL) && hostOf(m.canonicalURL)) || item.domain || hostOf(item.source_url) || '';
    }
    const hasSource = !!host && host !== 'local';
    const sourcePage = nb(input.canonicalURL) || nb(item.source_url);
    const sourceURLs = [item.source_url, sourcePage].filter(Boolean);
    const siteLabels = new Set(['Platform', 'Shop', 'Publication', 'Provider']);

    // Summary
    const shownKeys = new Set();
    const facts = [];
    const factValues = [];
    const summaryRows = input.facts.slice();
    if (input.identityRow) summaryRows.unshift(input.identityRow);
    summaryRows.forEach(([label, value], index) => {
      const v0 = nb(value);
      if (!v0) return;
      const v = dec(v0);
      const isIdentity = !!input.identityRow && index === 0;
      if (!isIdentity && isSameValue(v, [title])) return;
      if (kindLine && isSameValue(v, [kindLine])) return;
      if (sourceURLs.some((u) => isSameURL(u, v))) return;
      if (hasSource && !input.keepsSiteRows && siteLabels.has(label) && namesSameSite(v, host)) return;
      const key = factKey(label, v);
      if (shownKeys.has(key)) return;
      shownKeys.add(key);
      facts.push([label, v]);
      factValues.push(v);
    });
    for (const [summaryLabel, otherLabel] of input.factAliases) {
      for (const [label, value] of facts) if (label === summaryLabel && value) shownKeys.add(factKey(otherLabel, value));
    }

    const author = nb(item.author) ? dec(item.author.trim()) : null;
    if (author) {
      const elsewhere = [title, kindLine, ...factValues, ...input.extraShown, ...sectionValues(input.sections)].filter(Boolean);
      const key = factKey('Author', author);
      if (!isSameValue(author, elsewhere) && !shownKeys.has(key)) {
        shownKeys.add(key);
        facts.push(['Author', author]);
        factValues.push(author);
      }
    }

    const factLinks = {};
    if (hasSource) {
      facts.push(['Source', host]);
      shownKeys.add(factKey('Source', host));
      if (sourcePage) factLinks.Source = sourcePage;
    }
    const added = weekLabel(item.added_at);
    facts.push(['Added', added]);
    shownKeys.add(factKey('Added', added));

    const chipShown = [title, kindLine, ...extras, ...factValues].filter(Boolean);

    // Sections
    const sections = [];
    const sectionShown = [];
    const keptRows = (rows) => {
      const kept = [];
      for (const [label, value] of rows) {
        const v0 = nb(value);
        if (!v0) continue;
        const v = dec(v0);
        if (isSameValue(v, headerShown)) continue;
        if (sourceURLs.some((u) => isSameURL(u, v))) continue;
        const key = factKey(label, v);
        if (shownKeys.has(key)) continue;
        shownKeys.add(key);
        kept.push([label, v]);
        sectionShown.push(v);
      }
      return kept;
    };
    for (const s of input.sections) {
      switch (s.type) {
        case 'facts': {
          const kept = keptRows(s.rows);
          if (kept.length) sections.push({ type: 'facts', title: s.title, rows: factRows(kept) });
          break;
        }
        case 'chips': {
          const values = strs(s.chips);
          const caption = nb(s.caption);
          if (values.length || caption) { sections.push({ type: 'chips', title: s.title, chips: values, caption }); sectionShown.push(...values); }
          break;
        }
        case 'dedupedChips': {
          const values = filterTags(strs(s.chips), chipShown);
          if (values.length) { sections.push({ type: 'chips', title: s.title, chips: values, caption: null }); sectionShown.push(...values); }
          break;
        }
        case 'refs': {
          const values = refList(s.refs);
          if (values.length) { sections.push({ type: 'refs', title: s.title, refs: values }); sectionShown.push(...values.map((r) => r.name)); }
          break;
        }
        case 'text': {
          const t = nb(s.text) ? dec(s.text.trim()) : null;
          if (!t || isRedundant(t, headerTexts)) break;
          sections.push({ type: 'text', title: s.title, text: t });
          sectionShown.push(t);
          break;
        }
        case 'gallery':
          sections.push({ type: 'gallery', title: s.title, roles: s.roles });
          break;
        case 'faqs': {
          const items = arr(s.items).filter((f) => f && nb(f.question) && nb(f.answer));
          if (items.length) sections.push({ type: 'faqs', title: s.title, items });
          break;
        }
        case 'chipsFacts': {
          const values = strs(s.chips);
          const kept = keptRows(s.rows);
          if (values.length || kept.length) { sections.push({ type: 'chipsFacts', title: s.title, chips: values, rows: factRows(kept) }); sectionShown.push(...values); }
          break;
        }
        default: break;
      }
    }

    const links = input.links.filter(([, v]) => {
      const u = nb(v);
      return u && !isSameURL(u, item.source_url) && !isSameURL(u, input.canonicalURL);
    });

    const chips = Object.assign({}, input.plainChips);
    for (const [key, values] of Object.entries(input.dedupedChips)) chips[key] = filterTags(values, chipShown);

    const tagShown = [...headerShown, ...factValues, ...input.facts.map((r) => nb(r[1])).filter(Boolean),
      ...input.extraShown, ...sectionShown, ...Object.values(chips).flat()];
    if (hasSource) tagShown.push(host);

    // Cards after the header, in the Mac panel's order.
    const cards = [];
    const linksCard = () => { const rows = factRows(links); if (rows.length) cards.push({ type: 'facts', title: 'Links', rows }); };
    const chipsCard = (title, list) => { if (list && list.length) cards.push({ type: 'chips', title, chips: list, caption: null }); };

    cards.push({ type: 'facts', title: 'Summary', rows: factRows(facts, factLinks) });

    switch (kind) {
      case 'typeface': case 'website': case 'individual': case 'studio': case 'foundry': case 'place':
        cards.push(...sections);
        break;
      case 'music': {
        if (refsResolve(m.artists)) cards.push({ type: 'refs', title: 'Artists', refs: refList(m.artists) });
        if (m.curator && refsResolve([m.curator])) {
          cards.push({ type: 'refs', title: m.isOwnPlaylist === true ? 'Curated by (you)' : 'Curated by', refs: [m.curator] });
        }
        chipsCard('Genres', chips.genres);
        const tracks = arr(m.trackList).filter((t) => t && nb(t.name));
        if (tracks.length) cards.push({ type: 'tracklist', title: 'Tracklist', tracks: tracks.map((t) => ({ name: t.name, duration: duration(t.durationSeconds) })) });
        linksCard();
        break;
      }
      case 'product':
        if (m.creator && nb(m.creator.name)) cards.push({ type: 'refs', title: 'Posted by', refs: [m.creator] });
        linksCard();
        break;
      case 'post': {
        const model = nb(m.aiModel), prompt = nb(m.prompt);
        if (m.isAIArt === true && (model || prompt)) {
          cards.push({ type: 'aiArt', title: 'AI art', model, prompt, promptLabel: m.promptIsGuess ? 'Prompt (guess)' : 'Prompt' });
        }
        break;
      }
      case 'tool': {
        const topics = chips.topics || [];
        const hasRepoData = m.stars != null || m.language != null || m.license != null || m.lastPushedAt != null || topics.length;
        if (m.repoURL != null && hasRepoData) {
          cards.push({ type: 'github', title: 'GitHub', chips: topics, rows: factRows([
            ['Stars', m.stars != null ? `★ ${compactCount(m.stars)}` : null],
            ['Language', m.language], ['Licence', m.license], ['Last update', fmtDate(m.lastPushedAt)],
          ]) });
        }
        linksCard();
        break;
      }
      case 'resource': case 'book': case 'course': case 'article':
        if (kind === 'book') chipsCard('Subjects', chips.subjects);
        if (kind === 'course') chipsCard(m.topicsAreGuess ? 'Teaches (guess)' : 'Teaches', chips.teaches);
        if (kind === 'article') chipsCard('Tech stack', chips.techStack);
        linksCard();
        break;
      default:
        cards.push({ type: 'notes', title: 'Notes' });
        break;
    }

    return {
      kind, header, cards, tagShown, snippetTexts: headerTexts,
      isTyped: kind !== 'link', topRoles: typedTopMediaRoles(kind),
    };
  }

  /** Tags minus those naming a value the panel already shows (never deleted). */
  function visibleTags(tags, panel) {
    const sorted = arr(tags).slice().sort((a, b) => (b.weight || 0) - (a.weight || 0));
    const kept = new Set(filterTags(sorted.map((t) => t.tag), panel.tagShown));
    return sorted.filter((t) => kept.has(t.tag));
  }

  /** Snippets the main text doesn't already hold, with no repeats (keeps original index). */
  function visibleSnippets(snippets, panel) {
    const keptTexts = [];
    const out = [];
    arr(snippets).forEach((s, index) => {
      const text = s && nb(s.text);
      if (!text || isRedundant(text, panel.snippetTexts) || isRedundant(text, keptTexts)) return;
      keptTexts.push(text);
      out.push({ text: s.text, index });
    });
    return out;
  }

  // Grid card helpers: the Mac card's kind line and URL pill host.
  const CANONICAL_HOST_KINDS = new Set(['tool', 'resource', 'article', 'course', 'book']);
  function kindLineFor(item) {
    const kind = panelKind(item);
    if (kind === 'link') return null;
    const m = metaOf(item);
    const line = m ? cardKindLine(kind, m) : null;
    return line ? decodeEntities(line) : null;
  }
  function displayLink(item) {
    const kind = panelKind(item);
    const m = kind === 'link' ? null : metaOf(item);
    const h = CANONICAL_HOST_KINDS.has(kind) && m && nb(m.canonicalURL) ? hostOf(m.canonicalURL) : '';
    return (h || item.domain || '').replace(/^www\./, '');
  }

  const api = {
    layout, visibleTags, kindLineFor, displayLink, visibleSnippets, panelKind, metaOf,
    // exposed for tests
    normalize, isRedundant, isSameValue, factKey, filterTags, namesSameSite,
    formattedPrice, compactCount, weekLabel, toDate, cardKindLine,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.StelloPanel = api;
})(typeof window !== 'undefined' ? window : globalThis);
