# Research: iOS 平台所需套件調查（釘版本）

- **Query**: FMP `app/` 要在 iOS（先在模擬器、之後擁有者的 iPhone，免費 Apple ID 的 personal team 簽章，經 GitHub 發 IPA 由使用者側載）上跑，逐一調查 `pubspec.lock` 釘的套件版本在 iOS 的支援、設定與已知問題。格式沿用 `.trellis/tasks/archive/2026-11/10-28-macos-platform/research/packages-macos.md`。
- **Scope**: mixed（pub cache 原始碼 + 本機模擬器實測 + CI log + GitHub issue / Apple 文件）
- **Date**: 2026-11-04
- **環境**: Flutter 3.47.5（engine af7e796e16）、Xcode 27.1（27A9275）、macOS 27、Apple Silicon；模擬器 iPhone 18 Pro（iOS 27.0）。本機只有 Xcode 27.1，**沒有 Xcode 26.6**，所以 26.6 的結論只能引用 CI。
- **來源標記**: 【原始碼】= 讀 `~/.pub-cache/hosted/pub.dev/<pkg>-<ver>/`；【實測】= 本機建置或模擬器實跑；【CI】= GitHub Actions log；【文件】= 套件 README / Apple 文件 / GitHub issue。
- **實驗位置**: `<scratchpad>` = `/private/tmp/claude-501/-Users-roxy-orca-projects-FMP/4e5a2590-21d1-48a2-a14e-ecf59d04f4ae/scratchpad/`。`ios-research/app/`（獨立的 Flutter 專案，依賴釘同樣版本）、`ios-research/server.py`（Range、必須帶 Referer／UA／Cookie 才回 200，否則 403）、`ios-research/media/`（ffmpeg 產的測試音檔）、`ios-research/run*.log`。repo 內只動到 `.trellis/tasks/11-03-ios-platform/research/` 這份檔；`flutter build ios` 改動的 `app/ios/` CocoaPods 檔照指示沒有 commit 也沒有還原。實驗後模擬器已 `shutdown`、測試伺服器已停。

## 0. 釘版本與 iOS 實作一覽

| 套件 | `pubspec.lock` 版本 | iOS 實作 | 原生建置方式 | 套件宣告的 iOS 最低版本 |
|---|---|---|---|---|
| just_audio | 0.10.6 | 內建（共用 darwin，AVQueuePlayer） | SPM（`darwin/just_audio/Package.swift`） | 12.0 |
| audio_service | 0.18.19 | 內建（共用 darwin） | SPM | 12.0（`Package.swift:9`） |
| audio_session | 0.2.4 | 內建（`DarwinAudioSession.m`，`AVAudioSession`） | SPM | 12.0 |
| flutter_secure_storage | 11.2.0 → `flutter_secure_storage_darwin` 0.4.3 | darwin 子套件 | SPM | 13.0 |
| flutter_inappwebview | 6.2.0-beta.3 → `flutter_inappwebview_ios` 1.2.0-beta.3（`pluginClass: InAppWebViewFlutterPlugin`；iOS **沒有** stub，用真的） | WKWebView | SPM（帶進 `swift-collections`） | 12.0 |
| file_picker | 13.1.0 → `file_picker_darwin` 2.1.3 | `UIDocumentPickerViewController`、`PHPickerViewController` | SPM | README 寫 iOS 14.0 |
| share_plus | 13.3.1 | `FPPSharePlusPlugin.m`（`UIActivityViewController`） | SPM | 13.0 |
| url_launcher | 6.3.3 → `url_launcher_ios` 6.4.2 | 子套件 | SPM | — |
| connectivity_plus | 7.3.1 | 內建 | SPM | — |
| package_info_plus | 10.2.2 | 內建 | SPM | — |
| path_provider | 2.1.6 → `path_provider_foundation` 2.6.0 | 純 Dart + FFI（`objective_c` 9.5.0） | 無外掛（native assets） | — |
| sqflite_darwin | 2.4.4（`flutter_cache_manager` 帶進來） | 內建 | SPM | — |
| sqlite3 | 3.6.0 | build hooks 編成 `sqlite3.framework` | native assets | — |
| isar_community_flutter_libs | 3.3.2 | `ios/isar.xcframework`（靜態庫） | **CocoaPods（只有 podspec）** | podspec 11.0 |
| flutter_js | 0.8.7 | iOS 只有 JavaScriptCore 的 Swift 外掛，**沒有 QuickJS 符號** | **CocoaPods（只有 podspec）** | podspec 8.0 |
| fmp_quickjs（本機） | 0.1.0 | **只宣告 `macos: ffiPlugin: true`，沒有 iOS** | CocoaPods | — |
| window_manager、screen_retriever_* | 0.5.2 / 0.2.2 | **pubspec 沒有 `ios:` 平台，不編進 iOS** | — | — |
| smtc_windows、media_kit_libs_windows_audio | — | 只有 windows | — | — |
| media_kit | 1.2.6 | 純 Dart（FFI 找 libmpv），iOS 不載入 | — | — |

- 專案的 `IPHONEOS_DEPLOYMENT_TARGET = 15.0`（`app/ios/Runner.xcodeproj/project.pbxproj:520,572,736,…`）【原始碼】；實測建出的 `Runner.app/Info.plist` `MinimumOSVersion = 15.0`【實測】。高於上表所有套件最低版本，沒有部署版本衝突。
- `TARGETED_DEVICE_FAMILY = "1,2"`（iPhone 與 iPad 都支援，`project.pbxproj:834,904,957`）；`ios/Runner/` 底下沒有 `.entitlements` 檔【原始碼】。
- `app/ios/Runner/Info.plist` 現況：沒有 `UIBackgroundModes`、沒有 `NSAppTransportSecurity`、沒有任何 `*UsageDescription`、沒有 `LSApplicationQueriesSchemes`【原始碼】。
- 工作樹現況（建置前就有）：`app/ios/Podfile`、`Podfile.lock` 未追蹤；`Debug.xcconfig`／`Release.xcconfig` 多一行 `#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug|release.xcconfig"`；pbxproj、`contents.xcworkspacedata` 已被 CocoaPods 改過。我的建置沒有再增加任何 repo 變動（`git status` 前後相同）【實測】。

---

## 1. 建置：Xcode 27.1 模擬器、Xcode 26.6 的 CI（對應任務項 6、4）

### 1.1 實測：`flutter build ios --simulator --flavor dev --debug`（Xcode 27.1）
- 結果：**成功**，`✓ Built build/ios/iphonesimulator/Runner.app`，Xcode 建置 62.3 秒，bundle id `com.personal.fmp.dev`，`CFBundleDisplayName = FMP Dev`，`DTXcodeBuild = 27A9275`、`DTSDKName = iphonesimulator27.1`【實測】。沒有錯誤；只有 Flutter 的 SPM 提示：

  ```
  The following plugins do not support Swift Package Manager for ios:
    - flutter_js
    - isar_community_flutter_libs
  This will become an error in a future version of Flutter.
  ```
