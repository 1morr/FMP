# Performance Docs Alignment Review

本次只審查文檔與實作一致性，未修改程式碼，也未修改其他 performance review 報告。

## 語料與判讀方式

已閱讀目前核心語料：所有 `AGENTS.md`、`CLAUDE.md`、根 `README.md`、`docs/README.md` 指向的當前文檔、`.serena/memories/*`，以及 `docs/reviews/performance/instruction-corpus.md`。`docs/history/refactoring-log.md` 依根 `AGENTS.md` 與 `docs/README.md` 規則只視為歸檔背景，未作為當前規範。

判讀時將 `AGENTS.md` / scoped `AGENTS.md` 視為規範性要求；`README.md`、`docs/development.md`、memories 與 instruction corpus 中的實作描述，均用程式碼重新驗證。

## Findings

### 1. Android / just_audio buffer 策略有實作但缺少當前指令文檔

Status: Confirmed issue

Evidence:
- `lib/services/audio/AGENTS.md:141` 到 `lib/services/audio/AGENTS.md:149` 只記錄 desktop `MediaKitAudioService` aggressive network buffer：32MB player buffer、24MB demuxer forward buffer、8MB back buffer、7200s cache/readahead。
- `lib/services/audio/just_audio_service.dart:138` 到 `lib/services/audio/just_audio_service.dart:147` 對 Android `just_audio` 設定了 `AndroidLoadControl`：`minBufferDuration` 10s、`maxBufferDuration` 20s、`backBufferDuration` 3s、`targetBufferBytes` 2MB，註解說明是為了避免直播 muxed 流高碼率時緩衝數百 MB。

Trigger scenario:
Android 播放 Bilibili live / muxed fallback / 高碼率串流時，維護者只讀 `lib/services/audio/AGENTS.md` 會看到 desktop buffer 策略，卻看不到 Android 低記憶體 buffer 策略。

User impact:
後續調整播放 buffer 或排查 Android 記憶體暴增時，agent 可能只調整 media_kit / desktop，漏掉 ExoPlayer load control 的性能邊界。

Suggested measurement or fix:
將 Android `JustAudioService` buffer policy 補到 `lib/services/audio/AGENTS.md`，並建議用 Android profile 模式量測直播 / muxed fallback 的 RSS、external memory、buffered duration。

Instruction docs accuracy notes:
現有 desktop buffer 文檔與 `MediaKitAudioService` 常數相符；缺漏在 Android buffer 策略沒有進入當前核心指令文檔。

### 2. 下載暫停/失敗時沒有保存最新進度比例，與「paused/failed 時落 DB」描述不完全一致

Status: Confirmed issue

Evidence:
- `lib/services/AGENTS.md:10` 到 `lib/services/AGENTS.md:12` 要求下載跑在 isolate，progress 先留在記憶體，以避免 Windows PostMessage 與 Isar watch churn。
- `docs/reviews/performance/instruction-corpus.md:131` 到 `docs/reviews/performance/instruction-corpus.md:132` 將描述性 claim 寫成 progress 只在 terminal 或 paused states flush 到 Isar。
- `lib/services/download/download_service.dart:241` 到 `lib/services/download/download_service.dart:259` 明確只把 pending progress 發到 stream，不寫 DB。
- `lib/services/download/download_service.dart:539` 到 `lib/services/download/download_service.dart:544` 在 `pauseTask()` 先 `_clearPendingProgressForTask(taskId)`，再清理 isolate，最後只更新 status 為 paused。
- `lib/services/download/download_service.dart:1047` 到 `lib/services/download/download_service.dart:1056` 的 `_saveResumeProgress()` 會用 `task.progress` / `task.totalBytes` 寫 DB，但這個 `task` 是下載開始時的物件，不會從 `_pendingProgressUpdates` 取最新 progress。
- `lib/data/repositories/download_repository.dart:230` 到 `lib/data/repositories/download_repository.dart:238` 寫入的確是傳入的 `progress`、`downloadedBytes`、`totalBytes`。

Trigger scenario:
使用者下載大型檔案，進度已由 isolate 上報到記憶體，但在下一次 flush 或完成前按暫停，或網路錯誤進入 failed。

User impact:
暫停/失敗後下載列表可能顯示舊的 progress 比例，尤其初次下載時可能顯示 0%，即使 `.downloading` 暫存檔已有部分 bytes 可續傳。

Suggested measurement or fix:
補測 `pauseTask` / failure 後 DB 中 `progress`、`downloadedBytes`、`totalBytes` 是否與暫存檔一致。修正方向是暫停/失敗前從 `_pendingProgressUpdates[taskId]` 取最後一筆，或用 `tempFile.length()` 與可得的 total bytes 重新計算 progress，再寫入 `updateTaskProgress()`。

