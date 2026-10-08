# 0030 — 插件庫以 `fmp-plugins` 的 `main` 分支託管 `index.json`，插件可停用，安裝更新移除都先確認

- 狀態：提議中
- 日期：2026-10-08
- 影響範圍：`1morr/fmp-plugins`（`index.json`、產生腳本、CI）、`app/lib/plugins/`（registry、repository、安裝與移除）、`app/lib/core/network/host_fetch.dart`、`app/lib/core/endpoints.dart`、資料表 `installed_plugins`、`plugin_indexes`、插件頁、搜尋頁的首次啟動引導

## 背景

ADR 0014 §決定 6–8 定了原則：官方插件在 `1morr/fmp-plugins`，CI 跑契約並產生含 SHA-256 的 `index.json`；插件頁預設讀官方 index、可加自訂 index、可從檔案或網址安裝；安裝前顯示能力與網域並警告；只在打開插件頁或手動時檢查更新；沒有來源時引導安裝；移除時清 storage 與憑證、曲目保留。

它沒有定的（`research/m3-scope-digest.md` §8.15–§8.20）：index 的欄位、託管位置與官方網址；插件庫 CI 用哪個「固定的 FMP 版本」、版本號規則；「啟用」是什麼（ADR 0017、0025、0014 §決定 9 都假設有，`installed_plugins` 沒有這欄）；安裝、更新、移除的流程細節；插件頁的內容；首次引導的觸發與呈現。現況 `fmp-plugins` 只有 B 站插件、沒有 CI、沒有 index，manifest 是 0.1.0。

## 考慮過的選項

### index 的託管

- **`main` 分支經 `raw.githubusercontent.com`**：不用改 repo 設定；index 與 `.js` 同一個 commit。CDN 約 5 分鐘的快取可能讓兩者短暫不一致。採用（Obsidian `community-plugins.json` 的做法）。
- **GitHub Pages**：要改 repo 設定，一樣有 CDN 延遲。否決。
- **GitHub Releases**：每次改插件都要發 release，流程重。否決。

### 插件庫 CI 的 FMP 版本

- **tag 或 release**：FMP 在 M9 之前沒有發佈版本。否決。
- **`main` 分支**：FMP 一改宿主 API，插件庫 CI 就無預警變紅。否決。
- **以 commit SHA 釘住（repo 變數 `FMP_REF`）**：宿主 API 變了就開 PR 改它。採用（GitHub Actions 以 SHA 釘版本的慣例）。

### 停用與「沒有回應」

- **同一件事**：「沒有回應」是看門狗發現卡住（ADR 0014），到重啟就恢復；停用是使用者的選擇，要跨重啟。合在一起會讓卡住一次的插件永久停用。否決。
- **兩件事**：停用存資料庫；沒有回應只在記憶體，插件頁可以直接把它停用。採用。

## 決定

1. **`index.json`**：`{indexVersion: 1, plugins: [{id, name, author, description, version, apiVersion, capabilities, allowedHosts, url, sha256, checksUrl?, checksSha256?}]}`。
   - 欄位封閉：不認得的欄位整個拒收；`indexVersion` 不是 1 就拒讀並提示「需要更新 FMP」。
   - `sha256` 針對單一 `.js` 安裝檔（ADR 0014 的補充）；不符就拒裝，提示「插件庫剛更新，請稍後再試」。
   - `checksUrl`／`checksSha256`：從 index 安裝或更新時一併下載該插件的 `checks.json` 存起來，供 Debug 頁健康檢查（ADR 0025 §決定 6）；驗證不過就不存，插件照裝。從檔案或網址安裝的插件沒有健康檢查。
