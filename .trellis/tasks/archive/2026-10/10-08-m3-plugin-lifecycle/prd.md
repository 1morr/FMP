# 插件生命週期（M3 PR 4）

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`。技術設計在父任務 `design.md` §3.1（`installed_plugins` 的新欄位、`plugin_indexes`）、§3.2（schema 版本與測試）、§7.1（`index.json` 與讀取、`host_fetch`）、§7.3（啟用與停用）、§7.4（安裝、更新、移除）；ADR 0030。執行清單在父任務 `implement.md`「4.」。本檔只列做什麼與驗收。

## 目標

宿主有插件生命週期的資料與邏輯：插件可啟用、停用、移除；能讀插件 index、驗證 SHA、比對更新。UI（插件頁）在 PR 5。

## 做什麼

1. schema：`installed_plugins` 加 `enabled`（預設真）、`source_index_url`、`checks_json`；新表 `plugin_indexes`；repository 與 migration（`.trellis/spec/app/data/index.md` § 改 schema 的完整流程）。
2. `PluginRegistry`：只載入啟用的；`setEnabled`；移除流程照 design §7.4 的順序（排程器那一步在 PR 17 加）；`Redactor` 的 `_mediaCdns` 以插件 id 為鍵取代（M1 待辦 14）。
3. `lib/core/network/host_fetch.dart`（design §7.1 的規則）；`lib/plugins/repository/`：讀 index（欄位封閉、`indexVersion`）、SHA 驗證、`checksUrl` 下載、更新比對（`pub_semver`）、能力或網域增加時回傳「需要確認」。
4. `pluginNameProvider`：找不到插件時顯示「音源未安裝」，停用時顯示「音源已停用」（三語言）。
5. 文件：`app/AGENTS.md` 的對應段落與 data／plugins spec；每條寫閘門。

## 不做

- 插件頁、從檔案安裝的 UI、設定頁區塊（PR 5）；首次啟動引導（PR 6）；官方 index 網址與 `fmp-plugins` 的 CI（PR 3）；排程器那一步（PR 17）。

## 驗收

- [ ] 測試：migration 三種（升級前裝好的插件升級後仍啟用、內容不變）；`plugin_installer_test.dart`：design §7.4 閘門的每一條；`host_fetch_test.dart`：不帶憑證、只准 `https`、轉址換 host 失敗、大小上限、網路紀錄 `client: host`；index 解析：多出欄位拒收、`indexVersion` 不是 1；`plugin_registry_test.dart`：停用不載入、跨重啟；`pluginNameProvider` 的兩種顯示。
- [ ] 驗證清單全綠（`app/AGENTS.md` § 驗證）。
- 實機：沒有使用者看得到的改動（插件頁在 PR 5），不做。