Instruction docs accuracy notes:
「active progress 不頻繁寫 Isar」是準確的；「paused/failed 時 progress 落 DB」目前只保存了部分 resume bytes，未可靠保存最新比例與 total bytes。文檔若不改實作，應避免把 paused/failed flush 說成完整 progress flush。

### 3. FileExistsCache 文檔說「只快取存在路徑」，但實作也有負向 missing cache

Status: Confirmed issue

Evidence:
- `.serena/memories/download_system.md:41` 寫 `FileExistsCache` 只快取存在的路徑，最大 5000 條。
- `docs/reviews/performance/instruction-corpus.md:133` 也列出 `FileExistsCache` caches only existing paths。
- `lib/providers/download/file_exists_cache.dart:21` 到 `lib/providers/download/file_exists_cache.dart:31` 有 `_missingPaths` 與 `_maxMissingCacheSize = 5000`。
- `lib/providers/download/file_exists_cache.dart:37` 到 `lib/providers/download/file_exists_cache.dart:43` 在 `_missingPaths.contains(path)` 時直接回傳 false，不再查檔案系統。
- `lib/providers/download/file_exists_cache.dart:165` 到 `lib/providers/download/file_exists_cache.dart:173` 會把不存在路徑加入 `_missingPaths` 並裁切到 5000。

Trigger scenario:
UI 先查某個本地封面 / avatar 路徑，當時檔案不存在；之後外部同步、手動移動、或背景流程建立了該檔，但沒有呼叫 `markAsExisting()`、`remove()`、`clearAll()` 或相關 invalidation。

User impact:
圖片或下載標記可能維持 placeholder / 未下載狀態，直到某個流程清掉負向快取。

Suggested measurement or fix:
文檔應改成「快取存在路徑與有界 missing 路徑，各 5000 條；建立檔案後必須 mark/remove/clear/invalidate」。若要改實作，應針對外部同步和手動匯入流程補負向快取失效測試。

Instruction docs accuracy notes:
`lib/ui/AGENTS.md:14` 到 `lib/ui/AGENTS.md:22` 的 watch/read 使用模式仍準確；過時的是 memory 與 corpus 對 cache 內容的「only existing」描述。

### 4. `watchAll()` provider pattern 文檔把 history 列為範例，但播放歷史實作不是 `watchAll()` + data StateNotifier

Status: Confirmed issue

Evidence:
- `lib/providers/AGENTS.md:7` 到 `lib/providers/AGENTS.md:10` 將 DB collection / multi-writer 模式寫成 Isar `watchAll()` + `StateNotifier`，範例包含 Playlists、radio、history。
- Playlist 符合：`lib/providers/playlist_provider.dart:69` 到 `lib/providers/playlist_provider.dart:88` 用 `PlaylistListNotifier` 訂閱 `repo.watchAll()`。
- Radio 符合：`lib/services/radio/radio_controller.dart:296` 到 `lib/services/radio/radio_controller.dart:300` 訂閱 `_repository.watchAll()`。
- History 不符合該描述：`lib/providers/play_history_provider.dart:8` 到 `lib/providers/play_history_provider.dart:17` 是 `StreamProvider`，先 `loadHistorySnapshot()`，再對 `repo.watchHistory()` 重新載入 snapshot。
- Repository 端也不是 `watchAll()`：`lib/data/repositories/play_history_repository.dart:135` 到 `lib/data/repositories/play_history_repository.dart:137` 是 `_isar.playHistorys.watchLazy()`。
- History snapshot 目前固定載入最多 1000 筆：`lib/data/repositories/play_history_repository.dart:252` 到 `lib/data/repositories/play_history_repository.dart:266`。

Trigger scenario:
播放歷史快速增加、清除、批量刪除，或歷史頁在大量紀錄下切換排序 / 篩選。

User impact:
文檔會誤導維護者以為 history 已採用 `watchAll()` + StateNotifier data pattern。實際上每次 collection lazy watch 觸發都重新查 snapshot，性能特徵與 playlist/radio 不同；大量歷史時需要 profile 才能判斷是否造成查詢或 rebuild 壓力。

Suggested measurement or fix:
若現有 history 設計是刻意的，將 `lib/providers/AGENTS.md` 範例改成 Playlists / radio，並補一句 history 使用 `watchLazy()` + shared 1000-row snapshot。若要對齊模式，需先 profile 歷史頁大量資料下的 watch trigger、query time、UI rebuild，再決定是否改成專用 StateNotifier 或 query-level watch。

Instruction docs accuracy notes:
Provider pattern 本身可用，但 `history` 範例過時或過度概括。

### 5. 圖片預載路徑繞過統一 `ImageLoadingService` cache policy，文檔沒有覆蓋 preloading

