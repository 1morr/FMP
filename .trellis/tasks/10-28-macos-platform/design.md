# macOS 平台：設計

決定在 ADR 0036；這份寫怎麼落到程式碼。需求編號見 `prd.md`，事實來源見 `research/`。

## 1. 模組邊界

| 區塊 | 位置 | 改動 |
|---|---|---|
| QuickJS 原生庫 | `app/packages/fmp_quickjs/`（新） | 照搬的橋接原始碼與 QuickJS、podspec、授權與出處；Dart 端只有一個測試用的符號清單 |
| 原生專案 | `app/macos/` | entitlements、`Info.plist`、`AppDelegate.swift`、`MainFlutterWindow.swift`、Podfile、`Podfile.lock`、xcconfig、pbxproj |
| 組裝點 | `lib/platform/platform.dart` | 新的 `_macos(...)` 分支；macOS 從「未驗證」移出 |
| 各能力 | `lib/platform/<能力>/` | macOS 新檔：`app_data_directory_macos.dart`、`audio_macos.dart`、`cache_sizes_macos.dart`、`fonts_macos.dart`、`app_restart_macos.dart`、`media_controls_macos.dart`、`window_chrome` 的 Mac 實作；共用部分見各節 |
| 憑證 | `lib/platform/secure_storage/flutter_secure_storage_adapter.dart` | `system(flavor)` 帶 `MacOsOptions(usesDataProtectionKeychain: false)` |
| 標題列 UI | `lib/ui/shell/window_title_bar.dart` | 依 `WindowChrome.captionButtons` 排兩種版型，UI 不判斷平台 |
| 測試支援 | `test/support/quickjs.dart` | macOS 主機以 clang 編 `fmp_quickjs` 的原始碼成 dylib 並預先載入 |
| B 站插件 | `fmp-plugins` repo 的 `bilibili/` | `resolveLive` 依 `formats` 選 HLS |
| CI／發版 | `.github/workflows/ci.yml`、`app-release.yml`、`app/tool/release/` | macOS 整合測試、macOS zip |
| 驗證工具 | `.claude/skills/verify-on-device/references/macos.md`（新） | Mac 上的建置、啟動、操作、log |

## 2. QuickJS（R2，ADR 0036 §決定 1）

- 來源：`fast-development/android-js-runtimes` tag `0.3.6` 的 `quickjs/src/main/c/`，包括 `quickjs_runtime.cpp` 與 `quickjs/*`（QuickJS 2021-03-27）。
  - 只取 Android 的 CMake 用到的檔：`cutils.c`、`libregexp.c`、`libunicode.c`、`quickjs.c` 與它們的標頭。不取 `quickjs-libc.c`、`libbf.c`、`unicode_gen*`。
  - 放在 `packages/fmp_quickjs/src/`，旁邊放 `LICENSE`（MIT，含 QuickJS 的授權）與 `SOURCE.md`（repo、tag、檔案清單、取用日期、改了什麼）。
  - 原始碼不改；需要的補充放在另一個檔 `src/fmp_extras.c`：`jsSetMemoryLimit(JSRuntime*, size_t)` 包 `JS_SetMemoryLimit`。
- 編譯旗標：
  - 照 Android 的 CMake：`CONFIG_VERSION="2021-03-27"`、C++17、`-DQUICKJS`；
  - 加 `-Wno-error=int-conversion`：新的 clang 把 `quickjs.c` 兩處 `return NULL` 當錯誤，行為不變。
- 套件形式：Flutter plugin，只宣告 `macos`（之後 iOS 加 `ios`），`pluginClass` 是空的 Swift 類別。
  - podspec 的 `source_files` 是 `src/**/*.{c,cpp,h}`，加 `GCC_PREPROCESSOR_DEFINITIONS` 與 `OTHER_CFLAGS`。
  - CocoaPods 把它編成 framework 連進 App，啟動時就載入。`flutter_js` 的 `DynamicLibrary.process()` 走 `dlsym(RTLD_DEFAULT)`，找得到。
  - 要確認 release 建置沒有把符號剝掉：podspec 設 `DEAD_CODE_STRIPPING = NO`。實作時先以 `nm` 驗 framework 的 export，再決定是否需要這一行。
