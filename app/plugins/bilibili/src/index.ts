// Bilibili 插件。插件能力：search（brief 事實 F20、F26、F27）、resolveStream
// （事實 F1、F4、F5、F6、F21、F24）、listParts（事實 F1、F21、F27）、
// trackInfo（事實 F1）。
//
// 曲目 id 照 B 站影片頁網址的慣例（`/video/<bvid>?p=<分 P>`）：`<bvid>` 是
// 第一個分 P，`<bvid>?p=<n>` 是第 n 個分 P，n ≥ 2（GLOSSARY.md：每個分 P
// 是一首獨立的曲目）。不收 `?p=1`，一首曲目只有一個 id。

const SEARCH_URL = 'https://api.bilibili.com/x/web-interface/search/type';
const PAGELIST_URL = 'https://api.bilibili.com/x/player/pagelist';
const PLAYURL_URL = 'https://api.bilibili.com/x/player/playurl';
/**
 * 影片資訊（發佈時間、簡介、播放數等）。匿名打 `view` 會 412，`wbi/view` 不簽
 * 也回 200（事實 F1）。
 */
const VIEW_URL = 'https://api.bilibili.com/x/web-interface/wbi/view';
/** 批次查影片資訊，搜尋結果的分 P 數從這裡來（brief 事實 F27）。 */
const INFOS_URL = 'https://api.bilibili.com/x/v3/fav/resource/infos';
/** infos 的 `resources` 裡 `:2` 是資源類型「影片」。 */
const RESOURCE_TYPE_VIDEO = 2;

/** API 請求的 Referer 帶結尾斜線、加 Origin（brief 事實 F4）。 */
const API_REFERER = 'https://www.bilibili.com/';
const API_ORIGIN = 'https://www.bilibili.com';

/** playurl 的 DASH 格式；音訊軌是 m4a/AAC（brief 事實 F6）。 */
const FNVAL_DASH = '16';

const TRACK_ID = /^(BV[0-9A-Za-z]{10})(?:\?p=([2-9]|[1-9]\d+))?$/;

// curl、okhttp 這類 UA 必被風控擋（brief 事實 F2），用瀏覽器的。
const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

/**
 * 媒體 CDN：Referer 不帶結尾斜線、不帶憑證（brief 事實 F4），還要瀏覽器的
 * User-Agent：部分串流網址拒絕 ExoPlayer、AVPlayer 自己的 User-Agent，回
 * 403（事實 F22）。
 */
const MEDIA_HEADERS = {
  Referer: 'https://www.bilibili.com',
  'User-Agent': USER_AGENT,
};

/** 風控碼：要當限流退避，換 buvid 救不回來（brief 事實 F2）。 */
const RISK_CONTROL_CODES = new Set([-352, -412, -509, -799]);

/**
 * 其他已知的 API 代碼（brief 事實 F21）對到錯誤分類（brief〈錯誤、log 與診斷〉）。舊版把
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

/** 搜尋排序對到 B 站的 `order`（brief 事實 F26）。 */
const SEARCH_ORDER: Record<SearchSort, string> = {
  relevance: 'totalrank',
  viewCount: 'click',
  date: 'pubdate',
};

export async function search({
  query,
  sort,
  page = 1,
}: SearchRequest): Promise<SearchResponse> {
  const order = SEARCH_ORDER[sort ?? 'relevance'] ?? SEARCH_ORDER.relevance;
  const url =
    `${SEARCH_URL}?search_type=video&order=${order}&page=${page}` +
    `&keyword=${encodeURIComponent(query)}`;
  const res = await host.http.request({
    url,
    headers: {
      ...browserHeaders('https://search.bilibili.com/', 'https://search.bilibili.com'),
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    },
  });
  const data = parseResponse(res) as
    | { result?: unknown[]; numPages?: unknown }
    | undefined;
  const results = Array.isArray(data?.result) ? data.result : [];
  // 讀不到 numPages 時當成最後一頁，不會一直載入。
  const numPages = data?.numPages;
  const isEnd =
    results.length === 0 || typeof numPages !== 'number' || page >= numPages;
  const tracks = results.map(toTrack);
  const partCounts = await fetchPartCounts(results);
  return {
    tracks: tracks.map((t) => {
      const partCount = partCounts.get(t.id);
      return partCount === undefined ? t : { ...t, partCount };
    }),
    isEnd,
  };
}

