# 實驗：flutter_inappwebview 6.1.5 四平台建置（M0 票 04）

登入 WebView 要用的 `flutter_inappwebview` 6.1.5 在目前的工具鏈上四平台建不建得起來、能不能開一個網頁，並重驗 brief 事實 A4、W8、M8、K8。只驗建置與開頁，不做登入。

實驗程式可丟棄，但留在這裡：換 Flutter、Xcode、AGP、VS 或套件版本時照〈怎麼跑〉重量。

## 結果（2026-11-11）

環境：Flutter 3.47.5（Dart 3.13.4）；macOS 27.0.1、Xcode 27.2（brief 事實 T1 記的是 27.1，本機已更新）、CocoaPods 1.17.0；iOS 27.1 模擬器（iPhone Duo）；Android 模擬器 API 37（`Medium_Phone_API_37.0`），AGP 9.1.0、KGP 2.4.0、Gradle 9.3.1；Windows 11（`winpc`，Build 26200，cp950），VS 2026（MSVC 14.51.36231）。

`pubspec.lock` 解出：flutter_inappwebview 6.1.5、`_android` 1.1.3、`_ios` 1.1.2、`_macos` 1.1.2、`_windows` 0.6.0、`_platform_interface` 1.3.0+1。

| 平台 | 建置 | 開頁（example.com，讀回 `document.title`） | 要加的設定 |
| --- | --- | --- | --- |
| macOS | ✅ debug | ✅ | 沙盒要 `com.apple.security.network.client`（`flutter create` 的範本沒有；拿掉時頁面全白、沒有任何回呼，見下面 M3） |
| iOS 模擬器 | ✅ debug | ✅ | 無 |
| Android 模擬器 | ✅ debug、release | ✅ debug、release | `android.r8.proguardAndroidTxt.disallowed=false`（A4） |
| Windows | ✅ debug、release | ✅ debug、release | `windows/CMakeLists.txt` 對插件加 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`（W8）；`/FS` 留著當保險 |

每格的結果在 `results/<平台>.json`，release 是 `results/<平台>-release.json`：載入的網址、標題、WebView 的 user agent。截圖存在本機暫存目錄，不進 repo。

### 重驗的事實

- **A4（AGP 9 的 proguard 旗標）：仍需要。** 不加時 debug 與 release 都在 Gradle 設定階段失敗，`flutter_inappwebview_android-1.1.3/android/build.gradle` 第 44 行：「`getDefaultProguardFile('proguard-android.txt')` is no longer supported since it includes `-dontoptimize`」。加了 `android.r8.proguardAndroidTxt.disallowed=false` 後兩種都建得過，release（R8）沒有額外警告。上游 #2852 仍開著。
- **W8（VS 2026 的編譯選項）：define 仍需要；`/FS` 沒重現出需要；`/utf-8` 不需要。** 不加時插件編譯報 22 個 `error C2338`（STL1011：`<experimental/coroutine>` 已棄用，MSVC 14.51.36231 把它當錯誤）。`winpc` 共建了 13 次（每次都是刪掉目錄重來的乾淨建置）：

  | 補丁 | 次數 | 結果 |
  | --- | --- | --- |
  | 都不加 | 1 | C2338，失敗 |
  | 只加 define | 6 | 3 次成功、開得了頁；3 次在 `flutter_assemble`（MSB8066，Dart 那一段，還沒編到插件）失敗 |
  | define 加 `/FS` | 6 | 4 次成功（2 次 release）；1 次 `CL.exe` 以 0xC0000409 當掉（MSB6006）；1 次 `flutter_assemble` 失敗（MSB8066） |

  5 次失敗都是 docs/development.md〈平台〉 記的 `winpc` 環境問題（Dart 或 `CL.exe` 偶發當掉），重跑就過，和補丁無關；從沒出現 `/FS` 要防的 C1041（多個編譯行程同時寫同一個 PDB）。插件的 CMake 沒開 `/MP`，所以這個競爭可能本來就不會發生，但 3 次不足以證明，建議留著（舊版的註解說它在 VS 2022 不起作用，這點沒實測）。繁中 Windows（cp950）下插件的 `base64.cpp` 只報 C4819 **警告**：插件用自己的一套標準設定，刻意不開 `/WX`（見它的 `windows/CMakeLists.txt`），所以不需要 `/utf-8`；舊版 `windows/` 其實也沒加 `/utf-8`，原本那半句沒有出處支撐。上游 PR #2869 仍開著。
- **M8（macOS 在新 Xcode）：穩定版 6.1.5 在 Xcode 27.2 不加任何設定就建得過、開得了頁。** 27.1 沒試（本機已更新）。另一個發現：6.1.5 的 Apple 端（`_ios` 1.1.2、`_macos` 1.1.2）只有 podspec，沒有 `Package.swift`，Flutter 會退回 CocoaPods 並警告「The following plugins do not support Swift Package Manager … This will become an error in a future version of Flutter」。`app/` 目前沒有 Podfile（純 SwiftPM），加了它之後 iOS、macOS 都會多出 CocoaPods（Podfile、`Podfile.lock`、`Pods/`），建置機器要裝 CocoaPods。
- **M3 的 WKWebView 那半句（沙盒缺 `network.client` 時靜默失敗）：成立。** 把兩個 entitlements 檔的 `com.apple.security.network.client` 拿掉再建，頁面全白，30 秒內 `onLoadStop`、`onReceivedError` 都沒觸發，狀態列停在「loading」。M3 其餘幾句（子行程寫不了 `/Applications` 等）沒驗。
- **K8（beta 退回 stable 的 lock 殘留）：仍成立。** 先 `pub add flutter_inappwebview:6.2.0-beta.3`，再把 pubspec 改回 6.1.5 並 `pub get`：主套件回到 6.1.5，但 `_android`、`_ios`、`_macos`、`_web` 停在 1.2.0-beta.3、`_platform_interface` 停在 1.4.0-beta.3，建置在 Dart 編譯失敗（`InAppBrowser` is missing implementations…）。`flutter pub upgrade flutter_inappwebview` 清不掉；`flutter pub upgrade --unlock-transitive flutter_inappwebview` 把子套件都退回穩定版，之後建得過。`./lockfile-repro.sh` 重現整段（含一般的 `pub upgrade` 清不掉）。

### 其他觀察（給 M2 的登入票）

- WebView 的預設 user agent：Android 帶 `; wv`；iOS 27.1 模擬器報 `iPhone OS 18_7`、沒有 `Version/…Safari`；macOS 報 `Mac OS X 10_15_7`、也沒有 `Safari`。和登入有關的 UA 處理見事實 F12（未在這裡驗）。

## 檔案

| 路徑 | 內容 |
| --- | --- |
| `probe/` | Flutter App：開 `https://example.com/`，載入完成時讀回 `document.title` 與 user agent，顯示在頂端的黃色狀態列，結果寫成 JSON 並印出 `PROBE_FILE <路徑>` |
| `run.sh` | macOS、iOS 模擬器、Android 模擬器：建置、裝 App、開頁、截圖、取回結果 |
| `run-windows.sh`、`windows/probe.ps1` | Windows：同步到 `winpc` 的 `C:\fmpx\inappwebview`，以排程工作在桌面工作階段建置、開頁、截圖，取回結果 |
| `lockfile-repro.sh` | 重驗 K8 |
| `results/*.json` | 上表的結果（Windows 是最後一次 debug）。原始 log（`raw-*`）含本機路徑與主機名稱，不提交 |

