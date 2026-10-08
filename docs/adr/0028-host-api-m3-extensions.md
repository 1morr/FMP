# 0028 — 宿主 API v1 在發佈前擴充直播、Mix、分 P、曲目詳細與語意冪等，取消做在控制器層

- 狀態：已採納
- 日期：2026-10-08
- 影響範圍：`app/lib/plugins/`（`SourcePlugin`、`fmp-plugin.d.ts`、DTO 驗證、契約執行器的 `checks.json`）、`app/lib/core/network/`（重試判斷）、`app/lib/playback/`（被取代請求的處理）、`1morr/fmp-plugins` 的三個插件

## 背景

ADR 0014 §決定 4 列了 12 個能力，§決定 5 定了宿主 API v1，但只有 `search`、`resolveStream` 有輸入輸出（M1、M2）。M3 要用到的 `live`（電台）、`mix`（YouTube Mix）、`multiPart`（B 站分 P）、`trackDetail`（曲目詳細）都沒有 DTO 與函式簽名（`research/m3-scope-digest.md` §8.9）。另外三件留給 M3 的事也要動宿主 API：

- YouTube innertube 與網易的查詢是 POST，現行「只重試冪等方法」不會重試它們（M1 待辦，ADR 0013 §決定 4）；
- `checks.json` 只收 `search`、`resolveStream`，新能力與「要登入才有意義」的案例沒有格式（ADR 0015 §決定 4，digest 矛盾 9）；
- ADR 0018 §決定 6「被取代的請求經宿主 `http.request` 取消網路工作」需要宿主知道每個請求屬於哪一次插件呼叫（M2 待辦）。

`fmp-plugin.d.ts` 的物件是封閉的（不認得的欄位整個拒收），ADR 0014 把擴充限定為「發佈前在 v1 內」，但沒說何時算發佈（矛盾 11）。

`login` 的契約與 `authHeaders` 屬於帳號，見 ADR 0029。

## 考慮過的選項

### 選項 A：升 v2，一次把所有能力定完

把 12 個能力的 DTO 都定好再升 `apiVersion`。缺點：M4、M7 的能力（`importPlaylist`、`charts`、`lyrics`）還沒有實際使用者，現在定是猜；而且現在只有擁有者的 dev 版讀插件，沒有相容負擔，升版沒有好處。

### 選項 B：在 v1 內加選填欄位與新匯出，到 M9 對外發佈才凍結

只定 M3 用到的四個能力與兩個欄位，`hostApiVersion` 維持 1；能力與匯出同名、雙向一致的既有規則照舊。缺點：M9 之前插件與 FMP 要同一輪改。

### 取消的做法

- **宿主追蹤每個請求屬於哪一次呼叫**：YouTube.js 的請求經插件內的 fetch 補丁發出，QuickJS 沒有 AsyncLocalStorage，宿主對不回呼叫；要做就得要求插件每次手動傳呼叫 id，插件作者容易漏。否決。
- **控制器以代際檢查丟掉結果**：被取代的解析結果不播出、不再因它發新的解析；已送出的 HTTP 跑完。代價是快速切歌時多跑幾個請求的流量。

### 語意冪等的宣告位置

- **manifest 宣告「哪些網址可重試」**：網址規則難寫，YouTube 同一個端點有讀有寫。否決。
- **每次請求的選項**：插件在發請求的地方最清楚。採用。

## 決定

採用選項 B 與控制器層的取消。

1. **凍結點**：宿主 API v1 在 `app/` 第一個 prod 版本對外發佈（M9 切換）時凍結；在那之前可加選填欄位與新的匯出，`apiVersion` 不變，`1morr/fmp-plugins` 同一輪跟上。凍結後的新增是 v2。
2. **`HttpRequest.idempotent?: boolean`**：空＝依 HTTP 方法；`true` 讓語意冪等的 POST 也照網路層的規則重試。只影響重試，不影響認證、限流與網路紀錄。慣例：gRPC 的 per-method `idempotency_level`；RFC 9110 §9.2.2；ADR 0013 本來就允許「音源標為可重試者」。
   - **`HttpResponse.credentialsAttached?: boolean`**（選填，同屬 v1 內的擴充）：宿主告訴插件這次請求有沒有真的帶憑證（ADR 0012 的 `attach` 才為真；`omit`、`refuse`、`auth: 'never'`、憑證已失效時為假）。插件的「憑證無效」判定（ADR 0029 §決定 7）只在它為真的回應上成立：未帶憑證而被拒的 401、`-101` 是匿名請求被拒，不能標成憑證失效。插件只靠回應本身分不出這兩種情況，因為帶不帶憑證由宿主依 `auth`、登入狀態與「以登入身分瀏覽與播放」開關決定。