/**
 * 這頁搜尋結果的分 P 數，bvid 對分 P 數；搜尋結果自己沒有（事實 F27），每頁
 * 一次批次請求。這個請求失敗或被限流時，搜尋照常回來、這頁沒有分 P 數：
 * 分 P 數只是附帶的資訊，不該讓搜尋跟著失敗。
 */
async function fetchPartCounts(results: unknown[]): Promise<Map<string, number>> {
  const counts = new Map<string, number>();
  const aids = results
    .map((r) => (r as { aid?: unknown }).aid)
    .filter((aid): aid is number => Number.isSafeInteger(aid) && (aid as number) > 0);
  if (aids.length === 0) return counts;
  try {
    const resources = aids.map((aid) => `${aid}:${RESOURCE_TYPE_VIDEO}`).join(',');
    const data = await apiGet(`${INFOS_URL}?resources=${resources}&platform=web`);
    if (!Array.isArray(data)) {
      throw new PluginError('parse_failure', 'infos without a list');
    }
    for (const info of data as { bvid?: unknown; page?: unknown }[]) {
      const { bvid, page } = info ?? {};
      if (typeof bvid === 'string' && Number.isSafeInteger(page) && (page as number) >= 1) {
        counts.set(bvid, page as number);
      }
    }
  } catch (e) {
    if (!(e instanceof PluginError)) throw e;
    // 宿主 API 沒有 log（host.d.ts），這裡不記；這頁就沒有分 P 數。
  }
  return counts;
}

export async function listParts({
  trackId,
}: ListPartsRequest): Promise<ListPartsResponse> {
  const match = TRACK_ID.exec(trackId);
  if (match === null) {
    throw new PluginError('not_found', `not a bilibili track id: ${trackId}`);
  }
  const bvid = match[1] as string;
  const data = await apiGet(`${PAGELIST_URL}?bvid=${bvid}`);
  if (!Array.isArray(data)) {
    throw new PluginError('parse_failure', 'pagelist without a list');
  }
  const parts = (data as { page?: unknown; part?: unknown; duration?: unknown }[])
    .map((p) => {
      const { page, part, duration } = p ?? {};
      if (typeof page !== 'number' || !Number.isSafeInteger(page) || page < 1) {
        throw new PluginError('parse_failure', 'pagelist part without a page');
      }
      return {
        page,
        part: {
          id: page === 1 ? bvid : `${bvid}?p=${page}`,
          title: typeof part === 'string' && part !== '' ? part : `P${page}`,
          durationMs:
            typeof duration === 'number' && Number.isFinite(duration) && duration >= 0
              ? Math.round(duration * 1000)
              : undefined,
          url:
            `https://www.bilibili.com/video/${bvid}` +
            (page === 1 ? '' : `?p=${page}`),
        } satisfies PluginPart,
      };
    })
    .sort((a, b) => a.page - b.page)
    .map((p) => p.part);
  return { parts };
}

export async function trackInfo({
  trackId,
}: TrackInfoRequest): Promise<TrackInfoResponse> {
  const match = TRACK_ID.exec(trackId);
  if (match === null) {
    throw new PluginError('not_found', `not a bilibili track id: ${trackId}`);
  }
  // 分 P 沒有自己的資訊，用整支影片的。
  const data = (await apiGet(`${VIEW_URL}?bvid=${match[1]}`)) as
    | { pubdate?: unknown; desc?: unknown; stat?: Record<string, unknown> }
    | undefined;
  const stat = data?.stat ?? {};
  const pubdate = count(data?.pubdate);
  // B 站沒有專輯。
  return {
    publishedAtMs: pubdate === undefined || pubdate === 0 ? undefined : pubdate * 1000,
    playCount: count(stat.view),
    likeCount: count(stat.like),
    commentCount: count(stat.reply),
    description:
      typeof data?.desc === 'string' && data.desc.trim() !== '' ? data.desc : undefined,
  };
}

/** 非負整數才算數，其他（缺、負數、字串）都當成沒給。 */
function count(value: unknown): number | undefined {
  return Number.isSafeInteger(value) && (value as number) >= 0
    ? (value as number)
    : undefined;
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
    segmentBase: audio.segmentBase,
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
  segmentBase?: { initialization: string; indexRange: string };
}

