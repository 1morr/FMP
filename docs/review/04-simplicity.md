# 04 — 程式碼簡潔度（面向 C）

> 唯讀審查；證據均含 `file:line`。標 `對抗驗證` 者已覆核。成熟度評分：**3 / 5**。

## 1. 現狀摘要

- **好：** 路徑一律用 `p.join`、generated 檔清楚分離、`settings_page` 的 7 個 `part` 完整無孤兒、source adapter 的 search 差異屬合理 API 差異而非重複。
- **壞：** 多個 UI 頁面是單檔巨型 State 類別（900–1250 行）、download 與 audio 服務有過長方法（`_startDownload` 267 行）、`download_service` 殘留已不下載的舊 CancelToken 路徑、`playlist_service` 有 deprecated 且零引用的 getter、錯誤分類靠字串 `contains` 而非型別、灰階 `ColorFilter` 與下載檔名字面常數在多處重複。

## 2. 發現清單

### C1　多個核心頁面 State 類別嚴重肥大（900–1250 行） — 對抗驗證 **partially，High→Medium**
- 嚴重度：🟡 Medium　工作量：L
- 證據：
  - `lib/ui/windows/lyrics_window.dart:181-1430`（`_LyricsWindowPageState` 約 1250 行，混 channel 處理、偏移校正、顯示模式、樣式、字體測量、建構）
  - `lib/ui/pages/player/player_page.dart:45-1074`（`_PlayerPageState` 約 1030 行，build + 22 方法）
  - `lib/ui/pages/library/playlist_detail_page.dart:49-1157`（約 1109 行，~24 方法）
  - `lib/ui/pages/search/search_page.dart:42-959`（約 918 行，~20 方法）
- 驗證補充：player/playlist_detail/search 其實**已各自抽出**多個 private widget（player 有 `_CommentPager`/`_DetailContent` 等 8+、playlist_detail 4+、search 8+），重構方向已部分在執行中；`lyrics_window` 是最未拆分者。
- 影響：單一類別承擔生命週期、事件、樣式、度量、建構多重職責，閱讀與測試困難。純 code smell、無功能風險，故降 Medium。
- 建議：依職責抽 private widget / helper（lyrics_window 拆 `OffsetController`/`DisplayModeController`/`LyricsTextMeasurer`；純邏輯移到無 Widget 依賴的 helper）。

### C2　`download_service._startDownload` 過長（267 行）且 abort 清理區塊重複 5 次 — 對抗驗證 **partially，High→Medium**
- 嚴重度：🟡 Medium　工作量：M
- 證據：`lib/services/download/download_service.dart:695-961`（`_startDownload` 267 行，橫跨解析串流→IO→Isolate→元資料→清理五階段，穿插十餘次 `_shouldAbort*` 早返回）；`:870-928`（`if (_shouldAbortAfterFinalizationStarted(task.id)) { await _clearDownloadPathForTask(task); await _deleteTaskFiles(task); return; }` 逐字重複於 870/891/903/911/924 共 5 次）。驗證確認 `_startDownload` 為私有、無測試直接呼叫。
- 影響：主流程一方法五階段、密集 abort 檢查，難正確修改與測試；重複清理增加不一致風險（潛在、非現存）。
- 建議：抽 `Future<bool> _abortFinalizationCleanup(task)`（true=已中止），各檢查點單行 `if (await _abortFinalizationCleanup(task)) return;`；`_startDownload` 拆成 `resolve-stream`/`run-isolate`/`finalize`（promote+metadata+complete）三個私有方法，本身只做編排。

### C3　`download_service` 殘留已不再用於正式下載的 CancelToken 相容路徑
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/services/download/download_service.dart:77`（`final Map<int, CancelToken> _activeCancelTokens = {};`）；`:1426-1430`（`debugRegisterLegacyActiveDownloadForTesting` 是唯一寫入此 map 的位置，測試專用，正式路徑改走 Isolate 不再建立 CancelToken）；`:241-245`（dispose 內 `// 相容舊的 CancelToken` 註解下的迴圈與 `.clear()`）；`:1008,1040`（`_activeCancelTokens.remove`）；`:619-650`（`getActiveTaskIDs` 仍把 `_activeCancelTokens.keys` 併入回傳，實際恆空）。
- 影響：舊 CancelToken 後端已被 Isolate 取代，但欄位/dispose/取消/測試 hook 全部保留，誤導讀者以為存在兩條並存路徑。
- 建議：確認 phase1 測試可改用既有 `debugStartDownloadForTesting`/`debugWaitForTaskToBecomeActiveForTesting` 後，移除 `_activeCancelTokens`、其 cancel/dispose 邏輯、`getActiveTaskIDs` 併入、與 `debugRegisterLegacyActiveDownloadForTesting`，連帶調整 phase1 測試。

