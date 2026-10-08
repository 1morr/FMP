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
// `hostApiShapes`，契約檢查的格式對契約執行器的 `checkShapes`、`fixtureShapes`
// （app/test/plugins/contract/），FmpHost 對 `js_prelude.dart` 實際建出的 `fmp`
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
  /** 一句描述，最多 200 字元；沒寫等於空字串。 */
  description?: string | null;
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
  /**
   * 平台能播的格式；依它挑候選。順序已依使用者的格式偏好排過（例如 Opus
   * 優先時 opus 在 aac 前面）：同一首有多種格式時，依這個順序排候選。
   */
  formats: StreamFormat[];
  /**
   * 使用者的音質偏好。依它挑串流（例如同一首有多個碼率時：high 最高、low
   * 最低、medium 居中），其他的排在後面當備援。沒給時自行決定（舊的宿主不送）。
   */
  quality?: FmpAudioQuality | null;
}

export type FmpAudioQuality = 'high' | 'medium' | 'low';

export interface StreamFormat {
  container: string;
  codec: string;
}

export interface StreamResult {
  /** 依優先序；至少一個，找不到就拋 NotFound 或 Unavailable。 */
  candidates: StreamCandidate[];
  /**
   * 候選只有試聽片段（例如非會員）時為 true。宿主依使用者的「跳過試聽片段」
   * 設定跳過，或照播並標「試聽」。完全沒有可播的串流時改拋
   * `{ fmpError: 'Unavailable', reason: 'previewOnly' }`。
   */
  previewOnly?: boolean | null;
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
  /**
   * 只在宿主判定要帶憑證時才加上的 header（例如從 cookie 算出來的 `Authorization: SAPISIDHASH …`）；
   * 未登入、開關關閉、已失效或 auth 為 never 時整個丟掉。名稱一律進遮蔽名單。
   */
  authHeaders?: Record<string, string> | null;
  /** 空＝依方法（只有冪等方法重試）；true 讓語意冪等的 POST 也重試，false 一律不重試。 */
  idempotent?: boolean | null;
}

export interface HttpResponse {
  status: number;
  /** 跟隨轉址後的網址。 */
  url: string;
  /** 名稱小寫。 */
  headers: Record<string, string[]>;
  /** 以 UTF-8 解碼（不合法的位元組換成 U+FFFD）。 */
  body: string;
  /**
   * 這次請求有沒有真的帶憑證。「憑證無效」的判定（401 等）只在它為 true 的回應上成立：
   * 沒帶憑證的 401 是匿名請求被拒，不是憑證失效。
   */
  credentialsAttached?: boolean;
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

/** 登入憑證的形狀（ADR 0029 §決定 3）。值是秘密：不要寫進 log 或 storage。 */
export interface FmpLoginCredentials {
  /** cookie 名稱對值。 */
  cookies: Record<string, string>;
  /** 不是 cookie 的東西（例如刷新用的 refresh_token）。 */
  extra?: Record<string, string> | null;
}

export interface FmpCredentials {
  /** 這個插件自己的登入憑證；沒登入、暫時讀不到或已失效時為 null。 */
  get(): Promise<FmpLoginCredentials | null>;
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

// ---------------------------------------------------------------- 契約檢查
//
// 插件目錄（插件庫的一個插件、app/test/fixtures/plugins/ 的測試插件）：
//
//   <目錄>/<名稱>.js                  安裝檔，只能有一個
//   <目錄>/checks.json                FmpChecks
//   <目錄>/fixtures/<能力>/<序號>.json FmpFixture，依檔名排序就是請求的順序
//
// 契約執行器以 fixture 重播每條案例，檢查能力與匯出一致、回傳值通過 DTO 驗證、
// 案例的期望、錯誤類別、只連 allowedHosts、串流 headers 不帶憑證、log 與
// fixture 都遮蔽過。錄製模式真的連網跑同一份 checks.json，遮蔽後寫出
// fixture（只限不需要登入的案例）。指令見 app/AGENTS.md § 驗證。

/** checks.json：每個能力最多一條案例，鍵就是能力名稱。目前能寫案例的只有這兩個。 */
export interface FmpChecks {
  search?: FmpSearchCheck | null;
  resolveStream?: FmpResolveStreamCheck | null;
}

export interface FmpSearchCheck {
  input: SearchQuery;
  expect: FmpExpectSuccess | FmpExpectError;
}

export interface FmpResolveStreamCheck {
  input: StreamRequest;
  expect: FmpExpectSuccess | FmpExpectError;
  /**
   * 網址裡的期限：一個正規式，剛好一個擷取群組，擷取 unix 秒（例如 JSON 裡寫
   * `"[?&]deadline=(\\d+)"`）。給了就逐一核對候選：網址對得上的，`expiresAt`
   * 必須等於擷取到的時間；至少要有一個候選對得上。只能配成功的 expect。
   * 網址沒有期限參數的音源不寫。
   */
  expiresAtPattern?: string | null;
}

/** 成功；回傳的清單（search 的 items、resolveStream 的 candidates）符合條件。 */
export interface FmpExpectSuccess {
  /** 至少幾筆，預設 0。 */
  minItems?: number | null;
  /**
   * 每一筆都要有值的欄位，名稱同 TrackSummary／StreamCandidate：不是 null、
   * 空白字串、空陣列或空物件。
   */
  nonEmpty?: string[] | null;
}

/** 以這個錯誤失敗。 */
export interface FmpExpectError {
  error: FmpErrorName;
  /** 只有 Unavailable 能給。 */
  reason?: FmpUnavailableReason | null;
}

/**
 * 一次請求與它的回應，一個檔案。欄位名稱沿用 WireMock 的 stub mapping。
 * 錄製時寫檔前一律經宿主的遮蔽函式；手寫的也必須是遮過的樣子（值換成 `***`），
 * 否則契約檢查失敗。
 */
export interface FmpFixture {
  meta: FmpFixtureMeta;
  request: FmpFixtureRequest;
  response: FmpFixtureResponse;
}

export interface FmpFixtureMeta {
  /** 錄製時間（ISO 8601，UTC）；手寫的沒有。 */
  recordedAt?: string | null;
  /** 手寫或手改的理由（例如錯誤案例）。有它的案例，錄製模式不覆蓋。 */
  edited?: string | null;
}

export interface FmpFixtureRequest {
  /** 與實際請求比對。 */
  method: string;
  /**
   * 與實際請求比對（實際的網址先經同一個遮蔽函式）：scheme、host、port、路徑
   * 與 query，query 不分順序；值是 `***` 的 query 參數與路徑段不比對值。
   */
  url: string;
  /** 只供閱讀，不比對。名稱小寫。 */
  headers?: Record<string, string> | null;
  /** 只供閱讀，不比對。 */
  body?: string | null;
}

export interface FmpFixtureResponse {
  status: number;
  /** 名稱小寫。錄製時不留 content-length、content-encoding、transfer-encoding。 */
  headers?: Record<string, string[]> | null;
  /** 文字 body；與 jsonBody 最多給一個。 */
  body?: string | null;
  /** JSON 物件或陣列的 body，重播時編碼成緊湊的 JSON 文字。 */
  jsonBody?: unknown;
}

declare global {
  const fmp: FmpHost;
}