const BYTE_RANGE = /^\d+-\d+$/;

/**
 * 音訊軌的 init 與 sidx 位置（ADR 0040）：playurl 同時給 `SegmentBase`
 * （`Initialization`、`indexRange`）與 `segment_base`（`initialization`、
 * `index_range`）。讀不到或不像位元組範圍就不給，宿主照舊直接播網址。
 */
function segmentBaseOf(track: {
  SegmentBase?: unknown;
  segment_base?: unknown;
}): DashAudio['segmentBase'] {
  const camel = (track.SegmentBase ?? {}) as {
    Initialization?: unknown;
    indexRange?: unknown;
  };
  const snake = (track.segment_base ?? {}) as {
    initialization?: unknown;
    index_range?: unknown;
  };
  const initialization = camel.Initialization ?? snake.initialization;
  const indexRange = camel.indexRange ?? snake.index_range;
  if (
    typeof initialization === 'string' &&
    typeof indexRange === 'string' &&
    BYTE_RANGE.test(initialization) &&
    BYTE_RANGE.test(indexRange)
  ) {
    return { initialization, indexRange };
  }
  return undefined;
}

/** 頻寬最高的 DASH 音訊軌。 */
function bestAudio(tracks: unknown): DashAudio {
  const audios: DashAudio[] = [];
  for (const track of Array.isArray(tracks) ? tracks : []) {
    const fields = (track ?? {}) as {
      baseUrl?: unknown;
      base_url?: unknown;
      bandwidth?: unknown;
      codecs?: unknown;
      SegmentBase?: unknown;
      segment_base?: unknown;
    };
    const { baseUrl, base_url, bandwidth, codecs } = fields;
    const url = typeof baseUrl === 'string' ? baseUrl : base_url;
    if (typeof url === 'string' && url !== '' && typeof bandwidth === 'number') {
      audios.push({
        url,
        bandwidth,
        codec: typeof codecs === 'string' ? codecs : undefined,
        segmentBase: segmentBaseOf(fields),
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
    headers: browserHeaders(API_REFERER, API_ORIGIN),
  });
  return parseResponse(res);
}

/** API 請求共用的瀏覽器 header（brief 事實 F2、F4、F20）。 */
function browserHeaders(referer: string, origin: string): Record<string, string> {
  return {
    'User-Agent': USER_AGENT,
    Referer: referer,
    Origin: origin,
    Accept: 'application/json, text/plain, */*',
    Cookie: COOKIE,
  };
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
  pic: string;
  play: unknown;
}

function toTrack(item: unknown): PluginTrack {
  const { bvid, title, author, duration, pic, play } = item as SearchItem;
  if (typeof bvid !== 'string' || typeof title !== 'string') {
    throw new PluginError('parse_failure', 'search item without bvid or title');
  }
  return {
    id: bvid,
    title: plainText(title),
    author: typeof author === 'string' ? author : '',
    durationMs: parseDuration(duration),
    coverUrl: coverUrl(pic),
    coverLargeUrl: coverUrl(pic, '@720w_720h_1c.webp'),
    playCount:
      typeof play === 'number' && Number.isFinite(play) && play >= 0
        ? Math.round(play)
        : undefined,
    url: `https://www.bilibili.com/video/${bvid}`,
  };
}

/**
 * 清單用的縮圖：搜尋結果的 `pic` 是 `//host/…` 或 `http://…` 的原圖（平均約
 * 450 KB），一律改成 https（iOS 擋明文 http），再加 B 站圖床的縮圖參數，裁成
 * 160 方形 webp（約 2 KB），3x 螢幕上 40–52 點的封面夠用（事實 F23）。
 * 播放頁的大封面用同一張原圖加 `@720w_720h_1c.webp`（約 30–40 KB）。
 */
function coverUrl(
  pic: unknown,
  size = '@160w_160h_1c.webp',
): string | undefined {
  if (typeof pic !== 'string') return undefined;
  const match = /^(?:https?:)?\/\/(.+)$/.exec(pic);
  return match ? `https://${match[1]}${size}` : undefined;
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
