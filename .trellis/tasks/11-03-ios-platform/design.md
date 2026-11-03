# iOS 平台：設計

決定在 ADR 0037；這份寫怎麼落到程式碼。需求編號見 `prd.md`，事實來源見 `research/`。

## 1. 模組邊界

| 區塊 | 位置 | 改動 |
|---|---|---|
| 原生專案 | `app/ios/` | `Info.plist`、Podfile、`Podfile.lock`、xcconfig（Pods 與簽章的 `#include?`）、pbxproj、workspace、`Package.resolved`、`.gitignore`、圖示、`LaunchScreen.storyboard` |
| QuickJS 原生庫 | `app/packages/fmp_quickjs/` | `macos/` 改名 `darwin/`，podspec 改成兩個平台；`pubspec.yaml` 加 `ios` |
| 組裝點 | `lib/platform/platform.dart` | 新的 `_ios(...)` 分支；iOS 從「未驗證」移出；`assemble` 加 `iosMediaControls` |
| 共用實作改名 | `lib/platform/app_data_directory/`、`media_controls/`、`legacy_data/`、`app_restart/` | macOS 名字的改成 Apple，Android 的重啟改成 `ExitAppRestarter`（§4） |
| iOS 的常數 | `lib/platform/audio/audio_ios.dart`、`fonts/fonts_ios.dart`、`cache_sizes/cache_sizes_ios.dart` | 新檔 |
| 播放宣告與後端 | `lib/platform/audio/audio.dart`、`lib/playback/backends/backend_rules.dart`、`just_audio_backend.dart`、`audio_backends.dart` | `PlaybackSupport.interruptions` 與 Apple 的中斷對應（§7） |
| 憑證 | `lib/platform/secure_storage/flutter_secure_storage_adapter.dart` | `system(flavor)` 另帶 `iOptions`（§6） |
| 登入 WebView | `lib/platform/login_webview/flutter_inappwebview_login.dart` | `InAppLoginWebView.ios()`、`iosLoginUserAgent`（§10） |
| 分享 | `lib/platform/share/`、`lib/app/diagnostics/diagnostics_service.dart`、`lib/ui/debug/debug_export.dart` | `origin` 參數（§11） |
| CI／發版 | `.github/workflows/ci.yml`、`app-release.yml`、`app/tool/release/` | 模擬器測試、符號檢查、IPA |
| 驗證工具 | `.claude/skills/verify-on-device/references/ios.md`（新）、`SKILL.md` | 模擬器與實機 |
| 圖示工具 | `app/tool/make_ios_icon.py`（新） | 從 `assets/icon/app_icon.png` 產生 |

不動：路由器（`playback_event_router.dart`）、控制器、`NowPlayingPublisher`、UI 的版面程式（除了分享按鈕傳錨點；版面問題先回報）。

## 2. 原生專案（R1、R3.3、R7.1、R7.2，ADR 0037 §決定 1、4、5）

### 2.1 `ios/Runner/Info.plist`

加三項，改一項：

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoadsForMedia</key>
  <true/>
</dict>
<key>CFBundleName</key>
<string>$(APP_DISPLAY_NAME)</string>   <!-- 原本是字面值 fmp -->
```

其他照舊：方向四個都留；不加 `UIRequiresFullScreen`；不加任何 `*UsageDescription`。

### 2.2 簽章

- pbxproj：App target（`Runner`）的每個 configuration 設 `CODE_SIGN_STYLE = Automatic`。不寫 `DEVELOPMENT_TEAM`。`CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer"` 照舊。
- `ios/Flutter/Debug.xcconfig`、`Release.xcconfig` 各加一行，放在 Pods 那行之後：

  ```
  // 本機簽章（ADR 0037 §決定 1）：DEVELOPMENT_TEAM 寫在這個不進 repo 的檔。
  // 沒有它時模擬器與 --no-codesign 照常建；實機建置要它。
  #include? "Signing.xcconfig"
  ```

- `ios/.gitignore` 加 `Flutter/Signing.xcconfig`。
- 本機的檔：`ios/Flutter/Signing.xcconfig` 只有一行 `DEVELOPMENT_TEAM = <Team ID>`。值和本機 `macos/Runner/Configs/Signing.xcconfig` 的同一行相同。實作者在主 checkout 與自己的 worktree 建這個檔，不提交。
- 不在 Xcode 的 Signing & Capabilities 選 team：會把 `DEVELOPMENT_TEAM` 寫進 pbxproj。閘門見 §2.4。
- 第一次實機建置：Xcode 自動註冊 App ID 與裝置，產生 7 天的 profile。`flutter build ios` 會帶 `-allowProvisioningUpdates`；不帶的話改用 Xcode 開 `ios/Runner.xcworkspace` 建一次 `dev` scheme。
- `com.personal.fmp.dev` 註冊失敗（「not available」）時停下回報：換 bundle id 是身分變更，要另立 ADR。

### 2.3 CocoaPods 與 SwiftPM

- `ios/Podfile`：照 `macos/Podfile` 的寫法。
  - `platform :ios, '15.0'`（取消註解）；
  - `project 'Runner', { 'Debug' => :debug, 'Profile' => :release, 'Release' => :release, 'Debug-dev' => :debug, … 'Release-prod' => :release }`，加同一段說明註解；
  - 其餘照 Flutter 產生的內容（`use_frameworks!`、`target 'RunnerTests'`、`post_install`）。
