# Audio runtime performance review

審查日期：2026-05-25
審查範圍：`MediaKitAudioService`、`JustAudioService`、`AudioController`、buffer settings、streams、subscriptions、retry loop、timer、position update、長時間播放與快速切歌資源釋放。

## 語料分層

### 規範性要求

- UI 播放控制必須走 `AudioController`，不可直接呼叫 `FmpAudioService`；Radio 是明確例外，由 ownership hook 隔離。
- Android/iOS 使用 `JustAudioService`；Windows/Linux/macOS 使用 `MediaKitAudioService`，且 `MediaKit.ensureInitialized()` 只在桌面平台呼叫。
- `AudioController` 擁有 user-facing state、request supersession、temporary/mix/detached modes、notification/SMTC、network retry 與 source error 決策。
- 不走 `_executePlayRequest()` 的 URL 取得流程必須遞增 `_playRequestId`，並在每個 `await` 後檢查 `_isSuperseded(requestId)`。
- runtime backend network error 應 retry/refetch current track URL 並保留位置，不應直接 advance queue。
- `completedStream` 不一定代表自然播放完成；loading/retry/network-error 期間應忽略，mid-track completion 應重試 current track。
- 桌面 `MediaKitAudioService` 的 32MB player buffer、24MB demuxer forward buffer、8MB back buffer、7200s cache/readahead 是有意設計；`vid=no`、`sid=no` 必須保留。
- Queue position 持久化每 10 秒保存一次，seek 後立即保存；progress slider 只應在 `onChangeEnd` seek。
- Audio URLs 會過期，播放恢復與 stream resolution 要能 refresh；media headers 要經 `SourceHttpPolicy.mediaHeaders()` 的 source-aware allowlist。
- 文件型變更最低驗證為 `git diff --check`。

### 描述性內容，已用程式碼驗證

- `docs/development.md` 的平台分工與 `audioServiceProvider` 實作一致：mobile 回傳 `JustAudioService`，desktop 回傳 `MediaKitAudioService`。
- `.serena/memories/refactoring_lessons.md` 中「lyrics settings 不應重建 audio controller」有測試覆蓋。
- `.serena/memories/download_system.md` 與此次音訊 runtime review 只在 downloaded local-file selection 交會；下載 isolate/progress 行為未納入 finding。
- `lib/services/audio/AGENTS.md` 對桌面 buffer profile 的描述與常數、測試一致。

## Findings

### 1. 歌詞彈窗 raw position tick 會穿過 platform channel

Status：suspected issue

Evidence：
- `lib/ui/widgets/track_detail_panel.dart:302` 直接 listen `audioControllerProvider.select((s) => s.position)`。
- `lib/ui/widgets/track_detail_panel.dart:144` 到 `lib/ui/widgets/track_detail_panel.dart:169` 每次 position 變化都呼叫 `LyricsWindowService.instance.syncPosition(...)`，即使 `currentLineIndex` 沒變。
- `lib/services/lyrics/lyrics_window_service.dart:323` 到 `lib/services/lyrics/lyrics_window_service.dart:336` 每次 `syncPosition()` 都透過 `WindowMethodChannel.invokeMethod('updatePosition', ...)` 傳送。
- 子窗口端只在行索引變化時 `setState`：`lib/ui/windows/lyrics_window.dart:363` 到 `lib/ui/windows/lyrics_window.dart:370`。
- `currentLyricsLineIndexProvider` 已有較低頻的語意：`lib/providers/lyrics_provider.dart:247` 到 `lib/providers/lyrics_provider.dart:255` 說明依賴 raw position 但只讓 dependents 在整數行索引變化時收到通知。

Trigger scenario：長時間播放時開著 Windows 歌詞彈窗；播放 position stream 以 backend 頻率更新，但歌詞行通常數秒才變一次。

User impact：主 UI 不一定每 tick rebuild，但主視窗仍會做 LRC 行計算、JSON encode、platform channel IPC；長時間播放、歌詞彈窗共存與低階 Windows 機器上可能增加 CPU/IPC 壓力。

Suggested measurement or fix：
- 在 profile 模式量測開關歌詞彈窗前後的 platform channel 次數、UI thread frame time、Dart CPU。
- 若 positionMs 只供右鍵 offset 校準，可改為 line-index 變化時同步，或用 250ms/500ms throttle；若確實要保留 positionMs，可只在彈窗可見且校準互動期間提高頻率。

