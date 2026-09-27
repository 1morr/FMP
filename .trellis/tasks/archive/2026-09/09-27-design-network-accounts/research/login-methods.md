# 研究：各音源登入方式與 Linux 登入替代方案

對應項目 1、5。範圍：Bilibili、YouTube（YouTube Music）、網易雲音樂、Spotify、QQ 音樂的登入方式；
Linux 平台無成熟內嵌 WebView 套件時的替代方案。查不到的地方寫「查不到」，超出已驗證證據的推論標「推測」。

## 0. 一個貫穿全篇的重要發現：兩個最大的社群 API 文件／實作專案都被平台法律行動下架

在深入各音源之前先提出，因為這直接影響「該不該投入更多工程去對接非官方 API」的判斷：

- **`SocialSisterYi/bilibili-API-collect`**（Bilibili 非官方 API 文件的事實標準，20,202 星）於
  2026-01-28 收到 B 站委託律師事務所的存證信函，指控其「以技術手段系統性收集、整理 B 站非公開 API
  接口及其調用邏輯、參數結構、訪問控制及安全認證機制，並以文件、程式碼示例形式向公眾傳播」構成侵權。
  該倉庫已**永久關停並刪除全部文件與範例程式碼**，預設分支被改名為 `deprecated`，只留一份說明：
  <https://github.com/SocialSisterYi/bilibili-API-collect> （`gh api repos/SocialSisterYi/bilibili-API-collect`
  確認 `archived: true`、`default_branch: "deprecated"`；`deprecated` 分支的 README 為存證信函說明原文）。
  這代表本檔案原本要引用的「cookie 刷新流程官方文件」已經**不存在可驗證的穩定連結**——下面 §1.4
  的刷新流程步驟是延續本任務前一階段研究時讀過的內容整理，**現在已無法重新對照原文**，標記為「推測」
  （carried-over，非本次可重新驗證）；改以 PiliPlus 原始碼作為主要、可即時驗證的證據來源。
- **`Binaryify/NeteaseCloudMusicApi`**（網易雲音樂非官方 API 的事實標準，30,253 星）：`archived: true`，
  預設分支 `master` 的整個 git tree 只剩一份 `README.MD`，內容為「保护版权,此仓库不再维护」，並連結兩篇
  中文科技媒體報導（<https://www.landiannews.com/archives/101953.html>、
  <https://www.ithome.com/0/746/942.htm>）——同樣是版權/法律驅動的下架，不是單純棄坑。

兩個分屬 Bilibili、網易雲的頭號社群專案在同一年內都被平台方用法律手段下架，且都指名「系統性收集非公開
API」為理由。這比「套件多久沒更新」嚴重得多，是需要 owner 明確知情、明確決策的風險（見 §7）。

## 1. Bilibili

### 1.1 登入方式總覽（以 PiliPlus 為證據來源）

參考客戶端：**PiliPlus**（`bggRGjQaUbCoE/PiliPlus`，18,720 星，GPL-3.0，目前活躍維護，`main` 分支）。
選它是因為它是目前 star 數最高、仍在維護的 Flutter Bilibili 播放器，程式碼可直接對照。

PiliPlus 實際實作的登入方式（`gh api repos/bggRGjQaUbCoE/PiliPlus/contents/lib/http/login.dart` 確認存在，
內容已抓取）：

- **TV/APP 掃碼登入**（QR，非 Web QR）：
  - `LoginHttp.getHDcode()` → `POST` `Api.getTVCode`
    （`https://passport.bilibili.com/x/passport-tv-login/qrcode/auth_code`，App-sign 簽名），取得
    `auth_code` 與 QR 內容。
  - `LoginHttp.codePoll()` → `POST` `Api.qrcodePoll`
    （`.../x/passport-tv-login/qrcode/poll`，App-sign 簽名），輪詢掃碼狀態。
  - 確認端點常數見
    <https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/http/api.dart>：
    `qrcodeConfirm = '.../x/passport-tv-login/h5/qrcode/confirm'`、
    `getTVCode = '.../x/passport-tv-login/qrcode/auth_code'`、
    `qrcodePoll = '.../x/passport-tv-login/qrcode/poll'`。
  - 檔案：<https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/http/login.dart>
