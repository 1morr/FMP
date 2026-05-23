# Audio Architecture Review

審查日期：2026-05-22

## Findings

1. **P1 - backend error-stream retry 在 `stop()` 非同步完成後缺少 stale guard**

   `AudioController._onAudioError()` 會先擷取當前 `track`，再呼叫 `_audioService.stop().then(...)`，但 `.then()` / `.catchError()` 內沒有確認目前播放請求、目前 track、或 retry generation 仍是同一個。若 backend `stop()` 因平台 I/O、media_kit 狀態切換、或 audio focus 等原因延後完成，使用者在這段期間啟動另一個播放請求時，舊錯誤 callback 仍會執行 `state.copyWith(isLoading: false, isPlaying: false)`、`_resetLoadingState()` 與 `_scheduleRetry(oldTrack, oldPosition)`。這會讓舊 track 的網路錯誤污染新 track 的播放狀態。

   證據：`lib/services/audio/audio_provider.dart:2711` 取得 `state.playingTrack`；`lib/services/audio/audio_provider.dart:2735` 保存 stop 前位置；`lib/services/audio/audio_provider.dart:2739` 到 `lib/services/audio/audio_provider.dart:2748` 在 stop completion callback 內無條件 reset/loading/retry。規範要求 backend error-stream retry suppression 要 generation/current-track aware，見 `lib/services/audio/AGENTS.md:116`。

   建議方向：不要做大規模重構；在 `_onAudioError()` 這個 module 的局部加入 request/generation/current-track guard 即可。具體方向是：排 stop 前建立一個 error handling generation 或擷取 `_playRequestId` + `track.uniqueKey`，在 `.then()` / `.catchError()` 內先確認 controller 未 dispose、`state.playingTrack?.uniqueKey` 仍相同、且沒有較新的播放請求；不成立時直接 return。測試應補一個 pending-stop fake，覆蓋「error stop 尚未完成時使用者播放新 track，舊 retry 不得覆蓋新狀態」。

2. **P2 - `startMixFromPlaylist()` 在 Mix metadata fetch 期間沒有 supersession**

   `startMixFromPlaylist()` 會先等待 `fetcher(...)` 回傳 Mix tracks，然後才呼叫 `playMixPlaylist()`。這段 async work 不在 `_executePlayRequest()` 內，也沒有使用 `_playRequestId` / `_isSuperseded()` 或獨立 generation。若使用者點擊 Mix 後又立即播放其他歌曲，較舊的 Mix fetch 回來後仍會清空 queue 並開始 Mix playback。

   證據：`lib/services/audio/audio_provider.dart:927` 到 `lib/services/audio/audio_provider.dart:930` 等待 Mix tracks；`lib/services/audio/audio_provider.dart:936` 到 `lib/services/audio/audio_provider.dart:941` 無 supersession 檢查就進入 `playMixPlaylist()`。實際 UI 入口會 await 這個 method，見 `lib/ui/widgets/playlist_card_actions.dart:73` 到 `lib/ui/widgets/playlist_card_actions.dart:75`；playlist detail 也可直接呼叫 `playMixPlaylist()`，見 `lib/ui/pages/library/playlist_detail_page.dart:1052` 到 `lib/ui/pages/library/playlist_detail_page.dart:1058`。規範對「不走 `_executePlayRequest()` 的 async URL/播放準備流程」要求使用 request id 與 await 後 supersession check，見 `lib/services/audio/AGENTS.md:103`。

   建議方向：保持現有 `AudioController` interface，不新增大型 seam。只需把 Mix-start 視為一個可被取代的播放意圖：在 fetch 前建立 request/generation，fetch 後、呼叫 `playMixPlaylist()` 前檢查是否仍 current；若已被新播放意圖取代就靜默 return。若要在 UI 顯示 loading，也應使用現有 loading state，而不是引入另一組平行旗標。

