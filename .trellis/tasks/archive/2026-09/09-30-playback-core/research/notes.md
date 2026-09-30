# 播放核心（M1 PR 10）研究筆記

2026-09-30。context7 在這個 session 不可用，以 pub.dev API、pub-cache 裡的原始碼
（行號對應下列版本）與上游 repo 查證。

## 1. 套件版本（pub.dev 最新 stable）

| 套件 | 版本 | 發佈 | 用途 |
|---|---|---|---|
| `just_audio` | 0.10.6 | 2026-06-29 | Android 後端（ExoPlayer） |
| `audio_session` | 0.2.4 | 2026-06-29 | just_audio 的傳遞依賴，不直接用 |
| `media_kit` | 1.2.6 | 2025-12-13 | Windows 後端（libmpv），純 Dart＋FFI，沒有 Android 原生碼 |
| `media_kit_libs_windows_audio` | 1.0.9 | 2023-09-27 | Windows 的 libmpv（`mpv-dev-x86_64-20230924-git-652a1dd.7z`，建置時從 GitHub 下載並驗 MD5，見套件的 `windows/CMakeLists.txt`） |
| `fake_async` | 1.3.3 | — | dev：控制器測試的假時間（`flutter_test` 已依賴它，但不 export） |

- media_kit README 建議音訊 App 用 `media_kit_libs_audio`；它的依賴是
  `media_kit_libs_android_audio`、`_ios_audio`、`_macos_audio`、`_windows_audio`、
  `media_kit_libs_linux`（pub.dev API），會把 Android 的 libmpv 打進 APK。ADR 0018
  否決「全平台 media_kit」的理由之一就是這個體積，所以只加 Windows 那一個。

## 2. just_audio（Android）

- **前瞻與 gapless**：0.10.0 起 `ConcatenatingAudioSource` 棄用，改用 player 上的
  playlist API：`setAudioSources`、`addAudioSource`、`removeAudioSourceAt`
  （CHANGELOG 0.10.0；`just_audio.dart:877-947`）。README 的功能表 Android 有
  gapless。`useLazyPreparation` 從 audio source 搬到 `AudioPlayer` 建構子；設
  `false` 讓 ExoPlayer 一接上第二個項目就預備（`just_audio.dart:225-250`）。
- **標頭**：預設經 just_audio 的本機 HTTP proxy 送，需要允許明文流量（README）。
  `useProxyForRequestHeaders: false` 時交給 ExoPlayer：每個 media source 各自的
  `DefaultHttpDataSource.Factory.setDefaultRequestProperties(headers)`
  （`android/.../AudioPlayer.java:638-651, 731-747`）。採用後者，不必開明文流量。
- **asset**：`asset:///<key>` 由 just_audio 先複製到暫存檔再交給引擎
  （`just_audio.dart:2746-2757`）；載不到的 asset 在交給 ExoPlayer 前就拋，不是
  `PlayerException`，所以後端的 `open` 以 `on Object` 接。
- `play()` 的 Future 要到暫停才完成（README 與原始碼），不能 await。
- `playing` 跨 `setAudioSources` 保留：要停在暫停就先 `pause()`。
- 錯誤：0.10 以 `errorStream` 取代 `playbackEventStream.onError`，`PlayerException`
  帶項目的 `index`（CHANGELOG 0.10.0；`just_audio.dart:1810-1836`）。

### Android 音訊焦點（ADR 0018 §決定 3 的「換歌時不釋放」）

- ExoPlayer 自己不管焦點：`player.setAudioAttributes(attrs, false)`
  （`AudioPlayer.java:355, 387, 818`，第二個參數是 `handleAudioFocus`）。
- just_audio 在每次 `play()` 呼叫 `AudioSession.setActive(true)`
  （`just_audio.dart:1098`）；整個套件沒有 `setActive(false)`。
- audio_session 的 Android 端：`requestAudioFocus` 已有請求就直接回 true，不重新
  要求（`AndroidAudioManager.kt:345-347`）；只在收到 `AUDIOFOCUS_LOSS`（353）或
  引擎卸載時的 `dispose`（725）放掉。
- 結論：同一個 `AudioPlayer` 換來源、`stop()`（只卸掉 ExoPlayer）都不放焦點；
  所以整個 App 只建一個 `AudioPlayer`（`audioBackendProvider`），不在換歌時重建。
  實測以 `dumpsys audio` 的焦點堆疊確認（主對話執行）。
- 不另外 import `audio_session` 記焦點事件：焦點只在別的 App 搶走時才變，實機以
  `dumpsys audio` 看比 log 準；需要時（M2 的中斷處理）再加依賴與 owner。

## 3. media_kit（Windows）

