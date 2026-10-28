# Research: macOS 平台任務的程式碼盤點

- **Query**: 盤點 `app/lib/platform/` 各能力、Apple 預備、`app/macos/` 原生專案、測試與 CI、Windows 專屬行為、AGENTS.md 平台層規則、舊 App 的 macOS 痕跡
- **Scope**: internal（只讀程式碼，未改任何檔）
- **Date**: 2026-10-28

行號以 2026-10-28 的工作區為準（HEAD `99c36168`，`app/macos/` 有未提交的 CocoaPods 改動，見 §3）。

---

## 1. `app/lib/platform/` 能力盤點

### 1.1 `PlatformCapabilities` 全部欄位（`platform_capabilities.dart`）

| 行 | 欄位 | 型別／預設 | 意義 | Android | Windows | `none` |
|---|---|---|---|---|---|---|
| 65 | `dataDirectory` | `bool`（必填） | 有 App 資料目錄實作；假時 `main()` 只開「此平台尚未支援」 | true | true | false |
| 70 | `singleInstance` | `bool`（必填） | 原生端保證單一實例（Windows 由 `main.cpp` mutex），Dart 只宣告 | false | true | false |
| 73 | `fontFallback` | `FontFallback`（必填） | 各語言 CJK fallback 字型 | `FontFallback.none` | 微軟正黑／雅黑 | `none` |
| 77 | `fontChoices` | `List<String>`，預設 `[]` | 外觀設定可選字型 | 3 個通用名 | 6 個 | 空 |
| 82 | `customTitleBar` | `bool`，預設 false | 系統標題列隱藏、App 自繪 | false | true | false |
| 86 | `shortcutModifier` | `ShortcutModifier`，預設 `control` | 快捷鍵主修飾鍵 | control | control | control |
| 89 | `playback` | `PlaybackSupport?`（必填） | 後端與可播格式 | justAudio | mediaKit | null |
| 93 | `networkInterfaces` | `bool`（必填） | 有網路介面實作 | true | true | false |
| 98 | `cache` | `CacheSizes?`（必填） | 快取大小 | 128 MiB／100 張／50 MiB | 256 MiB／200 張／80 MiB | null |
| 102 | `secureStorage` | `bool`（必填） | 有憑證存放 | true | true | false |
| 105 | `files` | `bool`（必填） | 有檔案對話框 | true | true | false |
| 109 | `loginWebView` | `bool`（必填） | 有 App 內登入 WebView | true | true | false |
| 113 | `urlOpener` | `bool`（必填） | 有開網址實作 | true | true | false |
| 117 | `restartsItself` | `bool`（必填） | 重設／還原後 App 自己再起來 | false | true | false |
| 121 | `shareFiles` | `bool`（必填） | 有系統分享視窗 | true | true | false |
| 125 | `pluginDevTools` | `bool`（必填） | 插件開發工具（選資料夾讀目錄） | false | true | false |
| 129 | `mediaControls` | `MediaControlsSupport?`，預設 null | 系統媒體控制 | `supportsSeek: true` | `supportsSeek: false`、`positionRefresh: 5s` | null |

另有兩個複製方法：`withoutMediaControls()`（132–149）與 `withoutCustomTitleBar()`（152–169）。**新增欄位時這兩個手寫的複製方法也要加**（沒有 copyWith；漏掉會在初始化失敗路徑掉欄位）。

`none`（46–61）：全部 false／null／空，`shortcutModifier` 與 `fontChoices`、`customTitleBar` 取預設。

### 1.2 `AppPlatform._` 把欄位與實作綁在一起的 assert（`platform.dart:69–86`）

```dart
assert(capabilities.dataDirectory == (dataDirectory != null)),
assert(capabilities.dataDirectory == (restarterFactory != null)),
assert(capabilities.dataDirectory == (legacyDataLocator != null)),
assert(capabilities.files == (fileDialogs != null)),
assert(capabilities.loginWebView == (loginWebView != null)),
assert(capabilities.urlOpener == (urlOpener != null)),
assert(capabilities.shareFiles == (fileSharer != null)),
assert(capabilities.networkInterfaces == (networkInterfaces != null)),
assert((capabilities.cache != null) == (cacheDirectory != null)),
assert(capabilities.secureStorage == (secureStorage != null)),
assert(
  capabilities.customTitleBar ==
      (windowChrome != null || windowChromeFactory != null),
),
assert(
  (capabilities.mediaControls != null) ==
      (mediaControls != null || mediaControlsFactory != null),
),
```

沒有 assert 的：`singleInstance`、`fontFallback`／`fontChoices`、`shortcutModifier`、`playback`、`pluginDevTools`、`restartsItself`（`restartsItself` 無 assert，但 `restarterFactory` 與 `dataDirectory` 綁定，即「有資料目錄就必須有 restarter」）、`appInfo`（不是能力，只在 `none` 為 null；`main()` 在 `lib/main.dart:~154` 前用 `platform.appInfo!.read()`，**有資料目錄的平台必須給 appInfo**，這點沒有 assert 守）。

`main()` 對有資料目錄的平台一律用 `!`：`platform.legacyDataLocator!`（main.dart:~109）、`secureStorage!`、`cacheDirectory!`、`restarter!`、`appInfo!`。所以 macOS 一旦宣告 `dataDirectory: true`，這五個都不能是 null（其中 `cacheDirectory!` 與 `capabilities.cache` 由 assert 綁；`secureStorage!` 與 `secureStorage` 宣告綁）。

### 1.3 `assemble` 的 switch 與 Windows 分支原文

`assemble`（`platform.dart:108–178`）簽名：

```dart
factory AppPlatform.assemble(
  TargetPlatform platform,
  AppFlavor flavor, {
  Future<SystemMediaControls> Function(Log log)? androidMediaControls,
  Future<SystemMediaControls> Function(Log log)? windowsMediaControls,
  Future<WindowChrome> Function()? windowsWindowChrome,
  String? legacyDirectory,
}) => switch (platform) {
  TargetPlatform.android => AppPlatform._(...),   // 116–165，內嵌
  TargetPlatform.windows => _windows(flavor, windowsMediaControls, windowsWindowChrome, legacyDirectory), // 166–171
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => AppPlatform._(
    capabilities: PlatformCapabilities.none,
  ),                                               // 172–177
};
```

Windows 分支（switch 內 166–171）與 `_windows`（180–254）原文：

```dart
    TargetPlatform.windows => _windows(
      flavor,
      windowsMediaControls,
      windowsWindowChrome,
      legacyDirectory,
    ),
```

