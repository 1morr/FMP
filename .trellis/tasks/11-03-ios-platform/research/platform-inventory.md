# Research: iOS 平台任務的程式碼盤點

- **Query**: 盤點 `app/lib/platform/` 各能力在 Android／Windows／macOS 的值與 iOS 該怎麼做、macOS 檔案哪些可共用、`app/ios/` 原生專案與未提交的 CocoaPods 改動、`apple_identity_test.dart` 缺什麼、UI 的 iOS 慣例現況、CI、舊 App 的 iOS 痕跡、既有 ADR 對 iOS 的決定
- **Scope**: internal（只讀程式碼與 `gh run view`；沒有改任何 research/ 以外的檔）
- **Date**: 2026-11-03

行號以 2026-11-03 的工作區為準（HEAD `aa309a2d`，`app/ios/` 有未提交的 CocoaPods 改動，見 §3.4；這些檔沒有動）。範本是 `.trellis/tasks/archive/2026-11/10-28-macos-platform/research/platform-inventory.md`。

---

## 1. `app/lib/platform/` 能力盤點

### 1.1 `PlatformCapabilities` 逐欄（`platform_capabilities.dart`）

「iOS 要新實作」欄：是＝要新增實作檔或新 factory；共用＝沿用現有程式；宣告＝只要在組裝點填值。

| 行 | 欄位 | Android | Windows | macOS | `none`（iOS 現值） | iOS 應是什麼／要不要新實作 |
|---|---|---|---|---|---|---|
| 65 | `dataDirectory` | true | true | true | false | true。path_provider 的 `getApplicationSupportDirectory`（iOS 沙盒的 `Library/Application Support`）可沿用，但 macOS 的 `MacosAppDataDirectory`（`app_data_directory_macos.dart:10–18`）註解寫的是 `~/Library/Application Support/<bundle id>`、不開沙盒；iOS 邏輯相同（`Directory(path).create(recursive: true)`），dev／prod 靠 bundle id 分容器。是否共用同一個類別、改名，是設計決定（見 §7）。`AppPlatform._` 的 assert（`platform.dart:76–78`）要求有資料目錄就必須有 `restarterFactory`、`legacyDataLocator`，另外 `main()` 對 `appInfo!` 沒有 assert 守（`lib/main.dart:152`） |
| 70 | `singleInstance` | false | true（`main.cpp` mutex） | true（`LSMultipleInstancesProhibited`） | false | false，iOS 本來就單一行程；宣告 |
| 73 | `fontFallback` | `FontFallback.none`（`fonts_android.dart:11`） | 微軟正黑／雅黑 | `macosFontFallback`：`PingFang TC`／`PingFang SC`（`fonts_macos.dart:8–11`） | `none` | 要決定：macOS 的理由是預設 San Francisco 沒有 CJK、引擎挑到日文字形（flutter/flutter#103811，`fonts_macos.dart:5–7`）。iOS 的 Material 預設字型同為 SF，同一個問題大概成立，但**沒有實測**；PingFang 在 iOS 也是系統字型。可以共用常數也可以另寫 `fonts_ios.dart`（見 §2） |
| 77 | `fontChoices` | `sans-serif`／`serif`／`monospace`（`fonts_android.dart:15`） | 6 個 | `PingFang TC`／`PingFang SC`／`Hiragino Sans`（`fonts_macos.dart:14`） | `[]` | ADR 0035 §決定 5 與 U 的 design.md:43 寫「macOS／iOS：系統預設、蘋方-繁、蘋方-簡、Hiragino Sans」，與 macOS 同一份 |
| 82 | `customTitleBar` | false | true | true | false | false（`window_manager` 不在 iOS 的外掛清單，見 §3.5） |
| 86 | `shortcutModifier` | control | control | `appleShortcutModifier`（meta） | control | 宣告 `appleShortcutModifier`（`shortcut_modifier.dart:6–8` 寫「macOS／iOS 平台任務接上時宣告這個」）；iOS 只有外接鍵盤時用得到，同 Android 的註解（`platform_capabilities.dart:84–85`） |
| 89 | `playback` | `androidPlaybackSupport`（just_audio；mp4/aac、webm/opus、mp3、flac、wav） | `windowsPlaybackSupport`（media_kit） | `macosPlaybackSupport`（just_audio；mp4/aac、mp3、flac、wav、hls/aac；沒有 webm/opus；`outputDeviceSelection: false`，`audio_macos.dart:8–18`） | null | just_audio（AVPlayer）。AVPlayer 在 iOS 一樣不播 WebM、不播 FLV，格式表預期同 macOS；ADR 0018:76 寫「iOS／macOS 的格式支援（B 站 DASH 音訊、直播 HLS）在有機器時實測」，iOS 還沒實測。`audio.dart:6` 的註解已寫「Android、macOS（之後 iOS）」 |
| 93 | `networkInterfaces` | true | true | true | false | true；`ConnectivityPlusInterfaces.system()`；`connectivity_plus` 7.3.1 在 iOS 外掛清單內（§3.5） |
| 98 | `cache` | 128 MiB／100 張／50 MiB（`cache_sizes_android.dart:7`） | 256／200／80 | 256／200／80（`cache_sizes_macos.dart:5`） | null | 手機取行動平台值（ADR 0016 §決定 3 寫「行動平台」128 MiB）：可直接用 `androidCacheSizes`（常數名帶 android）或新寫 `cache_sizes_ios.dart`；`CacheDirectory(applicationCachePath: _applicationCachePath)`（`platform.dart:452`）沿用 |
| 102 | `secureStorage` | true | true | true | false | true，但 factory 要新增：`FlutterSecureStorageAdapter.system`（`flutter_secure_storage_adapter.dart:35–44`）只帶 `aOptions`，iOS 會走套件預設的 `IOSOptions`（data protection keychain，不需 `keychain-access-groups`，見 §6 備註）；macOS 的 `.macos()`（52–62）與 `deleteWholeStore` 是為登入 keychain 的 `-50` 寫的，iOS 不適用。dev／prod 以 bundle id 與 `fmp-dev.`／`fmp.` 前綴分開（同檔 76–81）。檔頭註解、`secure_storage_test.dart` 的選項斷言要加 iOS |
| 105 | `files` | true | true | true | false | true；`FilePickerDialogs` 共用（`file_picker_darwin` 2.1.3 在 iOS 外掛清單）。`saveFile` 在 iOS 要傳 bytes（`file_picker_dialogs.dart:42–46` 本來就傳）。`pickDirectory` 在 iOS 回的是 security-scoped 路徑，**沒有驗證**（跟 `pluginDevTools` 有關） |
| 109 | `loginWebView` | true（`InAppLoginWebView.android()`，去掉 `; wv` 的 UA） | true（`.windows()`，WebView2 資料夾） | **false**（`flutter_inappwebview_macos_stub`；真套件在 CI 的 Xcode 26.6 建不過，`platform.dart:209–211`） | false | 有機會是 true：`flutter_inappwebview_ios` 1.2.0-beta.3 已在 iOS 外掛清單內，且 CI 的 iOS job 目前（2026-11-03，run 41656986777）兩次建置都成功。需要新 factory（例如 `.ios()`）決定 UA 與 cookie 行為；`InAppLoginWebView` 目前只有 `.android()`／`.windows()` 兩個（`flutter_inappwebview_login.dart:34–51`）。登入頁 UA 在 iOS 要不要改（R1：Google 擋嵌入式 WebView）**沒有資料** |
| 113 | `urlOpener` | true | true | true | false | true；`UrlLauncherOpener` 共用（`url_launcher_ios` 6.4.2 在清單） |
| 117 | `restartsItself` | false | true | true | false | **false**（iOS 沒有正規的重啟自己）。流程見 §1.3 |
| 121 | `shareFiles` | true | true | true | false | true；`SharePlusFileSharer` 共用（`share_plus` 13.3.1 在清單）。`share_plus_file_sharer.dart:19–25` 沒有傳 `sharePositionOrigin`；`TARGETED_DEVICE_FAMILY = "1,2"`（含 iPad）時 iPad 的分享要錨點，iPhone 不用（見 §7 owner 決定「是否支援 iPad」） |
| 125 | `pluginDevTools` | false（讀任意目錄要 SAF） | true | true | false | 偏 false：從資料夾載入插件要 `pickDirectory` 並讀目錄；iOS 是沙盒外的 security-scoped 目錄，與 Android 同類問題，**沒有驗證**，要決定（見 §7） |
| 129 | `mediaControls` | `MediaControlsSupport(supportsSeek: true)` | `supportsSeek: false`、`positionRefresh: 5s` | `supportsSeek: true`（`positionRefresh` 留空，Now Playing 自己推算，`platform.dart:219–221`） | null | `supportsSeek: true`；`audio_service` 的 darwin 端（iOS 與 macOS 共用同一份 darwin 原始碼）。要新的 `MediaControlsSupport`、新的 `mediaControlsFactory`，見 §1.4 |
| — | `withoutMediaControls()`／`withoutCustomTitleBar()` | | | | | 手寫的複製方法（132–149、152–169）；iOS 不加欄位就不必改，但加欄位時兩個都要補 |

