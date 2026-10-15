# Android 的播放鍵、暫停鍵不再切換（#233）

## 現象與原因

已暫停時收到 `KEYCODE_MEDIA_PAUSE` 會開始播放；播放中收到 `KEYCODE_MEDIA_PLAY` 會暫停。
`audio_service` 0.18.19 的 `MediaSessionCallback.onMediaButtonEvent` 把真的 PLAY、PAUSE 鍵都轉成
`MediaButton.media`，Dart 端的 `click` 只能切換；上游沒有修。

## 決定（擁有者，2026-10-15）

App 內以反射修，不 fork 套件。繼承 `AudioService` 不可行：套件以 `AudioService.class` 找服務
（`AudioServicePlugin` 的 `ComponentName`、`enterPlayingState` 的 Intent），所以改成服務建好後換掉
`mediaSession` 的 callback（`MediaKeyFix.java`），由 Dart 經 `fmp/media_keys` 在 init 後與每次非 idle 的
publish 時安裝（冪等）。

## 結果

- PLAY → 播、PAUSE → 停；PLAY_PAUSE、耳機鍵、上一首、下一首、通知按鈕照舊。
- R8 keep 規則、`audio_service` 0.18.19 版本釘住測試、ADR 0018 補充、`app/AGENTS.md`。
- 審查（opus）：沒有阻擋；補了改名與註解。已知限制（`app/AGENTS.md`）：
  App 行程不在時以媒體鍵喚起的服務沒有這個頻道，要等打開 App 後的下一次 publish；服務被系統重建後也一樣。
- Android 模擬器（dev debug，重播 `fmp-test`，沒有真實請求），`adb shell input keyevent` 與 `dumpsys media_session`：
  播放中 PLAY → 仍播；PAUSE → 停；再 PAUSE → 仍停；PLAY → 播；再 PLAY → 仍播；PLAY_PAUSE 兩次 → 停、播；
  NEXT → 換到下一首。logcat 沒有 `MediaKeyFix` 的警告。