```dart
  static AppPlatform _windows(
    AppFlavor flavor,
    Future<SystemMediaControls> Function(Log log)? windowsMediaControls,
    Future<WindowChrome> Function()? windowsWindowChrome,
    String? legacyDirectory,
  ) {
    final dataDirectory = WindowsAppDataDirectory(
      flavor: flavor,
      executablePath: Platform.resolvedExecutable,
      roamingAppDataPath: Platform.environment['APPDATA'],
      applicationSupportPath: () async =>
          (await getApplicationSupportDirectory()).path,
      documentsPath: () async =>
          (await getApplicationDocumentsDirectory()).path,
    );
    return AppPlatform._(
      capabilities: const PlatformCapabilities(
        dataDirectory: true,
        singleInstance: true,
        fontFallback: windowsFontFallback,
        fontChoices: windowsFontChoices,
        playback: windowsPlaybackSupport,
        networkInterfaces: true,
        cache: windowsCacheSizes,
        secureStorage: true,
        files: true,
        loginWebView: true,
        urlOpener: true,
        restartsItself: true,
        shareFiles: true,
        pluginDevTools: true,
        // 系統標題列隱藏、App 自繪（ADR 0035 §決定 6）；Windows 的快捷鍵用 Ctrl。
        customTitleBar: true,
        // SMTC 不支援 seek，timeline 也不會自己前進：播放中每 5 秒重推位置。
        mediaControls: MediaControlsSupport(
          supportsSeek: false,
          positionRefresh: Duration(seconds: 5),
        ),
      ),
      appInfo: PackageInfoAppInfo(
        platform: 'Windows',
        osVersion: Platform.operatingSystemVersion,
        homeDirectory: Platform.environment['USERPROFILE'],
      ),
      dataDirectory: dataDirectory,
      networkInterfaces: ConnectivityPlusInterfaces.system(),
      cacheDirectory: CacheDirectory(
        applicationCachePath: _applicationCachePath,
      ),
      secureStorage: FlutterSecureStorageAdapter.system(flavor),
      fileDialogs: const FilePickerDialogs(),
      // WebView2 的使用者資料跟著資料目錄（dev 與 prod 分開、重設資料一起刪）。
      loginWebView: InAppLoginWebView.windows(
        userDataFolder: () async => p.join(
          (await dataDirectory.resolve()).path,
          loginWebViewDirectoryName,
        ),
      ),
      urlOpener: const UrlLauncherOpener(),
      fileSharer: SharePlusFileSharer(),
      windowChromeFactory: windowsWindowChrome ?? WindowManagerChrome.init,
      mediaControlsFactory:
          windowsMediaControls ?? (_) => WindowsSystemMediaControls.init(),
      restarterFactory: (_) => WindowsAppRestarter.system(),
      legacyDataLocator: windowsLegacyDataLocator(
        flavor: flavor,
        devDirectory: legacyDirectory,
        documentsPath: () async =>
            (await getApplicationDocumentsDirectory()).path,
        applicationSupportPath: () async =>
            (await getApplicationSupportDirectory()).path,
        roamingAppDataPath: Platform.environment['APPDATA'],
      ),
    );
  }
```

Android 分支的 `appInfo` 註解（platform.dart:135）：「資料目錄在 App 的沙盒裡，路徑不含使用者名稱：沒有要換成 `~` 的家目錄」，所以 `homeDirectory` 不給。

與組裝點相關的其他點：

- `withMediaControls`（313–344）與 `withWindowChrome`（348–378）各自手動複製所有欄位重建 `AppPlatform._`；新加欄位也要加進這兩處。
- `assemble` 的測試用注入參數是 `androidMediaControls`／`windowsMediaControls`／`windowsWindowChrome`，命名按平台；macOS 若要可注入的初始化需新增同款參數。
- 文件註解（platform.dart:101–102）：「只有 Android 與 Windows 有實作；其他平台驗證前宣告全部為『沒有』、也沒有實作檔（ADR 0009 §決定 4）」；259 行 `appInfo` 的註解、299 行起的 `restarter` 註解都寫著「Android、Windows」。

### 1.4 逐能力目錄

套件名以 `pubspec.yaml` 為準。「macOS 預估」只描述需要什麼，不建議做法。

#### app_data_directory/

- 介面：`app_data_directory.dart:11`（`AppDataDirectory.resolve()`）；另有 `ensureOutsideLegacyData`（45–51）、`LegacyDataLocationException`（26–39）、`dataDirectoryProvider`。
- Android：`app_data_directory_android.dart`（43 行）。`path_provider` 的 `getApplicationSupportDirectory`（注入）；dev 時用 `ensureOutsideLegacyData` 擋 `com.personal.fmp` 沙盒。dev 不加 `-dev`，靠 applicationId 後綴分開。
- Windows：`app_data_directory_windows.dart`（68 行）。程式目錄有 `unins000.exe` ＝安裝版用 application support（`%APPDATA%\<Company>\<ProductName>`），否則程式旁 `userdata`／`userdata-dev`；dev 擋 `Documents\FMP` 與 `%APPDATA%\com.personal\fmp`。
- 套件：`path_provider`（只准 `lib/platform/`）。
- macOS：需新實作檔。路徑來源（path_provider 的 `getApplicationSupportDirectory`）可沿用，但 dev／prod 分開與「dev 不得落在舊版位置」的規則要決定；ADR 0009 §決定 7 寫「macOS／iOS 沙盒 Application Support；開發版另用目錄與身分」。dev 與 prod 的 bundle id 不同，沙盒容器自然分開（`com.personal.fmp` vs `.dev`）。舊版沒有 macOS 資料（見 §6.3），所以不需要擋舊位置。

#### app_info/

- 介面：`app_info.dart`（`AppInfo` 值型別、`AppInfoReader`、`appInfoProvider`）。
- 實作：`package_info_app_info.dart`（`PackageInfoAppInfo`，Android／Windows 共用），平台名稱、`osVersion`、`homeDirectory` 由組裝點給。
- 套件：`package_info_plus`（macOS 端已在 `GeneratedPluginRegistrant.swift` 註冊為 `FPPPackageInfoPlusPlugin`）。
- macOS：可直接重用 `PackageInfoAppInfo`，組裝點給 `platform: 'macOS'`、`homeDirectory: Platform.environment['HOME']`。沙盒下 `HOME` 指向容器內，是否要遮蔽的路徑形式未驗證（unknown）。

#### app_restart/

- 介面：`app_restart.dart:8`（`AppRestarter.restart()`）、`appRestarterProvider`。
- Android：`app_restart_android.dart`。收掉媒體工作階段再 `exit(0)`，使用者手動再開。`restartsItself: false`。
- Windows：`app_restart_windows.dart`。`Process.start(Platform.resolvedExecutable, ['--fmp-restarted-from=<pid>'], mode: detached)` 然後 `exit(0)`；`windows/runner/main.cpp` 看到參數會先等舊 pid 結束。`restartsItself: true`。
- macOS：需新實作。`.app` 內的 `resolvedExecutable` 是 `Contents/MacOS/fmp`，直接 detached 啟動與 `open -n` 的差異未驗證；macOS 沒有單一實例 mutex 問題（LaunchServices 預設單實例，見 §6.1），但宣告 `restartsItself` 要真的做到，或宣告 false 並讓對話框說明手動再開（`restartsItself` 為假時 UI 已有文案，`debug_data_actions.dart:172`、`restore_flow.dart:123`、`legacy_import_flow.dart:275`）。**unknown**。

#### audio/ 與 `lib/playback/backends/`

- 介面／值型別：`audio.dart`（`AudioBackendKind { justAudio, mediaKit }`、`PlayableFormat`、`PlaybackSupport`）。列舉文件已寫「`just_audio`：Android（之後 iOS、macOS）」（audio.dart:6）。
- Android：`audio_android.dart`，`justAudio`，5 種格式，`outputDeviceSelection: false`。
- Windows：`audio_windows.dart`，`mediaKit`，同 5 種格式，`outputDeviceSelection: true`。
- 後端組裝：`lib/playback/backends/audio_backends.dart:15–16`（`AudioBackendKind.justAudio => JustAudioBackend(log: log)`、`mediaKit => MediaKitBackend.create(log: log)`）。兩種後端都已存在，不必新建列舉值。
- 套件與 macOS 註冊狀態：`just_audio` 與 `audio_session` 已在 macOS 的 `GeneratedPluginRegistrant.swift` 註冊。`media_kit` 在 macOS 沒有 libs 套件：`pubspec.yaml` 只有 `media_kit_libs_windows_audio`，registrant 裡沒有 media_kit。
- ADR 0018 §決定 3 寫 `JustAudioBackend`（Android、iOS、macOS），`MediaKitBackend`（Windows、Linux）；ADR 0018:76 寫「iOS／macOS 的格式支援（B 站 DASH 音訊、直播 HLS）在有機器時實測」。
- macOS：新檔 `audio_macos.dart`（宣告值）；格式清單與 `outputDeviceSelection` 要實測；`createAudioBackend` 有 assert 對齊 `outputDeviceSelection` 與後端 `outputDevices`（AGENTS.md:194–198）。