- App 依賴它：`pubspec.yaml` 加 `fmp_quickjs: path: packages/fmp_quickjs`，並加入 workspace。
- 測試支援（`test/support/quickjs.dart`）：macOS 主機上，
  1. 以 `xcrun clang` 把 `packages/fmp_quickjs/src` 編成 `.dart_tool/fmp_quickjs/<原始碼雜湊>/libfmp_quickjs.dylib`。只編主機架構；同一份雜湊已有就不重編。
  2. `DynamicLibrary.open` 它，之後 `flutter_js` 在 `FLUTTER_TEST` 下的 `DynamicLibrary.process()` 找得到。
  3. 編不出來就拋錯，不默默跳過，同 Windows、Linux 的「找不到原生庫就拋錯」。
  4. 插件的背景 isolate 在同一個行程裡，所以不必另外載入。
  - `libisar` 的主機載入在同一個 PR 看一下，做得到就一起做（`isar_community_flutter_libs` 的 macOS 目錄有 universal dylib），讓 `test/legacy_import/**` 在 Mac 上也能跑；做不到就記在 `app/AGENTS.md`。
- 閘門：`packages/fmp_quickjs/test/symbols_test.dart`：
  - 讀 pub cache 裡 `flutter_js` 的 `lib/quickjs/ffi.dart`，取出全部 lookup 的名稱；
  - 斷言 `src/` 編出的 dylib 都有（`nm -gU`）；
  - 只在 macOS 主機跑，其他平台 skip 並寫明原因。

## 3. 原生專案（R1、R6.1，ADR 0036 §決定 2、4、7、10）

- entitlements：
  - `Release.entitlements` 清成空的 dict。
  - `DebugProfile.entitlements` 只留 `com.apple.security.cs.allow-jit` 與 `com.apple.security.network.server`。
- `Info.plist` 加：
  - `LSMultipleInstancesProhibited` = true；
  - `NSAppTransportSecurity` → `NSAllowsArbitraryLoadsForMedia` = true。
- `AppDelegate.swift`：
  - `applicationShouldHandleReopen(_:hasVisibleWindows:)`：沒有可見視窗時 `mainFlutterWindow?.makeKeyAndOrderFront(nil)`，回 true。
  - `applicationShouldTerminateAfterLastWindowClosed` 照舊回 true。
- Podfile：
  - 照 Flutter 官方 flavor 文件（docs.flutter.dev/deployment/flavors-ios 的 Podfile 段）把 `Debug-dev`、`Debug-prod`、`Profile-*`、`Release-*` 對到 `:debug`、`:release`；
  - 和 `Podfile.lock`、xcconfig 的 `#include? "Pods/…"`、pbxproj 的 Pods 變動一起提交。
  - 提交前在乾淨的工作區跑 `flutter build macos --flavor dev --debug` 與 `--flavor prod --release`，確認之後 `git status` 不再有 `app/macos/` 的變動。
- `apple_identity_test.dart` 補上：
  - entitlements 沒有 `app-sandbox`、`keychain-access-groups`；
  - `Info.plist` 有那兩個鍵；
  - Podfile 的 configuration 對應。
  - 每一條都附變異案例：造出違規會紅，改縮排、註解不紅。
- 啟動閃爍：Windows 的 runner 等第一個畫面才顯示視窗。macOS 的 `MainMenu.xib` 預設啟動就顯示。實機看有沒有白閃；有的話在 `MainFlutterWindow` 先不顯示，第一個畫面出來再 `orderFront`。做法照 Windows 的 `SetNextFrameCallback`，Flutter macOS 的對應是 `FlutterViewController` 的 `engine` 第一個畫面回呼，實作時查 API。

## 4. 組裝點與各能力（R1、R3、R4、R5）

`AppPlatform.assemble` 加 `TargetPlatform.macOS => _macos(flavor, macosMediaControls, macosWindowChrome, legacyDirectory)`，形狀照 `_windows`。宣告如下：

