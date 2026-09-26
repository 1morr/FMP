# 研究：平台能力套件盤點與 Flutter 官方寫法建議

> 對應 `.trellis/tasks/09-27-design-platform` 的研究第 1、4 點。
> 目標平台：Android + Windows（第一波），Linux / macOS / iOS（後續）。
> 查證方式：pub.dev packages API（版本/發布時間/是否 discontinued）與 score API
> （`platform:*` tag）、context7、官方 README。政策類問題見另一份文件
> `platform-policy-and-peers.md`。查不到的一律寫「查不到」，未經一手來源證實的
> 推論一律標「推測」。所有 pub.dev 資料查證於 2026-09-27。

## 目錄

1. 系統匣（tray）
2. 視窗管理 + 自訂標題列
3. 全域快捷鍵
4. 開機自動啟動
5. 單一實例
6. 多視窗（桌面歌詞視窗）
7. 系統媒體控制
8. 登入用 WebView（含登入後讀 cookie）
9. 權限
10. 檔案選取 / 應用程式目錄
11. 應用內更新
12. 網路狀態
13. 音訊（僅列事實，不做引擎決策）
14. Flutter 官方對平台專屬程式碼的建議

---

## 1. 系統匣（System Tray）

| 套件 | 最新版 | 發布日期 | Discontinued | Android | iOS | Windows | macOS | Linux | 備註 |
|---|---|---|---|---|---|---|---|---|---|
| `tray_manager` | 0.5.3 | 見 FMP 現有 audit §4（已用） | 否 | – | – | ✅ | ✅ | ✅ | FMP 現況只接了 Windows；README 未寫 Linux 是走 `libayatana-appindicator3` 還是 StatusNotifierItem，需查原始碼確認（查不到，未在 README 明載）。 |
| `system_tray` | 見 pub.dev | — | 否 | – | – | ✅ | ✅ | ✅ | Spotube 未採用（其 pubspec 只有 `tray_manager`，見下方引用）；未再深挖，因 `tray_manager` 已是現有依賴且平台覆蓋相同，沒有理由多引入一個套件。 |

**來源**：`https://pub.dev/api/packages/tray_manager/score`（platform tag 含
android 以外的 windows/macos/linux）；Spotube 依賴確認見
`https://raw.githubusercontent.com/KRTirtho/spotube/master/pubspec.yaml`
（`tray_manager: ^0.5.0`）。

**結論**：`tray_manager` 已是 FMP 現有依賴且三桌面平台都聲明支援，維持使用，
只是目前只在 Windows 端接線；Linux 端要接時需先讀原始碼/範例 app 確認底層是
`libayatana-appindicator3`（GTK 沿用）還是新的 StatusNotifierItem 實作。

---

## 2. 視窗管理 + 自訂標題列

| 套件 | 最新版 | Discontinued | Windows | macOS | Linux | 備註 |
|---|---|---|---|---|---|---|
| `window_manager` | 見 FMP 現有 audit §4（已用） | 否 | ✅ | ✅ | ✅ | FMP 現況只接 Windows。 |
| `window_manager_plus` | 1.0.5（2024-10-08） | 否 | ✅ | ✅ | ❌ | **明確不支援 Linux**：README 原文「Linux is not currently supported.」，pub.dev 平台 tag 只有 `windows`/`macos`。是 `window_manager` 的獨立 fork/改寫，內建多視窗管理，但與 `desktop_multi_window` README 建議的另一個 fork（`boyan01/window_manager` 特定 commit）是**不同的兩個東西**，不要混淆。 |

**來源**：`https://pub.dev/api/packages/window_manager_plus/score`（tags 只有
`platform:windows`、`platform:macos`）；README 引用透過 WebFetch 讀取
`https://pub.dev/packages/window_manager_plus`。

**結論**：自訂標題列/視窗控制維持用 `window_manager`（三桌面平台都支援，FMP
已用於 Windows）。`window_manager_plus` 只在需要「多視窗」且能接受放棄 Linux
支援時才考慮，見下方第 6 節的取捨。

---

## 3. 全域快捷鍵