### C4　`playlist_service.getPlaylistCover` 標註 deprecated 且零引用
- 嚴重度：🟢 Low　工作量：S
- 證據：`lib/services/library/playlist_service.dart:371-376`（`/// @deprecated 使用 getPlaylistCoverData 替代`，全庫 `getPlaylistCover(` 在 lib/test 僅命中定義處；正式呼叫端皆已改 `getPlaylistCoverData`，`playlist_provider.dart:548`）。
- 建議：直接刪除；若需保留過渡，改用 `@Deprecated('use getPlaylistCoverData')` 註解並排定移除時程。

### C5　debug 測試頁 `_isBuffering`/`_isCompleted` 為寫入後從未讀取的死角
- 嚴重度：🟢 Low　工作量：S
- 證據：`lib/ui/pages/debug/youtube_stream_test_page.dart:78-81`（`// ignore: unused_field` 兩欄位僅在 listener/重設點被寫入，build 從不讀取，須 ignore 壓制分析）。
- 建議：不需顯示則移除欄位與其 listener `setState`；要顯示則接上 UI 並移除 ignore。

### C6　`radio_controller` 靠 `errorStr.contains('Stream failed to open')` 分類錯誤決定重試
- 嚴重度：🟡 Medium　工作量：S
- 證據：`lib/services/radio/radio_controller.dart:534-538`（`if (!isRetry && errorStr.contains('Stream failed to open'))` 重試）；`lib/services/audio/media_kit_audio_service.dart:905-907`（該字串來源 `throw Exception('Stream failed to open')`，僅 media_kit 後端會拋；just_audio 字串不同）。
- 影響：重試決策綁死特定後端的特定訊息文字，跨平台不一致且對訊息改動極脆弱。
- 建議：media_kit 後端定義專屬例外型別（如 `StreamOpenFailedException`），`radio_controller` 改 `catch (StreamOpenFailedException)`；錯誤分類一律走型別而非字串。

### C7　灰階 `ColorFilter.matrix`（REC.709）在 3 個 UI 檔逐字重複
- 嚴重度：🟢 Low　工作量：S
- 證據：`lib/ui/pages/home/home_page.dart:1093-1119`（內嵌 20 元素矩陣 + isLive 三元）；`lib/ui/pages/radio/radio_page.dart:400-420,603`（同矩陣出現兩次）；`lib/ui/pages/search/search_page.dart`（同矩陣；`rg '0\\.2126'` 命中 3 檔）。
- 建議：在 `lib/ui` 新增 helper（`ColorFilter grayscaleFilter()` 與 `coverColorFilter(bool isLive)`），矩陣作為頂部 `const` list，三處改呼叫。

### C8　下載檔名（`cover.jpg`/`avatar.jpg`/`metadata.json`）在 5+ 檔以字面常數重複、無集中常數
- 嚴重度：🟡 Medium　工作量：S
- 證據：`lib/services/download/download_service.dart:1297-1329`（字面 `metadata.json`/`cover.jpg`/`avatar.jpg`）；`lib/providers/download/download_scanner.dart:178-339`（掃描器多處 `File(p.join(entity.path, 'cover.jpg'))`、`'metadata.json'`、`'metadata_P$pageNumStr.json'`，須與下載端一致）；`lib/core/extensions/track_extensions.dart:63-79`（重複同名字面）；`rg` 在 `lib/core/constants` 找不到這些常數定義。
- 影響：下載寫入與掃描讀取的檔名靠散落字面維持一致，任一處改名即造成掃描遺漏或檔案找不到。
- 建議：在 `lib/core/constants` 定義 `kCoverFileName`/`kAvatarFileName`/`kMetadataFileName` 與分頁命名規則，下載端/掃描端/`track_extensions`/`playlist_service`/`track_detail_provider` 全改引用。

### C9　`_deletePathIfExists` 與 `_deleteDirectoryIfEmpty` 重試刪除骨架完全相同
- 嚴重度：🟢 Low　工作量：S
- 證據：`lib/services/download/download_service.dart:1130-1172`（兩方法同為 `for (attempt<10)` 內 `try/on FileSystemException/catch`，差異僅 `File.delete` vs `Directory.delete` + `list().isEmpty`）。
- 建議：抽泛型 `Future<void> _retryDelete({Future<bool> Function() action, String label, int taskId})`，各自只傳入存在檢查與刪除動作。

