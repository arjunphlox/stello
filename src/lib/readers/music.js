/**
 * Music: classification (host / og:type, or a confirmed YouTube oEmbed signal) and
 * best-effort extraction. Port of the music half of CaptureService.swift.
 *
 * Network goes through the injected `net` (see pipeline.js), so the parsing stays pure
 * and testable.
 */
import { jsonLDTypedNodes, nodeTypes, typeIs, isDict, toURL } from './html.js';
import { musicPlatform, isPlainYouTubeHost, isMusicYouTubeSignal, isMusicOGType, musicSubtype } from './classifier.js';

const individual = (name) => ({ name, kind: 'individual' });
const nilIfEmpty = (s) => {
  if (typeof s !== 'string') return null;
  const t = s.trim();
  return t || null;
};

/** Swift's MusicMeta always encodes these. */
export function emptyMusicMeta() {
  return { artists: [], genres: [], trackList: [] };
}

const DESCRIPTOR_WORDS = new Set([
  'video', 'audio', 'song', 'official', 'video song', 'full video', 'full song',
  'lyrical', 'lyrical video', 'music video', 'official video', 'official audio',
]);
const EDITION_KEYWORDS = ['remaster', 'edition', 'version', 'deluxe', 'anniversary', 'live', 'mono', 'stereo', 'reissue', 'expanded'];

// ─── Pure helpers ───────────────────────────────────────────────────────

export function embedURL(oembed) {
  if (oembed?.iframe_url) return oembed.iframe_url;
  const m = typeof oembed?.html === 'string' ? /src=["']([^"']+)["']/i.exec(oembed.html) : null;
  return m ? m[1] : null;
}

export function youtubeVideoID(url) {
  const u = toURL(url);
  if (!u) return null;
  if ((u.hostname || '').toLowerCase().includes('youtu.be')) return u.pathname.split('/').filter(Boolean)[0] ?? null;
  return u.searchParams.get('v');
}

export function parseISO8601MusicDuration(s) {
  if (typeof s !== 'string' || !s.startsWith('PT')) return null;
  let seconds = 0;
  let buf = '';
  for (const ch of s.slice(2)) {
    if (/[0-9]/.test(ch)) { buf += ch; continue; }
    if (buf) {
      const v = parseInt(buf, 10);
      if (ch === 'H') seconds += v * 3600;
      else if (ch === 'M') seconds += v * 60;
      else if (ch === 'S') seconds += v;
    }
    buf = '';
  }
  return seconds > 0 ? seconds : null;
}

function stringArray(v) {
  if (typeof v === 'string') return [v];
  if (Array.isArray(v)) return v.filter((x) => typeof x === 'string');
  return [];
}

function entityRefs(v) {
  const ref = (d) => (typeof d.name === 'string' ? individual(d.name) : null);
  if (isDict(v)) { const r = ref(v); return r ? [r] : []; }
  if (Array.isArray(v)) return v.filter(isDict).map(ref).filter(Boolean);
  if (typeof v === 'string') return [individual(v)];
  return [];
}

function trackEntries(v) {
  const entry = (d) => {
    if (typeof d.name !== 'string') return null;
    const e = { name: d.name };
    const dur = parseISO8601MusicDuration(d.duration);
    if (dur != null) e.durationSeconds = dur;
    return e;
  };
  if (Array.isArray(v)) return v.filter(isDict).map((d) => (isDict(d.item) ? entry(d.item) : entry(d))).filter(Boolean);
  if (isDict(v)) { const e = entry(v); return e ? [e] : []; }
  return [];
}

function totalDuration(list) {
  const total = list.reduce((s, t) => s + (t.durationSeconds ?? 0), 0);
  return total > 0 ? total : null;
}