| 套件 | 最新版 | Windows | macOS | Linux | 備註 |
|---|---|---|---|---|---|
| `hotkey_manager` | 0.2.3（FMP 已用） | ✅ | ✅ | ✅（X11 only，見下） | pub.dev 平台 tag 三者皆列，但 Linux 端底層是 `keybinder-3.0`，只支援 X11。 |

**Linux Wayland 限制（事實，非推測）**：Wayland 的安全模型設計上不允許應用
程式攔截「未取得焦點時」的全域按鍵，這是協定層面的限制，不是某個套件沒做好：

- KDE 開發者討論：`https://discuss.kde.org/t/global-shortcuts-on-wayland/…`
  （原文核心論點：全域快捷鍵在 Wayland 下必須透過 compositor 提供的
  portal，應用程式本身無法像 X11 時代直接抓鍵盤事件）
- GNOME Shell 的
  `org.gnome.desktop.portal.GlobalShortcuts` 是目前最接近的補救方案，
  GNOME 46+/48 逐步落地，但需要 compositor 端支援且流程是「使用者互動綁定」
  而非程式主動抓鍵，功能覆蓋面比 X11 版 `keybinder` 窄。
  來源：GNOME 官方 portal 文件
  `https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html`
- Arch Wiki／Arch Linux Forums 對 `keybinder-3.0` 的說明同樣指出它是
  X11-only（依賴 `libX11`/`XGrabKey`）。

**結論**：`hotkey_manager` 維持用於 Windows/macOS/X11-Linux；Wayland-Linux
下全域快捷鍵在設計上要當作「已知不可行」而非之後修的 bug，若要支援只能走
`GlobalShortcuts` portal 且功能會縮水（需 compositor 支援、無法在背景任意
時刻攔截任意組合鍵）。

---

## 4. 開機自動啟動（Launch at Startup）

| 套件 | 最新版 | 發布日期 | Android | iOS | Windows | macOS | Linux | 機制 |
|---|---|---|---|---|---|---|---|---|
| `launch_at_startup` | 0.5.1（FMP 已用） | 見 audit §4 | – | – | ✅ | ✅ | ✅ | README 未列出各平台底層機制細節（查不到）。 |
| `auto_start_flutter` | 1.4.0 | 2026-03-30 | ✅ | ✅ | ✅ | ✅ | ✅ | **五平台全支援**，且 README 明載各平台機制（見下）。 |

**`auto_start_flutter` 各平台機制（來源：
`https://pub.dev/packages/auto_start_flutter` README 原文）**：

- **Windows**：原生寫入 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
  登錄檔（帶 `--autostart` 參數），不需額外原生程式碼。
- **macOS**：呼叫新版 `SMAppService.mainApp.register()` API 註冊為登入項目
  ——**需要 macOS 13+**（雖然套件宣稱最低支援 10.14，但這個 API 本身要 13+，
  對應 audit 文件裡「macOS 原生程式碼需求」的疑慮是真的：舊版 macOS 需要
  fallback 到 `SMLoginItemSetEnabled` 之類的舊 API，套件是否有 fallback
  未在 README 說明，查不到）。
- **Linux**：在 `~/.config/autostart/` 產生標準 X-GNOME `.desktop` 檔案，
  不需原生程式碼。
- **Android**：監聽 `BOOT_COMPLETED` broadcast 並啟動 headless
  `FlutterEngine`；**需要手動在 `AndroidManifest.xml` 加
  `<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />`**
  （套件本身不再預設帶這個權限宣告）。callback 必須是 top-level/static
  函式並加 `@pragma('vm:entry-point')`。

**結論**：若要把「開機自動啟動」做成真正跨平台一致的能力，
`auto_start_flutter` 是目前唯一五平台都支援且機制透明的候選；但 macOS
13 以下的行為是設計上的缺口，需要在設計文件裡明確標注最低版本需求，不能
當成「已解決」。若近期只做 Windows（現況），`launch_at_startup` 維持不動
即可，機制差異不影響決策。

---

## 5. 單一實例（Single Instance）