- 產物 `Runner.app/Frameworks`：`App`、`flutter_js`、`Flutter`、`isar_community_flutter_libs`、`objective_c`、`sqlite3` 五個 framework，**x86_64 + arm64 兩個切片**都有（`lipo -archs`）；SPM 外掛以 `*.bundle` 資源出現：`connectivity_plus`、`file_picker_darwin`、`flutter_inappwebview_ios`、`flutter_secure_storage_darwin`、`package_info_plus`、`share_plus`、`sqflite_darwin`、`url_launcher_ios`【實測】。
- `flutter_js.podspec` 寫 `'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64'`；CocoaPods 把 pod 的 `VALID_ARCHS[sdk=iphonesimulator*]` 設成 `$(ARCHS_STANDARD)`（`ios/Pods/Pods.xcodeproj/project.pbxproj:1146`），Apple Silicon 模擬器 arm64 切片實際有建出，沒有造成問題【實測】。
- Pods 專案裡 Debug／Release 以外的 flavor configuration（`debug-dev`、`release-prod` 等）有各自的 `Pods-Runner.<config>.xcconfig`（CocoaPods 依專案的 build configuration 名稱產生）；`ios/Podfile` 的 `project 'Runner'` 只對應 `Debug`／`Profile`／`Release` 三個模式，和 `app/AGENTS.md` § 平台層寫的「`ios/` 的還沒提交，產生的 Podfile 只對應三個模式」一致【實測 + 原始碼】。`Pods-Runner.debug-dev.xcconfig` 與 `.debug.` 的 `GCC_PREPROCESSOR_DEFINITIONS` 都只有 `COCOAPODS=1`，看不出 debug／release 差別，沒有進一步驗證 `Debug-dev` 的 pod 以哪個模式編【實測】。
- **未實測**：`--release`／`--no-codesign` 的實機（iphoneos）建置在本機沒跑（模擬器不支援 release，`flutter build ios --simulator --release` 回 "Release mode is not supported for simulators."）；實機版本見 1.2 的 CI。

### 1.2 CI（Xcode 26.6 的 macOS runner）【CI】
- `.github/workflows/ci.yml:468-498` 的 `app-build-ios` 在 `macos-latest` 跑 `flutter build ios --flavor prod --release --no-codesign` 與 `--flavor dev --debug --no-codesign`。
- 最近一次有跑 iOS job 的 run：`41656986777`（head `755e7b0a`，2026-11-03），`App Build (iOS)` **success**；log 第一行 `Image: macos-26-arm64`；`Building com.personal.fmp for device (ios-release)... ✓ Built build/ios/iphoneos/Runner.app (36.1MB)`，`Building com.personal.fmp.dev for device (ios)... ✓ Built …`。log 有 `Xcode is fetching Swift Package Manager dependencies` 與 `Fetching from https://github.com/apple/swift-collections.git`，也就是 `flutter_inappwebview_ios` 這個 SPM 套件有被編進去。log 沒有印 Xcode 版本，所以「26.6」是依 runner 預設值（使用者與 ADR 0036 §決定 9 寫的 macos-26-arm64 預設 Xcode 26.6），不是從 log 確認。後兩個 run（`41659599984`、`41662449773`）的 iOS job 因為變更路徑沒動 `app/` 而 skipped。
- 結論：**真的 `flutter_inappwebview_ios` 1.2.0-beta.3 在 Xcode 27.1（本機）與 CI 的 macos-26 映像（Xcode 26.6）都建得過**，和 macOS 子套件在 26.6 建不過的狀況不同。差異的原因我沒有查到：macOS 版 `WebAuthenticationSession.swift:85` 是 `@available(macOS 10.15, *)` 搭配 package 的 `.macOS("10.14")`，iOS 版（`…/flutter_inappwebview_ios/WebAuthenticationSession/WebAuthenticationSession.swift:92-93`）是 `@available(iOS 12.0, *)` 搭配 package 的 `.iOS("12.0")`，兩份程式碼形狀相同。

### 1.3 上游相關 issue【文件】
- pichillilorenzo/flutter_inappwebview **#2813**（open，2026-04-07）：macOS Tahoe + Xcode 26.4，`WebAuthenticationSession.swift:85:17: protocol 'ASWebAuthenticationPresentationContextProviding' requires 'presentationAnchor(for:)' to be available in macOS 10.14 and newer`；對應修正 PR **#2809**（open，2026-10-26 仍未合併；留言說明 PR 作者原本只針對 macOS，之後補 iOS）。
- **#2830**（open，2026-05-06）：Xcode 26.4.1，**iOS** 子套件 `flutter_inappwebview_ios-1.1.2` 同一檔案（`WebAuthenticationSession.swift:91:16`）報同樣性質的錯（"requires 'presentationAnchor(for:)' to be available in iOS 11.0 and newer"）。回報者用的是 1.1.2（穩定版），不是我們釘的 1.2.0-beta.3；我們釘的版本在 CI 與本機都過了，所以這個 issue 不能直接套用到我們。
- iOS 行為類：#2713（open，2025-11-13）iOS 26 上 drawer 關閉後 WebView 觸控失效；#2727（open，2026-03-23）iOS 26.0 `showModalBottomSheet`／`showDialog` 後頁面無反應；#2723（open，2026-03-06）6.2.0-beta 在 ListView／ScrollView 內 href 點擊停止回應。這些是在使用者介面層才會碰到，未實測。

---

## 2. just_audio 0.10.6（iOS：yes）

### 2.1 實作與可播格式
- `AVQueuePlayer`（共用 darwin 原始碼），README 平台表（`just_audio-0.10.6/README.md:408-430`）：iOS 的 URL 讀取、request headers、HLS、ICY、gapless、playlists、clip、loop/shuffle 都是 yes；**DASH（`.mpd`）iOS 空白**；**「handle phonecall interruptions」iOS 為 yes、macOS 為空白**；pitch、skip silence、equalizer、volume boost 只有 Android【文件】。

### 2.2 實測：模擬器（iPhone 18 Pro，iOS 27.0）AVPlayer 能播什麼
測法：scratch app（釘同版本的 just_audio），`AudioPlayer(useProxyForRequestHeaders: false, handleInterruptions: false)`（與 `app/lib/playback/backends/just_audio_backend.dart:21-26` 同設定），`AudioSource.uri(url, headers: {Referer: https://www.bilibili.com/, User-Agent: FMPTest/1.0, Cookie: SESSDATA=abc})`，測試伺服器（`http://127.0.0.1:8099`，支援 Range，三個標頭任一不符就回 403）。每個案例：`setAudioSource` → `play` → 2 秒後讀位置 → seek 到 15 秒 → 1 秒後讀位置。所有音檔是 ffmpeg 從 30 秒 440Hz 正弦波產生【實測】。