Instruction docs accuracy notes：`lib/services/AGENTS.md` 描述「桌面歌詞 popup window 使用獨立 engine 且 rapid open 要 coalesce」是準確的；但目前沒有文檔明確要求 lyrics window position IPC 節流。

### 2. `AudioController` state raw position 更新未節流，且仍有 broad listeners/watchers

Status：needs profiling

Evidence：
- `MediaKitAudioService` 直接 forward backend position：`lib/services/audio/media_kit_audio_service.dart:311` 到 `lib/services/audio/media_kit_audio_service.dart:314`。
- `JustAudioService` 直接 forward backend position：`lib/services/audio/just_audio_service.dart:235` 到 `lib/services/audio/just_audio_service.dart:238`。
- `AudioController._onPositionChanged()` 每次 position tick 都 `state = state.copyWith(position: position, ...)`：`lib/services/audio/audio_provider.dart:2725` 到 `lib/services/audio/audio_provider.dart:2734`。
- notification/SMTC 有 500ms 節流：`lib/services/audio/audio_provider.dart:2736` 到 `lib/services/audio/audio_provider.dart:2763`，但 Riverpod `PlayerState` 本身沒有節流。
- Windows desktop service 使用 broad `ref.listen(audioControllerProvider, ...)`，雖然 callback 內只在 playing/track 變化時更新 tray：`lib/providers/windows_desktop_provider.dart:18` 到 `lib/providers/windows_desktop_provider.dart:27`。
- Radio UI 為了音量/裝置 watch 整個 `audioControllerProvider`：`lib/ui/widgets/radio/radio_mini_player.dart:37`、`lib/ui/pages/radio/radio_player_page.dart:31`。

Trigger scenario：長時間播放時開著主畫面、Radio mini player 或 Windows desktop provider；position stream 高頻進入 `PlayerState`，所有 broad listener/watch 都會被喚醒再自行過濾或 rebuild。

User impact：在長時間播放、歌詞面板與 Radio UI 共存時，可能出現不必要 rebuild/callback 與 CPU 使用。這不是功能錯誤，但屬於可量測的 runtime overhead。

Suggested measurement or fix：
- 用 `debugPrintRebuildDirtyWidgets` 或 Flutter rebuild profiler 比較整曲播放 5 分鐘的 rebuild count。
- 將 broad listener/watch 改成 `.select()` 或專用 provider，例如 volume/audioDevices/isPlaying/currentTrack tuple。
- 若 slider 需要流暢，保留 UI 層 position provider，但避免非進度 UI watch 整個 `PlayerState`。

Instruction docs accuracy notes：`lib/services/audio/AGENTS.md` 已規定 progress slider 不應高頻 seek，但未規定 playback position state 發布頻率；目前 notification/SMTC 的節流實作符合「減少 IPC」意圖，但 Riverpod state 還需要 profiling。

### 3. 快速切歌期間 `MediaKitAudioService` handoff 缺少 request-scoped cancellation

Status：suspected issue

Evidence：
- `AudioController._executePlayRequest()` 建立 `_LockWithId`，但搜尋結果顯示 `_playLock` 只被 complete，未被 await 作為真正互斥鎖：`lib/services/audio/audio_provider.dart:1981` 到 `lib/services/audio/audio_provider.dart:1983`、`lib/services/audio/audio_provider.dart:2098` 到 `lib/services/audio/audio_provider.dart:2104`。
- `PlaybackRequestExecutor` 在 `playUrl()` / `playFile()` handoff 之前檢查 superseded，但 backend handoff 本身完成後才再檢查：`lib/services/audio/playback_request_executor.dart:231` 到 `lib/services/audio/playback_request_executor.dart:242`、`lib/services/audio/playback_request_executor.dart:198` 到 `lib/services/audio/playback_request_executor.dart:203`。
- `MediaKitAudioService` 的 `_ensurePlayback()` 只用單一 `_playbackCancelled` bool；每次 `_ensurePlayback()` 開始都設回 `false`：`lib/services/audio/media_kit_audio_service.dart:630` 到 `lib/services/audio/media_kit_audio_service.dart:640`。
- `stop()` / `pause()` 會把 `_playbackCancelled` 設為 `true`：`lib/services/audio/media_kit_audio_service.dart:481` 到 `lib/services/audio/media_kit_audio_service.dart:490`。
- `playUrl()` 中 `open()`、duration polling、`_ensurePlayback()` 都是 async handoff：`lib/services/audio/media_kit_audio_service.dart:698` 到 `lib/services/audio/media_kit_audio_service.dart:731`。
- 現有 supersession 測試覆蓋「header resolution 後 abort」而非「backend handoff 中被 superseded」：`test/services/audio/playback_request_executor_test.dart:420` 到 `test/services/audio/playback_request_executor_test.dart:467`、`test/services/audio/playback_request_executor_test.dart:543` 到 `test/services/audio/playback_request_executor_test.dart:568`。

