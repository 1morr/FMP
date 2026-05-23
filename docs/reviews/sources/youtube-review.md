# YouTube Source Review

## Findings

1. **[High] `youtube_explode_dart` 的非 `SourceApiException` 串流錯誤會被降級成 `no_stream`，破壞 non-fallbackable error kind 合約。**
   證據位置：`lib/data/sources/youtube_source.dart:414`、`lib/data/sources/youtube_source.dart:456`、`lib/data/sources/youtube_source.dart:505`、`lib/data/sources/youtube_source.dart:364`、`lib/data/sources/youtube_source.dart:2122`。
   `_tryGetAudioOnlyStream`、`_tryGetMuxedStream`、`_tryGetHlsStream` 都 catch 任意錯誤；`_shouldAbortStreamFallback()` 對非 `SourceApiException` 只把疑似 rate limit 視為 abort，其餘錯誤會被記錄後繼續試下一種 stream，最後可能在 `getAudioStream()` 以 `no_stream` 丟出 `YouTubeApiException`。這會把 `youtube_explode_dart` manifest/HTTP 路徑上的 network、timeout、permission、geo 類錯誤吞掉，違反 shared contract 要保留 non-fallbackable `SourceErrorKind` 的要求。

2. **[Medium] InnerTube playability 只用 `status.toLowerCase()` 產生 code，YouTubeSource 目前沒有任何路徑會產生 `geo_restricted`。**
   證據位置：`lib/data/sources/youtube_source.dart:64`、`lib/data/sources/youtube_source.dart:68`、`lib/data/sources/youtube_source.dart:70`、`lib/data/sources/youtube_exception.dart:20`、`lib/data/sources/youtube_exception.dart:34`。
   `YouTubeApiException` 已定義 `geo_restricted -> SourceErrorKind.geoRestricted`，但 `YouTubeSource` 的 playability 檢查只把 InnerTube `playabilityStatus.status` lower-case 後直接作為 code，沒有檢查 `reason` 或其他 playability 欄位。因此只要 YouTube 用一般 `UNPLAYABLE` status 搭配地區限制 reason，程式會得到 `unplayable`/`unavailable`，而不是 `geoRestricted`，播放層就可能走錯 skip/toast/fallback 語義。

3. **[Medium] 播放 handoff 的 lower-quality fallback 可能重新選回剛失敗的 URL。**
   證據位置：`lib/services/audio/internal/audio_stream_delegate.dart:128`、`lib/services/audio/internal/audio_stream_delegate.dart:133`、`lib/services/audio/internal/audio_stream_delegate.dart:141`、`lib/services/audio/internal/audio_stream_delegate.dart:152`、`lib/data/sources/youtube_source.dart:658`、`lib/data/sources/youtube_source.dart:697`、`lib/data/sources/youtube_source.dart:1715`。
   YouTubeSource 的 alternative 選流本身會排除 `failedUrl`，包含 youtube_explode audio-only/muxed 與 InnerTube audio-only/muxed/HLS。但 `AudioStreamDelegate.getAlternativeAudioStream()` 在每個 lower-quality level 先呼叫 `source.getAlternativeAudioStream(... failedUrl ...)`，若回傳 `null`，接著直接呼叫 `source.getAudioStream(...)`，這條路徑沒有 `failedUrl` 參數。若 YouTube 在不同品質設定下仍只解析到同一個 media URL，fallback handoff 會把剛被 backend 拒絕的 URL 再交給播放器。

## Evidence

- YouTube direct source 確實同時使用 `youtube_explode_dart` 與 InnerTube：`lib/data/sources/youtube_source.dart:5` 匯入 `youtube_explode_dart`，`lib/data/sources/youtube_source.dart:23` 定義 InnerTube base URL，`lib/data/sources/youtube_source.dart:93` 呼叫 `/player`。
- audio-only 的 youtube_explode 路徑使用 `YoutubeApiClient.androidVr`：`lib/data/sources/youtube_source.dart:393` 到 `lib/data/sources/youtube_source.dart:396`；alternative audio-only 也一樣在 `lib/data/sources/youtube_source.dart:651` 到 `lib/data/sources/youtube_source.dart:654`。
- stream priority 與 format priority 有照設定走：`lib/data/sources/youtube_source.dart:333` 到 `lib/data/sources/youtube_source.dart:336` 依 `config.streamPriority` 嘗試，`lib/data/sources/youtube_source.dart:525` 到 `lib/data/sources/youtube_source.dart:529` 依 `config.formatPriority` 選 audio-only，InnerTube fallback 在 `lib/data/sources/youtube_source.dart:1653` 到 `lib/data/sources/youtube_source.dart:1663` 依 stream priority 選流。
- 現有測試已覆蓋幾個重要 YouTube 合約：`test/data/sources/youtube_source_test.dart:42` 驗證 InnerTube fallback 尊重 stream priority；`test/data/sources/youtube_source_test.dart:92` 驗證 format priority；`test/data/sources/youtube_source_test.dart:143` 驗證 authenticated alternative 會跳過 failed InnerTube URL；`test/data/sources/youtube_source_test.dart:193` 驗證 alternative fallback 保留 login-required。
- auth-for-play 有正確傳到播放與下載解析：`lib/services/audio/internal/audio_stream_delegate.dart:69` 到 `lib/services/audio/internal/audio_stream_delegate.dart:79` 讀 settings 並傳 auth headers；`lib/services/download/download_service.dart:699` 到 `lib/services/download/download_service.dart:711` 下載解析也走相同設定。
- playback/download media headers 是 source-aware，且 YouTube 不轉發 Cookie/Authorization 到 CDN/media 請求：`lib/data/sources/source_http_policy.dart:42` 到 `lib/data/sources/source_http_policy.dart:46` 定義 YouTube media headers；`lib/data/sources/source_http_policy.dart:54` 只允許 Netease 合併 auth headers；測試在 `test/services/download/download_media_headers_test.dart:21` 與 `test/services/download/download_media_headers_test.dart:54` 覆蓋 YouTube auth 不外洩。
- YouTube Mix/Radio 使用 RD playlist ID 與 InnerTube `/next`：`lib/data/sources/youtube_source.dart:902` 判斷 RD prefix，`lib/data/sources/youtube_source.dart:977` 到 `lib/data/sources/youtube_source.dart:992` 呼叫 `/next`。

