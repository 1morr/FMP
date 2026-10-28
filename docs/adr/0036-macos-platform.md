# 0036 — macOS 平台：不開沙盒、插件引擎同 Android 的 QuickJS、舊版 Keychain、App 自繪標題列保留紅綠燈

- 狀態：已採納
- 日期：2026-10-28
- 影響範圍：`app/macos/`（entitlements、`Info.plist`、`AppDelegate.swift`、`MainFlutterWindow.swift`、Podfile）、`app/packages/`（新的 QuickJS 原生庫套件）、`app/lib/platform/` 的 macOS 實作、`app/test/support/quickjs.dart`、插件 `resolveLive` 的格式宣告、CI 的 macOS job、`app-release.yml`

## 背景

ADR 0009 §決定 4：平台的實作在它的平台任務開始時才加。U 之後擁有者的順序是 macOS → iOS → M6（`milestones.md`，2026-10-24），Mac 是主力開發機，擁有者要在 Mac 上日常使用。研究在 `.trellis/tasks/10-28-macos-platform/research/`：

- `platform-inventory.md`：每個能力在 macOS 要什麼。
- `packages-macos.md`：釘住版本的套件在 macOS 的行為，含 ad-hoc 簽章加沙盒的實測。
- `plugin-runtime-macos.md`：插件執行環境在 macOS 的狀況。

四件事不能照既有 ADR 直接做：

1. **插件引擎**。ADR 0014 §決定 2 寫「iOS／macOS 用 JavaScriptCore」，但插件 worker 建在 `flutter_js` 的 `QuickJsRuntime2` 上，用到 module loader、`JSInvokable` 與 Promise 和 Future 互轉，這些 `flutter_js` 的 JavaScriptCore runtime 都沒有。`flutter_js` 0.8.7 在 macOS 不附 QuickJS：它以 `DynamicLibrary.process()` 找符號，結果找不到，插件一載入就失敗。
2. **沙盒**。Flutter 範本開著 App Sandbox。開著沙盒時，App 啟動的子行程不能寫 `/Applications`（實測），ADR 0022 §決定 6 的 macOS 更新做法（小腳本把舊 `.app` 改名再放上新的）在沙盒裡做不到。M6 的下載也會被限制在容器裡。ADR 0009 §決定 7 寫的「macOS／iOS 沙盒 Application Support」指的是目錄，沒有決定要不要沙盒。
3. **憑證**。沒有付費帳號就只能 ad-hoc 簽章。實測 `flutter_secure_storage` 的預設（data protection keychain）回 `-34018`；照它的 README 加 `keychain-access-groups`，App 一啟動就被 AMFI 殺掉。
4. **標題列**。ADR 0035 §決定 6 要 Mac 自繪標題列，同高同色、紅綠燈在左；ADR 0009 §決定 8 寫保留系統紅綠燈。兩者沒有衝突，但還沒有寫怎麼做。

## 考慮過的選項

### 插件引擎

- **A：照 ADR 0014 用 JavaScriptCore**。
  - 好處：系統內建，可以用時間上限中斷（實測可行）。
  - 壞處：
    - 要重寫 worker 的引擎層；
    - ES module 只能經私有 SPI（`moduleLoaderDelegate`、`JSScript`）載入，要寫原生碼；
    - 兩種引擎的行為差異（BigInt、全域名稱、錯誤訊息）沒有契約測試守。
- **B：所有平台換成可中斷的 QuickJS 套件**（`flutter_qjs_next`、`quickjs_engine`）。
  - 好處：API 幾乎相同，還能得到中斷與記憶體上限。
  - 壞處：要換掉 Android、Windows 上已經驗過的引擎。ADR 0014 補充（2026-09-30）已經因為這兩個套件都是單一作者、採用率低而不採用，這次沒有新的理由推翻。
- **C：自己編 `flutter_js` 在 Android 用的那份 QuickJS 橋接**（採用）。
  - Android 的 `libfastdev_quickjs_runtime.so` 來自 `fast-development/android-js-runtimes` 的 tag `0.3.6`（MIT）：`quickjs_runtime.cpp` 加 QuickJS 2021-03-27 原始碼。
  - 在 Mac 上編成 universal dylib 實測：`flutter_js` 的 `ffi.dart` 查 55 個符號，只缺 `jsSetMemoryLimit`（App 沒用到，lookup 是延遲的）。
  - 測試行程先 `DynamicLibrary.open` 這個 dylib 之後，`DynamicLibrary.process()` 找得到符號，eval 正確。
  - 代價：要維護一份原生原始碼的副本，但 Dart 端不動，引擎與 Android 相同。

### 沙盒