### 1.2 `platform.dart` 現在對 iOS 回什麼

```dart
// platform.dart:188–189
TargetPlatform.linux || TargetPlatform.iOS || TargetPlatform.fuchsia =>
  AppPlatform._(capabilities: PlatformCapabilities.none),
```

- `AppPlatform.assemble` 的 doc（108–115）寫「只有 Android、Windows 與 macOS 有實作；其他平台驗證前宣告全部為『沒有』、也沒有實作檔」。
- `none` 時 `main()` 只開「此平台尚未支援」畫面（`lib/app/unsupported_platform_app.dart:9`）。
- `test/platform/platform_test.dart:219–222` 的 `for (final unverified in [linux, iOS, fuchsia])` 逐項斷言 `none`；iOS 接上時要從這個清單移出，另加 iOS 的案例。
- 組裝點的簽名帶 per-platform 的注入參數：`androidMediaControls`、`windowsMediaControls`、`macosMediaControls`、`windowsWindowChrome`、`macosWindowChrome`（116–125）；iOS 要加 `iosMediaControls`（測試用）。
- `AppPlatform._` 的綁定 assert（76–93）：`dataDirectory`↔`restarterFactory`／`legacyDataLocator`、`files`↔`fileDialogs`、`loginWebView`、`urlOpener`、`shareFiles`、`networkInterfaces`、`cache`↔`cacheDirectory`、`secureStorage`、`customTitleBar`↔`windowChrome`、`mediaControls`↔`mediaControlsFactory`。

### 1.3 重設資料／還原備份之後的流程（`restartsItself`）

- 欄位定義與註解：`platform_capabilities.dart:115–117`：「沒有時行程結束後要使用者手動再開，對話框要寫明（Android）」。
- 讀它的地方（全部在 UI，只決定對話框文字）：`lib/ui/backup/restore_flow.dart:42,123`、`lib/ui/backup/legacy_import_flow.dart:73,275`、`lib/ui/debug/debug_data_actions.dart:50,172`。文字：`restartsItself`＝「完成後 App 會自動重新啟動。」，`restartsManually`＝「完成後 App 會關閉，請自己再開啟。」（`lib/i18n/strings_zh_TW.g.dart:2198,2201`）。
- 重啟實作：`AppRestarter.restart()`（`app_restart.dart:8–10`）；組裝點用 `restarterFactory: (SystemMediaControls?) => AppRestarter`。
  - Android：`AndroidAppRestarter.forMediaControls`（`app_restart_android.dart:20–30`）：`controls.publish(NowPlaying.nothing)`、`dispose()`，`finally` 裡 `exit(0)`，不重開。
  - macOS：`MacosAppRestarter.system`（`app_restart_macos.dart:30–43`）：`mediaControls?.dispose()`、脫離的 `/bin/sh` 等 pid 結束後 `open` 同一個 `.app`、`exit(0)`。靠 `Process.start`，iOS 沒有。
- iOS 能走的現成路徑：`restartsItself: false`＋`AndroidAppRestarter.forMediaControls` 的邏輯（收掉媒體工作階段再 `exit(0)`）。該類別名稱帶 `Android`，邏輯與 Android 專屬無關（沒有 Android API）；是否改名／另開 `IosAppRestarter` 是設計決定。`AppPlatform.restarter` 的註解（`platform.dart:374–376`）說 Android 的實作要收掉系統媒體工作階段，所以依 `mediaControls` 組出來。
- 沒有資料：iOS 上 `exit(0)` 之後 `audio_service` 的 Now Playing 是否被系統收掉、重開 App 的行為，沒有測過；`app/AGENTS.md` 的 Android 段（§平台層「結束並重啟」）列的實測方法是 `dumpsys notification`，iOS 沒有對應。

### 1.4 逐能力目錄