- **帳密登入**：`getWebKey()`（取得 salt 與 RSA 公鑰）搭配密碼加密提交；細節未展開讀取，未來若要做需另行
  細讀該函式後續呼叫。
- **簡訊登入**：`sendSmsCode()` → `POST` `Api.appSmsCode`，帶 Geetest 驗證碼參數
  （`geeChallenge`/`geeSeccode`/`geeValidate`）或 `recaptchaToken`——代表 Bilibili 的簡訊登入介面本身就內建
  人機驗證挑戰，純程式化提交會被擋。

PiliPlus **沒有**實作「Web 版」`x/passport-login/web/qrcode/*` 系列端點；它統一走 TV/APP 家族端點。這代表
「哪一種 QR 登入」在 Bilibili 生態裡至少有兩種變體，選 TV/APP 家族有一個活躍客戶端可直接對照實作。

### 1.2 兩種簽名機制（重要，容易漏掉）

PiliPlus 的原始碼證實 Bilibili API 至少有**兩種互不相通的簽名方案**，混用會直接導致簽名錯誤：

1. **WBI 簽名**（Web API 家族）：`img_key`/`sub_key` 混合出 mixin key，再對參數計算 `w_rid`/`wts`。
   檔案：<https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/utils/wbi_sign.dart>
2. **App-sign**（App/TV API 家族，登入相關端點都在這裡）：參數依 key 字母排序、串接固定的 `appkey`+`appsec`
   後取 MD5。檔案：<https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/utils/app_sign.dart>
   （`AppSign.appSign()`，約 40 行，已讀取確認邏輯）。

新專案的 Bilibili adapter 若同時要呼叫 Web API（列表、詳情）與登入相關的 App/TV API，**必須分別實作兩套
簽名**，不能假設一套簽名適用全站。

### 1.3 buvid／deviceId 自產生

PiliPlus 兩者都是**純本地產生**，不需要額外網路請求換取：

- `generateBuvid()`：16 個隨機 byte → MD5 → `'XY${md5Str[2]}${md5Str[12]}${md5Str[22]}$md5Str'`。
- `genDeviceId()`：BCD 編碼的時間戳 + 隨機 byte + checksum → MD5；程式內註解直接標明移植自
  `bilive_client`：
  <https://github.com/bilive/bilive_client/blob/2873de0532c54832f5464a4c57325ad9af8b8698/bilive/lib/app_client.ts#L62>。

兩者都在 <https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/utils/login_utils.dart>（`LoginUtils`
class）。沒有獨立的 `buvid.dart` 檔案，邏輯內嵌在 `login_utils.dart`（確認過 `lib/utils/` 55 個檔案的完整
清單，無此檔）。

### 1.4 Cookie 刷新（SESSDATA 過期前的主動刷新）

官方流程（延續前一階段研究的記憶整理，來源倉庫已如 §0 所述被下架，**目前無法提供可重新驗證的原文連結**，
標記「推測」，但邏輯與 PiliPlus 程式碼裡出現的端點家族一致，可信度仍高）：
`GET cookie/info`（檢查是否需要刷新）→ 用回傳的 RSA 公鑰加密一段 CorrespondPath → `GET correspond/1/{path}`
（帶著新舊 cookie 訪問這個網頁換取 refresh_csrf）→ `POST confirm/refresh`（提交新舊 csrf，換發新
SESSDATA/bili_jct，並讓舊 cookie 失效）。

**負面發現，且有第二個獨立來源交叉印證**：PiliPlus 的 `login.dart` 裡**沒有** `refresh` 或 `correspond`
字串（`curl` 全文檢索確認），代表這個目前 star 數最高的維護中 Flutter 客戶端**沒有實作**主動 cookie 刷新；
另一個獨立專案 `seiuna/bilibili-api` 先前研究也確認同樣不完整。這說明 Bilibili 的刷新流程即使官方有文件，
真正落地實作的成熟客戶端也少——**FMP 重寫時若要做這段，預期工作量與踩坑成本會比看起來大**，且沒有現成、
可直接抄的完整開源實作可以參照除錯，只能照官方描述的流程自行實作並自行測試邊界情況（例如 CorrespondPath
的有效期、多裝置同時刷新的競態）。