## Source-specific reason if applicable

- Finding 1 是 YouTube-specific 的原因是 YouTubeSource 主要依賴 `youtube_explode_dart` 取得 manifest；該外部 library 的錯誤不會天然是本專案的 `SourceApiException`。所以不能只用 `SourceApiException.kind` 判斷是否可 fallback，至少要把 Dio/Socket/timeout/HTTP 類錯誤轉成 YouTubeApiException 後再進入 shared contract。
- Finding 2 是 YouTube-specific 的原因是 InnerTube `playabilityStatus` 的 `status` 與 `reason` 才是 YouTube 的可播放語義來源。Netease/Bilibili 有平台數字 code；YouTube 不能只靠通用 HTTP code 或 status 字串保留 login/geo/unavailable 的差異。
- Finding 3 是 shared fallback 的問題，但對 YouTube 特別敏感，因為 audio-only URL 容易因 client/CDN/403 失敗，且 YouTube 的 stream priority 允許 audio-only、muxed、HLS 互相 handoff。保留 failed URL exclusion 是 YouTube fallback 正確性的核心要求。

## Suggested direction

- 在 YouTubeSource 的 stream manifest catch 內，對非 `SourceApiException` 做明確分類：Dio/HTTP 429、403、404、timeout、connection error、SocketException、TimeoutException 等應轉成 `YouTubeApiException` 並保留 `SourceErrorKind`；只有真正的「該 stream type 無可用格式」才允許繼續嘗試下一種 stream。
- 擴充 `_checkPlayability()`：把 `LOGIN_REQUIRED`、`AGE_RESTRICTED`、常見 age/login reason、private/permission、geo/country/region reason 分類成既有 code；沒有足夠信號時才落到 `unplayable`。
- 調整 `AudioStreamDelegate.getAlternativeAudioStream()` 的 lower-quality fallback：如果 `failedUrl` 存在，不應在同一輪直接呼叫沒有 exclusion 能力的 `source.getAudioStream()`，或需要在 `BaseSource` 合約新增可選 failed URL exclusion，避免重試同一 URL。
- 補測試：加入 YouTubeSource 對非 `SourceApiException` network/timeout/403 manifest error 不得變成 `no_stream` 的測試；加入 InnerTube playability geo/login reason 分類測試；加入 handoff fallback 在 lower-quality `getAlternativeAudioStream()` 回傳 null 時不得重選 failed URL 的回歸測試。

## Instruction docs accuracy notes

- `lib/data/sources/AGENTS.md` 對 YouTube 的核心規範大致準確：androidVr audio-only、stream priority、format priority、authenticated InnerTube fallback、failed URL exclusion、fallbackable kind 範圍，都能在程式或測試中找到對應驗證點。
- 需要修正文檔或註解的一處不一致：`lib/data/sources/youtube_source.dart:1633` 的註解說「認證路徑，androidVr 客戶端」，但實作在 `lib/data/sources/youtube_source.dart:1642` 到 `lib/data/sources/youtube_source.dart:1645` 明確說認證 fallback 使用 WEB client，原因是 ANDROID_VR 搭配 web cookies 會 client/auth mismatch。這不是本次 finding，但註解會誤導後續審查。
- `docs/development.md` 與 README 對 YouTube「視頻音頻、播放列表、Mix/Radio、Opus/AAC」的描述可由程式驗證；我沒有把這些描述直接當作事實，而是用 `youtube_source.dart`、settings model、audio/download service 與測試逐項對照。