#### cache_directory/ 與 cache_sizes/

- `cache_directory.dart`：`CacheDirectory`（沒有介面，路徑從組裝點注入的 `getApplicationCacheDirectory`），底下再一層 `fmp_cache`。只准快取模組與組裝點 import（lint `restrictedImports`）。
- `cache_sizes.dart`：值型別 `CacheSizes`；`cache_sizes_android.dart`（128 MiB、100 張、50 MiB）、`cache_sizes_windows.dart`（256 MiB、200 張、80 MiB）。
- macOS：`CacheDirectory` 直接重用（`_applicationCachePath` 是 `platform.dart:381` 的私有函式，macOS 分支可共用）；`CacheSizes` 需新檔 `cache_sizes_macos.dart`（桌面值 256 MiB 的 ADR 0016 §決定 3 為「桌面平台」）。

#### connectivity/

- 介面：`connectivity.dart`（`NetworkInterfaces`）；實作 `connectivity_plus_interfaces.dart`（Android／Windows 共用）。
- 套件：`connectivity_plus`（macOS 端已註冊 `ConnectivityPlusPlugin`）。
- macOS：重用 `ConnectivityPlusInterfaces.system()`；在 macOS 沙盒的行為（是否需要 entitlement）未驗證。

#### files/

- 介面：`files.dart`（`FileDialogs`：`pickFile`、`saveFile`、`pickDirectory`）；實作 `file_picker_dialogs.dart`（`FilePickerDialogs`，兩平台共用）。
- 套件：`file_picker`（macOS 端註冊為 `file_picker_darwin` 的 `FilePickerPlugin`）。
- macOS：Dart 端可重用；原生端沙盒需要 `com.apple.security.files.user-selected.read-write` entitlement，現有 entitlements 沒有（見 §3.4）。`pickDirectory` 與 `pluginDevTools` 也相關。

#### fonts/

- `fonts.dart`：`FontFallback`（繁中／簡中兩份清單，`familiesFor` 組出英文）、`FontLanguage`。
- `fonts_android.dart`：`androidFontFallback = FontFallback.none`（交給引擎依 locale 挑）、`androidFontChoices = ['sans-serif','serif','monospace']`。
- `fonts_windows.dart`：`windowsFontFallback`（`Microsoft JhengHei UI`／`Microsoft JhengHei`；`Microsoft YaHei UI`／`Microsoft YaHei`）、`windowsFontChoices`（6 個）。
- macOS：需新檔 `fonts_macos.dart`。ADR 0035 §決定 5：「Apple 平台繁中用蘋方（`PingFang TC`）」。`PingFang SC` 的簡中對應與 Flutter macOS 引擎是否能以名稱對到字型，沒有現成研究（Android 註解的研究在 `.trellis/tasks/archive/2026-09/09-29-platform-layer/research/notes.md`，我沒有去讀）。

#### legacy_data/

見 §6.2。macOS 需要給 `LegacyDataLocator`（assert 要求非 null）。

#### login_webview/

- 介面：`login_webview.dart`（`LoginWebView`、`LoginWebViewSpec`、`loginWebViewDirectoryName = 'webview'`）；實作 `flutter_inappwebview_login.dart`（`InAppLoginWebView`，`.android()`／`.windows()` 兩個 factory）。
- 套件：`flutter_inappwebview` 6.2.0-beta.3（釘版）。macOS 現況：`flutter_inappwebview_macos` 在目前 Xcode 編不過，所以 `pubspec.yaml` 依賴本機 `packages/flutter_inappwebview_macos_stub`（純 Dart，`implements: flutter_inappwebview`，registrant 不含 WebView）。`AGENTS.md:366–367`：「macOS 的 WebView 在 macOS 平台任務決定」；stub 套件註解：「屆時刪掉這個套件」。
- macOS：這是真正的未決項。要嘛換回真實的 macOS 實作（要先解 Swift 編譯問題）並新增 `InAppLoginWebView.macos()`，要嘛宣告 `loginWebView: false`（此時帳號頁的網頁登入入口不出現，QR 登入是否可用不在本文範圍）。`webview_stub_test.dart` 守 stub，改動時要連同更新。

#### media_controls/

- 介面：`media_controls.dart`（`SystemMediaControls`、`MediaControlsSupport`、`NowPlaying`、`MediaCommand` 家族）。
- Android：`media_controls_android.dart`，`audio_service`（`AudioService.init`，`_Handler extends BaseAudioHandler`），加 `MediaKeyFix`（`fmp/media_keys` MethodChannel，原生 `MediaKeyFix.java`）。
- Windows：`media_controls_windows.dart`，`smtc_windows` 1.1.0（Rust 橋接）。
- macOS：`audio_service` 已在 macOS registrant 註冊（`AudioServicePlugin`）。`AndroidSystemMediaControls` 的 `init` 帶有 Android 專屬的 `androidNotificationChannelId` 等設定，其 `_Handler`、`androidPlaybackStateOf` 是 Android 檔的私有／Android 命名，不是共用實作；macOS 需要新檔（或把共用部分拆出，屬設計決定）。ADR 0018 §決定 8 與 :22 寫「蘋果平台還不接 Now Playing」、「轉接器 Android／iOS／macOS 用 `audio_service`」。`MediaControlsSupport.supportsSeek`／`positionRefresh` 在 macOS 的值未驗證（unknown）。
- 原生端：`audio_service` 在 macOS 的 Info.plist／entitlements 需求未驗證。

#### secure_storage/

- 介面：`secure_storage.dart`；實作 `flutter_secure_storage_adapter.dart`（兩平台共用，鍵前綴 `fmp-dev.`／`fmp.`，鍵規則 `^[a-z0-9][a-z0-9.-]*$`）。
- 套件：`flutter_secure_storage` ^11.2.0（macOS 註冊為 `flutter_secure_storage_darwin`）。
- `FlutterSecureStorage(aOptions: ...)` 只帶 Android 選項；`FlutterSecureStorageAdapter.system(flavor)` 沒有 macOS／iOS 選項（`MacOsOptions`）可調。
- macOS：Dart 端可重用；Keychain 在沙盒下通常需要 keychain access group／entitlement，現有 entitlements 沒有（unknown，要實機）。`integration_test/secure_storage_test.dart` 目前只在 Windows 的 CI 跑。

#### share/

- 介面：`share.dart`（`FileSharer`）；實作 `share_plus_file_sharer.dart`（兩平台共用）。
- 套件：`share_plus` ^13.3.1（macOS 註冊為 `SharePlusMacosPlugin`）。
- macOS：Dart 端可重用；`shareFiles` 回傳 true／false 語意（平台是否回報結果）在 macOS 未驗證。

#### shortcut_modifier/

- `shortcut_modifier.dart`：`enum ShortcutModifier { control, meta }`；`const appleShortcutModifier = ShortcutModifier.meta`（8 行）。
- macOS：組裝點宣告 `shortcutModifier: appleShortcutModifier`，不需新檔。

#### url_opener/

- 介面 `url_opener.dart`；實作 `url_launcher_opener.dart`（兩平台共用，`LaunchMode.externalApplication`）。
- 套件：`url_launcher`（macOS 註冊 `UrlLauncherPlugin`）。
- macOS：重用；沙盒對外開網址不需要額外 entitlement（未實測）。

#### window_chrome/

