# 0029 — 登入由插件的匯出完成、憑證以 cookie 表存在 secure storage、失效在插件呼叫層單飛刷新

- 狀態：已採納
- 日期：2026-10-08
- 影響範圍：`app/lib/plugins/accounts/`（`CredentialStore`、帳號服務、單飛刷新）、`app/lib/platform/secure_storage/`、`app/lib/platform/login_webview/`、`app/lib/core/network/` 的認證攔截器、manifest 的 `login` 欄位與 `fmp-plugin.d.ts`、資料表 `accounts`、`source_settings`、帳號頁

## 背景

ADR 0012 定了原則：帶不帶憑證只看 `AuthRequirement`、憑證只存在 `CredentialStore`、登入是音源能力、拿到憑證先驗證才寫入、失效時單飛刷新、每音源一個「以登入身分瀏覽與播放」開關。它沒有定的（`research/m3-scope-digest.md` §8.8、§8.21、§8.23、§8.24）：

- 插件怎麼實作 QR 與驗證，App 內網頁登入的網址、UA、要取哪些 cookie 由誰決定；
- 憑證的形狀、`fmp.credentials.get()` 回什麼、YouTube 需要的 `SAPISIDHASH` 這類從 cookie 算出的 header 誰組；
- 登入後的 Cookie 與插件自己送的匿名 cookie（B 站 `buvid3`）是合併還是覆蓋（M1 待辦：目前 `headers.addAll` 整個蓋掉）；
- 「憑證無效」的判定在插件的 JS 裡，dio 的 `QueuedInterceptor` 看不到；
- 登入 WebView 用哪個套件、平台能力怎麼宣告；帳號表存什麼。

M1 已有 `AuthRequirement`、`decideAuth`、`CredentialSource` 介面與唯一的實作 `NoCredentials`。

## 考慮過的選項

### 登入流程放在哪

- **宿主內建各音源的登入頁**（舊版）：宿主就有音源分支，違反 ADR 0014 §決定 1。否決。
- **插件匯出登入步驟，宿主只提供畫面與 WebView**：宿主沒有音源分支，修登入只要更新插件。採用。

### 單飛刷新的位置

- **dio `QueuedInterceptor`**（ADR 0012 的字面）：判定在插件的 JS 內，dio 層只看到 HTTP 狀態，看不到 B 站的 `code: -101`。否決。
- **插件呼叫層**：插件丟 `CredentialInvalid` 時宿主刷新並重跑整個插件呼叫；重跑時請求自然帶新憑證（等同「以新憑證重建請求」）。採用。

### 登入 WebView 套件

- **`flutter_inappwebview` 6.1.5**（最新 stable，2024-10）：R1 在兩平台登入成功（Android、Windows WebView2）；`CookieManager` 讀得到 HttpOnly cookie、`deleteCookies` 有效。但它的 Android 部分在 `app/` 用的 AGP 9.1.0 建不起來（`proguard-android.txt` 已不支援），要靠 AGP 的暫時退路旗標 `android.r8.proguardAndroidTxt.disallowed=false`；6.1.x 的修正（上游 PR #2897）還沒合併。旗標會隨之後的 AGP 拿掉。否決。
- **`flutter_inappwebview` 6.2.0-beta.3**（2026-02）：維護者的開發線，Android 在 AGP 9.1.0 原樣建得起來，API 與 6.1.5 相容（R1 的探針不改一行就建得起來）。缺點：beta，2024-11 起沒有 stable；R1 的登入實測用的是 6.1.5，beta.3 只建置過。採用：全域規則「沒有可行 stable 時才用 beta」在這裡成立——唯一的 stable 要靠一個會被拿掉的 AGP 旗標才建得起來。
- 兩者的 Windows 部分在 MSVC 14.51 都要 `add_definitions(-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)`（插件用 `<experimental/coroutine>`，STL1011）。
- **`webview_flutter` 4.14.1**：官方維護，但沒有 Windows。否決。
- **`webview_windows` 0.4.0**：只有 Windows，2024-02 後沒有新版。否決。
- **`desktop_webview_window` 0.3.0**：獨立視窗，取 cookie 的能力沒查到。否決。
- **只提供貼上 cookie**：最簡單，體驗較差；是網頁登入失效時的退路（`phase2-plan.md:238`），與網頁登入並存。

