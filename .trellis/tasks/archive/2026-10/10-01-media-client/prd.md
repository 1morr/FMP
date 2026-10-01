# 媒體 client（M2 PR 3）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §4.1（擁有者決定 1：媒體 client 在 M2 建）；本檔只列做什麼與驗收。

## 目標

每個插件有一個不帶憑證的媒體 client，給 PR 4 的封面磁碟快取（之後 M6 的下載）抓圖片與檔案。它與 `SourceHttpClient` 守同一份網域規則，另外有大小上限與逾時。

## 做什麼

1. `lib/core/network/media_http_client.dart`：`MediaHttpClientFactory.create(pluginId, allowedHosts)`，每插件一個。
   - **不帶憑證**：不掛認證、cookie 攔截器；標頭只經 `mediaRequestHeaders`（`Referer`、`User-Agent`、`Origin`、`Range`）。
   - **每跳檢查**：`followRedirects: false`；每跳以同一份 `AllowedHosts` 檢查、只准 `https`、最多 5 跳；每跳只帶媒體標頭。規則與 `SourceHttpClient` 共用，不另寫一份。
   - **大小上限**：呼叫端給 `maxBytes`（封面會用 10 MiB）。先看 `Content-Length`，再邊收邊數，超過就中止、刪掉暫存檔，丟 `Unsupported`。
   - **逾時**：連線 10 秒、兩次收到資料之間 15 秒、整個請求 30 秒。
   - **錯誤對應**（ADR 0013 §決定 2）：
     - 傳輸錯誤與逾時是 `NetworkError`；
     - 429、帶 `Retry-After` 的 503 是 `RateLimited`；
     - 404、410 是 `NotFound`；
     - 其他狀態碼是 `UnexpectedError`，狀態碼進 log。
   - **不重試**。
   - **網路紀錄**：每跳一筆，tag `network`，欄位同 `SourceHttpClient`。兩種 client 都加一個 `client` 欄位（`source`／`media`）。
   - **網路狀態**：結果經 PR 2 的同一個入口回報（`networkStatusProvider` 的 `report`）：拿到回應算 `responded`，`NetworkError` 算失敗。
2. `PluginRegistry` 在插件載入時，以 manifest 的 `allowedHosts` 與 `SourceHttpClient` 一起建立它，並提供讓 PR 4 取得某插件媒體 client 的入口。PR 4 之前沒有呼叫端，這個入口要有測試。
3. 文件：
   - `app/AGENTS.md` § 網路加媒體 client 的契約，每條寫出閘門；
   - `.trellis/spec/app/network/index.md` 需要時補寫法。
   - M1 留下的「封面轉址不經 `allowedHosts`、沒有大小上限與逾時」（`app/AGENTS.md` § 介面）要到 PR 4 換掉 `Image.network` 時才解決，這個 PR 不改那段。
   - ADR 0011 的 log 欄位若有列舉，加 `client` 時看要不要一行補充。

## 不做

- 封面快取、`cache.db`、`ArtworkImage` 的改動（PR 4）。
- 重試、續傳、下載進度（M6）。

## 驗收

- [ ] 測試（`test/core/network/`，假 adapter，不連網）：
  - 請求沒有 `Cookie`、`Authorization`（ADR 0012 §如何確認），即使同一插件的 `SourceHttpClient` 有憑證；
  - 轉址出網域、轉到 `http`、第 6 跳，都失敗且不送出那一跳；
  - `Content-Length` 過大、串流中超過上限都中止，丟 `Unsupported`，且不留暫存檔；
  - 連線、間隔、總計三種逾時都是 `NetworkError`（以 `fakeAsync` 或可注入的時間，不真的等）；
  - 各狀態碼的錯誤對應；
  - `network log` 群組的欄位比對，含兩種 client 的 `client` 欄位；
  - 結果進網路狀態（回應與失敗各一）；
  - `PluginRegistry` 載入插件後拿得到該插件的媒體 client，`allowedHosts` 與 manifest 一致。
- [ ] `dart format`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全綠；動到 lint 時跑 `tool/lint_sentinel.dart`。
- [ ] 實機：沒有使用者看得到的改動，不做（父任務 implement.md § 3）。