- 介面：`window_chrome.dart`（`WindowChrome`：`maximized`、`minimize`、`toggleMaximize`、`close`、`startDragging`）；實作只有 `window_manager_chrome.dart`（Windows），`WindowManagerChrome.init` 用 `TitleBarStyle.hidden`，不 show／focus。
- 套件：`window_manager` ^0.5.2（macOS 註冊 `WindowManagerPlugin`，連帶 `screen_retriever_macos`）。
- 文件承諾：`window_chrome.dart:6`「Mac 的自繪列由 macOS 平台任務接上」；`platform_capabilities.dart:81`「目前只有 Windows；Mac 的自繪列由 macOS 平台任務接上」。
- 規格：ADR 0035 §決定 6 與 :45–49：Mac 用同高同色（36dp、主題色）自繪列，**紅綠燈留在左側（系統按鈕，不重畫）**。ADR 0009 §決定 8（較早）寫「macOS 保留系統紅綠燈按鈕」。
- UI 現況：`lib/ui/shell/window_title_bar.dart` 的 `WindowTitleBar` 文件註解寫「Windows 的自繪標題列」，右邊放最小化／最大化／關閉三顆鈕；紅綠燈在左側的 Mac 版型目前 UI 沒有分支（UI 不判斷平台，也沒有「按鈕在左」的宣告欄位）。`WindowDragArea` 對所有 `customTitleBar` 平台通用。
- macOS：`window_manager` 的 `TitleBarStyle.hidden` 在 macOS 預設保留紅綠燈（`windowButtonVisibility` 選項）——這是套件行為，未在本專案驗證。需要決定 `WindowChrome` 介面對 macOS 是否重用（三顆鈕不畫、只剩拖曳與雙擊）還是擴充。`WindowManagerChrome` 的 `maximized` 狀態在 macOS 沒有對應語意（macOS 的綠鈕是全螢幕／縮放）。**unknown**。

#### 其他平台層目錄

- `lib/platform/` 內沒有其他能力目錄。`legacy_data/` 與 `app_info/` 不是能力宣告（無 `PlatformCapabilities` 欄位）。

---

## 2. 為 Apple 預備的東西（U 里程碑）

| 位置 | 承諾／內容 |
|---|---|
| `platform/shortcut_modifier/shortcut_modifier.dart:1–8` | `appleShortcutModifier = ShortcutModifier.meta`；「macOS／iOS 平台任務接上時宣告這個」 |
| `platform/platform_capabilities.dart:81` | 「目前只有 Windows；Mac 的自繪列由 macOS 平台任務接上」 |
| `platform/platform_capabilities.dart:84` | 「Apple 平台是 ⌘，其餘是 Ctrl」 |
| `platform/window_chrome/window_chrome.dart:6` | 「Mac 的自繪列由 macOS 平台任務接上」 |
| `platform/audio/audio.dart:6` | `just_audio`：「Android（之後 iOS、macOS）」 |
| `platform/legacy_data/legacy_credential_reader.dart:60` | `NoLegacyCredentialReader`：「沒有舊資料可讀的平台（Linux、macOS、iOS，以及 dev 的 Android）」 |
| `app/unsupported_platform_app.dart:9` | 「Linux、macOS、iOS 驗證前」顯示的畫面 |
| `ui/shell/shell_shortcuts.dart:6, 61–80` | `primaryChord(key, modifier)` 與 `queueChord`：Apple 平台開佇列是 ⌥⌘U（`SingleActivator` meta+alt，見 :77）；避開 ⌘Q |
| `ui/shell/playback_shortcuts.dart:68, 104`、`ui/shell/app_shell.dart:420, 644`、`ui/tracks/track_selection.dart:293–295`、`ui/player/player_page.dart:358` | 讀 `platformCapabilitiesProvider.select((c) => c.shortcutModifier)`，Apple 平台換 ⌘ |
| `test/ui/shell/shortcut_modifier_test.dart`、`test/ui/support/shell_harness.dart:221` | 以 `ShellHarness(shortcutModifier: ShortcutModifier.meta)` 跑 ⌘ 那一組（表的矩陣、⌘F、⌘,、⌥⌘U 含輸入框、沒有 ⌘Q） |
| `test/ui/shell/ios_conventions_test.dart:10–35` | 用 `TargetPlatform.iOS` 驗：轉場是 Cupertino、右滑返回、SafeArea（只 iOS，沒有 macOS 案例） |
| `test/platform/platform_test.dart:382–384` | `Apple platforms will declare ⌘ as the shortcut modifier`：只斷言常數值 |
| `app/AGENTS.md:212` | 「常數 `appleShortcutModifier` 給 macOS／iOS 平台任務接上」 |
| `app/AGENTS.md:2812` | 「tooltip 裡寫的 `Ctrl+…` 字串目前不隨平台換成 ⌘（Apple 平台還不啟動），macOS 平台任務接上時處理」 |
| `app/AGENTS.md:2901–2902` | iOS Dart 端慣例；「實機（手勢、動態島）留給 iOS 平台任務」 |
| `app/AGENTS.md:366–367` | macOS 沒有登入 WebView，用 stub；「macOS 的 WebView 在 macOS 平台任務決定」 |
| `.trellis/spec/app/platform/index.md:18–19, 84` | 同 `shortcut_modifier` 說明；Quality Check：「未驗證平台（Linux、macOS、iOS）沒有新的實作檔」 |
| `.trellis/spec/app/ui/index.md:177, 185, 351` | 快捷鍵表依 `shortcutModifier`，不要寫死 `control: true` |
| `docs/adr/0035-legacy-ui-baseline.md:45–49, 74, 76, 79–80, 95, 110` | Mac 自繪列（紅綠燈在左）、`PingFang TC`、Ctrl→⌘、⌥⌘U、「Mac 的紅綠燈標題列。Dart 側的設定隨 U 實作；原生部分與實機驗證交給 macOS／iOS 平台任務」、「macOS 平台任務照第 6 條做 Mac 標題列」 |
| `docs/adr/0009...:49–57, 62–63` | 套件選擇（`audio_service` 給 Android／iOS／macOS）、macOS 沙盒 Application Support、macOS 公證的政策 |
| `docs/adr/0022...:56, 91` | macOS 發佈物 `fmp-v{版本}-macos.zip`（未公證，macOS 平台任務加入）；應用內更新解壓後換 `.app` |
| `docs/adr/0026...:93–95`、`0027...:49` | macOS：Mac 到貨後開；每個里程碑一次冒煙測試 |
| `app/AGENTS.md:185`、`test/release/verify_release_assets_test.dart:152` | 「Linux、macOS 的發佈物由各自的平台任務加進 workflow 與 `expectedAssets`」 |
| `lib/data/cache/cache_store.dart:369` | 註解提到「macOS 上常見」的非同步解析順序現象（與平台層無關） |
| `app/tool/opencc/TSCharacters.txt` | `@tofu-risk: not covered by PingFang/Source Han baseline`：繁簡字表以 PingFang 為字型涵蓋基準之一（與 `PingFang TC` 的選用同源） |

**沒有**：任何 `TargetPlatform.macOS` 的分支（`platform.dart:173` 只在 `none` 的 `||` 列表裡）、任何 `fonts_macos.dart`／`PingFang` 的程式碼常數（`PingFang` 只出現在 ADR 與 opencc 註解）、任何 `Platform.isMacOS`。

---

## 3. `app/macos/` 原生專案現況

### 3.1 檔案

已追蹤（`git ls-files app/macos`）：`.gitignore`、`Flutter/Flutter-Debug.xcconfig`、`Flutter/Flutter-Release.xcconfig`、`Flutter/GeneratedPluginRegistrant.swift`、`Runner.xcodeproj/project.pbxproj`、`Runner.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist`、`Runner.xcodeproj/xcshareddata/xcschemes/{Runner,dev,prod}.xcscheme`、`Runner.xcworkspace/contents.xcworkspacedata`、`Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist`、`Runner/{AppDelegate.swift,MainFlutterWindow.swift,Info.plist,DebugProfile.entitlements,Release.entitlements}`、`Runner/Assets.xcassets/AppIcon.appiconset/`（Contents.json 與 7 個尺寸 png）、`Runner/Base.lproj/MainMenu.xib`、`Runner/Configs/{AppInfo,Debug,Release,Warnings}.xcconfig`、`RunnerTests/RunnerTests.swift`。