| 案例 | 結果 |
|---|---|
| AAC in MP4（`.m4a`，`audio/mp4`） | 播放，`duration=29.975s`，2 秒後位置 2.004，seek 15 → 16.002 |
| ADTS AAC（`.aac`，`audio/aac`） | 播放，`duration=30.023s`，seek 正常 |
| MP3（`audio/mpeg`） | 播放，`duration=30.000s`，seek 正常（#1599 的 duration=0 沒有出現；該 issue 的環境是「iOS app on Apple silicon Mac」） |
| FLAC（`audio/flac`） | 播放，`duration=30.000s`，seek 正常 |
| WAV（`audio/wav`） | 播放，`duration=30.000s`，seek 正常 |
| **Ogg Opus**（`.opus`，`audio/ogg`） | **播放**，`duration=30.220s`，seek 正常（iOS 27 的 AVPlayer 可播 Ogg Opus） |
| **WebM Opus**（`.webm`，`audio/webm`） | **失敗**：`PlayerException (-11828) Cannot Open` |
| **FLV（AAC）**（`.flv`，`video/x-flv`） | **失敗**：`PlayerException (-11828) Cannot Open` |
| 單一檔案 fMP4 + `sidx`（`ffmpeg -f dash -single_file 1` 的 `.mp4` 改名 `.m4s`，接近 B 站 DASH 音訊），`audio/mp4`，Range | 播放，`duration=29.975s`，seek 15 → 15.9998 |
| 同一個 `.m4s`，`Content-Type: application/octet-stream` | **失敗**：`PlayerException (-11828) Cannot Open` |
| `.mp3` 以 `application/octet-stream` | 播放（`duration=30.0`） |
| `.m4a` 以 `application/octet-stream` | 播放（`duration=29.975`） |
| HLS，TS 分段（`p.m3u8` + `s0..7.ts`，VOD） | 播放，`duration=30.023s`，seek 正常 |
| HLS，fMP4 分段（`#EXT-X-MAP` + `.m4s`，VOD） | 播放，`duration=30.023s`，seek 正常 |
| 同一個 `.m4a` **不帶**標頭 | **失敗**：`PlayerException (-11829) Cannot Open`，伺服器看到 403（證明伺服器確實檢查標頭） |

- **網路伺服器端 log（`ios-research/srv.log`）**：48 個請求，46 個帶齊 `Referer`、`User-Agent: FMPTest/1.0`、`Cookie: SESSDATA=abc`（`ok=true`），2 個沒標頭（就是上表「不帶標頭」那一行）；**HLS 的 playlist、init、每個分段共 19 個請求全部帶齊標頭**【實測】。
- 與 macOS 研究的差異／相同點：同樣是 `AVURLAssetHTTPHeaderFieldsKey`（見 2.3），「`Content-Type: application/octet-stream` 的 `.m4s` 會 Cannot Open」兩邊一致。macOS 研究測的是 `audio/mp4`／`video/mp4`／`octet-stream`；我另外測了 `.mp3` 與 `.m4a` 配 octet-stream，兩者都能播（MP3 與 M4A 容器靠內容判斷）。
- 沒有測：**真實 Bilibili／YouTube／NetEase CDN 的 Content-Type 與檔案結構**（匿名呼叫 B 站 API 會被擋，沿用 macOS 研究的限制）；Dolby E-AC-3 軌；真實直播 HLS（live、無 ENDLIST）；模擬器的輸出裝置是 Mac 的喇叭，聽不出聲音，只驗證了播放位置前進。
- **YouTube 常見的 `audio/webm`（Opus）在 iOS 不能播**，和 ADR 0036 §決定 7 對 macOS 的結論一致；Ogg Opus 容器能播但 WebM 容器不能。

### 2.3 自訂 HTTP 標頭怎麼做（本 App 的設定）【原始碼】
- App 以 `useProxyForRequestHeaders: false` 建立，`UriAudioSource.m:49-68`（共用 darwin 程式）把標頭放進 `AVURLAsset` options：只有一個標頭且是 `User-Agent`、系統 ≥ 特定版本時用公開 key `AVURLAssetHTTPUserAgentKey`，其他情況（我們有 Referer、UA、Cookie）用 `assetOptions[@"AVURLAssetHTTPHeaderFieldsKey"]`。這個 key **不是公開 API**（README `:115` 自承 "iOS doesn't offer an official native API for setting headers"）；本次在 iOS 27.0 模擬器實測可行（2.2）。
- 不走本機 proxy，所以不需要 proxy 要求的 `NSAllowsArbitraryLoads`。issue：#470（HLS 標頭不遞迴，proxy 模式限制）、#747（open，2022-05-30，2023-11-13 更新）「AudioSource.uri with headers not working when app is locked for some amount of time and audio is stopped」（iOS 鎖屏一段時間後帶標頭來源行為異常，**未實測**）【文件】。

### 2.4 ATS 與 `NSAllowsArbitraryLoadsForMedia`
- README `:282-293`（iOS）：連非 HTTPS，或使用依賴 proxy 的功能時，要在 Info.plist 加 `NSAppTransportSecurity > NSAllowsArbitraryLoads`；本 App 不走 proxy，所以只在「來源回傳 `http://` 音訊網址」時才需要例外，ADR 0036 §決定 7 的 macOS 做法是 `NSAllowsArbitraryLoadsForMedia`。
- Apple 文件：`NSAllowsArbitraryLoadsForMedia` 只放寬 AV Foundation 載入的媒體，不影響其他連線；「只用在不含個人資訊的加密媒體」；上 App Store 要給理由（本專案以側載發 IPA，ADR 0009 §決定 9，不上 App Store）【文件】。
- **實測（模擬器，scratch app，Info.plist 沒有 ATS 設定）**：
  - `http://127.0.0.1:8099/…`（loopback）與 `http://192.168.50.98:8099/…`（LAN IP 字面值）：**都能播**。IP 位址不受 ATS 管（Apple ATS 文件：不套用於 IP 位址、未限定主機名、`.local`）。
  - `http://example.com/x.m4a`（網域名稱）：播放失敗，Dart 端只看到 `PlayerException (-11800)`；模擬器 log（`xcrun simctl spawn … log show --predicate 'process == "Runner"'`）有 `Runner: (CFNetwork) [com.apple.network:ATS] Warning [ATS violation]: Did not use TLS when opening connection for server: <private>`。
  - 在 Info.plist 加 `NSAppTransportSecurity > NSAllowsArbitraryLoadsForMedia = true` 後重跑同樣兩個網址：log 裡**不再有** `ATS violation`；播放仍失敗（`-11800`），因為這兩個網址本身不是音訊（`example.com`／`httpbin.org/status/404`），所以只證明了「ATS 攔截消失」，**沒有**一個真的 `http://` 網域音訊能播的正例（這台機器的 DNS 被攔截，`nip.io` 之類解不出來，公開的 http 音檔網址又多是轉址）。
- 所以 iOS 與 macOS 一樣：http 且是網域名稱的音訊網址會被 ATS 擋，iOS 上 Dart 錯誤碼是 `-11800`（不像 macOS 研究看得到底層 -1022）。

