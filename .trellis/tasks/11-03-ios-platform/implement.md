# iOS 平台：執行計畫

每個 PR 都要讓 repo 可運作，合併前 CI 綠。設計見 `design.md`，需求見 `prd.md`，決定見 ADR 0037。

## 共同規則

- 每個 PR 都在 `app/` 跑 `app/AGENTS.md` § 驗證的第一列：
  - `dart format --output=none --set-exit-if-changed .`
  - `dart analyze --fatal-infos`
  - `flutter analyze`
  - `flutter test`（Mac 本機約 7 分鐘）
- 改到 `ios/`、`macos/`、`packages/fmp_quickjs/` 的 PR，另跑：

  ```bash
  flutter build ios --simulator --flavor dev --debug
  flutter build ios --flavor prod --release --no-codesign
  flutter build macos --flavor dev --debug        # 改到 fmp_quickjs、共用實作時
  flutter build macos --flavor prod --release     # 同上
  git status --short app/ios app/macos            # 建完不該有變動
  ```

- 有 UI 或平台行為的 PR，在 iOS 模擬器驗 dev：
  - 照 `verify-on-device` 的 `references/ios.md` 做（PR 4 之前還沒有，照 design §15 的步驟）；
  - 用 `orca emulator` 操作，讀回畫面才算數；
  - 回報寫明平台（模擬器機型與 iOS 版本，不寫 UDID）、模式（重播或真實）、做了哪些請求。
- 改到共用實作（Apple 共用、`ExitAppRestarter`、`PlaybackSupport`、`FileSharer`）的 PR，另照 `app/AGENTS.md` § 實機驗證驗 Android 模擬器，以及 macOS 或 Windows。
- **主 checkout 的 `app/ios/` 有未提交的 CocoaPods 變動，不動、不提交、不還原。** 每個 PR 在自己的 worktree 做。只 stage 明確的路徑，不用 `git add -A`。
- 不在 Xcode 的 Signing & Capabilities 選 team（會把 Team ID 寫進 pbxproj）。Team ID 只放本機的 `ios/Flutter/Signing.xcconfig`。
- 公開 repo：commit、PR、截圖、回報都不含 Team ID、UDID、裝置名稱、帳號名、email；本機路徑寫 `<家目錄>`。
- 實作交給 sonnet 子代理時，附 `design.md` 對應的節與這裡的驗收。遇到計畫外的設計決定就停下回報，例如：
  - 介面要多改一個參數；
  - 版面要重排；
  - Google 擋登入；
  - bundle id 註冊失敗；
  - 研究的實測結果在實作時不成立。

## PR 0：文件

- 檔案：
  - `docs/adr/0037-ios-platform.md`（擁有者核可後改「已採納」）；
  - ADR 0021 §決定 10、ADR 0022 §決定 3、ADR 0026 §決定 4 各加一行修訂，指向 ADR 0037；
  - 任務的 `prd.md`、`design.md`、`implement.md`、`implement.jsonl`、`check.jsonl`、`research/`。
- 驗收：
  - 只改文件，CI 只跑文件與舊 App 的 job（照路徑分）；
  - `git grep -n '0037'` 的引用都指得到。
- 回退：純文件。

## PR 1：原生專案（design §2）

- 檔案：
  - `app/ios/Runner/Info.plist`：`UIBackgroundModes`、`NSAllowsArbitraryLoadsForMedia`、`CFBundleName`；
  - `app/ios/Runner.xcodeproj/project.pbxproj`：App target 的 `CODE_SIGN_STYLE = Automatic`，加上 CocoaPods 的變動；
  - `app/ios/Flutter/Debug.xcconfig`、`Release.xcconfig`：Pods 與 `Signing.xcconfig` 兩行 `#include?`；
  - `app/ios/.gitignore`：`Flutter/Signing.xcconfig`；
  - `app/ios/Podfile`（六個 configuration、`platform :ios, '15.0'`）、`Podfile.lock`；
  - `app/ios/Runner.xcworkspace/contents.xcworkspacedata`；
  - 兩份 `xcshareddata/swiftpm/Package.resolved`；
  - `app/test/identity/apple_identity_test.dart`：design §2.4 的檢查與 `iOS file mutations`；
  - `app/AGENTS.md` § App 身分（Podfile 已提交、iOS 本機簽章、Info.plist 的鍵）、§ 驗證的 Xcode 列。
