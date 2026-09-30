// Loads dist/youtubejs_probe.js in Node with an emulated `fmp` host (for fast
// iteration only; the real verdict comes from FMP's QuickJS runtime).
// STRIP=1 deletes Node's web globals first to mimic QuickJS.
import { pathToFileURL } from 'node:url';
import https from 'node:https';

const moduleUrl = pathToFileURL('dist/youtubejs_probe.js').href;
if (process.env.STRIP === '1') {
  for (const k of ['URL', 'URLSearchParams', 'TextEncoder', 'TextDecoder', 'fetch', 'Request', 'Response', 'Headers',
    'FormData', 'File', 'Blob', 'ReadableStream', 'CustomEvent', 'Event', 'EventTarget', 'AbortController',
    'AbortSignal', 'atob', 'btoa', 'structuredClone', 'crypto', 'setTimeout', 'clearTimeout', 'setInterval',
    'queueMicrotask', 'Intl', 'performance', 'navigator']) {
    try { delete globalThis[k]; } catch { /* ignore */ }
    if (k in globalThis) Object.defineProperty(globalThis, k, { value: undefined, configurable: true, writable: true });
  }
}
const store = new Map();
globalThis.fmp = {
  apiVersion: 1,
  http: {
    async request({ url, method, headers, body }) {
      return await new Promise((resolve, reject) => {
        const req = https.request(url, { method: method || 'GET', headers: headers || {} }, (res) => {
          const chunks = [];
          res.on('data', (c) => chunks.push(c));
          res.on('end', () => {
            const h = {};
            for (const [k, v] of Object.entries(res.headers)) h[k] = Array.isArray(v) ? v : [String(v)];
            resolve({ status: res.statusCode, url, headers: h, body: Buffer.concat(chunks).toString('utf8') });
          });
        });
        req.on('error', reject);
        if (body != null) req.write(body);
        req.end();
      });
    },
  },
  crypto: {},
  storage: {
    get: async (k) => store.get(k) ?? null,
    set: async (k, v) => { store.set(k, v); },
    delete: async (k) => { store.delete(k); },
  },
  credentials: { get: async () => null },
  log: { debug: console.log, info: console.log, warn: console.log, error: console.log },
};
const m = await import(moduleUrl);
const page = await m.search({ keyword: 'rick astley', page: 1 });
console.log('items', page.items.length, page.items.slice(0, 2));
const id = page.items.find((t) => t.durationMs > 60000 && t.durationMs < 900000).sourceId;
const r = await m.resolveStream({ sourceId: id, purpose: 'playback', formats: [{ container: 'mp4', codec: 'aac' }] });
console.log(r.candidates.map((c) => [c.container, c.codec, c.bitrate, new URL(c.url).host]));
