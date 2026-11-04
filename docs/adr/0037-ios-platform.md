# 0037 — iOS 平台：免費帳號自動簽章、插件引擎沿用 fmp_quickjs、背景播放與 iOS 的中斷語意、Apple 共用實作、發未簽章 IPA

- 狀態：已採納（擁有者 2026-11-04 核可）
- 日期：2026-11-04
- 影響範圍：`app/ios/`（`Info.plist`、Podfile、xcconfig、pbxproj、圖示與啟動畫面）、`app/packages/fmp_quickjs/`、`app/lib/platform/` 的 iOS 組裝與共用實作、`app/lib/playback/backends/` 的中斷對應、`app/lib/platform/share/` 的介面、CI 的 iOS job、`app-release.yml`、`verify-on-device` skill

## 背景

ADR 0009 §決定 4：平台的實作在平台任務開始時才加。擁有者的順序是 U → macOS → iOS → M6（`milestones.md`，2026-10-24），要在 iPhone 上日常使用。macOS 已完成（ADR 0036），iOS 沿用它的大部分做法。研究在 `.trellis/tasks/11-03-ios-platform/research/`：

- `platform-inventory.md`：每個能力在 iOS 要什麼、macOS 的檔案能不能共用。
- `packages-ios.md`：釘住版本的套件在 iOS 的行為，含模擬器實測（格式、標頭、ATS、keychain、路徑）。
- `plugin-runtime-ios.md`：QuickJS 怎麼編進 iOS、背景時 JS 會不會被凍結。
- `signing-distribution-ios.md`：免費與付費帳號、這台 Mac 的簽章狀況、未簽章 IPA。

現況：`platform.dart` 對 iOS 回 `PlatformCapabilities.none`，畫面只有「此平台尚未支援」。有六件事不能照既有 ADR 直接做：

1. **簽章與散佈**。ADR 0026 §決定 4 把「要不要實機、要不要付費帳號」留給這個任務；ADR 0022 §決定 3 寫「iOS 沒有發佈物，散佈方式由 iOS 平台任務決定」。
2. **插件引擎**。`flutter_js` 0.8.7 在 iOS 只附 JavaScriptCore；插件 worker 繼承 `QuickJsRuntime2`，iOS 的建置裡找不到任何 QuickJS 符號（`packages-ios.md` §6.7，實測）。
3. **背景**。`Info.plist` 沒有 `UIBackgroundModes`。沒有它，App 進背景後 Dart 與 JS 一起被凍結（`plugin-runtime-ios.md` §3，模擬器實測 28 秒沒有任何 tick）。
4. **音訊中斷**。audio_session 在 iOS 的中斷開始一律報 `unknown`。現有對應把它當成「永久失去焦點」，來電掛斷後不會續播（`backend_rules.dart` 的註解、`packages-ios.md` §2.5）。
5. **憑證**。`flutter_secure_storage` 在 iOS 預設 `accessibility: unlocked`，鎖屏後讀不到（`-25308`）；背景換曲時插件要讀帳號憑證（`packages-ios.md` §4.1）。
6. **帶 macOS 名字的共用邏輯**。`MacosAppDataDirectory`、`MacosSystemMediaControls`、`macosLegacyDataLocator` 在 iOS 邏輯相同；`AndroidAppRestarter` 的邏輯 iOS 也要用（`platform-inventory.md` §2）。

擁有者 2026-11-04 已定：先用免費 Apple ID；開發與驗收用這台 Mac 上已有的 Apple Development 憑證，從 Mac 安裝；付費帳號留到 M9；本機簽名資訊不進 repo；iPhone 與 iPad 都支援；Live Activity 歌詞移到 M7；功能做完、模擬器驗過，再約擁有者在 iPhone 上驗一次。技術細節照研究建議定案。

## 考慮過的選項

### 簽章

