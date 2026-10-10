# 網頁登入與貼上 cookie（M3 PR 9，FMP 端）

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`。技術設計在父任務 `design.md` §6.4（網頁登入、跳轉卡住、貼上 cookie）、§6.6（登出與移除清 WebView cookie）、§14（`flutter_inappwebview` 6.2.0-beta.3）；ADR 0029 §決定 9；R1 研究 `research/r1-youtube-login.md`。執行清單在父任務 `implement.md`「9.」。疊在 PR 8（#228）之上。YouTube 插件的 `login`（`webView`、`cookie`、`loginVerify`、`SAPISIDHASH` 的 `authHeaders`）在 fmp-plugins#4。本檔只列做什麼與驗收。

## 目標

宣告 `webView` 的插件能在 App 內開網頁登入、完成時自動取 cookie；宣告 `cookie` 的插件能貼上 cookie 登入；登出與移除插件會清掉 WebView 裡的對應 cookie。

## 做什麼

1. 平台層 `lib/platform/login_webview/`：`flutter_inappwebview` 6.2.0-beta.3 釘死；介面照 design §6.4（`build`、`cookies`、`clear`、`clearAll`）；Windows 的 `WebViewEnvironment` 使用者資料在資料目錄的 `webview/`；`app/windows/CMakeLists.txt` 加 STL1011 的 define；UA：Android 拿掉 `; wv`（含 `;wv`），Windows 不設；宣告 `PlatformCapabilities.loginWebView`（Android、Windows）。
2. 網頁登入畫面：開 manifest 的 `webView.url`；每次 `onLoadStop` 讀 `cookieHosts` 的 cookie，`doneCookies` 齊了就關頁 → `AccountService.login`；不以網址判定完成；跳轉卡住（`url` 網域已有 cookie、15 秒內 `doneCookies` 沒齊）顯示「登入沒有完成」與「重試」（Windows 重建 `WebViewEnvironment`、Android 重建 WebView），仍不行提示重開 App；取到的 cookie 不進 log。
3. 貼上 cookie 畫面：多行輸入；解析 `name=value; …` 與 Netscape `cookies.txt`（壞行略過）；通用的「如何取得」說明（不指名音源）；輸入內容不進 log、錯誤報告。
4. 帳號區塊的 `availableLoginMethods` 打開 `webView`（依平台能力）與 `cookie`。
5. 登出與移除插件時清 `cookieHosts` 與 `url` 網域的 WebView cookie（PR 7 留的那一步；design §6.6、§7.4 的順序）。
6. 三語言；`app/AGENTS.md`（平台層、帳號）與 spec；`toast_layering_test.dart` 加新的全螢幕路由。

## 不做

- YouTube 插件本身（fmp-plugins#4）；重設資料的 `clearAll` 呼叫點（PR 14）；失效與刷新（PR 10）。

## 驗收

- [ ] cookie 字串與 `cookies.txt` 的解析（含壞行）；輸入內容不出現在 log（假 cookie 掃描）。
- [ ] `loginWebView` 為假的平台不出現「網頁登入」；完成只看 `cookieHosts` 的 cookie（其他網域的同名 cookie 不算）；Android UA 轉換（`; wv`、`;wv`、沒有標記）；卡住提示的計時（fakeAsync）。
- [ ] 登出與移除時 WebView 的清除以假 `LoginWebView` 斷言被呼叫；`platform_test.dart` 的 `loginWebView`。
- [ ] 驗證清單全綠；兩平台建置成功；Android 新增原生庫 `zipalign -c -P 16` 通過。
- [ ] 實機：重播（`fmp-test` 加 `cookie` 方式時）兩平台貼上 cookie 登入、登出；真實（擁有者的 Google 測試帳號、擁有者自己輸入密碼）在擁有者回來後做。