export function applyMusicJSONLD(html, meta) {
  for (const node of jsonLDTypedNodes(html)) {
    const types = nodeTypes(node.dict);
    const d = node.dict;
    const has = (n) => types.some((t) => typeIs(t, n));
    if (meta.subtype === 'track' && has('MusicRecording')) {
      if (meta.cleanTitle == null && typeof d.name === 'string') meta.cleanTitle = d.name;
      if (!meta.artists.length && d.byArtist != null) meta.artists = entityRefs(d.byArtist);
      if (isDict(d.inAlbum)) {
        if (meta.album == null) set(meta, 'album', nilIfEmpty(d.inAlbum.name));
        if (meta.albumArtist == null && d.inAlbum.byArtist != null) {
          set(meta, 'albumArtist', nilIfEmpty(entityRefs(d.inAlbum.byArtist).map((r) => r.name).join(', ')));
        }
      }
      if (meta.totalDurationSeconds == null && typeof d.duration === 'string') set(meta, 'totalDurationSeconds', parseISO8601MusicDuration(d.duration));
    }
    if (has('MusicAlbum')) {
      if (meta.subtype === 'track') {
        if (meta.album == null) set(meta, 'album', nilIfEmpty(d.name));
        if (meta.albumArtist == null && d.byArtist != null) {
          set(meta, 'albumArtist', nilIfEmpty(entityRefs(d.byArtist).map((r) => r.name).join(', ')));
        }
      } else if (meta.cleanTitle == null && typeof d.name === 'string') meta.cleanTitle = d.name;
      if (!meta.genres.length) meta.genres = stringArray(d.genre);
      if (meta.releaseYear == null && typeof d.datePublished === 'string' && d.datePublished.length >= 4) meta.releaseYear = d.datePublished.slice(0, 4);
      if (meta.label == null) {
        if (isDict(d.recordLabel) && typeof d.recordLabel.name === 'string') meta.label = d.recordLabel.name;
        else if (typeof d.recordLabel === 'string') meta.label = d.recordLabel;
      }
      if (!meta.artists.length && d.byArtist != null) meta.artists = entityRefs(d.byArtist);
      if (!meta.trackList.length && d.track != null) {
        meta.trackList = trackEntries(d.track);
        const total = totalDuration(meta.trackList);
        if (total != null) meta.totalDurationSeconds = total; else delete meta.totalDurationSeconds;
      }
    }
    if (has('MusicComposition') && !meta.artists.length && d.composer != null) meta.artists = entityRefs(d.composer);
    if (has('MusicGroup') && !meta.artists.length && typeof d.name === 'string') meta.artists = [individual(d.name)];
    if (has('AudioObject') && meta.previewAudioURL == null && typeof d.contentUrl === 'string') meta.previewAudioURL = d.contentUrl;
  }
}

export function youtubeDescription(html) {
  const m = /"shortDescription":"((?:[^"\\]|\\.)*)"/.exec(html || '');
  if (!m) return null;
  try { return nilIfEmpty(JSON.parse(`"${m[1]}"`)); } catch { return null; }
}

export function parseProvidedToYouTube(description) {
  if (!description) return null;
  const lines = description.split(/\r\n|\r|\n|\u2028|\u2029/).map((l) => l.trim()).filter(Boolean);
  const start = lines.findIndex((l) => l.toLowerCase().startsWith('provided to youtube by'));
  if (start < 0 || start + 1 >= lines.length) return null;
  const credit = lines[start + 1].split(' · ').map((s) => s.trim()).filter(Boolean);
  if (credit.length < 2) return null;
  let album = null;
  if (start + 2 < lines.length) {
    const c = lines[start + 2];
    const l = c.toLowerCase();
    const footer = c.startsWith('℗') || c.startsWith('©') || l.startsWith('released on') || l.startsWith('auto-generated');
    if (!footer) album = c;
  }
  return { artists: credit.slice(1), album };
}

export function parseSpotifyDescription(description) {
  if (!description) return null;
  const segments = description.split(' · ').map((s) => s.replace(/^[\s.]+|[\s.]+$/g, ''));
  const typeWords = new Set(['song', 'album', 'single', 'ep', 'compilation']);
  const i = segments.findIndex((s) => typeWords.has((s.split(' ').pop() || '').toLowerCase()));
  if (i < 0 || i + 1 >= segments.length) return null;
  const artist = nilIfEmpty(segments[i + 1]);
  const yr = segments.slice(i + 2).find((s) => /^[0-9]{4}$/.test(s)) ?? null;
  return { artist, year: yr };
}

export function cleanAppleMusicTrackTitle(ogTitle) {
  let title = nilIfEmpty(ogTitle);
  if (!title) return null;
  const i = title.toLowerCase().lastIndexOf(' on apple music');
  if (i < 0) return title;
  title = title.slice(0, i);
  const by = title.lastIndexOf(' by ');
  if (by >= 0) title = title.slice(0, by);
  return nilIfEmpty(title);
}

export function ruleParseYouTubeMusicTitle(rawTitle) {
  const pipes = rawTitle.split('|').map((s) => s.trim()).filter(Boolean);
  const result = { artist: null, track: null, film: null };
  const first = pipes[0] ?? rawTitle.trim();
  let film = false;
  const dash = first.indexOf(' - ');
  if (dash >= 0) {
    const before = first.slice(0, dash).trim();
    const after = first.slice(dash + 3).trim();
    if (DESCRIPTOR_WORDS.has(after.toLowerCase())) {
      result.track = before;
      film = true;
    } else {
      result.artist = before;
      result.track = after;
    }
  } else {
    result.track = first;
  }
  if (film && pipes.length >= 2) result.film = pipes[1];
  return result;
}

