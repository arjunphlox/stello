// Port of StelloTests/MusicEnrichmentTests.swift (mood / why-saved vocabulary, panel-row
// and SwiftData tests stay with the Apple app).
import { test } from 'node:test';
import { eq } from './readers-helpers.js';
import * as C from '../src/lib/readers/classifier.js';
import * as M from '../src/lib/readers/music.js';

const sub = (url, platform) => C.musicSubtype(new URL(url), null, platform);
const offlineNet = { json: async () => null, get: async () => null, used: 0 };

test('Known music hosts classify by domain; Amazon Music and generic hosts do not', () => {
  for (const [host, p] of [['open.spotify.com', 'spotify'], ['music.apple.com', 'apple-music'], ['arjun.bandcamp.com', 'bandcamp'],
    ['soundcloud.com', 'soundcloud'], ['music.youtube.com', 'youtube-music'], ['tidal.com', 'tidal'], ['mixcloud.com', 'mixcloud'], ['deezer.com', 'deezer']])
    eq(C.musicPlatform(host), p, host);
  eq(C.musicPlatform('music.amazon.com'), null);
  eq(C.musicPlatform('example.com'), null);
});

test('Plain YouTube is a candidate only; music.youtube.com is matched separately', () => {
  eq(C.isPlainYouTubeHost('youtube.com'), true);
  eq(C.isPlainYouTubeHost('youtu.be'), true);
  eq(C.isPlainYouTubeHost('music.youtube.com'), false);
});

test("'- Topic' channel and VEVO confirm music; an ordinary upload does not", () => {
  eq(C.isMusicYouTubeSignal('Notaker - Topic', null), true);
  eq(C.isMusicYouTubeSignal('SomeArtistVEVO', null), true);
  eq(C.isMusicYouTubeSignal(null, 'Song Title - Official Music Video'), true);
  eq(C.isMusicYouTubeSignal('Random Vlogger', 'My Day At The Beach'), false);
  eq(C.isMusicYouTubeSignal('Some Tech Channel', 'Unboxing My New Laptop'), false);
});

test('og:type music.* classifies regardless of host', () => {
  for (const t of ['music.album', 'music.song', 'music.playlist', 'music.musician']) eq(C.isMusicOGType(t), true, t);
  eq(C.isMusicOGType('article'), false);
  eq(C.isMusicOGType(null), false);
});

test('Subtypes from real URLs', () => {
  eq(sub('https://music.apple.com/in/playlist/focus-zone/pl.u-g3y0HWE82zr', 'apple-music'), 'playlist');
  eq(sub('https://music.apple.com/in/album/f1/1821963324?i=1821963565', 'apple-music'), 'track');
  eq(sub('https://music.apple.com/in/artist/a-ka/1743301775', 'apple-music'), 'artist');
  eq(sub('https://open.spotify.com/album/063f8Ej8rLVTz9KkjQKEMa', 'spotify'), 'album');
  eq(sub('https://music.youtube.com/watch?v=I4sFp6hZg14', 'youtube-music'), 'track');
  eq(sub('https://www.mixcloud.com/someuser/some-show/', 'mixcloud'), 'mix');
});

test('Playlist curator extraction; never fabricated for a non-playlist subtype', () => {
  const meta = M.emptyMusicMeta();
  M.applyCurator('Focus Zone by Arjun Phlox', null, 'playlist', meta);
  eq(meta.curator?.name, 'Arjun Phlox');
  const track = M.emptyMusicMeta();
  M.applyCurator('Some Track by Someone', null, 'track', track);
  eq(track.curator, null);
});

test("Rule fallback: Western 'Artist - Track' grammar", () => {
  eq(M.ruleParseYouTubeMusicTitle('Zara Larsson - How Deep Is Your Love (Calvin Harris, Disciples Cover) (Live) | Spotify Live Room'),
    { artist: 'Zara Larsson', track: 'How Deep Is Your Love (Calvin Harris, Disciples Cover) (Live)', film: null });
});

