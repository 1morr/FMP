# M3b PR 11：開發者模式、「關於」、Debug 路由與概覽

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（`implement.md` §11，design §3.1、§3.3、§12.1）。ADR 0025（開發者模式與 Debug 頁）、ADR 0024（設定頁 list-detail、§決定 9 的「關於」）、ADR 0011（遮蔽）。計畫已核准，在範圍內直接做；遇到計畫沒寫的決定才問。

## 做什麼

1. **schema v9**：新表 `developer_settings`（單列，四欄一次建好：`developer_mode` bool?、`log_level` text?、`plugin_dev_folder` text?、`report_reminder_dismissed` bool?，全部可空，空＝沒設定過）。照 `.trellis/spec/app/data/index.md` § 改 schema 的完整流程（migration、schema 快照、三種 migration 測試）。
2. **設定組「開發者」**：Notifier 套預設（`developer_mode`：prod 關、dev 開；`log_level`：`info`），提供 `developerMode`、`logLevel` 的 setter；關閉開發者模式時**同一筆寫入**清空 `log_level` 與 `plugin_dev_folder`（卸載開發中插件的那一半在 PR 16）。
3. **App 版本**：平台層讀 `package_info_plus` 10.2.2（design §14；pub.dev 2026-10-13 的 latest 也是 10.2.2）。
4. **設定頁「關於」區塊**：設定頁最後一個區塊（開發者模式下 Debug 在它之後），只有版本列（版本、flavor）。版本列連點 7 次開啟開發者模式：第 2 次起提示「再點 n 次即可開啟開發者模式」，離開頁面計數歸零（Firefox `SecretDebugMenuTrigger` 的慣例）；已開啟時點了提示已開啟。
5. **Debug 路由**：開發者模式關閉時一律 redirect 回設定頁；設定頁的 Debug 入口只在開啟時出現。版面沿用設定頁的 list-detail（ADR 0024），ADR 0025 §決定 2 的八個區塊做成骨架，**這個 PR 只顯示「概覽」**，其餘區塊由後續 PR 各加一個。
6. **概覽**：最上方總開關（關閉＝第 2 點的那筆寫入，之後回到設定頁、入口消失）；log 層級（`debug`／`info`，接上 log 門面，改成 `debug` 後 debug 記錄進記憶體歷史）；版本／flavor／平台／資料目錄（顯示時家目錄換成 `~`）；快取用量連結（到設定頁「網路」）。
7. **文件**：`app/AGENTS.md` 對應各層（設定、資料、UI、平台）的契約與閘門；需要時更新 `.trellis/spec/app/<layer>/`；新增的全螢幕路由加進 `toast_layering_test.dart` 的案例。

## 不做

- Debug 頁其他區塊（PR 12–16）、錯誤提示的「詳細」（PR 13）、插件開發工具與 `plugin_dev_folder` 的使用（PR 16）、`report_reminder_dismissed` 的使用（PR 13）、「關於」的其餘內容（M9）。

## 驗收

- [ ] ADR 0025 §如何確認的開發者模式三項：連點 7 次寫入 `developer_mode = true`；關閉時清空 `log_level`（與 `plugin_dev_folder`）；dev flavor 預設開、prod 預設關。
- [ ] 開發者模式關閉時直接進 Debug 路由被 redirect 回設定頁；設定頁的 Debug 入口只在開啟時出現（widget）。
- [ ] log 層級改成 `debug` 後，debug 記錄進記憶體歷史；改回 `info` 後不進。
- [ ] migration 三種（空資料庫建立、v8 升 v9、schema 快照比對）；guideline 測試（新頁面的寬窄版面）。
- [ ] `flutter analyze`、`dart analyze --fatal-infos`、`dart format`、`flutter test` 全綠；`toast_layering_test.dart` 含 Debug 路由。
- [ ] **實機（重播）**：Windows **release**（`flutter build windows --flavor dev --release`）連點 7 次開啟 → 重啟後仍開啟 → 總開關關掉 → 入口消失；Android（debug）同樣走一次。Windows 照 ADR 0027 §決定 3 的修訂要驗：本 PR 加了帶原生程式碼的依賴（`package_info_plus`）。