- `Player.open(Playlist([...]))`、`add(Media)`、`remove(index)`，都經內部 lock 序列化；
  `remove` 自己調整目前的索引並以同一份 `Media` 物件清單發 `playlist` 事件
  （`native/player/real.dart:137-235, 455-560`）。所以以 `Expando` 從 `Media` 實例
  對回來源 id，不用網址（不同來源可以同網址，例如測試插件的三首都是同一個音檔）。
- **標頭**：`Media(uri, httpHeaders:)` 存進以網址為鍵的全域快取，在 mpv 的
  `on_load` hook 設成 per-file 的 `http-header-fields`（`real.dart:2124-2175`、
  `media_native.dart:104-120`）。同一個網址只有一組標頭。
- **前瞻**：mpv 的 `prefetch-playlist` 預設 `no`，media_kit 不設；後端設成 `yes`。
  mpv 手冊說它 "Highly experimental"、用 per-file 選項時可能不準；舊專案
  （`lib/services/audio/media_kit_audio_service.dart:241-250`）以只認正確 Referer 的
  本機伺服器實測過前瞻開流帶的標頭是對的。
- **結束與交接**：media_kit 用 `keep-open=yes`，`completed` 來自 `eof-reached`；
  目前項目來自 `playlist-playing-pos`（`real.dart:1604-1618, 1943-1960`）。有下一個
  項目時 mpv 自己接上，`completed` 可能在換檔的瞬間閃一下（Namida 的
  `custom_mpv_player.dart` 有同樣的註解），所以有前瞻時忽略它。
- **錯誤**：只有 log 行（`file`、`ffmpeg` 的 `tcp:`、`ad`、`vd`、`cplayer`、`stream`
  前綴的 error 級），不帶項目（`real.dart:2060-2117`）。
- **屬性事件只在值改變時發**（本 PR 的 Windows 整合測試發現）：兩個一樣長的檔案，
  接上前瞻後不會再收到 `duration`。後端交接時先沿用 `player.state.duration`。
- `MediaKit.ensureInitialized()` 可以延到第一次建立 `Player` 前才呼叫（只載入
  libmpv），不必在 `main()`。
- `PlayerConfiguration.title` 是 Windows 音量混合器顯示的名稱，預設
  `package:media_kit`，改成 `FMP`。

## 4. 參考實作與採用的慣例（ADR 0018 列的三個）

- **Namida**（`namidaco/namida@5cb84bfa52`，`lib/class/custom_mpv_player.dart`）：
  一個播放器介面（`AVPlayer`），ExoPlayer 與 mpv 兩個實作；前瞻用
  `addMediaNext`（只保留「目前＋一個」：加在目前之後，再移掉尾巴與已播的頭）與
  `removeAllMediaNext`；gapless 交接以「清單索引移到排隊的那個 `Media`（identical）」
  判斷並發 `autoTransition` 事件。**採用**：`AudioBackend` 的 `open`／`setNext`、
  後端以物件身分判斷交接並發 `SourceAdvanced`。
- **Harmonoid**（`harmonoid/harmonoid@2b021f7b0b`，`lib/core/media_player/`）：
  `MediaPlayer` 單例直接包 media_kit 的 `Player`，播放清單在 media_kit 裡，系統媒體
  控制、audio_session、Discord 等以 mixin 註冊、由狀態推送。M1 沒有系統媒體控制；
  它的「推送去重與序列化」留給 M2 的 `NowPlayingPublisher`（ADR 0018 §決定 8）。
  佇列真相在原生清單這點是 ADR 0018 否決的，不採用。
- **Finamp**（`jmshrv/finamp`，`lib/services/music_player_background_task.dart`）：
  `BaseAudioHandler`（audio_service）包一個 just_audio `AudioPlayer`，整個佇列放進
  `ConcatenatingAudioSource`。同樣是原生清單當真相，不採用；audio_service 的接法
  留給 M2。
- **舊專案**（`lib/services/audio/`）：`playback_end_reason_rules.dart` 的
  `classifyCompletion`（時長沒回報＝提前結束、容忍 1.5 秒）與
  `next_media_plan.dart` 的 `NextMediaPlan` 照搬成 `backend_rules.dart` 的
  `classifyTrackEnd`、`LookAheadEdit`（ADR 0008：葉節點照搬）。mpv／ExoPlayer 錯誤
  訊息的分類表（輸出裝置、傳輸、開不起來、解碼）M1 不搬：M1 只分「還沒載入就失敗
  （換候選）」與「播放中中斷（重試）」，輸出裝置失敗的處理在 ADR 0018 §決定 7，
  屬 M2。

## 5. 實測（本 PR 內做的）

- Windows（media_kit 真後端）：`flutter test integration_test/audio_backend_contract_test.dart -d windows`
  7/7 通過（第一次跑抓到 §3 的 duration 問題，修正後通過）。
- Android（just_audio 真後端）：同一個檔案 `-d emulator-5554`，由主對話執行（本
  session 的模擬器同時被別的 worktree 使用，跑整合測試會覆蓋它安裝的 dev App）。
