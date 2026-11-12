// bilibili/src/index.ts
var SEARCH_URL = "https://api.bilibili.com/x/web-interface/search/type";
var PAGELIST_URL = "https://api.bilibili.com/x/player/pagelist";
var PLAYURL_URL = "https://api.bilibili.com/x/player/playurl";
var API_REFERER = "https://www.bilibili.com/";
var API_ORIGIN = "https://www.bilibili.com";
var MEDIA_HEADERS = { Referer: "https://www.bilibili.com" };
var FNVAL_DASH = "16";
var TRACK_ID = /^(BV[0-9A-Za-z]{10})(?:\?p=([1-9]\d*))?$/;
var USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
var RISK_CONTROL_CODES = /* @__PURE__ */ new Set([-352, -412, -509, -799]);
var ERROR_CODES = /* @__PURE__ */ new Map([
  [-404, "not_found"],
  [62002, "unavailable_copyright"],
  [62012, "unavailable_copyright"],
  [-10403, "unavailable_region"]
]);
var COOKIE = browserCookie();
async function search({ query }) {
  const url = `${SEARCH_URL}?search_type=video&page=1&keyword=${encodeURIComponent(query)}`;
  const res = await host.http.request({
    url,
    headers: {
      "User-Agent": USER_AGENT,
      Referer: "https://search.bilibili.com/",
      Origin: "https://search.bilibili.com",
      Accept: "application/json, text/plain, */*",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      Cookie: COOKIE
    }
  });
  const data = parseResponse(res);
  const results = Array.isArray(data?.result) ? data.result : [];
  return { tracks: results.map(toTrack) };
}
async function resolveStream({
  trackId
}) {
  const match = TRACK_ID.exec(trackId);
  if (match === null) {
    throw new PluginError("not_found", `not a bilibili track id: ${trackId}`);
  }
  const bvid = match[1];
  const page = Number(match[2] ?? "1");
  const cid = await partCid(bvid, page);
  const data = await apiGet(
    `${PLAYURL_URL}?bvid=${bvid}&cid=${cid}&fnval=${FNVAL_DASH}`
  );
  const audio = bestAudio(data?.dash?.audio);
  return {
    url: audio.url,
    headers: { ...MEDIA_HEADERS },
    expiresAtMs: deadlineMs(audio.url),
    codec: audio.codec,
    bitrate: audio.bandwidth
  };
}
async function partCid(bvid, page) {
  const data = await apiGet(`${PAGELIST_URL}?bvid=${bvid}`);
  if (!Array.isArray(data)) {
    throw new PluginError("parse_failure", "pagelist without a list");
  }
  const part = data.find(
    (p) => p?.page === page
  );
  if (part === void 0) {
    throw new PluginError("not_found", `${bvid} has no part ${page}`);
  }
  if (typeof part.cid !== "number") {
    throw new PluginError("parse_failure", "pagelist part without a cid");
  }
  return part.cid;
}
function bestAudio(tracks) {
  const audios = [];
  for (const track of Array.isArray(tracks) ? tracks : []) {
    const { baseUrl, base_url, bandwidth, codecs } = track ?? {};
    const url = typeof baseUrl === "string" ? baseUrl : base_url;
    if (typeof url === "string" && url !== "" && typeof bandwidth === "number") {
      audios.push({
        url,
        bandwidth,
        codec: typeof codecs === "string" ? codecs : void 0
      });
    }
  }
  if (audios.length === 0) {
    throw new PluginError("parse_failure", "playurl without DASH audio");
  }
  return audios.reduce((best, a) => a.bandwidth > best.bandwidth ? a : best);
}
function deadlineMs(url) {
  const match = /[?&]deadline=(\d+)(?:&|#|$)/.exec(url);
  return match === null ? void 0 : Number(match[1]) * 1e3;
}
async function apiGet(url) {
  const res = await host.http.request({
    url,
    headers: {
      "User-Agent": USER_AGENT,
      Referer: API_REFERER,
      Origin: API_ORIGIN,
      Accept: "application/json, text/plain, */*",
      Cookie: COOKIE
    }
  });
  return parseResponse(res);
}
function parseResponse(res) {
  if (res.status === 412 || res.status === 429) {
    throw new PluginError("rate_limited", `HTTP ${res.status}`);
  }
  if (res.status !== 200) {
    throw new PluginError("network", `HTTP ${res.status}`);
  }
  let body;
  try {
    body = JSON.parse(res.body);
  } catch {
    throw new PluginError("parse_failure", "response is not JSON");
  }
  if (body.code !== 0) {
    const detail = `code ${String(body.code)}: ${String(body.message)}`;
    if (typeof body.code === "number" && RISK_CONTROL_CODES.has(body.code)) {
      throw new PluginError("rate_limited", detail);
    }
    const known = typeof body.code === "number" ? ERROR_CODES.get(body.code) : void 0;
    if (known !== void 0) throw new PluginError(known, detail);
    throw new PluginError("parse_failure", detail);
  }
  return body.data;
}
function toTrack(item) {
  const { bvid, title, author, duration } = item;
  if (typeof bvid !== "string" || typeof title !== "string") {
    throw new PluginError("parse_failure", "search item without bvid or title");
  }
  return {
    id: bvid,
    title: plainText(title),
    author: typeof author === "string" ? author : "",
    durationMs: parseDuration(duration)
  };
}
function plainText(html) {
  return html.replace(/<[^>]*>/g, "").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}
function parseDuration(text) {
  if (typeof text !== "string" || !/^\d+(:\d{1,2}){1,2}$/.test(text)) {
    return void 0;
  }
  const seconds = text.split(":").reduce((total, part) => total * 60 + Number(part), 0);
  return seconds * 1e3;
}
function browserCookie() {
  const hex = (n) => Array.from(
    { length: n },
    () => Math.floor(Math.random() * 16).toString(16).toUpperCase()
  ).join("");
  const uuid = `${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}`;
  const buvid3 = `${uuid}infoc`;
  const nut = Math.floor(Date.now() / 1e3);
  return `buvid3=${buvid3}; buvid4=${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}; b_nut=${nut}; _uuid=${buvid3}; buvid_fp=${buvid3}`;
}
export {
  resolveStream,
  search
};