- 介面：無 Dart 介面。`apple_identity_test` 若要新的解析輔助（例如讀 plist 陣列），寫成檔內的頂層函式，附自己的變異案例。
- 測試：`flutter test test/identity/apple_identity_test.dart`。每條新檢查都要能證明：造出違規會紅，改無關格式不紅。
- 驗證：
  1. 在 worktree 從乾淨的 HEAD 照 design §2.3 產生 CocoaPods 檔，再建一次。
  2. 共同規則的兩個 iOS 建置；`git status --short app/ios` 只剩這個 PR 要提交的檔，提交後為空。
  3. 本機建 `ios/Flutter/Signing.xcconfig`（從 macOS 的同名檔取 `DEVELOPMENT_TEAM` 那一行），跑 `flutter build ios --flavor dev --release`。這一步只確認簽得起來、Xcode 產生得了 profile，不安裝；簽不起來就記下錯誤停下回報。
  4. 模擬器啟動 dev：仍顯示「此平台尚未支援」（能力還沒宣告）。
- 驗收：
  - CI 的 iOS、macOS job 綠；
  - `apple_identity_test` 在 Mac 本機與 CI（Linux）都綠；
  - pbxproj 沒有 `DEVELOPMENT_TEAM`。
- 回退：回退後建置再次改動追蹤中的檔案，不影響功能。合併後主 checkout 拉 main 前，那些未提交的 `app/ios/` 檔要先處理：由主對話依全域規則問擁有者要不要備份。

## PR 2：`fmp_quickjs` 給 iOS（design §3）

- 檔案：
  - `app/packages/fmp_quickjs/macos/` → `darwin/`（`git mv`）；
  - `darwin/fmp_quickjs.podspec`：兩個平台；
  - `app/packages/fmp_quickjs/pubspec.yaml`：`ios`、`macos` 的 `sharedDarwinSource: true`；
  - `SOURCE.md` 若寫到 `macos/` 的路徑，跟著改；
  - `app/ios/Podfile.lock`、pbxproj 的變動（多了 `fmp_quickjs` 這個 pod）；
  - `.github/workflows/ci.yml` 的 `app-build-ios`：prod 建置之後加 `QuickJS is linked into the app`（design §13 第 3 步）；
  - `app/AGENTS.md`：§ 驗證提到 `fmp_quickjs` 的地方（CI 的 iOS job 也查符號）；§ App 身分的 podspec 說明。
- 介面：無。
- 測試：
  - `packages/fmp_quickjs` 內的 `flutter test`（`symbols_test.dart`）照舊；
  - 完整的 `flutter test`。
- 驗證：
  1. 共同規則的 iOS 與 macOS 建置。
  2. `nm -gU build/ios/iphoneos/Runner.app/Frameworks/fmp_quickjs.framework/fmp_quickjs | grep ' _jsNewRuntime$'` 有結果。
  3. macOS 的同一個檢查照舊。
  4. `flutter test integration_test/install_search_play_test.dart -d macos --flavor dev`：macOS 的插件仍載得起來。
  5. `sharedDarwinSource` 不被接受時照 design §3 的退路做，在 ADR 0037 §決定 3 補一行。
- 驗收：
  - CI 的 macOS job（符號、整合測試）與 iOS job（新的符號檢查）都綠。
  - App 在 iOS 仍顯示「此平台尚未支援」。
- 回退：iOS 回到沒有 QuickJS，macOS 回到 `macos/`。

## PR 3：共用實作改名（design §4）

- 檔案：
  - `lib/platform/app_data_directory/app_data_directory_macos.dart` → `app_data_directory_apple.dart`；
  - `lib/platform/media_controls/media_controls_macos.dart` → `media_controls_apple.dart`；
  - `lib/platform/legacy_data/legacy_data_locations.dart`（函式改名）；
  - `lib/platform/app_restart/app_restart_android.dart` → `app_restart_exit.dart`；
  - `lib/platform/platform.dart` 的引用；
  - `test/platform/media_controls_macos_test.dart` → `media_controls_apple_test.dart`；
  - `app_restart_test.dart`、`app_data_directory_test.dart`、`legacy_data_locator_test.dart`、`platform_test.dart` 的引用；
  - `app/AGENTS.md`、`.trellis/spec/app/platform/index.md` 的引用。