- `app_data_directory/`：`app_data_directory.dart`（介面、`ensureOutsideLegacyData`）、`_android`（帶 flavor，dev 另加子目錄並擋舊位置）、`_windows`、`_macos`（只收 `applicationSupportPath`，不呼叫 `ensureOutsideLegacyData`：舊版沒發過 macOS）。**iOS 同樣沒有舊 App**（見 §6），不需擋舊位置。
- `app_info/`：`PackageInfoAppInfo(platform:, osVersion:, homeDirectory:)` 全平台共用（`package_info_app_info.dart`）。iOS 傳 `platform: 'iOS'`、`osVersion: Platform.operatingSystemVersion`；沙盒路徑不含使用者名稱，`homeDirectory` 不傳（同 Android，`platform.dart:145`）。
- `audio/`：`audio_android.dart`、`audio_macos.dart`、`audio_windows.dart` 各一個常數；`audio.dart:6` 的列舉註解已寫 iOS。**`lib/playback/backends/backend_rules.dart:108–113` 寫明中斷處理只對 Android 成立：「audio_session 在 iOS 的中斷開始一律報 unknown、之後照樣有結束，接 iOS 時要另外對應」**。`just_audio_backend.dart:24` 用 `useProxyForRequestHeaders: false`、`:28` 用 `handleInterruptions: false`、自己聽 `audio_session`（`:231–`）。因為不走本機 proxy，just_audio README 說 iOS 的 headers 用未公開的 `AVURLAssetHTTPHeaderFieldsKey`（README:115）；B 站串流要帶 header（`just_audio_backend.dart:290–292`），iOS 上有沒有效沒有資料（packages-macos.md 的 #747、#1245 提到 iOS 的 header 問題）。
- `cache_directory/`、`cache_sizes/`：見 §1.1。
- `connectivity/`：`connectivity_plus_interfaces.dart` 共用。
- `files/`、`share/`、`url_opener/`：實作都以套件命名、全平台共用。
- `fonts/`：`FontFallback` 值型別＋各平台常數。
- `legacy_data/`：`legacy_data_locations.dart` 有 `windowsLegacyDataLocator`（25–60）、`androidLegacyDataLocator`（68–101）、`macosLegacyDataLocator`（106–117）。`macosLegacyDataLocator(flavor:, devDirectory:)` 沒有任何 macOS 專屬邏輯：prod 回 `_none`，dev 只看 `--fmp-legacy-dir`，憑證用 `NoLegacyCredentialReader`；`legacy_credential_reader.dart:60` 的註解已寫「沒有舊資料可讀的平台（Linux、macOS、iOS…）」。`main()` 與 assert 要求有資料目錄就要有 `legacyDataLocator`。
- `login_webview/`：見 §1.1。
- `media_controls/`：`media_controls_audio_service.dart`（共用：`audioServiceMediaItemOf`、`audioServicePlaybackStateOf`、`reportAsyncErrors`、`AudioServiceCommandHandler`）、`_android`（通知頻道、`MediaKeyFix`）、`_macos`（`MacosSystemMediaControls`，26–30 的 `AudioService.init(builder:)` 不帶 config）、`_windows`。
- `secure_storage/`：見 §1.1。
- `shortcut_modifier/`：見 §1.1。
- `window_chrome/`：`window_manager_chrome.dart`，iOS 不用。

---

## 2. macOS 這次加的檔案：iOS 能不能共用

| 檔案 | 內容 | iOS 可否共用 | 說明 |
|---|---|---|---|
| `app_data_directory/app_data_directory_macos.dart` | `MacosAppDataDirectory`：`Directory(applicationSupportPath()).create(recursive: true)` | 邏輯共用、類別名帶 macOS | 註解寫「App 不開沙盒」「`~/Library/Application Support/<bundle id>`」，iOS 要改敘述。實作與測試（`test/platform/app_data_directory_test.dart`）不含 macOS 專屬行為 |
| `audio/audio_macos.dart` | `macosPlaybackSupport` 常數 | 預期相同的格式表，需實測 | 註解寫 AVPlayer 不播 WebM／FLV，iOS 一樣是 AVPlayer。是否共用常數或另寫 `audio_ios.dart` 要決定；`PlayableFormat('hls','aac')` 與 B 站插件 `resolveLive` 的 HLS 路線（ADR 0036 §決定 7）對 iOS 同樣適用，但沒實測 |
| `media_controls/media_controls_audio_service.dart` | 共用 handler、`MediaItem`、`PlaybackState` 轉換 | 直接共用 | 註解寫「Android 與 macOS 共用」；`audio_service` 的 darwin 端同時服務 iOS 與 macOS |
| `media_controls/media_controls_macos.dart` | `MacosSystemMediaControls`：`init` 呼叫 `AudioService.init(builder: AudioServiceCommandHandler.new)`；`dispose` 呼叫 `stopService` | 邏輯相同，需要 iOS 版本 | `init` 之外的 `publish`／`dispose` 與 macOS 一致；iOS 還要 `Info.plist` 的 `UIBackgroundModes: audio`（§3.3）與 audio session 啟用。`media_controls_macos_test.dart` 是範本。packages-macos.md:103 記：iOS ≥ 13 的 `playbackState` 沒回報（#1139），`center.playbackState` 只在 `TARGET_OS_OSX` 設，所以「macOS 不受影響、iOS 受影響」——iOS 上 Now Playing 的行為要實測 |
| `fonts/fonts_macos.dart` | `macosFontFallback`、`macosFontChoices` | 預期可共用，需實測 | 見 §1.1 |
| `cache_sizes/cache_sizes_macos.dart` | 桌面預設值 | 不共用 | iOS 是手機，取 `androidCacheSizes` 的行動值（ADR 0016 §決定 3） |
| `secure_storage/flutter_secure_storage_adapter.dart` 的 `.macos()` | `MacOsOptions(usesDataProtectionKeychain: false)`＋`deleteWholeStore` | 不共用，要新 factory | 這是為不開沙盒、ad-hoc 簽章寫的。iOS 一定是沙盒，用 data protection keychain（套件預設）。macos-acceptance.md:53 寫「login keychain 的做法要重新看（iOS 一定是沙盒，有 data protection keychain）」。`.system(flavor)` 也可以直接給 iOS，因為 `FlutterSecureStorage(aOptions:)` 不影響 iOS；要不要明確寫 `IOSOptions(accessibility:)`（預設 `unlocked`，背景播放時 App 被鎖屏可能讀不到憑證，`first_unlock` 才讀得到）是設計決定，**沒有實測** |
| `legacy_data/legacy_data_locations.dart` 的 `macosLegacyDataLocator` | 見 §1.4 | 共用 | 沒有 macOS 專屬邏輯 |
| `app_restart/app_restart_macos.dart` | `Process.start` 等 pid 再 `open` | 不能 | iOS 沒有；用 §1.3 的 Android 式 |
| `app_info`（`homeDirectory: Platform.environment['HOME']`） | | iOS 不傳 | 沙盒路徑不含使用者名稱 |
| `window_chrome`、`customTitleBar` | | 不適用 | |
| `packages/fmp_quickjs/` | QuickJS 與 flutter_js C 橋接，podspec 在 `macos/fmp_quickjs.podspec`（`s.dependency 'FlutterMacOS'`、`s.platform = :osx, '12.0'`）；`pubspec.yaml:flutter.plugin.platforms` 只有 `macos: ffiPlugin: true` | **要新增 `ios/` 的 podspec 與 `ios: ffiPlugin: true`**（ADR 0036 §決定 1：「iOS 平台任務沿用同一個套件」；套件的 pubspec description 也寫「Apple 平台」） | `flutter_js` 0.8.7 的 iOS podspec 是 `s.platform = :ios, '8.0'`、只附 JavaScriptCore runtime（`ios/.symlinks/plugins/flutter_js/ios/flutter_js.podspec:17–18`）。插件 worker 用 `QuickJsRuntime2`（`lib/plugins/runtime/plugin_worker.dart`），在 iOS 一樣靠 `DynamicLibrary.process()` 找符號。`Classes/*` 轉接檔相對路徑 `../../src/...`；iOS 的目錄放 `ios/Classes/` 時深度相同 |
| `packages/flutter_inappwebview_macos_stub` | macOS 的 stub | 不影響 iOS | iOS 用真的 `flutter_inappwebview_ios`；`webview_stub_test.dart` 只解析 Linux、macOS |
| `test/support/quickjs.dart` | 在 Mac 主機上以 clang 編 dylib 供 `flutter test` | 不需改 | 主機仍是 macOS |

---

## 3. `app/ios/` 原生專案現況

### 3.1 檔案

