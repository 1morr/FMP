# 03 — 程式碼邏輯統一性（面向 B）

> 唯讀審查；證據均含 `file:line`。標 `對抗驗證` 者已覆核。成熟度評分：**3 / 5**。

## 1. 現狀摘要

- **好：** Runtime 音源層（`lib/data/sources` 三個 adapter + `SourceManager`）相當乾淨——統一走 `SourceHttpPolicy.createApiDio()`、三個 exception 一致 `extends SourceApiException` 並呼叫 `classifyDioError()`、重試延遲一致用 `AppConstants.networkRetryDelay`、UI track action 一致走 `TrackActionCoordinator`、無 `Image.network/file` 違規。
- **壞：** 一致性在「音源層之外」崩掉——歌詞/匯入/更新子系統自己 `new Dio()` 並硬編 header/timeout、歌詞源用一套不繼承 `SourceApiException` 的自有 exception、`core/errors` 有整套未接線且與 `SourceApiException` 平行的 `AppException` 體系、日誌一半 `Logging` mixin 一半 `debugPrint`。

## 2. 發現清單

### B1　歌詞/匯入/更新子系統繞過 `SourceHttpPolicy`/`HttpClientFactory`，自行 `new Dio` 並硬編 header/timeout — 對抗驗證 **confirmed，High→Medium**
- 嚴重度：🟡 Medium　工作量：M
- 證據：
  - `lib/services/lyrics/netease_source.dart:127-144`（`new Dio(BaseOptions)`，硬編 Chrome/120 UA、Referer/Origin、connect 10s/receive 15s，未走 policy）
  - `lib/services/lyrics/qqmusic_source.dart:101-117`（硬編 Firefox/115 UA + Accept，timeout 10s/15s）
  - `lib/services/lyrics/lrclib_source.dart:23-37`（硬編 baseUrl、UA=`FMP/1.0.0`、timeout 10s/15s）
  - `lib/data/sources/playlist_import/spotify_playlist_source.dart:15`（`_dio = dio ?? Dio()` 裸 new，無 timeout/UA/Referer；同目錄 `netease_playlist_source.dart:16` 卻正確用 `SourceHttpPolicy.createApiDio`，**同目錄內即不一致**）
  - `lib/data/sources/playlist_import/qq_music_playlist_source.dart:13`（同上裸 new）
- 影響：同份 UA/Referer/timeout 多處重複維護，policy 一改歌詞/匯入端不會跟改；timeout（10s/15s）與全域 `networkConnectTimeout`(10s)/`networkReceiveTimeout`(30s) 不一致，行為難以預測。驗證確認這些 provider（`lyrics_provider.dart:27/30/33`、`playlist_import_service.dart:131/132`）**未注入 Dio**，故硬編路徑在生產一定執行。
- 建議：歌詞源若屬既定 `SourceType` 一律改用 `SourceHttpPolicy.createApiDio(...)`；非音源（lrclib/spotify/QQ 匯入）至少改用 `HttpClientFactory.create(headers:..., connectTimeout:..., receiveTimeout:...)`，刪除裸 `new Dio()`。可加 lint 禁止 `lib/` 內直接 `Dio(BaseOptions())`。

### B2　歌詞子系統自有一套不繼承 `SourceApiException` 的 exception，且未用 `classifyDioError` — 對抗驗證 **confirmed，High→Medium**
- 嚴重度：🟡 Medium　工作量：L
- 證據：
  - `lib/services/lyrics/lrclib_source.dart:8-16`（`LrclibException implements Exception`，未繼承 `SourceApiException`）
  - `lib/services/lyrics/qqmusic_source.dart:86`（`QQMusicException implements Exception`）
  - `lib/services/lyrics/netease_source.dart:109`（歌詞版 `NeteaseException implements Exception`，與 `lib/data/sources/netease_exception.dart:5` 的 `NeteaseApiException` 是**兩套同名不同基底**型別）
  - `lib/services/lyrics/lrclib_source.dart:126-136`（`_handleDioError` 手寫 `switch(e.type)` 只產生英文字串，不帶 `SourceErrorKind`、不呼叫 `classifyDioError`，且在分類器內直接 `logError` 副作用）
  - `lib/services/lyrics/lyrics_auto_match_service.dart:120,190,203,349,588,653,696,739,786`（大量通用 `catch(e)` 收這些異質 exception，無法用 `isRetryable`/`shouldSkipTrack` 語義決策）
