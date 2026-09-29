# 網路層（M1 PR 8）

父任務：`../09-28-m1-skeleton-tracer`（implement「8.」）。

依據：
- ADR 0012 §決定 1–2：API client、攔截器順序、轉址、`AuthRequirement`；
- ADR 0011 §決定 4：網路紀錄；
- ADR 0013 §決定 2、4：傳輸錯誤轉 `NetworkError`、只在網路層重試、併發上限與最小間隔；
- ADR 0015 §決定 5：fixture 錄製與重播接在 dio 最底層的 `HttpClientAdapter`，本 PR 讓它可以替換，PR 9 實作。

## 範圍調整（主對話決定）

**媒體 client 延到 M6。**
- M1 沒有使用者：播放後端自己抓串流網址，下載在 M6。
- M1 需要的是「交給播放後端的 headers 不帶憑證」。本 PR 做成媒體 header 政策，PR 10 使用。
- 理由：ADR 0009 的「不寫空實作」精神。這一條寫進父任務的 design §3。

## 做什麼

所有程式放在 `lib/core/network/`，`Dio(` 只准出現在這裡，`fmp_http_client_owner` 守。

1. **每插件一個 API client**：`SourceHttpClient`（名稱可調），由一個工廠依插件建立。
   - 輸入：
     - 插件 id；
     - 允許的網域清單（manifest，PR 9）；
     - `RetryPolicy`、`RateLimitPolicy`（PR 7）；
     - 認證來源介面：M1 沒有 `CredentialStore`，用「沒有憑證」的實作；
     - log 門面；
     - 可替換的 `HttpClientAdapter`，預設為 dio 的 IO adapter。
   - 攔截器順序照 ADR 0012 §決定 1：認證注入 → cookie 管理 → 錯誤對應 → 限流與退避 → 網路紀錄。實作形式照 dio 官方做法，最後的執行順序要有測試斷言。
2. **網域與轉址**：
   - 請求的 host 必須符合允許清單：與清單項目相同，或是它的子網域（`.` 邊界）；只准 `https`。不符合時不發請求，直接回 `Unsupported`，或一個明確的 AppError 子類。
   - 轉址手動跟隨（`followRedirects: false`），每一跳都檢查網域，最多 5 跳；超過或出網域就失敗。
   - 做法參考舊版 `lib/data/sources/source_url_policy.dart` 的 `resolveRedirects`。
   - 跨網域的轉址不帶原請求的 `Cookie`、`Authorization`。
3. **認證**：
   - `AuthRequirement` enum：`required`、`userPreference`、`never`（預設）。
   - 判斷函式：輸入「是否已登入」「以登入身分瀏覽的開關」、標記，輸出三種結果：帶憑證、不帶、或不發請求並回 `AuthRequired`（`required` 且未登入時）。
   - 認證攔截器只依這個結果注入。M1 的來源一律「未登入」，三種標記在三種狀態下的結果照 ADR 0012 §如何確認寫測試，用假的認證來源。
   - `CredentialStore` 與登入在 M3。
4. **cookie**：`cookie_jar`＋`dio_cookie_manager`，每插件一個記憶體 cookie jar。
   - 匿名 cookie（例如 B 站 `buvid`）要跨重啟保存時，由插件寫進自己的 storage（`plugin_storage`，ADR 0014）；網路層不另建持久化。
   - 這個做法寫進 AGENTS.md。
5. **錯誤對應**：
   - 傳輸層錯誤轉 `NetworkError`：逾時、連線失敗、TLS 失敗、被取消另外處理。
   - HTTP 429，以及帶 `Retry-After` 的 503，轉 `RateLimited`，用 PR 7 的 `parseRetryAfter`。這是 HTTP 通用語意（RFC 6585 §4、RFC 9110 §15.6.4）。
   - 其他狀態碼不在網路層判斷，把回應原樣交給插件，由插件在自己的邊界對應（ADR 0013 §決定 2）。
6. **重試與限流**：
   - 用 PR 7 的 `shouldRetry`、`delayFor` 重試；時鐘與 `Random` 可注入。
   - 每插件的併發上限與最小請求間隔（`RateLimitPolicy`）。
   - 被取消的請求不重試。
7. **網路紀錄**：每個請求一筆摘要，經 log 門面以 `debug` 寫入，失敗時用 `warning`。
   - 欄位：方法、host、path、遮過的 query、狀態、耗時、回應大小、插件 id、錯誤類型、是否帶了憑證、重試次數。
   - 不記 body。
   - 每筆有一個 id；產生的 `AppError` 帶上這個 id（PR 7 的網路紀錄 id 欄位）。
8. **媒體 header 政策**：一個純函數，輸入插件給的串流 headers，只保留 `Referer`、`User-Agent`、`Origin`、`Range`，其餘一律丟掉，特別是 `Cookie` 與 `Authorization`。
   - ADR 0012 §如何確認的「媒體請求不帶 Cookie／Authorization」在 M1 由這個函數與 PR 10 的後端接線守。
9. **PR 7 的待辦**：未捕捉錯誤若是 `AppError`，改走 `log.report`。
10. **測試**：一律用假的 `HttpClientAdapter`，不聯網；零聯網防線照常生效。
    - 攔截器順序；
    - 網域：相同、子網域、`evil-bilibili.com` 不算、`http` 被拒；
    - 轉址：5 跳內成功、第 6 跳失敗、出網域失敗、跨網域不帶 Cookie；
    - `AuthRequirement` 的表；
    - 錯誤對應：逾時轉 `NetworkError`；429 帶秒數與日期的 `Retry-After`；503 有與沒有 `Retry-After`；
    - 重試：只重試冪等請求、次數上限、尊重 `Retry-After`（假時鐘）；
    - 限流：併發上限、最小間隔（假時鐘）；
    - 網路紀錄：欄位完整、query 裡的假憑證被遮、沒有 body、`AppError` 帶上紀錄 id；
    - 媒體 header 政策；
    - 未捕捉的 `AppError` 走 `report`。
11. **文件**：
    - `app/AGENTS.md` 網路段；
    - `.trellis/spec/app/network/index.md`（繁中）；
    - 父任務 design §3 補「媒體 client 延到 M6」一列。

## 驗收

- [ ] `app/`：
  - format 通過；
  - codegen 沒有變動；
  - `dart analyze --fatal-infos`、`flutter analyze` 零問題；
  - `flutter test` 全綠；
  - 哨兵通過。
- [ ] 不是使用者看得到的改動，不需要實機驗證。真實連線在 PR 9 的 B 站插件驗證。
