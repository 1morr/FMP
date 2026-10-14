# R1：YouTube App 內網頁登入實測

- 日期：2026-10-08
- 執行：主對話；擁有者用自己另開的 Google 測試帳號，自己輸入帳號密碼（代理不操作輸入框）。
- 計畫：`implement.md` § R1。探針是 `app/` 外的暫時 Flutter 專案（session 暫存目錄，已刪）。
- 只記 cookie 名稱、domain、HttpOnly、值的長度；不記值、帳號名稱、email。

## 版本

| 項目 | 版本 |
|---|---|
| Flutter | 3.47.5（Dart 3.13.4），與 `app/` 相同 |
| `flutter_inappwebview` | 6.1.5（最新 stable，2024-10-08）；平台套件 `_android` 1.1.3、`_windows` 0.6.0、`_platform_interface` 1.3.0+1 |
| Windows WebView2 | 154.0.4258.62（`WebViewEnvironment.getAvailableVersion()`） |
| Android 模擬器 | `Medium_Phone`，API 37；`com.google.android.webview` 153.0.8010.36（`dumpsys webviewupdate`） |
| 桌面 UA 的 Chrome 主版號 | 156（Chrome version history API，當天 Windows stable 156.0.8078.12） |

## 建置

| 平台 | 6.1.5 原樣 | 繞法 |
|---|---|---|
| Android，AGP 9.1.0／Gradle 9.3.1／Kotlin 2.4.0（`app/` 現用） | **失敗**：`getDefaultProguardFile('proguard-android.txt')` is no longer supported（`flutter_inappwebview_android-1.1.3/android/build.gradle:44`） | `android/gradle.properties` 加 `android.r8.proguardAndroidTxt.disallowed=false`（AGP 9.0 release notes 的官方暫時退路）：debug 與 release APK 都建得起來。降到 AGP 8.13.0／Gradle 8.14.3 也行，但 Flutter 警告即將不支援 |
| Windows，MSVC 14.51（Visual Studio 2026） | **失敗**：`C2338 STL1011`（插件用 `<experimental/coroutine>`） | `windows/CMakeLists.txt` 加 `add_definitions(-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)` |
| Windows，專案路徑超過 260 字元 | `FTK1011` | 只發生在探針的長暫存路徑；`app/` 的路徑短，不受影響 |

上游狀態（2026-10-08）：