- 介面（只改名，簽章不變）：

  ```dart
  final class AppleAppDataDirectory implements AppDataDirectory {
    AppleAppDataDirectory({required Future<String> Function() applicationSupportPath});
  }
  final class AppleSystemMediaControls implements SystemMediaControls {
    static Future<AppleSystemMediaControls> init(Log log);
    AppleSystemMediaControls.forTest(Log log);
  }
  LegacyDataLocator appleLegacyDataLocator({required AppFlavor flavor, required String? devDirectory});
  final class ExitAppRestarter implements AppRestarter {
    ExitAppRestarter({required Future<void> Function() stopMediaSession, required void Function(int code) exitProcess});
    factory ExitAppRestarter.forMediaControls(SystemMediaControls? controls, {void Function(int code)? exitProcess});
  }
  ```

- 測試：完整的 `flutter test`；名稱改了的測試群組照舊通過。
- 驗證：
  - `git grep -n 'MacosAppDataDirectory\|MacosSystemMediaControls\|macosLegacyDataLocator\|AndroidAppRestarter\|media_controls_macos\|app_restart_android'` 只剩封存任務與 ADR 的歷史敘述；
  - macOS 建置；macOS 實機冒煙：啟動、播一首、控制中心有 Now Playing；
  - Android 模擬器冒煙：啟動、播一首、Debug 頁重設資料後 App 結束。
- 驗收：
  - 行為不變；
  - CI 綠。
- 回退：`git revert`。

## PR 4：iOS 組裝與核心能力（曳光彈，design §5、§6、§9、§13、§15）

第一個在 iOS 上端到端跑起來的 PR。

- 檔案：
  - `lib/platform/platform.dart`：`_ios(...)`；`assemble` 加 `iosMediaControls`（這個 PR 先不用）；
  - `lib/platform/audio/audio_ios.dart`：`iosPlaybackSupport`，這個 PR 不含 `interruptions` 欄位，PR 6 再加；
  - `lib/platform/fonts/fonts_ios.dart`、`lib/platform/cache_sizes/cache_sizes_ios.dart`；
  - `lib/platform/secure_storage/flutter_secure_storage_adapter.dart`：`iosOptionsFor`、`system` 帶 `iOptions`；
  - design §5 列的 doc 註解；
  - `test/platform/platform_test.dart`、`secure_storage_test.dart`；
  - `.github/workflows/ci.yml`：`app-build-ios` 加模擬器開機與整合測試、刪 dev debug 實機建置、`timeout-minutes: 60`、更新註解（design §13）；
  - `.claude/skills/verify-on-device/references/ios.md`（模擬器的部分）、`SKILL.md`、`references/runtime-state.md`；
  - `app/AGENTS.md`：§ 平台層、§ 資料目錄、§ 驗證的 CI 段、§ 實機驗證；
  - `.trellis/spec/app/platform/index.md`：「未驗證平台」只剩 Linux。
- 這個 PR 先不接：
  - 系統媒體控制：`mediaControls: null`，PR 5 接；
  - 登入 WebView：`loginWebView: false`，PR 7 接；
  - 分享錨點：PR 8 接。iPad 的分享表暫時在螢幕中央。
- 介面：

  ```dart
  // lib/platform/audio/audio_ios.dart
  const iosPlaybackSupport = PlaybackSupport(/* 同 macosPlaybackSupport 的格式，outputDeviceSelection: false */);
  // lib/platform/fonts/fonts_ios.dart
  const iosFontFallback = FontFallback(traditionalChinese: ['PingFang TC'], simplifiedChinese: ['PingFang SC']);
  const iosFontChoices = ['PingFang TC', 'PingFang SC', 'Hiragino Sans'];
  // lib/platform/cache_sizes/cache_sizes_ios.dart
  const iosCacheSizes = CacheSizes(defaultLimitMebibytes: 128, memoryImages: 100, memoryImageMebibytes: 50);
  // FlutterSecureStorageAdapter
  static IOSOptions iosOptionsFor(AppFlavor flavor);
  ```