2. **託管**：`1morr/fmp-plugins` 的 `main` 分支，經 `raw.githubusercontent.com` 讀；官方 index 網址在 `app/lib/core/endpoints.dart`。index 與 `.js` 由腳本在同一個 commit 產生。
3. **插件庫 CI**：以 `FMP_REF` checkout FMP，對每個插件目錄跑契約測試（重播），並檢查 index 是最新的；`.js` 有改動時 manifest 版本必須比 `main` 的高。冒煙測試不進 CI（ADR 0015 §決定 4）。
4. **版本**：semver，只升不降；`apiVersion` 不相容時顯示「需要更新 FMP」、不能安裝或更新。
5. **讀取**：宿主自己的請求（index、插件檔、checks）走一個不帶憑證、沒有 cookie、只准 `https`、有大小上限與逾時、寫網路紀錄的 client；允許網域是該網址自己的 host，轉址不得換 host。
6. **自訂 index**：加入時提示「非官方來源」，確認才存（`plugin_indexes` 表）。每個已安裝插件記住它來自哪個 index（`installed_plugins.source_index_url`，空＝從檔案或網址安裝），只從那裡更新；不同 index 的同 id 插件各自列出並標來源。
7. **啟用與停用**：`installed_plugins.enabled`（預設開）。停用＝不載入：不出現在搜尋、帳號頁、健康檢查、排程器（ADR 0017 §決定 5 立即移除它的工作）；佇列裡它的曲目照「音源已停用」跳過並標示；憑證與 storage 保留。「沒有回應」只在記憶體到重啟為止，插件頁可直接停用它。
8. **安裝**：先確認，列出名稱、作者、版本、能力、會連的網域，警告「此腳本會以你的登入身分存取這些網站」；從檔案或網址安裝另加「非官方來源」。確認的內容取自下載並驗過 SHA-256 的 `.js` 標頭 manifest；與 index 那一筆的 id、版本、能力、網域不一致就拒裝。dev flavor 的開發入口照舊跳過確認（prod 不讀）。
9. **更新**：只在打開插件頁或按「檢查更新」時比對（ADR 0014 §決定 7）；同 id 更新保留 storage 與憑證。**新版本的能力或網域比目前多時，先列出新增的部分再確認**；「全部更新」對這種插件逐個詢問，其餘直接更新。
10. **移除**：確認 → 關閉 runtime → 刪憑證與遮蔽登記 → 刪該插件 WebView 網域的 cookie → 刪帳號列與每音源設定 → 刪快取項目 → 移除排程器工作 → 刪 `installed_plugins` 列（`plugin_storage` cascade）。中途失敗就停下並提示，再按一次可完成（每一步都可重複）。曲目與電台保留，顯示「音源未安裝」。
11. **插件頁**：設定頁的「插件」區塊；分頁「已安裝」（版本、標記：開發中／已停用／沒有回應／有更新；能力、網域、來源；啟用開關、更新、移除、登入）與「可安裝」（官方與自訂 index）；工具列：檢查更新、全部更新、從檔案安裝、從網址安裝、管理 index。健康狀態在 Debug 頁。
12. **首次啟動引導**：沒有任何已啟用、具 `search` 能力的插件時，搜尋頁就地顯示空狀態（不做精靈，ADR 0024 §決定 9）：官方插件清單預設全勾、一次確認後依序安裝、部分失敗列出；讀不到 index 時顯示離線狀態與「重試」；「稍後再說」後的空狀態附「前往插件頁」。dev flavor 已有測試插件時不出現。

採用的慣例：Obsidian 的 `community-plugins.json`；MusicFree 的插件訂閱與「禁用」、沒有插件時的空狀態引導；VS Code Extensions 的「已安裝／市集」與啟用停用；Chrome 擴充功能在要求新權限時先等確認；GitHub Actions 以 SHA 釘版本。

## 後果

- 好的：插件可以停用而不失去登入；index 與安裝檔有完整性檢查；更新不會悄悄擴大插件能連的網域；首次啟動不必找插件頁；插件庫 CI 不被 FMP 的進度弄紅。
- 壞的：`fmp-plugins` 合併後約 5 分鐘內安裝可能因 SHA 不符失敗；FMP 改宿主 API 時要記得更新 `FMP_REF`；index 多兩個欄位要維護。
- 之後要注意：
  - M5 的 legacy import 偵測舊音源並提示一鍵安裝，用同一個安裝流程；
  - 若之後要簽章（不只 SHA），另立 ADR；
  - 自動檢查插件更新仍不做（ADR 0014）。

## 如何確認

- `plugin_installer_test.dart`：SHA 不符拒裝且不寫資料庫；index 與 `.js` manifest 的能力或網域不同時拒裝；semver 降版不顯示更新；`apiVersion` 不符；更新保留 storage 與憑證；能力或網域增加時回傳「需要確認」；移除後憑證、帳號列、快取項目、storage、`installed_plugins` 列都不在；移除中途失敗後重跑可完成。
- index 解析的測試：多出欄位拒收、`indexVersion` 不是 1 拒讀。
- `host_fetch_test.dart`：不帶憑證、只准 `https`、轉址換 host 失敗、大小上限。
- `plugin_registry_test.dart`：停用不載入、跨重啟；停用時排程器的工作被移除。
- widget 測試：插件頁兩分頁、標記、離線；首次啟動引導出現與消失的條件、部分失敗、離線。
- `fmp-plugins` 的 CI：`build_index --check` 對過時的 index 失敗；`.js` 改了沒升版本時失敗。
- 實機（ADR 0027，真實）：首次啟動引導安裝三個官方插件；停用、啟用、更新（以暫時分支當自訂 index）、移除。