- 影響：runtime 無法對歌詞錯誤套用統一語義分類，只能一律吞成 noResult；`SourceApiException`「所有音源 API 異常統一基底」的設計承諾在歌詞子樹失效（主音源路徑仍有效，故降 Medium）。驗證確認對照組：`netease_source.dart:996`、`youtube_source.dart:2426`、`bilibili_source.dart:1022` 三個「真」音源 source 全部正確呼叫 `classifyDioError`。
- 建議：歌詞源 exception 改 `extends SourceApiException` 並實作 `sourceType`/`kind`；`_handleDioError` 改呼叫 `SourceApiException.classifyDioError(e)` 後再包成自訂類型；移除分類器內 `logError` 副作用。

### B3　`core/errors` 存在一整套未接線、與 `SourceApiException` 平行的 `AppException`/`ErrorHandler` 體系
- 嚴重度：🟡 Medium　工作量：S　[未個別驗證]
- 證據：`lib/core/errors/app_exception.dart:9-223`（`AppException`/`NetworkException`/`ServerException`/`NotFoundException`/`PermissionException`/`CancelledException` + `ErrorHandler.wrap`/`getDisplayMessage`/`log`，內含獨立 `_handleDioError` switch）；對照 `lib/data/sources/source_exception.dart:5-27,79-146`（`SourceErrorKind` + `SourceApiException.classifyDioError`，code 用小寫語義碼 `'timeout'/'not_found'/'rate_limited'`）；`app_exception.dart:113-189`（`ErrorHandler._handleDioError` 用大寫 `'TIMEOUT'/'404'/'CONNECTION_ERROR'`，與 source 體系 code 命名完全不相容）。另：`test/scenarios/offline_scenarios_test.dart:11-40` 唯一 scenario 測試只測 `ErrorHandler.wrap`。
- 影響：新人會誤以為 `ErrorHandler` 是官方途徑而重複造輪子；兩套 code 命名與分類邊界不一致（403 在 core 算 Permission、在 source 算 permissionDenied；412/429 限流語義只在 source 體系）。
- 建議：確認 `core/errors` 是否仍需要——若需要則統一 code 與 `SourceErrorKind` 對齊、讓 `ErrorHandler.wrap` 識別 `SourceApiException`；若不需要則刪除整套避免誤用。

### B4　日誌寫法不一致：一半服務用 `Logging` mixin（`logXxx`），一半直接 `debugPrint`
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/services/platform/windows_desktop_service.dart:59,109,139,188,328,425,506`（多處 `debugPrint('[WindowsDesktopService] ...')`）；`lib/services/cache/ranking_cache_service.dart:318,355,359,370,382,423,428`（直接 `debugPrint`，訊息混用中文『網絡恢復』『刷新失敗』與英文）；`lib/services/lyrics/lyrics_window_service.dart:241,248,317,338,399,414,429,519,528`（全用 `debugPrint`，與同 lyrics 子系統的 `qqmusic_source`（`with Logging`）不一致）；對照 `lib/core/logger.dart:54-237`（`AppLogger` + `Logging` mixin 提供統一介面與環形 buffer）。
- 影響：同 app 兩套日誌風格；`debugPrint` 訊息不進 `AppLogger` buffer、無 level 過濾、release 仍印；中英混雜降低可讀性。
- 建議：上述服務 `mixin Logging` 並把 `debugPrint` 換成 `logDebug/logInfo/logWarning/logError`；可加 lint 禁止 `lib/services` 內直接 `debugPrint`（`logger.dart` 自身除外）。

### B5　`duration` parser（`'3:45'`→毫秒）在三個 adapter 逐字重複，無共用 util
- 嚴重度：🟢 Low　工作量：S
- 證據：`lib/data/sources/youtube_source.dart:1213-1221` 與 `lib/data/sources/bilibili_source.dart:1066-1074`（逐字相同的 `text.split(':').map(int.parse)` + 2 段/3 段公式 + `catch(_){} return 0`；全庫無 `parseDurationToMillis`/`parseTimestamp` 共用函式）。
- 建議：抽到 `lib/core/utils` 一個 `parseColonDurationToMillis(String)`，三個 adapter 共用。

### B6　歌詞自動匹配以硬編字串 switch 分派源，三個 `_tryXxxMatch` 為 copy-paste
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/services/lyrics/lyrics_auto_match_service.dart:268-298`（`switch(source)` 字串 `'netease'/'qqmusic'/'lrclib'` 分派）；`:662,705,748`（`_tryNeteaseMatch`/`_tryQQMusicMatch`/`_tryLrclibMatch` 結構近乎相同：search→filter by duration→map to LyricsResult）；`:448,755`（另有 `_lrclib.search` 直接呼叫與 `_tryDirectFetch`，多源邏輯分散）。
- 影響：每加一個歌詞源就要新增字串 case + 一個幾乎相同的 `_tryXxxMatch`；漂移風險高、難測。
- 建議：定義 `LyricsSource` 介面（`search` 回傳統一 `LyricsResult`），netease/qqmusic/lrclib 實作後存 `List<LyricsSource>`，auto-match 改迴圈呼叫同一方法，移除字串 switch 與三份重複包裝。

