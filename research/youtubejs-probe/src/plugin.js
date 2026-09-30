// Probe plugin: YouTube.js (youtubei.js) inside FMP's plugin runtime.
// Built by build.mjs into ../dist/youtubejs_probe.js with the FMP manifest header.
import { HeadersShim, RequestShim, ResponseShim, fetchShim } from './shims.js';
import { Innertube, Platform, Log } from 'youtubei.js/web';

// ---------------------------------------------------------------- platform
// Cache over fmp.storage (values are ArrayBuffers; storage takes strings).
class StorageCache {
  constructor() { this.cache_dir = ''; }
  async get(key) {
    const v = await fmp.storage.get(`ytjs:${key}`);
    if (v == null) return undefined;
    const bin = atob(v);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out.buffer;
  }
  async set(key, value) {
    const u8 = new Uint8Array(value);
    let bin = '';
    for (let i = 0; i < u8.length; i += 8192) bin += String.fromCharCode.apply(null, u8.subarray(i, i + 8192));
    await fmp.storage.set(`ytjs:${key}`, btoa(bin));
  }
  async remove(key) { await fmp.storage.delete(`ytjs:${key}`); }
}

Platform.load({
  runtime: 'fmp-quickjs',
  server: true,
  Cache: StorageCache,
  sha1Hash: async () => { throw new Error('sha1Hash is only used for logged-in requests'); },
  uuidv4: () => globalThis.crypto.randomUUID(),
  // Player JS deciphering (signature / n). QuickJS has eval/new Function; the
  // ANDROID_VR path never needs it (its URLs are not ciphered), kept for completeness.
  eval: (data, env) => {
    const props = [];
    if (env.n) props.push(`n: exportedVars.nFunction(${JSON.stringify(env.n)})`);
    if (env.sig) props.push(`sig: exportedVars.sigFunction(${JSON.stringify(env.sig)})`);
    return new Function(`${data.output}\nreturn { ${props.join(', ')} }`)();
  },
  fetch: fetchShim,
  Request: RequestShim,
  Response: ResponseShim,
  Headers: HeadersShim,
  FormData: class FormData {},
  File: class File {},
  ReadableStream: class ReadableStream {},
  CustomEvent: class CustomEvent {},
});
Log.setLevel(Log.Level.ERROR);

// ---------------------------------------------------------------- session
const CLIENT = 'ANDROID_VR';
let innertubePromise = null;
const now = () => Date.now();

function innertube() {
  if (!innertubePromise) {
    const t0 = now();
    innertubePromise = Innertube.create({
      retrieve_player: false, // ANDROID_VR URLs are plain; no player JS download/parse
      timezone: 'UTC', // Session's default reads Intl, which QuickJS lacks
      cache: new StorageCache(),
      enable_session_cache: true,
    }).then((yt) => {
      fmp.log.info(`[probe] Innertube.create ms=${now() - t0}`);
      return yt;
    }, (e) => {
      innertubePromise = null;
      throw e;
    });
  }
  return innertubePromise;
}

const continuations = new Map();

// ---------------------------------------------------------------- capabilities
export async function search({ keyword, page }) {
  const yt = await innertube();
  const t0 = now();
  let result;
  if (page > 1 && continuations.has(`${keyword}#${page}`)) {
    result = await continuations.get(`${keyword}#${page}`).getContinuation();
  } else {
    result = await yt.search(keyword, { type: 'video' });
  }
  const items = [];
  for (const v of result.videos) {
    if (v.type !== 'Video' || !v.video_id) continue;
    const seconds = v.duration && v.duration.seconds;
    items.push({
      sourceId: v.video_id,
      title: v.title ? v.title.toString() : v.video_id,
      uploader: v.author ? v.author.name : null,
      durationMs: typeof seconds === 'number' && seconds > 0 ? seconds * 1000 : null,
      artwork: (v.thumbnails || [])
        .filter((t) => typeof t.url === 'string' && t.url.startsWith('https://') && /(^|\.)ytimg\.com$/.test(new URL(t.url).host))
        .map((t) => ({ url: t.url, width: t.width || null })),
    });
  }
  if (result.has_continuation) continuations.set(`${keyword}#${page + 1}`, result);
  fmp.log.info(`[probe] search ms=${now() - t0} items=${items.length}`);
  return { items, hasMore: !!result.has_continuation };
}

function describe(mime) {
  const m = /^audio\/(\w+);\s*codecs="([^"]+)"/.exec(mime || '');
  if (!m) return { container: null, codec: null };
  const codec = m[2].startsWith('mp4a') ? 'aac' : m[2];
  return { container: m[1], codec };
}

export async function resolveStream({ sourceId, formats }) {
  const yt = await innertube();
  const t0 = now();
  const info = await yt.getBasicInfo(sourceId, { client: CLIENT });
  const ps = info.playability_status || {};
  if (ps.status !== 'OK') {
    throw { fmpError: 'Unavailable', reason: 'region', message: `${CLIENT} playability ${ps.status}: ${ps.reason || ''}` };
  }
  const audio = ((info.streaming_data && info.streaming_data.adaptive_formats) || []).filter((f) => f.has_audio && !f.has_video);
  const wanted = (formats || []).map((f) => `${f.container}/${f.codec}`);
  const rank = (c) => { const i = wanted.indexOf(`${c.container}/${c.codec}`); return i < 0 ? wanted.length : i; };
  const candidates = [];
  for (const f of audio) {
    const url = await f.decipher(undefined); // plain URL for ANDROID_VR
    if (!url) continue;
    const { container, codec } = describe(f.mime_type);
    const expire = Number(new URL(url).searchParams.get('expire'));
    candidates.push({ url, container, codec, bitrate: f.bitrate || null, expiresAt: expire > 0 ? expire * 1000 : null });
  }
  candidates.sort((a, b) => rank(a) - rank(b) || (b.bitrate || 0) - (a.bitrate || 0));
  if (candidates.length === 0) throw { fmpError: 'NotFound', message: 'no audio-only formats' };
  fmp.log.info(`[probe] resolveStream ms=${now() - t0} client=${CLIENT} candidates=${candidates.length} first=${candidates[0].container}/${candidates[0].codec}@${candidates[0].bitrate}`);
  return { candidates };
}
