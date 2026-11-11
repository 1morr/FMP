// 宿主給插件的 API（ADR 0038）。插件跑在 fjs 引擎裡，只有這些全域與 ES2023
// 內建：沒有 fetch、require、檔案系統與 socket（app/lib/plugins/src/js_engine.dart）。
// 改這裡要同時改 Dart 端：錯誤代碼對照 plugin_error.dart，宿主 API 對照
// js_engine.dart 的 prelude，插件能力的參數與回傳值對照 plugin_host.dart。

/** 插件回報錯誤用的固定代碼，宿主轉成錯誤分類（brief §13）。 */
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
}

/** 插件能力 search。 */
interface SearchRequest {
  query: string;
}

interface SearchResponse {
  tracks: PluginTrack[];
}