3. **P3 - UI playback seam 目前維持良好，不建議為了形式再抽新 adapter**

   本次搜尋未發現 `lib/ui` 直接讀取 `audioServiceProvider`、`FmpAudioService`、`JustAudioService`、`MediaKitAudioService`，也未發現 UI 直接呼叫 backend `playUrl()` / `playFile()`。UI playback controls 目前主要經 `audioControllerProvider` 或 `TrackActionCoordinator` 進入 `AudioController`，這符合文件期望；`RadioController` 直接使用 shared backend 是文件明確列出的非 UI 例外。

   證據：`lib/ui/handlers/track_action_coordinator.dart:23` 到 `lib/ui/handlers/track_action_coordinator.dart:26` 透過 `AudioControllerTrackActionAdapter(ref.read(audioControllerProvider.notifier))`；`lib/ui/pages/home/home_page.dart:475` 到 `lib/ui/pages/home/home_page.dart:477` 經 controller pause/resume；`lib/ui/pages/search/search_page.dart:856` 到 `lib/ui/pages/search/search_page.dart:862` 經 controller temporary play。radio 例外在 `lib/services/radio/radio_controller.dart:1124` 讀 `audioServiceProvider`，並在 `lib/services/radio/radio_controller.dart:397` 到 `lib/services/radio/radio_controller.dart:404` 設定 ownership hook，符合 `lib/services/audio/AGENTS.md:32` 與 `lib/services/AGENTS.md:99`。

   建議方向：不建議新增 compile-time UI facade 或拆分 UI adapter。現在的 module depth 主要來自 `AudioController` interface 對 UI 隱藏 queue、temporary、retry、notification/SMTC 等 implementation；多加一層 pass-through adapter 會降低 locality，且不能直接降低上述兩個競態風險。應維持 `rg` review 規則即可。

## Evidence

- 規範性要求：
  - UI 不可繞過 `AudioController`：`AGENTS.md:99`、`AGENTS.md:109` 到 `AGENTS.md:111`、`lib/services/audio/AGENTS.md:28`。
  - Radio 是非 UI 例外：`lib/services/audio/AGENTS.md:32`、`lib/services/AGENTS.md:99`。
  - `_PlaybackContext.activeRequestId > 0` 是 loading request 來源：`lib/services/audio/AGENTS.md:96`；實作在 `lib/services/audio/audio_provider.dart:151` 到 `lib/services/audio/audio_provider.dart:152`。
  - request supersession 規則：`lib/services/audio/AGENTS.md:103` 到 `lib/services/audio/AGENTS.md:105`；實作核心在 `lib/services/audio/audio_provider.dart:1798` 到 `lib/services/audio/audio_provider.dart:1799` 與 `lib/services/audio/audio_provider.dart:1885` 到 `lib/services/audio/audio_provider.dart:1888`。
  - retry/current-track awareness：`lib/services/audio/AGENTS.md:116`；目前大部分 retry path 使用 generation，見 `lib/services/audio/audio_provider.dart:2175` 到 `lib/services/audio/audio_provider.dart:2226`，但 `_onAudioError()` stop callback 缺少同等 guard。

- 描述性內容，已用程式碼驗證：
  - `docs/development.md:36` 與 `docs/development.md:159` 摘要 UI -> `AudioController` -> backend 的形狀；`lib/services/audio/audio_provider.dart:3016` 到 `lib/services/audio/audio_provider.dart:3038` 驗證 provider 確實把 `FmpAudioService`、`QueueManager`、`AudioStreamManager` 組進 `AudioController`。
  - `.serena/memories/refactoring_lessons.md:11` 到 `.serena/memories/refactoring_lessons.md:18` 提醒 supersession、loading context、JustAudio play 不等待；現況在 `lib/services/audio/just_audio_service.dart:506` 到 `lib/services/audio/just_audio_service.dart:510`、`lib/services/audio/audio_provider.dart:1936` 到 `lib/services/audio/audio_provider.dart:1952` 可驗證。
  - `.serena/memories/ui_coding_patterns.md:502` 說搜尋/排行榜/探索使用 `playTemporary()`；實際例子包括 `lib/ui/pages/explore/explore_page.dart:235`、`lib/ui/pages/home/home_page.dart:619`、`lib/ui/pages/search/search_page.dart:856`。