- **開著沙盒**：多一層隔離。代價：
  - ADR 0022 的 macOS 更新要改成另一種做法（例如請使用者手動覆蓋）；
  - M6 的下載位置要用 security-scoped bookmark；
  - 重啟時命令列參數會被丟掉（實測）。
- **不開沙盒**（採用）：App Store 以外散佈的 Mac 播放器多半如此，例如 IINA 的主程式 entitlements 沒有 `app-sandbox`。插件跑在 QuickJS 裡，碰不到檔案與網路，只能經宿主 API，所以沙盒對插件沒有多出保護。

### 憑證

- **付費帳號加 `keychain-access-groups`**：ADR 0022 已經決定暫不付費公證，不採用。
- **`MacOsOptions(usesDataProtectionKeychain: false)`**（採用）：存在使用者的 login keychain。實測 ad-hoc 簽章、重建二進位後仍讀得到，沒有跳授權視窗。

## 決定

1. **插件引擎**：macOS 也用 QuickJS，和 Android 是同一份橋接原始碼（`android-js-runtimes` tag `0.3.6`，MIT）。
   - 原始碼原樣放進本機套件 `app/packages/fmp_quickjs/`，附授權與出處。另加一個檔補上 `jsSetMemoryLimit`。
   - 由 podspec 編進 App 行程，`flutter_js` 的 `DynamicLibrary.process()` 就找得到。iOS 平台任務沿用同一個套件。
   - macOS 主機上的 `flutter test` 由 `test/support/quickjs.dart` 以 clang 把同一份原始碼編成 dylib 再預先載入，插件測試在 Mac 上也能跑。
   - 這條取代 ADR 0014 §決定 2 的「iOS／macOS 用 JavaScriptCore」。
2. **不開 App Sandbox**：`DebugProfile.entitlements` 與 `Release.entitlements` 都移除 `app-sandbox`，也不加 hardened runtime（沒有公證，ADR 0022）。
   - Debug 留 `cs.allow-jit` 與 `network.server`，`flutter run` 連進 App 要用。
   - 不加 `keychain-access-groups`：沒有 provisioning profile 時，App 會被殺掉。
   - 資料目錄是 path_provider 的 application support，也就是 `~/Library/Application Support/<bundle id>`；dev 與 prod 的 bundle id 不同，所以自然分開。
3. **憑證**：`flutter_secure_storage` 在 macOS 傳 `MacOsOptions(usesDataProtectionKeychain: false)`，存在使用者的 login keychain。之後若改用付費帳號與 data protection keychain，算是換儲存位置，要先另立 ADR 處理遷移。
4. **單一實例**：
   - `Info.plist` 設 `LSMultipleInstancesProhibited`：從 Finder、Dock、`open`、`open -n` 開，都會回到已在執行的那一個。
   - `AppDelegate` 實作 `applicationShouldHandleReopen`：沒有可見視窗時把主視窗帶回來。
   - 直接執行 `.app` 內的二進位擋不住，只有開發時會這樣做，不另外加鎖。
   - dev 與 prod 的 bundle id 不同，可以同時開。
5. **重啟**（重設資料、從備份還原之後）：
   - App 以分離的 `/bin/sh` 等目前的行程結束，再 `open` 自己的 `.app`，然後結束。
   - 不用 `NSWorkspace` 直接開新實例，因為 `LSMultipleInstancesProhibited` 會把它導回舊行程。
   - 這和 ADR 0022 的 macOS 更新腳本是同一個形式。
6. **標題列**：
   - `window_manager` 的 `TitleBarStyle.hidden` 隱藏系統標題，保留系統紅綠燈；App 在最上面畫 36dp、主題色的標題列。
   - 紅綠燈在左、垂直置中；「FMP」置中；不畫最小化、最大化、關閉三顆鈕。
   - 空白處可以拖曳；雙擊照系統的「縮放」。
   - 全螢幕時紅綠燈隱藏，標題列不再預留它們的空間。
   - 關閉最後一個視窗就結束 App，同 Windows；「關閉時留在背景」跟托盤一起在 M8 做。
7. **播放**：
   - `just_audio`（AVPlayer，ADR 0018 §決定 3）。可播格式和 Android 相同，但沒有 `webm/opus`：AVPlayer 不播 WebM。另外宣告 `hls/aac`：插件在 `resolveLive` 看到平台宣告 HLS，就給 HLS，不給 FLV（B 站插件改成 h5 平台的直播網址）。
   - `Info.plist` 設 `NSAllowsArbitraryLoadsForMedia`：AVPlayer 開 `http://` 網址會被 ATS 擋（實測 `-1022`）。這個例外只放寬媒體載入，Dart 的網路層本來就不受 ATS 管。
   - 輸出裝置跟著系統，App 內不能選。