| 欄位 | macOS |
|---|---|
| `dataDirectory` | true：`MacosAppDataDirectory(applicationSupportPath: …)`，`resolve()` 回 path_provider 的 application support（`~/Library/Application Support/<bundle id>`），不另加 `-dev`，因為 bundle id 已經不同 |
| `singleInstance` | true（原生端做，§3） |
| `fontFallback` | 繁中 `['PingFang TC']`、簡中 `['PingFang SC']`，日文不另列（系統 fallback） |
| `fontChoices` | `['PingFang TC', 'PingFang SC', 'Hiragino Sans']`（U design §2） |
| `playback` | `macosPlaybackSupport`：just_audio；`mp4/aac`、`mp3/mp3`、`flac/flac`、`wav/pcm_s16le`、`hls/aac`；不選輸出裝置 |
| `networkInterfaces` | true（`ConnectivityPlusInterfaces.system()`） |
| `cache` | `macosCacheSizes`，值同 Windows（桌面） |
| `secureStorage` | true（`FlutterSecureStorageAdapter.system(flavor)`，§5） |
| `files`、`pluginDevTools` | true（`FilePickerDialogs`） |
| `loginWebView` | true（`InAppLoginWebView.macos()`，§7）；CI 建不過時 false |
| `urlOpener`、`shareFiles` | true（沿用共用實作） |
| `restartsItself` | true（§6） |
| `customTitleBar` | true（§8） |
| `shortcutModifier` | `appleShortcutModifier` |
| `mediaControls` | `MediaControlsSupport(supportsSeek: true)`，Now Playing 自己依速率推進度，不重推；實機看，不對再改 |

- `appInfo`：`PackageInfoAppInfo(platform: 'macOS', osVersion: …, homeDirectory: Platform.environment['HOME'])`。log 遮蔽家目錄的規則和 Windows 相同。
- `legacyDataLocator`：`macosLegacyDataLocator(flavor, devDirectory)`。prod 回 `_none`；dev 有 `--fmp-legacy-dir` 時回那個資料夾加 `NoLegacyCredentialReader`，沒有時 `_none`。沒有「真實舊資料位置」要擋。
- `cacheDirectory`：`CacheDirectory(applicationCachePath: _applicationCachePath)`，同 Windows。
- 字串：Apple 平台的快捷鍵提示用 ⌘ ⌥ ⇧ 符號（AGENTS.md 提到 tooltip 的 `Ctrl+` 字串尚未隨平台換）。實作時查 `lib/ui/shell/*_shortcuts.dart` 與 tooltip 怎麼組字；如果是寫死的 `Ctrl+`，改成依 `shortcutModifier` 組，Windows 的字串不變。
- 測試：`test/platform/platform_test.dart` 把 macOS 移出未驗證清單，逐欄核對宣告與實作。

## 5. 憑證（R4.1，ADR 0036 §決定 3）

`FlutterSecureStorageAdapter.system(flavor)` 建套件實例時加 `mOptions: macOsOptionsFor(flavor)`，和 `androidOptionsFor` 一樣是公開的靜態函式，讓測試核對：

- `usesDataProtectionKeychain: false`；
- `accountName` 依 flavor：dev 是 `fmp-dev`，prod 是 `fmp`，對應套件的 service。dev 與 prod 已經有鍵前綴，帳戶名稱再分開是為了在「鑰匙圈存取」裡分得出來。

## 6. 重啟（R1.4，ADR 0036 §決定 5）

`MacosAppRestarter`：

- `restart()`：
  1. 收掉媒體工作階段（同 Android：`mediaControls?.dispose()`，Now Playing 才不會殘留）。
  2. 從 `Platform.resolvedExecutable`（`…/fmp.app/Contents/MacOS/fmp`）往上三層取 `.app` 路徑。
  3. `Process.start('/bin/sh', ['-c', 'while kill -0 $pid 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open "$1"', 'sh', bundlePath], mode: ProcessStartMode.detached)`。
  4. `exit(0)`。
- `pid` 與路徑都從建構子注入；`Process.start`、`exit` 也從建構子注入，單元測試核對指令與順序（同 `WindowsAppRestarter`）。

## 7. 登入 WebView（R4.2，ADR 0036 §決定 9）