- 測試：
  - `platform_test.dart` 的 `iOS` 組（design §5）；
  - `secure_storage_test.dart` 的 iOS 選項；
  - `fonts_test.dart` 若逐平台列常數，加 iOS。
- 驗證（iOS 模擬器，iPhone，重播）：
  1. 啟動，不再是「此平台尚未支援」；資料目錄在容器的 `Library/Application Support`；log 的路徑顯示成 `~`（design §5 的 `HOME`）。
  2. 以 `SIMCTL_CHILD_FMP_DEV_PLUGIN` 安裝測試插件；搜尋、播一首；佇列三首，回到主畫面，背景換曲（design §7.6 的步驟）。
  3. 設一個值，結束 App 再開，值還在。
  4. `flutter test integration_test/secure_storage_test.dart -d <模擬器> --flavor dev`。
  5. Debug 頁重設資料：App 關閉，再開資料是空的（design §9）。
  6. 字型清單有四項；繁中的「骨」「直」「為」不是日文字形（design §5）。
  7. `flutter test integration_test/install_search_play_test.dart -d <模擬器> --flavor dev`。
  8. Android 模擬器冒煙（`FlutterSecureStorageAdapter.system` 改了）。
- 驗收：
  - CI 的 iOS job 綠，含符號檢查與模擬器整合測試，記下整個 job 的時間；
  - 上面八項通過。
- 回退：iOS 回到「此平台尚未支援」，CI 回到只建置。

## PR 5：系統媒體控制（design §8）

- 檔案：
  - `lib/platform/platform.dart`：`_ios` 的 `mediaControls`、`mediaControlsFactory`；
  - `test/platform/platform_test.dart`：`system media controls on iOS`；
  - `app/AGENTS.md` § 平台層的媒體控制段（iOS 共用 Apple 實作）、§ 驗證的系統媒體控制列（加 iOS 模擬器建置）；
  - `references/ios.md`：怎麼看 Now Playing。
- 介面：無新介面。
- 測試：`platform_test.dart`：宣告是 `supportsSeek: true`、沒有 `positionRefresh`；注入的工廠被用到；初始化失敗時宣告改為沒有。
- 驗證：
  - iOS 模擬器（重播）：播放、暫停、上下首時控制中心的 Now Playing（看得到時）；重設資料後不殘留；
  - macOS 冒煙：Now Playing 照舊。
- 驗收：
  - CI 綠；
  - 模擬器看得到的項目通過，看不到的列進 PR 10 的實機清單。
- 回退：iOS 回到沒有系統媒體控制，播放照常。

## PR 6：音訊中斷（design §7）

- 檔案：
  - `lib/platform/audio/audio.dart`：`AudioInterruptions`、`PlaybackSupport.interruptions`；
  - `audio_android.dart`、`audio_macos.dart`、`audio_ios.dart`、`audio_windows.dart`：填值；
  - `lib/playback/backends/backend_rules.dart`：`respondToInterruption` 的新參數與 Apple 的對應、`InterruptionKind` 的 doc；
  - `lib/playback/backends/just_audio_backend.dart`：建構子收 `interruptions`；
  - `lib/playback/backends/audio_backends.dart`：傳值與 assert；
  - 測試（design §7.5）；
  - `app/AGENTS.md` § 播放的中斷段；`.trellis/spec/app/playback/index.md` § 音量、速度、中斷、輸出裝置。
- 介面：

  ```dart
  enum AudioInterruptions { androidAudioFocus, appleAudioSession, none }
  // PlaybackSupport
  const PlaybackSupport({required this.backend, required this.formats, required this.outputDeviceSelection, required this.interruptions});
  // backend_rules.dart
  InterruptionResponse respondToInterruption({required bool begin, required InterruptionKind kind, required AudioInterruptions interruptions});
  // just_audio_backend.dart
  JustAudioBackend({required Log log, required AudioInterruptions interruptions});
  ```

