// bilibili/src/index.ts
var SEARCH_URL = "https://api.bilibili.com/x/web-interface/search/type";
var PAGELIST_URL = "https://api.bilibili.com/x/player/pagelist";
var PLAYURL_URL = "https://api.bilibili.com/x/player/playurl";
var VIEW_URL = "https://api.bilibili.com/x/web-interface/wbi/view";
var INFOS_URL = "https://api.bilibili.com/x/v3/fav/resource/infos";
var RESOURCE_TYPE_VIDEO = 2;
var API_REFERER = "https://www.bilibili.com/";
var API_ORIGIN = "https://www.bilibili.com";
var FNVAL_DASH = "16";
var TRACK_ID = /^(BV[0-9A-Za-z]{10})(?:\?p=([2-9]|[1-9]\d+))?$/;
var USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
var MEDIA_HEADERS = {
  Referer: "https://www.bilibili.com",
  "User-Agent": USER_AGENT
};
var RISK_CONTROL_CODES = /* @__PURE__ */ new Set([-352, -412, -509, -799]);
var ERROR_CODES = /* @__PURE__ */ new Map([
  [-404, "not_found"],
  [62002, "unavailable_copyright"],
  [-10403, "unavailable_region"]
]);
var COOKIE = browserCookie();
var SEARCH_ORDER = {
  relevance: "totalrank",
  viewCount: "click",
  date: "pubdate"
};
async function search({
  query,
  sort,
  page = 1
}) {
  const order = SEARCH_ORDER[sort ?? "relevance"] ?? SEARCH_ORDER.relevance;
  const url = `${SEARCH_URL}?search_type=video&order=${order}&page=${page}&keyword=${encodeURIComponent(query)}`;
  const res = await host.http.request({
    url,
    headers: {
      ...browserHeaders("https://search.bilibili.com/", "https://search.bilibili.com"),
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
    }
  });
  const data = parseResponse(res);
  const results = Array.isArray(data?.result) ? data.result : [];
  const numPages = data?.numPages;
  const isEnd = results.length === 0 || typeof numPages !== "number" || page >= numPages;
  const tracks = results.map(toTrack);
  const partCounts = await fetchPartCounts(results);
  return {
    tracks: tracks.map((t) => {
      const partCount = partCounts.get(t.id);
      return partCount === void 0 ? t : { ...t, partCount };
    }),
    isEnd
  };
}
async function fetchPartCounts(results) {
  const counts = /* @__PURE__ */ new Map();
  const aids = results.map((r) => r.aid).filter((aid) => Number.isSafeInteger(aid) && aid > 0);
  if (aids.length === 0) return counts;
  try {
    const resources = aids.map((aid) => `${aid}:${RESOURCE_TYPE_VIDEO}`).join(",");
    const data = await apiGet(`${INFOS_URL}?resources=${resources}&platform=web`);
    if (!Array.isArray(data)) {
      throw new PluginError("parse_failure", "infos without a list");
    }
    for (const info of data) {
      const { bvid, page } = info ?? {};
      if (typeof bvid === "string" && Number.isSafeInteger(page) && page >= 1) {
        counts.set(bvid, page);
      }
    }
  } catch (e) {
    if (!(e instanceof PluginError)) throw e;
  }
  return counts;
}
async function listParts({
  trackId
}) {
  const match = TRACK_ID.exec(trackId);
  if (match === null) {
    throw new PluginError("not_found", `not a bilibili track id: ${trackId}`);
  }
  const bvid = match[1];
  const data = await apiGet(`${PAGELIST_URL}?bvid=${bvid}`);
  if (!Array.isArray(data)) {
    throw new PluginError("parse_failure", "pagelist without a list");
  }
  const parts = data.map((p) => {
    const { page, part, duration } = p ?? {};
    if (typeof page !== "number" || !Number.isSafeInteger(page) || page < 1) {
      throw new PluginError("parse_failure", "pagelist part without a page");
    }
    return {
      page,
      part: {
        id: page === 1 ? bvid : `${bvid}?p=${page}`,
        title: typeof part === "string" && part !== "" ? part : `P${page}`,
        durationMs: typeof duration === "number" && Number.isFinite(duration) && duration >= 0 ? Math.round(duration * 1e3) : void 0,
        url: `https://www.bilibili.com/video/${bvid}` + (page === 1 ? "" : `?p=${page}`)
      }
    };
  }).sort((a, b) => a.page - b.page).map((p) => p.part);
  return { parts };
}
async function trackInfo({
  trackId
}) {
  const match = TRACK_ID.exec(trackId);
  if (match === null) {
    throw new PluginError("not_found", `not a bilibili track id: ${trackId}`);
  }
  const data = await apiGet(`${VIEW_URL}?bvid=${match[1]}`);
  const stat = data?.stat ?? {};
  const pubdate = count(data?.pubdate);
  return {
    publishedAtMs: pubdate === void 0 || pubdate === 0 ? void 0 : pubdate * 1e3,
    playCount: count(stat.view),
    likeCount: count(stat.like),
    commentCount: count(stat.reply),
    description: typeof data?.desc === "string" && data.desc.trim() !== "" ? data.desc : void 0
  };
}
function count(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : void 0;
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
    bitrate: audio.bandwidth,
    segmentBase: audio.segmentBase
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
var BYTE_RANGE = /^\d+-\d+$/;
function segmentBaseOf(track) {
  const camel = track.SegmentBase ?? {};
  const snake = track.segment_base ?? {};
  const initialization = camel.Initialization ?? snake.initialization;
  const indexRange = camel.indexRange ?? snake.index_range;
  if (typeof initialization === "string" && typeof indexRange === "string" && BYTE_RANGE.test(initialization) && BYTE_RANGE.test(indexRange)) {
    return { initialization, indexRange };
  }
  return void 0;
}
function bestAudio(tracks) {
  const audios = [];
  for (const track of Array.isArray(tracks) ? tracks : []) {
    const fields = track ?? {};
    const { baseUrl, base_url, bandwidth, codecs } = fields;
    const url = typeof baseUrl === "string" ? baseUrl : base_url;
    if (typeof url === "string" && url !== "" && typeof bandwidth === "number") {
      audios.push({
        url,
        bandwidth,
        codec: typeof codecs === "string" ? codecs : void 0,
        segmentBase: segmentBaseOf(fields)
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
    headers: browserHeaders(API_REFERER, API_ORIGIN)
  });
  return parseResponse(res);
}
function browserHeaders(referer, origin) {
  return {
    "User-Agent": USER_AGENT,
    Referer: referer,
    Origin: origin,
    Accept: "application/json, text/plain, */*",
    Cookie: COOKIE
  };
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
  const { bvid, title, author, duration, pic, play } = item;
  if (typeof bvid !== "string" || typeof title !== "string") {
    throw new PluginError("parse_failure", "search item without bvid or title");
  }
  return {
    id: bvid,
    title: plainText(title),
    author: typeof author === "string" ? author : "",
    durationMs: parseDuration(duration),
    coverUrl: coverUrl(pic),
    coverLargeUrl: coverUrl(pic, "@720w_720h_1c.webp"),
    playCount: typeof play === "number" && Number.isFinite(play) && play >= 0 ? Math.round(play) : void 0,
    url: `https://www.bilibili.com/video/${bvid}`
  };
}
function coverUrl(pic, size = "@160w_160h_1c.webp") {
  if (typeof pic !== "string") return void 0;
  const match = /^(?:https?:)?\/\/(.+)$/.exec(pic);
  return match ? `https://${match[1]}${size}` : void 0;
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
  listParts,
  resolveStream,
  search,
  trackInfo
};