8. **系統媒體控制**：`audio_service`（ADR 0018 §決定 8），接 Now Playing 與媒體鍵。和 Android 共用 handler 與狀態轉換；Android 專屬的部分（通知頻道、`MediaKeyFix`）留在 Android 檔。
9. **登入 WebView**：
   - 移除 `flutter_inappwebview_macos_stub`，改用套件預設的 `flutter_inappwebview_macos`。它在 Xcode 27.1 經 Swift Package Manager 建置成功（2026-10-28 實測）；stub 在 2026-10-10 加入時是建不過的。
   - CI 的 macOS runner 也建得過才採用，否則保留 stub、宣告沒有登入 WebView，帳號登入走 QR 與貼上 cookie（ADR 0012 §決定 8）。
10. **CocoaPods**：
    - `flutter_js` 與 `isar_community_flutter_libs` 沒有 Swift Package Manager 支援，所以 macOS 一定有 Podfile。
    - 提交 `macos/Podfile` 與 `Podfile.lock`，Podfile 照 Flutter 官方的 flavor 文件對應六個 build configuration；也提交 xcconfig 的 `#include? Pods…` 與 pbxproj 的變動。這樣建置不再改動追蹤中的檔案，`Debug-dev` 的 pod 也用 debug 編。
    - iOS 的 Podfile 由 iOS 平台任務照同樣做法處理。
11. **舊資料**：舊版沒有發過 macOS 版，prod 沒有可找的舊資料位置。dev 入口 `--fmp-legacy-dir` 照常可以指向從別的平台複製來的資料夾；舊憑證讀不到（Windows 是 DPAPI 加密），用 `NoLegacyCredentialReader`。
12. **CI 與發版**：
    - CI 的 macOS job 在現有的兩次建置之外，跑一次 `install_search_play_test.dart -d macos`，守插件引擎有沒有編進 App。
    - `app-release.yml` 加 `fmp-v{版本}-macos.zip`（ad-hoc 簽章、未公證，ADR 0022 §決定 3）。

採用的慣例：
- IINA 不開沙盒；
- `flutter_secure_storage` README 給「沒有 provisioning profile」的做法；
- Flutter 官方的 macOS flavor 與 Podfile 文件；
- Apple 的 `LSMultipleInstancesProhibited` 與 `applicationShouldHandleReopen`；
- Apple Music 的紅綠燈加整合標題列外觀。

## 後果

- 好的：
  - 插件在 Android、macOS（之後 iOS）跑同一個 QuickJS 版本，契約測試的結果適用；
  - Mac 上可以跑插件測試，不必每次都經 Linux 機器；
  - ADR 0022 的更新做法在 macOS 可行；
  - 建置不再改動追蹤中的檔案。
- 壞的：
  - 多維護一份 QuickJS 原始碼；
  - 沒有沙盒，App 被攻破時影響範圍較大；
  - 未公證的 App 第一次開啟要使用者手動放行（ADR 0022 已接受）；
  - 憑證在 login keychain，換成 data protection keychain 要遷移。
- 之後要注意：
  - 升級 `flutter_js` 時重新核對 `ffi.dart` 查的符號（`fmp_quickjs` 的測試列出全部）；
  - `window_manager` 已停止維護，macOS 的頂端點擊問題（leanflutter/window_manager#565）在每次 macOS 大版本實機看一次；
  - just_audio 在 Apple silicon 的時長問題（ryanheise/just_audio#1599，MP3）要在網易的 MP3 上實測。
- 修訂：ADR 0014 §決定 2 的引擎改為本 ADR §決定 1；ADR 0009 §決定 7 的 macOS 目錄依本 ADR §決定 2。

## 如何確認

- `test/identity/apple_identity_test.dart`：
  - entitlements 沒有 `app-sandbox` 與 `keychain-access-groups`；
  - `Info.plist` 有 `LSMultipleInstancesProhibited` 與 `NSAllowsArbitraryLoadsForMedia`；
  - Podfile 對應六個 configuration。
- `packages/fmp_quickjs` 的測試：`flutter_js` 查的每個符號都在。
- `test/platform/platform_test.dart`：macOS 的宣告與實作對得上。
- CI 的 macOS job：`install_search_play_test.dart -d macos`。
- 實機（擁有者的 Mac）：
  - 插件、播放（B 站 DASH、直播 HLS、YouTube、網易）、Now Playing 與媒體鍵；
  - 登入 WebView、憑證重開後仍在；
  - 標題列與紅綠燈、單一實例、重啟。
  - 步驟寫在 `verify-on-device` 的 `references/macos.md`。