### 2.5 背景播放、音訊工作階段與中斷
- **`UIBackgroundModes: audio`**：audio_service README `:403-415`（iOS setup）要求在 Info.plist 加 `UIBackgroundModes = [audio]`；just_audio 本身沒有這個要求，但沒有它，App 進背景後 iOS 會暫停行程（即使 audio_service 在）。**沒有在實機驗證**（模擬器不強制執行背景暫停）【文件】。Apple 文件：這個 key 對應 Xcode 的「Background Modes」capability；`audio` 模式只寫在 Info.plist，不需要 provisioning profile 的額外授權（推論自「它是 Info.plist key」，沒有找到免費帳號對它的明文說明）。
- **AVAudioSession 的 category**：just_audio 的 darwin 原生端沒有設定 category（`grep setCategory just_audio/darwin/.../*.m` 沒有結果）。`AudioPlayer.play()` 呼叫 `AudioSession.instance.setActive(true)`（`just_audio.dart:1097-1098`，`handleAudioSessionActivation` 預設 true），audio_session 的 `setActive` 在還沒 `configure` 時用 `fallbackConfiguration = AudioSessionConfiguration.music()`（`audio_session-0.2.4/lib/src/core.dart:226-235`），其 iOS category 是 `AVAudioSessionCategory.playback`、mode `defaultMode`（`core.dart:548-557`）。App 目前沒有呼叫 `AudioSession.configure`（`app/lib` 只有 `just_audio_backend.dart` 用 `AudioSession.instance`）。所以 iOS 上第一次 `play()` 才會把 category 設成 `playback`【原始碼】。
- **中斷事件的對應（iOS 與 Android 不同）**【原始碼】：`audio_session` Dart 端（`core.dart:65-82`）把 iOS 的 `AVAudioSessionInterruptionNotification` 轉成：
  - `began`（且 `wasSuspended != true`）→ `AudioInterruptionEvent(begin: true, type: unknown)`；
  - `ended` → `AudioInterruptionEvent(begin: false, type: pause)`（`options` 含 `shouldResume`）或 `type: unknown`（沒有 `shouldResume`）。
  `app/lib/playback/backends/backend_rules.dart:108-114` 已註明這一點（"audio_session 在 iOS 的中斷開始一律報 unknown、之後照樣有結束，接 iOS 時要另外對應"）。把這個事實代入現有的對應與路由：`respondToInterruption(begin: true, kind: unknown)` → `InterruptionResponse.lost` → `Interrupted(transient: false)`（`backend_rules.dart:150-158`）；`playback_event_router.dart:270-273` 對 `AudioInterrupted(transient: false)` 回 `PauseWithoutResuming`，不會設 `pausedByInterruption`；之後的 `InterruptionEnded(resume: true)` 在 `pausedByInterruption == false` 時被 `playback_event_router.dart:275-276`（`AudioInterruptionEnded() when !snapshot.pausedByInterruption => IgnoreEvent`）忽略。也就是**依現有程式，iOS 來電掛斷後不會自動續播**（推論自原始碼，沒有在實機接電話驗證）。
- `becomingNoisy`：iOS 由 `AVAudioSessionRouteChangeReasonOldDeviceUnavailable` 觸發（`core.dart:89-94`，有 `// TODO: Check specifically if headphones were unplugged.`），也就是任何「舊輸出裝置不可用」都會發，不限耳機【原始碼】。
- scratch app 只掛了 `interruptionEventStream` / `becomingNoisyEventStream` 監聽，模擬器沒有提供模擬來電的簡便方法，**這兩個事件沒有觸發過**，上面是純讀碼。
- 相關 issue【文件】：just_audio **#1579**（open，2026-03-23）某些實機 `AudioPlayer.play()` 丟 `PlatformException(561017449 …)`，原生 log `AVAudioSession_iOS.mm:2540 Failed to set properties, error: '!pri'`（`insufficientPriority`），出現在 `AudioSession.setActive(true)`；**#1598**（open，2026-08-14）`play()` 的 Future 在 audio session 啟用被拒或沒有來源時永不完成；**#1556**（open，2025-10-01）iOS 26 gapless loop 失效；**#1613**（open，2026-10-27）iOS 上 `LoopMode.one` 緊接在自動換曲之後設定，`currentIndex` 跑到清單結尾。

### 2.6 已知問題（iOS 的 duration／位置）
- 沿用 macOS 研究列的：**#1599**（MP3 duration 為 0，2026-08-26 open，環境是「iOS app on Apple silicon Mac」）、#1435（LockCachingAudioSource 轉址）、**#903**（open，iOS HLS duration 不正確）、#877（open，`preferredForwardBufferDuration` 在 iOS 無效）。本次在 iOS 27.0 模擬器（Apple Silicon 主機）上，MP3 與 HLS 的 duration 都正確（30 秒；HLS 是 VOD），但**沒有測 live HLS**。

---

## 3. audio_service 0.18.19（iOS：yes，與 macOS 共用 darwin 原始碼）

- `pubspec.yaml:60-62`：iOS `pluginClass: AudioServicePlugin`、`sharedDarwinSource: true`；README 平台表（`:20-31`）iOS 的 background audio、headset clicks、play/pause/seek/rate/stop、fast forward/rewind、repeat/shuffle、queue、custom actions、notifications/control center、**lock screen controls**（macOS 空白、iOS 有）、album art、CarPlay 都打勾【文件】。
- 共用的 darwin 原生程式（`darwin/audio_service/Sources/audio_service/AudioServicePlugin.m`）【原始碼】：
  - `MPRemoteCommandCenter`（`:89-135`）：`play/pause/stop/next/previous/skipForward/skipBackward/seek/changePlaybackPosition/togglePlayPause/repeat/shuffle/rate` 等；`changePlaybackPosition`（`:485-490`）把 `event.positionTime` 轉成微秒送 Dart 的 `seek`，即**鎖定畫面／控制中心可以拖進度條**（只要 handler 宣告 `MediaAction.seek`，`updateControls` 才啟用）。
  - `MPNowPlayingInfoCenter`：title、album、artist、duration、artwork、播放速率、經過時間、`MPNowPlayingInfoPropertyMediaType = audio`、`isLive`。
  - 第一次收到 `playing == true` 的狀態才 `activateCommandCenter`，iOS 另外 `[AVAudioSession sharedInstance]`（`:180-188`）。
  - 封面：iOS 以 `extras["artCacheFile"]` 的**本機檔案路徑**建 `UIImage`（`:206-225`，`TARGET_OS_IPHONE` 分支）；與 macOS 同樣需要 `AudioService` 的 `cacheManager`（Dart 端）。
  - **`center.playbackState` 只在 `#if TARGET_OS_OSX` 設定**（`:292-295`）；iOS 不設。上游 issue **#1139**（open，2025-09-08，2026-07-06 更新）說 iOS ≥ 13 的 `playbackState` 沒回報，維護者回覆已合併修正到 minor 分支，但釘的 0.18.19 原始碼仍是 `#if TARGET_OS_OSX`，所以這個修正**不在 0.18.19**。實際影響（例如 iOS 17+ 的某些 Now Playing 顯示）**沒有在實機驗證**。
  - `setQueue`、`setPlaybackInfo`、`notifyChildrenChanged`、`androidForceEnableMediaButtons` 都是直接回 `{}` 的空實作（與 macOS 同）。