`app/ios/`：`Flutter/`（`AppFrameworkInfo.plist`、`Debug.xcconfig`、`Release.xcconfig` 已追蹤；`Generated.xcconfig`、`ephemeral/`、`Flutter.podspec` 被忽略）、`Runner/`（`AppDelegate.swift`、`SceneDelegate.swift`、`Info.plist`、`Assets.xcassets`、`Base.lproj`、`GeneratedPluginRegistrant.*`、`Runner-Bridging-Header.h`）、`RunnerTests/`、`Runner.xcodeproj`、`Runner.xcworkspace`。**沒有 `*.entitlements`，沒有 `Runner/Configs/`，沒有 `.gitignore` 裡的 `Signing.xcconfig`。**（macOS 有 `DebugProfile.entitlements`、`Release.entitlements`、`Configs/AppInfo.xcconfig`。）

### 3.2 身分（`Runner.xcodeproj/project.pbxproj`）

- 解析結果（以 python 逐 build configuration 讀）：

| configuration | App target `PRODUCT_BUNDLE_IDENTIFIER` | `APP_DISPLAY_NAME` |
|---|---|---|
| `Debug-dev`／`Profile-dev`／`Release-dev` | `com.personal.fmp.dev` | `FMP Dev` |
| `Debug-prod`／`Profile-prod`／`Release-prod`、`Debug`／`Profile`／`Release`（範本） | `com.personal.fmp` | `FMP` |
| `RunnerTests` 全部 | `com.personal.fmp.RunnerTests` | — |

- 三個 configuration list 都有六個 flavor configuration 加範本三個；`defaultConfigurationName = Release`（pbxproj:1319、1335、1351）。
- scheme：`xcshareddata/xcschemes/dev.xcscheme`、`prod.xcscheme`、`Runner.xcscheme`；`dev.xcscheme` 的 Test／Launch／Analyze 用 `Debug-dev`、Profile 用 `Profile-dev`、Archive 用 `Release-dev`。
- `IPHONEOS_DEPLOYMENT_TARGET = 15.0`、`TARGETED_DEVICE_FAMILY = "1,2"`（iPhone＋iPad）、`SWIFT_VERSION = 5.0`、`CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer"`。
- **沒有** `CODE_SIGN_STYLE`、`DEVELOPMENT_TEAM`、`CODE_SIGN_ENTITLEMENTS` 在 App target 上（只有 `RunnerTests` 設 `CODE_SIGN_STYLE = Automatic`）。macOS 是手動簽章加 `Signing.xcconfig`（AGENTS.md § App 身分）。
- `Flutter/AppFrameworkInfo.plist` 的 `MinimumOSVersion` 沒有另外查；專案層是 15.0，`FlutterGeneratedPluginSwiftPackage` 的 `Package.swift` 寫 `.iOS("15.0")`（`ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`，被忽略的檔）。

### 3.3 `Runner/Info.plist`（全文已讀）

- 有：`CFBundleDisplayName = $(APP_DISPLAY_NAME)`（10）、`CFBundleName = fmp`（**字面值**，18；macOS 的 `CFBundleName` 是 `$(APP_DISPLAY_NAME)`，`apple_identity_test.dart:44–47` 只對 macOS 檢查它）、`CFBundleIdentifier = $(PRODUCT_BUNDLE_IDENTIFIER)`、`UIApplicationSceneManifest`（`UIApplicationSupportsMultipleScenes = false`、`SceneDelegate`）、`UILaunchStoryboardName`、`CADisableMinimumFrameDurationOnPhone`、`UISupportedInterfaceOrientations`（直、橫左、橫右；iPad 含倒立）。
- **沒有**：`UIBackgroundModes`（背景播放需要 `audio`，ADR 0009:62）、`NSAppTransportSecurity`（macOS 有 `NSAllowsArbitraryLoadsForMedia`；just_audio README 的 iOS 段在連非 HTTPS 或用到 proxy 的功能時要 `NSAllowsArbitraryLoads`；App 用 `useProxyForRequestHeaders: false`、`http://` 串流是否會遇到要實測，ADR 0036 §決定 7 在 macOS 實測遇過 `-1022`）、任何 `NS*UsageDescription`、`ITSAppUsesNonExemptEncryption`、`LSApplicationQueriesSchemes`、`UIFileSharingEnabled`／`LSSupportsOpeningDocumentsInPlace`（M6 下載的「檔案」App 可見性，ADR 0020:92 寫由該平台任務定）。
- `AppDelegate.swift` 是 Flutter 範本的 `FlutterAppDelegate, FlutterImplicitEngineDelegate`，`SceneDelegate` 是空的 `FlutterSceneDelegate`；沒有自訂原生碼。

### 3.4 未提交的 CocoaPods 改動（`git status --short app/ios`、`git diff app/ios`；未動）

```
 M app/ios/Flutter/Debug.xcconfig
 M app/ios/Flutter/Release.xcconfig
 M app/ios/Runner.xcodeproj/project.pbxproj
 M app/ios/Runner.xcworkspace/contents.xcworkspacedata
?? app/ios/Podfile
?? app/ios/Podfile.lock
?? app/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/
?? app/ios/Runner.xcworkspace/xcshareddata/swiftpm/
```

- `Debug.xcconfig`／`Release.xcconfig`：各加一行 `#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.{debug,release}.xcconfig"`。
- `contents.xcworkspacedata`：加 `group:Pods/Pods.xcodeproj`。
- `project.pbxproj`：加 `Pods_Runner.framework`／`Pods_RunnerTests.framework`、`Pods-Runner.*`／`Pods-RunnerTests.*` 共 18 個 xcconfig 的 file reference（含 `-dev`／`-prod` 六組，CocoaPods 對每個 configuration 各產生一份）、`[CP] Check Pods Manifest.lock`、`[CP] Embed Pods Frameworks` 兩個 build phase、`RunnerTests` 的各 configuration 的 `baseConfigurationReference`；以及把 `XCLocalSwiftPackageReference "Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage"` 改名成 `"FlutterGeneratedPluginSwiftPackage"`（781AD8BC…，一處）。
- `Podfile`（43 行，flutter 工具產生）：`# platform :ios, '15.0'` 仍是註解；`project 'Runner', { 'Debug' => :debug, 'Profile' => :release, 'Release' => :release }` **只有三個模式**，沒有六個 flavor configuration；`flutter_ios_podfile_setup`、`use_frameworks!`、`flutter_install_all_ios_pods`、`target 'RunnerTests' { inherit! :search_paths }`、`post_install` 呼叫 `flutter_additional_ios_build_settings`。對照 macOS 的 Podfile（`app/macos/Podfile:1–22`）已加六個對應與說明註解。
- `Podfile.lock`：`Flutter 1.0.0`、`flutter_js 0.1.0`、`isar_community_flutter_libs 1.0.0`，COCOAPODS 1.17.0。**沒有 `fmp_quickjs`**（因為套件沒有 iOS podspec）。其他外掛不在 Podfile.lock，因為走 Swift Package Manager：`FlutterGeneratedPluginSwiftPackage` 含 `audio_service`、`audio_session`、`connectivity_plus`、`file_picker_darwin`、`flutter_inappwebview_ios`、`flutter_secure_storage_darwin`、`integration_test`、`just_audio`、`package_info_plus`、`share_plus`、`sqflite_darwin`、`url_launcher_ios`。
- `.symlinks/` 與 `Flutter/Flutter.podspec` 被 gitignore（`git status --ignored`）。`Pods/` 目錄存在於工作區（含 `xcuserdata/roxy.xcuserdatad`），不在 `git status` 的未追蹤清單內，所以是被 ignore 的（macOS 的 `macos/Pods` 同樣沒追蹤）。
- 兩個 `xcshareddata/swiftpm/` 目錄是 Xcode 解析 Swift package 後產生的（內容沒讀，Package.resolved 類）。
- 對應規定：`app/AGENTS.md` § App 身分 「`ios/` 的還沒提交，產生的 Podfile 只對應三個模式：iOS 平台任務照 macOS 的做法處理」；ADR 0036 §決定 10：「iOS 的 Podfile 由 iOS 平台任務照同樣做法處理」；macOS 任務 prd.md:87：「`app/ios/` 的 CocoaPods 檔：iOS 平台任務照 §決定 10 的做法處理，這個任務不動」。
- 事實：`Pods-Runner` 的 xcconfig 在 `Target Support Files/Pods-Runner/` 已有 `debug-dev`、`debug-prod`…的六組檔（CocoaPods 對 project 內每個 configuration 都產生），但 `Podfile` 沒有對應 → 這些 configuration 的 pod 一律當 release 編（AGENTS.md § App 身分 的說明、macOS Podfile 第 6–7 行註解）。

