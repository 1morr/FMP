// Bilibili 插件。插件能力：search（brief 事實 F20）、resolveStream（事實
// F1、F4、F5、F6、F21）。
//
// 曲目 id 照 B 站影片頁網址的慣例（`/video/<bvid>?p=<分 P>`）：`<bvid>` 是
// 第一個分 P，`<bvid>?p=<n>` 是第 n 個分 P，n ≥ 2（GLOSSARY.md：每個分 P
// 是一首獨立的曲目）。不收 `?p=1`，一首曲目只有一個 id。

const SEARCH_URL = 'https://api.bilibili.com/x/web-interface/search/type';
const PAGELIST_URL = 'https://api.bilibili.com/x/player/pagelist';
const PLAYURL_URL = 'https://api.bilibili.com/x/player/playurl';

/** API 請求的 Referer 帶結尾斜線、加 Origin（brief 事實 F4）。 */
const API_REFERER = 'https://www.bilibili.com/';
const API_ORIGIN = 'https://www.bilibili.com';

/** 媒體 CDN 只要 Referer，不帶結尾斜線、不帶憑證（brief 事實 F4）。 */
const MEDIA_HEADERS = { Referer: 'https://www.bilibili.com' };

/** playurl 的 DASH 格式；音訊軌是 m4a/AAC（brief 事實 F6）。 */
const FNVAL_DASH = '16';

const TRACK_ID = /^(BV[0-9A-Za-z]{10})(?:\?p=([2-9]|[1-9]\d+))?$/;

// curl、okhttp 這類 UA 必被風控擋（brief 事實 F2），用瀏覽器的。
const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

/** 風控碼：要當限流退避，換 buvid 救不回來（brief 事實 F2）。 */
const RISK_CONTROL_CODES = new Set([-352, -412, -509, -799]);

/**
 * 其他已知的 API 代碼（brief 事實 F21）對到錯誤分類（brief §13）。舊版把
 * `-404` 歸不可用；它是「啥都木有」、稿件不存在，這裡歸找不到。`62002`
 * （稿件不可見）歸下架。舊版的「沒有權限」（`-403`、`62012`）與 `-503` 在
 * 錯誤分類裡沒有對應的原因，不猜，和其他代碼一樣是 parse_failure。
 */
const ERROR_CODES = new Map<number, PluginErrorCode>([
  [-404, 'not_found'],
  [62002, 'unavailable_copyright'],
  [-10403, 'unavailable_region'],
]);

/** 匿名的瀏覽器指紋 cookie，引擎載入插件時產生一次（brief 事實 F20）。 */
const COOKIE = browserCookie();

export async function search({ query }: SearchRequest): Promise<SearchResponse> {
  const url =
    `${SEARCH_URL}?search_type=video&page=1` +
    `&keyword=${encodeURIComponent(query)}`;
  const res = await host.http.request({
    url,
    headers: {
      'User-Agent': USER_AGENT,
      Referer: 'https://search.bilibili.com/',
      Origin: 'https://search.bilibili.com',
      Accept: 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      Cookie: COOKIE,
    },
  });
  const data = parseResponse(res) as { result?: unknown[] } | undefined;
  const results = Array.isArray(data?.result) ? data.result : [];
  return { tracks: results.map(toTrack) };
}

export async function resolveStream({
  trackId,
}: ResolveStreamRequest): Promise<ResolveStreamResponse> {
  const match = TRACK_ID.exec(trackId);
  if (match === null) {
    throw new PluginError('not_found', `not a bilibili track id: ${trackId}`);
  }
  const bvid = match[1] as string;
  const page = Number(match[2] ?? '1');
  const cid = await partCid(bvid, page);
  const data = (await apiGet(
    `${PLAYURL_URL}?bvid=${bvid}&cid=${cid}&fnval=${FNVAL_DASH}`,
  )) as { dash?: { audio?: unknown } } | undefined;
  const audio = bestAudio(data?.dash?.audio);
  return {
    url: audio.url,
    headers: { ...MEDIA_HEADERS },
    expiresAtMs: deadlineMs(audio.url),
    codec: audio.codec,
    bitrate: audio.bandwidth,
  };
}

/** 第 [page] 個分 P 的 cid；匿名查 cid 走 pagelist（brief 事實 F1）。 */
async function partCid(bvid: string, page: number): Promise<number> {
  const data = await apiGet(`${PAGELIST_URL}?bvid=${bvid}`);
  if (!Array.isArray(data)) {
    throw new PluginError('parse_failure', 'pagelist without a list');
  }
  const part = (data as { cid?: unknown; page?: unknown }[]).find(
    (p) => p?.page === page,
  );
  if (part === undefined) {
    throw new PluginError('not_found', `${bvid} has no part ${page}`);
  }
  if (typeof part.cid !== 'number') {
    throw new PluginError('parse_failure', 'pagelist part without a cid');
  }
  return part.cid;
}

