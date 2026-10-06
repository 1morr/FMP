# E19：音量、速度、輸出裝置與 Android 音訊中斷（M2 PR 13）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §7.6（`AudioBackend` 加的成員、能力宣告、偏好裝置、速度、音量、Android 音訊中斷與拔耳機、契約測試的音量與速度兩條）、§3.3（`output_device_id`、`output_device_name`，表已在 PR 10 建好）、§7.5「桌面輸出裝置失敗：暫停並提示，不跳過」、§7.9（`OutputDeviceFailed` 事件）。執行清單在父任務 `implement.md`「13.」。本檔只列做什麼與驗收。

## 目標

播放核心能調音量、靜音、速度、（Windows）選輸出裝置；Android 被別的 App 搶走音訊焦點、來電、拔耳機時照使用者預期暫停、降音量或續播。**UI 入口不在這個 PR**：播放列的音量、靜音、輸出裝置在 PR 17，速度選單在播放頁（PR 18a），音量與靜音的持久化在 PR 14（`player_state`）。

## 做什麼

1. **`AudioBackend`**：`setVolume(double)`（0–1，換來源與前瞻交接後維持）、`setSpeed(double)`（夾到 0.5–2.0，換來源後維持）、`OutputDevices? outputDevices`（只有 Windows 不為空：裝置清單 stream、目前裝置、`select(device?)`，空＝系統預設）。假後端同步。
2. **能力宣告**：`PlaybackSupport.outputDeviceSelection`（`lib/platform/audio/`），Windows 真、Android 假；組裝點的 `assert` 讓宣告與 `outputDevices` 是否為空一致（ADR 0009 §如何確認）。
3. **`JustAudioBackend`**（Android）：
   - `AudioPlayer(handleInterruptions: false)`，後端自己聽 `audio_session`；`audio_session` 改為直接依賴（本來是傳遞依賴），擁有者 `lib/playback/backends`（依賴擁有者的規則照 `app/AGENTS.md`）。
   - duck：後端內部把實際輸出乘 0.5，結束還原，不改使用者音量（理由：just_audio 0.10.6 的內建處理在 duck 結束時無條件把音量乘 2，design §7.6）。
   - 暫停類與 unknown 類中斷：發 `Interrupted`；暫停類中斷結束：發 `InterruptionEnded(resume: true)`；拔耳機（`becomingNoisy`）：發 `BecameNoisy`。
   - 不影響 M1 的「換歌不放音訊焦點」：焦點取得與釋放仍由 `handleAudioSessionActivation` 管。
4. **`MediaKitBackend`**（Windows）：音量（0–100，乘 100）、速度（`setRate`）、裝置清單（`audioDevices` stream）、選擇（`setAudioDevice`、`AudioDevice.auto()`）；mpv 的 `ao` 錯誤 → 發 `OutputDeviceFailed`。
5. **控制器**：`setVolume`、`toggleMute`（記住靜音前的音量，取消靜音回到它）、`setSpeed`、`selectOutputDevice`；中斷事件由控制器決定暫停或續播（控制器是唯一寫狀態的地方）：`Interrupted` → 暫停；`InterruptionEnded(resume: true)` → 只有原本因中斷而暫停才續播；`BecameNoisy` → 只暫停；`OutputDeviceFailed` → 暫停並發事件給外殼提示（不跳過）。
6. **偏好裝置**：存 `playback_settings` 的 `output_device_id`（mpv 的裝置名）與 `output_device_name`（顯示用描述）；裝置清單第一次就緒時套用一次；找不到那個裝置就用系統預設、不清掉偏好。Notifier 加需要的 setter。
7. **契約測試**（`test/playback/backends/audio_backend_contract.dart`，假後端在 `flutter test`、真後端在 `integration_test/audio_backend_contract_test.dart`）：音量、速度在 `open` 之前設定也生效，且在換來源與前瞻交接後維持；速度夾在 0.5–2.0；輸出裝置：Windows 選 `auto` 之後仍在播。
8. **外殼提示**：`OutputDeviceFailed` 經既有 listener 轉成提示，三語言。
9. 文件：`app/AGENTS.md`（§ 播放、§ 平台、依賴擁有者表）、playback／platform spec；每條寫閘門。

## 不做

- 播放列的音量滑桿、靜音鈕、輸出裝置鈕、快捷鍵（PR 17）；速度選單（PR 18a）。
- 音量與靜音的持久化（PR 14 的 `player_state`）。
- 系統媒體控制（PR 16a／16b）。

## 驗收

- [ ] 測試：契約的音量、速度案例；控制器的中斷事件 → 暫停與續播（只有暫停類中斷結束才續播、使用者自己暫停的不會被續播）；拔耳機只暫停；duck 不改使用者音量；靜音與取消靜音；`OutputDeviceFailed` 暫停並提示；宣告與 `outputDevices` 一致（`platform_test.dart`）；偏好裝置不在清單時用預設且不清掉偏好、清單第一次就緒才套用一次。
- [ ] 驗證清單全綠（父任務 implement.md「每個 PR 的固定流程」第 5 步），含兩平台真後端契約。
- [ ] 實機（主對話做；重播）：兩平台跑真後端契約；Android 以另一個 App 或 `adb shell cmd media_session` 觸發焦點中斷，確認暫停與續播；拔耳機（模擬器以 `adb` 送 `ACTION_AUDIO_BECOMING_NOISY` 或等效方式，做不到就記為未驗）；Windows 輸出裝置：有兩個裝置時切換，只有一個時記錄只驗了 `auto`。UI 入口還沒有，音量與速度的實機以契約為準。