- **共用 handler 能不能直接用**：`app/lib/platform/media_controls/media_controls_macos.dart` 的 `MacosSystemMediaControls.init` 只呼叫 `audio.AudioService.init(builder: AudioServiceCommandHandler.new)`，沒有任何 macOS 專屬的 Dart 呼叫（沒有 `Platform.isMacOS`、沒有 `AudioServiceConfig` 的 Android 欄位）；`AudioServiceCommandHandler`、`audioServiceMediaItemOf`、`audioServicePlaybackStateOf`（`media_controls_audio_service.dart`）也沒有 macOS 專屬分支。darwin 原生端是同一份程式。這是**讀碼結論**：在 iOS 上可以直接用同一份 Dart，但 `MacosSystemMediaControls` 這個類別名稱與 `platform.dart` 的 `TargetPlatform.macOS` 分支要另外接（`TargetPlatform.iOS` 目前落在 `PlatformCapabilities.none`，`platform.dart:188`）。實際 Now Playing／鎖定畫面／遠端指令的顯示與回應：**未實測**（模擬器的控制中心沒有跑，也不在實機）。
- 其他 iOS issue【文件】：audio_service **#1153**（open，2026-01-24，2026-04-19 更新）iOS 鎖定畫面不顯示歌曲 metadata（音訊正常；回報者的 handler 還在 `_configureAudioSession` 自己 `setActive(true)`，可能是用法問題，沒有結論）；#1127（open）iOS 更新 `mediaItem` duration 無效；#724（open，2021）iOS 控制中心。just_audio **#1427**（open，2025-05-31）「[iOS] Lock Screen Media Controls Are Transparent and Not Visible on Any IOS Device」（用 just_audio_background，未驗證是否與 audio_service 共通）。
- 不需要 entitlement；Info.plist 要 `UIBackgroundModes = [audio]`（2.5）。

---

## 4. flutter_secure_storage 11.2.0 / flutter_secure_storage_darwin 0.4.3（iOS：yes）

### 4.1 套件行為【原始碼】
- iOS 選項類別 `IOSOptions`（`flutter_secure_storage-11.2.0/lib/options/ios_options.dart`）繼承 `AppleOptions`：`accountName`（原生端映射 `kSecAttrService`，`FlutterSecureStorage.swift:21-22,222`）、`groupId`（映射 `kSecAttrAccessGroup`，**只在 `#if os(iOS)` 加進 query**，`:290-293`）、`accessibility`、`synchronizable`、`label`、…、`accessControlFlags`、`useSecureEnclave`。
- **預設 `accessibility = KeychainAccessibility.unlocked`**（`apple_options.dart:72`）→ `kSecAttrAccessibleWhenUnlocked`（`FlutterSecureStorage.swift:93`）。可用值：`passcode`、`unlocked`、`unlocked_this_device`、`first_unlock`、`first_unlock_this_device`。**裝置鎖定時，`unlocked` 的項目讀不到**；上游 issue **#743**（closed，2024-06-18，8 則留言）：鎖屏後在 isolate 讀值，`PlatformException(…Code: -25308, Message: User interaction is not allowed…)`；**#727**（closed，2025-03-20）同樣 -25308。
- `kSecUseDataProtectionKeychain` 在 iOS 原始碼是 `#if os(macOS)` 才設（`:284-288`）；iOS 的 keychain 一律是 data protection keychain，沒有 macOS 那種 login keychain／ad-hoc 簽章的 `-34018` 問題。
- `keychain-access-groups`：darwin README（`README.md:16-32`）與主套件 README（`:314-332`）要求在 `ios/Runner/DebugProfile.entitlements`／`Release.entitlements` 加 `<key>keychain-access-groups</key><array/>`。本專案 `ios/Runner/` **沒有 entitlements 檔**。Apple 文件（Security 的「Sharing access to keychain items among a collection of apps」）：Xcode 簽章時會自動加 `application-identifier` entitlement（Team ID + bundle ID），app 永遠屬於「只含自己」的 access group；沒有指定 `kSecAttrAccessGroup` 時項目寫進預設群組。所以**不加 entitlement 與 `groupId`，也能存取自己的項目**（沒有 App Group、不跨 app 分享的情況）【文件】。

### 4.2 實測：模擬器（Xcode 27.1，iOS 27.0，未簽章／模擬器自帶簽章）
scratch app 以 `FlutterSecureStorage(iOptions: …)` 做 write、read、readAll、delete、deleteAll【實測】：

| 設定 | 結果 |
|---|---|
| `IOSOptions()`（預設，accessibility `unlocked`） | write 後 read = `v1`；`readAll` = `(fmp-dev.k1)`；delete 後 read = null；`deleteAll` 後 read = null |
| `IOSOptions(accessibility: first_unlock, accountName: 'fmp-dev')` | 同上全部成功 |

- **iOS 的 `readAll` 可用**，不像 macOS login keychain 回 `-50`（`app/AGENTS.md` § 平台層、`FlutterSecureStorageAdapter.macos` 的註解）；`FlutterSecureStorageAdapter.system(flavor)`（`flutter_secure_storage_adapter.dart:31-40`）目前只傳 `aOptions`，iOS 會走預設 `IOSOptions`（`unlocked`、無 `accountName`）。
- 模擬器的 keychain 不能代表實機的簽章行為（沒有 provisioning profile 的情況）；**免費 personal team 實機簽章下 keychain 能不能用沒有在實機測**（本任務禁止）。依上面 Apple 文件，Xcode 自動簽章會帶 `application-identifier`，預設群組可用，不需要 Keychain Sharing capability；這是文件結論，不是實測。

### 4.3 重裝 App 後資料還在嗎
- **模擬器實測**：寫入一個 marker 後，（a）`simctl uninstall com.example.scratch` 再 `install` + 啟動，（b）再次 uninstall + install + 啟動，三次啟動都讀得到上一次寫的 marker（`marker before:` 依序為 `null` → `2026-11-03T23:59:34…` → `…00:06:34…` → `…00:06:48…`，來自 `simctl spawn log show` 的 `flutter: RES: marker before`）【實測，模擬器】。
- 文件：flutter_secure_storage **#897**（closed，2025-03-03，16 則留言）、**#482**（closed，2022-11-29）：iOS 上解除安裝再安裝，keychain 資料仍在，與 Android 不同；留言者建議用 shared preferences 旗標判斷是否第一次啟動。是 iOS 的 keychain 行為，不是套件 bug【文件】。
- **重簽／換 Team 的情況**（推論，未測）：access group = Team ID + bundle ID（Apple 文件）。用同一個 Apple ID（同一個 personal team Team ID）、同一個 bundle ID 重新簽名安裝，群組不變；經側載工具（AltStore、Sideloadly 等）重簽時若改了 bundle ID 或 Team，舊項目就讀不到。`app/AGENTS.md`／ADR 0009 §決定 9 寫的發版方式是「iOS 經 GitHub 發 IPA、由使用者側載時重簽」，這一條與它相關，需要在決定時考慮。