### secure storage 套件

- **`flutter_secure_storage` 11.2.0**（ADR 0012 已指定 11.x）：Android 以 RSA-OAEP 包 AES-GCM；Windows 以 AES-GCM 加密檔案、金鑰在 Credential Manager，所以沒有 Credential Manager 單筆約 2.5 KB 的限制。注意它的 Android 預設 `resetOnError: true`（讀取失敗就清空），與 ADR 0012「讀取失敗不刪除」衝突。

## 決定

1. **manifest 的 `login`**：`{methods: ('qr' | 'webView' | 'cookie')[], webView?, refresh?: 'onStartup' | null, browseAsLoggedInDefault?: boolean, automationRisk?: boolean}`。
   - `webView`（methods 含 `webView` 時必填）：`{url, cookieHosts, doneCookies}`——登入頁、取 cookie 的網址、`cookieHosts` 的 cookie 裡齊了就算完成的名稱。宿主開 WebView，沒有任何音源分支。UA 不在 manifest：讓嵌入式 WebView 像一般瀏覽器是平台的事，由平台層決定（決定 9）。
   - `browseAsLoggedInDefault`：「以登入身分瀏覽與播放」的預設（空＝開，ADR 0012 §決定 6）。
   - `automationRisk`：真時開關旁顯示通用說明「以登入身分大量請求可能被視為自動化行為（推測）」（ADR 0012 對 YouTube 的要求，宿主不認得 YouTube）。
2. **匯出**：
   - `loginQrStart() → {qrText, token}`、`loginQrPoll(token) → {status: 'waiting' | 'scanned' | 'expired' | 'done', credentials?}`；
   - `loginVerify(credentials) → {userId, displayName, avatar?}`：宿主在三種方式之後都先呼叫它，通過才寫入（ADR 0012 §決定 4）；
   - `loginRefresh(credentials) → credentials | null`：`null`＝不需要或沒有新的；刷新失敗拋 `CredentialInvalid`。
   - `loginVerify`、`loginRefresh` 呼叫時憑證還沒寫入，由插件以傳進來的憑證自己組 `Cookie`、請求標 `auth: 'never'`；宿主在呼叫前就把這組值登記到遮蔽函式。
   - **`login*` 匯出（`loginQrStart`、`loginQrPoll`、`loginVerify`、`loginRefresh`）執行期間，該插件的 client 不把回應的 `Set-Cookie` 存進 cookie jar**。插件仍讀得到回應 header（QR 的 `done` 就是從那裡取憑證）；登入回應設的 cookie 是憑證，只經 `CredentialStore` 與注入送出（見決定 4）。
3. **憑證的形狀**：`FmpLoginCredentials = {cookies: Record<string, string>, extra?: Record<string, string>}`，`fmp.credentials.get()` 回傳它或 `null`。`CredentialStore` 以 `credentials.<插件 id>` 存它的 JSON；dev 與 prod 以鍵前綴與命名空間分開（ADR 0015 §決定 8）。鍵只用檔名安全的字元：Windows 實作以鍵直接當檔名（`<鍵>.secure`），`:` 不合法。
4. **注入**：認證攔截器只在 `decideAuth` 為 `attach` 時，把憑證的 `cookies` 合併進 `Cookie`，再加上請求的 `authHeaders`（插件從 cookie 算出的 header，例如 `SAPISIDHASH`；名稱一律進遮蔽的 header 名單）。**同名 cookie 以憑證為準**，其次是插件自己送的 header，最後是 cookie jar（舊版也是合併）。`omit`、`refuse` 時 `authHeaders` 整個丟掉。帶不帶憑證仍只由 `auth` 一處決定。
   - **憑證的 cookie 不經 cookie jar**：`dio_cookie_manager` 的 `loadCookies` 把 jar 的 cookie 接在每個請求上、不看 `auth`，憑證若落進 jar，B 站 QR 登入後 `auth: 'never'` 的請求或關掉「以登入身分瀏覽與播放」時仍會帶出 `SESSDATA`，違反 ADR 0012。所以除了決定 2 的「登入時不存」，cookie jar 送出時還要**跳過憑證裡有的 cookie 名稱**，不論這次請求有沒有帶憑證、憑證有沒有失效。
   - **`CredentialSource` 介面不回傳拼好的 `Cookie` 字串**，回傳 cookie 表（名稱對值）與要附加的標頭，另提供憑證裡的 cookie 名稱（已失效時照樣回傳）；合併在網路層做。
