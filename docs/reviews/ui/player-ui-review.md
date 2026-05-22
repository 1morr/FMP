# Player UI 專項審查報告

## Findings

1. 類型：bug；嚴重度：中；文件：`lib/ui/pages/queue/queue_page.dart:234`

   `QueuePage` 直接從 `audioControllerProvider.select((s) => s.queue)`、`currentIndex`、`queueVersion`、`isMixMode`、`mixTitle`、`isLoadingMoreMix` 讀取 queue 狀態。音訊層已建立 `queueStateProvider` / `queueProvider` 作為 queue UI 的同步來源，且現有測試明確要求 `queueProvider` 跟隨 `queueStateProvider`，不是 `PlayerState.queue`。這讓 queue page 可能在 controller 狀態與 queue 專用 provider 分離時顯示過期或不一致的隊列、Mix 載入狀態與目前播放索引。

2. 類型：重構機會；嚴重度：低；文件：`lib/ui/widgets/lyrics_display.dart:165`

   `LyricsDisplay.build()` 期間偵測 `matchId` 變化並直接修改 `_lastMatchId`、`_currentLineIndex`、`_isFirstBuild`、`_userScrolling`，同時取消 `_scrollResumeTimer`。目前沒有直接呼叫 `setState()`，所以不是立刻觸發 build-loop 的 bug；但這仍把歌詞匹配切換的副作用放在 build path，狀態邊界不清楚，後續如果加入更多 reset 邏輯容易造成難追的 rebuild 或 timer 行為。

## Evidence

- 已讀取並套用 `AGENTS.md`、`lib/ui/AGENTS.md`、`lib/services/audio/AGENTS.md`、`lib/providers/AGENTS.md`、`docs/README.md`；補充讀取 `.serena/memories/refactoring_lessons.md`、`ui_coding_patterns.md`、`code_style.md`。其中音訊規則要求 UI playback controls 只能呼叫 `AudioController`，queue/shuffle/loop 必須使用 provider/controller state，progress slider 不得在 `onChanged` seek。
- `rg -n "audioServiceProvider|FmpAudioService"` 在 `lib/ui/pages/player/player_page.dart`、`lib/ui/widgets/player/mini_player.dart`、`lib/ui/pages/queue/queue_page.dart`、`lib/ui/widgets/lyrics_display.dart` 未找到 UI 直接使用 backend service。播放、暫停、上一首、下一首、shuffle、loop、seek、queue 移動與清空都透過 `ref.read(audioControllerProvider.notifier)` 或傳入的 `AudioController` 呼叫，例如 `player_page.dart:500`、`player_page.dart:510`、`player_page.dart:528`、`player_page.dart:535`、`player_page.dart:583`，以及 `queue_page.dart:220`、`queue_page.dart:306`、`queue_page.dart:435`、`queue_page.dart:436`、`queue_page.dart:463`。
- Full player progress bar 符合規則：`player_page.dart:447` 的 `Slider.onChanged` 只更新本地 `_dragProgress`，實際 `controller.seekToProgress(value)` 只在 `player_page.dart:451` 的 `onChangeEnd` 執行。
- Mini player progress 不是 Flutter `Slider`，但拖曳流程同樣只在結束時 seek：`mini_player.dart:163` 更新 `_dragProgress`，`mini_player.dart:171` 才呼叫 `seekToProgress`。`mini_player.dart:181` 的 tap-to-seek 是一次性點擊操作，不是拖曳期間高頻 seek。
- Playing state 在 player/mini player 控制列使用 controller state：`player_page.dart:92` select 出 `isPlaying`，`mini_player.dart:322` select `s.isPlaying`。Queue list 的高亮使用 `index == currentIndex`（`queue_page.dart:421`），這是隊列頁自身語境下合理的目前隊列項判斷。
- Queue 專用 provider 的程式碼與測試支持第一個 finding：`audio_provider.dart:54` 定義 `QueueState`，`audio_provider.dart:115` 定義 `queueStateProvider`，`audio_provider.dart:3059` 將 controller 的 queue callback 寫入 `queueStateProvider`，`audio_provider.dart:3115` 讓 `queueProvider` 讀 `queueStateProvider.select((s) => s.queue)`。`test/services/audio/audio_queue_state_provider_test.dart:50` 的測試名稱與斷言明確指出 `queueProvider follows queueStateProvider instead of PlayerState queue`。
- 歌詞顯示已避免最重的每 tick rebuild：`lyrics_provider.dart:250` 的 `currentLyricsLineIndexProvider` 只公開目前行 index，註解在 `lyrics_provider.dart:247` 說明 position tick 可重算但 dependents 只應在整數行變化時通知；`lyrics_display.dart:262` 使用該 provider，而不是直接 watch raw playback position。
- 歌詞狀態有清楚的使用者狀態分支：載入中 `lyrics_display.dart:177`、自動匹配中 `lyrics_display.dart:184`、無歌詞 `lyrics_display.dart:200`、載入錯誤 `lyrics_display.dart:204`、純音樂 `lyrics_display.dart:224`、無可解析內容 `lyrics_display.dart:241`、同步/純文字歌詞 `lyrics_display.dart:246` / `lyrics_display.dart:252`。
- 圖片規則未見違反：審查範圍內未找到 `Image.network()` 或 `Image.file()`；player cover 使用 `TrackCover`（`player_page.dart:366`），mini/queue 使用 `TrackThumbnail`（`mini_player.dart:274`、`queue_page.dart:526`），作者頭像使用 `ImageLoadingService.loadAvatar()`（`player_page.dart:1036`、`player_page.dart:1064`）。