工作區未追蹤／已改：`Podfile`、`Podfile.lock`（未追蹤）；`Flutter/Flutter-{Debug,Release}.xcconfig`、`Runner.xcodeproj/project.pbxproj`、`Runner.xcworkspace/contents.xcworkspacedata`（已改）。`Pods/` 與 `Flutter/ephemeral/` 被 `.gitignore` 排除（`app/macos/.gitignore`：`**/Flutter/ephemeral/`、`**/Pods/`、`**/dgph`、`**/xcuserdata/`）。

沒有 `Runner/Configs/` 以外的自訂原生碼：`Runner/` 裡沒有 Swift 檔除了範本的 `AppDelegate.swift`、`MainFlutterWindow.swift`；沒有 MethodChannel。

### 3.2 原文（`git show HEAD:`，與工作區相同，這些檔未被改）

`Runner/Info.plist`：

```xml
<key>CFBundleDevelopmentRegion</key>   <string>$(DEVELOPMENT_LANGUAGE)</string>
<key>CFBundleDisplayName</key>         <string>$(APP_DISPLAY_NAME)</string>
<key>CFBundleExecutable</key>          <string>$(EXECUTABLE_NAME)</string>
<key>CFBundleIconFile</key>            <string></string>
<key>CFBundleIdentifier</key>          <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key>                <string>$(APP_DISPLAY_NAME)</string>
<key>CFBundlePackageType</key>         <string>APPL</string>
<key>CFBundleShortVersionString</key>  <string>$(FLUTTER_BUILD_NAME)</string>
<key>CFBundleVersion</key>             <string>$(FLUTTER_BUILD_NUMBER)</string>
<key>LSMinimumSystemVersion</key>      <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
<key>NSHumanReadableCopyright</key>    <string>$(PRODUCT_COPYRIGHT)</string>
<key>NSMainNibFile</key>               <string>MainMenu</string>
<key>NSPrincipalClass</key>            <string>NSApplication</string>
```

（原檔是標準 plist 格式，這裡壓成一行一鍵。沒有 `NSAppTransportSecurity`、`LSApplicationCategoryType`、`NSMicrophone…` 等鍵。）

`Runner/DebugProfile.entitlements`：

```xml
<key>com.apple.security.app-sandbox</key>        <true/>
<key>com.apple.security.cs.allow-jit</key>       <true/>
<key>com.apple.security.network.server</key>     <true/>
```

`Runner/Release.entitlements`：

```xml
<key>com.apple.security.app-sandbox</key>        <true/>
```

兩份都**沒有** `com.apple.security.network.client`、`files.user-selected.*`、keychain-access-groups、`com.apple.security.device.audio-input` 等。

`Runner/MainFlutterWindow.swift`：

```swift
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
```

`Runner/AppDelegate.swift`：

```swift
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
```

`Runner/Configs/AppInfo.xcconfig`：`PRODUCT_NAME = fmp`；`PRODUCT_COPYRIGHT = Copyright © 2026 com.personal. All rights reserved.`；註解指出 bundle id 與 `APP_DISPLAY_NAME` 依 flavor 寫在 `project.pbxproj`。
`Runner/Configs/Debug.xcconfig`：`#include "../../Flutter/Flutter-Debug.xcconfig"` ＋ `#include "Warnings.xcconfig"`；`Release.xcconfig` 同理指向 `Flutter-Release.xcconfig`。
`Runner/Configs/Warnings.xcconfig`：範本標準的 13 行 clang 警告設定（`WARNING_CFLAGS = -Wall ...` 等）。

### 3.3 部署目標與 scheme

- `MACOSX_DEPLOYMENT_TARGET = 12.0`，`project.pbxproj` 內 9 處（HEAD 也是 9 處、同為 12.0）。工作區 `Podfile` 為 `platform :osx, '12.0'`。
- Scheme（`Runner.xcodeproj/xcshareddata/xcschemes/`）：`Runner.xcscheme`、`dev.xcscheme`、`prod.xcscheme`。`dev` 的 Test／Launch／Analyze 用 `Debug-dev`、Profile 用 `Profile-dev`、Archive 用 `Release-dev`；`prod` 同理（`apple_identity_test.dart:54–66` 斷言）。
- Build configuration 有 Debug／Release／Profile 各加 `-dev`、`-prod`，共 9 個。
- App 套件名稱 `fmp.app`（dev、prod 相同），顯示名稱 `FMP`／`FMP Dev`（`APP_DISPLAY_NAME`），bundle id `com.personal.fmp`／`com.personal.fmp.dev`（AGENTS.md:111–113）。

### 3.4 工作區未提交的 CocoaPods 改動（只讀，未動）

`git diff --stat -- app/macos`：4 檔，+134 −3。內容：

- `Flutter/Flutter-Debug.xcconfig`：開頭多一行 `#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"`；`Flutter-Release.xcconfig` 同理加 `...Pods-Runner.release.xcconfig`。
- `Runner.xcworkspace/contents.xcworkspacedata`：多一個 `<FileRef location = "group:Pods/Pods.xcodeproj">`。
- `Runner.xcodeproj/project.pbxproj`：CocoaPods 整合——`Pods_Runner.framework`／`Pods_RunnerTests.framework` 檔案參照、`Pods` 群組與 18 個 `Pods-Runner*.xcconfig`／`Pods-RunnerTests*.xcconfig`（含 `-dev`／`-prod` 的每個 configuration）、`[CP] Check Pods Manifest.lock` 與 `[CP] Embed Pods Frameworks` 建置階段、`baseConfigurationReference` 指向 Pods xcconfig；另有兩處非 CocoaPods 的改動：`fmp.app` 的 `path = "fmp.app"` 變 `path = fmp.app`，以及 `XCLocalSwiftPackageReference "Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage"` 變 `"FlutterGeneratedPluginSwiftPackage"`（SwiftPM 整合的路徑寫法，Xcode／Flutter 工具重寫的）。
- `Podfile`（未追蹤）：標準 Flutter 範本，`platform :osx, '12.0'`；`project 'Runner', {'Debug' => :debug, 'Profile' => :release, 'Release' => :release}`（**沒有** `-dev`／`-prod` configuration 的對應，與 AGENTS.md:135–137 的說明一致：其他 configuration CocoaPods 一律當 release）；`target 'Runner'` 內 `use_frameworks!` 與 `flutter_install_all_macos_pods`；`RunnerTests` 繼承 `:search_paths`；`post_install` 呼叫 `flutter_additional_macos_build_settings`。
- `Podfile.lock`（未追蹤）：`PODS` 有 `flutter_js`、`FlutterMacOS`、`isar_community_flutter_libs` 三個；`COCOAPODS: 1.17.0`。
- 另外 `app/ios/` 也有同類未提交改動（Podfile、Podfile.lock、swiftpm 目錄），不在本文範圍。
- 這些改動會讓 `apple_identity_test` 變紅（AGENTS.md:36–38：「Mac 建置時 CocoaPods 會改那些檔、讓 `apple_identity_test` 變紅」），原因是 `flavorConfigurationProblems()` 要求每個 target 與 `baseConfigurationReference` 一致；新加的 Pods xcconfig 對 `-dev`／`-prod` 與 `Debug`／`Release` 的 base 不同——**此推論未實跑**。

### 3.5 已註冊的 macOS 外掛（committed `GeneratedPluginRegistrant.swift`）

`audio_service`、`audio_session`、`connectivity_plus`、`file_picker_darwin`、`flutter_js`、`flutter_secure_storage_darwin`、`isar_community_flutter_libs`、`just_audio`、`package_info_plus`、`screen_retriever_macos`、`share_plus`、`sqflite_darwin`、`url_launcher_macos`、`window_manager`。

沒有：`media_kit*`、`smtc_windows`、`flutter_inappwebview*`（stub，不註冊）。`webview_stub_test.dart:66–69` 斷言 registrant 不含 WebView。