5. **`CredentialStore`**：`flutter_secure_storage` 11.2.0，經平台層 `SecureStorage`；Android 一律 `resetOnError: false`。讀取失敗時狀態為「暫時無法讀取」（只在記憶體）、不帶憑證、30 秒後重讀，不刪除。載入、寫入時登記遮蔽（短於遮蔽函式下限的值略過，它們不是秘密），登出、移除時取消。
6. **帳號表與每音源設定**：
   - `accounts(plugin_id 主鍵, user_id, display_name, avatar_json, status: active | invalidated, logged_in_at, last_refresh_at, last_refresh_result)`。是否登入只看 `CredentialStore`；啟動時帳號列與憑證不一致就刪掉多的那一邊。不存 VIP。
   - `source_settings(plugin_id 主鍵, browse_as_logged_in 可空)`：ADR 0011 §決定 7 的每音源設定表。
7. **失效與刷新**：
   - 「憑證無效」的判定表在各插件內（ADR 0013：錯誤在音源內轉換），判定成立時插件拋 `CredentialInvalid`；網路錯誤、限流、風控碼不算。**只在 `HttpResponse.credentialsAttached`（ADR 0028 §決定 2）為真的回應上判定**：宿主說這次沒帶憑證的回應，401、`-101` 只是匿名請求被拒，不能標 `invalidated`。
   - 宿主在插件呼叫層單飛：同一插件同時只有一個刷新；宣告 `refresh` 的插件刷新成功就寫入並**重跑原呼叫一次**；不支援刷新、回 `null` 或刷新失敗就標 `invalidated`：保留憑證、停止帶它、提示一次附「登入」（ADR 0012 §決定 5、ADR 0013 的呈現表）。
   - 啟動刷新：宣告 `refresh: 'onStartup'` 的插件，在第一幀之後、網路狀態第一次是 `Online` 時呼叫一次 `loginRefresh`（ADR 0016「離線中不發背景請求」）。不做全面的帳號驗證。
8. **登入方式**：UI 顯示「`methods` ∩ 平台有能力」。`qr`、`cookie` 不需要平台能力；`webView` 需要平台層宣告 `loginWebView`。官方插件：B 站與網易 `qr`；YouTube `webView` 與 `cookie`。
9. **App 內網頁登入**（R1 通過，Android 與 Windows；實測見 `.trellis/tasks/10-08-m3-sources-accounts-devtools/research/r1-youtube-login.md`）：
   - `flutter_inappwebview` 6.2.0-beta.3（釘死），平台層 `lib/platform/login_webview/` 實作，Android 與 Windows 宣告 `loginWebView`。`app/windows/CMakeLists.txt` 加上面的 STL1011 define。
   - **UA 由平台層決定**：Android 用系統 WebView 的 UA 拿掉 `; wv`（R1：桌面 Chrome UA 會被 Google 擋在 `/v3/signin/rejected`）；Windows 不設，用 WebView2 預設（R1：預設與桌面 UA 都能登入）。
   - Windows 的 WebView2 使用者資料放在 App 資料目錄下，dev 與 prod 分開、「重設資料」能整個刪。
   - **完成以 cookie 判定，不以網址判定**：每次 `onLoadStop` 讀 `cookieHosts` 的 cookie，`doneCookies` 齊了就交 `loginVerify`。只看 `cookieHosts` 網域的 cookie：Google 帳號的同名 cookie 在 `.google.com`，`SetSID` 之前就出現。登入後的落點也不固定（Android 會先插入 `gds.google.com` 的提示頁，最後到 `m.youtube.com`）。
   - **跳轉卡住**：R1 在 Windows 看到登入後停在 `SetSID`（或程序消失），重開 App 後再開登入頁就完成。登入頁在 `url` 的網域已有 cookie、`cookieHosts` 一段時間仍沒齊時，提示「登入沒有完成」與重試；重試重建 WebView 環境再開登入頁。
