# Windows SMTC 的隨機、循環接上 App 的設定（#263）

## 目標

擁有者 2026-10-15 決定：SMTC（媒體浮層）的隨機、循環鈕按了切換 App 的設定，狀態也同步顯示；
在 Mix 或直播中照 App 的規則處理。M2 起這兩個鈕一直是啟用的，但按了沒反應。

## 現況（讀碼確認）

- `lib/platform/media_controls/media_controls_windows.dart` 只接 `buttonPressStream`；`smtc_windows` 1.1.0 另有
  `shuffleChangeStream`（`Stream<bool>`）、`repeatModeChangeStream`（`Stream<RepeatMode>`：`none`、`track`、`list`）
  與 `setShuffleEnabled`、`setRepeatMode`。兩個事件流是系統送來的**要求**（Rust 端的 `*RequestEvent`），
  套件不會自己改狀態：App 不推新值，SMTC 就維持原本的值。
- SMTC 不能單獨停用這兩個鈕（套件沒有對應的設定）。所以「Mix、直播中停用」在 SMTC 上的做法是**收到不合規則的要求就不理**，
  SMTC 會繼續顯示 App 實際的狀態。
- 指令由 `lib/playback/now_playing_publisher.dart` 的 `_onCommand` 轉給 `PlaybackController`；
  App 的循環依 off → all → one 輪轉（`QueueModel.cycleLoopMode`），Mix 中依 off → one → off（#261）。
  Windows 浮層的循環鈕也依 none → list → track 輪轉，每次送出「下一個」模式。

## 要求

1. **平台介面**（`media_controls.dart`，平台中立）：
   - 新的 `enum MediaRepeat { off, all, one }`；`NowPlaying` 加 `shuffle`（bool）與 `repeat`（`MediaRepeat`），
     納入 `==`、`hashCode`、`copyWith`。
   - 新的指令 `MediaSetShuffle(bool enabled)`、`MediaSetRepeat(MediaRepeat mode)`。
2. **Windows**：把兩個事件流轉成上面的指令；`publish` 時 `shuffle`、`repeat` 和上次推的不同才呼叫
   `setShuffleEnabled`、`setRepeatMode`（停用後重新顯示時要重推，同現有的 `_metadata` 等欄位）。
   對應：`none` ↔ off、`list` ↔ all、`track` ↔ one。寫成可單元測試的純函式（同 `smtcConfigOf` 的寫法）。
3. **Android**：不接（`audio_service` 的通知預設不顯示這兩個鈕；擁有者的決定只說 Windows）。新欄位照收，忽略即可。
4. **發布者**（`now_playing_publisher.dart`）：
   - `_build` 帶入佇列的隨機與循環；直播時也帶佇列的值（SMTC 無法隱藏，畫面上直播版沒有這兩個鈕）。
   - `MediaSetShuffle(e)`：直播中或 Mix 中不理；值和現在相同不理；否則 `controller.setShuffle(e)`。
   - `MediaSetRepeat(m)`：直播中不理；和現在相同不理；Mix 中要求 `all` 時照 App 的 Mix 輪轉
     （`cycleLoopMode()`：off → one、one → off），讓浮層的 none → list → track 在 Mix 中也能到「單曲」；其餘設成 `m`。
     需要新的 `PlaybackController.setLoopMode` 與 `QueueModel.setLoopMode`（Mix 中拒絕 `all`，回傳不變的值）。
   - 不理的要求記一行 debug log（`System media command ignored`，帶指令名稱與原因），不提示使用者。
5. **驗證工具**（`.claude/skills/verify-on-device/scripts/`）：
   - `smtc_command.ps1` 加 `shuffle-on`、`shuffle-off`、`repeat-none`、`repeat-list`、`repeat-track`
     （`TryChangeShuffleActiveAsync`、`TryChangeAutoRepeatModeAsync`，同樣只對 `-Aumid` 精確相符的工作階段）。
   - `smtc_probe.ps1` 多印 `IsShuffleActive` 與 `AutoRepeatMode`（`GetPlaybackInfo()`）。
   - `references/windows.md` 同步。
6. **文件**：ADR 0018（系統媒體控制那一條）加一行補充；`app/AGENTS.md` 的系統媒體控制條目同步。

## 驗收

- 單元測試：Windows 的對應函式、兩個事件流轉指令；發布者對各情況的處理（一般、Mix、直播、相同值）；
  `QueueModel.setLoopMode` 的 Mix 規則。拿掉各項處理時會紅（變異寫在 PR 描述）。
- `dart format`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過。
- **Windows 實機**（dev debug，重播 `fmp-test`，`smtc_probe.ps1 -AppFilter fmp`、`smtc_command.ps1`，不送全域媒體鍵）：
  - App 裡切換隨機、循環，probe 看到 `IsShuffleActive`、`AutoRepeatMode` 跟著變。
  - 以 `smtc_command.ps1` 送 shuffle、repeat 要求，App 的播放頁按鈕跟著變（MSAA 讀 tooltip）。
  - Mix 中：送 shuffle-on 不變；從 off 送 repeat-list 變成「單曲」。
  - 直播中（`live-ok`）：兩種要求都不變。
- Android：不受影響，跑既有測試即可（`now_playing_publisher_test`）。

## 不做

- Android 的隨機、循環鈕。
- SMTC 上的停用（做不到，以不理代替）。

## 結果

- 審查（opus）：沒有要修的；確認 `smtc_windows` 的 Rust 端只把要求轉給 Dart、不自己套用，所以不理的要求不用推任何東西。
- `flutter test` 3415 通過；變異：每條規則拿掉都會紅。
- **Windows 實機**（dev debug，重播 `fmp-test`，`smtc_probe.ps1 -AppFilter fmp`、`smtc_command.ps1`，沒有送全域媒體鍵、沒有真實請求）：
  - App 設循環「全部」→ SMTC `AutoRepeatMode=List`。
  - 送 `repeat-track`、`shuffle-on` → 播放頁循環鈕「單曲」，SMTC `IsShuffleActive=True`。
  - Mix 中：`shuffle-on` 不變（log `reason: mix`）；`repeat-none` → 關；`repeat-list` → 單曲。
  - 直播（`live-ok`）中：`shuffle-on`、`repeat-list` 都不變（log `reason: live`）。
- 留下的：控制器層沒有測 `setLoopMode` 寫進資料庫（與 `cycleLoopMode` 同一條 `queueStates`，審查判斷風險低）。