- `6.2.0-beta.3`（2026-02-04，`_android` 1.2.0-beta.3、`_windows` 0.7.0-beta.3）改用 `proguard-android-optimize.txt`，Android 在 AGP 9.1.0 原樣建得起來；Windows 的 STL1011 **沒修**，一樣要上面的 define。探針的程式碼不必改（API 相容）。
- 6.1.5 分支的修正 PR [#2897](https://github.com/pichillilorenzo/flutter_inappwebview/pull/2897)（2026-09-24）還開著；AGP 9 的 issue #2765 已在 master 關閉。
- 從 6.2.0-beta 退回 6.1.5 時，lockfile 會留著 `_platform_interface` 1.4.0-beta.3 而建置失敗；退回要連 `pubspec.lock` 一起還原，或 `flutter pub upgrade flutter_inappwebview`。

## 登入結果

登入頁：`https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/`（舊版的網址）。驗證請求：innertube `account/account_menu`，Cookie＋`SAPISIDHASH`，每次一個請求。

| 平台 × UA | 登入 | youtube.com 的 cookie | 驗證請求 | 阻擋與備註 |
|---|---|---|---|---|
| Windows × 預設（`userAgent` 不設） | 可以（3 次全新登入） | 19 個；必要三個齊、`__Secure-3PAPISID`、`LOGIN_INFO`、`SID` 在 | 200，有帳號區塊 | 3 次裡 2 次在跳回 YouTube 時出事（見下） |
| Windows × 桌面 Chrome 156 | 可以（1 次） | 19 個，同上 | 200，有帳號區塊 | 無 |
| Android × 桌面 Chrome 156 | **不行** | — | — | 輸入帳號後跳 `/v3/signin/rejected`：「This browser or app may not be secure」 |
| Android × 行動（系統 UA 拿掉 `; wv`，保留 `Version/4.0`） | 可以（1 次） | 21 個；必要三個齊、`__Secure-3PAPISID`、`SID` 在，`LOGIN_INFO` 不在 | 200，有帳號區塊 | 登入後 Google 插入 `gds.google.com/web/landing`、`recoveryoptions`、`homeaddress` 等設定提示頁，跳過後到 `m.youtube.com` |

沒有遇到 captcha 或「改用瀏覽器」以外的阻擋；兩步驟驗證依測試帳號的設定，本次沒有出現。

**清除**（`deleteCookies` youtube.com／accounts.google.com／www.google.com 加 `.youtube.com`、`.google.com` 的 domain 變體，再 `deleteAllCookies`）：兩平台都有效，兩個網域的 cookie 都是 0，再載入登入頁回到輸入帳號；Android 的頁面重新整理成未登入。

**Cookie 讀取**：兩平台的 `CookieManager.getCookies` 都讀得到 HttpOnly 的 cookie（`__Secure-1PSID`、`__Secure-3PSID` 等）。以 `https://www.youtube.com` 查只回 `.youtube.com` 的 cookie；Google 帳號的同名 cookie 在 `.google.com`，比 youtube.com 早出現（`CheckCookie` 時就有）。

### Windows 跳轉時的偶發失敗（未解）

- 第 1 次全新登入：經 `SetSID` 開始載入 `www.youtube.com` 時，探針視窗自己消失（`flutter run` 報 Lost connection；Windows 事件記錄與 CrashDumps 沒有記錄）。
- 同一程序內 Clear 後重新登入：停在 `accounts.youtube.com/accounts/SetSID`，頁面不再前進。此時 google.com 已有 24 個 cookie、youtube.com 是 0 個。在同一程序內重建 `InAppWebView`（換 key 再 Load）也一樣卡住、畫面空白。
- 關掉程序重開後再 Load：經 `SetSID` 進到 YouTube，cookie 齊全（登入狀態在 WebView2 的使用者資料目錄裡留著）。
- 之後同一程序內 Clear 後重新登入兩次（桌面 UA、預設 UA）都正常，沒能重現。加的「重建 `WebViewEnvironment`」沒有機會測。
- Windows 0.6.0 沒有 render process gone 之類的事件可以接（只有 load、history、progress、console、createWindow 等）。

## 結論：通過

兩平台都至少有一個 UA 能登入、取到必要的三個 cookie、驗證請求回到帳號區塊、清除有效（`implement.md` § R1 的通過定義）。`loginWebView` 在 Android 與 Windows 都宣告。

ADR 0029 與 design §6.4 要定的值：

- **`url`**：`https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/`。
- **UA 不能是單一固定字串**：Android 只有「系統 UA 拿掉 `; wv`」能過，桌面 UA 被擋；Windows 用 WebView2 預設就能過。這是「嵌入式 WebView 要像一般瀏覽器」的平台事，與音源無關，改成宿主的平台層負責（Android 拿掉 `; wv`、Windows 不設），manifest 拿掉 `userAgent` 欄位（2026-10-08 擁有者決定）。
- **`cookieHosts`**：`https://www.youtube.com`。
- **`doneCookies`**：`SAPISID`、`__Secure-1PSID`、`__Secure-3PSID`，**只以 youtube.com 的 cookie 判定**：google.com 的同名 cookie 在 `SetSID` 之前就出現，用它判定會在 YouTube 還沒拿到登入時關頁。
- **流程不能以網址判定完成**：Android 登入後會插入 `gds.google.com` 的提示頁，最後落在 `m.youtube.com`，不是 `www.youtube.com`；以 cookie 判定就不受影響。
- **清除**：WebView 只給登入用（Windows 有自己的使用者資料目錄），登出時 `deleteAllCookies` 即可，不必列網域。

PR 9 要處理的：

- **套件與建置**：用 6.2.0-beta.3（見下）。兩條路的 Windows 都要 `CMakeLists.txt` 的 STL1011 define。
- **Windows 跳轉卡住**：google.com 已有必要 cookie、youtube.com 一段時間仍沒有時，提示「登入沒有完成，重試」；重試先重建 `WebViewEnvironment` 再開登入頁（未驗證能救），救不回就請使用者重開 App（已驗證：重開後登入狀態還在，再開登入頁就完成）。視窗消失那次沒有記錄可查，PR 9 實測時盯著。

### 套件選擇（2026-10-08 擁有者決定：B，6.2.0-beta.3）

| 方案 | 內容 | 風險 |
|---|---|---|
| A. 6.1.5（stable）＋ AGP 退路旗標 | `app/android/gradle.properties` 加 `android.r8.proguardAndroidTxt.disallowed=false` | 旗標是 AGP 的暫時退路，之後的 AGP 會拿掉；到時要等 #2897 的 6.1.x 或 6.2.0 stable。只建置過，release APK 沒有實跑登入 |
| B. 6.2.0-beta.3 | 不用 Gradle 旗標 | beta，2024-11 起至今沒有 stable；登入只在 6.1.5 實測過，PR 9 的實測第一次驗 beta.3 |

選 B 的理由：6.1.5 那條線 2024-10 後沒有新版、backport PR 沒人合併；AGP 旗標是會被拿掉的暫時退路，選 A 只是把換版往後推；beta.3 與 6.1.5 API 相容，PR 9 的登入出問題時退回 A 只改兩行設定（連 `pubspec.lock` 一起還原）。全域規則「沒有可行 stable 時才用 beta」在這裡成立：唯一的 stable 要靠暫時旗標才建得起來。

## 收尾

- Android：`adb uninstall com.personal.r1.r1_login_probe`（WebView 資料隨之刪除）。
- Windows：探針的 WebView2 使用者資料目錄（含測試帳號的登入 cookie）已刪；探針專案在 session 暫存目錄，session 結束即消失。
- 已請擁有者在 Google 帳號的「安全性 → 你的裝置」登出這兩個工作階段。