---

## 4. 觸碰 Apple 的測試與閘門

### 4.1 `test/identity/apple_identity_test.dart`（312 行）

對 `ios` 與 `macos` 各跑一組（`for (final platform in ['ios','macos'])`），不需要 Xcode，自己用 OpenStep plist 解析器讀 `Runner.xcodeproj/project.pbxproj`：

1. prod 的 `PRODUCT_BUNDLE_IDENTIFIER` ＝ `{com.personal.fmp}`、`APP_DISPLAY_NAME` ＝ `{FMP}`（App 型 target 的 Debug／Profile／Release-prod）。
2. dev 為 `com.personal.fmp.dev`、`FMP Dev`。
3. 顯示名稱等於 Dart 的 `flavor.displayName`。
4. `Info.plist` 的 `CFBundleDisplayName` 是 `$(APP_DISPLAY_NAME)`；macOS 另要 `CFBundleName` 也是它。
5. 每個 `XCConfigurationList`（專案與每個 target）都要有 `Debug/Profile/Release` × `-dev/-prod` 共 6 個 configuration，且各自的 `baseConfigurationReference` 與同模式的 base configuration 相同。
6. `dev.xcscheme`／`prod.xcscheme` 的 Test／Launch／Profile／Analyze／Archive 各用對應 configuration。
7. 一組「parser mutations」（只對 ios 的 pbxproj）：違規會被算出來、無關格式改動不影響結果。

### 4.2 會因 macOS 啟用而需要更新的測試（現況斷言）

- `test/platform/platform_test.dart:151–211`：`for (final unverified in [linux, macOS, iOS, fuchsia])` 逐項斷言 `PlatformCapabilities.none`（dataDirectory false、`appInfo` null、`shortcutModifier` control、`fontChoices` 空…）。macOS 需從這個清單移出。
- `test/platform/platform_test.dart:382–384`：`Apple platforms will declare ⌘…` 只驗常數；macOS 宣告後可再加組裝點斷言。
- `test/platform/webview_stub_test.dart:62–69, 100`：「macOS resolves flutter_inappwebview to the Dart-only stub」、「the committed macOS plugin registrant registers no web view」、「the endorsed macOS plugin is caught」——若決定換掉 stub 就要改。
- `test/app/unsupported_platform_app_test.dart`：測 `UnsupportedPlatformApp` 本身（用 `Locale('zh','TW')` 驗字串），**沒有**測 macOS 會落入它；沒有任何測試斷言「macOS 顯示此平台尚未支援」（`main()` 分支沒有測試，AGENTS.md:191–192 也這樣寫）。
- 文件／註解會變假：`unsupported_platform_app.dart:9`、`platform.dart:101, 258`、`app_data_directory.dart:9`、`connectivity.dart:7`、`files.dart:5`、`share.dart:3`、`url_opener.dart:3`、`login_webview.dart:16`、`media_controls.dart:9`、`window_chrome.dart:5–6`、`app_info.dart:46`、`app_restart.dart:5` 都寫「實作有（只有）Android 與 Windows」。
- `test/support/quickjs.dart:20`、`test/support/libisar.dart:13`：macOS 主機不支援（不處理），所以 macOS 本機不能跑插件測試（AGENTS.md:30–36）。
- `test/release/verify_release_assets_test.dart:152`：macOS 發佈物之後加進 `expectedAssets`。

### 4.3 Lint `fmp_platform_checks`

- 規則：`app/packages/fmp_lints/lib/src/rules/platform_checks.dart`（`PlatformChecks`，lint code `fmp_platform_checks`）。以名稱判斷 `defaultTargetPlatform`、`TargetPlatform`、`Platform.isXxx`、`Platform.operatingSystem`，`lib/platform` 以外（`lib/` 內）報警告。
- 啟用：`app/analysis_options.yaml:60`（`fmp_platform_checks: true`）。
- 平台套件白名單：`packages/fmp_lints/lib/src/rules/layer_imports.dart:45–67` 的 `platformPackages`（`path_provider`、`window_manager`、`smtc_windows`、`audio_service`、`connectivity_plus`、`file_picker`、`package_info_plus`、`flutter_inappwebview`、`flutter_secure_storage`、`url_launcher`、`share_plus`、`win32`、`ffi` 等）。macOS 若引入新平台套件要加進這份清單並在 `layer_imports_test` 補案例。
- 哨兵：`app/tool/lint_sentinel.dart`。

---

## 5. CI

`.github/workflows/ci.yml`（`APP_FLUTTER_VERSION: 3.47.5`，env 於 :34–38）：

| Job | 行 | runner | timeout | 指令 |
|---|---|---|---|---|
| `app`（analyze＋test） | 206–213 | `ubuntu-latest` | 30 分 | 兩次 analyze 加 `flutter test`，**macOS 不跑測試** |
| `app-build-macos`（「App Build (macOS)」） | 412–444 | `macos-latest` | 45 分 | `flutter pub get`；`flutter build macos --flavor prod --release`；`flutter build macos --flavor dev --debug` |
| `app-build-ios` | 446–476 | `macos-latest` | 45 分 | `flutter build ios --flavor prod --release --no-codesign`；`flutter build ios --flavor dev --debug --no-codesign` |
| `app-integration-linux` | 484–~520 | `ubuntu-latest` | 30 分 | `xvfb-run -a flutter test integration_test/install_search_play_test.dart -d linux`、`toast_layering_test.dart` |
| `app-integration-windows` | 521–~556 | `windows-2022` | 30 分 | `install_search_play_test`、`toast_layering_test`、`secure_storage_test`、`legacy_credentials_test` 各一步 `-d windows` |
| `ci-result` | 558–575 | `ubuntu-latest` | 5 分 | `needs` 含 `app-build-macos`、`app-build-ios`（:570–571） |

- macOS build job 沒有 `pod install` 的獨立步驟，註解（:438–439）說「flutter_js 只有 podspec，建置時會產生 Podfile 並 pod install」。因此 CI 上的 Podfile 是臨時產生的、不提交（AGENTS.md:135–137）。
- 沒有任何 `flutter test -d macos` 的 integration job；`ci.yml:293–296` 註解：「Linux、macOS、iOS 還沒有平台實作，App 只開『此平台尚未支援』，這裡只證明建得起來」（平台任務完成後這段註解會失真）。
- `.github/workflows/app-release.yml`：job 為 `release-please`、`build-android`、`build-windows`、`verify`、`publish`；**沒有任何 macOS／darwin／dmg 字樣**（grep 無結果）。AGENTS.md:185 說明 macOS 發佈物由 macOS 平台任務加進 workflow 與 `expectedAssets`；ADR 0022:56 預定檔名 `fmp-v{版本}-macos.zip`（未公證）。
- 舊 `release.yml` 也沒有 macOS。

---

## 6. Windows 專屬行為與 macOS 對應

### 6.1 單一實例

- `app/windows/runner/main.cpp`：`kSingleInstanceMutexName`（:17）建 mutex；已存在時以 `FindWindowW(kMainWindowClassName, kMainWindowTitle)`（:52）找第一個實例的視窗，`ShowWindow(SW_SHOW/SW_RESTORE)` 與 `SetForegroundWindow`（:58–63）後結束。flavor 的 mutex 名與視窗標題寫在 `windows/runner/app_identity.cmake`（dev 的 mutex 是 `Local\FMP_MainInstance-dev`，AGENTS.md:107）。
- Dart 端只有宣告 `singleInstance: true`；`lib/` 內沒有任何程式讀 `capabilities.singleInstance`（grep 結果只有宣告與 `platform_capabilities.dart`／`platform.dart`）。
- macOS：`app/macos/Runner/AppDelegate.swift` 沒有任何單一實例邏輯；`.app` 經 LaunchServices 預設只開一個實例，但直接執行 `Contents/MacOS/fmp` 或 `open -n` 可開多個。是否要宣告 `singleInstance: true` 以及原生保證的做法（unknown）。dev 與 prod 因 bundle id 不同是不同 App。

