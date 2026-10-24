# Mac 開發環境的實測（2026-10-24）

主力開發從 Windows 電腦搬到 Mac（Apple Silicon，macOS 27）。這份記錄在 Mac 上實際跑過的結果，U 的 PR 1 與之後的驗證以它為準。

## 工具

- Flutter 3.47.5 stable（照 `.github/workflows/ci.yml` 的 `APP_FLUTTER_VERSION`），以 git clone 安裝；`flutter doctor` 沒有問題。
- CocoaPods 1.17.0：flutter_js 與 isar_community_flutter_libs 沒有 Swift Package Manager 支援，iOS、macOS 建置時 flutter 會產生 Podfile 並執行 `pod install`。
- 每次 iOS／macOS 建置都會改動這些檔：
  - `ios/`、`macos/` 的 4 個 xcconfig（加 `#include? Pods…`）；
  - 兩個 `project.pbxproj`、兩個 `contents.xcworkspacedata`；
  - 並新增 `Podfile`、`Podfile.lock` 與 SwiftPM 的 `Package.resolved`。
  
  依 `app/AGENTS.md` § App 身分不提交，留在工作區；要不要提交 Podfile 交給 macOS／iOS 平台任務。
- Bash 工具的沙箱會擋 `adb` 連本機 5037 埠，伺服器也會隨單次呼叫結束：在沙箱外以常駐方式啟動 `adb nodaemon server`。

## 各平台的 dev 版

| 平台 | 結果 |
|---|---|
| Android 模擬器 `Medium_Phone_API_37.0`（arm64） | `flutter build apk --flavor dev --debug` 成功；以 `--fmp-dev-plugin` 裝測試插件，搜尋並播放一首：`Track audible`（367ms），`dumpsys media_session` 為 `PLAYING`。重播模式，沒有連網 |
| macOS | `flutter build macos --flavor dev --debug` 成功，App 啟動（`App started`, dev／debug），畫面顯示「此平台尚未支援」 |
| iOS 模擬器（iPhone 17，iOS 27.0） | `flutter run --flavor dev` 成功啟動，同樣顯示「此平台尚未支援」 |

macOS／iOS 的畫面是設計使然：`lib/platform/platform.dart` 只有 Android、Windows 有實作，其他平台宣告 `PlatformCapabilities.none`，沒有資料目錄就不啟動資料層，插件裝不上也播不了。dev 版目前在 Mac 上沒有資料目錄，只有系統建的沙盒容器（`~/Library/Containers/com.personal.fmp.dev/`）。

## Mac 上的 `flutter test`

結果：4504 過、995 失敗，`test/ui/debug/debug_plugin_dev_test.dart` 卡死，逾時參數擋不住，要砍掉 `flutter_tester` 行程。失敗原因：

| 原因 | 失敗數（約） | 例子 |
|---|---|---|
| 插件執行環境：QuickJS 的原生庫只有 Windows、Linux 版（`test/support/quickjs.dart`），macOS 的 flutter_js 走 JavaScriptCore | 700 以上 | `test/plugins/**`、帳號與插件頁的 UI 測試 |
| 同一檔案裡被前面的插件測試拖垮 | 254 | `test/ui/guidelines_test.dart`，單獨跑佇列的案例會通過 |
| `libisar.dylib` 不在 | 30 以上 | `test/legacy_import/**` |
| CocoaPods 改過的 `project.pbxproj` | 44 | `test/identity/apple_identity_test.dart`（flavor 的 configuration 不再和 Debug／Profile／Release 同一個 base xcconfig） |
| 沒有 cmake | 4 | `test/identity/windows_identity_test.dart` |

`dart format`、`dart analyze --fatal-infos`、`flutter analyze` 都沒有問題。

## Windows 虛擬機（UTM）

- 規格：Windows 11 Pro ARM64，6 核、12 GB RAM。
- SSH 連不上的原因：虛擬機重開後網路被歸成「公用」，而 OpenSSH 的防火牆規則只開放「私人」。解法：另加一條只允許 Mac 主機連 22 埠的規則 `sshd-utm-host`，不論網路類別都有效。
- 建置工具（已裝、保留）：Git、Rustup、CMake、NuGet、VS 2022 Build Tools（C++、x64／ARM64 工具鏈、ATL x64／ARM64）、Flutter 3.47.5。
- 缺過的東西：
  - `flutter_inappwebview_windows` 要 `nuget.exe`（錯誤碼 9009）；
  - `flutter_secure_storage_windows` 要 ATL（`atlstr.h`）。
- `flutter build windows --flavor dev --debug` 成功，但產物是 ARM64：flutter_tools 3.47.5 在 ARM64 主機上固定以 `windows-arm64` 為目標（`commands/build_windows.dart`），沒有參數能改成 x64。
- 有三個依賴只附 x64 的 DLL：
  - `libmpv-2.dll`（media_kit，播放）；
  - `quickjs_c_bridge.dll`（flutter_js，插件）；
  - `libisar.dll`（舊資料匯入）。
  
  ARM64 行程載不了它們。
- 結論：虛擬機跑不了能播放、能載插件的 dev 版。**Windows 的實機驗證繼續在 Windows 電腦上做**；等這三個依賴有 ARM64 版，或 Flutter 能在 ARM64 主機建 x64，再重試。

## Apple 平台的快捷鍵慣例

Apple Music（support.apple.com「Keyboard shortcuts in Music on Mac」）：

- 顯示佇列：⌥⌘U；
- 音量：⌘↑／⌘↓；
- ⌘Q 是結束 App。

ADR 0035 §決定 7 照這個定。

## 後續（U PR 1）

- 完整的 `flutter test` 改用 `app/tool/linux_test.sh`：在 OrbStack 的 x86_64 Ubuntu 24.04 上跑，和 CI 同架構，約 9 分鐘。用法見 `app/AGENTS.md` § 驗證。
- 第一次在那台機器上跑時，`test/data/cache/cache_store_test.dart` 的「同時開兩次」失敗了一次。這是真的 bug：`openCacheStore` 先解析目錄才登記，後呼叫的可能先開。單獨跑時 macOS 10 次錯 8 次。已修成照呼叫順序登記，修好後 macOS 20 次全過。