- **付費 Developer Program**：profile 長效，不必每週重裝（`signing-distribution-ios.md` §1）。擁有者決定留到 M9，與 macOS 的發版簽章一起定。不採用。
- **免費 personal team、手動簽章**（同 macOS 的做法）：免費帳號的 profile 由 Xcode 自動產生，7 天就換一份；手動簽章要每週自己指定新的 profile。不採用。
- **免費 personal team、自動簽章**（採用）：Xcode 依 `DEVELOPMENT_TEAM` 自動註冊 App ID 與裝置、產生 profile。Team ID 放在不進 repo 的檔。免費帳號可用 Background Modes 與 Keychain（Apple 的能力表，`signing-distribution-ios.md` §1）。

### 散佈

- **這個任務不發 IPA，等 M9**：少一個 PR。但 ADR 0009 §決定 5 早已定了「經 GitHub 發 IPA、側載」，而且付費帳號也幫不了別人側載（`signing-distribution-ios.md` §5）。不採用。
- **發未簽章 IPA**（採用）：`flutter build ios --release --no-codesign` 之後把 `Runner.app` 包成 `Payload/` 的 zip（實測可行，`signing-distribution-ios.md` §4）。使用者用 SideStore／AltStore 以自己的 Apple ID 重簽。發版在 M9 之前只能手動觸發，不會有人拿到。

### 插件引擎

- **改用 JavaScriptCore**：理由同 ADR 0036 的選項 A，worker 要重寫。不採用。
- **`fmp_quickjs` 加一份 `ios/` podspec**：實測可行（`plugin-runtime-ios.md` §2），但 podspec 與 6 個轉接檔要維護兩份。
- **`fmp_quickjs` 改成 iOS 與 macOS 共用的 `darwin/`**（採用）：Flutter 的 `sharedDarwinSource`，`audio_service`、`just_audio` 都這樣做。一份 podspec 以 `s.ios`／`s.osx` 分平台設定。

### 音訊中斷

- **打開 just_audio 的 `handleInterruptions`**：README 說 iOS 支援。但它在 0.10.6 的 duck 結束時把音量乘 2，而且自己暫停、續播，控制器的狀態會和引擎分岔（`respondToInterruption` 的註解）。不採用。
- **在後端判斷平台**：違反「平台判斷只寫在組裝點」（`app/AGENTS.md` § 平台層，lint `fmp_platform_checks`）。不採用。
- **平台宣告中斷事件的語意，後端依宣告對應**（採用）：`PlaybackSupport` 多一個欄位，由組裝點填。

### 共用邏輯的命名

- **iOS 另寫一份複本**：兩份相同的程式碼與測試。不採用。
- **改名成 Apple 共用**（採用）：repo 已有 `appleShortcutModifier`。只是值的宣告（格式表、字型、快取大小）各平台各一份常數，因為各有各的實測依據（macOS 的 `macosCacheSizes` 也是自己一份，沒有共用 Windows 的）。

### 重啟

- **行程內重建**（關掉資料庫、重建 provider，不結束行程）：要改 `main()` 的啟動流程，範圍大。不採用。
- **結束行程，請使用者再開**（採用）：同 Android（`restartsItself: false`）。Apple 的 QA1561 不建議 App 自己結束，但那是 App Store 的審查問題，FMP 不上架（ADR 0009 §決定 5）；重設與還原很少用，對話框已寫明「App 會關閉，請自己再開啟」。

### 憑證的 accessibility

- **`unlocked`（套件預設）**：鎖屏後讀不到，背景換曲要憑證的插件會失敗。不採用。
- **`first_unlock_this_device`**：不隨加密備份搬到新手機，換機要重新登入。
- **`first_unlock`**（採用）：開機後第一次解鎖起都讀得到，鎖屏也讀得到；套件 README 給背景讀取的建議值。換機以加密備份還原時憑證跟著走。

### 登入 WebView