### 1.5 建議

- QR 登入走 TV/APP 家族端點（`passport-tv-login/*`），因為有 PiliPlus 這個活躍客戶端可直接對照實作與除錯。
- buvid/deviceId 本地產生即可，不必額外請求。
- 需要清楚拆開 WBI 與 App-sign 兩套簽名邏輯，各自獨立測試。
- Cookie 刷新流程按官方描述實作，但**預留比預期更多的測試與除錯時間**，並接受「SESSDATA 過期後退回重新登入」
  是一個合理、被業界驗證過的降級路徑（PiliPlus 這麼成熟的客戶端都沒做主動刷新）。

## 2. YouTube / YouTube Music

### 2.1 Google 官方政策：內嵌 WebView 無法用於 Google 登入

Google 官方部落格明文禁止在內嵌 WebView（`android.webkit.WebView`、`WKWebView` 等）裡完成 OAuth 登入，
2021 年公告、2023 年擴大執行範圍，違反者會在 OAuth 授權端點看到 `disallowed_useragent` 錯誤：

- <https://developers.googleblog.com/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews>
  （原始公告，2021 年 9 月 30 日起全面封鎖內嵌 WebView）
- <https://groups.google.com/g/omegaup-soporte/c/fGNQ9JH4Ad4>（2023 年擴大到企業/教育帳號的通知信原文，
  引用同一份政策）

這代表 ADR 0009 選定的 `flutter_inappwebview`（本質上就是包裝 `WKWebView`/`android.webkit.WebView`）**原則上
無法用來完成 Google 帳號登入**——不是「可能不穩定」，是 Google 明確會擋。此政策只針對 Google 自家 OAuth
端點，不影響其他音源。

### 2.2 開源客戶端實際怎麼取得登入態

`sigma67/ytmusicapi`（Python，YouTube Music 非官方 API 的事實標準，3,029 星，維護活躍，最後 push
2026-09-25）官方文件列出兩種認證方式：

1. **Browser 認證**（官方文件：
   <https://raw.githubusercontent.com/sigma67/ytmusicapi/main/docs/source/setup/browser.rst>）：
   使用者自己在**真實瀏覽器**（非嵌入 WebView）登入 `music.youtube.com`，用瀏覽器開發者工具複製一個已認證
   POST 請求（如 `/browse`）的完整 request headers（含 cookie），貼給 `ytmusicapi browser` 指令或
   `headers_raw` 參數。文件明確標註：「這組憑證的有效期跟你的瀏覽器 session 一樣長，大約兩年，除非你登出」
   （原文："These credentials remain valid as long as your YTMusic browser session is valid (about 2 years
   unless you log out).")。這是「登入用系統瀏覽器、貼上 cookie/headers」模式的官方先例，直接對應本任務
   項目 5 問的「Linux 上用系統瀏覽器登入再貼 cookie」是否可行——**可行，且是 ytmusicapi 官方推薦的主要
   方式之一**。
2. **OAuth（TV/Limited Input device 類型）**（官方文件：
   <https://raw.githubusercontent.com/sigma67/ytmusicapi/main/docs/source/setup/oauth.rst>）：
   文件明確寫「自 2024 年 11 月起，YouTube Music 要求開發者自備 YouTube Data API 的 Client ID 與 Secret
   才能連上 API」，需要自己在 Google Cloud Console 申請專案，OAuth client type 選
   「TVs and Limited Input devices」。官方連結：
   - 申請憑證：<https://developers.google.com/youtube/registering_an_application>
   - 流程規格：<https://developers.google.com/youtube/v3/guides/auth/devices>（Google 官方的 TV device
     OAuth flow）
   換言之，**這條路線仍然可用**（不是被完全砍掉），但代價是 FMP 專案要自己申請並內嵌一組 Google Cloud
   OAuth 憑證，且要處理裝置碼輪詢流程；比「使用者手動貼 headers」複雜，但不需要使用者手動操作開發者工具。