- 提交：
  - `Podfile`、`Podfile.lock`；
  - `Flutter/Debug.xcconfig`、`Release.xcconfig` 的 `#include? "Pods/…"`；
  - pbxproj 與 `Runner.xcworkspace/contents.xcworkspacedata` 的 CocoaPods 變動；
  - `Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` 與 `Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`。`swiftpm/configuration/` 是空目錄，git 不追蹤。
- 主 checkout 的 `app/ios/` 有未提交的同類變動（擁有者的工作區），**不動它**。實作在 worktree 裡，從乾淨的 HEAD 重新產生：
  1. `flutter pub get`、`flutter build ios --simulator --flavor dev --debug`（產生 Podfile 並 `pod install`）；
  2. 改 Podfile、`pod install`（在 `ios/`）；
  3. 再建一次，確認 `git status --short app/ios` 只剩要提交的檔。
- 合併後主 checkout 拉 main 會和那些未提交的檔衝突。由主對話問擁有者要不要先備份（全域規則）再處理，實作者不碰。

### 2.4 `apple_identity_test.dart`

`for (final platform in ['ios', 'macos'])` 裡加 `if (platform == 'ios')` 的檢查，並加一組 `iOS file mutations`（範本是現有的 `macOS file mutations`）：

| 檢查 | 變異會紅 | 改格式不紅 |
|---|---|---|
| `UIBackgroundModes` 含 `audio` | 拿掉 `audio`、整個鍵拿掉 | 陣列多一個值、縮排、註解 |
| `NSAllowsArbitraryLoadsForMedia` 為真 | 改成 `<false/>` | 鍵的順序 |
| `CFBundleName` 是 `$(APP_DISPLAY_NAME)`（iOS 也查） | 改回 `fmp` | 縮排 |
| App target `CODE_SIGN_STYLE` 是 `{'Automatic'}` | 某個 configuration 改 `Manual` | — |
| pbxproj 沒有 `DEVELOPMENT_TEAM`（iOS 與 macOS 都查） | 某個 configuration 加一行 | 只在註解裡出現的字 |
| `Flutter/Debug.xcconfig`、`Release.xcconfig` 有 `#include? "Signing.xcconfig"` | 拿掉、改成沒有 `?` 的 `#include` | 前後多空白、加註解 |
| `ios/.gitignore` 排除 `Flutter/Signing.xcconfig` | 拿掉那一行 | 檔案其他行的順序 |
| Podfile 對應六個 configuration（用現有的 `podfileConfigurations`） | 少一個、`Debug-dev` 對到 release | 引號、縮排、註解 |

`#include` 沒有 `?` 時沒有本機檔就建不起來，所以要擋。

## 3. QuickJS（R2.1，ADR 0037 §決定 3）

- `git mv packages/fmp_quickjs/macos packages/fmp_quickjs/darwin`。轉接檔 `Classes/*` 的 `#include "../../src/…"` 深度不變。
- `darwin/fmp_quickjs.podspec`：
  - `s.ios.dependency 'Flutter'`、`s.osx.dependency 'FlutterMacOS'`；
  - `s.ios.deployment_target = '13.0'`、`s.osx.deployment_target = '12.0'`（取代原本的 `s.platform`）；
  - 其餘（`source_files`、`GCC_PREPROCESSOR_DEFINITIONS`、`OTHER_CFLAGS`、`s.library = 'c++'`）不變。
- `pubspec.yaml`：

  ```yaml
  flutter:
    plugin:
      platforms:
        ios:
          ffiPlugin: true
          sharedDarwinSource: true
        macos:
          ffiPlugin: true
          sharedDarwinSource: true
  ```

  description 與檔頭的說明改成「macOS 與 iOS」。
- Flutter 工具若不接受 FFI plugin 的 `sharedDarwinSource`（`flutter pub get` 或建置報錯）：`macos/` 不動，另加 `ios/fmp_quickjs.podspec` 與 `ios/Classes/`（`plugin-runtime-ios.md` §1 的做法）。在 ADR 0037 §決定 3 補一行結果，不必停下。
- 驗：
  - `flutter build ios --flavor prod --release --no-codesign` 之後，`nm -gU build/ios/iphoneos/Runner.app/Frameworks/fmp_quickjs.framework/fmp_quickjs` 有 `_jsNewRuntime`、`_jsSetMemoryLimit`；
  - macOS 的兩次建置與 CI 的 macOS 符號檢查照舊。路徑 `…/fmp.app/Contents/Frameworks/fmp_quickjs.framework/fmp_quickjs` 不變。
- `test/symbols_test.dart`、`test/support/quickjs.dart` 讀的是 `src/`，不改。

## 4. 共用實作改名（ADR 0037 §決定 13）

純改名，不改行為。檔案以 `git mv` 移動，測試跟著改名。

| 舊 | 新 | 用在 |
|---|---|---|
| `app_data_directory_macos.dart` 的 `MacosAppDataDirectory` | `app_data_directory_apple.dart` 的 `AppleAppDataDirectory` | macOS、iOS |
| `media_controls_macos.dart` 的 `MacosSystemMediaControls` | `media_controls_apple.dart` 的 `AppleSystemMediaControls` | macOS、iOS |
| `test/platform/media_controls_macos_test.dart` | `media_controls_apple_test.dart` | |
| `legacy_data_locations.dart` 的 `macosLegacyDataLocator` | 同檔的 `appleLegacyDataLocator` | macOS、iOS |
| `app_restart_android.dart` 的 `AndroidAppRestarter`（含 `forMediaControls`） | `app_restart_exit.dart` 的 `ExitAppRestarter` | Android、iOS |