- 刪除 `packages/flutter_inappwebview_macos_stub`、它在 `pubspec.yaml` 的依賴與 workspace 列；`webview_stub_test.dart` 改成只守 Linux，macOS 改成斷言解析到 `flutter_inappwebview_macos`。
- `InAppLoginWebView.macos()`：
  - WKWebView 沒有 WebView2 那種使用者資料目錄，資料在 App 的 `~/Library/WebKit/<bundle id>`，dev 與 prod 自然分開；
  - UA 照 Windows（桌面 Safari 或 Chrome 的 UA 由現有的 UA 規則決定，實作時看 `LoginWebViewSpec`）；
  - cookie 讀刪經 `CookieManager`，同其他平台。
- 重設資料要刪 WebView 的 cookie：`clearAll` 已經在登出、移除插件時呼叫；重設資料的流程有沒有呼叫它，實作時查。沒有的話，重設前先 `clearAll`。
- CI 的 macOS job 建不過時：保留 stub，`loginWebView: false`，在 ADR 0036 §決定 9 補一行結果。
- 結果（2026-10-28）：CI 的 Xcode 26.6 建不過（`presentationAnchor(for:)` 的可用版本），照上一點收尾；#357 的分支留著，CI 的預設 Xcode ≥ 27 時再用。

## 8. 標題列（R5.1，ADR 0035 §決定 6、ADR 0036 §決定 6）

介面 `WindowChrome` 加兩個成員：

```dart
/// 視窗鈕由誰畫。
enum CaptionButtons {
  /// App 在標題列右邊畫最小化、最大化、關閉（Windows）。
  drawn,
  /// 系統的紅綠燈在標題列左邊（macOS）；App 不畫，留出 [WindowChrome.leadingInset]。
  systemLeading,
}

CaptionButtons get captionButtons;

/// 標題列開頭要讓給系統鈕的寬度（邏輯像素）；`drawn` 永遠是 0，macOS 全螢幕時是 0。
ValueListenable<double> get leadingInset;
```

- `WindowTitleBar`：
  - `drawn` 照現在的版型；
  - `systemLeading`：左邊留 `leadingInset`（`AnimatedContainer` 不需要，直接換值）、「FMP」置中（同設計稿 APL-2 A）、右邊不放鈕，整條除了文字都是拖曳區。
- Mac 的實作 `MacosWindowChrome`，用 `window_manager`，放在 `window_chrome/` 底下：
  - `minimize`、`close`、`startDragging` 同 Windows；
  - `toggleMaximize` 用 `isMaximized`、`maximize`、`unmaximize`，也就是 macOS 的 zoom；
  - `maximized` 聽 `onWindowMaximize`、`onWindowUnmaximize`；
  - `leadingInset`：平常 78，`onWindowEnterFullScreen` 時 0，`onWindowLeaveFullScreen` 時 78。78 是紅綠燈三顆加左右間距的寬度，實機量過再定。
  - 和 Windows 共用的部分寫成同一個類別帶參數，或抽一個基底；看哪個比較短，實作時決定。
- 紅綠燈垂直置中：
  - `TitleBarStyle.hidden` 時，系統把紅綠燈放在 28pt 高的標題區中間，我們的列是 36dp，差 4pt。
  - 先試在 `MainFlutterWindow` 加一個空的 `NSToolbar`，`toolbarStyle = .unifiedCompact`，讓標題區變高。
  - 量得不準，就在 `windowDidResize`、`windowDidEnterFullScreen` 等通知裡調三顆鈕的 `frame.origin.y`。
  - 驗收：紅綠燈中心和標題列中心差不超過 1pt，最大化、全螢幕進出、換主題後都還在原位。
  - leanflutter/window_manager#333：加了 `NSToolbar` 之後，最大化或還原後的第一次點擊沒反應。實機要特別點一次看看。
- 雙擊：系統的標題區（上 28pt）自己處理雙擊與拖曳。`WindowDragArea` 的雙擊照樣呼叫 `toggleMaximize`。實機確認兩者不會重複觸發，也就是雙擊一次只縮放一次。
- 播放頁頂端的拖曳區照舊用 `WindowDragArea`。

## 9. 系統媒體控制（R3.3，ADR 0036 §決定 8）