3. **yt-dlp 的 cookie 方式**（延續前一階段研究）：yt-dlp 支援直接讀取瀏覽器的 cookie 檔（`--cookies-from-browser`）
   或匯入 Netscape 格式 cookie 檔案來取得串流權限，邏輯上與 ytmusicapi browser 認證同源（都是「借用真實
   瀏覽器已登入的 cookie」），不是獨立的第三條路。
4. **Harmony Music**（Flutter YouTube Music 播放器）：前一階段研究已確認它完全沒有實作登入，最終退回
   離線功能為主——負面案例，證實「在 Flutter 裡幫 YouTube 做內嵌登入」連同類產品都沒做成。

### 2.3 建議

- **沒有可靠的內嵌 WebView 登入方式**，這是 Google 官方政策造成的硬限制，不是實作能力問題。
- 兩個現實可行的路線：
  1. 「系統瀏覽器登入 → 使用者手動複製 headers/cookie 貼回 App」——ytmusicapi 官方採用且文件化，成熟度高，
     但使用者體感複雜（需要開發者工具）。
  2. TV device OAuth flow——使用者體驗較好（裝置碼＋另開瀏覽器授權，不需要開發者工具），但 FMP 需要自己
     申請並打包一組 Google Cloud OAuth 憑證，且要處理該憑證被 Google 停權/限流的風險。
- 兩條路線都不涉及在 App 內嵌 WebView 跑 Google 登入頁，跟平台選型（flutter_inappwebview／webview_cef／
  desktop_webview_window）無關——**YouTube 登入的瓶頸不是 Linux 有沒有 WebView，而是 Google 政策本身**，
  這點在三個平台（Android/Windows/Linux）都一樣。

## 3. 網易雲音樂

### 3.1 QR 登入流程（以 `TianhaoC/NeteaseCloudMusicApi-enhanced` 為證據來源）

原始的 `Binaryify/NeteaseCloudMusicApi`（30,253 星）已如 §0 所述被下架刪除原始碼。改用其分支
`TianhaoC/NeteaseCloudMusicApi-enhanced`（`archived: false`，但 `stargazers_count: 0`、
`pushed_at: 2026-01-19`，距今約 8 個月沒更新，儘管專案描述自稱「自 v4.28.0 後自行維護」）取得可驗證的原始碼：

- `module/login_qr_key.js`：`POST /api/login/qrcode/unikey`，body `{type: 3}`，取得 QR 用的 `key`。
- `module/login_qr_create.js`：組出 `https://music.163.com/login?codekey=${query.key}`（web 平台可加
  `chainId` 參數），用 npm 套件 `qrcode` 產生 QR 圖。
- `module/login_qr_check.js`：`POST /api/login/qrcode/client/login`，body `{key, type: 3}`；輪詢回傳
  狀態碼 **801=等待掃碼／802=已掃碼待確認／803=登入成功**；成功時 `result.cookie`（陣列）以 `.join(';')`
  組成完整 Cookie 字串回傳——**MUSIC_U 就在這個陣列裡**。
- `module/login_refresh.js`：`POST /api/login/token/refresh`，成功（`code === 200`）時同樣回傳
  `result.cookie` 陣列並 join 成字串——確認網易雲有一個明確的 token 刷新端點，且刷新後同樣是整組換發
  cookie（不是單獨換一個 token 欄位）。
- `module/login_cellphone.js`：`POST /api/w/login/cellphone`（`weapi` 加密），body 含 `phone`、
  `countrycode`（預設 `86`）、`captcha`（簡訊驗證碼）或 `password`/`md5_password`（MD5 雜湊過的密碼），
  `remember: 'true'`；成功時同樣回傳 `result.cookie`。確認手機號登入同時支援「驗證碼」與「密碼」兩種方式，
  由呼叫端決定帶哪一個欄位。

