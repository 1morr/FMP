# 0012 — 網路層與帳號：請求宣告是否帶憑證、憑證只存一處、登入由音源宣告

- 狀態：已採納
- 日期：2026-09-27
- 影響範圍：`app/` 的 HTTP client 與攔截器、憑證存放、帳號狀態、登入 UI、每音源設定表、音源插件的請求定義

## 背景

舊專案的帳號與網路（`docs/audit/accounts-network.md`、`docs/audit/errors.md`）：

- UI 顯示的登入狀態讀 Isar `Account`，實際送請求只看 secure storage，兩者可能不一致；「重設所有資料」不清憑證，重設後請求仍帶舊 cookie。
- 「用登入狀態播放」只影響部分請求，三個音源語意不同（YouTube 只在匿名失敗後才帶；YouTube 與網易的排行永遠不帶）。
- 帶不帶憑證散落在各 service 手動組 header；每個 service 各自一個 dio。
- B 站 QR 登入可能假成功；B 站刷新憑證後用舊 options 重送；網易任何非 200 都當失效並清憑證；播放用的連線偵測不到失效；secure storage 暫時讀不到就刪憑證；失效提示每次執行只跳一次。

舊版 `CONTEXT.md`（階段三刪除，術語移到舊專案的 `.trellis/spec/legacy/services/download-and-auth.md`）記錄的原則經審計驗證仍成立，併入本 ADR：**憑證只用在向音源解析串流與 API 請求，實際抓取音訊位元組的請求一律不帶憑證**。

## 考慮過的選項

- **沿用各 service 自己決定帶不帶憑證**：否決。規則散落，無法一處檢查，是舊版範圍不一致的根源。
- **每個 service 一個 dio**：否決。刷新、cookie、限流無法共用。
- **手動拼 Cookie header**：否決。改用 `cookie_jar`＋`dio_cookie_manager`。
- **YouTube 只用「貼上 cookie」**：否決為唯一方式，保留為備案；App 內網頁登入體驗較好。
- **YouTube TV 裝置碼 OAuth**：否決。需在公開 repo 放 Google Cloud 憑證，有被濫用與撤銷的風險，並受配額限制。
- **採用：請求層宣告＋每音源一個 API client＋獨立媒體 client＋單一憑證存放＋登入方式由音源宣告**，見下。

## 決定

1. **HTTP 層**：每個音源一個 API client（dio），該音源所有 service 共用；攔截器順序為認證注入、cookie 管理、錯誤對應、
   限流與退避（策略由音源宣告）、網路紀錄（ADR 0011）。另有一個**媒體 client** 專抓音訊位元組，只加媒體 headers（Referer、UA），
   不掛認證攔截器與 cookie 管理。匿名用的非機密 cookie（例如 B 站 `buvid`）存資料庫。
   轉址：宿主 HTTP 跟隨轉址時每一跳都要在 manifest 網域內，最多 5 跳（舊版 `SourceUrlPolicy.resolveRedirects` 的做法）；媒體 client 跟隨轉址時每一跳只帶媒體 headers。
   補充（2026-10-08，M3 PR 0）：匿名 cookie 由插件存在自己的 storage（`plugin_storage` 表）；登入後的 Cookie 與插件自己送的同名 cookie 以憑證為準合併；憑證的 cookie 不經 cookie jar（登入時不存、送出時跳過憑證的名稱），所以 `auth: never` 與開關關閉時不帶（ADR 0029）。
2. **帶憑證的單一宣告點**：每個請求在音源插件的定義處宣告 `AuthRequirement`：
   - `required`：寫入遠端歌單、讀收藏夾與私人歌單；未登入就不發請求，直接回「需要登入」。
   - `userPreference`：搜尋、排行、詳情、串流解析、下載詳情、歌單刷新、電台、Mix；已登入且開關開啟才帶。
   - `never`（預設）：公開頁面抓取、第三方歌詞源。
   認證攔截器只依此標記注入。網路紀錄記錄每個請求是否帶了憑證。
3. **憑證存放**：唯一來源 `CredentialStore`（`flutter_secure_storage` 11.x，以音源 id 為鍵），登入狀態由它推導；
   帳號的非機密顯示資訊存資料庫。讀取失敗時狀態為「暫時無法讀取」並稍後重試，**不刪除**。憑證載入或更新時登記到遮蔽函式。
   舊憑證由 legacy import 以 10.x 讀入（ADR 0010）。