test('Rule fallback: Indian film-music grammar names the film, not an artist', () => {
  eq(M.ruleParseYouTubeMusicTitle('Thassadiya - Video Song | Maa Inti Bangaaram | Samantha | Chinmayi | Punya | Santhosh Narayanan'),
    { artist: null, track: 'Thassadiya', film: 'Maa Inti Bangaaram' });
  eq(M.ruleParseYouTubeMusicTitle('Aerodynamic'), { artist: null, track: 'Aerodynamic', film: null });
});

test('Edition suffix splits off remaster/year markers only', () => {
  eq(M.splitMusicEdition('Ambient 1: Music For Airports (Remastered 2004)'), { title: 'Ambient 1: Music For Airports', edition: 'Remastered 2004' });
  eq(M.splitMusicEdition('How Deep Is Your Love (Calvin Harris, Disciples Cover)'), { title: 'How Deep Is Your Love (Calvin Harris, Disciples Cover)', edition: null });
});

test('Spotify oEmbed iframe → embed URL', () => {
  eq(M.embedURL({ iframe_url: 'https://open.spotify.com/embed/album/063f8Ej8rLVTz9KkjQKEMa', title: 'An Album' }), 'https://open.spotify.com/embed/album/063f8Ej8rLVTz9KkjQKEMa');
});

test('Deezer album response fills upc / year / genres / track list / total length', () => {
  const d = { id: 302127, title: 'Discovery', upc: '0724384960650', release_date: '2001-03-07', label: 'Parlophone France',
    genres: { data: [{ id: 113, name: 'Dance' }] }, tracks: { data: [{ id: 1, title: 'One More Time', duration: 320 }, { id: 2, title: 'Aerodynamic', duration: 213 }] } };
  const meta = M.emptyMusicMeta();
  M.applyDeezerData(d, meta);
  eq(meta.upc, '0724384960650');
  eq(meta.releaseYear, '2001');
  eq(meta.genres, ['Dance']);
  eq(meta.trackList.length, 2);
  eq(meta.totalDurationSeconds, 533);
});

test("'Provided to YouTube' description names track artists and album", () => {
  const description = 'Provided to YouTube by Republic Records\n\nBlinding Lights · The Weeknd\n\nAfter Hours\n\n℗ 2020 The Weeknd XO, Inc.\n\nReleased on: 2020-03-20';
  eq(M.parseProvidedToYouTube(description), { artists: ['The Weeknd'], album: 'After Hours' });
  const noAlbum = M.parseProvidedToYouTube('Provided to YouTube by DistroKid\n\nSong · Artist One · Artist Two\n\n℗ 2021 Artist One');
  eq(noAlbum?.artists, ['Artist One', 'Artist Two']);
  eq(noAlbum?.album, null);
  eq(M.parseProvidedToYouTube('New video every week! Subscribe for more.'), null);
  eq(M.parseProvidedToYouTube(null), null);
});

test("Full description is read from the watch page's player JSON", () => {
  const html = '<script>var ytInitialPlayerResponse = {"videoDetails":{"shortDescription":"Provided to YouTube by X\\n\\nTrack · Artist\\n\\nThe \\"Album\\"\\n\\n℗ 2020","isLive":false}};</script>';
  const description = M.youtubeDescription(html);
  eq(description, 'Provided to YouTube by X\n\nTrack · Artist\n\nThe "Album"\n\n℗ 2020');
  eq(M.parseProvidedToYouTube(description)?.album, 'The "Album"');
});

test('Spotify description gives the artist and year', () => {
  const p = M.parseSpotifyDescription('Listen to Blinding Lights on Spotify. Song · The Weeknd · 2019.');
  eq(p?.artist, 'The Weeknd');
  eq(p?.year, '2019');
  eq(M.parseSpotifyDescription('Spotify is a digital music service.'), null);
});

test('Apple Music track og:title is cleaned to the song name', () => {
  eq(M.cleanAppleMusicTrackTitle('Blinding Lights by The Weeknd on Apple Music'), 'Blinding Lights');
  eq(M.cleanAppleMusicTrackTitle('Stand by Me by Ben E. King on Apple Music'), 'Stand by Me');
  eq(M.cleanAppleMusicTrackTitle('Stand by Me'), 'Stand by Me');
});