- 從 `media_controls_android.dart` 抽出共用檔 `media_controls_audio_service.dart`：
  - `_Handler` 改成公開的 `AudioServiceCommandHandler`；
  - `androidPlaybackStateOf` 改名 `audioServicePlaybackStateOf`；
  - `reportAsyncErrors` 也搬過來。
  - Android 的通知設定與 `MediaKeyFix` 留在 Android 檔。
- `MacosSystemMediaControls.init(log)`：
  - `AudioService.init(builder: AudioServiceCommandHandler.new, config: const AudioServiceConfig())`；
  - `publish` 推 `MediaItem` 與 `PlaybackState`；
  - `dispose` 停服務。
- 封面：
  - audio_service 在 macOS 用 `extras['artCacheFile']` 的本機檔，Dart 端從 `artUri` 準備這個檔。我們傳的是 `file://` 的 `artworkFile`，實作時查 `audio_service.dart` 對 `file:` 的處理。
  - 如果不會自己設 `artCacheFile`，就在 `MediaItem.extras` 直接放檔案路徑。
- 測試：狀態轉換的純函數已有 Android 的測試，改名後照舊；macOS 的 `publish` 用 `forTest` 建 handler 核對 `MediaItem`。

## 10. 直播 HLS（R3.2）

- macOS 的 `PlaybackSupport.formats` 有 `PlayableFormat('hls', 'aac')`。播放模組把格式轉成 `StreamFormat` 交給插件（`LiveStreamRequest.formats` 已有，不改宿主 API）。
- B 站插件的 `resolveLive`：
  - `formats` 有 `hls/aac` 時，`Room/v1/Room/playUrl` 改用 `platform: 'h5'`（回 m3u8）；
  - 沒有時照舊用 `platform: 'web'`（FLV）。
  - Windows、Android 沒宣告 `hls`，行為不變。
  - 先錄一次 h5 的回應確認形狀（真實連線，錄 fixture，ADR 0027 §決定 2），再寫程式。
  - 插件版本升 minor，`checks.json` 加一個 HLS 案例。
- `just_audio` 以副檔名或 `Content-Type` 認 HLS。插件的候選如果是不以 `.m3u8` 結尾的網址，要確認 `JustAudioBackend` 怎麼開。實作時看 `lib/playback/backends/just_audio_backend.dart` 有沒有依格式選 `HlsAudioSource`。

## 11. CI 與發版（R6）

- `ci.yml` 的 `app-build-macos`：兩次建置之後加一步 `flutter test integration_test/install_search_play_test.dart -d macos --flavor dev`，時間上限照實際加。
- `app-release.yml`：
  - 加 macOS 建置 job：`flutter build macos --flavor prod --release`；
  - 以 `ditto -c -k --keepParent fmp.app fmp-v{版本}-macos.zip` 打包，`ditto` 保留符號連結與擴充屬性；
  - 上傳到草稿 release。
- `tool/release/verify_release_assets.dart`：`expectedAssets` 加 macOS zip，檢查 zip 根是 `fmp.app`、`Info.plist` 的 bundle id 與版本。
- 閘門：`release_workflow_test.dart`、`verify_release_assets_test.dart` 補案例。

## 12. 會壞或要改的測試

- `test/platform/platform_test.dart`：macOS 不再是 `none`。
- `test/platform/webview_stub_test.dart`：macOS 的段落。
- `test/identity/apple_identity_test.dart`：新的檢查。CocoaPods 的變動提交之後，「本機會紅」的說明（AGENTS.md）也一起改。
- 跟 macOS 宣告有關的 widget 測試：快捷鍵表、外觀設定的字型清單。目前用注入的宣告測，只在新增 macOS 版時補案例。

## 13. 文件

- `app/AGENTS.md`：
  - § 驗證：Mac 上能跑插件測試，`tool/linux_test.sh` 的理由改寫；
  - § App 身分：Podfile 已提交；
  - § 平台層：macOS 的各項；
  - § 資料目錄：macOS；
  - § 發版：macOS zip；
  - Xcode 那一列的驗證要求。
- `.trellis/spec/app/platform/index.md`：現有例子補 macOS，加 `fmp_quickjs` 的位置。
- `verify-on-device`：新增 `references/macos.md`，`SKILL.md` 的平台表加一列。
- `milestones.md`：macOS 的結果與兩項 §8 的去向。