### C10　`SearchService` 直接手寫 `_isar.searchHistorys` 查詢，與其他模型一律走 Repository 不一致
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/services/search/search_service.dart:201-267`（直接持 Isar 並手寫 `where()`/`put()`/`delete()`/`clear()` 與去重排序）；`lib/data/repositories/repositories.dart:1-12`（倉庫匯出清單獨缺 `SearchHistoryRepository`）。
- 影響：唯獨搜尋歷史由 service 直接碰 Isar，存取模式不一致、難單獨測試資料層。
- 建議：新增 `SearchHistoryRepository`（get/add-or-touch/delete/clear/排序裁剪），`SearchService` 注入只做編排。

### C11　`AudioController.initialize` 連續 10 個近乎相同的 `stream.listen` 註冊區塊
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/services/audio/audio_provider.dart:382-421`（10 段 `_subscriptions.add(_audioService.<stream>.listen(_on...))`，每塊夾 `if (_isDisposed) return;` 與 `logDebug`）。
- 建議：抽 `_registerAudioServiceListeners()` 集中，或以 `(stream, handler)` 配列 `forEach` 註冊；`initialize` 只留編排與 restore。

### C12　`_executePlayRequest` 內 retry 排程區塊與 superseded guard 重複出現
- 嚴重度：🟡 Medium　工作量：S　[未個別驗證]
- 證據：`lib/services/audio/audio_provider.dart:2304-2336`（`on SourceApiException` 與 `catch` 兩處皆為 guard→`_resetLoadingState`→`_scheduleRetryForSessionRequest`→`throw _RetryScheduledException()`，逐字重複）；`:900-918`；`rg _isSessionSuperseded(requestId)` 本檔 15 次。
- 建議：抽 `Never _scheduleRetryAndThrow(requestId, track, position, mode)`（內含 guard/reset/schedule/throw）；考慮 `_abortIfSuperseded(requestId)` bool helper 統一 guard+logDebug+return。

### C13　`youtube_source.parsePlaylist`（176 行）與 `_parsePlaylistViaInnerTube`（187 行）過長、巢狀深
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/data/sources/youtube_source.dart:1372-1548`（`parsePlaylist` 176 行，多職責交織）；`:2061-2248`（`_parsePlaylistViaInnerTube` 187 行，深層巢狀）；`:1744-1823`（`_trackFromLockupViewModel` 80 行單一映射）。
- 建議：`parsePlaylist` 拆 `_routePlaylistParse` 與各自解析方法；`_parsePlaylistViaInnerTube` 抽出 request/continually 解析/tracks 映射/token 翻頁四段。

### C14　`_loadMoreMixTracks` 巢狀深、`isCurrent(mixState)` 中止檢查重複
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/services/audio/audio_provider.dart:1774-1908`（135 行 `while` 內含 abort 檢查/種子選擇/去重/重試延遲多層 if）；`:1814,1847,1882`（`isCurrent` 中止檢查 4 次）。
- 建議：抽 `Future<List<Track>?> _fetchOneMixBatch(mixState, queue, attempt)`，主方法只負責迴圈與計數；重複中止包 helper。

## 3. 具體建議（可驗收）

1. **下載主流程拆解（C2 + C3）：** `_startDownload` 拆三階段 + `_abortFinalizationCleanup` 單行化；移除 dead CancelToken 路徑。驗收：`_startDownload` ≤ ~80 行編排；`rg "_activeCancelTokens|debugRegisterLegacyActiveDownloadForTesting"` 命中歸零。
2. **常數收斂（C8 + C7）：** 下載檔名與灰階矩陣提升為 const/helper。驗收：`rg "cover.jpg|avatar.jpg|metadata.json" lib` 僅命中常數定義處。
3. **UI 巨型 State 拆分（C1）：** 優先 `lyrics_window`（最未拆）。驗收：拆出 helper 後 State 主類別行數減半且測試可獨立覆蓋偏移邏輯。
4. **錯誤分類型別化（C6）：** radio 重試改型別判斷。

## 4. 本面向優先級 Top 3

1. **C2** — `_startDownload` 拆解 + abort 清理去重（最肥大、最難測的方法）
2. **C1** — 巨型 State 類別拆分（以 `lyrics_window` 為先）
3. **C3** — 移除 dead CancelToken 相容路徑（誤導性死碼）