- doc 註解改寫成兩個平台的說法。例如 `AppleAppDataDirectory`：「path_provider 的 application support。macOS 是 `~/Library/Application Support/<bundle id>`（不開沙盒，ADR 0036）；iOS 是 App 容器的 `Library/Application Support`（ADR 0037）。」
- `ExitAppRestarter` 的 doc 寫兩個平台的理由：Android 是 `SystemNavigator.pop` 讓行程活著（原文保留）；iOS 是沒有重新啟動自己的 API。
- `platform.dart` 的 `assemble` 參數 `macosMediaControls` 名稱不變：它注入的是 macOS 分支。
- 引用舊名的文件同一個 PR 改：`app/AGENTS.md`、`.trellis/spec/app/platform/index.md`、註解。用 `git grep -n 'MacosAppDataDirectory\|MacosSystemMediaControls\|macosLegacyDataLocator\|AndroidAppRestarter\|media_controls_macos'` 確認沒有殘留（封存的任務目錄與 ADR 的歷史敘述不改）。

## 5. 組裝點與宣告（R1、R2、R5、R6，ADR 0037 §決定 12）

`AppPlatform.assemble` 加參數 `Future<SystemMediaControls> Function(Log log)? iosMediaControls`（doc 照其他三個寫），分支 `TargetPlatform.iOS => _ios(flavor, iosMediaControls, legacyDirectory)`。`TargetPlatform.linux || TargetPlatform.fuchsia` 留在 `none`。

| 欄位 | iOS |
|---|---|
| `dataDirectory` | true：`AppleAppDataDirectory(applicationSupportPath: () async => (await getApplicationSupportDirectory()).path)` |
| `singleInstance` | false |
| `fontFallback`／`fontChoices` | `iosFontFallback`（`PingFang TC`／`PingFang SC`）、`iosFontChoices`（`['PingFang TC', 'PingFang SC', 'Hiragino Sans']`） |
| `playback` | `iosPlaybackSupport`（§7） |
| `networkInterfaces` | true：`ConnectivityPlusInterfaces.system()` |
| `cache` | `iosCacheSizes`：128／100／50，doc 引 ADR 0016 §決定 3；`CacheDirectory(applicationCachePath: _applicationCachePath)` |
| `secureStorage` | true：`FlutterSecureStorageAdapter.system(flavor)`（§6） |
| `files` | true：`FilePickerDialogs()` |
| `loginWebView` | PR 4 先 false；PR 7 改 true：`InAppLoginWebView.ios(osVersion: …)`（§10） |
| `urlOpener`、`shareFiles` | true：`UrlLauncherOpener()`、`SharePlusFileSharer()` |
| `restartsItself` | false：`restarterFactory: ExitAppRestarter.forMediaControls` |
| `pluginDevTools` | false（註解：同 Android，security-scoped 目錄） |
| `customTitleBar` | false：不給 `windowChromeFactory` |
| `shortcutModifier` | `appleShortcutModifier` |
| `mediaControls` | PR 4 先 null；PR 5 改 `MediaControlsSupport(supportsSeek: true)`，`mediaControlsFactory: iosMediaControls ?? AppleSystemMediaControls.init` |

- `appInfo`：`PackageInfoAppInfo(platform: 'iOS', osVersion: Platform.operatingSystemVersion, homeDirectory: Platform.environment['HOME'])`。
  - iOS 的 `HOME` 是 App 容器。模擬器上它含 Mac 的使用者名稱，交給遮蔽之後 log 與畫面都顯示成 `~`。
  - 實作時在模擬器確認 `HOME` 有值，而且等於資料目錄往上兩層。不對就停下回報。
- `legacyDataLocator`：`appleLegacyDataLocator(flavor: flavor, devDirectory: legacyDirectory)`。
- 字型：在模擬器以繁中介面看「骨」「直」「為」的字形（日文字形的「骨」上半部方向相反）。混到日文字形就是 fallback 沒有生效，停下回報。
- 更新 doc：
  - `platform.dart` 的 `assemble` 說明：「Android、Windows、macOS 與 iOS 有實作」；
  - `audio.dart`、`shortcut_modifier.dart`、`legacy_credential_reader.dart`、`unsupported_platform_app.dart`、`file_picker_dialogs.dart`、`share_plus_file_sharer.dart`、`flutter_secure_storage_adapter.dart` 提到平台清單的註解。
- 測試 `test/platform/platform_test.dart`：
  - iOS 從 `unverified` 清單移出（剩 linux、fuchsia）；
  - 加一組 `iOS`：逐欄核對上表的宣告與實作型別、`windowChrome` 為 null、`restartsItself` 為假、`appInfo.platform == 'iOS'`；
  - PR 5 加 `system media controls on iOS`（照 macOS 那組：注入的工廠、初始化失敗時宣告改為沒有）。

## 6. 憑證（R5.1，ADR 0037 §決定 6）

```dart
/// iOS 的選項。測試核對 accessibility 與帳號名。
static IOSOptions iosOptionsFor(AppFlavor flavor) => IOSOptions(
  // 背景換曲時裝置可能鎖著；unlocked（套件預設）鎖屏後讀不到（-25308）。
  accessibility: KeychainAccessibility.first_unlock,
  accountName: _namespaceOf(flavor),
);
```