- **宣告沒有（同 macOS）**：帳號頁只剩 QR 與貼上 cookie。
- **宣告有**（採用）：`flutter_inappwebview_ios` 1.2.0-beta.3 在本機 Xcode 27.1 與 CI 都建得過（`packages-ios.md` §1.2），和 macOS 的狀況不同。

## 決定

1. **簽章與安裝**：
   - 用免費 Apple ID 的 personal team。App target `CODE_SIGN_STYLE = Automatic`。
   - `DEVELOPMENT_TEAM` 寫在 `ios/Flutter/Signing.xcconfig`，由 `ios/Flutter/Debug.xcconfig`、`Release.xcconfig` 以 `#include?` 讀。這個檔 gitignore，不進 repo（同 ADR 0036 §決定 3 的更正）。pbxproj 不得有 `DEVELOPMENT_TEAM`：在 Xcode 的 Signing & Capabilities 選 team 會寫進 pbxproj。
   - 模擬器與 CI 不簽（`--simulator`、`--no-codesign`）。實機一定要簽，只在這台 Mac 上建。
   - 實機裝 release 模式的 dev flavor：iOS 14 起 debug 建置不能從主畫面開。profile 7 天到期，從 Mac 重建重裝；同一個 team 重裝，資料與 keychain 都留著。
   - 驗證只裝 dev（`com.personal.fmp.dev`），佔免費帳號每台 3 個 App 中的 1 個。
   - 付費 Developer Program 在 M9 與 macOS 的發版簽章一起決定。
2. **散佈**：`app-release.yml` 加 `fmp-v{版本}-ios.ipa`：prod、未簽章，根目錄是 `Payload/Runner.app`。使用者以 SideStore／AltStore 重簽安裝。沒有 `fmp-latest-*` 別名（舊版沒發過 iOS）；App 內更新是 `none`，只顯示「前往下載頁」（ADR 0022 §決定 5）。
3. **插件引擎**：
   - `fmp_quickjs` 的 `macos/` 改成 `darwin/`，`pubspec.yaml` 的 `ios`、`macos` 都是 `ffiPlugin: true` 加 `sharedDarwinSource: true`。
   - 一份 podspec：`s.ios.dependency 'Flutter'`、`s.osx.dependency 'FlutterMacOS'`，iOS 最低 13.0、macOS 照舊 12.0，編譯旗標不變。
   - 沿用 Podfile 預設的 `use_frameworks!`（動態 framework），不用另加連結旗標。改成靜態連結會讓 55 個符號全部找不到（`plugin-runtime-ios.md` §2），CI 的符號檢查與模擬器整合測試會抓到。
   - 如果 Flutter 工具不接受 FFI plugin 的 `sharedDarwinSource`，退回 `ios/` 另一份 podspec（研究實測的做法），結果記在這裡。
4. **原生專案**（`ios/Runner/Info.plist`）：
   - `UIBackgroundModes` = `[audio]`：背景播放與背景解析下一首。
   - `NSAppTransportSecurity` → `NSAllowsArbitraryLoadsForMedia` = true：同 macOS（ADR 0036 §決定 7）。iOS 上 `http://` 網域的媒體被 ATS 擋（模擬器實測 `-11800`，`packages-ios.md` §2.4）；Dart 的網路層不經 ATS。
   - `CFBundleName` 從字面值 `fmp` 改成 `$(APP_DISPLAY_NAME)`，同 macOS。
   - 不加 entitlements 檔、`keychain-access-groups`、App Groups、`*UsageDescription`、`LSApplicationQueriesSchemes`：用不到（`packages-ios.md` §7）。
   - 最低版本維持 iOS 15.0。`TARGETED_DEVICE_FAMILY = "1,2"`（iPhone 與 iPad）維持；四個方向都允許；不設 `UIRequiresFullScreen`，iPad 可以分割畫面。
   - 圖示由 `assets/icon/app_icon.png` 產生，取代 Flutter 預設圖：iOS 要 1024 的不透明方圖，圓角由系統裁。啟動畫面的底色跟著系統的深淺色，深色模式開 App 時不閃白。