Status: Suspected issue

Evidence:
- `lib/ui/AGENTS.md:7` 到 `lib/ui/AGENTS.md:12` 要求圖片走 `TrackThumbnail` / `TrackCover` / `ImageLoadingService`，並傳尺寸供縮略圖優化。
- `lib/core/services/image_loading_service.dart:416` 到 `lib/core/services/image_loading_service.dart:427` 的主要網路圖片路徑使用 `CachedNetworkImage`，明確傳 `NetworkImageCacheService.defaultCacheManager`，並設定 `memCacheWidth` / `memCacheHeight`。
- `lib/ui/widgets/track_detail_panel.dart:2062` 到 `lib/ui/widgets/track_detail_panel.dart:2072` 的 `_RadioClickableCover._preloadImage()` 直接建立 `CachedNetworkImageProvider(optimizedUrl, headers: ...)`，沒有傳 `NetworkImageCacheService.defaultCacheManager`，也沒有使用 `ImageLoadingService` 的候選 URL fallback / mem cache sizing。
- 顯示同一張圖時又走 `ImageLoadingService.loadImage()`：`lib/ui/widgets/track_detail_panel.dart:2102` 到 `lib/ui/widgets/track_detail_panel.dart:2107`。

Trigger scenario:
進入含 radio cover 的播放詳情面板；預載先用預設 cache manager 建立 provider，真正顯示再用 FMP 自訂 network image cache manager 載入。

User impact:
同一 URL 可能進入不同 cache manager / memory cache policy，導致重複請求、重複 decode、cache size 設定不一致，或預載成功但實際顯示仍重新載入。

Suggested measurement or fix:
用 HTTP profile / cache logs 驗證該 cover 是否重複請求。修正方向是提供統一的 `ImageLoadingService` preload helper，或在預載時傳同一個 `NetworkImageCacheService.defaultCacheManager` 並沿用候選 URL / 尺寸策略。

Instruction docs accuracy notes:
`lib/ui/AGENTS.md` 對 visible image widget 的規則準確，但未明確覆蓋 image preloading。建議補一句：預載也應復用同一 cache manager、headers、thumbnail URL policy。

### 6. Bilibili live cover header 規範只提 preloading，但多個顯示路徑未傳 live headers

Status: Suspected issue

Evidence:
- `lib/data/sources/AGENTS.md:20` 到 `lib/data/sources/AGENTS.md:23` 要求 live room API clients、stream playback headers、radio cover preloading 使用 `SourceHttpPolicy.bilibiliLiveHeaders()` / `createBilibiliLiveDio()`，保持 live Referer 與 media UA 一致。
- Stream path 有帶 headers：`lib/services/radio/radio_source.dart:288` 到 `lib/services/radio/radio_source.dart:291` 的 `LiveStreamInfo` 使用 `SourceHttpPolicy.bilibiliLiveHeaders()`。
- Detail panel 預載有帶 headers：`lib/ui/widgets/track_detail_panel.dart:2066` 到 `lib/ui/widgets/track_detail_panel.dart:2071`。
- 但 radio mini player 顯示封面未傳 headers：`lib/ui/widgets/radio/radio_mini_player.dart:120` 到 `lib/ui/widgets/radio/radio_mini_player.dart:126`。
- Radio player cover 也未傳 headers：`lib/ui/pages/radio/radio_player_page.dart:155` 到 `lib/ui/pages/radio/radio_player_page.dart:160`。
- Radio page 列表/網格 cover 未傳 headers：`lib/ui/pages/radio/radio_page.dart:424` 到 `lib/ui/pages/radio/radio_page.dart:430`、`lib/ui/pages/radio/radio_page.dart:603` 到 `lib/ui/pages/radio/radio_page.dart:609`。

Trigger scenario:
Bilibili live cover CDN 對 Referer / UA 敏感，或之後 live image URL 來源更嚴格。

User impact:
封面可能偶發 403 / placeholder，或同一 live cover 在預載與實際顯示使用不同 header policy，增加排查難度。

Suggested measurement or fix:
先用 HTTP profile 或手動請求驗證 Bilibili live cover 在無 headers 情況下是否穩定。若需要一致性，讓 radio cover display paths 也傳 `SourceHttpPolicy.bilibiliLiveHeaders()`，或在文檔中明確區分「只有預載需要 live headers，顯示路徑不需要」並說明原因。

Instruction docs accuracy notes:
現有規範提到 preloading，但沒有說 display loads 是否也應同源 header policy；此處是文檔邊界不清，而非已確認的使用者可見錯誤。

### 7. 下載 isolate 文檔有平台語義不一致：核心文檔是全平台，memory 說 Windows-only

Status: Confirmed issue

