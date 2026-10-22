# M4 備份的兩個後續：插件與插件庫不一致的提示、「以登入身分瀏覽」留在這台

`implement.md`「PR 22 → 之後」的前兩條。擁有者 2026-10-22 回覆「按你建議」。

## 1. 已安裝插件與它的插件庫不一致

### 背景

- 備份可以把 `installed_plugins.source_index_url` 設成官方 index，插件頁的「來源」就把任意腳本標成官方（`plugins_page.dart` 的 `sourceLabel`）。
- 版本設得很高時，`updateStatus`（`lib/plugins/repository/plugin_updates.dart`）因為 semver 只升不降，永遠回 `none`，官方更新蓋不掉它。
- 還原確認框已列出插件、網域與警告；備份本來就能帶任意腳本，這兩點是在那之上的誤導與持續。
- 官方 index 每個插件只有最新一版、帶 `sha256`（ADR 0030 §決定 1）；插件頁打開或按「檢查更新」時本來就會讀 index。
- 參考的慣例：VS Code、瀏覽器的同步只帶擴充的 id、從商店重裝；FMP 的備份帶腳本（ADR 0034），所以改成「以來源 index 為準，讀到 index 時核對」。

### 需求

- R1：`PluginUpdateStatus` 加 `mismatch`：已安裝插件的 `sourceIndexUrl` 等於這份 index、id 相同，且
  - 已安裝版本（合法 semver）比 index 那一筆**高**；或
  - 版本相同，但已安裝腳本的 SHA-256 與 index 那一筆的 `sha256` 不同。
  
  版本較低時照舊是 `available`／`needsAppUpdate`（更新會換成驗過的腳本）。已安裝版本不是合法 semver 時照舊當最低。
- R2：腳本的 SHA-256 以安裝時存下的 `installed_plugins.script` 算。**從 index 正常安裝的插件不得誤判**：先確認 `PluginFile.decode` 存下的文字以 UTF-8 編回去與下載的位元組相同（含 BOM 的情形）；不同就改成在安裝時另外處理，停下回報，不自行改 schema。
- R3：插件頁「已安裝」：`mismatch` 的插件顯示警告標記「與插件庫不一致」，並有「從插件庫重新安裝」按鈕。這個按鈕走與更新相同的流程（`prepare` 下載並驗 SHA-256 與 manifest → 新增的能力與網域要確認 → 安裝），允許版本比已安裝的低。安裝後保留 storage 與憑證（同 id 更新的既有語意）。
- R4：「全部更新」與「檢查更新」的「有 n 個更新」不算 `mismatch`；檢查更新時若有 `mismatch`，提示改成告訴使用者有插件與插件庫不一致（一則 toast 即可，字串進 slang）。
- R5：標記與按鈕照 `plugins_page.dart` 既有的「有更新」「需要更新 FMP」的寫法與 ADR 0024 的版面，警告色用主題既有的 token。
- R6：測試：
  - `plugin_updates_test.dart`：較高版本 → `mismatch`；同版本不同腳本 → `mismatch`；同版本同腳本 → `none`；較低版本 → `available`；來源不同或 id 不同 → `none`。
  - 下載器到安裝的真實路徑（假的 HTTP、真的 `PluginFile.decode`）裝好後 `updateStatus` 是 `none`，含 BOM 的腳本一例。
  - widget 測試：`mismatch` 顯示標記與按鈕、按下走重新安裝；「全部更新」不包含它。

## 2. `source_settings.browse_as_logged_in` 留在這台

### 背景

- 憑證在 secure storage，備份不帶、還原保留這台的（ADR 0034）。「以登入身分瀏覽與播放」跟著登入，現在卻從備份帶過來：另一台換了帳號時，會靜默改掉這台的設定。
- `backupDeviceColumns`（`lib/data/database/backup_format.dart`）只處理單列表（`id = 1`）；`source_settings` 每個插件一列（主鍵 `plugin_id`）。

### 需求

- R7：新增「每列以鍵對應的裝置欄位」：`source_settings` 的 `browse_as_logged_in`，鍵是 `plugin_id`。形狀自訂，例如 `backupDeviceKeyedColumns = {'source_settings': (key: 'plugin_id', columns: ['browse_as_logged_in'])}`；名稱與型別由實作決定，但要和 `backupDeviceColumns` 一樣是常數清單、由同一個歸類閘門守。
- R8：匯出：這一欄在備份檔裡設成 NULL（同 `backupDeviceColumns` 的處理）。
- R9：還原（`readCarriedState` → `_carryOver`）：備份裡每一列的這一欄換成這台同 `plugin_id` 那一列的值；這台沒有那一列時是 NULL（＝預設）。這台有、備份沒有的插件不新增列。
- R10：`backup_format_test.dart` 的歸類閘門涵蓋新常數（欄位存在、表在帶走的清單裡）；`database_backups_test.dart` 加：匯出後該欄全是 NULL；還原後是這台的值、這台沒有的列是 NULL、其餘欄位（`match_target`、`match_rank` 等）照備份。

## 文檔

- R11：ADR 0030 §決定 4、9 加補充（2026-10-22）寫 R1、R3（「以來源 index 為準」是 semver 只升不降的例外）；ADR 0034 加補充寫 R7–R9；M4 `design.md` §11 若列了裝置欄位同步一句。
- R12：`implement.md`「PR 22 → 之後」前兩條改成已處理並指向這個 PR（主對話寫）。

## 驗收

- `flutter analyze`、`dart format --set-exit-if-changed`、全部測試綠。
- Android 實機（dev flavor）：
  - 插件頁讀官方 index（真實：1 個 index GET，插件頁本來就會發），從官方裝的插件都不顯示「與插件庫不一致」。
  - 用測試插件以外的方式不偽造；`mismatch` 的畫面由 widget 測試守。
- 備份的裝置欄位由資料庫測試守，不另做兩平台實機（共用 Dart、沒有平台差異）。

## 不做

- 不在還原時連網驗證；不改備份檔格式版本（只多一欄設成 NULL，舊檔照樣能還原）。
- 確認框列「這台有、備份沒有、還原後會消失」的插件、`isOlderVersion` 的非 semver、Android SAF 篩選：照舊留在「PR 22 → 之後」。
- `playlist_remote.writable` 的即時更正。