10. **貼上 cookie**：接受 `name=value; …` 與 Netscape `cookies.txt` 兩種格式，解析成 `cookies` 表再 `loginVerify`；輸入內容不進 log 與錯誤報告。
11. **登出**：清該插件的憑證、帳號列、遮蔽登記、記憶體 cookie jar、WebView 中 `cookieHosts` 與 `url` 網址讀得到的 cookie（逐一以名稱、domain、path 刪除）；`source_settings` 保留。移除插件與重設資料的範圍見 ADR 0030 與 ADR 0025。

採用的慣例：ytmusicapi 的瀏覽器 cookie 與 `SAPISIDHASH`；PiliPlus 的 QR 輪詢；Finamp 的已知值遮蔽（ADR 0011）；舊版 `youtube_login_page.dart` 的登入網址與必要 cookie（`SAPISID`、`__Secure-1PSID`、`__Secure-3PSID`）。

## 後果

- 好的：登入流程隨插件更新；宿主沒有音源分支；匿名 cookie 不再被登入憑證蓋掉；憑證讀取失敗不會遺失；失效只提示一次並有刷新。
- 壞的：每個插件要自己寫帳號資訊驗證、憑證無效判定表與刷新（B 站要純 JS 的 RSA-OAEP）；`loginVerify` 期間插件要自己組 `Cookie`；`login*` 執行期間同一個 client 上其他請求的 `Set-Cookie` 也不存（登入期間插件只做登入，可接受）；重跑整個插件呼叫比重送單一請求多花一點時間。
- 之後要注意：
  - YouTube 的網頁登入可能隨 Google 的政策失效，屆時只剩貼上 cookie（manifest 拿掉 `webView` 即可，不必發 App）；
  - `flutter_inappwebview` 6.2.0 出 stable 就換到 stable；上游修好 STL1011 就拿掉 Windows 的 define；
  - Windows 登入後跳轉卡住的原因沒查到（R1 重現不出來），之後的實測要盯著；
  - Linux 沒有 WebView 與 keyring 時的行為在 Linux 平台任務決定（ADR 0012 §決定 8）；
  - 舊憑證的匯入在 M5，轉成本 ADR 的形狀。

## 如何確認

- `auth_test.dart`：`AuthRequirement` 三種 × 未登入／已登入且開關開／已登入且開關關（以假 `CredentialStore`）；`authHeaders` 只在 attach 時出現；已失效時不帶。
- 認證與 cookie 攔截器的測試：同名 cookie 三方來源的合併結果；cookie jar 送出時不含憑證名稱的 cookie（attach、omit、已失效三種）；`auth: 'never'` 的請求在登入後不帶憑證 cookie；`login*` 執行期間 jar 不存回應的 cookie、結束後一般回應照常存；`credentialsAttached` 只在帶了憑證時為真。
- `credential_store_test.dart`：讀取失敗不刪、稍後重讀；啟動對齊；遮蔽登記（假 cookie 值不出現在 log、網路紀錄）；平台層的 `resetOnError: false` 以 `platform_test.dart` 斷言。
- `account_service_test.dart`：`loginVerify` 拋錯時什麼都不寫；QR 的輪詢在離開畫面後停止（沒有待執行的計時器）。
- 單飛刷新：刷新後重跑的請求帶新憑證；三個並行的呼叫只刷新一次；不支援刷新時標失效且只提示一次；限流與網路錯誤不標失效（ADR 0012 §如何確認）。
- 三個官方插件的「憑證無效」判定表以手寫的錯誤 fixture 走契約測試（`credentialsAttached` 為真才判定，為假的同樣回應不判定）。
- 登出、移除插件、重設資料後 `CredentialStore` 為空，之後的請求不帶憑證。
- 網頁登入：只有 `cookieHosts` 的 cookie 能讓 `doneCookies` 成立（其他網域的同名 cookie 不算）；Android 的 UA 轉換拿掉 `; wv`、其餘不動；`loginWebView` 為假的平台不出現「網頁登入」；登出以假 `LoginWebView` 斷言清除的網址。
- 實機（ADR 0027，真實）：每個音源登入一次、帶憑證的搜尋、登出；YouTube 的網頁登入（或貼上 cookie）是 M3a 驗收的 §8 項目。