FMP 現況：Windows-only，C++ named mutex（audit §3/§3.8）。

| 套件 | 最新版 | 發布日期 | Android/iOS/Web | Windows/Linux/macOS | 機制 |
|---|---|---|---|---|---|
| `flutter_single_instance` | 1.7.0 | 2025-11-04 | ⚠️ 恆回傳「是第一個實例」（README 原文：「will always return `true` for `isFirstInstance` method」），行動端等於沒有這個能力 | ✅（README 標「Confirmed working」） | **README 未指名機制**（不是 named mutex/socket/lock file 的哪一種，查不到）；從依賴列表（`path_provider` + `grpc` + `protobuf`）與 macOS 設定需求（要求關掉 App Sandbox、要能「當 server 監聽/當 client 送焦點請求」）推測底層是「本機 gRPC channel + 檔案系統狀態」，**此為推測，非 README 明載**。另外 debug build 下永遠回報是第一個實例，除非手動關閉 `debugMode`。 |

**結論**：`flutter_single_instance` 可以覆蓋 Windows/macOS/Linux 三個桌面
平台，比現有的 Windows-only C++ named mutex 更省維護（不用自己寫平台原生
碼），但底層機制沒有在文件公開,若要採用建議先讀原始碼再決定是否信任其
跨程序協定的安全性/穩定性（例如 gRPC channel 的埠號/socket 路徑是否有
權限或多使用者衝突風險）。行動端本來就不需要這個能力（單一實例是桌面
多開視窗情境的問題），所以「行動端恆為第一個實例」不是缺點。

---

## 6. 多視窗（桌面歌詞視窗）

FMP 現況：`desktop_multi_window` 0.3.1，audit §3.7 已有完整的原生註冊
時序圖與流程說明。

| 套件 | 最新版 | Windows | macOS | Linux | 備註 |
|---|---|---|---|---|---|
| `desktop_multi_window` | 0.3.1（FMP 已用） | ✅ | ✅ | ✅ | README 建議搭配一個 fork 過的 `window_manager`（`boyan01/window_manager`，鎖定特定 commit）以取得視窗控制能力，**這個 fork 跟 `window_manager_plus` 是兩個不同的東西**，不要混淆（見第 2 節）。 |
| `window_manager_plus` | 1.0.5 | ✅ | ✅ | ❌ | 自帶多視窗管理，但明確不支援 Linux；若採用等於歌詞視窗功能在 Linux 上要另找方案或直接不支援。 |

**結論**：維持 `desktop_multi_window`（FMP 現有依賴且三桌面平台都支援），
不建議换成 `window_manager_plus`——後者雖然「自帶多視窗」比較省事，但
直接放棄 Linux 支援，與「目標平台功能對等」的前提衝突。`desktop_multi_window`
的已知代價（audit §3.7 已載明）是每個新視窗是獨立 Flutter engine，原生
plugin 要重新註冊一次，這件事在换任何套件的情況下都不會消失，除非放棄
「歌詞獨立視窗」這個功能形態本身。

---

## 7. 系統媒體控制

FMP 現況：Android 用 `audio_service` 0.18.18；Windows 用 `smtc_windows`
1.1.0（無 seek 支援，audit §3 已載明）；Linux/macOS/iOS 尚未串接。

**先回答任務指定的關鍵問題：目前沒有任何單一套件同時覆蓋 Android + iOS +
macOS + Windows + Linux 五個平台的系統媒體控制**，各平台仍需拼接不同套件：