### 4.4 相關 issue【文件】
- **#1158**（closed，2026-09-08）iOS 升級到 10.1.0 後讀不到舊值（0.4.1 修正：舊版寫入的項目在沒有 `accessControlFlags` 時查不到）；**#1164**（closed，2026-09-17）0.3.x 把 `kSecAttrAccessible` 當嚴格篩選，改變 accessibility 後讀不到舊項目（0.4.3 起「跨 accessibility level 找項目」，CHANGELOG #1269）。意思是改 `accessibility` 設定是可行的，套件會跨 level 找。

---

## 5. flutter_inappwebview 6.2.0-beta.3 / flutter_inappwebview_ios 1.2.0-beta.3（iOS：yes，**使用真的子套件，不是 stub**）

- 子套件：`pubspec.lock` 有 `flutter_inappwebview_ios 1.2.0-beta.3`；`app/pubspec.yaml` 只把 Linux 與 macOS 換成 stub，iOS 沒有換【原始碼】。建置產物含 `flutter_inappwebview_ios_flutter_inappwebview_ios.bundle`【實測】。
- 建置：Xcode 27.1 與 CI 的 macos-26 映像都成功（見 1.1、1.2）。依賴 `swift-collections`（`Package.swift` 的 `from: "1.2.1"`，podspec 寫 `~>1.1.1`；實際走 SPM）。
- 最低 iOS 12.0（`Package.swift`）；專案 15.0，沒有衝突。
- 登入 WebView（ADR 0012 §決定 8、`PlatformCapabilities.loginWebView`）：iOS 底層是 WKWebView，cookie 走 `WKHTTPCookieStore`（與 macOS 子套件同類原始碼）；**登入流程沒有在 iOS 實測**，`InAppLoginWebView` 目前只有 Android／Windows 的建構（`app/AGENTS.md` § 平台層）。
- 需要的 Info.plist：基本載入頁面不需要特別 key（`http://` 非 loopback 同樣受 ATS，WKWebView 另受 `NSAllowsArbitraryLoadsInWebContent` 管，**未測**）。官方不要求 `NSCameraUsageDescription` 等，除非網頁要用相機／定位（iOS 26 的定位提示問題見 #2831 open，2026-05-07）。

---

## 6. 其他套件

### 6.1 path_provider 2.1.6 / `path_provider_foundation` 2.6.0
- 純 Dart + FFI（`objective_c` 9.5.0 的 native assets，`Frameworks/objective_c.framework` 已隨建置產出）【實測】。
- **模擬器實測路徑**（容器 `…/Containers/Data/Application/<UUID>/`）：`getApplicationSupportDirectory()` = `…/Library/Application Support`；`getApplicationCacheDirectory()` = `…/Library/Caches`；`getTemporaryDirectory()` = `…/Library/Caches`（與 Cache 相同，和 macOS 研究一致）；`getApplicationDocumentsDirectory()` = `…/Documents`；`getLibraryDirectory()` = `…/Library`；`getDownloadsDirectory()` = `…/Downloads`（沒有丟錯，iOS 的 `path_provider_foundation` 有回傳）【實測】。
- **iOS 與 macOS 差異**：macOS 的 application support／caches 會再加 `<bundle id>` 子目錄（macOS 研究 §6.1）；iOS 沒有加（路徑直接是 `Library/Application Support`）。**每個 App 容器本來就分開，dev 與 prod bundle id 不同所以自然分開**。
- iOS 容器內的 `Application Support`、`Documents` 會進 iCloud／iTunes 備份（`Caches`、`tmp` 不會）；本次沒有查 App 是否會把資料庫放在需排除備份的位置，只記事實。
- 用到的地方：`app/lib/platform/platform.dart:143,161,163,191,193,248,250,382`。

### 6.2 file_picker 13.1.0 / `file_picker_darwin` 2.1.3
- iOS 的 `pickFile(type: custom)`：`UIDocumentPickerViewController(forOpeningContentTypes:, asCopy: true)`（`IOSFilePickerHandler.swift:270-281`），選到的檔案先複製到 App 的暫存目錄再回傳路徑（`copyToTemporaryDirectory`）【原始碼】。
- 副檔名 → `UTType(filenameExtension:)`（`:327-333`）；實測（macOS 上的 `UTType` 與 iOS 共用）`js` → `com.netscape.javascript-source`、非動態型別【實測，小程式 `scratchpad/ut.swift`】。App 的 `.js` 篩選（`file_picker_dialogs.dart:18-21`）可用；從「檔案」App 選 `.js` 的互動沒有實測。
- `saveFile`：先把 bytes 寫到 `NSTemporaryDirectory()`，再開 `UIDocumentPickerViewController(forExporting: [tempFile], asCopy: true)`。
- `getDirectoryPath`（`FilePickerDialogs.pickDirectory`，目前只有 `lib/ui/debug/debug_plugin_dev.dart:130` 用）：`didPickDocumentsAt` 直接回 `urls.first?.path`；`file_picker_darwin` 全部 Swift 原始碼沒有 `startAccessingSecurityScopedResource` 或 bookmark（grep 無結果）【原始碼】，之後在該目錄讀寫的行為沒有測。
- Info.plist：自訂副檔名的文件選取器不需要使用說明；`PHPickerViewController`（`FileType.image/video/media`）不需要 `NSPhotoLibraryUsageDescription`（App 沒用這些 type）。`UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace` 不是選檔必要的。
- iOS 最低 14.0（README），專案 15.0 沒有衝突。

### 6.3 share_plus 13.3.1
- `UIActivityViewController`（`ios/share_plus/Sources/share_plus/FPPSharePlusPlugin.m`）；`SharePlusFileSharer` 呼叫 `ShareParams(files: …)`，沒有傳 `sharePositionOrigin`（`share_plus_file_sharer.dart:23-25`）。
- README `:263-271`（iPad）：iPad 的分享表是 popover，需 `sharePositionOrigin`；沒提供時「落在螢幕中央」（較早版本可能當機或沒回應，13.x 已處理）；`FPPSharePlusPlugin.m:414-423` 的註解說明 Xcode 26 起 iPhone 上 `popoverPresentationController` 也可能非 nil，外掛只在 iPad 設定。專案 `TARGETED_DEVICE_FAMILY = "1,2"`，所以 iPad 要考慮；iPhone 不受影響【文件、原始碼】。
- 不需要 Info.plist key。分享的檔案要在 App 容器內可讀（診斷包在 App 暫存／快取目錄）。

### 6.4 url_launcher 6.3.3 / `url_launcher_ios` 6.4.2
- `UrlLauncherOpener` 只呼叫 `launchUrl(uri, mode: LaunchMode.externalApplication)`（`url_launcher_opener.dart:12,19`），`app/lib` 沒有 `canLaunchUrl`【原始碼】。
- README `:44-50`：只有 `canLaunchUrl` 要列在 `LSApplicationQueriesSchemes`；`launchUrl` 開 `https` 不需要。模擬器實測 `canLaunchUrl('https://example.com')` = true（沒有設任何 key）【實測】。