Trigger scenario：Windows 上網路慢或 `media_kit` `open()`/buffer 初始化較慢時，使用者快速連點切歌；第一個 handoff 仍在 `open()` 或 `_ensurePlayback()`，第二個 handoff 已開始並把 `_playbackCancelled` 重設。

User impact：疑似可能出現舊請求在 backend 層晚到並呼叫 `play()`、影響新歌播放狀態，或造成短暫錯歌/卡 loading。Controller state 有 superseded guard，但 backend side effect 已經發生。

Suggested measurement or fix：
- 加一個 request/generation token 到 `MediaKitAudioService.playUrl()`、`playFile()`、`setUrl()` 與 `_ensurePlayback()`，在每個 `await` 後確認 token 仍是最新。
- 補測試：fake backend handoff 在 `open()` 後、`_ensurePlayback()` 前掛起，再快速發第二次播放，確認第一個 handoff 不會呼叫 stale `play()`。

Instruction docs accuracy notes：`lib/services/audio/AGENTS.md` 對 `_playRequestId` supersession 的規範在 controller/executor 層大致有落實；但 backend service 自身沒有 request-scoped token，文檔沒有明示這層風險。

### 4. 桌面大 buffer profile 合理但需要真機長時段記憶體 profiling

Status：needs profiling

Evidence：
- 常數為 32MB player buffer、24MB demuxer max、8MB back buffer、7200 秒 readahead/cache：`lib/services/audio/media_kit_audio_service.dart:19` 到 `lib/services/audio/media_kit_audio_service.dart:26`。
- `PlayerConfiguration(bufferSize: bufferSize)` 在桌面使用 32MB：`lib/services/audio/media_kit_audio_service.dart:153` 到 `lib/services/audio/media_kit_audio_service.dart:160`。
- mpv 屬性包含 `vid=no`、`sid=no`、`demuxer-max-bytes`、`demuxer-max-back-bytes`、`demuxer-readahead-secs`、`cache=yes`、`cache-secs`、`cache-pause-initial=no`：`lib/services/audio/media_kit_audio_service.dart:248` 到 `lib/services/audio/media_kit_audio_service.dart:285`。
- 測試固定這組 buffer profile：`test/services/audio/media_kit_audio_service_buffer_test.dart:5` 到 `test/services/audio/media_kit_audio_service_buffer_test.dart:23`。

Trigger scenario：YouTube Mix 長時間播放、VPN/CDN 抖動、快速切歌、或 muxed fallback stream；每首歌都可能讓 libmpv/native cache 有短期高水位。

User impact：大 buffer 可以降低 CDN stall，但可能提高 RSS/native memory 峰值。`vid=no`/`sid=no` 降低 muxed stream 風險，但仍需確認快切與 Mix load-more 時 mpv cache 是否及時釋放。

Suggested measurement or fix：
- 以 profile mode 在 Windows 真機播放 YouTube Mix 30-60 分鐘，記錄 VM `_currentRSS`、`_maxRSS`、Dart `externalUsage`，並同步記錄每次切歌前後。
- 用同一 playlist A/B 比較 32/24/8MB 與較保守 profile 的 stall 次數、RSS 峰值、首次播放 latency。
- 若 RSS 高水位不回落，再考慮平台/網路條件式 buffer profile；目前不建議只因靜態值偏大就降低。