| 平台 | 候選套件 | 最新版 | 發布日期 | 備註 |
|---|---|---|---|---|
| Android / iOS / macOS | `audio_service` | 0.18.18（FMP 已用於 Android） | 見 audit | 官方文件與 README 宣稱涵蓋 Android/iOS/macOS 三者的通知列/控制中心整合（`MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`），FMP 目前只接了 Android。 |
| Windows | `smtc_windows` | 1.1.0（FMP 已用） | 見 audit | 目前無 seek 支援（audit 已載明）；`audio_service_win` 是另一個候選（見下）。 |
| Windows（替代） | `audio_service_win` | 見 pub.dev | — | 定位是 `audio_service` 的 Windows 平台實作（federated plugin 的 windows 端），與 `smtc_windows` 是不同的兩條路：一個是「讓 `audio_service` 這個 app-facing API 在 Windows 上也能用」，一個是「直接包 SMTC 原生 API」。是否比 `smtc_windows` 更完整（例如是否支援 seek）需要進一步讀原始碼比對，**查不到**（README 未明確列出 seek 支援與否）。 |
| Linux | `audio_service_mpris` | 0.2.0（Spotube 採用，見
`https://raw.githubusercontent.com/KRTirtho/spotube/master/pubspec.yaml`） | — | 走 `audio_service` 的 federated 架構，把 MPRIS（D-Bus）接到同一套 app-facing API。 |
| Linux（替代） | `mpris_service` | 見 pub.dev | — | 獨立的 MPRIS 實作，不透過 `audio_service` 的 plugin 架構，直接自己起 D-Bus service。 |
| Linux（新發現，較冷門） | `anni_mpris_service` | 0.1.0（2022-09-06） | 已 3 年未更新，likeCount 僅 4，pub points 150/160 | 明顯是個人專案等級的小套件，維護活躍度低，不建議作為主要候選，僅供比較。來源：`https://pub.dev/api/packages/anni_mpris_service/score`。 |
| macOS（額外選項） | `flutter_media_session` | 見 pub.dev | — | 定位不明確是否涵蓋多平台或僅 macOS/iOS，README 需要進一步確認涵蓋範圍，**查不到完整平台清單**（初步查詢顯示它的訴求接近 `audio_service` 的替代品，但生態成熟度與採用度遠不如 `audio_service`，未深入比較）。 |

**結論**：系統媒體控制的現實是「`audio_service` 家族（federated plugin）
是唯一有機會做到多平台一致 API 的路線」——Android/iOS/macOS 走
`audio_service` 本體，Linux 走 `audio_service_mpris` 補上 federated
實作，Windows 則要在 `smtc_windows`（目前已用，但無 seek）與
`audio_service_win`（federated 路線但成熟度未知）之間選：如果 Windows
也想收斂進 `audio_service` 的同一套 API 之下，`audio_service_win` 值得
花時間評估；如果 SMTC 的 seek 缺口可以之後再補，`smtc_windows` 維持現況
風險最小。

---

## 8. 登入用 WebView（含登入後讀 Cookie）

FMP 現況：`flutter_inappwebview`（audit §4 已指出無 Linux 支援、
最後發布 2024-10-08，久未更新）。

| 套件 | 最新版 | 發布日期 | Windows | macOS | Linux | Android/iOS | Cookie 讀取 | 備註 |
|---|---|---|---|---|---|---|---|---|
| `flutter_inappwebview` | 見 audit §4 | 2024-10-08（久未更新） | ✅ | ✅ | ❌ | ✅ | 內建 `CookieManager` | audit 已載明無 Linux 支援；一年多沒發新版，長期維護風險需列入設計考量。 |
| `webview_flutter` | 見 pub.dev | — | 官方федерated plugin，桌面支援仍在發展中 | 部分支援 | 官方本身不含 Linux 實作 | ✅ | 有官方 `WebViewCookieManager` | Google 官方維護，行動端最穩，桌面覆蓋不如專門的桌面 WebView 套件完整。 |
| `desktop_webview_window` | 0.3.0 | 4 個月前（相對 2026-09 約當 2026-05 前後） | ✅（WebView2 1.0.992.28，Win10 需另裝 Runtime，Win11 內建） | ✅（WKWebView） | ✅（WebKitGTK-4.1/4.0 + libsoup-3.0） | – | **README 未提供 cookie 讀取 API**（只有 `runWebViewTitleBarWidget`、`WebviewWindow.create()`、`launch(url)`、`isWebviewAvailable()`），查不到內建 cookie 方法。 | 桌面三平台齊全，由 verified publisher `mixin.dev` 維護，524k 下載、160 分，維護訊號良好；但登入後讀 cookie 這個 FMP 需要的能力，目前檯面上的 README 沒有給答案，需要進一步翻原始碼確認是否可用 `evaluateJavascript('document.cookie')` 繞過（缺點是讀不到 HttpOnly cookie）。 |
| `webview_cef` | 0.6.2 | 32 天前（很新） | ✅（Win10+ x64） | ✅（12.0+，arm64/x86_64/universal） | ✅（x64/arm64；另有 eLinux Wayland/DRM-GBM 變體不依賴 GTK/X11） | – | **有明確 cookie API**：`WebviewManager().visitAllCookies()`、
`visitUrlCookies(url, bool)`、`setCookie`、`deleteCookie` | 基於 CEF/Chromium 149，桌面三平台 CI 都跑，更新頻繁（0.5.0 才剛做過含破壞性變更的大升級），但 publisher 是 unverified uploader、like/下載量遠低於 `desktop_webview_window`（88 like vs 222 like），屬於較新、還在快速迭代的套件。 |