- 測試：
  - `backend_rules_test.dart`：`audio interruptions (Android)` 照舊綠，`audio interruptions (Apple)` 與 `none` 拋錯；
  - `platform_test.dart`：四個平台的值；
  - `playback_controller_test.dart`：design §7.5 的情境（已涵蓋就不加）。
- 驗證：
  1. `flutter test integration_test/audio_backend_contract_test.dart -d <iOS 模擬器> --flavor dev`。
  2. 同一個契約測試在 Android 模擬器（加 `--flavor dev --no-uninstall`）與 Windows 各跑一次（`app/AGENTS.md` § 驗證的播放後端列）。
  3. iOS 模擬器：播放中用 Safari 播影片，FMP 暫停，log 的 `response` 是 `interrupted`；Safari 停下之後的事件照實記錄。
  4. Android 模擬器：`adb emu gsm call` 與 `gsm cancel`，掛斷後照舊續播（Android 的對應沒變的證據）。
- 驗收：
  - CI 綠；
  - 契約測試三個平台都過；
  - 模擬器上的中斷行為如上。
  - 來電續播列進 PR 10 的實機清單。
- 回退：iOS 回到來電後不續播，其他平台不變。

## PR 7：登入 WebView（design §10）

- 檔案：
  - `lib/platform/login_webview/flutter_inappwebview_login.dart`：`iosLoginUserAgent`、`InAppLoginWebView.ios`；版本解析的純函數；
  - `lib/platform/platform.dart`：`loginWebView: true`；
  - `test/platform/login_webview_test.dart`、`webview_stub_test.dart`、`platform_test.dart`；
  - `app/AGENTS.md` § 平台層的登入 WebView 段。
- 介面：

  ```dart
  String iosLoginUserAgent(String systemUserAgent, {required String osVersion});
  factory InAppLoginWebView.ios({required String osVersion});
  ```

- 測試：design §10 的 UA 與版本解析案例；iOS 解析到真的 `flutter_inappwebview_ios`。
- 驗證（iOS 模擬器，**真實連線**，只開頁不登入）：
  1. YouTube 插件的網頁登入停在 Google 的輸入帳號，沒有「不安全」的錯誤頁；
  2. B 站的網頁登入頁正常；
  3. 開、關、再開登入頁，帳號頁之後還能點；
  4. 回報列出開了哪些頁。
  5. Google 擋下時停下回報。
- 驗收：
  - CI 的 iOS job 綠（`flutter_inappwebview_ios` 在 CI 的 Xcode 建得過）；
  - 上面四項通過。
- 回退：`loginWebView: false`，帳號頁只剩 QR 與貼上 cookie。

## PR 8：手機與 iPad 的 UI（design §11、§12）

- 檔案：
  - `lib/platform/share/share.dart`、`share_plus_file_sharer.dart`：`origin`；
  - `lib/app/diagnostics/diagnostics_service.dart`、`lib/ui/debug/debug_export.dart`：傳 `origin`；
  - `tool/make_ios_icon.py`（新）、`ios/Runner/Assets.xcassets/AppIcon.appiconset/`（單一 1024 與 `Contents.json`）；
  - `ios/Runner/Base.lproj/LaunchScreen.storyboard`：背景色；
  - 測試（design §11）；
  - 驗證中找到的 bug 的修正與 widget 測試；
  - `app/AGENTS.md` § 介面（iOS 圖示怎麼產生，同 macOS 那段）、§ 平台層的分享段；
  - `references/ios.md`：iPad、分割畫面、外接鍵盤、深淺色的操作。
- 介面：

  ```dart
  Future<bool> shareFiles(List<String> paths, {required String mimeType, Rect? origin});   // FileSharer
  Future<void> share(DiagnosticsBundle bundle, {Rect? origin});                           // DiagnosticsService
  ```

- 測試：`share_plus_file_sharer_test.dart`、`diagnostics_test.dart`、`debug_export_test.dart` 的 `origin`；修正的 bug 各自的 widget 測試。
- 驗證（iOS 模擬器，重播）：design §12 的整張表，iPhone 與 iPad 各一輪。
  - 圖示：主畫面截圖；
  - 啟動畫面：深色模式冷啟動，沒有白閃（錄影或連拍截圖）；
  - Android 模擬器冒煙：分享診斷包照舊；
  - Windows：`FileSharer` 改了，分享一次。