- `FlutterSecureStorageAdapter.system(flavor)` 改成 `FlutterSecureStorage(aOptions: androidOptions(flavor), iOptions: iosOptionsFor(flavor))`。套件只在 iOS 讀 `iOptions`，Android、Windows 不受影響。
- 檔頭的平台清單加 iOS 一段：data protection keychain、`first_unlock` 的理由、解除安裝後項目仍在、換 Team 讀不到。
- 測試 `test/platform/secure_storage_test.dart`：`iosOptionsFor` 兩個 flavor 的 `accessibility`、`accountName`。`IOSOptions` 有 `toMap()`：比 map 裡的值，不比型別。
- 實機的寫讀刪：`flutter test integration_test/secure_storage_test.dart -d <模擬器> --flavor dev`，在 PR 4 跑一次，實機驗收再跑一次。
- 舊的 `unlocked` 項目不必搬：iOS 版沒發過，沒有舊項目。

## 7. 播放與中斷（R3，ADR 0037 §決定 7、8）

### 7.1 宣告

`lib/platform/audio/audio.dart`：

```dart
/// 後端收到的音訊中斷事件是哪一種語意（audio_session 在兩個平台給的事件形狀不同）。
enum AudioInterruptions {
  /// Android 的音訊焦點：unknown 類的開始是 AUDIOFOCUS_LOSS，不會有結束。
  androidAudioFocus,

  /// Apple 的 AVAudioSession：開始一律報 unknown，之後有結束；結束帶 shouldResume
  /// 時報暫停類，沒帶時報 unknown。
  appleAudioSession,

  /// 後端不聽中斷（media_kit）。
  none,
}
```

`PlaybackSupport` 加 `required this.interruptions`（`final AudioInterruptions interruptions;`）。四個平台的值：

| 常數 | `interruptions` |
|---|---|
| `androidPlaybackSupport` | `androidAudioFocus` |
| `macosPlaybackSupport` | `appleAudioSession`（註解：macOS 的 audio_session 不發中斷事件，宣告的是語意） |
| `iosPlaybackSupport`（新，`audio_ios.dart`） | `appleAudioSession` |
| `windowsPlaybackSupport` | `none` |

`iosPlaybackSupport` 的格式與 `outputDeviceSelection: false` 同 macOS。doc 寫 ADR 0037 §決定 7 的理由（WebM 不播、Ogg Opus 能播但插件不給），引 `packages-ios.md` §2.2。

### 7.2 對應

`backend_rules.dart`：

```dart
InterruptionResponse respondToInterruption({
  required bool begin,
  required InterruptionKind kind,
  required AudioInterruptions interruptions,
})
```

| `interruptions` | (begin, kind) | 回應 |
|---|---|---|
| `androidAudioFocus` | 全部 | 照舊（現有六列） |
| `appleAudioSession` | (true, unknown) | `interrupted` |
| | (false, pause) | `endedResumable` |
| | (false, unknown) | `ended` |
| | (true, pause) | `interrupted`（audio_session 不會發，對應要完整） |
| | (true, duck)／(false, duck) | `duck`／`unduck`（不會發，同上） |
| `none` | 任何 | 拋 `StateError`：不聽中斷的後端不該呼叫 |

- `backend_rules.dart` 的 `lib/platform/` import 規則：`audio.dart` 只是值型別。實作時確認 lint `fmp_layer_imports` 允許後端目錄 import `package:fmp/platform/audio/audio.dart`（`audio_backends.dart` 已經 import 它）。
- `InterruptionKind` 的 doc 改寫：「audio_session 的 `AudioInterruptionType`；語意依平台宣告的 `AudioInterruptions`」，拿掉「接 iOS 時要另外對應」那句。

### 7.3 接線

- `JustAudioBackend({required Log log, required AudioInterruptions interruptions})`；`_onInterruption` 把它傳給 `respondToInterruption`，log 的欄位加 `interruptions`。
- `createAudioBackend(support, log:)` 傳 `support.interruptions`。
- 加一個 assert：`justAudio` 不能配 `none`。
- 其他建 `JustAudioBackend` 的地方（`integration_test/audio_backend_contract_test.dart` 若直接建）跟著改。

### 7.4 資料流

```
AVAudioSessionInterruptionNotification
  → audio_session（Dart 的 AudioInterruptionEvent：begin、type）
  → JustAudioBackend._onInterruption → respondToInterruption(…, interruptions: appleAudioSession)
  → 後端事件 Interrupted(transient: true) ／ InterruptionEnded(resume: true|false)
  → PlaybackSession → routePlaybackEvent（不改）
  → PlaybackController：PauseForInterruption（記 pausedByInterruption）／ResumeAfterInterruption／PauseWithoutResuming
  → NowPlayingPublisher：MediaPhase.interrupted ／ ready
  → AppleSystemMediaControls → MPNowPlayingInfoCenter
```

拔耳機：audio_session 的 `becomingNoisyEventStream`（iOS 是 route change 的 `OldDeviceUnavailable`）→ `BecameNoisy` → 照舊暫停、不續播。

### 7.5 測試

- `test/playback/backends/backend_rules_test.dart`：
  - 現有的 `audio interruptions (Android)` 加上 `interruptions: AudioInterruptions.androidAudioFocus`；
  - 新增 `audio interruptions (Apple)`：上表四列，加 `duckedAfter` 照舊只有 duck 為真；
  - 另加一個案例：`none` 拋錯。
