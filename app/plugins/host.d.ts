// 宿主給插件的 API（ADR 0038）。插件跑在 fjs 引擎裡，只有這些全域與 ES2023
// 內建：沒有 fetch、require、檔案系統與 socket（app/lib/plugins/src/js_engine.dart）。
// 改這裡要同時改 Dart 端：錯誤代碼對照 plugin_error.dart，宿主 API 對照
// js_engine.dart 的 prelude，插件能力的參數與回傳值對照 plugin_host.dart。

/** 插件回報錯誤用的固定代碼，宿主轉成錯誤分類（brief〈錯誤、log 與診斷〉）。 */
type PluginErrorCode =
  | 'network'
  | 'rate_limited'
  | 'login_required'
  | 'credential_invalid'
  | 'verification_required'
  | 'unavailable_region'
  | 'unavailable_copyright'
  | 'unavailable_membership_required'
  | 'unavailable_trial_only'
  | 'not_found'
  | 'parse_failure'
  | 'unsupported';

/**
 * 插件丟這個錯誤回報失敗。宿主自己的失敗也以它交給插件：連不上、逾時是
 * `network`；連 manifest 沒宣告的網域是 `domain_not_allowed`。
 */
declare class PluginError extends Error {
  constructor(code: PluginErrorCode, message?: string);
  readonly code: PluginErrorCode | 'domain_not_allowed';
}

interface HostHttpRequest {
  /** 只收 https，主機要在 manifest 的 domains 裡；轉址由宿主跟，同樣檢查。 */
  url: string;
  headers?: Record<string, string>;
}

interface HostHttpResponse {
  /** 任何狀態碼都照實交回，由插件判斷。 */
  status: number;
  body: string;
}

declare const host: {
  readonly http: {
    /** GET。連不上、逾時時丟 PluginError('network')。 */
    request(req: HostHttpRequest): Promise<HostHttpResponse>;
  };
};

/** 曲目（GLOSSARY.md）。id 的格式由插件決定，宿主不解讀。 */
interface PluginTrack {
  id: string;
  title: string;
  /** 歌手或上傳者。 */
  author: string;
  durationMs?: number;
  /** 封面圖的 http(s) 網址；宿主不經網路層直接載入（ARCHITECTURE〈快取〉）。 */
  coverUrl?: string;
  /** 播放數，非負整數；不知道就不給。給了不合格的值，整次搜尋算解析失敗。 */
  playCount?: number;
  /**
   * 曲目在音源網站上的頁面，http(s) 的絕對網址；有網址才出現「複製連結」與
   * 「在瀏覽器開啟」。給了不合格的值，整次搜尋算解析失敗。
   */
  url?: string;
}

/**
 * 搜尋的排序（ADR 0039），名字照 YouTube Data API search.list 的 `order`：
 * 綜合排序、最多播放、最新發布。
 */
type SearchSort = 'relevance' | 'viewCount' | 'date';

/** 插件能力 search。 */
interface SearchRequest {
  query: string;
  /**
   * 排序。宿主只傳 manifest 的 `searchSorts` 宣告過的值；沒給就用插件自己的
   * 預設（`searchSorts` 的第一個）。
   */
  sort?: SearchSort;
  /** 第幾頁，從 1 起；宿主一律會給，沒給當成 1。 */
  page?: number;
}

interface SearchResponse {
  tracks: PluginTrack[];
  /**
   * true 表示沒有下一頁（照 MusicFree 插件搜尋的 `isEnd`）。沒給當成 true，
   * 不分頁的插件不會被一直載入；給了不是 boolean，整次搜尋算解析失敗。
   */
  isEnd?: boolean;
}

/** 插件能力 resolveStream：把一首曲目解析成串流（GLOSSARY.md）。 */
interface ResolveStreamRequest {
  /** 搜尋等插件能力回傳的 PluginTrack.id。 */
  trackId: string;
}

/** 串流。欄位命名參考 Spotube 插件的音訊來源（url、codec、bitrate）。 */
interface ResolveStreamResponse {
  /** http(s) 的絕對網址，可以直接播放。 */
  url: string;
  /** 播放時請求 url 要帶的 header。 */
  headers?: Record<string, string>;
  /** 網址失效的時間（unix 毫秒）；不知道就不給。 */
  expiresAtMs?: number;
  /** RFC 6381 的 codec 字串，例如 AAC-LC 的 'mp4a.40.2'。 */
  codec?: string;
  /** 位元率（bit/s）。 */
  bitrate?: number;
  /**
   * 串流是單檔 fragmented MP4 時，init（ftyp、moov）與 sidx 的位置：含頭尾的
   * 位元組範圍 '<first>-<last>'，命名照 MPEG-DASH 的 SegmentBase（ADR 0040）。
   * 不知道就不給；給了格式不對，整次解析算失敗。
   */
  segmentBase?: { initialization: string; indexRange: string };
}
