# 0003 — 保留兩個音訊後端

- 狀態：已採納
- 日期：2026-09-24
- 影響範圍：`lib/services/audio/`、`lib/providers/audio/audio_controller_provider.dart`、`pubspec.yaml` 的音訊依賴

## 背景

`FmpAudioService`（`lib/services/audio/audio_service.dart`）後面有兩個實作：
Android 的 `JustAudioService`（just_audio → ExoPlayer），Windows 的
`MediaKitAudioService`（media_kit → libmpv）。`audioServiceProvider` 依
`AudioRuntimePlatform` 選：android / ios 拿前者，其餘拿後者。

兩個後端意味著兩份行為。上層會碰到的差異寫在 `FmpAudioService` 的類別與成員
dartdoc 上（音訊焦點只有 Android、桌面的 `processingStateStream` 是合成的、
`bufferedPositionStream` 的量級、裝置選擇只有桌面、`playMedia` 回傳的時機），
這裡不重列。

這個形狀改過三次，兩種「統一」都真的走過：

- `4f140894`（2026-01-03）起全平台是 just_audio，Windows 靠 `just_audio_windows`。
  `7fdec08e`（2026-01-10）把它換成 just_audio_media_kit，`pubspec.yaml` 當時的
  註解寫的是為了解決 Windows 上的訊息佇列溢出。
- `2e73d1b8`（2026-01-31）全平台改用 media_kit，Android 也是
  （`media_kit_libs_android_audio`），取代 just_audio + just_audio_media_kit。
  `MediaKitAudioService` 檔頭至今記著原因：just_audio_media_kit 的代理對
  audio-only 流有相容問題。
- `6d39d15c`（2026-02-19）把 Android 拆回 just_audio。那次 commit 記下的理由是
  libmpv 在 Android 比 ExoPlayer 多用約 10–15 MB 記憶體，同一個數字留在
  `pubspec.yaml` 的註解裡。這份 ADR 沒有重新量過它。

Linux / macOS：repo 沒有 `linux/`、`macos/` 目錄，`pubspec.yaml` 寫明不出這兩個
平台。程式裡殘留的分支（`selectAudioRuntimePlatform` 把它們歸到 desktop、
`main.dart` 對它們呼叫 `MediaKit.ensureInitialized()`）建置不出來；在那兩個平台上
`AudioService.init` 不會跑（只有 Android / iOS），`WindowsSmtcHandler` 也不會
初始化，所以沒有任何系統媒體控制。它們不是支援平台。

## 決策

**維持兩個實作。** UI 與控制器只認 `FmpAudioService`。兩邊能收斂的判斷抽成純
規則（`playback_end_reason_rules.dart`、`live_edge_seek_policy.dart`、
`next_media_plan.dart`），由 `test/services/audio/backend_contract_test.dart` 測規則
本身，`test/services/static_rules/audio_backend_shared_rules_static_rule_test.dart`
釘住兩個後端真的轉呼叫它們、沒有各留一份關鍵字表。收斂不了的差異寫進介面
dartdoc。

**只在有新證據時重新評估統一。** 下面的否決理由有任何一條不再成立 —— 例如
Windows 的 libmpv 有了維護中的來源、或出現一個只有換後端才修得掉的缺陷 —— 才
重開這題。

## 被否決的替代方案

### 統一到 media_kit

- **修不到 Windows 的任何問題。** Windows 本來就是 media_kit；統一只會動到
  目前沒有問題的 Android。
- **Android 的音訊焦點要重做。** 來電 duck、中斷暫停、拔耳機暫停都寫在
  `JustAudioService.initialize()` 裡，透過 `audio_session` 監聽。`audio_session`
  只為 android、ios、macos、web 出 plugin（pub cache 裡
  `audio_session-0.2.4/pubspec.yaml` 的 `flutter.plugin.platforms`），所以
  `4ff58e86` 把桌面那份從寫好起就沒執行過的處理刪了。換成 media_kit，這段要在
  `MediaKitAudioService` 裡為 Android 重建一次。
- **ExoPlayer 的錯誤分類要重做。** `classifyExoPlayerFailure` 的註解記著它是
  照實測做的：ExoPlayer 把網路層問題壓成 `code=0, message=Source error`，
  所以只看訊息、不看 code。換後端，這份分類換成 `classifyMpvMessage` 那一套，
  Android 上的措辭要重新量。
- **media_kit 的發版與 Windows 原生庫。** pub.dev API 顯示 `media_kit` 最新版
  是 1.2.6（2025-12-13）、`media_kit_libs_windows_audio` 最新版仍是 1.0.9
  （2023-09-27），2026-09-24 查證。`THIRD_PARTY_LICENSES.md` §1 記錄 Windows 的
  `libmpv-2.dll` 是 2023-09-24 的凍結快照、建置它的 repo 已於 2024-10-09 封存。
  把 Android 也押上這條依賴鏈，只是把風險放大到兩個平台。
- 還有 `6d39d15c` 當時記下的記憶體理由，見背景。

### 統一到 just_audio

just_audio 自己不支援 Windows：`just_audio-0.10.6/pubspec.yaml` 的
`flutter.plugin.platforms` 只有 android、ios、macos、web。Windows 只能靠第三方
federated 實作。其中 `just_audio_windows`（0.2.3，WinRT MediaPlayer）的 pub.dev
功能表上 request headers 那一列沒有打勾（2026-09-24 查證），而 FMP 播放時會帶
headers（`MediaKitAudioService` 以 `Media(url, httpHeaders: headers)` 開流）。
這兩條 FMP 都走過：`just_audio_windows` 在 `7fdec08e` 被換掉，
just_audio_media_kit 在 `2e73d1b8` 被換掉（理由見背景）。

### 兩個真後端跑同一份契約測試

現在做得到一半，做不到另一半：

- `MediaKitAudioService` 從 `eef6f1bb` 起接受
  `@visibleForTesting PlatformPlayer? platformPlayer`。
  `test/services/audio/media_kit_audio_service_state_test.dart` 把 libmpv 那層換成
  假引擎，服務本身的狀態合成與開流流程照樣在 `flutter test` 裡執行。
- `JustAudioService` 沒有對應的注入點：`initialize()` 直接建 `ja.AudioPlayer`，
  需要 platform channel。所以同一份斷言跑在兩個真後端上仍然做不到，
  `backend_contract_test.dart` 走的是「判斷抽成純規則」這條路。

## 後果

- 每個播放行為的改動都要想兩次：兩個後端各改一次，或者抽進共用規則。
  新的差異要寫進 `FmpAudioService` 的 dartdoc，不寫就只能到實機上才發現。
- Android 的後端行為只能在模擬器或實機上驗證；桌面後端有一部分能在
  `flutter test` 裡驗。
- Windows 的解碼器停在 2023-09-24 的 FFmpeg。某條串流 Android 能播、Windows
  開不起來時，先懷疑它（`docs/troubleshooting.md` 有一節）。