5. **CocoaPods 與 Swift Package Manager**：照 ADR 0036 §決定 10。
   - 提交 `ios/Podfile`（`platform :ios, '15.0'`，六個 flavor configuration 對到 debug／release）、`Podfile.lock`、xcconfig 的 `#include? Pods…`、pbxproj 與 workspace 的變動。
   - 也提交兩份 `xcshareddata/swiftpm/Package.resolved`：它釘住 `flutter_inappwebview_ios` 帶進來的 `swift-collections`。Swift 官方建議 App 提交 `Package.resolved`。
   - 之後建置不再改動追蹤中的檔案。
6. **憑證**：iOS 用 data protection keychain（套件在 iOS 的唯一做法）。
   - `FlutterSecureStorageAdapter.system(flavor)` 另帶 `iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock, accountName: 'fmp-dev'／'fmp')`。`accountName` 同 macOS 的帳號名。
   - 不設 `groupId`：預設的 access group 就是 Team ID 加 bundle id（Apple 文件，`packages-ios.md` §4.1）。
   - iOS 的 `readAll` 正常（模擬器實測），`deleteAll` 照其他平台只刪自己前綴的鍵。
   - 已知行為：解除安裝後 keychain 項目仍在（iOS 的設計，`packages-ios.md` §4.3）；重新安裝、再裝同一個插件時，舊憑證會回來。換 Team 重簽（例如 SideStore 用別的 Apple ID）就讀不到，要重新登入。
7. **播放格式**：`just_audio`（AVPlayer），宣告同 macOS：`mp4/aac`、`mp3/mp3`、`flac/flac`、`wav/pcm_s16le`、`hls/aac`。
   - 沒有 `webm/opus`：AVPlayer 不播 WebM（模擬器實測 `-11828`）。
   - 也不宣告 `ogg/opus`：iOS 27 能播 Ogg Opus（實測），但插件的 Opus 都是 WebM 容器（YouTube 插件以 mime 的 `audio/webm` 取容器名），宣告了也沒有候選。
   - 自訂標頭走 `AVURLAssetHTTPHeaderFieldsKey`，HLS 的每個分段都帶到（模擬器實測，`packages-ios.md` §2.2）。
   - B 站直播走 HLS：插件依 `hls/aac` 選 h5 的網址（ADR 0036 §決定 7），iOS 不必改插件。
8. **音訊中斷**：
   - `PlaybackSupport` 加 `interruptions`（`AudioInterruptions.androidAudioFocus`／`appleAudioSession`／`none`），宣告 audio_session 事件的語意。Android 是 `androidAudioFocus`；iOS、macOS 是 `appleAudioSession`（macOS 的 audio_session 不發中斷事件，宣告只說明語意）；Windows 的 media_kit 不聽，是 `none`。
   - `respondToInterruption` 多收這個值。`appleAudioSession` 的對應照 Apple 的「Handling audio interruptions」：
     - 開始（一律 `unknown`）→ 暫時中斷，記下「因中斷而暫停」；
     - 結束帶 `shouldResume`（audio_session 報 `pause`）→ 可續播；
     - 結束沒帶 `shouldResume`（`unknown`）→ 不續播。
   - Android 的對應不變。路由器、控制器、`NowPlayingPublisher` 不改。
   - 已知限制：別的 App 開始播放時 iOS 只發開始、不發結束。FMP 停在「因中斷而暫停」，直到使用者按播放或暫停。
9. **系統媒體控制**：`audio_service`（ADR 0018 §決定 8），和 macOS 共用同一個實作（改名見決定 13）。
   - 宣告 `MediaControlsSupport(supportsSeek: true)`，不設 `positionRefresh`：鎖定畫面可以拖進度（`changePlaybackPosition`，`packages-ios.md` §3）。
   - `MediaPhase.interrupted` 照共用的轉換（播放中加緩衝）。
   - audio_service 0.18.19 在 iOS 不設 `playbackState`（上游 #1139，修正不在釘的版本），實機看鎖定畫面與控制中心的顯示，不對再處理。