3. **`live`** 的匯出：
   - `liveSearch({keyword, page, status?}) → {items: LiveRoom[], hasMore}`（`status` 是「開播中／未開播」篩選，空＝全部）；
   - `liveRoomFromUrl({url}) → {roomId} | null`（不是這個插件的網址回 `null`）；
   - `liveStatus({roomId}) → LiveRoom`，**查詢失敗一律拋錯，不能回未開播**（D10）；
   - `resolveLive({roomId, formats}) → StreamResult`，`expiresAt` 可空。
   - `LiveRoom = {roomId, title, hostName?, artwork?, status: 'live' | 'offline', online?}`。
4. **`mix`**：`mix({seed: {sourceId, cid?}} | {mixId, cursor}) → {mixId, title, tracks, cursor | null}`。`cursor` 是插件的不透明字串，`null` 表示這個 Mix 沒有更多。**Mix 身分**＝（插件 id, `mixId`）；佇列持久化（ADR 0018 §決定 10）與 M4 的 `playlists.kind = mix`（ADR 0019）存同一對值。
5. **`multiPart`**：`TrackSummary` 加選填 `partCount`；`multiPart({sourceId}) → {parts: [{cid, title, durationMs?, index}]}`。每個分 P 是一首曲目（ADR 0005）。
6. **`trackDetail`**：`trackDetail({sourceId, cid?}) → {description?, publishedAt?, uploaderAvatar?, album?, stats?: [{kind, count}]}`；`kind` 是封閉的 union（`view`、`like`、`favorite`、`comment`、`share`、`danmaku`、`coin`），宿主依它挑圖示與翻譯，不顯示插件給的文字。
7. **`checks.json`**：每個能力一個鍵，案例形狀與 `search` 相同（`input`＋`expect`）；`login` 的案例是 `loginVerify`，`live` 的是 `liveStatus`。案例可標 `requiresLogin: true`（M3 只有 `login` 的案例標它；每個能力只有一條案例，不為登入後的行為另加案例）：契約測試照常重播 fixture；Debug 頁健康檢查與 App 內錄製遇到它時，該插件已登入就用已存的憑證跑，未登入標「略過」；命令列錄製略過它。
8. **被取代的請求**：不經宿主取消網路工作。控制器以代際檢查丟掉被取代的 `resolveStream`／`resolveLive` 結果，不播出、不再發解析；已送出的 HTTP 讓它跑完。ADR 0018 §決定 6 與 §決定 9（「開直播必然取消進行中的音樂請求」）各加一行更正指到這裡。
9. **同步點**：每加一個欄位或匯出，同一個 PR 改 `fmp-plugin.d.ts`、Dart 端的 shapes、`SourcePlugin` 的方法與 `FmpChecks`。`SourcePlugin` 的方法只在引入它的 PR 加。

採用的慣例：MusicFree、LX Music 的插件以函式匯出各能力、App 依匯出出現入口；gRPC 的冪等宣告；舊版 `video_detail.dart`、`radio_station.dart`、`mix_session_coordinator.dart` 的欄位與行為作規格。

## 後果

- 好的：M3 的四個能力有了契約，宿主仍沒有音源分支；POST 查詢也能重試；健康檢查分得出「失敗」與「沒登入所以略過」；取消不需要插件配合。
- 壞的：M9 之前 FMP 與 `fmp-plugins` 要同一輪改；被取代的請求仍會跑完（多一點流量）；`trackDetail` 的統計種類寫死在 union，新種類要改宿主。
- 之後要注意：
  - M4 的 `importPlaylist`、`libraryRead`、`libraryWrite`、`charts` 與 M7 的 `lyrics` 照同樣的方式加，凍結前定完；
  - 若量到被取代的請求造成問題（例如風控），再設計讓插件傳呼叫 id 的取消方式，需要新 ADR。

## 如何確認

- `type_definitions_test.dart`：`fmp-plugin.d.ts` 的新欄位、新匯出、`stats.kind` 等 union 與 Dart 端一致（含變異案例）。
- `script_source_plugin_test.dart`：宣告 `live`、`mix`、`multiPart`、`trackDetail` 而沒有匯出對應函式時拒載；多出的欄位拒收。
- `source_http_client_test.dart` 的 `retry`：標 `idempotent` 的 POST 重試、沒標的不重試；`auth`：`credentialsAttached` 只在帶了憑證時為真。
- `checks_test.dart`、`contract_runner_test.dart`：新能力的案例格式、`requiresLogin` 在重播照跑、命令列錄製略過；健康檢查：已登入用已存憑證跑、未登入標略過。
- 控制器測試：解析中開直播（或換歌），解析完成後後端只收到新的流，`resolveStream` 的呼叫次數不變。
- 三個官方插件的契約案例在 `fmp-plugins` 的 CI 以固定的 FMP 版本執行（ADR 0015 §決定 6）。
