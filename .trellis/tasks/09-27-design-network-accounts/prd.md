# 設計第 12 項：網路層與帳號

## 目標

設計新 App 的 HTTP 層、憑證存放與刷新、「哪些請求帶憑證」的單一宣告點、「用登入狀態」開關的統一語意，
以及登入作為音源能力的形狀（UI 依音源宣告自適應）。

需求來源：parent `prd.md` 階段二第 2、12 項；`questions.md` M1–M13（使用者：各音源邏輯統一、開關語意一致且可能涵蓋排行、登入由音源提供、介面自適應）、C1、C3、C4、C5、C6（重寫時修正）、B4、B14；ADR 0009（登入 WebView 平台差異）、0010（legacy import）、0011（遮蔽與網路紀錄）。

## 現況（證據）

- UI 顯示的登入狀態讀 Isar `Account`，實際送請求只看 secure storage（`docs/audit/accounts-network.md` §6.1）。
- 請求 × 音源憑證矩陣：開關只影響部分請求；YouTube 的「用登入狀態」只是匿名失敗後的備援；YouTube／網易排行永遠不帶登入（`accounts-network.md` §7）。
- 缺陷：重設資料不清憑證（C1）、B 站 QR 假成功（C3）、B 站刷新後重送帶舊 cookie（C4）、網易非 200 即清憑證（C5）、播放連線偵測不到失效（C6）、secure storage 暫時讀不到就刪憑證（M8）、失效提示每次執行只跳一次（M9）。
- 登入方式：B 站 WebView＋QR；YouTube 只有 WebView（桌面 Chrome UA 開 `accounts.google.com/ServiceLogin`，登入後讀 cookie，`lib/ui/pages/settings/youtube_login_page.dart:60,329-337`）；網易 Android WebView＋QR、Windows 只有 QR。
- Spotify 匯入抓公開 embed 頁（`lib/data/sources/playlist_import/spotify_playlist_source.dart:55-58`），不需登入。

## 研究結論（`research/login-methods.md`、`research/credentials-and-http.md`）

- B 站：成熟客戶端（PiliPlus）以 QR 為主；WBI 與 App 簽名兩套；cookie 刷新流程的社群文件已因存證信函下架，需以實作驗證。
- 網易：QR 或手機驗證碼；社群 API 專案同樣已封存。
- YouTube：Google 封鎖內嵌 WebView 做 **OAuth**（`disallowed_useragent`）。可行替代：系統瀏覽器登入後貼上 cookie／headers（ytmusicapi 官方方式之一，憑證約兩年有效）；TV 裝置碼 OAuth 需自備 Google Cloud 憑證。
  **不一致**：研究以 OAuth 政策推論 WebView 不可用，但舊 App 走的是 `ServiceLogin` 網頁登入加桌面 UA，不是 OAuth；實際是否可用程式碼無法判斷。
- Spotify：**不一致**：研究以 Web API 推論匯入需登入，舊 App 用的是 embed 頁，不受影響（但抓頁面本身可能隨時失效）。
- 憑證：`flutter_secure_storage` 11.2.0，五平台；新 App 寫的是新資料，可直接用 11.x；legacy import 維持 10.x 唯讀（ADR 0010）。Linux 需要 libsecret 與執行中的 keyring，沒有 keyring 時的行為查不到。
- HTTP：每個音源一個共用 dio 實例；`cookie_jar`＋`dio_cookie_manager` 管 cookie；刷新後重送用 `QueuedInterceptor` 並以新憑證重建請求；`dio_smart_retry` 兩年未更新，只適合網路層重試，音源錯誤碼的退避自寫。
- 宣告帶憑證：以請求層標記（`RequestOptions.extra` 帶 `AuthRequirement`：必須／可選／禁止，預設禁止）；媒體位元組請求走另一個不掛認證攔截器的 dio。

## 已決定

- D1（使用者 2026-09-27）：YouTube 登入以 App 內 WebView（桌面 UA 開網頁登入、讀 cookie）為主，另提供「從瀏覽器貼上 cookie」作為備案（被 Google 擋或平台沒有合適 WebView，例如 Linux）。不做 TV 裝置碼 OAuth。舊版 WebView 登入目前是否可用未知，列為第一個加入 YouTube 登入的里程碑先實測的項目。

- D2（使用者 2026-09-27）：開關改為「以登入身分瀏覽與播放」，每音源一個、語意一致，涵蓋該音源所有讀取請求（搜尋、排行、詳情、串流解析、下載詳情、歌單刷新、電台、Mix）；寫入與私人資料一律需登入；媒體位元組請求一律不帶。預設 B 站、網易、YouTube 皆開，YouTube 附帳號風險說明。
- 其餘依研究與使用者方向寫入 design.md。

## 需求

- R1 每音源一個 API client；媒體位元組請求走獨立的媒體 client，不掛認證。
- R2 每個請求在音源插件宣告 `AuthRequirement`（required／userPreference／never，預設 never），認證攔截器只依此注入。
- R3 憑證只存一處（`CredentialStore`），登入狀態由它推導；讀不到不刪。
- R4 登入方式由音源宣告，UI 取音源與平台能力交集；登入成功須先驗證憑證有效。
- R5 憑證無效由音源明確判定，限流／網路／風控不算；刷新後以新憑證重建請求重送；失效時保留憑證、提示、可重新登入且下次失效會再提示。
- R6 登出清該音源憑證與 WebView cookie；重設資料清全部。
- 修正：C1、C3、C4、C5、C6、M1、M5、M6、M7、M8、M9、M12（M12：歌單刷新依開關，不再被重新匯入覆寫）。

## 驗收標準

- [ ] design.md 涵蓋 HTTP 層、帶憑證宣告、憑證存放與狀態、登入方式、刷新與失效、開關語意、只匯入的來源。
- [ ] `docs/adr/0012-*.md` 依範本寫成。
- [ ] `phase2-plan.md` 標記第 12 項完成並記下 YouTube WebView 實測項目。