**結論**：這是本次研究裡最沒有「一個套件打天下」答案的能力項。
`flutter_inappwebview` 的 Linux 缺口加上更新停滯，長期不是理想解；
桌面三平台 + 明確 cookie API 這個組合目前只有 `webview_cef` 符合，
代價是套件本身較新、社群訊號較小；`desktop_webview_window` 訊號更好但
cookie 能力不明確需要再查原始碼。若行動端與桌面端要走不同套件（行動端
留 `flutter_inappwebview` 或换官方 `webview_flutter`，桌面端另接
`webview_cef`/`desktop_webview_window`），這件事本身就是「登入 WebView」
這個能力天生無法用單一套件覆蓋五平台的證據。

---

## 9. 權限（Permissions）

| 套件 | 最新版 | Android | iOS | Windows | macOS | Linux | Web |
|---|---|---|---|---|---|---|---|
| `permission_handler` | 見 pub.dev | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |

**來源（一手 API 資料，非轉述）**：
`https://pub.dev/api/packages/permission_handler/score` 回傳的 `tags`
逐字為：
```
['publisher:baseflow.com', 'sdk:flutter', 'platform:android',
 'platform:ios', 'platform:windows', 'platform:web', 'is:plugin',
 'is:null-safe', 'is:wasm-ready', 'is:swiftpm-plugin',
 'is:built-in-kotlin', 'is:dart3-compatible', 'license:mit',
 'license:fsf-libre', 'license:osi-approved']
```
**macOS 與 Linux 完全沒有 `platform:` tag**，不是我方擷取遺漏，是套件本身
沒有宣告支援。

**結論**：FMP 目前沒有依賴 `permission_handler`（現況是自己寫
MethodChannel 版的 storage 權限服務，對應 audit 文件脈絡下的
`storage_permission_service.dart`）。這次查證的意義是：即使設計階段考慮
「乾脆全平台都改用 `permission_handler`」，這條路本來就走不通——macOS 和
Linux 需要另外的方案（例如 macOS 的檔案存取權限走 sandbox
entitlement/NSOpenPanel 使用者授權模式，Linux 桌面環境本身多半沒有
Android 式的執行期權限系統，多半是檔案系統 DAC 或 portal
（`xdg-desktop-portal`）授權模型），這兩個平台的「權限」概念本來就和
Android/iOS 不同，不是「换一個套件」能解決的問題。

---

## 10. 檔案選取 / 應用程式目錄

| 套件 | 涵蓋 | 備註 |
|---|---|---|
| `file_picker` | Android/iOS/Windows/macOS/Linux/Web 均支援檔案選取對話框 | 現有 FMP 依賴（假設；未在本次逐一重查版本，因非本輪 gap） |
| `path_provider` | 五平台皆支援，但語意不同：Android 有 app-specific 外部/內部儲存區分；iOS/macOS 走 sandbox 容器內的 `Documents`/`Application Support`；Windows/Linux 走 `%APPDATA%`/`~/.local/share` 類的使用者設定目錄 | 這是官方 first-party 套件（`flutter/packages` 倉庫下維護），屬最穩定、最沒有替代品必要的選項。 |