test('Apple Music MusicRecording JSON-LD fills album and album artist', () => {
  const html = `<script type="application/ld+json">
  {"@context":"https://schema.org","@type":"MusicRecording","name":"One More Time",
   "byArtist":[{"@type":"MusicGroup","name":"Daft Punk"}],"duration":"PT5M20S",
   "inAlbum":{"@type":"MusicAlbum","name":"Discovery","byArtist":[{"@type":"MusicGroup","name":"Daft Punk"}]}}
  </script>`;
  const meta = { ...M.emptyMusicMeta(), subtype: 'track' };
  M.applyMusicJSONLD(html, meta);
  eq(meta.cleanTitle, 'One More Time');
  eq(meta.artists.map((a) => a.name), ['Daft Punk']);
  eq(meta.album, 'Discovery');
  eq(meta.albumArtist, 'Daft Punk');
  eq(meta.totalDurationSeconds, 320);
});

test('A track saved from its album page takes the album node as Album, not the title', () => {
  const html = '<script type="application/ld+json">\n{"@type":"MusicAlbum","name":"Now That\'s Music","byArtist":{"@type":"MusicGroup","name":"Various Artists"}}\n</script>';
  const meta = { ...M.emptyMusicMeta(), subtype: 'track' };
  M.applyMusicJSONLD(html, meta);
  eq(meta.cleanTitle, null);
  eq(meta.album, "Now That's Music");
  eq(meta.albumArtist, 'Various Artists');
});

test('Deezer track hit fills Album, Album artist and the track length; mismatches and albums are skipped', () => {
  const album = { title: 'Hits 2020', artist: { name: 'Various Artists' }, upc: '123', label: 'Sony', tracks: { data: [{ title: 'A', duration: 200 }, { title: 'B', duration: 100 }] } };
  const meta = { ...M.emptyMusicMeta(), subtype: 'track' };
  M.applyDeezerMatch({ album, track: { id: 1, title: 'A', duration: 200, album: { id: 9, title: 'Hits 2020' } } }, meta);
  eq(meta.album, 'Hits 2020');
  eq(meta.albumArtist, 'Various Artists');
  eq(meta.upc, '123');
  eq(meta.totalDurationSeconds, 200);
  const mismatch = { ...M.emptyMusicMeta(), subtype: 'track', album: 'Studio Album' };
  M.applyDeezerMatch({ album: { title: 'Some Live Album', artist: { name: 'Band' }, upc: '999' }, track: null }, mismatch);
  eq(mismatch.album, 'Studio Album');
  eq(mismatch.albumArtist, null);
  eq(mismatch.upc, null);
  const alb = { ...M.emptyMusicMeta(), subtype: 'album' };
  M.applyDeezerMatch({ album: { title: 'Discovery', artist: { name: 'Daft Punk' }, upc: '0724' }, track: null }, alb);
  eq(alb.album, null);
  eq(alb.albumArtist, null);
  eq(alb.upc, '0724');
});

test('Offline: a Spotify album link is still music; a plain page and an unconfirmed YouTube video are not', async () => {
  const url = new URL('https://open.spotify.com/album/063f8Ej8rLVTz9KkjQKEMa');
  const r = await M.classifyAndExtractMusic({ sourceURL: url, domain: url.hostname, title: 'Discovery (Remastered 2004)', ogType: null, page: null, net: offlineNet });
  eq(r?.meta.platform, 'spotify');
  eq(r?.meta.subtype, 'album');
  const plain = new URL('https://example.com/about');
  eq(await M.classifyAndExtractMusic({ sourceURL: plain, domain: plain.hostname, title: 'About', ogType: null, page: null, net: offlineNet }), null);
  const yt = new URL('https://www.youtube.com/watch?v=abc');
  eq(await M.classifyAndExtractMusic({ sourceURL: yt, domain: yt.hostname, title: 'Unboxing My New Laptop', ogType: null, page: null, net: offlineNet }), null);
});