- 驗收：
  - 表上每項通過，或已回報擁有者並得到決定；
  - CI 綠。
  - **設計稿等級的 UI 變動不在這個 PR 自己決定**，列給擁有者。
- 回退：各項獨立；分享的 `origin` 是可選參數，拿掉不影響其他平台。

## PR 9：發版的 IPA（design §14）

- 檔案：
  - `.github/workflows/app-release.yml`：`build-ios`，`verify`、`publish` 的 `needs`；
  - `tool/release/verify_release_assets.dart`；
  - `test/release/verify_release_assets_test.dart`、`release_workflow_test.dart`；
  - `app/AGENTS.md` § 發版。
- 介面：

  ```dart
  // verify_release_assets.dart（檔內私有）
  Future<List<String>> _iosIpaProblems(File ipa, {required String name, required String version, required ZipLister listZip, …});
  ```

  參數照 `_macosZipProblems` 的形狀。
- 測試：design §14 的案例；`only workflow_dispatch triggers it` 照舊。
- 驗證：
  - actionlint（`app/AGENTS.md` § 驗證的發版列）；
  - 本機照 workflow 的步驟打一個 IPA，用 verify 檢查；
  - 解開看 `Payload/Runner.app/Info.plist` 是 XML，bundle id 與版本對。
- 驗收：
  - CI 綠；
  - 本機的 IPA 通過 verify。
  - 用 SideStore 實裝不在範圍內。
- 回退：從 workflow 與 `expectedAssets` 拿掉。

## PR 10：驗收

- 模擬器：
  - 按 `prd.md` 的 Acceptance Criteria 在 iPhone 與 iPad 模擬器走完整流程；
  - 真實連線各一首或一間：B 站 DASH、B 站直播、YouTube、網易；
  - 紀錄寫在 `research/ios-acceptance.md`，含做了哪些請求。
- 實機（擁有者的 iPhone）：
  1. **先問擁有者時間**，列出要他在場的步驟：
     - 開發者模式（會重新開機）、信任電腦；
     - 第一次安裝後在「VPN 與裝置管理」信任開發者；
     - 解鎖與鎖屏；
     - 登入（網頁或 QR；QR 要第二支裝置掃）；
     - 一通來電或 FaceTime 音訊；
     - 有耳機時拔一次。
  2. `flutter build ios --flavor dev --release`，以 `devicectl` 安裝（`references/ios.md`）。
  3. 依 ADR 0037 §決定 16 的清單驗，每項記結果。
  4. `flutter test integration_test/secure_storage_test.dart -d <iPhone> --flavor dev`（debug，接著工具跑）。
  5. 同一個 team 覆蓋安裝一次，確認仍登入、資料還在。
- 修正驗收找到的問題（各自的修正 PR，照共同規則）。
- 收尾：
  - `milestones.md` 的 iOS 列：「AVPlayer 對 B 站 DASH 與直播 HLS」打勾；「Live Activity 本機逐行更新」移到 M7 的驗收；寫結果；
  - ADR 0037 補上實測與決定不符的更正行；
  - `.trellis/spec/app/platform/index.md` 與 `app/AGENTS.md` 收尾；
  - `references/ios.md` 補上實機的實際指令。
- 擁有者以 dev 版在 iPhone 上試用後認可，才算完成。

## 回退點

- 每個 PR 獨立可回退。
- PR 1 回退：建置再次改動追蹤中的檔案，不影響功能。
- PR 2 回退：iOS 沒有 QuickJS，macOS 回到 `macos/`；PR 4 之後要一起回退，否則 iOS 的插件載入失敗（CI 的模擬器測試會紅）。
- PR 3 回退：純改名；PR 4 之後回退要連 `_ios` 的引用一起改回。
- PR 4 回退：iOS 回到「此平台尚未支援」，CI 回到只建置；PR 5–8 依賴它。
- PR 5–9：互不依賴，各自回退。