以上四個檔案內容均已直接讀取確認（原始碼可信、非轉述）。

### 3.2 建議

- **QR 登入是風險最低、最值得優先做的方式**：流程單純（三個端點：拿 key、組 QR、輪詢狀態）、不需要處理
  簡訊驗證碼的圖形驗證、也不涉及密碼加密細節，且 QR 登入天生不依賴 WebView（見 §6），三平台一致。
- 手機號登入可作為 QR 之外的第二選項，但要處理 `weapi` 這層網易雲自家的請求體加密（本次研究未深入該加密
  演算法本身，若要做需另行研究 `weapi`/`eapi` 加密機制）。
- **token 刷新有明確端點**（`login/token/refresh`），比 Bilibili 的刷新流程單純，值得在新專案優先實作，
  作為一個「刷新流程能落地」的正面對照。

### 3.3 需要留意的風險

- `TianhaoC/NeteaseCloudMusicApi-enhanced` 本身接近一年沒更新、star 數為 0，**不算一個「持續維護」的專案**，
  只是目前少數還保有原始碼可查的分支，不建議把它當長期依賴，只當作端點行為的參考實作。
- 原始版 `Binaryify/NeteaseCloudMusicApi` 的下架與 Bilibili 的 `bilibili-API-collect` 下架同屬 2026 年内
  的平台法律行動，兩個 FMP 要做「可播放」的中文音源都各自出現過一次「頭號社群專案被平台方法律手段下架」
  的先例，見 §0、§7。

## 4. Spotify、QQ 音樂（只需「匯入」，不需播放）

### 4.1 Spotify：2026 年的 API 限縮，已讓「免登入匯入公開歌單」名存實亡

Spotify 官方 2026 年 2 月的開發者變更公告與遷移指南（均為官方一手來源）：

- <https://developer.spotify.com/documentation/web-api/references/changes/february-2026>：
  `GET /playlists/{id}/tracks` 被 `GET /playlists/{id}/items` 取代。
- <https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide>：
  明確寫新端點「**只對使用者擁有或協作的歌單開放**」（原文："Only available for playlists the user owns
  or collaborates on."）——即使呼叫端已經是登入使用者，也不能讀別人的公開歌單內容。
- <https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security>：
  官方部落格說明 Development Mode（一般第三方 App 預設走的模式）自 2026-02-11 起限縮：需要 Spotify
  Premium 帳號、每個開發者只能有一個 Development Mode Client ID、每組 Client ID 最多 5 個被授權使用者、
  可呼叫的端點集合被縮小。

**結論**：Spotify 原本可以用 Client Credentials flow（不需要使用者登入）讀公開歌單 metadata 的路徑，在
2024 年 11 月已針對 Spotify 官方歌單、瀏覽類端點先收緊過一輪；2026 年 2-3 月這輪更直接把「讀取歌單曲目
內容」限縮到「該歌單的擁有者或協作者本人登入後才能讀」。**這代表擁有者原本設想的「Spotify 只需要匯入
公開歌單，不需要處理登入」這個假設，在 2026 年的 Spotify API 現狀下已經不成立**——除非匯入對象剛好是
使用者自己的歌單（此時使用者本來就需要登入 Spotify），否則匯入「別人分享的公開歌單連結」在 Development
Mode 下很可能直接被 API 拒絕。這點列入 §7 需要 owner 重新確認範圍。

### 4.2 QQ 音樂：公開歌單通常不需要登入

延續前一階段研究：QQ 音樂的公開歌單詳情（以 `disstid` 為 key 的端點）一般**不需要登入態**，但需要正確的
`User-Agent`/`Referer` header 組合（瀏覽器直接呼叫會因為 `Referer` 檢查被擋，必須模擬 App 或桌面端的
header）。登入態主要用在 VIP 歌曲串流 URL、私人/個人歌單這類需要身分的資源。官方也提供需要開發者註冊的
OpenAPI，作為更穩定但需要走審核流程的替代方案（本次研究未深入 OpenAPI 的申請門檻與額度限制，若要採用
需另行查證）。