- `test/platform/platform_test.dart`：四個平台的 `playback.interruptions`。
- 控制器與路由器的測試不必改：它們吃的是後端事件。另在 `playback_controller_test.dart` 的 `audio interruptions` 群組加一個情境：開始 → 結束（resume: true）→ 續播。現有案例已涵蓋的話就不加。
- 真後端：`flutter test integration_test/audio_backend_contract_test.dart -d <iOS 模擬器> --flavor dev`（PR 6）。接 audio_session 的那幾行沒有自動閘門，實機驗。
- 模擬器能驗的部分：播放中在模擬器的 Safari 播一段影片（別的 App 搶走音訊）→ FMP 暫停，log 有 `Audio interruption` 與 `response: interrupted`。Safari 停下後有沒有結束事件，照實記錄。來電只能實機。

### 7.6 背景

- `UIBackgroundModes: audio`（§2.1）加上播放中的 `AVAudioSession(.playback)`，行程持續執行。插件 isolate 照常解析下一首（`plugin-runtime-ios.md` §3）。
- App 沒呼叫 `AudioSession.configure`：第一次 `play()` 時 audio_session 用 `music()` 的預設（category `playback`），不改（`packages-ios.md` §2.5）。
- 模擬器驗：
  1. 測試插件的三首 2 秒音檔排進佇列，按播放後回到主畫面；
  2. 等 10 秒，log 有三首的開始；
  3. 對照組：暫時拿掉 `UIBackgroundModes` 的本機建置，換曲停在第一首，不提交。

## 8. 系統媒體控制（R4，ADR 0037 §決定 9）

- `_ios` 宣告 `MediaControlsSupport(supportsSeek: true)`，工廠 `iosMediaControls ?? AppleSystemMediaControls.init`。
- `AppleSystemMediaControls.init` 不帶 `AudioServiceConfig`（同 macOS）。iOS 不需要通知頻道或前景服務。
- 封面：`audio_service` 在 iOS 以 `extras['artCacheFile']` 的本機檔建 `UIImage`，和 macOS 同一條路。macOS 已實測 `file://` 的 `artUri` 會被設成 `artCacheFile`。
- `dispose` 呼叫 `stopService`，`ExitAppRestarter` 在 `exit(0)` 前呼叫。
- 測試：
  - `media_controls_apple_test.dart` 不改（`forTest`）；
  - `platform_test.dart` 的 `system media controls on iOS`。
- 模擬器：控制中心有 Now Playing 就核對曲名、作者、封面、播放與暫停；沒有就記「只能實機驗」，不算失敗。
- 實機：
  - 鎖定畫面與控制中心的五個指令與拖進度；
  - 暫停狀態顯示是否正確（#1139：0.18.19 在 iOS 不設 `playbackState`）。
  - 顯示不對時記下現象回報，不在這個任務改 audio_service。

## 9. 重啟（R1.2，ADR 0037 §決定 10）

- `ExitAppRestarter.forMediaControls(controls)`：`publish(NowPlaying.nothing)`、`dispose()`，`finally` 裡 `exit(0)`。邏輯就是現在的 Android 版，不改。
- 對話框文字已由 `restartsItself: false` 選成「完成後 App 會關閉，請自己再開啟。」（`restore_flow.dart`、`legacy_import_flow.dart`、`debug_data_actions.dart`），不改 UI。
- 測試：`app_restart_test.dart` 的 `Android` 群組改名 `exit`（Android 與 iOS 共用），案例不變。
- 模擬器：
  1. Debug 頁「重設資料」→ App 消失；
  2. `xcrun simctl spawn booted launchctl list | grep fmp` 沒有行程；
  3. 再開時 log 有新的 `App started`，資料是空的。
- 實機：Now Playing 跟著消失。

## 10. 登入 WebView（R5.2，ADR 0037 §決定 11）

```dart
/// iOS 登入頁用的 UA：WKWebView 的預設 UA 沒有 `Version/…` 與 `Safari/…`，Google 把它
/// 當成嵌入式 WebView 擋下（同 Android 的 `; wv`，R1）。補成 Safari 的形狀；已經有
/// `Safari/` 的不動。[osVersion] 是系統版本（例如 `27.0`），iPad 的桌面版 UA 裡沒有。
String iosLoginUserAgent(String systemUserAgent, {required String osVersion})
```

- iPhone 的 UA（含 `Mobile/`）：
  - 在 `Mobile/` 前插入 `Version/<osVersion> `，結尾加 ` Safari/604.1`。
  - 例：`…(KHTML, like Gecko) Mobile/15E148` → `…(KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1`。
- iPad 的桌面版 UA（`Macintosh`，沒有 `Mobile/`）：結尾加 ` Version/<osVersion> Safari/605.1.15`。
- `InAppLoginWebView.ios({required String osVersion})`：
  - `userAgent: () async => iosLoginUserAgent(await InAppWebViewController.getDefaultUserAgent(), osVersion: osVersion)`；
  - `createEnvironment: null`。
