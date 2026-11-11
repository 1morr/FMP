// Bilibili 插件。目前的插件能力：search（brief 事實 F20）。

const SEARCH_URL = 'https://api.bilibili.com/x/web-interface/search/type';

// curl、okhttp 這類 UA 必被風控擋（brief 事實 F2），用瀏覽器的。
const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

/** 風控碼：要當限流退避，換 buvid 救不回來（brief 事實 F2）。 */
const RISK_CONTROL_CODES = new Set([-352, -412, -509, -799]);

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