10. **重啟**：`restartsItself: false`。重設與還原後先 `publish(NowPlaying.nothing)` 加 `dispose()` 收掉 Now Playing，再 `exit(0)`；使用者自己再開。Android 與 iOS 共用同一個實作（改名見決定 13）。
11. **登入 WebView**：`loginWebView: true`，用真的 `flutter_inappwebview_ios`。
    - `InAppLoginWebView.ios()`：沒有 WebView 環境；cookie 經 WKWebView 的 cookie store。
    - UA：WKWebView 的預設 UA 沒有 `Version/…` 與 `Safari/…`，Google 會當成嵌入式 WebView 擋下（同 Android 的 `; wv`，ADR 0029 的 R1）。`iosLoginUserAgent` 補成 Safari 的形狀，系統版本由組裝點給。
    - 在模擬器上 Google 仍擋時，停下來回報擁有者，不自行改成宣告沒有。
12. **其他能力的宣告**：

    | 欄位 | iOS | 理由 |
    |---|---|---|
    | `dataDirectory` | 有：容器的 `Library/Application Support` | path_provider 實測（`packages-ios.md` §6.1）；dev 與 prod 是不同容器。留在 iCloud 備份裡：音樂庫是使用者資料（Apple 的檔案系統指南：Application Support 放 App 產生、要備份的資料） |
    | `singleInstance` | 沒有 | iOS 本來就只有一個行程 |
    | `fontFallback` | 繁中 `PingFang TC`、簡中 `PingFang SC` | 同 macOS 的理由（flutter/flutter#103811）；模擬器上看「骨」「直」的字形確認 |
    | `fontChoices` | `PingFang TC`、`PingFang SC`、`Hiragino Sans` | ADR 0035 §決定 5 |
    | `cache` | 128 MiB、100 張、50 MiB | ADR 0016 §決定 3 的行動平台值 |
    | `networkInterfaces`、`urlOpener`、`files`、`shareFiles` | 有 | 共用的實作；分享加 iPad 的錨點（決定 14） |
    | `pluginDevTools` | 沒有 | 同 Android：`file_picker_darwin` 不處理 security-scoped 目錄（`packages-ios.md` §6.2） |
    | `customTitleBar` | 沒有 | `window_manager` 不編進 iOS，呼叫會拋 `MissingPluginException`（實測，`packages-ios.md` §6.8）；組裝點不給 `windowChromeFactory` |
    | `shortcutModifier` | `appleShortcutModifier` | iPad 外接鍵盤用 ⌘（ADR 0035 §決定 7） |
    | `appInfo` | `platform: 'iOS'`，`homeDirectory` 是 `HOME`（App 容器） | 畫面把路徑顯示成 `~/Library/…`；模擬器的容器路徑含 Mac 的使用者名稱，log 遮蔽靠它。更正（2026-11-04，PR 4 實測）：iOS 的 Dart 讀不到環境變數與 `main()` 的參數，`HOME` 是空的；`homeDirectory` 改由 `Directory.systemTemp.path`（`<容器>/tmp`）的上一層推出（`iosHomeDirectory`）。開發入口（`FMP_DEV_PLUGIN`、`FMP_LEGACY_DIR`）因此多一個編譯期的 `--dart-define` 來源，只在模擬器可用 |
    | `legacyDataLocator` | prod 沒有位置；dev 只看 `--fmp-legacy-dir` | 舊版沒發過 iOS（`app/AGENTS.md` § App 身分） |