### 3.5 已註冊的 iOS 外掛（`GeneratedPluginRegistrant.m` 與 `Package.swift`）

`audio_service`、`audio_session`、`connectivity_plus`、`file_picker_darwin`、`flutter_inappwebview_ios`、`flutter_js`（pod）、`flutter_secure_storage_darwin`、`integration_test`、`isar_community_flutter_libs`（pod）、`just_audio`、`package_info_plus`、`share_plus`、`sqflite_darwin`、`url_launcher_ios`。沒有 `window_manager`、`smtc_windows`、`media_kit*`、`fmp_quickjs`。

### 3.6 App 側與 iOS 有關的依賴現況（`pubspec.yaml`）

- `flutter_inappwebview: 6.2.0-beta.3`（`pubspec.yaml` 約 80 行，註解 macOS 另用 stub）；iOS 用預設 `flutter_inappwebview_ios`。
- `fmp_quickjs` 註解：「macOS（之後 iOS）的 QuickJS」。
- `flutter.default-flavor: dev`；測試插件 asset 只給 dev flavor。
- `isar_community_flutter_libs: 3.3.2`：有 iOS pod（Podfile.lock 內）。舊資料匯入在 iOS 沒有來源（§6）。

---

## 4. 測試與閘門

### 4.1 `test/identity/apple_identity_test.dart`（534 行）對 iOS 查了什麼

迴圈 `for (final platform in ['ios', 'macos'])`（16），兩個平台都跑（24–67）：

1. prod 的 bundle id 是 `{com.personal.fmp}`、顯示名稱 `{FMP}`；
2. dev 是 `{com.personal.fmp.dev}`、`{FMP Dev}`；
3. Dart 的 `AppFlavor.displayName` 與 pbxproj 的 `APP_DISPLAY_NAME` 相同；
4. `Info.plist` 的 `CFBundleDisplayName` 指向 `$(APP_DISPLAY_NAME)`（macOS 另查 `CFBundleName`，iOS 不查）；
5. 每個 target 的 configuration list 都有六個 flavor configuration、且與 base 對得上（`flavorConfigurationProblems()`）；
6. `dev`／`prod` scheme 的 Test、Launch、Profile、Analyze、Archive 各用對的 configuration。

`'parser mutations'`（220–）以 **iOS 的 pbxproj** 當變異來源（221）：dev 後綴被拿掉、某 target 少一個 configuration、格式無關改動。

**只有 macOS 才有、iOS 沒有的檢查**（`if (platform == 'macos')`，69–122）：
- entitlements 沒有 `app-sandbox`、`keychain-access-groups`（iOS 沒有 entitlements 檔，也沒有相反方向的斷言）；
- `Info.plist` 有 `LSMultipleInstancesProhibited`、`NSAllowsArbitraryLoadsForMedia`；
- App target 手動簽章、`AppInfo.xcconfig` `#include?` `Signing.xcconfig`、`.gitignore` 排除它；
- **Podfile 把每個 flavor configuration 對到 debug／release**（109–121，`podfileConfigurations(...)`、`_podMode`）——**iOS 沒有這條**，而且目前 iOS 的 Podfile 也不滿足它（§3.4）；
- `'macOS file mutations'`（125–216）：對 macOS 的檔做變異，證明檢查會紅、無關格式不紅（包含 Podfile 的變異，188–196、`'layout, comments and quoting…'` 的 Podfile 部分）。
- iOS 要的新規則（例如 `UIBackgroundModes` 含 `audio`、entitlements 不含什麼、Podfile 對應）要在同輪補測試並做雙向變異（個人 CLAUDE.md 規則）；檔案本身沒有 iOS 版本的這些測試函式。

### 4.2 iOS 相關的其他測試

- `test/platform/platform_test.dart:219–222`：iOS 目前在「未驗證」清單，斷言全部 none（見 §1.2）。
- `test/ui/shell/ios_conventions_test.dart`（見 §5）。
- `test/platform/webview_stub_test.dart`：只解析 Linux、macOS（未讀 iOS）。
- 沒有 iOS 的整合測試；`integration_test/` 有 `install_search_play_test.dart`、`secure_storage_test.dart`、`toast_layering_test.dart`、`audio_backend_contract_test.dart`、`legacy_credentials_test.dart`、`plugin_runtime_benchmark_test.dart`。

### 4.3 驗證表（`app/AGENTS.md` § 驗證）

- 「Xcode 專案（`ios/`、`macos/`）、`packages/fmp_quickjs/`」一列：「`flutter build macos --flavor dev --debug` 與 `--flavor prod --release`…；**iOS 建置交給 CI 的 iOS job**」。
- 實機驗證規則：每個使用者看得到的 PR 都要在 Android 模擬器驗；改到平台各自實作的另驗 Windows 與 macOS；沒有 iOS（`app/AGENTS.md` § 實機驗證；`.claude/skills/verify-on-device/SKILL.md:34`：「Linux、iOS 在各自的平台任務加進 `references/`，現在不驗」）。`references/` 目前有 `android.md`、`macos.md`、`runtime-state.md`、`windows.md`，沒有 `ios.md`。ADR 0027 的表：iOS 模擬器「每個里程碑一次冒煙測試，iOS 平台任務（Mac 到貨後）」。

---

## 5. UI 在手機尺寸與 iOS 慣例

### 5.1 `lib/ui/` 與平台分支