- `osVersion` 由組裝點從 `Platform.operatingSystemVersion` 取主次版本（`'Version 27.0 (Build …)'` 的實際格式在模擬器上看）。解析寫成 `platform.dart` 裡的私有函式，或放進 `flutter_inappwebview_login.dart` 當公開的純函數一起測。
- 測試 `login_webview_test.dart`：
  - iPhone 的 UA、iPad 的桌面 UA、已有 `Safari/` 的 UA 不動；
  - `osVersion` 解析的兩三種輸入。
- `webview_stub_test.dart`：加一條 iOS 解析到真的 `flutter_inappwebview_ios`（讀 `.flutter-plugins-dependencies`），防止之後誤加 stub。
- 模擬器驗（真實連線，只開頁，不登入）：
  1. 開 YouTube 插件的網頁登入，Google 的頁面要停在輸入帳號，不出現「此瀏覽器或應用程式可能不安全」；
  2. 開 B 站的網頁登入，頁面正常；
  3. 回報列出開了哪些頁面。
  4. Google 擋下時停下回報擁有者（ADR 0037 §決定 11）。
- 上游 #2713、#2727（iOS 26 上 drawer、modal 之後觸控失效）：登入頁怎麼開，實作時看呼叫端。在模擬器上從帳號頁開、關、再開一次，確認之後的畫面還能點。
- 重設資料要清 WebView 的 cookie：macOS 任務已查過 `clearAll` 的呼叫點，照現況。

## 11. 分享錨點（R6.3，ADR 0037 §決定 14）

介面（`lib/platform/share/share.dart`）：

```dart
/// [origin] 是觸發分享的元件在螢幕上的位置（全域座標）；iPad 的分享表從它彈出，其他
/// 平台不用。沒給時 iPad 的分享表在螢幕中央。
Future<bool> shareFiles(
  List<String> paths, {
  required String mimeType,
  Rect? origin,
});
```

- `SharePlusFileSharer` 把 `origin` 交給 `ShareParams(sharePositionOrigin: origin)`。
- `DiagnosticsService.share(bundle, {Rect? origin})` 往下傳。
- `debug_export.dart` 在按鈕的 `onPressed` 取位置，在任何 `await` 之前：

  ```dart
  final box = context.findRenderObject()! as RenderBox;
  final origin = box.localToGlobal(Offset.zero) & box.size;
  ```

  `context` 要是按鈕自己的（必要時包一個 `Builder`）。這是 share_plus README 的 iPad 寫法。
- 介面在 `lib/platform/`，`Rect` 來自 `dart:ui`，不依賴 Flutter widget。
- 測試：
  - `share_plus_file_sharer_test.dart`：`origin` 傳到 `ShareParams.sharePositionOrigin`，沒給時是 null；
  - `test/app/diagnostics_test.dart`：往下傳；
  - `debug_export_test.dart`：分享時傳出的 `origin` 不是 null。
- 模擬器（iPad）：分享表從「分享」按鈕彈出。

## 12. 手機與 iPad 的 UI（R6，ADR 0037 §決定 4、14）

不改版面程式，只驗。驗出問題時：

- 是 bug（溢出、被遮住、點不到）：照一般的修正，同 PR 補 widget 測試；
- 要改版面或互動的（例如 iPad 要不同的導覽、播放頁要重排）：停下回報擁有者，附截圖與建議，不自己定。

模擬器清單（iPhone 選有動態島的機型，iPad 選一台 13 吋）：

| 項目 | 怎麼看 |
|---|---|
| 動態島、home indicator | 首頁、播放頁、內頁的頂欄與底部導覽列、播放列都在安全區域內（`ios_conventions_test.dart` 的實機對照） |
| 右滑返回 | 從左緣右滑退出內頁 |
| 鍵盤 | 搜尋框、設定的文字欄位在鍵盤之上；收鍵盤 |
| iPhone 橫向 | 側欄與內容避開兩側的安全區域 |
| iPad | 直向、橫向；分割畫面 1/3、1/2、2/3（`WindowClass` 跟著換）；台前調度改視窗大小 |
| 深淺色 | 狀態列文字的顏色跟著主題 |
| 外接鍵盤（iPad） | 模擬器的 I/O → Keyboard → Connect Hardware Keyboard；試一個 ⌘ 快捷鍵（例如開佇列 ⌥⌘U） |

圖示與啟動畫面：

- `tool/make_ios_icon.py`：把 `assets/icon/app_icon.png` 放在白底、不透明的 1024 方圖上（iOS 自己裁圓角），輸出到 `ios/Runner/Assets.xcassets/AppIcon.appiconset/`。`Contents.json` 改成單一 1024 的 universal 格式（Xcode 14 起支援），刪掉舊的多尺寸檔。
  - 圖示在白底上的大小照 macOS 的比例（824/1024）。看起來太小或太大時，附截圖回報擁有者再定。
- `ios/Runner/Base.lproj/LaunchScreen.storyboard`：根 view 的背景色改成 `systemBackgroundColor`；`LaunchImage` 的那張圖照舊。深色模式下啟動時不閃白。

## 13. CI（R7.3，ADR 0037 §決定 15）

`app-build-ios`：`timeout-minutes: 60`，步驟：

1. checkout、Flutter、`flutter pub get`（照舊）。
2. `flutter build ios --flavor prod --release --no-codesign`（照舊）。
3. 新增 `QuickJS is linked into the app`：

   ```bash
   lib=build/ios/iphoneos/Runner.app/Frameworks/fmp_quickjs.framework/fmp_quickjs
   nm -gU "$lib" | grep -q ' _jsNewRuntime$'
   nm -gU "$lib" | grep -q ' _jsSetMemoryLimit$'
   ```

