# 設計：播放核心（階段二第 13 項）

## 目標

為 `app/` 定下佇列、播放模式、播放狀態機、音訊後端抽象、串流解析與網址過期、錯誤恢復、系統媒體控制，
以及電台／直播繞過播放控制器的例外是否保留。產出 ADR 0018。

依據：parent `prd.md` 階段二第 13 項；`phase2-plan.md`（A5、D1–D10、E12、E13、E19）；ADR 0013、0014、0016、0017 留給本項的部分
（播放層的恢復與跳過、`fmp_periodic_timer_owner` 的播放模組清單）；ADR 0015 §6 標給本項的舊 static-rule
（`audio_backend_shared_rules`、`audio_seam`、`playback_event_routing`）。

## 現況（`research/current-state.md`，已以程式碼核對，另見 `docs/audit/playback.md`）

- `AudioController`（`audio_provider.dart` 2,953 行）已拆出 13 個協作者：`QueueManager`（佇列唯一寫入口）、`PlaybackRequestSession`（請求代際）、
  `PlaybackEventRouter`（純函數，後端事件→23 種動作，唯一判讀失敗的地方）、`PlaybackRecoveryCoordinator`（1/2/4/8/16 秒 ×5）、`PlaybackHandoffGate`、
  `NowPlayingPublisher`（系統媒體控制唯一出口）等。
- 狀態至少 5 份並存；`PlayerState.error` 一欄承載三種內容（音源訊息、例外 `toString()`、開流失敗文案）。
- 佇列：四種模式 `queue／temporary／detached／mix`；UI 幾乎所有點歌走臨時播放（D1）；隨機為非破壞性索引排列（不持久化）；
  「下一首播放」在隨機模式插到隨機位置（`queue_manager.dart:541-547,775-786`）；Mix 只增不減、不檢查上限。
- 兩個後端共用 `FmpAudioService` 介面，**不能收斂的差異寫在介面 dartdoc**（音訊焦點僅 Android、`processingState` 在 Windows 為合成值、`playMedia` 回傳時機不同等）；
  可收斂的規則抽成 4 個純檔並有契約測試（`backend_contract_test.dart`）。gapless 以「當前＋一個前瞻」清單實作（`next_media_plan.dart`）。
- 錯誤恢復：只有 unavailable 且 **queue 模式**才 300ms 後跳下一首，**Mix 完全不跳**（`audio_provider.dart:1955`，D3）；限流只設錯誤不重試（D5）；
  重試次數成功後不歸零；被取代的請求不取消網路工作。
- 系統媒體控制：Android `audio_service`、Windows `smtc_windows`；音訊焦點與拔耳機只有 Android；SMTC 不支援 seek；服務層反向 import `main.dart` 的全域 handler。
- 電台是唯一繞過 `AudioController` 直接操作後端的播放者（`radio_controller.dart:286` 起），靠 `isRadioPlaying` 互斥；
  開電台只暫停音樂、不取消進行中的解析（D8 的競態），`restore()` 路徑也不停電台。
- 其他缺陷：`_navRequestId` 是死碼且與 `.trellis/spec/services/audio.md:70-72` 不一致（不一致）；B 站多 P 只取第一個 cid（`bilibili_source.dart:456-473`）；
  播放中不檢查網址過期。

## 研究結論（`research/prior-art.md`、`research/packages-and-platform.md`）

- Finamp、Spotube、Harmonoid、Namida 都沒有「臨時播放」模式；佇列真相多半放在原生播放清單、Dart 只投影；「一個介面、兩個後端」只有 Namida 做（Android ExoPlayer、桌面 mpv），
  FMP 現有的介面＋dartdoc 差異清單是其中最完整的形狀。插播在隨機模式下錯位是共通坑，各家有解法。錯誤跳過只有 Namida 產品化（7 秒倒數）。直播只有 Namida 有 `isLive` 分支。