- `lib/ui/` 與 `lib/app/` 裡沒有 `TargetPlatform.iOS`、`Platform.isIOS`、`Cupertino*`、`defaultTargetPlatform` 分支（lint `fmp_platform_checks` 擋 `lib/platform/` 以外的平台判斷）。grep 命中的 `iOS` 只出現在註解（`lib/ui/i18n/ui_locale.dart:63`、`lib/platform/*`）。
- Cupertino 頁面轉場：`lib/` 與 `pubspec.yaml` 沒有 `pageTransitionsTheme`、`Cupertino*`、`cupertino_ui` 的引用。`test/ui/shell/ios_conventions_test.dart:28–39` 斷言 `Theme.of(...).pageTransitionsTheme.builders[TargetPlatform.iOS]` 的型別名是 `CupertinoPageTransitionsBuilder`（註解：該型別在 `cupertino_ui` 套件，App 沒有直接依賴，所以比型別名）——也就是 iOS 的轉場來自 `material_ui` 預設主題，不是 App 自己設。
- 唯一有 iOS 專屬斷言的測試：`test/ui/shell/ios_conventions_test.dart`（U PR 15，ADR 0035 §決定 13）。內容：
  1. iOS 頁面用 Cupertino 轉場（28–39）；
  2. 內頁左緣右滑返回回到上一頁（41–59，`tester.dragFrom(Offset(2,400), Offset(300,0))`）；
  3. 直向：頁面頂欄不進劉海（`_topInset = 47`）、導覽列不進 home indicator（`_bottomInset = 34`）（61–81）；
  4. 橫向：側欄與頁面避開左右 59pt（83–）。
  檔頭註解：「實機（劉海、動態島、手勢）留給 iOS 平台任務」。
- 安全區域／返回的實作點（不是平台分支，是全平台一體適用）：`lib/ui/shell/app_shell.dart:156`（`MediaQuery.viewPaddingOf(context).bottom`）、`:404`（`MediaQuery.paddingOf`）、`:528`、`:582`、`:596` 的 `SafeArea`、`:608` 的外殼 `PopScope`；`player_page.dart:410,436` 的 `SafeArea`；`playlist_hero.dart:94`（`paddingOf.top`）；`error_detail_page.dart:117`、`account_playlists_page.dart:187`、`add_to_playlist.dart:229`、`legacy_side_rail.dart:82` 的 `SafeArea`。版面分 `WindowClass.compact/medium/…`（`app_shell.dart:55,527`）：compact＝底部 `NavigationBar`＋播放列在它上面。

### 5.2 U 任務說「原生部分在 macOS／iOS 平台任務」之後 iOS 留下的原生部分

出處：`.trellis/tasks/archive/2026-10/10-24-ui-legacy-parity/prd.md:43`（R2.4「iPhone 的安全區域與右滑返回」；「U 只做 Dart 側並以 widget 測試驗證；原生部分與實機驗證交給 macOS／iOS 平台任務」）、ADR 0035 §決定 13（`0035…md:95`）、`milestones.md:167`。iOS 留下的：

- **實機驗證**：劉海、動態島、home indicator、手勢（ios_conventions_test.dart 檔頭）。
- 原生沒有 Mac 標題列的對應，iOS 沒有「原生部分」要寫的視窗層；Dart 側的 `SafeArea`／Cupertino 轉場已有測試，沒有任何 iOS 原生檔針對 UI（`AppDelegate.swift`、`SceneDelegate.swift` 是範本）。
- U 的 `u-acceptance.md`／`mac-environment.md`（`archive/.../research/`）有 iOS 模擬器（iPhone 17，iOS 27.0）跑 `flutter run --flavor dev` 的記錄：顯示「此平台尚未支援」（`mac-environment.md:23`）。
- 其他 U 留下、與手機尺寸有關但**沒有查證**的：播放頁 `useSafeArea: true`（`player_page.dart:288`）、直橫向（`Info.plist` 允許橫向）。沒有 iOS 實機畫面的資料。

---

## 6. CI、發版、舊 App

### 6.1 `.github/workflows/ci.yml` 的 iOS job（`app-build-ios`，468–498）

- `runs-on: macos-latest`、`timeout-minutes: 45`、`working-directory: app`；步驟：checkout、`subosito/flutter-action`（`APP_FLUTTER_VERSION`）、`flutter pub get`、`flutter build ios --flavor prod --release --no-codesign`、`flutter build ios --flavor dev --debug --no-codesign`。
- **不簽名**（註解：「不簽名（ADR 0009 §決定 9）：iOS 經 GitHub 發 IPA、由使用者側載時重簽」，493）。**沒有模擬器測試**，沒有 `flutter test integration_test/... -d <simulator>`，沒有 `pod install` 專用步驟（flutter 工具自己產生 Podfile 並執行，所以 CI 是在 Podfile 三模式下建）。
- ADR 0009 §決定 9（`0009…md:55–57`）：「Linux、macOS、iOS 從第一個里程碑起在 CI 編譯（iOS 加模擬器測試）」；ADR 0009 後果（:84）：「建置矩陣含 Linux、macOS、iOS（不簽名）」。現在的 job 沒有模擬器測試。
- `ci.yml:293–298` 的註解仍寫「Linux、iOS 還沒有平台實作，App 只開『此平台尚未支援』，這裡只證明建得起來」（iOS 平台任務完成後會失真）。
- `ci-result` 的 `needs` 含 `app-build-ios`（593）。
- 最近的結果（`gh run view`）：run 41656986777（2026-11-03，sha `755e7b0a`）的 `App Build (iOS)` 成功，約 7 分鐘（14:46:38–14:53:35）；兩次建置都成功，表示 `flutter_inappwebview_ios` 與 pods 在 CI 的 Xcode 上建得過（macOS 的 `flutter_inappwebview_macos` 建不過，ADR 0036 §決定 9）。run 41662449773（docs 的 PR）iOS job 被路徑篩掉（skipped）。
- macOS job 作對照（413–466）：建置之後多跑 `nm` 查 `fmp_quickjs` 符號、`fmp_quickjs` 的 `flutter test`、`install_search_play_test.dart -d macos --flavor dev`。

### 6.2 `app-release.yml`

有 `build-android`、`build-windows`、`build-macos`（271–）、`verify`、`publish`，**沒有 iOS**。grep `ios|ipa|apple` 無命中。ADR 0022 §決定 3：「iOS 沒有發佈物，散佈方式由 iOS 平台任務決定」；更新器：「iOS、dev flavor 與其他安裝方式：`none`，只顯示『前往下載頁』」（`0022…md:59,70`）。`app/AGENTS.md` § 發版只列 Android、Windows、macOS；Linux 另加。

### 6.3 舊 App（根目錄，只讀）

- 根目錄**沒有 `ios/`**（`ls` 無此目錄；`git log --all -- ios` 空）。根目錄有 `android/`、`windows/`、`assets/`、`lib/`、`test/`、`tool/`。
- `app/AGENTS.md` § App 身分：「iOS、macOS 的舊版沒有發過，prod 沿用 Android 的 `com.personal.fmp`」。所以 iOS 沒有舊資料位置、沒有舊憑證，匯入入口用 `NoLegacyCredentialReader`／dev `--fmp-legacy-dir`。
- 舊程式碼有些 `Platform.isIOS` 分支（`lib/main.dart:156,167`、`lib/ui/pages/settings/bilibili_login_page.dart:90`、`lib/core/services/network_image_cache_service.dart:140`、`lib/data/database/database_migration.dart:108`），代表舊程式曾考慮 iOS 但從未建置發行；本次未讀這些分支的內容。
- 舊 `lib/AGENTS.md` 與根 `pubspec.yaml` 沒有 iOS 發行資訊（`grep -i ios` 在 `lib/AGENTS.md` 只命中無關的 `FmpAudioService` 字樣）。

---

## 7. 其他 ADR 對 iOS 的既定決定