### B7　`playlist_import` 自行硬編限流延遲，未沿用 `AppConstants` 重試/節流派典
- 嚴重度：🟢 Low　工作量：S
- 證據：`lib/services/import/playlist_import_service.dart:256-265`（`switch(searchSource){...1000/800/800}` + `Future.delayed(Duration(milliseconds: delay))` 硬編毫秒，未用 `AppConstants`）；對照 `lib/data/sources/bilibili_source.dart:667`（adapter 端正確用 `AppConstants.networkRetryDelay`）。
- 建議：把匯入節流延遲提升為 `AppConstants`（如 `importThrottleDelayBilibili/Youtube`）或集中 `ImportThrottleConfig`，移除硬編毫秒。

### B8　`audio_provider` 內 catch 寫法不一致：多數 `catch(e,stack)+logError`，部分 `catch(e)+logWarning` 丟失 stack
- 嚴重度：🟢 Low　工作量：S
- 證據：`lib/services/audio/audio_provider.dart:908-912`（典型 `catch(e,stack){ logError(...,e,stack); }`）；`:1698-1700,1737,1873,2826`（`catch(e){ logWarning('... $e'); }` 不帶 stack，丟失追蹤資訊）。
- 建議：非預期錯誤統一 `catch(e,stack)+logError`；明確預期小失敗（如歷史記錄）才降 `logWarning` 並加註釋說明為何丟 stack。

### B9　`searchAll` 與 `playlist_import` 的 `catch(_)` 完全靜默吞掉單源錯誤，無 log 痕跡
- 嚴重度：🟢 Low　工作量：S
- 證據：`lib/data/sources/source_provider.dart:155-163`（`searchAll` 內 `catch(_){/*忽略單個源錯誤*/}`，註釋說明刻意但無 log）；`lib/services/import/playlist_import_service.dart:285-290`（`.searchFrom(...).catchError((_)=>SearchResult.empty())` 把任何錯誤含程式錯誤都吞成空結果，無 log）。
- 影響：限流/網路錯誤被完全靜音，問題發生時無任何痕跡可排查。
- 建議：這類「單源容錯」catch 內補一行 `logDebug/logWarning`（含 sourceType 與 e）；區分 `DioException`（預期，降級）與其他 `Exception`（程式錯誤，warning）。

## 3. 具體建議（可驗收）

1. **HTTP/錯誤/日誌三條主線統一（B1+B2+B4）：** 歌詞/匯入 Dio 改走 `SourceHttpPolicy`/`HttpClientFactory`；歌詞 exception 繼承 `SourceApiException` 並用 `classifyDioError`；`debugPrint` 收斂到 `Logging` mixin。驗收：`rg "Dio\(BaseOptions|debugPrint"` in `lib/services` 命中數歸零（logger.dart 除外）；歌詞 `is SourceApiException` 路徑可分類重試。
2. **刪/接線 dead error 體系（B3）：** 決定 `core/errors` 去留並補測試。驗收：repo 內僅存一套錯誤分類基底。
3. **抽共用 util（B5/B6/B7）：** duration parser、歌詞 source 介面、節流常數。驗收：新增第 4 個歌詞源不需 copy-paste。

## 4. 本面向優先級 Top 3

1. **B1** — 歌詞/匯入子系統 Dio/header/timeout 統一（一致性主線）
2. **B2** — 歌詞 exception 併入 `SourceApiException` 體系（統一錯誤語義）
3. **B4** — 日誌收斂到 `Logging` mixin（可觀測性一致）