**結論**：這兩個能力已經是生態系「事實標準」，沒有必要重新評估替代品；
真正需要設計決策的是「FMP 自己在這些目錄底下的檔案配置規則」（例如下載
檔案要放 Documents 還是 Application Support，這牽涉使用者能否直接在
系統檔案總管看到），這屬於設計文件（design.md）的範疇，不是套件選型
問題。

---

## 11. 應用內更新（per-platform）

| 平台 | 可行機制 | 備註 |
|---|---|---|
| Android | 下載 APK 後導向系統安裝流程（`REQUEST_INSTALL_PACKAGES` 權限） | 現況（audit 已載明），非 Play Store 上架前提下唯一路徑。 |
| Windows | Installer（如 Inno Setup/MSIX）或 portable 版本直接覆蓋執行檔 | 需要應用自己下載新版並觸發安裝程式，或提示使用者手動更新；沒有作業系統層級的強制簽章要求，但未簽章的 installer 會被 SmartScreen 攔一次性警告。 |
| Linux | AppImage 可用 `AppImageUpdate`／`zsync` 做差量自我更新；Flatpak／deb **不建議**做應用內自我更新 | 見 `platform-policy-and-peers.md` §Linux 打包格式自我更新可行性，附官方來源。 |
| macOS | `auto_updater`（Flutter 套件）包裝 Sparkle 框架 | 需要產生 EdDSA 金鑰、架設 `appcast.xml`，且應用本身仍建議走 Developer ID 簽章 + notarization（否則 Gatekeeper 會擋，見政策文件）。 |
| iOS | **不可能**：App Store 是唯一分發管道時完全走蘋果審核；側載（AltStore/SideStore）情境下更新機制受限於 7 天重簽或年費開發者帳號，細節見政策文件。 | |

`auto_updater` 套件細節：來源 `https://pub.dev/packages/auto_updater`——
包裝 macOS 的 Sparkle 與 Windows 的 WinSparkle（**因此 `auto_updater`
本身理論上是 Windows + macOS 雙平台**，但 FMP 現況 Windows 端更新機制
未使用它，需要在設計階段決定是否統一到這個套件，或維持 Windows 自己的
installer 流程、只在 macOS 端引入 `auto_updater`）。

**結論**：更新機制天生無法五平台統一，這不是套件選型能解決的限制，而是
各平台分發模式本身的差異（有無審核商店、有無強制簽章）。`auto_updater`
是目前唯一同時覆蓋 macOS + Windows 兩個桌面平台的現成套件，值得在設計
階段評估是否取代 Windows 現有的更新流程以換取程式碼共用。

---

## 12. 網路狀態

| 套件 | 涵蓋平台 |
|---|---|
| `connectivity_plus` | Android / iOS / Windows / macOS / Linux / Web 均支援（federated plugin，官方生態系常見選擇） |

**結論**：五平台都支援，沒有必要比較替代品，直接可用。

---

## 13. 音訊（僅列事實，不做引擎決策）

本節刻意不下「該選哪個音訊引擎」的結論，只列查證到的事實，決策留給
design.md。