| ADR | 出處 | 內容 |
|---|---|---|
| 0008 | `0008…md`（沒有 iOS 字樣） | 新版與舊版同 repo；prod 身分與舊版相同（`com.personal.fmp`，AGENTS.md § App 身分 引用 §決定 3） |
| 0009 | `0009…md:11,35,45,49,53,55–57,61–62,78,84` | 五平台為長期目標；平台實作在平台任務開始時才加（不預寫）；`audio_service` 給 Android／iOS／macOS；資料目錄「macOS／iOS 沙盒 Application Support」；iOS 加模擬器測試；iOS 不能自行安裝更新、App Store Guideline 5.2.3 與下載第三方媒體衝突**不上架**、經 GitHub 發 IPA 以 AltStore／SideStore 側載（免費 Apple ID 7 天重簽、最多 3 個 App）、背景播放需 `UIBackgroundModes: audio`；CI 建置 iOS（不簽名） |
| 0010 | `0010…md:24` | 舊資料層 Linux、macOS、iOS 從未驗證 |
| 0012 | `0012…md:58` | 沒有 WebView 的平台用 QR（B 站、網易）與貼上 cookie（YouTube）；ADR 內沒有 iOS 字樣；§決定 3 憑證只存 secure storage |
| 0014 | `0014…md:35,69` | `flutter_js` 引擎；**補充（ADR 0036 §決定 1）：macOS（之後 iOS）用 QuickJS，不用 JavaScriptCore** |
| 0016 | `0016…md`（§決定 3） | 磁碟快取預設：行動 128 MiB、桌面 256 MiB（`cache_sizes_*.dart` 引用） |
| 0017 | `0017…md:19` | 不用 `workmanager`：iOS 由系統決定背景執行時間 |
| 0018 | `0018…md:22,35,55,76` | `JustAudioBackend`（Android、iOS、macOS）；系統媒體控制 Android／iOS／macOS 用 `audio_service`；蘋果平台過去「不接 Now Playing」的理由是 media_kit 的 libs（因此 Apple 用 just_audio）；iOS／macOS 的格式支援（B 站 DASH 音訊、直播 HLS）有機器時實測 |
| 0020 | `0020…md:92` | iOS／macOS 的下載位置與「檔案」App 可見性由該平台任務定 |
| 0021 §決定 10 | `0021…md:104`（另 :35、:20、:166） | **iOS 鎖屏／動態島**：平台能力 `liveActivityLyrics`，以 ActivityKit 顯示目前一行（＋翻譯）、資料 ≤ 4KB、換行時本機更新；iOS 平台任務**實測後才宣告**。iOS 系統級懸浮歌詞不可行（只開放影片子母畫面）。`milestones.md:238–240` 的 iOS 驗收清單有「Live Activity 本機逐行更新（ADR 0021）」 |
| 0022 | `0022…md:59,70` | iOS 沒有發佈物，散佈方式由 iOS 平台任務決定；iOS 的 `appUpdate` 為 `none` |
| 0024 | `0024…md:39,123` | Flutter 不做 Apple '26 設計；快捷鍵補充 Apple 的 ⌘ |
| 0026 | `0026…md:93–96,124` | macOS、iOS：Mac 到貨後開；**iOS 要不要實機、要不要付費帳號，在該任務決定**；Linux、macOS、iOS 的功能會落後 Android 與 Windows |
| 0027 | `0027…md:20,50` | iOS 模擬器：每個里程碑一次冒煙測試，加進 skill 的 `references/ios.md`（「每個平台的操作說明…放在 `references/<平台>.md`」） |
| 0035 | `0035…md:42,43,95` | 全平台同一套 Material＋Apple 平台慣例；§決定 13：iPhone 安全區域、iOS 右滑返回（`CupertinoPageTransitionsBuilder`），原生與實機交 macOS／iOS 平台任務 |
| 0036 | `0036…md:59,61,109,125,138`、`macos-acceptance.md:53` | iOS 沿用 `fmp_quickjs`；iOS 的 Podfile 照 macOS 做；憑證做法 iOS 要重看；just_audio 在 Apple silicon 的 MP3 duration 問題（#1599，macOS）；ADR 0009 §決定 7 的「iOS 沙盒 Application Support」未被修訂 |

另外：`milestones.md:17`（M6 下載排在 iOS 之後）、`:23`（iOS 平台：Mac）、`:28`（2026-10-24 順序 U → macOS → iOS → M6）、`:238`（iOS 驗收：AVPlayer 對 B 站 DASH 與直播 HLS、Live Activity）。

---

## 8. iOS 任務要做的事（依能力與地方，全是事實清單，不是建議）

1. **組裝點**：`platform.dart` 新增 iOS 分支（現在落在 `none`，188–189）；`PlatformCapabilities` 填值；`AppPlatform.assemble` 加 `iosMediaControls` 注入參數；`platform_test.dart` 把 iOS 從 `unverified` 清單移出、加 iOS 的案例。
2. **資料目錄**：iOS 的實作（或與 macOS 共用）；`app_data_directory_test.dart`。
3. **播放**：`PlaybackSupport`（justAudio；格式表待實測）；iOS 的 audio session／中斷對應（`backend_rules.dart:108–113`）；B 站帶 header 的串流在 `useProxyForRequestHeaders: false` 下的行為；ATS 是否要 `NSAllowsArbitraryLoadsForMedia`；背景播放 `UIBackgroundModes: audio`。
4. **系統媒體控制**：iOS 的 `SystemMediaControls` 實作（共用 `media_controls_audio_service.dart`）、`MediaControlsSupport`、測試；Now Playing 與鎖定畫面、遠端指令的實機驗證；`playbackState` 在 iOS 的 #1139 問題。
5. **secure storage**：iOS 的 factory／選項、`secure_storage_test.dart` 增 iOS 斷言、`integration_test/secure_storage_test.dart` 在 iOS 模擬器跑；`accessibility`（鎖屏後背景播放時要不要讀得到憑證）要決定；dev／prod 的 service 名稱。
6. **插件引擎**：`packages/fmp_quickjs` 加 `ios/` podspec（`s.dependency 'Flutter'`、`s.platform = :ios, <版本>`）、`ios/Classes/*` 轉接檔、pubspec 的 `platforms: ios: ffiPlugin: true`；`symbols_test.dart` 只在 macOS 主機跑；release 建置後 `nm` 確認符號（CI macOS job 有這步，iOS 沒有）；插件 worker 在 iOS 實跑。
7. **登入 WebView**：決定 `loginWebView` true／false；true 要 `InAppLoginWebView.ios()` 與 UA 決定，false 要像 macOS 的 stub 或不 import（目前 iOS 已引入 `flutter_inappwebview_ios`，編得過）。
8. **其他共用能力**：`files`、`shareFiles`（iPad 錨點？）、`urlOpener`、`networkInterfaces`、`cache`（行動值）、`fontFallback`／`fontChoices`、`shortcutModifier`、`appInfo`、`legacyDataLocator`（`macosLegacyDataLocator` 邏輯相同）。
9. **重啟**：iOS 用 Android 式（`restartsItself: false`＋收媒體工作階段＋`exit(0)`）；`app_restart_test.dart`；實機看 Now Playing 是否清掉。
10. **原生專案**：
    - `Runner/Info.plist` 加 `UIBackgroundModes: [audio]`（必要）、ATS 的決定、`CFBundleName` 是否改 `$(APP_DISPLAY_NAME)`（macOS 已這樣）；
    - entitlements：目前沒有；是否需要（簽章方式決定後）；
    - 簽章：App target 現在沒有 `CODE_SIGN_STYLE`／`DEVELOPMENT_TEAM`；macOS 的本機簽章機制（`Signing.xcconfig`＋手動簽章）在 iOS 如何對應；
    - **Podfile**：照 macOS 加六個 flavor configuration 對應（`'Debug-dev' => :debug` …）；取消註解 `platform :ios, '15.0'`（或決定版本）；提交 `ios/Podfile`、`Podfile.lock`、xcconfig 的 `#include? Pods…`、pbxproj 與 workspace 的 CocoaPods 改動，並處理 `xcshareddata/swiftpm/` 兩個目錄（提交或忽略）；`flutter build ios` 之後 `git status` 不該再有 `app/ios/` 的變動；
    - 驗證表與 AGENTS.md 的對應文字（「`ios/` 的還沒提交…」要更新）；
    - 新原生部分有沒有閘門：`apple_identity_test.dart` 增 iOS 的 Podfile 對應（macOS 有 109–121）與 `Info.plist`／簽章規則，並附變異案例。
