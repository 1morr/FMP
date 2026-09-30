// Web API shims for FMP's QuickJS plugin runtime (host API v1 only).
// Everything here lives inside the plugin script; FMP's host code is untouched.
//
// QuickJS (flutter_js 0.8.7) has the ES built-ins but none of the web platform:
// no URL, TextEncoder/TextDecoder, fetch family, crypto, atob/btoa, timers.
import 'core-js/actual/url';
import 'core-js/actual/url-search-params';
import 'core-js/actual/atob';
import 'core-js/actual/btoa';
import 'core-js/actual/structured-clone';

const g = globalThis;

// ---------------------------------------------------------------- text
class TextEncoderShim {
  get encoding() { return 'utf-8'; }
  encode(input = '') {
    const s = String(input);
    const out = [];
    for (let i = 0; i < s.length; i++) {
      let c = s.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
        const d = s.charCodeAt(i + 1);
        if (d >= 0xdc00 && d <= 0xdfff) { c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00); i++; }
        else c = 0xfffd;
      } else if (c >= 0xd800 && c <= 0xdfff) c = 0xfffd;
      if (c < 0x80) out.push(c);
      else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
      else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
    return new Uint8Array(out);
  }
}
class TextDecoderShim {
  constructor(label = 'utf-8') {
    if (!/^utf-?8$/i.test(label)) throw new RangeError(`TextDecoder shim: only utf-8, got ${label}`);
  }
  get encoding() { return 'utf-8'; }
  decode(input) {
    if (input === undefined) return '';
    const b = input instanceof Uint8Array ? input
      : ArrayBuffer.isView(input) ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength)
        : new Uint8Array(input);
    let out = '';
    const chunk = [];
    for (let i = 0; i < b.length;) {
      const x = b[i++];
      let c;
      if (x < 0x80) c = x;
      else if (x >= 0xc2 && x < 0xe0 && i < b.length) c = ((x & 31) << 6) | (b[i++] & 63);
      else if (x >= 0xe0 && x < 0xf0 && i + 1 < b.length) { c = ((x & 15) << 12) | ((b[i] & 63) << 6) | (b[i + 1] & 63); i += 2; }
      else if (x >= 0xf0 && x < 0xf5 && i + 2 < b.length) { c = ((x & 7) << 18) | ((b[i] & 63) << 12) | ((b[i + 1] & 63) << 6) | (b[i + 2] & 63); i += 3; }
      else c = 0xfffd;
      if (c > 0xffff) { c -= 0x10000; chunk.push(0xd800 + (c >> 10), 0xdc00 + (c & 1023)); }
      else chunk.push(c);
      if (chunk.length > 8000) { out += String.fromCharCode.apply(null, chunk); chunk.length = 0; }
    }
    return out + String.fromCharCode.apply(null, chunk);
  }
}
if (!g.TextEncoder) g.TextEncoder = TextEncoderShim;
if (!g.TextDecoder) g.TextDecoder = TextDecoderShim;

// ---------------------------------------------------------------- crypto (not security relevant here)
if (!g.crypto) {
  g.crypto = {
    getRandomValues(arr) {
      for (let i = 0; i < arr.length; i++) arr[i] = Math.floor(Math.random() * 256);
      return arr;
    },
    randomUUID() {
      return '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, (ch) => {
        const c = Number(ch);
        return (c ^ (Math.floor(Math.random() * 256) & (15 >> (c / 4)))).toString(16);
      });
    },
  };
}

// ---------------------------------------------------------------- timers
// No setTimeout in host API v1. Nothing on the search/resolve path uses it
// (only LiveChat/OAuth2); run callbacks on the microtask queue, ignore delay.
if (!g.setTimeout) {
  let id = 0;
  const cancelled = new Set();
  g.setTimeout = (fn, _ms, ...args) => {
    const h = ++id;
    Promise.resolve().then(() => { if (!cancelled.delete(h)) fn(...args); });
    return h;
  };
  g.clearTimeout = (h) => { cancelled.add(h); };
}
if (!g.queueMicrotask) g.queueMicrotask = (fn) => { Promise.resolve().then(fn); };