### 6.5 connectivity_plus 7.3.1、package_info_plus 10.2.2
- 實測（模擬器）：`Connectivity().checkConnectivity()` = `[ConnectivityResult.wifi]`；`PackageInfo.fromPlatform()` = `com.example.scratch 1.0.0+1 installer=com.apple.simulator`【實測】。不需要 Info.plist key。`installerStore` 在實機側載時預期為 null 或 `com.apple…`（沒測）。

### 6.6 isar_community_flutter_libs 3.3.2（iOS）
- iOS 內容：`ios/isar.xcframework`（`ios-arm64`、`ios-arm64_x86_64-simulator` 兩個切片，`libisar.a` 靜態庫），podspec `s.platform = :ios, '11.0'`、`s.vendored_frameworks = 'isar.xcframework'`、`s.resource_bundles` 帶 `PrivacyInfo.xcprivacy`；沒有 `Package.swift`，所以 iOS 一定有 Podfile【原始碼】。
- 實測：`Pods` 解出 `isar_community_flutter_libs (1.0.0)`，建置產物有 `isar_community_flutter_libs.framework`（x86_64 + arm64）【實測】。Isar 資料庫本身（libmdbx）的 iOS 讀寫沒有實跑。
- 舊 App 在 iOS 沒發過（`app/AGENTS.md:115`），沒有舊 Isar 資料可匯入。

### 6.7 `flutter_js` 0.8.7 與 `fmp_quickjs`（**iOS 的缺口**）
- `flutter_js` 的 iOS 外掛（`ios/Classes/*.swift`、`FlutterJsPlugin.m`）是 JavaScriptCore；podspec `s.frameworks = 'JavaScriptCore'`、`s.platform = :ios, '8.0'`。**iOS 沒有 QuickJS 原生庫**【原始碼】。
- `flutter_js` 的 Dart 端 `lib/quickjs/ffi.dart:119-131`：`FLUTTER_TEST` 為真時 macOS 用 `DynamicLibrary.process()`，其他非 Android／Windows／Linux 平台（含 iOS）一律 `DynamicLibrary.process()`；`quickjs_runtime.dart:15` 同樣。App 的插件執行環境（`lib/plugins/runtime/plugin_worker.dart:181`）繼承 `QuickJsRuntime2`，走 QuickJS 路徑，不走 `getJavascriptRuntime` 的 JSC 分支。
- `app/packages/fmp_quickjs/pubspec.yaml` 的 `flutter.plugin.platforms` 只有 `macos: ffiPlugin: true`，套件目錄只有 `macos/`（podspec + `Classes/`），**沒有 `ios/`**；podspec 是 `s.dependency 'FlutterMacOS'`、`s.platform = :osx, '12.0'`【原始碼】。ADR 0036 §決定 1：「iOS 平台任務沿用同一個套件」。
- 實測：iOS 模擬器建置產物（`Runner.debug.dylib`、`Runner`、所有 `Frameworks/*.framework`）用 `nm` 找 `flutter_js` 會查的符號（`jsAtomToValue`、`jsCall`、`jsDefinePropertyValue` 等），**全部找不到**；`Frameworks/` 裡也沒有 `fmp_quickjs.framework` 【實測】。因此現況的 iOS 建置**可以編過但插件執行環境一用就會在 `lookup` 時找不到符號**（Dart 端的 `DynamicLibrary.process().lookup` 會拋錯；沒有實際跑插件，所以丟的例外型別是讀碼推論）。
- QuickJS 是直譯器，沒有 JIT，iOS 不需要 `allow-jit` 類 entitlement；flutter_js issue #189（open，2026-03-21）、#190（open，2026-09-05）要求加 SPM 支援，所以未來上游若改 SPM 會影響這個 CocoaPods 依賴（流程同 macOS）【文件】。
- 上游 flutter_js 的 iOS issue：#120（open，2023-06-22）iOS 上 `evaluate` 回 `Pointer<NativeType>: address=0xa`；#176（closed，2025-06-28）「macOS & iOS Crash: type 'Null' is not a subtype of type 'Pointer<NativeType>' on initialization」；#126（closed）找不到 JavaScriptCore；這些是 JSC 路徑，與本專案走 QuickJS 的路徑不同【文件】。
- `flutter_js.podspec` 對 iOS 模擬器寫 `VALID_ARCHS = x86_64`，但實測 arm64 切片仍建出（1.1）。

### 6.8 桌面套件在 iOS（window_manager 等）【原始碼 + 實測】
- `window_manager` 0.5.2 的 `pubspec.yaml:41-48` 只列 linux、macos、windows；`screen_retriever` 只有 linux／macos／windows 實作；iOS 建置產物裡**沒有** `window_manager`、`screen_retriever_*` 的 bundle 或 framework（見 1.1 的清單）。
- 實測（scratch app 含 `window_manager: 0.5.2`）：在 iOS 模擬器呼叫 `windowManager.ensureInitialized()` → `MissingPluginException(No implementation found for method ensureInitialized on channel window_manager)`。也就是**不會被編進 iOS、也不會讓建置失敗，但 Dart 端若被呼叫會丟 `MissingPluginException`**。App 的呼叫點只在 `lib/platform/window_chrome/`，由 `platform.dart` 的 Windows／macOS 分支組裝，iOS 目前不走【原始碼】。
- `smtc_windows`（`ffiPlugin` 只有 windows）、`flutter_rust_bridge`（純 Dart，無 plugin）、`media_kit`／`media_kit_libs_windows_audio`（windows 專用）不會編進 iOS；`media_kit_backend.dart` 的 Dart 程式仍會進 AOT，但不載入 libmpv（同 macOS 研究 §8）。
- `app/lib/platform/platform.dart:188`：`TargetPlatform.linux || TargetPlatform.iOS || TargetPlatform.fuchsia => AppPlatform._(capabilities: PlatformCapabilities.none)`，`main()` 看到沒有資料目錄就只開「此平台尚未支援」畫面（`app/AGENTS.md` § 平台層）【原始碼】。

---

## 7. iOS 要加的設定（依本調查彙整）