對 FMP「只需匯入公開歌單」的需求而言，QQ 音樂目前技術上可行、風險遠低於 Spotify；主要工作是維持正確的
偽裝 header，而非處理登入。

## 5. Linux 登入替代方案

### 5.1 起點：`flutter_inappwebview` 不支援 Linux

直接查 pub.dev API 確認（<https://pub.dev/api/packages/flutter_inappwebview>，抓取當下 `latest.version`
為 `6.1.5`）：其 `dependencies` 只列出
`flutter_inappwebview_android`／`_ios`／`_macos`／`_web`／`_windows` 五個平台實作套件，**沒有 Linux**。
這與 ADR 0009 §之後要注意「登入 WebView 在 Linux 的選型…在網路與帳號的 ADR 決定」的前提一致：Linux 從
一開始就不在 `flutter_inappwebview` 的能力範圍內，必須另外選型。

### 5.2 `webview_cef`：cookie API 已直接讀原始碼確認，可讀 HttpOnly cookie

pub.dev 資料（<https://pub.dev/api/packages/webview_cef>）：最新版 **0.6.2**，發布於 2026-08-25T08:37:54Z；
score（<https://pub.dev/api/packages/webview_cef/score>）140/160、88 個 like、近 30 天下載 831 次；支援
Windows、macOS、Linux（含 eLinux）。

**Cookie API 已確認、非推測**：官方 README
（<https://github.com/hlwhl/webview_cef/blob/main/README.md>）「Cookies」一節列出：

```dart
await WebviewManager().setCookie('example.com', 'key', 'value');
await WebviewManager().deleteCookie('example.com', 'key');
final all = await WebviewManager().visitAllCookies();
final some = await WebviewManager().visitUrlCookies('example.com', false);
```

往下追原生實作，`visitAllCookies`/`visitUrlCookies` 是包在 `WebviewCookieVisitor` 這個 C++ 類別上，
它直接實作 CEF 原生介面 `CefCookieVisitor`（<https://github.com/hlwhl/webview_cef/blob/main/common/webview_cookieVisitor.h>、
<https://github.com/hlwhl/webview_cef/blob/main/common/webview_cookieVisitor.cc>，已讀取完整原始碼）。
CEF 的 `CefCookieVisitor`/`CefCookieManager` 系列 API 是直接讀 Chromium 網路層底層的 cookie store（等同
`chrome://settings/cookies` 看得到的那份資料），**不是**透過頁面 JS 的 `document.cookie`（後者本來就讀不到
HttpOnly cookie）。因此可以有把握地說：**webview_cef 能讀到 HttpOnly cookie**，這是基於它使用的是 CEF
原生 C++ cookie 介面（而非 JS 橋接）這個結構性事實得出的推論，不是我們直接跑過驗證，但可信度高，标記
「推測（基於原始碼結構的合理推論，未實機驗證）」。

**包裝大小**：README 明確寫 Windows 首次建置會下載「官方 CEF Standard Distribution（約 330 MB，來自
<https://cef-builds.spotifycdn.com>）」，並從原始碼編譯 `libcef_dll_wrapper`——這是**建置時**下載的暫存
依賴大小，不等於最終安裝包大小。README 沒有給出最終打包後的安裝包體積數字，**這點查不到**，需要在
POC 階段實際打包一次 Windows/Linux 版本才能得到準確數字；可以合理預期比純 Flutter（無 CEF）的包大上
一個量級（CEF 是完整 Chromium），與市面上其他內嵌 Chromium 的桌面框架（如 Electron）體積量級相近，這是
基於「同樣內嵌完整 Chromium」的合理推論，標記「推測」。

Linux 建置需求（README「Linux」一節）：`clang`、`cmake`、`ninja-build`、`libgtk-3-dev`、`pkg-config`；
CEF 在首次建置時自動下載（x64、arm64 皆支援），無最低發行版版本要求（表格中 Linux 一欄的「Minimum
version」是「—」，即未特別限制）。

