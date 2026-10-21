# 首頁排行、探索頁、首頁排行設定

## 目標

M4 PR 21（上層 `implement.md` § 21、design §9.2、§9.3、§10.2、§10.7、§10.10，ADR 0016 §決定 4、7，ADR 0033）：把 PR 20 已經在背景抓好、寫進快取的榜單呈現出來——首頁最上面的排行區塊、「查看全部」開的探索頁、設定頁新的「音樂庫」區的「首頁排行」排序與開關。上層計畫已核准，本 PR 不需要新的擁有者決定。

## 現況（PR 20 已合併）

- `lib/charts/chart_jobs.dart`：`chartSettingsProvider`（`chart_settings` 的 stream）、`chartFailuresProvider`（記憶體的單榜單「更新失敗」）、`chartJobsProvider`（`runNow(pluginId)` 回 `RunNowResult`，離線回 `offline`）；`ChartJobs` 監看 `chartSettingsProvider`，榜單停用時自己刪快取並重新登記工作。
- `lib/charts/chart_cache.dart`：`chartContentProvider(ChartKey)` 回 `ChartCacheEntry?`（`fetchedAt`、`tracks`），沒有或被淘汰是 `null`。
- `lib/data/repositories/chart_settings_repository.dart`：`watch`、`setEnabled`、`removePlugin`；還沒有寫 `sort_order` 的方法。
- 榜單名稱（`chartList` 的 `title`）只存在 `ChartJobs` 的私有 `_lists`，沒有 provider 給 UI。

## 需求

- **榜單清單給 UI**：在 `lib/charts/` 加一個 provider，給「每個已啟用、宣告 `charts` 的插件的榜單（`pluginId`、`chartId`、`title`、插件顯示名稱）＋ `chart_settings` 的啟用與順序」合併後的清單。順序：`sort_order` 由小到大，沒有的排在後面、依插件清單順序再依 `chartList` 順序（同 design §8.3 的目標音源排序規則）。插件新增的榜單預設啟用；插件拿掉的榜單不顯示。重用 `ChartJobs` 已取得的 `chartList`，不要讓 UI 每次重建都打插件。
- **首頁排行區塊**（design §9.2、§10.2）：首頁區塊順序變成排行、我的歌單、電台、最近播放。每個啟用的榜單依上面的順序一個子區塊：榜單名稱與音源、前 5 首（點一下臨時播放，選單照 `TrackRowMenu`）、「查看全部」（開探索頁的那個分頁）。
  - 快取有內容：顯示並標「更新於 <時間>」；`chartFailuresProvider` 標了的加「更新失敗」。
  - 沒有快取：在線顯示載入中（並觸發不了就保持載入中直到工作寫入）、不在線顯示離線空狀態（ADR 0016 §決定 7，用既有的 `lib/ui/offline/` 元件）。
  - 全部停用（或沒有任何宣告 `charts` 的插件）就沒有這個區塊（決定 2，不保留「至少留一個」）。首頁「全部都沒有時顯示說明」與首次啟動引導的判斷要把排行算進去。
    - 註記（實作時確定）：首次啟動引導照 ADR 0030 §決定 12、design §10.2 只看有沒有 `search` 能力的插件，不看排行；排行只算進「全部都沒有內容」的判斷（啟用的榜單算內容）。
- **探索頁**（design §9.3）：首頁「查看全部」開的子頁，在首頁的巢狀 `Navigator` 裡。每個啟用的榜單一個分頁（順序同上），完整清單、多選（`lib/ui/tracks/track_selection.dart`，動作照 §10.7：加入佇列、加入歌單、加入遠端歌單）、工具列「刷新」（`runNow(pluginId)`；離線與失敗以既有 toast 慣例提示）。每個分頁的快取、失敗、離線狀態同首頁。
- **設定頁「音樂庫」區**（design §10.10；這一區第一次出現，PR 19 之後會加「匹配目標音源」）：區塊順序：帳號、外觀、播放、音樂庫、網路、插件、備份與還原（PR 22 才有）、關於。內容「首頁排行」：可拖曳排序、可勾選的榜單清單，每列標榜單名稱與音源。拖曳後整批寫 `sort_order`（repository 加這個方法）；取消勾選寫 `enabled = false`（`ChartJobs` 會刪快取並重新登記工作，本 PR 不重做）。沒有任何榜單時顯示說明。
- 字串三語言（slang）。

## 設計空間

design 只定了上面的內容與行為，版面（子區塊的卡片或列、前 5 首的排法、探索頁分頁的形式、設定清單的拖曳把手）沒有定稿，由實作者照 ADR 0024 與既有首頁、音樂庫、設定頁的元件決定，並在回報裡列出做了哪些版面選擇。行為或範圍上 design 沒涵蓋的決定（例如要不要新增設定、改變工作或快取的行為）停下回報，不自行拍板。

## 驗收

- 測試：
  - 榜單清單 provider：順序照 `sort_order` 再照插件與 `chartList`；新增的榜單預設啟用；插件拿掉的不出現；停用插件的不出現。
  - 首頁：全部停用沒有排行區塊；順序照設定；快取有內容時顯示前 5 首與「更新於」；失敗標記；沒有快取時在線載入中、離線空狀態；全部區塊都沒有時的說明仍正確。
  - 探索頁：分頁照順序、完整清單、多選的動作、刷新呼叫 `runNow`（離線提示）。
  - 設定：拖曳寫 `sort_order`、取消勾選寫 `enabled`；之後 `chartSettingsProvider` 變化（工作的刪快取與重新登記由 PR 20 的測試守，這裡只驗寫入）。
  - guideline 測試（`.trellis/spec/app/ui/index.md` 的現有 guideline 案例若涵蓋首頁或設定區塊就跟著加）。
- `dart format --output=none --set-exit-if-changed lib test integration_test tool`、`build_runner` 後沒有實質變動、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過（Windows 上兩個 `trackDetail` CRLF 失敗是既有的）。
- 文件：`app/AGENTS.md` 有首頁或設定頁區塊清單就更新；需要的 spec。
- 實機（主對話做）：重播（Android）：`fmp-test` 的 `hot`、`new`、`broken` → 首頁、探索、多選加入歌單 → 停用 `new`。真實（匿名，Android）：首頁看到三個官方插件的榜單一次。

## 不做

- 匹配目標音源設定（PR 19）、備份區（PR 22）。
- 排行工作、快取、間隔設定的行為（PR 20 已做）。