4. **登入是音源能力**：音源宣告支援的登入方式（QR、App 內網頁登入、貼上 cookie），UI 顯示「音源支援 ∩ 平台有能力（ADR 0009）」。
   B 站、網易以 QR 為主；YouTube 以 App 內網頁登入（桌面 UA）為主、貼上 cookie 為備案。
   **拿到憑證後先呼叫帳號資訊 API 驗證，通過才寫入**。
5. **刷新與失效**：
   - 刷新由音源宣告是否支援與時機（B 站啟動時詢問是否需要刷新）；帳號頁顯示最後刷新時間與結果。
   - 只有帶了憑證的請求才可能觸發失效；每個音源明確列出哪些回應代表憑證無效，網路錯誤、限流、風控碼不算。
   - 遇到憑證無效：`QueuedInterceptor` 單飛，支援刷新就先刷新、**以新憑證重建請求**後重送一次；否則標記已失效。
   - 已失效：保留憑證、停止帶它、提示一次，帳號頁與相關入口顯示需要重新登入；重新登入後下一次失效會再提示。
   - 登出：清該音源憑證、該音源網域的 WebView cookie、記憶體 cookie、遮蔽登記。重設所有資料：清資料庫、全部憑證、全部 WebView 資料。
   - 補充（2026-10-08，M3 PR 0）：上面「`QueuedInterceptor` 單飛」由 ADR 0029 細化：判定在插件內，單飛刷新與重送做在插件呼叫層，重跑整個插件呼叫。
6. **「以登入身分瀏覽與播放」**：每個音源一個開關（每音源設定表，ADR 0011），控制所有 `userPreference` 請求，三個音源語意一致。
   預設由音源宣告，B 站、網易、YouTube 皆開；YouTube 旁附說明：以登入身分大量請求可能被視為自動化行為（推測）。
   legacy import 以舊開關值作為使用者設定；舊版開關範圍較窄，切換版本的發行說明寫明。
7. **只能匯入的來源**：Spotify（embed 頁）、QQ（公開歌單）不需登入，標為 `never`；抓頁面可能隨改版失效，由音源健康檢查涵蓋。
8. **沒有 WebView 的平台**（例如 Linux）：B 站、網易用 QR，YouTube 用貼上 cookie；是否引入 `webview_cef` 在 Linux child task 決定。

採用的慣例：dio 官方 `QueuedInterceptor`；`cookie_jar`＋`dio_cookie_manager`；PiliPlus 以 QR 為主的 B 站登入；
ytmusicapi 的瀏覽器 cookie 認證；Finamp 的已知值遮蔽（ADR 0011）。

## 後果

- 好的：一處就能看出每個請求帶不帶憑證；憑證不可能送到 CDN；登入狀態只有一個來源；三個音源行為一致；審計列出的 C1、C3、C4、C5、C6、M1、M5–M9、M12 由結構修正。
- 壞的：每個請求定義多一個標記；每個音源要維護「憑證無效」判定表與遮蔽名單；YouTube 的 App 內網頁登入可能被 Google 擋，屆時只能靠貼上 cookie。
- 之後要注意：
  - B 站與網易的社群 API 文件已因法律行動下架，刷新流程等細節需以實作與測試驗證。
  - YouTube App 內網頁登入目前是否可用未知，第一個加入 YouTube 登入的里程碑先實測。
  - Linux 沒有 keyring 時 secure storage 的行為，在 Linux child task 實測。
  - 統一錯誤型別與限流退避策略的細節由錯誤模型的 ADR 定。

## 如何確認

- 契約測試：每個音源的媒體請求經媒體 client 發出後，請求上不含任何 Cookie／Authorization。
- 測試：`AuthRequirement` 三種標記在「未登入／已登入且開關開／已登入且開關關」下的注入結果。
- 測試：刷新後重送的請求帶的是新憑證。
- 測試：每個音源的「憑證無效」判定表；限流與網路錯誤碼不會把帳號標為失效。
- 測試：登出與重設所有資料後，`CredentialStore` 為空且請求不再帶憑證。