## 怎麼跑

```bash
cd scripts/experiments/inappwebview
./run.sh macos
IOS_SHOT_ARGS=--display=1 ./run.sh ios     # iPhone Duo 截圖要 --display=1；IOS_DEVICE 預設 booted
./run.sh android                           # MODE=release 測 release
./run-windows.sh                           # FMPX_WIN_PATCH=0 / define 測不同的補丁組合；VERBOSE=1 加 -v
./lockfile-repro.sh
```

- 截圖存到 `SHOT_DIR`（預設每次新開一個暫存目錄，路徑印在最後），打開來看才算數。macOS 的截圖靠 `orca computer get-app-state`（要在 Orca 裡跑、並給 Orca 螢幕錄製與輔助使用權限）。
- 每次開跑先刪掉這個平台、這個模式上一次的結果檔；沒拿到結果時腳本以非零結束，不會留下舊檔。
- `run.sh` 的建置在鎖外；裝 App 到關 App、`run-windows.sh` 整段都經 `app/tool/device_lock.dart` 持有共用裝置鎖（docs/development.md〈平台〉），別的 worktree 正在用裝置時會等。
- 重驗 M3：刪掉 `probe/macos/Runner/*.entitlements` 的 `com.apple.security.network.client` 再 `./run.sh macos`，預期逾時、截圖全白。
- 重驗 A4：刪掉 `probe/android/gradle.properties` 的 `android.r8.proguardAndroidTxt.disallowed=false` 再 `./run.sh android`。
- 重驗 W8：`FMPX_WIN_PATCH=0`（都不加）、`define`（只加 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`）、不設（再加 `/FS`），開關在 `probe/windows/CMakeLists.txt`。
- `winpc`：ssh 主機別名、預設 shell 是 PowerShell、擁有者已登入桌面；截圖會短暫搶前景。用完 `dart run tool/device_lock.dart -- ssh winpc 'Remove-Item -Recurse -Force C:\fmpx\inappwebview'`（在 `app/` 裡跑）清掉。