Evidence:
- `lib/services/AGENTS.md:10` 到 `lib/services/AGENTS.md:12` 寫「Downloads run in an isolate」，並說此舉避免 Windows PostMessage queue overflow 與 Isar watch churn。
- `.serena/memories/download_system.md:39` 寫「Windows 下載在 isolate 中執行」。
- 實作沒有平台 gating：`lib/services/download/download_service.dart:762` 到 `lib/services/download/download_service.dart:777` 直接 `Isolate.spawn(_isolateDownload, ...)`。
- isolate 內使用 `HttpClient` 並逐跳套用 download media headers：`lib/services/download/download_service.dart:1511` 到 `lib/services/download/download_service.dart:1555`。

Trigger scenario:
agent 只讀 memory 或維護下載流程時，以為 isolate 僅是 Windows 特例。

User impact:
Android 或其他平台下載性能 / 取消流程排查時，可能忽略 isolate 通訊、cancel port、progress message threshold 這些共通行為。

Suggested measurement or fix:
更新 `.serena/memories/download_system.md`，改成「下載目前全平台走 isolate；主要動機包含 Windows PostMessage queue overflow」。若 memory 已不該承載核心規則，合併到 `lib/services/AGENTS.md` 後刪除或縮短該 memory。

Instruction docs accuracy notes:
核心 `lib/services/AGENTS.md` 準確；補充 memory 的 Windows-only 措辭過窄。

### 8. `lyricsSearchProvider` 仍 watch 整個 audio settings state，selector 粒度文檔未覆蓋這個重建面

Status: Needs profiling

Evidence:
- `.serena/memories/refactoring_lessons.md:34` 要求歌詞設定不要讓 `audioControllerProvider` 重建，歌詞 provider 應只 watch 自己需要的 setting/selectors。
- `lib/services/audio/audio_provider.dart:3247` 使用 `ref.read(lyricsAutoMatchServiceProvider)`，因此 audio controller 不會因 lyrics auto-match service dependency rebuild 而直接重建，這點符合 memory。
- `lib/providers/lyrics_provider.dart:469` 到 `lib/providers/lyrics_provider.dart:487` 的 `lyricsSearchProvider` 則 `ref.watch(audioSettingsProvider)` 整個 state，但實際只用 `lyricsSourceOrder` 與 `disabledLyricsSources`。
- `lib/providers/audio_settings_provider.dart:11` 到 `lib/providers/audio_settings_provider.dart:26` 顯示 `AudioSettingsState` 同時包含 quality、format priority、stream priority、lyrics、auth-for-play 等欄位。

Trigger scenario:
使用者在音訊設定頁調整音質、stream priority、auth-for-play 或 AI lyrics endpoint，同時歌詞搜尋 sheet 存在或即將開啟。

User impact:
可能造成不必要的 `LyricsSearchNotifier` 重建或搜尋狀態重置。是否可見取決於 provider lifetime 與 UI flow，需要 runtime profile 或 widget test 佐證。

Suggested measurement or fix:
加 provider observer / widget test 驗證非歌詞 source-order 設定變更時 `lyricsSearchProvider` 是否重建並清掉搜尋狀態。若確認有影響，改用 `audioSettingsProvider.select((s) => (s.lyricsSourceOrder, s.disabledLyricsSources))` 或既有 selector providers。

Instruction docs accuracy notes:
文檔目前只明確保護 `audioControllerProvider`，沒有列出 lyrics search provider 的 selector 粒度要求。若此 provider 的重建是可接受的，文檔應說明；若不可接受，文檔應補上。

## 已核對且方向一致的性能策略

- Desktop `MediaKitAudioService` buffer 常數與 `lib/services/audio/AGENTS.md` 相符：`desktopPlayerBufferSizeBytes = 32MB`、`desktopDemuxerMaxBytes = 24MB`、`desktopDemuxerMaxBackBytes = 8MB`、`desktopBufferSeconds = 7200`，並設定 `vid=no` / `sid=no`。
- `JustAudioService.playUrl()` / `playFile()` 未 await `just_audio.play()`，符合 memory 中避免長時間阻塞 loading state 的描述。
- 下載 active progress 透過記憶體 map、timer 與 stream 更新 UI，沒有高頻寫 Isar。
- 下載音訊與 metadata image header helpers 有被使用：media 在 isolate 內逐 URL 呼叫 `buildDownloadMediaHeaders()`，metadata image 使用 `buildDownloadImageHeaders()`，播放 request 也走 `SourceHttpPolicy.mediaHeaders()`。
- UI 中未發現直接 `Image.network()` / `Image.file()`；主要可見圖片路徑大多走 `ImageLoadingService.loadImage()` 並傳尺寸或 `targetDisplaySize`。