### 6.2 舊資料位置（`legacy_data/`）

- 入口：`LegacyDataLocator`（`legacy_data_locator.dart:44`），回傳 `LegacySource`（資料庫檔 `fmp_database.isar` ＋ 憑證讀取器）；`LegacyLocations`（databaseDirectories ＋ credentialReader）。
- Windows（`legacy_data_locations.dart:25–60`）：prod 找 `<Documents>\FMP\fmp_database.isar`，其次 `<Documents>`；憑證讀 application support 的 `flutter_secure_storage.dat`（DPAPI，`WindowsLegacyCredentialReader`，`win32` ＋ `ffi`）。dev 只看 `--fmp-legacy-dir`（或 env `FMP_LEGACY_DIR`，`legacy_dev_entry.dart`），並擋真實舊位置。
- Android（:68–101）：prod 找 `<app_flutter>/FMP`，其次 `<app_flutter>`（`getApplicationDocumentsDirectory`）；憑證讀 `shared_prefs/FlutterSecureStorage.xml`（`AndroidLegacyCredentialReader`）。dev 只看 `--fmp-legacy-dir`、不讀憑證（`NoLegacyCredentialReader`）。
- 沒有 macOS 位置。`_none`（:103）是檔案內私有常數（`LegacyLocations(databaseDirectories: [], credentialReader: NoLegacyCredentialReader())`），沒有公開的「不找舊資料」locator 工廠；`AppPlatform._` 的 assert 要求有資料目錄的平台 `legacyDataLocator != null`。
- `NoLegacyCredentialReader` 的文件已把 macOS 列為「沒有舊資料可讀的平台」。

### 6.3 舊 App 在 macOS 有沒有存過資料

- 舊 App 根目錄只有 `android/`、`windows/`，**沒有 `macos/`、`ios/` 目錄**（`ls <repo 根目錄>`）；`.github/workflows/release.yml` 沒有任何 `macos`／`ios` 字樣；`README.md` 沒有 macOS 字樣。
- 舊程式碼會跑在 macOS 上的路徑：`lib/data/database/database_provider.dart:15, 51` 以 `getApplicationDocumentsDirectory()` ＋ `FMP` 為資料庫目錄；`lib/core/log_file_sink.dart:25`、`lib/services/download/download_path_utils.dart:209, 214` 也用同一函式。程式碼上能在 macOS 執行（見 §8），但沒有 macOS 的建置與發佈，ADR 0010:24 也寫「Linux、macOS、iOS 從未驗證」；AGENTS.md:115 寫「iOS、macOS 的舊版沒有發過」。結論：沒有發行過的 macOS 舊資料。

### 6.4 其他 Windows 專屬行為

- 重啟：見 §1.4 `app_restart/`；`windows/runner/main.cpp:21–23, 25–45, 73–74` 的 `--fmp-restarted-from=<pid>` 等待。
- 免安裝版／安裝版資料目錄分流（`unins000.exe`）：macOS 無對應概念（ADR 0022 §決定 5 是 Windows 安裝器）。
- WebView2 使用者資料夾：`InAppLoginWebView.windows`（macOS 無對應，見 login_webview）。
- Windows 版的 `rustup` 建置需求、`media_kit_libs_windows_audio`、`win32`／`ffi` 的 DPAPI：只在 Windows。
- Windows 的 SMTC `artworkUrl`（https URL，由系統自己下載）：`NowPlaying.artworkUrl`／`artworkFile` 兩種封面格式 macOS 用哪個未決。
- `windows/runner/flutter_window.cpp` 的 `SetNextFrameCallback` 才顯示視窗（`window_manager_chrome.dart:20–22` 註解）：macOS 的 `MainFlutterWindow` 沒有對應邏輯。

---

## 7. `app/AGENTS.md` § 平台層（187–375）與 § 資料目錄（375–387）

### 7.1 新平台必須遵守的規則

1. `PlatformCapabilities` 只含已經有實作的能力；Linux／macOS／iOS 驗證前宣告全部為「沒有」、沒有實作檔（:191–192）。
2. 新能力連同實作一起加：宣告欄位、各平台實作、組裝點分支、測試列在同一個 PR，不預留欄位（:193–195）。
3. 平台判斷只寫在組裝點 `lib/platform/platform.dart`（:196–197）；lint `fmp_platform_checks` 擋 `lib/platform/` 以外（:371–374）。
4. 播放後端的能力（`outputDeviceSelection`）不在 `AppPlatform`；`createAudioBackend` 的 assert 對齊（:198–202）。
5. 閘門：`test/platform/platform_test.dart` 以注入的平台值逐平台核對宣告與實作（未驗證平台必須全部為沒有）（:371–374）；組裝點以外的平台層檔案與「不預留欄位」沒有自動閘門，review 時看（:373–375）。
6. 平台套件只准在 `lib/platform/`（`platformPackages`）：`flutter_secure_storage`、`url_launcher`、`share_plus`、`window_manager`、`audio_service`、`smtc_windows` 各段重述（:206–208, 331–333 等）。
7. 初始化可能失敗的實作（媒體控制、window chrome）：`assemble` 先宣告有並帶工廠，`withMediaControls`／`withWindowChrome` 在 `main()` 初始化，失敗時記 log 並改宣告為沒有（:210–217, `.trellis/spec/app/platform/index.md` § 啟動時才知道的能力）。
8. `.trellis/spec/app/platform/index.md` § 加一個能力：介面不 import 平台套件；實作系統值從建構子注入、不讀 `Platform`；加欄位時連同 `none` 一起改；`AppPlatform` 加欄位並擴 assert；測試逐平台斷言；使用者看得到的能力另在 Android 模擬器與 Windows 實機驗。
9. App 身分（:100–137）：iOS／macOS bundle id、顯示名稱、`PRODUCT_NAME = fmp`；flavor 是 Xcode scheme，每個 target（含 `RunnerTests`、`Flutter Assemble`）都要有六個 configuration；閘門 `apple_identity_test.dart`。
10. 驗證表（:15）：Xcode 專案改動「第一列；本機沒有 Mac 時建置交給 CI 的 iOS、macOS job（prod release 與 dev debug 各一次）」。
11. ADR 規則（`AGENTS.md` 根）：`app/` 的程式需有已接受的 ADR 涵蓋；跨模組的新決定要新 ADR。
12. 使用者可見的改動要在實機驗（`verify-on-device`）；該 skill 目前只涵蓋 Android 與 Windows（skill 描述）。

### 7.2 明講「只有 Windows」或「只有 Android」的地方

- `platform.dart:101`（只有 Android 與 Windows 有實作）、`:258`（appInfo 只有能跑主 App 的平台）、`:303`（restarter：Android 的實作要收媒體工作階段）。
- `platform_capabilities.dart:67–69`（singleInstance：Windows 由 main.cpp mutex）、`:81`（customTitleBar：目前只有 Windows）、`:115–117`（restartsItself：Android 假）、`:121`（shareFiles：Windows 10 1809 以前拋錯）、`:125`（pluginDevTools：Android 沒有）。
- AGENTS.md：
  - :23–24 驗證表：播放後端改動「Windows 與 Android 模擬器各跑一次」；:25 系統媒體控制改動要 `flutter build windows --flavor dev` 與 Android 模擬器。
  - :107–109、:122–123、:138–139：Windows 的 mutex、視窗標題、ProductName 決定 path_provider 目錄。
  - :214：自繪標題列「只有 Windows」；:293–302 SMTC；:303–312 Android 前景服務；:324–335 Android 媒體鍵修正與 `MainActivity` 覆寫；:337–346 結束並重啟（Windows／Android 各一）；:345 `app_info`（Windows 用 `USERPROFILE`、Android 為空）；:358–364 登入 WebView 的 UA 與 WebView2。
  - :375–387 § 資料目錄：Windows 以 `unins000.exe` 分安裝版／免安裝版；dev 解析到 `Documents\FMP`、`%APPDATA%\com.personal\fmp`、Android `com.personal.fmp` 沙盒就拋 `LegacyDataLocationException`。
  - :2893：「必須在 Windows 實機驗」的標題列項目。