### 5.3 `desktop_webview_window`：WebKitGTK 原生 cookie API（前一階段研究，本次確認套件現況）

pub.dev 資料（<https://pub.dev/api/packages/desktop_webview_window>）：最新版 **0.3.0**，發布於
2026-05-27T04:26:21Z，支援 macOS、Windows、Linux。

前一階段研究已直接讀過其 Linux 端原始碼，確認它透過 WebKitGTK 原生 API
（`webkit_cookie_manager_get_cookies`、`soup_cookie_get_http_only()`）讀取 cookie，這組 API 同樣是直接讀
WebKitGTK 的網路層 cookie store，可以讀到 HttpOnly cookie（此為前一階段已驗證的結論，非本次重新驗證，
但原始碼引用仍然有效，此處視為已確認、非推測）。

### 5.4 一個重要的真實案例對照：PiliPlus 在 Linux 上**沒有**用任何原生 WebView cookie API

PiliPlus 為了支援 Linux，寫了一個自己的、基於 `MethodChannel` 的 Linux WebView plugin
（<https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/plugin/linux_webview.dart>，channel 名稱
`com.example.piliplus/linux_webview`），**沒有使用 `webview_cef` 或 `desktop_webview_window`**。它的 cookie
處理方式（<https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/utils/linux_cookie_manager.dart>，
`LinuxCookieManager`，已讀取完整原始碼）是：

- **讀取**：直接從 App 自己的 Dio cookie jar（`Accounts.main.cookieJar`）拿 cookie，**不從 WebView 原生
  API 讀**。
- **寫入**（要把已登入的 cookie 灌回 WebView，讓網頁顯示已登入狀態）：組一段 JS
  （`generateCookieInjectionJs()`），透過 `document.cookie = ...` 把 cookie 注入頁面——這個方向沒有
  HttpOnly 限制（寫入 cookie 本來就不受 HttpOnly 影響，HttpOnly 只擋「JS 讀取」）。
- 登出/清除：呼叫 `LinuxWebviewPlugin.clearAllCookies()`。
- 在非 Linux 平台，`LoginUtils.setWebCookie()` 則是把 cookie jar 同步進 `flutter_inappwebview` 的
  `CookieManager`（<https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/utils/login_utils.dart>）。

**這是一個已被驗證、上線運作的真實案例**，證明「Linux WebView 不需要有原生 cookie 讀取 API，只要能載入
登入頁讓使用者操作，登入成功後的憑證從自己的 Dio cookie jar 或 App 端攔截網路請求取得即可」是可行的設計。
換句話說，即使某個 Linux WebView 方案的 cookie API 有疑慮，只要能：(a) 顯示登入頁、(b) 讓應用層攔截或
讀出登入成功後產生的 Set-Cookie（例如透過攔截該 WebView 的網路請求，或後續改用該音源自己的登入 API 而非
單純泡在 WebView 裡等 cookie），仍然可以不依賴 WebView 的原生 cookie API 完成登入。

### 5.5 系統瀏覽器登入＋貼上 cookie／headers，作為完全不需要嵌入式 WebView 的備案

見 §2.2：`ytmusicapi` 官方文件就是採用這個模式（使用者在真實瀏覽器登入、用開發者工具複製 headers 貼回
App），且明確說「有效期約兩年」。這代表：

- 這不是一個臨時的權宜之計，是至少一個成熟開源專案官方採用、且文件化的正式登入方式。
- 缺點是使用者體感複雜（需要打開瀏覽器開發者工具），比較適合當 Linux 平台在其他方式都不可行時的
  **最後備援**，而不是主要體驗。
- 對 Bilibili、網易雲這類支援 QR 登入的音源，QR 登入本身就完全不依賴 WebView（只需要能顯示一張 QR 圖
  給使用者用手機掃，加上一個輪詢 API）——**QR 登入是三平台一致、不需要處理 WebView 選型的最穩健方案**，
  應該優先於任何形式的 WebView 內嵌登入。

