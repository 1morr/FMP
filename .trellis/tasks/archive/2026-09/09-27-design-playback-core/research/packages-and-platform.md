# 播放核心：套件與平台研究

- 查證日期：2026-09-27
- 查證方式：context7（官方文檔）→ pub.dev API（版本／發佈日期／平台標籤）→ GitHub API（repo 活動、issue）→ tavily-search（補缺）。體積數據為直接下載量測。
- 範圍：`just_audio`、`media_kit`、`audio_service`、`audio_session`、Windows SMTC、Linux MPRIS、macOS/iOS Now Playing，以及 A5「一個播放介面、每平台一個實作」下的兩方案比較。

## 0. 版本與維護狀態一覽（pub.dev 為準）

| 套件 | 最新版 | 發佈日期 | 平台標籤 | 備註 |
|---|---|---|---|---|
| `just_audio` | 0.10.6 | 2026-06-29 | android, ios, macos, web | Flutter Favorite；**無 windows/linux**。[pub.dev](https://pub.dev/packages/just_audio) |
| `just_audio_background` | 0.0.1-beta.17 | 2025-05-13 | android, ios, macos, web | 仍是 beta 版本線。[pub.dev](https://pub.dev/packages/just_audio_background) |
| `audio_service` | 0.18.19 | 2026-06-29 | android, ios, macos, web | **無 windows**；Linux 靠 `audio_service_mpris`。[pub.dev](https://pub.dev/packages/audio_service) |
| `audio_session` | 0.2.4 | 2026-06-29 | android, ios, macos, web | [pub.dev](https://pub.dev/packages/audio_session) |
| `media_kit` | 1.2.6 | 2025-12-13 | android, ios, macos, windows, linux, web | [pub.dev](https://pub.dev/packages/media_kit) |
| `media_kit_libs_audio` | 1.0.7 | 2025-10-05 | — | 傘套件，依賴下方各平台 libs。[pub.dev](https://pub.dev/packages/media_kit_libs_audio) |
| `media_kit_libs_android_audio` | 1.3.8 | 2025-10-05 | android | [pub.dev](https://pub.dev/packages/media_kit_libs_android_audio) |
| `media_kit_libs_windows_audio` | 1.0.9 | **2023-09-27** | windows | 近三年未發版。[pub.dev](https://pub.dev/packages/media_kit_libs_windows_audio) |
| `media_kit_libs_macos_audio` | 1.1.4 | **2023-09-27** | macos | 近三年未發版。[pub.dev](https://pub.dev/packages/media_kit_libs_macos_audio) |
| `media_kit_libs_ios_audio` | 1.1.4 | **2023-09-27** | ios | 近三年未發版。[pub.dev](https://pub.dev/packages/media_kit_libs_ios_audio) |
| `media_kit_libs_linux` | 1.2.1 | 2025-03-24 | linux | [pub.dev](https://pub.dev/packages/media_kit_libs_linux) |
| `smtc_windows` | 1.1.0 | 2025-08-18 | windows | KRTirtho/frb_plugins 子套件。[pub.dev](https://pub.dev/packages/smtc_windows) |
| `audio_service_mpris` | 0.2.1（stable）/ 1.0.0-beta.2 | 2026-03-15 / 2026-03-26 | linux | audio_service 的 Linux federated 實作；pub points 160/160。[pub.dev](https://pub.dev/packages/audio_service_mpris) |
| `audio_service_win`（第三方） | 0.0.3 | 2026-03-29 | windows | 讓 `audio_service` 可在 Windows 跑。[pub.dev](https://pub.dev/packages/audio_service_win) |
| `just_audio_media_kit` | 2.1.0 | 2025-04-13 | 全平台 | media_kit 後端接 just_audio 介面，供 Linux/Windows 用；unverified uploader。[pub.dev](https://pub.dev/packages/just_audio_media_kit) |
| `media_kit_fork`（第三方） | 0.0.3 | 2025-01-16 | — | azkadev 的 fork，活動低。[pub.dev](https://pub.dev/packages/media_kit_fork) |

關於「media_kit 約 9 個月沒更新」的核實：**對 pub.dev 發版成立、對 repo 開發不成立**。`media_kit` 主套件最後發版 1.2.6 是 2025-12-13（至查證日約 9.5 個月），但 GitHub repo 持續有 commit，最近到 2026-08-30（`fix: memory leaks (#1446)`），2026-06-27 有 `build(macos, ios): bump libmpv`（尚未發版）；open issues 353、open PR 17。[commits](https://github.com/media-kit/media-kit/commits/main)、[repo](https://github.com/media-kit/media-kit)。Windows/macOS/iOS 的 libs 套件則確實停在 2023-09-27，近三年未發版。`ryanheise/just_audio`（stars 1218、open issues 345）、`ryanheise/audio_service`（stars 871、open issues 204）均在 2026-06 有發版與 commit，維護活躍。[just_audio repo](https://github.com/ryanheise/just_audio)、[audio_service repo](https://github.com/ryanheise/audio_service)。

## 1. `just_audio`

### 背景播放
- 官方方案是 **`just_audio_background`**：`JustAudioBackground.init(...)` 一行接入，涵蓋通知、鎖屏控制、耳機按鍵、智慧手錶、Android Auto、CarPlay；需在 AndroidManifest 宣告 `AudioService`、`MediaButtonReceiver` 與 `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 權限。不需要自己接 `audio_service`。[README](https://github.com/ryanheise/just_audio/blob/minor/just_audio_background/README.md)
- 取捨（官方原文）：just_audio_background「designed for applications with a single AudioPlayer instance」；多播放器實例或要細粒度自訂通知按鈕時改用 `audio_service`。[README](https://github.com/ryanheise/just_audio/blob/minor/just_audio_background/README.md)

### gapless
- README 功能表：Android gapless ✅；`setAudioSources(playlist)` + `ConcatenatingAudioSource` 支援動態增刪移、shuffle、loop。Web 不支援 gapless。[README](https://github.com/ryanheise/just_audio/blob/minor/just_audio/README.md)

### 自訂 HTTP header
- `AudioSource.uri(uri, headers: {...})`、`HlsAudioSource(uri, headers: ...)` 都有 `headers` 參數。[context7 / _autodocs/audio-sources.md](https://github.com/ryanheise/just_audio/blob/minor/_autodocs/audio-sources.md)
- 預設走本機 HTTP proxy（`useProxyForRequestHeaders: true` 為預設），因此 Android/iOS/macOS 需開 cleartext；`useProxyForRequestHeaders: false` 改用平台原生 header 實作，但 iOS 無官方 API，依賴未記載的 `AVURLAssetHTTPHeaderFieldsKey`。[README](https://github.com/ryanheise/just_audio/blob/minor/just_audio/README.md)

### HLS／直播
- 功能表 HLS：Android/iOS/macOS ✅（Windows/Linux 經桌面後端亦列 ✅）；DASH：Android ✅。有 `HlsAudioSource`；`StreamAudioSource` 可自餵 byte stream。[README](https://github.com/ryanheise/just_audio/blob/minor/just_audio/README.md)
- FLV：底層 ExoPlayer 官方支援格式清單（DASH、HLS、SmoothStreaming、progressive containers）**不含 FLV**；HTTP-FLV 直播在 just_audio/Android 端查不到官方支援。[Android Developers: ExoPlayer supported formats](https://developer.android.com/media/media3/exoplayer/supported-formats)

### 均衡器
- 內建 `AndroidEqualizer`（"An AudioEffect for Android that can adjust the gain for different frequency bands"）、`AndroidEqualizerBand`、`AndroidEqualizerParameters`、`AndroidLoudnessEnhancer`；**Android 限定**（README 功能表 Equalizer 僅 Android ✅），走 Android `Equalizer` AudioEffect API 掛在播放 session 上。[pub.dev documentation](https://pub.dev/documentation/just_audio/latest/just_audio/just_audio-library.html)、[README](https://github.com/ryanheise/just_audio/blob/minor/just_audio/README.md)

### 桌面
- Windows/Linux 非內建，README 明列需外加 `just_audio_media_kit`、`just_audio_windows` 或 `just_audio_libwinmedia`。[README](https://github.com/ryanheise/just_audio/blob/minor/just_audio/README.md)

## 2. `media_kit`

### 維護狀態
- 見 §0：主套件 ~9.5 個月未發版但 repo 活躍（2026-08 仍在修 memory leak）；桌面/行動 libs 發版停在 2023-09（win/mac/ios）與 2025-03（linux）、2025-10（android）。知名 fork 只有低活動的 `media_kit_fork`（2025-01-16，0.0.3）。[pub.dev media_kit_fork](https://pub.dev/packages/media_kit_fork)

### Android 支援品質
- README 平台表 Android ✅（Android 5.0+）；音訊輸出用 OpenSL ES（`ao: opensles`），API ≤ 25 模擬器直接靜音（`ao: null`）。[README](https://github.com/media-kit/media-kit/blob/main/README.md)、[real.dart](https://github.com/media-kit/media-kit/blob/main/media_kit/lib/src/player/native/player/real.dart)
- **沒有內建背景播放／通知／audio focus**：repo 內查無 audio focus 實作（issue #1099「two players simultaneously」仍 open）；iOS 上與 `audio_service` 搭配做背景播放有未能運作的回報（issue #1227，closed 但內文顯示整合困難）。Android 上 media_kit + audio_service 混用有成功案例（同 issue 內文「implemented a mix of media_kit and audio_service working fine on Android」）。[issue #1099](https://github.com/media-kit/media-kit/issues/1099)、[issue #1227](https://github.com/media-kit/media-kit/issues/1227)

### APK 體積
- `media_kit_libs_android_audio` 本身不含 .so；build 時由 Gradle 從 GitHub release `libmpv-android-audio-build v1.1.8` 下載各 ABI 的 jar。實測（HTTP content-length，2026-09-27）：arm64-v8a 2,983,585 B（≈2.85 MB）、armeabi-v7a 2,865,617 B、x86_64 3,114,935 B、x86 3,040,597 B——**每 ABI 約 +3 MB（壓縮後）**進 APK/AAB。[build.gradle](https://github.com/media-kit/media-kit/blob/main/libs/android/media_kit_libs_android_audio/android/build.gradle)、[release v1.1.8](https://github.com/media-kit/libmpv-android-audio-build/releases/tag/v1.1.8)
- 官方對體積的立場（issue #1089）：體積來自 FFmpeg decoder，「the size needs to be this way due to FFmpeg」。[issue #1089](https://github.com/media-kit/media-kit/issues/1089)

### 自訂 HTTP header
- `Media(url, httpHeaders: {'Foo': 'Bar', ...})` 直接傳入；mpv/FFmpeg 層處理。[README](https://github.com/media-kit/media-kit/blob/main/media_kit/README.md)

### 直播（HLS／FLV）
- README 支援格式清單（FFmpeg demuxers）含 `hls`、`flv`、`live_flv`（live RTMP FLV）、`dash`、`rtsp`、`rtp`。Bilibili 直播的 HTTP-FLV/HLS 在格式層面有覆蓋；HTTP-FLV 實際播放品質（斷線重連等）未查證。[README](https://github.com/media-kit/media-kit/blob/main/README.md)

### 均衡器／音訊濾鏡
- 無內建 EQ API；走 mpv 音訊濾鏡：對 `NativePlayer` 下 `setProperty('af', ...)`（issue #205 使用者以 `af-add`/`af-append` 掛濾鏡，`firequalizer` 在該 build 不存在；issue #570 回報 equalizer 對 FLAC 無效——可用濾鏡集取決於打包的 FFmpeg build）。[issue #205](https://github.com/media-kit/media-kit/issues/205)、[issue #570](https://github.com/media-kit/media-kit/issues/570)
- 內建音量／倍速／音高：`setVolume` / `setRate` / `setPitch`（pitch 需在 `PlayerConfiguration` 啟用）。[README](https://github.com/media-kit/media-kit/blob/main/media_kit/README.md)

### 桌面系統媒體控制
- **SMTC（Windows）：media_kit 無內建**——repo 程式碼搜尋 `smtc` 無任何結果；需搭配 `smtc_windows`（見 §5）。[gh code search repo:media-kit/media-kit smtc → 0 結果](https://github.com/media-kit/media-kit)
- **MPRIS（Linux）：media_kit 無內建**；慣例是搭配 `audio_service_mpris`（見 §6）。
- **Now Playing（macOS/iOS）：media_kit 無內建**——repo 程式碼搜尋 `MPNowPlayingInfoCenter` 無結果。[gh code search](https://github.com/media-kit/media-kit)

### gapless
- 官方文檔查不到 gapless 相關 API 或宣告；repo issue 搜尋 `gapless` 無結果。mpv 底層有 `--gapless-audio` 選項，（推測）可經 mpv property 傳入，但未查證 media_kit 是否可行。

## 3. `audio_service`

- 現況：0.18.19（2026-06-29），維護活躍（repo 2026-07 仍有 commit）。[pub.dev](https://pub.dev/packages/audio_service)
- 官方定位（README 開頭）：包住既有音訊程式碼，提供背景播放＋通知、鎖屏、耳機按鍵、穿戴裝置、Android Auto；「It supports Android, iOS, web and Linux (via audio_service_mpris)」。功能表 macOS 通知/control center ✅。**Windows 不在支援列**；issue #609「Add windows support」open；第三方 `audio_service_win`（issue #1138 提及，0.0.3 / 2026-03-29）補 Windows。[README](https://github.com/ryanheise/audio_service/blob/minor/audio_service/README.md)、[issue #609](https://github.com/ryanheise/audio_service/issues/609)、[issue #1138](https://github.com/ryanheise/audio_service/issues/1138)
- 與 `just_audio_background` 的差異：just_audio_background 是 audio_service 之上的零組態封裝，限定單一 `AudioPlayer`；audio_service 直接給 `AudioHandler` 模型，可自訂通知按鈕、多播放器、非 just_audio 後端（例如 media_kit）也能接。[just_audio_background README](https://github.com/ryanheise/just_audio/blob/minor/just_audio_background/README.md)
- 注意（README）：「this plugin will not work with other audio plugins that overlap in responsibility」（背景播放、通知、鎖屏等職責重疊的外掛不能並存）。[README](https://github.com/ryanheise/audio_service/blob/minor/audio_service/README.md)

## 4. `audio_session`

- 現況：0.2.4（2026-06-29），維護活躍。[pub.dev](https://pub.dev/packages/audio_session)
- 音訊焦點：設定 `androidWillPauseWhenDucked`、`androidAudioFocusGainType` 等；他 App（導航、電話）搶焦點時經 `session.interruptionEventStream` 收到 `duck` / `pause` 事件，結束時可 unduck／resume。iOS 對應 `AVAudioSession`。[README](https://github.com/ryanheise/audio_session)
- 耳機拔除：`session.becomingNoisyEventStream`（「Observe unplugged headphones」）。[README](https://github.com/ryanheise/audio_session)
- README 指出：播放外掛本身可能已自動處理 duck/pause 與拔除事件，沒有才自己聽 stream。

## 5. Windows SMTC

- `smtc_windows`：1.1.0（2025-08-18），repo [KRTirtho/frb_plugins](https://github.com/KRTirtho/frb_plugins)（Spotube 作者）最後 push 2025-08-18（與發版同日），open issues 10。Windows 限定。[pub.dev](https://pub.dev/packages/smtc_windows)
- media_kit **不內建** SMTC（§2）。
- `audio_service` 官方不支援 Windows；第三方 `audio_service_win` 0.0.3（2026-03-29）提供 Windows 平台實作，成熟度的公開資料少（推測：使用者少）。[pub.dev audio_service_win](https://pub.dev/packages/audio_service_win)
- Windows 背景播放的系統要求：不用 MediaPlayer 自動整合時，必須手動接 SMTC（至少啟用 play/pause 並處理 ButtonPressed），否則進背景音訊會停止。[Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/develop/media-playback/system-media-transport-controls)

## 6. Linux MPRIS

- `audio_service_mpris`：stable 0.2.1（2026-03-15），另有 1.0.0-beta.2（2026-03-26）；repo [bdrazhzhov/audio-service-mpris](https://github.com/bdrazhzhov/audio-service-mpris) push 2026-03-26，open issues 0，pub points 160/160。是 `audio_service` 的 Linux federated 實作（pub.dev 標籤 `implements-federated-plugin:audio_service_platform_interface`），即沿用 audio_service 的 Dart API、底層播放引擎不限。[pub.dev](https://pub.dev/packages/audio_service_mpris)
- 其他選項：查不到同等成熟的獨立 MPRIS 套件（未逐一窮舉）。

## 7. macOS/iOS Now Playing

- `audio_service`：iOS control center ✅、macOS notifications/control center ✅（README 功能表）；just_audio_background 同樣覆蓋 iOS/macOS（含 CarPlay）。[audio_service README](https://github.com/ryanheise/audio_service/blob/minor/audio_service/README.md)
- media_kit 在 iOS/macOS：播放本身 ✅（iOS 9+ / macOS 10.9+），但**不整合 Now Playing**（repo 無 `MPNowPlayingInfoCenter`）；iOS/macOS 的 libs 套件停在 2023-09-27（repo 2026-06 有 bump libmpv 未發版）；open issue 有 iOS 播放 crash（#627、#1361）。iOS 上要 Now Playing／背景音訊仍需 audio_service 系，且有整合困難回報（issue #1227）。[README](https://github.com/media-kit/media-kit/blob/main/README.md)、[issue #627](https://github.com/media-kit/media-kit/issues/627)、[issue #1227](https://github.com/media-kit/media-kit/issues/1227)

## 8. 補充：`just_audio_media_kit` 橋接層

- 2.1.0（2025-04-13），unverified uploader。用 media_kit 實作 just_audio 的平台介面，讓同一套 `AudioPlayer` API 跑 Windows/Linux。已知限制：shuffleOrder 被忽略、`SilenceAudioSource` 不支援、gapless（`prefetchPlaylist`）標示「highly experimental. Use at your own risk.」。不含 SMTC／MPRIS／背景播放整合。[pub.dev](https://pub.dev/packages/just_audio_media_kit)

## 9. A5 比較表：全平台 media_kit vs Android just_audio + 桌面 media_kit

| 面向 | 方案 A：全平台 media_kit | 方案 B：Android just_audio + 桌面 media_kit |
|---|---|---|
| 背景播放（Android） | 無內建；需自接 audio_service（職責重疊限制見 §3；Android 上有成功混用案例）[#1227](https://github.com/media-kit/media-kit/issues/1227)、[#1099](https://github.com/media-kit/media-kit/issues/1099) | just_audio_background 一行接入，官方方案含通知/鎖屏/Auto/CarPlay [README](https://github.com/ryanheise/just_audio/blob/minor/just_audio_background/README.md) |
| 系統媒體控制 — Android 通知 | 經 audio_service 自接（同上） | just_audio_background 內建 [README](https://github.com/ryanheise/just_audio/blob/minor/just_audio_background/README.md) |
| 系統媒體控制 — Windows SMTC | media_kit 無內建；搭配 `smtc_windows`（1.1.0/2025-08，活動中）[pub.dev](https://pub.dev/packages/smtc_windows) | 同左（桌面同為 media_kit） |
| 系統媒體控制 — Linux MPRIS | media_kit 無內建；搭配 `audio_service_mpris`（0.2.1/2026-03，160/160 分）[pub.dev](https://pub.dev/packages/audio_service_mpris) | 同左 |
| 系統媒體控制 — macOS/iOS Now Playing | media_kit 無內建（repo 無 MPNowPlayingInfoCenter）；iOS 接 audio_service 有困難回報 [#1227](https://github.com/media-kit/media-kit/issues/1227) | Android 端不影響；若未來 iOS/macOS 用 just_audio 則 audio_service/just_audio_background 原生覆蓋 [audio_service README](https://github.com/ryanheise/audio_service/blob/minor/audio_service/README.md) |
| 均衡器 | 無內建 API；mpv `af` 濾鏡，可用濾鏡集依打包 FFmpeg 而定，有失效回報 [#205](https://github.com/media-kit/media-kit/issues/205)、[#570](https://github.com/media-kit/media-kit/issues/570) | Android：內建 `AndroidEqualizer`（Android 限定）；桌面仍走 mpv `af` [pub.dev docs](https://pub.dev/documentation/just_audio/latest/just_audio/just_audio-library.html) |
| 直播 — HLS | 支援（FFmpeg `hls`）[README](https://github.com/media-kit/media-kit/blob/main/README.md) | Android：ExoPlayer HLS ✅（`HlsAudioSource`）；桌面 media_kit ✅ [README](https://github.com/ryanheise/just_audio/blob/minor/just_audio/README.md) |
| 直播 — HTTP-FLV（Bilibili） | FFmpeg `flv`/`live_flv` 在支援清單 [README](https://github.com/media-kit/media-kit/blob/main/README.md) | Android：ExoPlayer 支援格式**不含 FLV**，需另謀（桌面不受限）[Android Developers](https://developer.android.com/media/media3/exoplayer/supported-formats) |
| APK 體積 | 每 ABI +約 3 MB（libmpv audio build，壓縮後實測）[build.gradle](https://github.com/media-kit/media-kit/blob/main/libs/android/media_kit_libs_android_audio/android/build.gradle)、[release](https://github.com/media-kit/libmpv-android-audio-build/releases/tag/v1.1.8) | Android 端 +0 MB（ExoPlayer 為純 Java/Kotlin）；桌面仍帶 libmpv |
| 維護風險 | 主套件 9.5 個月未發版（repo 活躍）；win/mac/ios libs 近三年未發版；353 open issues [repo](https://github.com/media-kit/media-kit) | Android 端 ryanheise 系 2026-06 發版、Flutter Favorite；桌面端風險同左，但僅桌面承受 [pub.dev](https://pub.dev/packages/just_audio) |
| 自訂 HTTP header | `Media(httpHeaders:)`，mpv/FFmpeg 層處理 [README](https://github.com/media-kit/media-kit/blob/main/media_kit/README.md) | Android：`headers:` 參數；預設走本機 proxy（需 cleartext），可關 [README](https://github.com/ryanheise/just_audio/blob/minor/just_audio/README.md)；桌面 media_kit 同左 |
| gapless | 官方無宣告；mpv `--gapless-audio` 未查證可經 media_kit 使用 | Android：gapless ✅ 官方功能 [README](https://github.com/ryanheise/just_audio/blob/minor/just_audio/README.md)；桌面 media_kit 同方案 A |
| 音訊焦點／打斷 | 無內建，需自接 audio_session [#1099](https://github.com/media-kit/media-kit/issues/1099) | Android：just_audio 內建處理（底層用 audio_session）；桌面另行處理 [audio_session README](https://github.com/ryanheise/audio_session) |

## 10. 事實摘要（只列影響決策的硬事實）

1. `just_audio` 無 Windows/Linux 支援；桌面需 `just_audio_media_kit` 等橋接，其 gapless 標示「highly experimental」。（[pub.dev](https://pub.dev/packages/just_audio)、[just_audio_media_kit](https://pub.dev/packages/just_audio_media_kit)）
2. `audio_service` 官方支援 Android/iOS/macOS/web，Linux 經 `audio_service_mpris`（活躍、滿分），Windows 僅有第三方 `audio_service_win`（0.0.3，資料少）。（[README](https://github.com/ryanheise/audio_service/blob/minor/audio_service/README.md)）
3. media_kit **完全不內建**系統媒體控制：無 SMTC、無 MPRIS、無 Now Playing、無 Android 通知／audio focus，全部要自接對應套件。（repo 程式碼搜尋、§2）
4. media_kit 主套件 9.5 個月未發版但 repo 2026-08 仍活躍；Windows/macOS/iOS libs 停在 2023-09-27。（§0）
5. media_kit 對 APK 的影響：每 ABI 約 +3 MB（壓縮後，實測 libmpv-android-audio-build v1.1.8 jar）。（§2）
6. Android 均衡器：just_audio 有內建 `AndroidEqualizer`；media_kit 只能走 mpv `af` 濾鏡且有失效回報。（§1、§2）
7. Bilibili HTTP-FLV 直播：media_kit 的 FFmpeg demuxer 清單含 flv/live_flv；ExoPlayer 官方支援格式不含 FLV，just_audio/Android 端查不到 FLV 支援。（§1、§2）
8. HLS 兩方案都支援；just_audio 另有 `HlsAudioSource` 與 DASH。（§1、§2）
9. 自訂 HTTP header：兩邊都支援；just_audio 預設走本機 proxy 需 cleartext 權限（可關），media_kit 直接傳 `httpHeaders`。（§1、§2）
10. Android 背景播放：just_audio_background 是官方一行接入方案（仍為 0.0.1-beta 版本線，最後發版 2025-05-13）；media_kit 在 Android 需自接 audio_service，且 audio_service 與「職責重疊」外掛不可並存。（§1、§3）
11. gapless：just_audio Android 官方 ✅；media_kit 官方無 gapless 宣告。（§1、§2）

## 11. 補漏：`audio_session` 的平台缺席（2026-09-28 補）

- `audio_session` 的平台標籤只有 android / ios / macos / web（§0 表），**沒有 windows / linux** —— 桌面端不存在這個外掛，因此「duck／pause 中斷、拔耳機事件、`setActive` 語意」在桌面**不是「換一套件」而是要自己接平台 API**（Windows 走 WASAPI session／SMTC、Linux 走 MPRIS 或 PulseAudio/ PipeWire 事件），或直接不做。本 repo 的 `lib/services/audio/audio_service.dart:9-17` dartdoc 已把「音訊焦點為 Android 專屬」寫成後端契約的一部分，兩者一致。
- 對 A5 表「音訊焦點／打斷」列的影響：兩個方案在**桌面**都是空白，這一列不構成 A 與 B 的差異；差異只在 Android（方案 B 由 just_audio 內建處理）。
- `just_audio` 本身底層即使用 `audio_session`（§9 該列註記），故選 just_audio 時 `audio_session` 是**傳遞依賴**，不是可選項；選 media_kit 則需自行決定是否引入。
- 未查證：Windows/Linux 上是否有成熟、活躍的 Flutter 套件能提供 duck／中斷事件（`audio_session` 無桌面實作，其他替代未逐一搜尋）。