export function splitMusicEdition(rawTitle) {
  const m = /\s*\(([^)]+)\)\s*$/.exec(rawTitle);
  if (!m) return { title: rawTitle.trim(), edition: null };
  const bracketed = m[1].trim();
  const base = rawTitle.slice(0, m.index).trim();
  if (!EDITION_KEYWORDS.some((k) => bracketed.toLowerCase().includes(k))) return { title: rawTitle.trim(), edition: null };
  return { title: base, edition: bracketed };
}

function applyRuleTitleParsing(rawTitle, platform, meta) {
  if (!rawTitle || !rawTitle.trim()) return;
  const { title, edition } = splitMusicEdition(rawTitle);
  if (meta.edition == null) set(meta, 'edition', edition);
  if (platform !== 'youtube' && platform !== 'youtube-music') {
    if (meta.cleanTitle == null) meta.cleanTitle = title;
    return;
  }
  const parsed = ruleParseYouTubeMusicTitle(title);
  if (meta.cleanTitle == null) meta.cleanTitle = parsed.track ?? title;
  if (!meta.artists.length && parsed.artist) meta.artists = [individual(parsed.artist)];
  if (meta.film == null) set(meta, 'film', parsed.film);
}

export function applyCurator(rawTitle, description, subtype, meta) {
  if (subtype !== 'playlist' || meta.curator != null) return;
  for (const c of [rawTitle, description].filter(Boolean)) {
    const m = /\bby\s+(.+)$/i.exec(c);
    if (!m) continue;
    const name = m[1].trim();
    if (!name) continue;
    meta.curator = individual(name);
    return;
  }
}

export function applyDeezerMatch(match, meta) {
  if (meta.subtype !== 'track') { applyDeezerData(match.album, meta); return; }
  const deezerAlbum = nilIfEmpty(match.album.title);
  const known = nilIfEmpty(meta.album);
  if (known && deezerAlbum && known.toLowerCase() !== deezerAlbum.toLowerCase()) return;
  if (meta.album == null) set(meta, 'album', deezerAlbum);
  if (meta.albumArtist == null) set(meta, 'albumArtist', nilIfEmpty(match.album.artist?.name));
  applyDeezerData(match.album, meta);
  if (match.track?.duration > 0) meta.totalDurationSeconds = match.track.duration;
}

export function applyDeezerData(d, meta) {
  if (meta.upc == null) set(meta, 'upc', typeof d.upc === 'string' ? d.upc : null);
  if (meta.label == null) set(meta, 'label', typeof d.label === 'string' ? d.label : null);
  if (meta.releaseYear == null && typeof d.release_date === 'string' && d.release_date.length >= 4) meta.releaseYear = d.release_date.slice(0, 4);
  const genres = Array.isArray(d.genres?.data) ? d.genres.data.map((g) => g?.name).filter((n) => typeof n === 'string') : [];
  if (!meta.genres.length && genres.length) meta.genres = genres;
  const tracks = Array.isArray(d.tracks?.data) ? d.tracks.data.filter((t) => typeof t?.title === 'string') : [];
  if (!meta.trackList.length && tracks.length) {
    meta.trackList = tracks.map((t) => (Number.isInteger(t.duration) ? { name: t.title, durationSeconds: t.duration } : { name: t.title }));
    const total = totalDuration(meta.trackList);
    if (total != null) meta.totalDurationSeconds = total; else delete meta.totalDurationSeconds;
  }
}

// ─── Network-backed extraction ──────────────────────────────────────────

const enc = (s) => encodeURIComponent(s);
const youtubeOEmbedURL = (url) => `https://www.youtube.com/oembed?url=${enc(url)}&format=json`;

/**
 * @param net  { json(url, opts) → object|null } (pipeline.js)
 * @returns {Promise<null | { meta, coverImageURL, coverFallbackURL, rawTitle }>}
 */