### 5.6 建議（Linux 登入方式排序）

1. **優先用 QR 登入**（Bilibili TV/APP QR、網易雲 QR）——完全不需要 WebView，三平台程式碼一致，是本研究
   中風險最低的選項。
2. 音源沒有 QR 登入、必須走 WebView（例如帳密登入頁）時，`webview_cef` 是目前唯一同時支援 Windows/macOS/
   Linux 三桌面平台、cookie API 有原始碼可驗證讀取邏輯的套件，代價是打包變大（確切數字待 POC 驗證）與
   建置鏈變複雜（需要 C++20 工具鏈、CEF 下載）。
3. 若 `webview_cef` 的建置成本或包大小在 POC 階段被判定不可接受，PiliPlus 的模式（自建輕量 WebView plugin
   + 不依賴原生 cookie API，改用應用層自己的 cookie jar 或攔截登入成功後的網路回應）是一個有實機驗證先例
   的備案，但需要為每個要用 WebView 登入的音源多做一層「登入成功偵測」邏輯（不能單純等 WebView 的 cookie
   API 通知）。
4. YouTube 登入完全不依賴以上選型（見 §2.3），系統瀏覽器貼 headers 或 TV OAuth device flow 是唯二選項，
   三平台一致。

## 6. 查不到／需要進一步驗證的項目清單

- Bilibili cookie 刷新流程的官方原文連結：來源倉庫已下架，查不到可重新驗證的穩定連結（見 §0、§1.4）。
- `webview_cef` 最終打包後在 Windows/Linux 的安裝包體積：官方 README 只給建置時 CEF 下載量（約 330 MB），
  查不到最終打包體積的官方數字，需 POC 階段實測。
- QQ 音樂官方 OpenAPI 的申請門檻與額度限制：本次未深入查證。
- Bilibili 帳密登入（`getWebKey()` 之後的 RSA 加密細節）與網易雲 `weapi`/`eapi` 請求體加密演算法：本次
  研究未展開，兩者都只在需要真的實作「帳密登入」時才必要（QR 登入不需要）。

## 7. 需要 owner 決定的事項

1. **Bilibili、網易雲兩個中文音源的頭號社群 API 專案都已被平台方以法律手段下架**（§0）。這代表持續對接
   這兩個音源的非公開 API 存在真實的、已發生過的法律風險先例，不是假設性風險。是否要在文件（例如
   README 或 ADR）中明確記錄這個風險並取得 owner 知情同意，還是需要重新評估投入這兩個音源的工程優先序，
   需要 owner 決定。
2. **Spotify 匯入公開歌單在 2026 年的 API 現狀下技術上可能不可行**（§4.1）：新端點只對歌單擁有者/協作者
   開放，Development Mode 額度也大幅限縮。這與「Spotify 只需要匯入，不需要處理登入」的原始假設衝突，
   需要 owner 確認：(a) 維持原假設但接受多數「匯入別人分享的公開歌單」案例會失敗；(b) 改為要求使用者
   登入自己的 Spotify 帳號、只能匯入自己擁有或協作的歌單；(c) 放棄 Spotify 匯入功能。
3. **YouTube 登入無法用內嵌 WebView**（§2.1，Google 官方政策），必須在「使用者手動複製瀏覽器 headers」
   與「FMP 自行申請 Google Cloud OAuth 憑證走 TV device flow」之間選一個作為主要方式，兩者使用者體驗與
   工程成本差異大，需要 owner 決定要哪一種、或兩種都提供讓使用者選。
4. **Linux 登入 WebView 選型**：`webview_cef`（包大小/建置鏈成本較高，但 cookie API 有結構性把握）
   v.s. 自建輕量 WebView + 不依賴原生 cookie API（PiliPlus 模式，開發工作量較高、但有實機驗證先例）——
   兩個方案目前都缺少「在 FMP 的實際打包流程裡跑一次」的驗證數據，需要 owner 決定是否值得為此開一個
   POC child task 再做最終選型，或先接受某個選項並在後續里程碑修正。