## User impact

- QueuePage 狀態來源不一致時，使用者可能看到的隊列順序、目前播放列、Mix 載入中提示或總數不是音訊層實際發布給 UI 的 queue state。音樂播放器的直接影響是：點選 queue item、移除歌曲、清空隊列或在 Mix 動態載入時，頁面可能短暫或持續呈現錯誤上下文。
- 歌詞 reset 副作用放在 build 中目前風險較低，但會增加後續維護成本；如果將來在該區塊加入 provider 寫入、動畫控制器或 `setState()`，就容易造成多餘 rebuild、timer 取消時機不穩，影響歌詞滾動與手動瀏覽體驗。

## Suggested direction

- QueuePage 應改為讀 `queueStateProvider` 或現有 queue selector providers：`queueProvider`、`queueVersionProvider`、`queueTrackProvider`，並補齊 `currentIndex`、`isMixMode`、`mixTitle`、`isLoadingMoreMix` 等 selector（若尚未有）。queue 操作本身仍維持透過 `audioControllerProvider.notifier` 呼叫 `moveInQueue()`、`playAt()`、`removeFromQueue()`、`shuffleQueue()`、`clearQueue()`。
- QueuePage 的本地 `_localQueue` 可保留作為拖曳防閃爍快取，但同步依據應改成 `queueStateProvider.queueVersion`，避免從 `PlayerState.queueVersion` 取值。
- LyricsDisplay 的 `matchId` reset 建議移到 `ref.listen(currentLyricsMatchProvider, ...)`、`didUpdateWidget` 能涵蓋的 lifecycle，或抽成明確的 `_resetForMatch()` 並確保不在 build 期間擴張副作用。
- 若要補測，建議新增 queue page 靜態或 widget 測試：驗證頁面資料來源包含 `queueStateProvider` / `queueProvider`，並避免直接 watch `audioControllerProvider.select((s) => s.queue)`；同時保留既有 reorder 測試覆蓋 shuffle 模式仍可拖曳。

## Instruction docs accuracy notes

- `lib/services/audio/AGENTS.md` 的「UI must use `upcomingTracks` / provider state instead of calculating next track order manually」與目前音訊層 `queueStateProvider` 設計方向一致，但沒有明確點名 QueuePage 應讀 `queueStateProvider` / `queueProvider` 而不是 `PlayerState.queue`。若修正 QueuePage，建議在該段或 `lib/ui/AGENTS.md` 補一句 queue UI 的狀態來源。
- `.serena/memories/ui_coding_patterns.md` 第 11 節寫「新代碼禁止硬編碼值」，比 `lib/ui/AGENTS.md` 的「small local layout/animation literals are acceptable」更嚴格；本次審查以 `AGENTS.md` 為準，未把播放器頁既有局部 layout 數值列為 finding。
- `docs/README.md` 的文檔權威說明與實際讀取結果一致：當記憶檔與 AGENTS 可能衝突時，AGENTS 和當前程式碼應優先。