| 套件 | 涵蓋平台 | 關鍵事實 |
|---|---|---|
| `just_audio` | Android/iOS/macOS/Web；**不支援 Windows/Linux 原生**（FMP 現況只在 Android 用，audit 已載明） | 官方定位是行動端/Web 優先的播放引擎。 |
| `media_kit` | Android/iOS/macOS/Windows/Linux 全平台（基於 libmpv） | FMP 現況 Windows 端使用（`media_kit` 1.2.6 + `media_kit_libs_windows_audio` 1.0.9）。**`media_kit_libs_*` 系列全部都是 `is:unlisted`**（非只有 macOS 版如此）：本次重新查證 `media_kit_libs_linux`、`media_kit_libs_windows_audio`、`media_kit_libs_macos_audio`、`media_kit_libs_ios_audio` 四個套件的 score API，`tags` 都包含 `is:unlisted`，且都由同一個 `publisher:media-kit.dev` 發布——這是 media-kit.dev 團隊刻意的作法（把「引擎殼」`media_kit` 上架、把「各平台原生函式庫包」故意標成 unlisted 避免使用者誤裝錯平台的包），**不是套件被棄用或有問題的訊號**，audit 文件原本對 macOS 版本的疑慮可以澄清為「四個平台包都是同樣的 unlisted 狀態，行為一致」。唯一例外是 `media_kit_libs_macos_audio` 的 score API 回傳資料明顯比其他三個少很多（只有 `is:unlisted` 與 `publisher` 兩個 tag，没有 `platform:macos`、沒有 grantedPoints），這看起來像是 pub.dev 分析流程對這個特定套件跑失敗，而非套件本身聲明的差異——**用 packages API（非 score API）重新確認**其 `pubspec.flutter.plugin.platforms` 內確實宣告了 `macos`，可視為 pub.dev 網站端資料展示的落差，不影響套件本身可用性判斷。來源：`https://pub.dev/api/packages/media_kit_libs_macos_audio`。 |
| `audioplayers` | Android/iOS/Windows/macOS/Linux/Web 全平台（latest 6.8.1，2026-06-27 發布，likeCount 3445，pub points 150/160，活躍度高） | **README 本身沒有寫背景播放機制**：官方 README 完全沒有提到 Android 前景服務、iOS 背景音訊 session、桌面背景播放行為或媒體通知，只泛泛帶過「並非所有功能都支援所有平台」並指向另一份 Feature Parity Table（該表未在 README 頁面內展開）。**背景播放機制查不到**，需要另外去 GitHub 的 Feature Parity Table 或原始碼確認，不能假設它像 `just_audio`+`audio_service` 那樣有現成的背景播放/通知整合。來源：`https://pub.dev/packages/audioplayers`。 |

**結論（僅陳述事實，非決策）**：`media_kit` 是唯一單一套件涵蓋五平台的
音訊引擎候選；`just_audio` 在 Windows/Linux 端沒有原生實作，必須另外
搭配平台特定方案（FMP 現況正是如此：Android 走 `just_audio`，Windows
走 `media_kit`）；`audioplayers` 雖然套件本身平台覆蓋最廣，但背景播放
這個對音樂播放器至關重要的能力，官方文件沒有給出足夠資訊，需要在
design.md 決策前先補這塊查證，不能只憑「平台 tag 齊全」就假設它能滿足
背景播放需求。

---

## 14. Flutter 官方對平台專屬程式碼的建議

來源：context7 `/flutter/website`（Flutter 官方文件庫）。

### (1) `defaultTargetPlatform` vs `dart:io Platform`

官方架構總覽文件（`architectural-overview.md`）示範的寫法是用
`defaultTargetPlatform`（來自 `package:flutter/foundation.dart`）搭配
`TargetPlatform` enum 做分支，而非 `dart:io` 的 `Platform.isX`：

```dart
if (defaultTargetPlatform == TargetPlatform.android) {
  return AndroidView(...);
} else if (defaultTargetPlatform == TargetPlatform.iOS) {
  return UiKitView(...);
}
return Text('$defaultTargetPlatform is not yet supported by the maps plugin');
```

`defaultTargetPlatform` 的優勢（推測性總結，基於此範例與其在
`package:flutter/foundation.dart` 而非 `dart:io` 的定位）：它在 Web
編譯下也能運作（`dart:io` 的 `Platform` 類別在 Web 上會丟例外，因為
Web 平台沒有 `dart:io`），因此凡是「UI 層／Widget 層」要依平台分支的
程式碼，官方範例都用 `defaultTargetPlatform`；`dart:io Platform.isX`
則保留給「本來就只會在原生平台跑」的邏輯（例如檔案系統操作、
Isolate、Socket 這類 Web 上本來就不存在的能力）。FMP 現況三種判斷風格
並存（`Platform.isWindows` 直接呼叫、`isDesktopPlatform` helper、
`AudioRuntimePlatform` enum，見 audit §0），對照官方建議，UI 層的平台
分支應該收斂到 `defaultTargetPlatform`／`TargetPlatform`，`dart:io`
的 `Platform` 保留給非 UI 層（例如平台通道初始化、原生檔案路徑組裝）。