- 測試覆蓋觀察：
  - 已有 superseded playback request 測試：`test/services/audio/audio_controller_phase1_test.dart:400` 到 `test/services/audio/audio_controller_phase1_test.dart:461`。
  - 已有 retry handoff 新錯誤測試：`test/services/audio/audio_auth_retry_phase4_test.dart:166` 到 `test/services/audio/audio_auth_retry_phase4_test.dart:201`。
  - 但 fake backend 只有 pending `playUrl` / `setUrl` / `seek` gate，見 `test/support/fakes/fake_audio_service.dart:63` 到 `test/support/fakes/fake_audio_service.dart:78`；`stop()` 是立即完成，見 `test/support/fakes/fake_audio_service.dart:262` 到 `test/support/fakes/fake_audio_service.dart:270`，因此沒有覆蓋 P1 的 pending-stop race。

## Risk

- P1 風險最高：它發生在 runtime backend error stream，且 media_kit 文件與現有規範都承認網路轉換、VPN/CDN stall、`ffurl_read` 類錯誤會走這條 path。失敗型態不是單純重試失敗，而是舊 track retry state 覆蓋新播放，可能導致 UI 顯示新歌但 retry 舊 URL、loading 提早消失、或手動 retry 目標錯誤。
- P2 風險中等：需要使用者在 Mix fetch 未完成前切換播放意圖，或 source fetch 延遲。發生後會清空 queue 並進入 Mix mode，影響面較大，但入口較少且較容易用局部 generation 修正。
- UI direct backend 風險目前低：搜尋未看到違規 direct call；不建議以低風險為理由引入大規模 module 拆分。

## Suggested direction

- 優先修 P1：在 `_onAudioError()` 補 stale guard，並新增 pending-stop regression test。這是最小改動，能直接提升 retry path locality。
- 接著修 P2：讓 `startMixFromPlaylist()` 使用現有播放 request/supersession 模式，fetch 後確認仍是最新播放意圖再進入 `playMixPlaylist()`。
- 保持 `AudioController` 作為 UI-facing module；保留 `PlaybackRequestExecutor`、`AudioStreamManager`、`QueueManager` 這些 internal seams。現有 module 已經把 backend adapter、stream selection、queue order 分開，問題集中在少數 async handoff 缺 guard，不需要大規模拆分。
- 測試最小集：`flutter test test/services/audio`。若改到 stream selection/header 則再加 `flutter test test/data/sources`；本次僅產出 review，未執行測試。

## Instruction docs accuracy notes

- `lib/services/audio/AGENTS.md` 的架構描述大致準確：`audioServiceProvider` 選擇 `JustAudioService` / `MediaKitAudioService`，見 `lib/services/audio/audio_provider.dart:2967` 到 `lib/services/audio/audio_provider.dart:2975`；`QueueManager` 管 shuffle/loop/upcoming，見 `lib/services/audio/queue_manager.dart:98` 到 `lib/services/audio/queue_manager.dart:128`、`lib/services/audio/queue_manager.dart:671` 到 `lib/services/audio/queue_manager.dart:720`。
- `completedStream` 不是自然完成的提醒是準確的；實作會在 loading/retry/network-error 時忽略 completion，並在尚未接近 duration 時排 retry，見 `lib/services/audio/audio_provider.dart:2752` 到 `lib/services/audio/audio_provider.dart:2771`。
- `Progress slider onChanged` 規範目前未發現違反：主播放器 slider 在 `onChanged` 只更新 local state，`onChangeEnd` 才 seek，見 `lib/ui/pages/player/player_page.dart:447` 到 `lib/ui/pages/player/player_page.dart:453`。`MiniPlayer` 是自訂 gesture progress bar，drag end / tap seek 見 `lib/ui/widgets/player/mini_player.dart:171` 到 `lib/ui/widgets/player/mini_player.dart:183`，不屬於 `Slider.onChanged` 直接 seek。
- `toggleMute()` 規範目前符合：播放器與 mini player mute button 使用 `toggleMute()`，見 `lib/ui/pages/player/player_page.dart:786`、`lib/ui/widgets/player/mini_player.dart:586`；volume slider 使用 `setVolume(value)` 調整音量，見 `lib/ui/pages/player/player_page.dart:805`、`lib/ui/widgets/player/mini_player.dart:604`。
- docs corpus 的權威順序清楚：`docs/README.md:15` 到 `docs/README.md:19` 說明 `AGENTS.md` 是 agent 規則權威、`docs/development.md` 是 onboarding 摘要、`.serena/memories/` 只應作窄補充。這與本次「規範性要求作期望設計、描述性內容需代碼驗證」的審查方式一致。