13. **共用實作的命名**：
    - 有邏輯的類別與函式改成 Apple 共用，macOS 與 iOS 都用：
      - `MacosAppDataDirectory` → `AppleAppDataDirectory`（`app_data_directory_apple.dart`）；
      - `MacosSystemMediaControls` → `AppleSystemMediaControls`（`media_controls_apple.dart`）；
      - `macosLegacyDataLocator` → `appleLegacyDataLocator`。
    - `AndroidAppRestarter` 改名 `ExitAppRestarter`（`app_restart_exit.dart`），Android 與 iOS 共用，以行為命名。
    - 只是宣告的常數各平台各一份：`audio_ios.dart`、`fonts_ios.dart`、`cache_sizes_ios.dart`。
    - 內部改名不留舊名（相容層）。
14. **手機與 iPad 的 UI**：沿用現有的 `WindowClass` 版面，不另做 iPad 專屬的版面。
    - 補充（2026-11-04，擁有者決定）：右側「正在播放」面板另看視窗高度，高度是 M3 的 compact（< 480，橫向的手機）時不並排，照直放的呈現；iPad 與桌面照舊。左側導覽側欄不變（M9 打磨）。
    - 補充（2026-11-04，擁有者決定）：窄版設定頁點進的組與 Debug 頁的區塊改成推上去的 route（原本是頁面原地換內容），iOS 才有跟手指的右滑返回；三個平台因此都有換頁轉場，寬版兩欄不變。全畫面右滑返回不做，留到 M9。
    - `FileSharer.shareFiles` 多一個 `origin`（分享按鈕在螢幕上的位置），交給 share_plus 的 `sharePositionOrigin`：iPad 的分享表是 popover，要錨點（share_plus README 的 iPad 段）。
    - 在模擬器驗：
      - 動態島、home indicator、右滑返回；
      - 鍵盤不蓋住輸入框；
      - iPhone 橫向；
      - iPad 直橫向與分割畫面時版面跟著寬度換；
      - 深淺色的狀態列。
    - 驗出需要改版面、改互動的（設計稿等級），先回報擁有者，不在這個任務自行決定。
15. **CI**：iOS job 留在現有的 `app-build-ios`，時間上限從 45 分改 60 分。
    - prod 的 release 建置（`--no-codesign`）之後，以 `nm` 查 `fmp_quickjs.framework` 有沒有 `_jsNewRuntime`、`_jsSetMemoryLimit`。
    - 開一台模擬器跑 `install_search_play_test.dart --flavor dev`：ADR 0009 §決定 9 要求的模擬器測試，也守插件引擎有編進 App。
    - 原本的 dev debug 實機建置拿掉：模擬器測試已建 `Debug-dev`，scheme 與 configuration 照樣有守。
    - `secure_storage_test.dart` 不進 CI，在模擬器與實機手動跑。
16. **驗證的分工**：
    - 每個 PR 在 iOS 模擬器驗（`orca emulator` 操作、讀回畫面才算數）。操作步驟寫在 `verify-on-device` 的 `references/ios.md`。
    - 功能全部做完、模擬器（iPhone 與 iPad）走完驗收之後，約擁有者在他的 iPhone 上驗一次。只能在實機驗的：
      - 鎖屏後的背景播放與換曲；
      - 鎖定畫面與控制中心的 Now Playing、遠端指令、拖進度；
      - 來電中斷與掛斷後續播；
      - 免費帳號簽章下的 keychain，鎖屏時讀得到；
      - 登入（QR 要第二支裝置掃）；
      - 拔耳機暫停。
    - 擁有者要在場的步驟先問時間：開發者模式、信任電腦與開發者、解鎖、登入、接電話。
    - 之後每個里程碑在 iOS 模擬器冒煙測試一次（ADR 0027 §決定 3）。
17. **Live Activity 歌詞**（ADR 0021 §決定 10）移到 M7：那時才有歌詞可顯示。它要 Widget Extension，會多吃一個免費帳號的 App ID 與安裝額度（`signing-distribution-ios.md` §1），M7 一併評估。