### (2) 條件匯入（Conditional imports）

官方 Web/Wasm FAQ 文件示範的模式：

```dart
import 'fallback.dart'
  if (dart.library.js) 'legacy_web_interop.dart'
  if (dart.library.js_interop) 'wasm_web_interop.dart';
```

這個機制原本是為 Web/Wasm 而設計（依 `dart.library.*` 是否存在切換
匯入的檔案），但同樣的語法也可以用 `dart.library.io` 之類的條件在
桌面/行動端之間切換實作檔案，是 Dart 語言層級的能力，不依賴任何套件。
來源：`https://github.com/flutter/website/blob/main/sites/docs/src/content/platform-integration/web/faq.md`。

### (3) Platform Channels 與 Pigeon

官方 Platform Channels 總覽文件明確建議：**如果只是要寫「平台專屬的
Dart 程式碼」（不涉及呼叫原生語言 API），用 `defaultTargetPlatform`
即可，不需要 platform channel**；platform channel 機制是保留給
「真的需要呼叫非 Dart 語言（Kotlin/Swift/C++ 等）撰寫的原生 API」的
情境。原文（節錄）：

> "you can also write platform-specific Dart code in your Flutter
> app by inspecting the `defaultTargetPlatform` property."

`Pigeon` 是官方推薦的 platform channel 型別安全替代方案：用 Dart
定義 `@HostApi()` 介面，自動生成雙端型別安全的 binding 程式碼，取代
手寫 `MethodChannel` 字串命名容易出錯的問題。FMP 現況的 MethodChannel
對照表（audit §3.8）如果未來要擴充更多平台端呼叫，`Pigeon` 是官方建議
的路線，比繼續手寫字串常量 channel 名稱更不容易出錯。
來源：
`https://github.com/flutter/website/blob/main/sites/docs/src/content/platform-integration/platform-channels.md`、
Pigeon 範例
`https://github.com/flutter/website/blob/main/examples/platform_integration/pigeon/lib/pigeon_source.dart`。

### (4) Federated Plugins（聯邦式外掛架構）

官方套件開發文件（`developing-packages.md`）說明 federated plugin
的宣告方式：一個「app-facing package」定義共用介面，各平台各自一個
「platform package」透過 `implements` 宣告自己實作了哪個 app-facing
package：

```yaml
flutter:
  plugin:
    implements: hello
    platforms:
      windows:
        pluginClass: HelloPlugin
```

這正是 `audio_service`（app-facing）+ `audio_service_mpris`／
`audio_service_win`（各平台 platform package）這類生態系套件採用的
架構，也是 `path_provider`、`connectivity_plus`、`file_picker` 等
Google 官方套件的標準做法。**設計啟示**：FMP 若要建立自己的「平台層」
抽象（audit §7 問題 #11 提到的整合三種平台判斷風格），federated
plugin 的介面切分方式（一個共用抽象 + 各平台各自的實作套件/模組）是
官方認可、且已被生態系驗證過的架構模式，不需要自己發明一套新的分層
方式。
來源：
`https://github.com/flutter/website/blob/main/sites/docs/src/content/packages-and-plugins/developing-packages.md`。

---

## 待補查項（誠實列出，非本次時間內完成）

- `audioplayers` 的 Feature Parity Table（GitHub 上，非 pub.dev README）
  未實際打開比對背景播放逐平台細節——**查不到**（本次只查了 pub.dev
  README 頁面本身）。
- `desktop_webview_window` 是否能透過原始碼裡未在 README 曝光的 API
  讀取 cookie——**查不到**，需要另外開 repo 讀 `lib/` 原始碼確認。
- `audio_service_win` 是否支援 seek（相對於 `smtc_windows` 目前的
  已知缺口）——**查不到**，README 未明確比較。
- `launch_at_startup` 套件本身在 Linux 端的底層機制（`.desktop` 檔案
  還是其他方式）未在其 README 找到直接說明——**查不到**，只查了
  `auto_start_flutter` 的對應說明作為參照。