Instruction docs accuracy notes：`lib/services/audio/AGENTS.md` 對桌面 aggressive buffer profile 的描述與實作、測試一致；屬於準確規範，不是 drift。

### 5. `AudioController.dispose()` 觸發 async backend dispose 但沒有 await/錯誤接收

Status：suspected issue

Evidence：
- `AudioController.dispose()` 是同步 `void`，其中直接呼叫 `_audioService.dispose()`，沒有 await 或 error handling：`lib/services/audio/audio_provider.dart:521` 到 `lib/services/audio/audio_provider.dart:543`。
- `MediaKitAudioService.dispose()` 是 async，會取消多個 subscription、close 多個 controller，再 `await _player.dispose()`：`lib/services/audio/media_kit_audio_service.dart:443` 到 `lib/services/audio/media_kit_audio_service.dart:467`。
- `JustAudioService.dispose()` 同樣是 async，會取消 subscription、close controller、`await _player.dispose()`：`lib/services/audio/just_audio_service.dart:284` 到 `lib/services/audio/just_audio_service.dart:306`。
- Provider 目前由 `AudioController` owns backend dispose；`audioServiceProvider` 本身沒有 `ref.onDispose()`：`lib/services/audio/audio_provider.dart:3175` 到 `lib/services/audio/audio_provider.dart:3181`。
- dispose safety 測試覆蓋 provider double-dispose 與 service repeat dispose，但沒有驗證 real backend async dispose error 是否被觀測：`test/services/audio/audio_service_dispose_test.dart:75` 到 `test/services/audio/audio_service_dispose_test.dart:129`、`test/services/audio/audio_service_dispose_test.dart:207` 到 `test/services/audio/audio_service_dispose_test.dart:218`。

Trigger scenario：應用關閉、provider container dispose、或開發期 hot restart 時，backend dispose 的 native player 或 stream cancel 發生錯誤。

User impact：大多數情況 cleanup 仍會開始執行；風險在於 async dispose failure 可能成為 unhandled async error，或關閉時 native resource 釋放完成時間不可觀測。這對 release 關閉流程通常低風險，但對長時間播放後資源釋放驗證不利。

Suggested measurement or fix：
- 在 provider dispose 中用 `unawaited(_audioService.dispose().catchError(...))` 明確記錄錯誤；或讓 service provider own dispose 並集中處理 async cleanup。
- 對 fake async backend 補一個「dispose Future throws」測試，確認錯誤被 logging 而非未處理。

Instruction docs accuracy notes：AGENTS 只要求 preserve resources 與 dispose safety，沒有指定 async backend dispose ownership；目前測試能證明 repeat dispose safety，但不能證明 native async cleanup error path。

## Notable non-findings

- `MediaKitAudioService` 與 `JustAudioService` 的 stream subscription 都集中在 `_subscriptions`，dispose 時逐一 cancel，controller 也 close；未看到明顯未取消 subscription。
- `AudioController` 的 retry timer 使用 `_retryGeneration` 與 track key 防 stale，`dispose()` 會 `_cancelRetryTimer()` 與取消 network recovery subscription。
- completion fallback timer 每 1 秒檢查一次，`dispose()` 會取消；自然完成與 premature completion 的分流有測試覆蓋。
- `QueueManager` 每 10 秒保存 position，`dispose()` 取消 timer；`test/services/audio/queue_manager_test.dart:111` 覆蓋 dispose 後 periodic saver 不再繼續。
- YouTube Mix 在 queue 尾端 pending load-more 時會等待 `_mixLoadMoreFuture`，避免自然完成先結束；有 `test/services/audio/audio_controller_mix_boundary_test.dart:265` 覆蓋。

## 建議 profiling 腳本焦點

- Windows profile mode：播放 YouTube Mix 30-60 分鐘，開/關歌詞彈窗各一次，記錄 RSS、externalUsage、frame jank、platform channel call count。
- 快速切歌：連續點 next 20 次，每次間隔 100-300ms，觀察 backend error、舊歌是否短暫復活、RSS 是否回落。
- 網路不穩：VPN 切換或限速，確認 runtime error 走 current-track retry，並觀察 `_retryGeneration` 是否阻止 stale retry。
- Radio coexistence：保留 radio context 後播放音樂，觀察 broad `audioControllerProvider` watch 的 rebuild/callback。
