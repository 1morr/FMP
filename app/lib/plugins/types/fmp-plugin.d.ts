// FMP 插件的型別定義，apiVersion 1（ADR 0014 §決定 5）。
//
// 插件是一個 .js 檔：開頭以 `/* ==FMP Plugin==` 與 `==/FMP Plugin== */` 包一段
// JSON manifest（FmpPluginManifest），之後是 ES2020 module，每個宣告的能力匯出
// 一個同名函式。宿主 API 在全域的 `fmp`（FmpHost）；`console` 轉到 `fmp.log`。
// 沒有 fetch、setTimeout、檔案系統，也碰不到其他插件的資料。
//
// 物件的欄位是封閉的：多出不認得的欄位，宿主整個拒收（ParseError）。選填欄位
// 可以省略或給 null。
//
// 與宿主的 Dart 端一致：interface 的欄位對 `manifestShapes`、`sourceDtoShapes`、
// `hostApiShapes`，FmpHost 對 `js_prelude.dart` 實際建出的 `fmp`
// （app/test/plugins/type_definitions_test.dart 比對）。

// ---------------------------------------------------------------- manifest

export type FmpCapability =
  | 'search'
  | 'resolveStream'
  | 'trackDetail'
  | 'multiPart'
  | 'importPlaylist'
  | 'libraryRead'
  | 'libraryWrite'
  | 'charts'
  | 'live'
  | 'mix'
  | 'lyrics'
  | 'login';

export interface FmpPluginManifest {
  /** 1–32 個小寫英數與 `-`，不以 `-` 開頭或結尾。 */
  id: string;
  name: string;
  version: string;
  author: string;
  /** 必須等於宿主支援的版本。 */
  apiVersion: 1;
  /** 不能是空的；每個能力要有同名的匯出函式，反之亦然。 */
  capabilities: FmpCapability[];
  /**
   * 可以連的網域：只有小寫 host，涵蓋子網域。請求、串流與封面網址、圖示都
   * 只能在這些網域。
   */
  allowedHosts: string[];
  /** M1 沒有登入，只能省略或 null。 */
  login?: null;
  retry?: FmpRetryPolicy | null;
  rateLimit?: FmpRateLimitPolicy | null;
  /** 追加到宿主的遮蔽名單（只增不減）。 */
  redaction?: FmpRedaction | null;
  defaults?: Record<string, unknown> | null;
  /** `https` 網址（網域在 allowedHosts）或 `data:image/…;base64,`（≤ 64 KiB）。 */
  icon?: string | null;
}

export interface FmpRetryPolicy {
  /** 0–5，預設 2。 */
  maxRetries?: number | null;
  baseDelayMs?: number | null;
  maxDelayMs?: number | null;
  /** 伺服器的 Retry-After 超過它就不重試。 */
  maxRetryAfterMs?: number | null;
}

export interface FmpRateLimitPolicy {
  /** 至少 1。 */
  maxConcurrentRequests: number;
  minRequestIntervalMs: number;
}

export interface FmpRedaction {
  headerNames?: string[] | null;
  keyNames?: string[] | null;
  mediaCdns?: FmpMediaCdn[] | null;
}

export interface FmpMediaCdn {
  host: string;
  signedQueryParameters?: string[] | null;
  signedPath?: boolean | null;
}

// ---------------------------------------------------------------- DTO

export interface SearchQuery {
  keyword: string;
  /** 從 1 開始。 */
  page: number;
}

export interface SearchPage {
  items: TrackSummary[];
  hasMore: boolean;
}

export interface TrackSummary {
  /** 音源內的 id，不能含 `:`。曲目鍵的第一段（音源）由宿主填成插件 id。 */
  sourceId: string;
  /** 分 P 的 cid（非負整數）。 */
  cid?: number | null;
  title: string;
  uploader?: string | null;
  /** 非負整數毫秒。 */
  durationMs?: number | null;
  artwork?: Artwork[] | null;
}

export interface Artwork {
  /** `https`，網域在 allowedHosts。 */
  url: string;
  width?: number | null;
}

export interface StreamRequest {
  sourceId: string;
  cid?: number | null;
  purpose: 'playback';
  /** 平台能播的格式；依它挑候選。 */
  formats: StreamFormat[];
}

export interface StreamFormat {
  container: string;
  codec: string;
}