11. **CI**：ADR 0009 §決定 9 的模擬器測試（`install_search_play_test.dart -d <simulator>`）；`nm` 檢查 `fmp_quickjs`；更新 `ci.yml:293–298` 失真的註解；`apple_identity_test` 在 Linux 跑（讀 pbxproj）。
12. **發版**：`app-release.yml` 沒有 iOS；IPA 如何產、簽、發（ADR 0009 §決定 5「GitHub 發 IPA、側載」）；`expectedAssets`、`verify_release_assets_test.dart`、`release_workflow_test.dart` 要不要列 IPA。
13. **驗證 skill**：新增 `.claude/skills/verify-on-device/references/ios.md`（iOS 模擬器，`orca emulator`；實機是否也驗）；`SKILL.md:34` 的「iOS…現在不驗」要改；AGENTS.md § 實機驗證 要把 iOS 放進規則。
14. **UI 在手機上**：`ios_conventions_test.dart` 的實機驗證（劉海、動態島、home indicator、右滑返回）；Live Activity（ADR 0021 §決定 10）是否在這個任務做（milestones.md:238 列在 iOS 驗收）。
15. **文件與規格**：`.trellis/spec/app/platform/index.md:19,84`（「macOS／iOS 平台任務接上時填 `appleShortcutModifier`」「未驗證平台（Linux、macOS、iOS）」）、`app/AGENTS.md` § 平台層（Linux、iOS 驗證前…）、`shortcut_modifier.dart:6–8`、`audio.dart:6`、`legacy_credential_reader.dart:60`、`unsupported_platform_app.dart:9`、`platform.dart:108–115`、各平台共用的 doc 註解（`file_picker_dialogs.dart`、`share_plus_file_sharer.dart`、`flutter_secure_storage_adapter.dart:9`）會提到「Android、Windows 與 macOS」；ADR：iOS 的決定要新 ADR（`docs/adr/template.md`，下一個編號 0037）。

---

## 9. 需要擁有者決定的事

1. **簽章與散佈**：免費 Apple ID（7 天重簽、最多 3 個 App、側載）還是付費 Developer Program（ADR 0026 §決定 4：「iOS 要不要實機、要不要付費帳號，在該任務決定」；ADR 0022 §決定 3：iOS 散佈方式由這個任務決定）。影響：entitlements、provisioning、`keychain-access-groups` 與 data protection keychain、CI 的 IPA 產出（`--no-codesign` 後怎麼簽）、`app-release.yml` 要不要有 iOS。
2. **要不要實機驗證**（只用模擬器，還是 iPhone）。任務描述寫「verified on the owner's iPhone」；`orca emulator` 只管模擬器。
3. **iPad**：`TARGETED_DEVICE_FAMILY = "1,2"` 目前含 iPad；要不要支援（影響 `share_plus` 的 `sharePositionOrigin`、版面分類、Info.plist 的 iPad 方向）。
4. **登入 WebView**：iOS 要不要宣告 `loginWebView: true`（`flutter_inappwebview_ios` 在 CI 建得過，beta 版）、UA 怎麼處理。
5. **`pluginDevTools`**：iOS 要不要有（`pickDirectory` 的 security-scoped 目錄）。
6. **Live Activity**：是否在這個任務做（ADR 0021 §決定 10 要「實測後才宣告」；milestones.md 把它列在 iOS 驗收；需要 Widget Extension target，專案現在沒有）。
7. **`restartsItself`／重啟**：iOS 以 `exit(0)` 結束再由使用者開，是否可接受（側載不受 App Store 對 `exit` 的規範，但仍是設計決定）。
8. **iCloud 備份與資料目錄**：`Library/Application Support` 預設會進 iCloud／iTunes 備份（資料庫、log）；要不要排除（設計決定，沒有相關程式碼）。
9. **下載位置與「檔案」App 可見性**（ADR 0020:92）：M6 之前要不要先決定 `UIFileSharingEnabled`／`LSSupportsOpeningDocumentsInPlace`。
10. **最低 iOS 版本**：專案現在 15.0（`IPHONEOS_DEPLOYMENT_TARGET`、`Package.swift`），Podfile 註解掉；要不要改。
11. **ATS**：`NSAllowsArbitraryLoadsForMedia`（同 macOS）或 `NSAllowsArbitraryLoads`（just_audio README）或不加，待實測 `http://` 串流。
12. **iOS 共用與改名**：`MacosAppDataDirectory`、`macosLegacyDataLocator`、`media_controls_macos.dart`、`AndroidAppRestarter` 等是共用、改名，還是另寫 iOS 版（AGENTS.md「選完整滿足現有需求的最簡方案，不靠預先抽象」）。
13. **iOS 的 flavor 與 app 顯示名稱**：維持 `com.personal.fmp.dev` / `FMP Dev`（現狀已符合 apple_identity_test）。

---

## Caveats / Not Found

- 沒有實測：iOS 的字型 fallback（flutter#103811 是否同樣出現）、AVPlayer 的格式表（含 HLS、B 站 DASH 音訊）、iOS 的 `audio_service` Now Playing／遠端指令、`flutter_secure_storage` 的 iOS 行為（`IOSOptions` 預設、背景讀取）、`url_launcher`／`share_plus`／`file_picker` 在 iOS 的表現。這些只是依套件清單與其他平台的資料推論，標明為「沒有資料」。
- 沒有讀 `Pods/Pods.xcodeproj`、`xcshareddata/swiftpm/` 的內容；沒有跑任何 flutter／xcodebuild 指令。
- `lib/AGENTS.md` 的內容與舊 App 的 `Platform.isIOS` 分支只看了命中行，未深讀。
- 第 6.1 節的 CI 結果來自 `gh run view`（讀取），只看了兩次 main 上的 run。
- 「Library/Application Support 預設進 iCloud 備份」「`IOSOptions` 預設 accessibility」是外部知識／套件原始碼印象，沒有在這份研究內查證原始碼，列在 §9 作為決定題，不當結論。
- `app/ios/Flutter/AppFrameworkInfo.plist` 的 `MinimumOSVersion` 沒有讀。