interface DashAudio {
  url: string;
  bandwidth: number;
  codec?: string;
}

/** 頻寬最高的 DASH 音訊軌。 */
function bestAudio(tracks: unknown): DashAudio {
  const audios: DashAudio[] = [];
  for (const track of Array.isArray(tracks) ? tracks : []) {
    const { baseUrl, base_url, bandwidth, codecs } = (track ?? {}) as {
      baseUrl?: unknown;
      base_url?: unknown;
      bandwidth?: unknown;
      codecs?: unknown;
    };
    const url = typeof baseUrl === 'string' ? baseUrl : base_url;
    if (typeof url === 'string' && url !== '' && typeof bandwidth === 'number') {
      audios.push({
        url,
        bandwidth,
        codec: typeof codecs === 'string' ? codecs : undefined,
      });
    }
  }
  if (audios.length === 0) {
    throw new PluginError('parse_failure', 'playurl without DASH audio');
  }
  return audios.reduce((best, a) => (a.bandwidth > best.bandwidth ? a : best));
}

/** 網址的 `deadline`（unix 秒）換成毫秒；讀不到就不給（brief 事實 F5）。 */
function deadlineMs(url: string): number | undefined {
  const match = /[?&]deadline=(\d+)(?:&|#|$)/.exec(url);
  return match === null ? undefined : Number(match[1]) * 1000;
}

/** 帶瀏覽器 header 的 API 請求，回傳 `data`。 */
async function apiGet(url: string): Promise<unknown> {
  const res = await host.http.request({
    url,
    headers: {
      'User-Agent': USER_AGENT,
      Referer: API_REFERER,
      Origin: API_ORIGIN,
      Accept: 'application/json, text/plain, */*',
      Cookie: COOKIE,
    },
  });
  return parseResponse(res);
}

/** 檢查 HTTP 狀態與 B 站的 `code`，回傳 `data`。 */
function parseResponse(res: HostHttpResponse): unknown {
  if (res.status === 412 || res.status === 429) {
    throw new PluginError('rate_limited', `HTTP ${res.status}`);
  }
  if (res.status !== 200) {
    throw new PluginError('network', `HTTP ${res.status}`);
  }
  let body: { code?: unknown; message?: unknown; data?: unknown };
  try {
    body = JSON.parse(res.body);
  } catch {
    throw new PluginError('parse_failure', 'response is not JSON');
  }
  if (body.code !== 0) {
    const detail = `code ${String(body.code)}: ${String(body.message)}`;
    if (typeof body.code === 'number' && RISK_CONTROL_CODES.has(body.code)) {
      throw new PluginError('rate_limited', detail);
    }
    const known =
      typeof body.code === 'number' ? ERROR_CODES.get(body.code) : undefined;
    if (known !== undefined) throw new PluginError(known, detail);
    throw new PluginError('parse_failure', detail);
  }
  return body.data;
}

interface SearchItem {
  bvid: string;
  title: string;
  author: string;
  duration: string;
}

function toTrack(item: unknown): PluginTrack {
  const { bvid, title, author, duration } = item as SearchItem;
  if (typeof bvid !== 'string' || typeof title !== 'string') {
    throw new PluginError('parse_failure', 'search item without bvid or title');
  }
  return {
    id: bvid,
    title: plainText(title),
    author: typeof author === 'string' ? author : '',
    durationMs: parseDuration(duration),
  };
}

/** 標題裡標關鍵字的 `<em class="keyword">` 與 HTML 實體。 */
function plainText(html: string): string {
  return html
    .replace(/<[^>]*>/g, '')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');
}

/** `m:ss` 或 `h:mm:ss`；認不得時不給時長。 */
function parseDuration(text: unknown): number | undefined {
  if (typeof text !== 'string' || !/^\d+(:\d{1,2}){1,2}$/.test(text)) {
    return undefined;
  }
  const seconds = text
    .split(':')
    .reduce((total, part) => total * 60 + Number(part), 0);
  return seconds * 1000;
}

function browserCookie(): string {
  const hex = (n: number) =>
    Array.from({ length: n }, () =>
      Math.floor(Math.random() * 16).toString(16).toUpperCase(),
    ).join('');
  const uuid = `${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}`;
  const buvid3 = `${uuid}infoc`;
  const nut = Math.floor(Date.now() / 1000);
  return (
    `buvid3=${buvid3}; buvid4=${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}; ` +
    `b_nut=${nut}; _uuid=${buvid3}; buvid_fp=${buvid3}`
  );
}