4. 新增 `Boot a simulator`：以 `xcrun simctl list devices available --json` 取第一台 iPhone 的 UDID，`xcrun simctl boot`，寫進 `$GITHUB_ENV`（`SIMULATOR_UDID`）。用 `jq` 或 Python 解析，不寫死機型。
5. 新增 `Install a plugin, search and play`：`flutter test integration_test/install_search_play_test.dart -d "$SIMULATOR_UDID" --flavor dev`。
6. 刪掉 `Build iOS (dev, debug)`。

註解要更新：

- 第 293–298 行的總註解：iOS 已有平台實作，CI 在模擬器跑整合測試；Linux 仍只證明建得起來。
- job 內「不簽名」那行：改指 ADR 0037 §決定 1、2。

`app/AGENTS.md` § 驗證的 CI 段同步改。

## 14. 發版（R7.4，ADR 0037 §決定 2）

- `app-release.yml` 加 `build-ios`（`macos-latest`），照 `build-macos` 的形狀：
  1. `flutter build ios --flavor prod --release --no-codesign --build-name <版本> --build-number <versionCode>`；
  2. `mkdir -p out/Payload && cp -R build/ios/iphoneos/Runner.app out/Payload/`；
  3. Info.plist 轉成 XML（見下）；
  4. `(cd out && zip -qry ../fmp-v<版本>-ios.ipa Payload)`；
  5. 上傳 artifact。
- `verify` 與 `publish` 的 `needs` 加 `build-ios`。
- Info.plist：iOS 建出的多半是二進位 plist，verify 跑在 Linux 而且只讀 XML（`plistString`）。
  - 打包前在 `Payload/Runner.app/Info.plist` 上跑 `plutil -convert xml1`。App 沒有簽章，改它不破壞任何簽章；iOS 兩種格式都讀。
  - 實作時先看建出來的格式。已經是 XML 就不轉，註解寫明。
- `tool/release/verify_release_assets.dart`：
  - `expectedAssets` 加 `fmp-$tag-ios.ipa`，沒有別名；
  - `_iosIpaProblems`：zip 的唯一根是 `Payload/`，裡面唯一的 `.app` 是 `Runner.app`；`Payload/Runner.app/Info.plist` 的 `CFBundleIdentifier` 是 `com.personal.fmp`、`CFBundleShortVersionString` 是這一版；
  - 檔頭的清單加 iOS。
- 測試：
  - `verify_release_assets_test.dart`：好的 IPA、根不是 `Payload`、bundle id 是 dev、版本不對、缺檔；
  - `release_workflow_test.dart`：`build-ios` 在 `verify` 的 `needs` 裡、用 `--no-codesign`、產出的檔名。
- `app/AGENTS.md` § 發版加一段 iOS（未簽章、使用者重簽、Info.plist 轉 XML 的理由）。

## 15. 驗證工具（R8.1）

新增 `.claude/skills/verify-on-device/references/ios.md`，結構照 `macos.md`：

1. **模擬器**：
   - 選機型：`xcrun simctl list devices available`，iPhone 選有動態島的，iPad 選 13 吋；開機：`xcrun simctl boot <名稱或 UDID>`、`open -a Simulator`。
   - 建置與安裝：`flutter build ios --simulator --flavor dev --debug`、`xcrun simctl install booted build/ios/iphonesimulator/Runner.app`。
   - 帶開發入口啟動：
     1. 測試插件的安裝檔先複製進 App 容器：`xcrun simctl get_app_container booted com.personal.fmp.dev data` 底下的 `tmp/`；
     2. `SIMCTL_CHILD_FMP_DEV_PLUGIN=<容器內路徑> xcrun simctl launch booted com.personal.fmp.dev`。`SIMCTL_CHILD_` 前綴的環境變數會交給 App，`devPluginPath` 讀環境變數。
     3. 實作時確認可行；命令列參數在 iOS 不一定進得了 Dart 的 `main`。
   - `flutter run -d <UDID> --flavor dev` 要熱重載時用，放進 Orca terminal。
   - log：資料目錄是容器的 `Library/Application Support`，log 在其下的 `logs/fmp.jsonl`；系統 log：`xcrun simctl spawn booted log stream --predicate 'process == "Runner"'`。
   - 操作與讀畫面：`orca emulator` skill（點按、手勢、輸入、旋轉、無障礙樹、截圖），讀回畫面才算數。
   - 背景：`xcrun simctl launch booted com.apple.Preferences` 切走，或 `orca emulator` 的 home 鍵。
   - 深淺色：`xcrun simctl ui booted appearance dark|light`。
   - 收尾：`xcrun simctl terminate`、`shutdown`。
2. **實機**（擁有者的 iPhone）：
   - 前置：本機 `ios/Flutter/Signing.xcconfig`（§2.2）。iPhone 已配對、開發者模式已開（設定 → 隱私權與安全性 → 開發者模式，會重新開機，擁有者操作）。
   - 建置：`flutter build ios --flavor dev --release`。debug 建置不能從主畫面開，只在要接 `flutter run` 時用。
   - 安裝：`xcrun devicectl device install app --device <裝置> build/ios/iphoneos/Runner.app`；第一次要在 iPhone 的「設定 → 一般 → VPN 與裝置管理」信任開發者（擁有者操作）。
   - 啟動：`xcrun devicectl device process launch --device <裝置> com.personal.fmp.dev`。
   - 讀 log：`xcrun devicectl device copy from --device <裝置> --domain-type appDataContainer --domain-identifier com.personal.fmp.dev --source 'Library/Application Support/logs/fmp.jsonl' --destination <暫存目錄>`。
   - 參數以 `xcrun devicectl help <子指令>` 為準，不靠記憶。
   - 7 天到期：重跑建置與安裝；同一個 team 覆蓋安裝，資料與 keychain 都留著。
   - 只能實機驗的清單（ADR 0037 §決定 16）與擁有者要在場的步驟；開始前先問擁有者時間。