| 項目 | 內容 | 來源與狀態 |
|---|---|---|
| `Info.plist` `UIBackgroundModes` | `<array><string>audio</string></array>` | audio_service README `:403-415`【文件】；未在實機驗證 |
| `Info.plist` `NSAppTransportSecurity` | `NSAllowsArbitraryLoadsForMedia = true`（與 ADR 0036 §決定 7 的 macOS 一致）。只有來源可能回傳 `http://` 網域音訊網址時需要；IP 位址、loopback 不受 ATS 管 | 實測 ATS 違規 log 有無；沒有 http 網域音訊正例 |
| `Info.plist` `LSApplicationQueriesSchemes` | **不需要**（只用 `launchUrl`，不用 `canLaunchUrl`） | 原始碼 + 實測 |
| `Info.plist` 相簿／相機／麥克風／定位 `*UsageDescription` | **不需要**（file_picker 只用文件選取器；沒有用 `getRecordPermission`，所以 audio_session 的 `AUDIO_SESSION_MICROPHONE` 也不用開） | 原始碼 |
| entitlements | `ios/Runner/` 沒有 entitlements 檔；`keychain-access-groups`、App Groups 都不需要（預設 access group 存取自己的項目） | Apple 文件；實機簽章未測 |
| `IOSOptions` | `FlutterSecureStorageAdapter` 要傳 `iOptions`：`accountName: 'fmp-dev'／'fmp'`（與 macOS 同）；`accessibility` 預設 `unlocked` 會讓鎖屏後讀不到（見風險 R2），可改 `first_unlock` | 原始碼、模擬器實測兩種設定都可寫讀刪 |
| `platform.dart` 的 iOS 分支 | `TargetPlatform.iOS` 目前落在 `PlatformCapabilities.none`；需新增 iOS 的組裝（media controls 的 `AudioServiceCommandHandler` 可共用，secure storage 的 iOS 選項、`appleShortcutModifier` 已預留） | 原始碼 |
| `fmp_quickjs` | `pubspec.yaml` 加 `ios: ffiPlugin: true`，新增 `ios/fmp_quickjs.podspec`（`s.dependency 'Flutter'`、`s.platform = :ios, '15.0'`、同樣的編譯旗標與 `s.library = 'c++'`），`Classes/` 沿用同一份原始碼 | 缺口已實測（iOS 產物沒有符號） |
| `ios/Podfile`、`Podfile.lock` | 要提交；Podfile 要照 macOS 的做法對應六個 flavor build configuration（目前只對應三個模式） | `app/AGENTS.md` § 平台層；ADR 0036 §決定 10 |
| iPad | `TARGETED_DEVICE_FAMILY = "1,2"`：share_plus 的 `sharePositionOrigin`（沒給則落在螢幕中央）；`UISupportedInterfaceOrientations~ipad` 已有四個方向 | 文件、原始碼 |

## 8. 風險

- **R1（高，已實測）插件引擎在 iOS 沒有 QuickJS**：`fmp_quickjs` 只有 macOS，iOS 產物裡沒有 `flutter_js` 要找的符號；iOS 建置會過、第一次啟動插件執行環境才失敗。CI 的 `app-build-ios` 現在抓不到這個，只有 macOS job 有 `nm` 符號檢查與 `install_search_play_test -d macos`（`ci.yml:448-466`）。
- **R2（中，讀碼推論）鎖屏背景播放時讀 keychain**：`flutter_secure_storage` 預設 `accessibility = unlocked`，裝置鎖定時讀取會回 `-25308`（issue #743、#727）；背景播放、鎖屏狀態下換曲若要讀憑證（帳號 cookie）就可能失敗。換成 `first_unlock` 的行為是文件結論，沒有實機驗證。套件會跨 accessibility level 找舊項目（0.4.3，#1164）。
- **R3（中，讀碼推論）iOS 來電中斷不會自動續播**：audio_session 在 iOS 把中斷開始一律報 `unknown`，現有 `respondToInterruption` 對應成 `lost`（永久失焦點）、不設 `pausedByInterruption`，掛斷後的 `InterruptionEnded(resume: true)` 被路由忽略；`backend_rules.dart:108-114` 已註明「接 iOS 時要另外對應」。沒有在實機接電話驗證。
- **R4（中，未驗證）背景播放與鎖定畫面**：`UIBackgroundModes: audio`、Now Playing、遠端指令（含 `changePlaybackPosition`）都只讀了碼，模擬器沒有驗證；`audio_service` 0.18.19 的 `center.playbackState` 在 iOS 不設（#1139，修正未在釘的版本）。just_audio #747（鎖屏一段時間後帶標頭的來源異常）、audio_service #1153／just_audio #1427（鎖定畫面資訊問題）是上游回報，沒有結論。
- **R5（中）免費 Apple ID 側載與 keychain／資料**：keychain 項目在解除安裝後仍存在（模擬器實測、#897/#482）；若重簽改了 bundle ID 或 Team ID，access group 改變，舊憑證讀不到（推論）。personal team 的 7 天簽章到期、App ID 數量限制沒有在這次查。
- **R6（低～中）上游 `flutter_inappwebview_ios` 與較新 Xcode**：現在 Xcode 27.1 與 CI（26.6）都建得過；同檔案在 Xcode 26.4.1 對 1.1.2 有回報（#2830），修正 PR #2809 仍 open。若 CI 映像升級或 Flutter 換版本，這是 iOS 與 macOS 都可能碰到的建置風險。
- **R7（低）AVPlayer 格式**：iOS 與 macOS 一樣不能播 WebM（實測 `-11828`）與 FLV（實測 `-11828`）；Ogg Opus 在 iOS 27 能播；單一 `.m4s` 需要 CDN 的 `Content-Type` 不是 `application/octet-stream`（實測會 Cannot Open）。真實 CDN 內容沒測。
- **R8（低）`AVURLAssetHTTPHeaderFieldsKey` 是非公開 API**：Apple 沒保證；本次在 iOS 27.0 模擬器可行，沒有測 iOS 27.1 模擬器與實機。
- **R9（低）iOS 的 `Podfile` 對 `Debug-dev` 等 flavor configuration 沒有對應**（CocoaPods 一律當 release），與 macOS 當初同一個問題，修法已記在 ADR 0036 §決定 10。

## Caveats / Not Found

- **沒有 Xcode 26.6 可本機重現**；`flutter_inappwebview_ios` 在 26.6 能建的證據來自 CI run `41656986777`（image `macos-26-arm64`，log 未印 Xcode 版本）。
- 沒有在實機、也沒有在 iOS 27.1 模擬器測播放；測試只在 iOS 27.0 模擬器（iPhone 18 Pro）。模擬器不驗證：背景暫停、鎖定畫面、來電中斷、耳機拔除、實機簽章下的 keychain、personal team 的 provisioning。
- 沒有測真實 Bilibili／YouTube／NetEase 網址與 CDN；沒有測 live HLS、E-AC-3；`http://` 網域音訊的「放行」正例沒做（只驗了 ATS 違規 log 有無）。
- 登入 WebView、檔案選取（從「檔案」App 選 `.js`）、分享表、Isar 資料庫讀寫在 iOS 都沒有互動驗證，只有建置、符號、原始碼層面的結論。
- 沒有查 App Store／TestFlight／Apple Developer 計畫的限制，也沒有查 personal team 的 7 天簽章與 App ID 配額。
- 上面「Apple 文件」引用取自 `developer.apple.com/tutorials/data/documentation/...` 的 JSON 內容（Security 的 keychain 分享文件、`NSAllowsArbitraryLoadsForMedia`、`UIBackgroundModes`）；ATS 對 IP 位址不套用的說法來自 Apple ATS 文件與本機實測（192.168.x 位址可播）。
