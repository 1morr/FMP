// bilibili/src/index.ts
var SEARCH_URL = "https://api.bilibili.com/x/web-interface/search/type";
var USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
var RISK_CONTROL_CODES = /* @__PURE__ */ new Set([-352, -412, -509, -799]);
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
  search
};