3. **回報**：不寫 UDID、裝置名稱、Team ID；log 路徑改寫成 `<資料目錄>`。

`SKILL.md`：

- 平台表加一列 iOS；
- 「Linux、iOS 在各自的平台任務加進 `references/`，現在不驗」改成只剩 Linux；
- 「平台」段加 iOS 何時驗：改到 iOS 的平台實作、`ios/`、手機版面時驗模擬器，里程碑冒煙測試一次；
- description 加 iOS 模擬器。

`references/runtime-state.md` 的資料目錄表加 iOS。

## 16. 會壞或要改的測試

| 測試 | 為什麼 |
|---|---|
| `test/platform/platform_test.dart` | iOS 不再是 `none`；`playback.interruptions`；改名的型別 |
| `test/platform/media_controls_macos_test.dart` | 改名 `media_controls_apple_test.dart` |
| `test/platform/app_restart_test.dart` | `AndroidAppRestarter` 改名 |
| `test/platform/app_data_directory_test.dart`、`legacy_data_locator_test.dart` | 改名 |
| `test/platform/secure_storage_test.dart` | iOS 的選項 |
| `test/playback/backends/backend_rules_test.dart` | `respondToInterruption` 多一個參數 |
| `test/platform/share_plus_file_sharer_test.dart`、`test/app/diagnostics_test.dart`、`test/ui/debug/debug_export_test.dart` | `origin` |
| `test/platform/login_webview_test.dart`、`webview_stub_test.dart` | iOS 的 UA 與解析 |
| `test/identity/apple_identity_test.dart` | iOS 的新檢查 |
| `test/release/*` | IPA |
| 用到 `PlaybackSupport(…)` 建構子的測試 | 多一個必填欄位；`git grep -n 'PlaybackSupport('` 找 |

## 17. 文件

- `app/AGENTS.md`：
  - § 驗證：Xcode 那一列加 `flutter build ios --simulator --flavor dev --debug` 與 `flutter build ios --flavor prod --release --no-codesign`（建完 `git status` 沒有 `app/ios/` 的變動），拿掉「iOS 建置交給 CI 的 iOS job」；CI 段寫 iOS 的模擬器測試；播放後端那列加 iOS 模擬器的契約測試。
  - § 實機驗證：iOS 何時驗（同 §15 的 `SKILL.md`）。
  - § App 身分：iOS 的 Podfile 已提交；iOS 本機簽章（自動簽章、`ios/Flutter/Signing.xcconfig`、新 worktree 要複製、不在 Xcode 選 team）；`Info.plist` 的三個鍵與閘門。
  - § 發版：iOS 的 IPA。
  - § 平台層：iOS 的各項（憑證的 `first_unlock`、重啟、登入 UA、媒體控制、分享的 `origin`、中斷的宣告）；「Linux、iOS 驗證前宣告全部為沒有」改成只剩 Linux。
  - § 資料目錄：iOS。
  - § 播放：中斷段加 Apple 的對應與已知限制。
- `.trellis/spec/app/platform/index.md`：改名後的例子、`fmp_quickjs` 的 `darwin/`、「未驗證平台」只剩 Linux。
- `.trellis/spec/app/playback/index.md` § 音量、速度、中斷、輸出裝置：中斷的宣告與 Apple 的對應。
- `verify-on-device`：§15。
- `milestones.md`：iOS 列的結果與 Live Activity 的去向（PR 10）。

## 18. 取捨與回退

| 取捨 | 選擇 | 代價 | 回退 |
|---|---|---|---|
| 簽章 | 免費、自動簽章 | 7 天重裝；每台 3 個 App | M9 改付費：只換 `Signing.xcconfig` 的 team，程式不動 |
| 中斷語意 | 平台宣告 | `PlaybackSupport` 多一個欄位 | 回退 PR 6：iOS 回到「來電後不續播」，其他平台不變 |
| keychain | `first_unlock` | 比 `unlocked` 寬：開機解鎖一次後，鎖著也讀得到 | 改回去只動 `iosOptionsFor`，套件會跨 accessibility 找舊項目（`packages-ios.md` §4.4） |
| 重啟 | `exit(0)` | 看起來像閃退 | 之後要行程內重建時另立 ADR |
| 登入 UA | 補成 Safari 的形狀 | Google 改偵測方式時要跟著改 | 宣告 `loginWebView: false`（帳號頁只剩 QR 與貼上 cookie） |
| IPA | 發未簽章 | 沒有在 SideStore 實裝過 | 從 workflow 與 `expectedAssets` 拿掉 |
| 共用命名 | Apple 共用 | 一次改名的 PR | 純改名，`git revert` 即可 |
| `sharedDarwinSource` | 一份 podspec | 改到 macOS 的建置 | 退回 `ios/` 另一份（§3） |