// ---------------------------------------------------------------- fetch family over fmp.http.request
class HeadersShim {
  constructor(init) {
    this._m = new Map();
    if (!init) return;
    if (init instanceof HeadersShim) init.forEach((v, k) => this.append(k, v));
    else if (Array.isArray(init)) for (const [k, v] of init) this.append(k, v);
    else for (const k of Object.keys(init)) this.append(k, init[k]);
  }
  append(k, v) {
    const key = String(k).toLowerCase();
    const prev = this._m.get(key);
    this._m.set(key, prev === undefined ? String(v) : `${prev}, ${v}`);
  }
  set(k, v) { this._m.set(String(k).toLowerCase(), String(v)); }
  get(k) { const v = this._m.get(String(k).toLowerCase()); return v === undefined ? null : v; }
  has(k) { return this._m.has(String(k).toLowerCase()); }
  delete(k) { this._m.delete(String(k).toLowerCase()); }
  forEach(cb, thisArg) { for (const [k, v] of this._m) cb.call(thisArg, v, k, this); }
  *entries() { yield* this._m.entries(); }
  *keys() { yield* this._m.keys(); }
  *values() { yield* this._m.values(); }
  [Symbol.iterator]() { return this.entries(); }
  getSetCookie() { const v = this._m.get('set-cookie'); return v ? v.split(/,\s*(?=[^;,]+=)/) : []; }
}

class RequestShim {
  constructor(input, init = {}) {
    const base = input instanceof RequestShim ? input : null;
    this.url = base ? base.url : String(input instanceof URL ? input.href : input);
    this.method = ((init && init.method) || (base && base.method) || 'GET').toUpperCase();
    this.headers = new HeadersShim((init && init.headers) || (base && base.headers) || undefined);
    this.body = (init && init.body !== undefined) ? init.body : (base ? base.body : undefined);
    this.redirect = (init && init.redirect) || (base && base.redirect) || 'follow';
    this.signal = (init && init.signal) || undefined;
  }
  clone() { return new RequestShim(this); }
}

const encoder = new TextEncoderShim();
class ResponseShim {
  constructor(body = '', init = {}) {
    this._text = typeof body === 'string' ? body : body == null ? '' : new TextDecoderShim().decode(body);
    this.status = init.status === undefined ? 200 : init.status;
    this.statusText = init.statusText || '';
    this.headers = init.headers instanceof HeadersShim ? init.headers : new HeadersShim(init.headers);
    this.url = init.url || '';
    this.redirected = false;
    this.type = 'basic';
    this.bodyUsed = false;
  }
  get ok() { return this.status >= 200 && this.status < 300; }
  get body() { return null; } // no ReadableStream: download() is not supported
  async text() { this.bodyUsed = true; return this._text; }
  async json() { this.bodyUsed = true; return JSON.parse(this._text); }
  // Host API v1 hands the plugin a UTF-8-decoded string; binary bodies are lossy.
  async arrayBuffer() { this.bodyUsed = true; return encoder.encode(this._text).buffer; }
  clone() { return new ResponseShim(this._text, this); }
}

async function fetchShim(input, init = {}) {
  const req = new RequestShim(input, init);
  const headers = {};
  req.headers.forEach((v, k) => { headers[k] = v; });
  let body = req.body;
  if (body != null && typeof body !== 'string') {
    if (body instanceof URLSearchParams) body = body.toString();
    else if (ArrayBuffer.isView(body) || body instanceof ArrayBuffer) {
      // Host API v1 only carries string bodies. Protobuf request bodies would need a
      // binary-safe primitive; we fail loudly instead of corrupting them.
      throw new TypeError('fetch shim: binary request bodies are not supported by fmp.http.request');
    } else body = String(body);
  }
  const res = await fmp.http.request({ url: req.url, method: req.method, headers, body: body == null ? null : body });
  const h = new HeadersShim();
  for (const k of Object.keys(res.headers)) for (const v of res.headers[k]) h.append(k, v);
  return new ResponseShim(res.body, { status: res.status, headers: h, url: res.url });
}

g.Headers = g.Headers || HeadersShim;
g.Request = g.Request || RequestShim;
g.Response = g.Response || ResponseShim;
g.fetch = g.fetch || fetchShim;

export { HeadersShim, RequestShim, ResponseShim, fetchShim };