export async function classifyAndExtractMusic({ sourceURL, domain, title, ogType, page, net }) {
  if (!domain) return null;
  const src = toURL(sourceURL);
  let platform = musicPlatform(domain);
  let ytOEmbed = null;
  if (platform == null) {
    if (isPlainYouTubeHost(domain)) {
      ytOEmbed = await net.json(youtubeOEmbedURL(src.href));
      if (!isMusicYouTubeSignal(ytOEmbed?.author_name ?? null, ytOEmbed?.title ?? title)) return null;
      platform = 'youtube';
    } else if (isMusicOGType(ogType)) {
      platform = 'unknown';
    } else {
      return null;
    }
  }
  const subtype = musicSubtype(src, ogType, platform);
  const meta = { ...emptyMusicMeta(), subtype, platform, canonicalURL: src.href };
  let rawTitle = title;
  let coverURL = null;
  let coverFallbackURL = null;
  const fromOEmbed = (r, withAuthor) => {
    rawTitle = r.title ?? rawTitle;
    coverURL = r.thumbnail_url ?? null;
    set(meta, 'embedURL', embedURL(r));
    const author = nilIfEmpty(r.author_name);
    if (withAuthor && author) meta.artists = [individual(author)];
  };

  switch (platform) {
    case 'apple-music': case 'deezer': case 'bandcamp': case 'unknown':
      if (page) {
        rawTitle = page.og.title ?? rawTitle;
        coverURL = page.og.imageURL ?? null;
        applyMusicJSONLD(page.html, meta);
      }
      if (platform === 'apple-music' && subtype === 'track' && page) rawTitle = cleanAppleMusicTrackTitle(page.og.title) ?? rawTitle;
      break;
    case 'spotify': {
      const r = await net.json(`https://open.spotify.com/oembed?url=${enc(src.href)}`);
      if (r) fromOEmbed(r, false);
      const parsed = parseSpotifyDescription(page?.og.description ?? null);
      if (parsed) {
        if (!meta.artists.length && parsed.artist) meta.artists = [individual(parsed.artist)];
        if (meta.releaseYear == null) set(meta, 'releaseYear', parsed.year);
      }
      break;
    }
    case 'youtube': case 'youtube-music': {
      const r = ytOEmbed ?? await net.json(youtubeOEmbedURL(src.href));
      if (r) {
        rawTitle = r.title ?? rawTitle;
        set(meta, 'embedURL', embedURL(r));
        const author = nilIfEmpty(r.author_name);
        if (author) {
          const cleaned = author.replace(/ - Topic/gi, '').trim();
          if (cleaned) meta.artists = [individual(cleaned)];
        }
      }
      if (subtype === 'track' && page) {
        const provided = parseProvidedToYouTube(youtubeDescription(page.html) ?? page.og.description);
        if (provided) {
          if (meta.album == null) set(meta, 'album', provided.album);
          if (!meta.artists.length && provided.artists.length) meta.artists = provided.artists.map(individual);
        }
      }
      const id = youtubeVideoID(src);
      if (id) {
        coverURL = `https://i.ytimg.com/vi/${id}/maxresdefault.jpg`;
        coverFallbackURL = `https://i.ytimg.com/vi/${id}/hqdefault.jpg`;
      }
      break;
    }
    case 'tidal': {
      const r = await net.json(`https://oembed.tidal.com/?url=${enc(src.href)}`);
      if (r) fromOEmbed(r, false);
      break;
    }
    case 'mixcloud': {
      const r = await net.json(`https://app.mixcloud.com/oembed/?url=${enc(src.href)}&format=json`);
      if (r) fromOEmbed(r, true);
      break;
    }
    case 'soundcloud': {
      const r = await net.json(`https://soundcloud.com/oembed?url=${enc(src.href)}&format=json`);
      if (r) fromOEmbed(r, true);
      break;
    }
    default: break;
  }

  applyRuleTitleParsing(rawTitle, platform, meta);
  applyCurator(rawTitle, page?.og.description ?? null, subtype, meta);

  const searchTitle = nilIfEmpty(meta.cleanTitle ?? rawTitle);
  if (searchTitle) {
    const match = await deezerResolve(meta.artists[0]?.name ?? null, searchTitle, subtype, net);
    if (match) applyDeezerMatch(match, meta);
  }
  return { meta, coverImageURL: coverURL, coverFallbackURL, rawTitle };
}

async function deezerResolve(artist, title, subtype, net) {
  const q = enc([artist, title].filter(Boolean).join(' '));
  let albumID = null;
  let track = null;
  if (subtype === 'track') {
    const r = await net.json(`https://api.deezer.com/search/track?q=${q}`, { timeout: 10000 });
    const hit = Array.isArray(r?.data) ? r.data[0] : null;
    if (hit && Number.isInteger(hit.id)) {
      track = hit;
      albumID = hit.album?.id ?? null;
    }
  }
  if (albumID == null && track == null) {
    const r = await net.json(`https://api.deezer.com/search/album?q=${q}`, { timeout: 10000 });
    albumID = Array.isArray(r?.data) ? r.data[0]?.id ?? null : null;
  }
  if (albumID == null) return null;
  const album = await net.json(`https://api.deezer.com/album/${albumID}`, { timeout: 10000 });
  return isDict(album) && !album.error ? { album, track } : null;
}

function set(obj, key, value) {
  if (value != null) obj[key] = value;
}