export interface StreamResult {
  /** 依優先序；至少一個，找不到就拋 NotFound 或 Unavailable。 */
  candidates: StreamCandidate[];
}

export interface StreamCandidate {
  /** `https`（網域在 allowedHosts）或 App 內附的 `asset:///…`。 */
  url: string;
  headers?: Record<string, string> | null;
  container?: string | null;
  codec?: string | null;
  /** 每秒位元數。 */
  bitrate?: number | null;
  /** 網址的期限（UTC epoch 毫秒），從網址本身讀。 */
  expiresAt?: number | null;
}

// ---------------------------------------------------------------- 宿主 API

export interface HttpRequest {
  /** `https`，網域在 allowedHosts；否則拋 Unsupported，不發請求。 */
  url: string;
  /** RFC 9110 的大寫方法，預設 GET。只有冪等方法會自動重試。 */
  method?: string | null;
  headers?: Record<string, string> | null;
  body?: string | null;
  /** 帶不帶登入憑證（ADR 0012），預設 never。 */
  auth?: 'never' | 'userPreference' | 'required' | null;
}

export interface HttpResponse {
  status: number;
  /** 跟隨轉址後的網址。 */
  url: string;
  /** 名稱小寫。 */
  headers: Record<string, string[]>;
  /** 以 UTF-8 解碼（不合法的位元組換成 U+FFFD）。 */
  body: string;
}

export interface FmpHttp {
  /** 經宿主的網路層：網域檢查、重試、限流、網路紀錄。429 等錯誤以 FmpError 拋出。 */
  request(request: HttpRequest): Promise<HttpResponse>;
}

export interface FmpCrypto {
  /** 字串的 UTF-8 位元組，小寫 hex。 */
  md5(text: string): string;
  sha256(text: string): string;
}

/** 這個插件自己的 key／value；移除插件時清除。 */
export interface FmpStorage {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  delete(key: string): Promise<void>;
}

export interface FmpCredentials {
  /** 這個插件自己的登入憑證；M1 一律 null。 */
  get(): Promise<Record<string, string> | null>;
}

/** 寫進宿主的 log（經遮蔽），tag 是插件 id。 */
export interface FmpLog {
  debug(message: unknown, fields?: Record<string, unknown>): void;
  info(message: unknown, fields?: Record<string, unknown>): void;
  warn(message: unknown, fields?: Record<string, unknown>): void;
  error(message: unknown, fields?: Record<string, unknown>): void;
}

export interface FmpHost {
  readonly apiVersion: 1;
  readonly http: FmpHttp;
  readonly crypto: FmpCrypto;
  readonly storage: FmpStorage;
  readonly credentials: FmpCredentials;
  readonly log: FmpLog;
}

// ---------------------------------------------------------------- 錯誤

export type FmpErrorName =
  | 'NetworkError'
  | 'RateLimited'
  | 'AuthRequired'
  | 'CredentialInvalid'
  | 'VerificationRequired'
  | 'Unavailable'
  | 'NotFound'
  | 'ParseError'
  | 'Unsupported'
  | 'UnexpectedError';

export type FmpUnavailableReason =
  | 'region'
  | 'copyright'
  | 'membership'
  | 'age'
  | 'previewOnly';

/**
 * 結構化錯誤：`throw { fmpError: 'RateLimited', retryAfterSeconds: 5 }`，
 * 或在 Error 上加這些屬性。宿主轉成同名的錯誤類別；其他拋出的值都當成插件的
 * bug（UnexpectedError）。宿主 API 拋出的錯誤也是這個形狀，原樣再拋出即可。
 * message 只進 log，使用者看到的是宿主依類別顯示的訊息。
 */
export interface FmpError {
  fmpError: FmpErrorName;
  retryAfterSeconds?: number;
  /** fmpError 為 Unavailable 時必填。 */
  reason?: FmpUnavailableReason;
  message?: string;
}

// ---------------------------------------------------------------- 匯出

/** 插件 module 的匯出：宣告了哪個能力就匯出哪個。 */
export interface FmpPluginExports {
  search?(query: SearchQuery): SearchPage | Promise<SearchPage>;
  resolveStream?(request: StreamRequest): StreamResult | Promise<StreamResult>;
}

declare global {
  const fmp: FmpHost;
}