- 後端事實（pub.dev，2026-09-27）：`just_audio` 0.10.6、`audio_service` 0.18.19、`audio_session` 0.2.4（均 2026-06，活躍；無 Windows／Linux）；
  `media_kit` 1.2.6（2025-12 最後發版，repo 2026-08 仍活躍），Windows／macOS／iOS 的 libs 停在 2023-09；`smtc_windows` 1.1.0；Linux 用 `audio_service_mpris`。
  media_kit **不內建任何系統整合**（通知、音訊焦點、SMTC、MPRIS、Now Playing 都要自接），Android APK 每個 ABI 約 +3MB。
  just_audio 在 Android 有 gapless、`AndroidEqualizer`／`AndroidLoudnessEnhancer`（對應待辦的均衡器與響度）、`HlsAudioSource`。
- **研究更正**：研究稱 ExoPlayer 不支援 FLV；官方支援格式表列 FLV 為「YES，不可 seek」（developer.android.com/media/media3/exoplayer/supported-formats，2026-09-28 查證），
  與舊版 Android 能播 B 站直播一致。兩方案都能播 HLS 與 FLV 直播。
- 桌面沒有 `audio_session`，音訊焦點與拔耳機在桌面兩方案都不支援，不構成差異。

## 已確定的方向（先前的勾選）

D1 點歌＝臨時播放；D2 歌單「全部」只加入佇列；D3 Mix 與佇列統一「不可播放就自動跳過」；D4 網易試聽標示並依設定跳過；
D5 限流由網路層退避、播放多次失敗才跳過並提示；D6 開流成功記歷史、單曲循環每圈記；D7 隨機模式行為保留；D8 開電台時取消正在載入的音樂；
D10 區分「未開播」與「查詢失敗」；E12 電台、E13 Mix、E19 速度／音量／輸出裝置保留（均衡器、響度、睡眠定時器在待辦）；
ADR 0013 的呈現表：無法取得／找不到「播放時跳過並提示」。

## 已決定

1. **後端（A5，2026-09-28 選 A）**：`just_audio` 用於 Android、iOS、macOS（ExoPlayer／AVPlayer，系統媒體控制經 `audio_service`）；`media_kit` 用於 Windows、Linux（libmpv，SMTC 經 `smtc_windows`、MPRIS 經 `audio_service_mpris`）。仍是一個介面、兩個實作。
   AVPlayer 格式較窄（無 FLV、無 webm/opus）：平台層宣告可播的容器與編碼，插件的 `resolveStream` 依此挑格式（B 站直播在蘋果平台改用 HLS、YouTube 用 m4a）；iOS／macOS 依 ADR 0009 待有機器時實作並實測。Windows 的 libmpv 庫停在 2023-09 是兩方案共同的風險。

2. **隨機模式的拖曳（D7 之二，2026-09-28）**：隨機順序是「位置」的順序，不是「歌曲」的順序。拖曳後，歌曲落在哪個位置，輪到那個位置時就播它（與舊版 `QueueManager.move` 不動 `_shuffleOrder` 的行為一致，`queue_manager.dart:593-612`）。拖進本輪已播過的位置，本輪不會再播。

## 待決定

- [ ] D7 之一：隨機模式下「下一首播放」插到哪裡

## 驗收條件

- [ ] ADR 0018 記錄：後端選擇與介面、佇列與播放模式、狀態模型、串流解析與過期、錯誤恢復與跳過、系統媒體控制、電台／直播、播放模組的計時器與 lint。
- [ ] D1–D10、E12、E13、E19 各自對到決定；ADR 0015 §6 標給本項的三支舊 static-rule 有去向。
- [ ] `phase2-plan.md` §3 第 13 項標 ✅ 與 ADR 編號。

## 不在範圍

- 下載（第 11 項）；歌詞與桌面歌詞視窗（第 15 項）；播放器 UI 版面（第 5 項）；均衡器、響度、睡眠定時器、邊聽邊存（待辦）。
