# 排行契約、快取與工作（FMP 端）

## 目標

M4 PR 20 的 FMP 端（上層 `implement.md` § 20、design §3.1、§3.3、§4.6、§4.9、§6.2、§9.1、ADR 0032 §決定 5–7、ADR 0016、ADR 0017）：`charts` 能力的契約、`fmp-test` 的榜單、排行快取、每插件一個 `charts:<pluginId>` 排程工作、排行刷新間隔設定、`chart_settings` 表。三個官方插件的 `chartList`／`chart` 在 `1morr/fmp-plugins` 另一個 PR（本 PR 合併後）。首頁的呈現在 PR 21。上層計畫已核准，本 PR 不需要新的擁有者決定。

## 需求

- **契約**（照 `importPlaylist` 在 PR 6 的做法）：
  - `ChartsExports`（`chartList`、`chart`）進 `PluginManifest.requiredExports`／`knownExports`：宣告 `charts` 就兩個都要匯出，匯出了沒宣告就拒載。
  - `SourcePlugin.chartList()`、`chart(chartId)`；DTO `ChartRef {chartId, title}`、`ChartList {charts}`、`ChartPage {tracks: TrackSummary[]}`（名稱照現有 DTO 慣例），加進 `sourceDtoShapes` 與驗證：`chartId` 不重複、`title` 不空；`tracks` 可以是空的。請求 `userPreference`（ADR 0032 §決定 5）。
  - `fmp-plugin.d.ts`、`FmpChecks.charts`（輸入 `{chartId}`，跑 `chart`，檢查 `tracks`；不標 `requiresLogin`）、`checkShapes`、`PluginCheck.run`、契約測試與健康檢查的 `a charts case`。
- **`fmp-test`**（design §4.9）：宣告 `charts`；`chartList` 回 `hot`、`new`、`broken`；`hot` 5 首、`new` 3 首、`broken` 以 `NetworkError` 失敗；`checks.json` 加 `charts` 案例（`hot`）。曲目沿用現有的測試音檔 id 讓它們可播。
- **schema v17**（主資料庫）：
  - `network_settings.chart_refresh_interval_minutes` int?：空＝60，`0`＝關閉，選項 0／30／60／120／240。
  - `chart_settings`：主鍵（`plugin_id`, `chart_id`）、`enabled` bool?（空＝啟用）、`sort_order` int?。不建外鍵到 `installed_plugins`。
  - migration 照 `.trellis/spec/app/data/index.md`（`make-migrations`、schema 快照、migration 測試三種：全新、從 v16 升、資料保留）。
  - `chart_settings_repository.dart`：只加有人呼叫的方法（讀全部、`watch`、本 PR 需要的寫入；設定頁的排序與開關在 PR 21，那時再加）。
  - 移除插件時 `PluginInstaller.remove` 刪該插件的 `chart_settings` 列（同 `source_settings`）。
- **設定**：`NetworkSettings` 加 `chartRefreshInterval`（對外 `Duration?`，`null`＝關閉）與 setter（選項外丟 `ArgumentError`），照 `radioStatusInterval` 的寫法；設定頁「網路」區在電台間隔之後加一列（字串三語言）。
- **快取**（design §9.1）：快取庫加 `CacheCategory.chart`（converter 的寫死字串）；鍵 `chart:<pluginId>:<chartId>`，內容 `{fetchedAt, tracks}` 的 JSON，所屬插件記在索引，`CacheStore.removePlugin` 一起刪。`lib/charts/chart_cache.dart` 只經 `CacheStore` 讀寫，`lib/charts/` 不直接碰 `lib/data/cache/` 的表（`fmp_layer_imports` 的 `charts/` 那半條，lint 雙向變異測試）。被淘汰視為沒有快取。
- **工作**（design §6.2，照 `lib/radio/radio_status_jobs.dart`）：`lib/charts/chart_jobs.dart`，`FmpApp` 常駐。
  - 每個「已啟用、宣告 `charts`、至少一個啟用榜單」的插件一個工作 `charts:<pluginId>`（帶 `pluginId`），間隔是排行間隔（關閉＝`interval: null`，只有手動 `runNow` 會跑）。
  - 每次執行：`chartList` → 啟用的榜單（`chart_settings.enabled` 不是假；插件新增的榜單預設啟用；插件拿掉的榜單的列留著、讀時以 `chartList` 為準）逐一 `chart` → 寫快取。單一榜單失敗只在記憶體標那一個「更新失敗」（照 `radioQueryFailuresProvider`），其他繼續；全部失敗才丟錯讓排程器退避。
  - 只在插件實例、間隔、啟用榜單集合改變時重新登記；某插件的榜單全部停用就移除工作；榜單被停用時刪那個榜單的快取（ADR 0016 §決定 4）。插件停用時刪該插件的排行快取。
  - 對外：`runNow(pluginId)`（離線回 `offline`，照電台的手動刷新）、讀快取與失敗標記的 provider，給 PR 21 用。本 PR 沒有 UI 讀它們，只有測試。
- log：工作完成時一行（插件、成功與失敗的榜單數）；照現有 tag 慣例。

## 驗收

- 測試：
  - `charts_capability_test.dart`（照 `import_playlist_capability_test` 之類）：宣告與匯出不符拒載、DTO 驗證（重複 `chartId`、空 `title` 拒收、空 `tracks` 接受）。
  - 排程：全部榜單停用不登記、單榜單失敗不退避且標記、全部失敗退避、間隔改變重新登記、關閉時 `interval: null` 且 `runNow` 仍可跑、離線 `runNow` 回 `offline`。
  - 快取：寫入後讀得到 `fetchedAt` 與曲目、榜單停用刪快取、插件停用刪、移除插件刪（`chart_settings` 列與快取都刪）。
  - migration 三種；設定的 Notifier 與設定頁「網路」區的新列（guideline 若網路區有案例就跟著）。
  - 契約測試與健康檢查的 `a charts case`（`fmp-test` 的 `hot`）。
  - lint：`fmp_layer_imports` 新規則的雙向變異（違規會紅、無關改名不紅），`dart run tool/lint_sentinel.dart`。
- `dart format --output=none --set-exit-if-changed lib test integration_test tool`、`build_runner` 後沒有實質變動、`dart run slang`（無差異）、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過（Windows 上兩個 `trackDetail` CRLF 失敗是既有的）。
- 文件：`app/AGENTS.md` 的排程器工作清單、插件能力、快取段落；`.trellis/spec/app/plugins/index.md` 多匯出能力那一句加 `charts`；需要的 spec。
- 實機（主對話做，重播，Android）：沒有 UI，以 log 看 `fmp-test` 的 `charts:fmp-test` 工作執行（`hot`、`new` 成功、`broken` 失敗）、快取寫入。

## 不做

- 首頁排行、探索頁、設定頁「音樂庫」區的榜單排序與開關（PR 21）。
- 三個官方插件的實作（`fmp-plugins` 的後續 PR）。