採用的慣例：
- Apple：
  - Background Modes 的 `audio`；
  - ATS 的 `NSAllowsArbitraryLoadsForMedia`；
  - Keychain 的 `kSecAttrAccessibleAfterFirstUnlock`（背景讀取）；
  - 「Handling audio interruptions」的 `shouldResume`；
  - Xcode 自動簽章。
- Flutter：
  - flavors-ios 文件的 Podfile 對應；
  - plugin 的 `sharedDarwinSource`（`audio_service`、`just_audio` 的做法）。
- 套件 README：
  - `audio_service` 的 iOS 設定；
  - `flutter_secure_storage` 的 accessibility；
  - `share_plus` 的 iPad 錨點。
- 散佈：Spotube 等以 GitHub 發未簽章 IPA、讓使用者側載的開源 App（ADR 0014 已引用 Spotube 的側載發佈）。

## 後果

- 好的：
  - 插件在 Android、macOS、iOS 跑同一份 QuickJS，契約測試的結果適用；
  - macOS 與 iOS 共用資料目錄、媒體控制、舊資料 locator，修一處兩邊都好；
  - 建置不再改動追蹤中的檔案；
  - CI 從此在 iOS 模擬器上跑插件與播放流程。
- 壞的：
  - 免費帳號每 7 天要從 Mac 重裝一次；
  - 重設與還原後 App 直接關閉，看起來像閃退（對話框有寫）；
  - 發出去的 IPA 未簽章，這個任務沒有用 SideStore 實際裝過；
  - 解除安裝後 keychain 留著舊憑證；
  - Google 對 WebView 的偵測改了，iOS 的登入 UA 就要跟著改；
  - `AVURLAssetHTTPHeaderFieldsKey` 不是公開 API（`packages-ios.md` §2.3）。
- 之後要注意：
  - `flutter_js`、`isar_community_flutter_libs` 加了 SPM 支援時，重新看 Podfile 還要不要；
  - CI 的 Xcode 升級時看 `flutter_inappwebview_ios` 還建不建得過（上游 #2830、#2809）；
  - just_audio #747：鎖屏一段時間後帶標頭的來源異常，實機長時間播放時留意；
  - `com.personal.fmp.dev` 若已被別的 team 註冊，Xcode 會拒絕。換 bundle id 是身分變更，要另立 ADR。
- 修訂：
  - ADR 0022 §決定 3 的「iOS 沒有發佈物」改為本 ADR §決定 2；
  - ADR 0026 §決定 4 的「iOS 要不要實機、要不要付費帳號」由本 ADR §決定 1、16 決定；
  - ADR 0021 §決定 10 的 Live Activity 移到 M7（本 ADR §決定 17）。

## 如何確認

- `test/identity/apple_identity_test.dart`，每條都有變異案例：
  - iOS 的 `Info.plist` 有 `UIBackgroundModes` 含 `audio`、`NSAllowsArbitraryLoadsForMedia`；`CFBundleName` 指向 `$(APP_DISPLAY_NAME)`；
  - App target 自動簽章，iOS 與 macOS 的 pbxproj 都沒有 `DEVELOPMENT_TEAM`；
  - `Flutter/Debug.xcconfig`、`Release.xcconfig` 以 `#include?` 讀 gitignore 的 `Signing.xcconfig`；
  - Podfile 對應六個 configuration。
- `test/platform/platform_test.dart`：iOS 的宣告與實作對得上，沒有 `windowChrome`。
- `test/playback/backends/backend_rules_test.dart`：Apple 的中斷對應。
- `test/platform/secure_storage_test.dart`：iOS 的選項。
- CI 的 iOS job：符號檢查、模擬器上的 `install_search_play_test.dart`。
- `test/release/`：IPA 的檔名、根目錄與 `Info.plist`。
- 實機（擁有者的 iPhone）：決定 16 的清單。步驟寫在 `references/ios.md`，結果記在任務的 `research/ios-acceptance.md`。