- 沒有任何一條規則寫「macOS 必須…」；macOS 只出現在 §2 列的幾處。

---

## 8. 舊 App（`lib/`，凍結，唯讀）中與 macOS 有關的地方

- `lib/main.dart:202–216`：`Platform.isWindows || isLinux || isMacOS` 時 `MediaKit.ensureInitialized()`（桌面走 media_kit）。
- `lib/main.dart:219–237`：非 Windows 桌面（Linux／macOS）只初始化視窗管理器（`_initializeWindowManager`，:314；`TitleBarStyle.hidden`，:329），不做 SMTC。
- `lib/core/utils/platform_utils.dart:3–8`：`isDesktopPlatform` 含 macOS。
- `lib/services/audio/audio_runtime_platform.dart:14`：`'macos'` 歸類為 `desktop`。
- `lib/services/audio/audio_service.dart:10` 註解：`audio_session` 只為 android、ios、macos、web 出 plugin。
- 托盤：`lib/services/platform/windows_desktop_service.dart`（Windows 專屬）；`pubspec.yaml` 有 `tray_manager`、`window_manager ^0.4.3`、`hotkey_manager`。舊 App 沒有 `macos/` 原生專案，所以以上 macOS 分支從未實際建置發佈。

---

## macOS 需要做的清單（依能力）

圖例：**重用**＝現有實作不改即可；**新 Dart**＝需要新檔或新分支；**原生**＝需要 `app/macos/` 的 entitlement／Swift／Info.plist 工作；**unknown**＝本盤點無法判定，需實驗或外部查證。

| 能力 | 狀態 | 備註 |
|---|---|---|
| `dataDirectory` / `app_data_directory/` | 新 Dart | 新 `app_data_directory_macos.dart`；套件 `path_provider` 沿用；dev／prod 靠 bundle id 分開；沒有舊版 macOS 位置要擋 |
| `app_info/` | 重用（`PackageInfoAppInfo`） | 組裝點給 `platform: 'macOS'`、`homeDirectory`（沙盒下取值 unknown） |
| `app_restart/` + `restartsItself` | 新 Dart ＋ unknown | 沒有現成實作；`Process.start` 在 `.app` 內的行為、或宣告 false 走手動再開 |
| `singleInstance` | unknown / 原生 | 目前 `AppDelegate.swift` 無邏輯；Dart 端無讀取者 |
| `audio/` + `playback` | 新 Dart（宣告值）＋ 實測 | `AudioBackendKind.justAudio` 已存在，`just_audio` 已註冊於 macOS；格式清單、`outputDeviceSelection` 待實測；`media_kit` 在 macOS 沒有 libs |
| `mediaControls` | 新 Dart ＋ 原生 unknown | `audio_service` 已註冊於 macOS；現有 Android 實作不能直接用；進度條／seek 行為 unknown |
| `fonts/`（`fontFallback`、`fontChoices`） | 新 Dart | `fonts_macos.dart`；ADR 0035 §決定 5 指定繁中 `PingFang TC`；簡中與可選字型清單未定 |
| `shortcutModifier` | 重用 | `appleShortcutModifier` 已存在；tooltip 的 `Ctrl+` 字串尚未隨平台換（AGENTS.md:2812） |
| `customTitleBar` / `window_chrome/` | 新 Dart ＋ 原生 unknown | `window_manager` 已註冊於 macOS；紅綠燈在左、三顆鈕不畫的 UI 分支目前不存在；`maximized` 語意 unknown |
| `networkInterfaces` / `connectivity/` | 重用 | `connectivity_plus` 已註冊；沙盒下行為待驗 |
| `cache` / `cache_directory/` / `cache_sizes/` | 重用 `CacheDirectory`；新 Dart `cache_sizes_macos.dart` | 桌面值（256 MiB 等）是否沿用 Windows 待定 |
| `secureStorage` | 重用 ＋ 原生 unknown | `flutter_secure_storage_darwin` 已註冊；Keychain 在沙盒下的 entitlement 現未設，待實機 |
| `files` / `pluginDevTools` | 重用 ＋ 原生 | `file_picker_darwin` 已註冊；Release／Debug entitlements 都沒有 `files.user-selected.*`；`pluginDevTools` 靠 `pickDirectory` |
| `loginWebView` | unknown（決策項） | 現為 `flutter_inappwebview_macos_stub`（純 Dart）；要換回真實 macOS 實作需先解 Xcode 編譯問題，或宣告 false；`webview_stub_test.dart` 需連動 |
| `urlOpener` | 重用 | `url_launcher_macos` 已註冊 |
| `shareFiles` | 重用 ＋ unknown | `share_plus` 已註冊；`shareFiles` 回傳語意待驗 |
| `legacy_data/`（`legacyDataLocator`） | 新 Dart | assert 要求非 null；舊版沒有 macOS 資料，需要一個空的 locator（目前只有檔內私有的 `_none`）；憑證讀取用 `NoLegacyCredentialReader` |
| 原生：entitlements | 原生 | Release 只有 `app-sandbox`；沒有 `network.client`（外連網路）；Debug 有 `allow-jit` 與 `network.server` |
| 原生：CocoaPods／Podfile | 決策項 | 工作區有未提交的 Podfile／pbxproj 改動；AGENTS.md:135–137 寫產生的 Podfile 不提交，提交要照官方文件補六個 configuration |
| 原生：`MainFlutterWindow`／`AppDelegate` | 原生 | 範本內容；標題列隱藏、視窗初始顯示、關閉最後視窗終止行為（現為 true） |
| 測試 | 新 Dart | `platform_test.dart` 把 macOS 移出 unverified 清單、加 macOS 組裝斷言；各能力 `<能力>_macos_test.dart`；`apple_identity_test` 在 pbxproj 變動後要仍綠 |
| CI | 無需新增（建置） | `app-build-macos` 已存在；沒有 macOS 測試／整合測試 job，由任務決定是否加；`app-release.yml` 要加 macOS 發佈物（`fmp-v{版本}-macos.zip`）與 `expectedAssets` |
| 文件 | 更新 | `AGENTS.md` § 平台層、§ 資料目錄、`.trellis/spec/app/platform/index.md`、`ci.yml:293–296` 註解、各介面檔「實作有 Android 與 Windows」的註解 |

## Caveats / Not Found

- 「macOS 預估」欄位僅依程式碼與已註冊外掛推斷；各套件在 macOS 的實際行為（沙盒、Keychain、紅綠燈、`path_provider` 的實際路徑）沒有查證，另有外部研究 agent 負責。
- 我沒有讀 `.trellis/tasks/archive/2026-09/09-29-platform-layer/research/notes.md` 與 `docs/` 的 design 文件（ADR 0009 提到的 `design.md §3` 各能力×平台表）；其中可能有更完整的 macOS 套件表。
- `apple_identity_test` 在目前髒工作區是否紅，我沒有實跑，只依 AGENTS.md:36–38 的說明列出。
- `AGENTS.md` 的行號是 2026-10-28 的檔案內容，該檔超過 2900 行，平台層區段以 `## 平台層`（約 187）到 `## 資料目錄`（約 375）為界。
- §7.2 中 `app/AGENTS.md` 的行號除 :107、:111–115、:185、:191–202、:212、:214、:366–367 外是依段落位置估的近似值（該檔 2900 多行），引用前請以內文關鍵字再 grep 一次。
