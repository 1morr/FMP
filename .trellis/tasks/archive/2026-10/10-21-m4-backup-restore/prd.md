# 備份與還原

## 目標

M4 PR 22（上層 `implement.md` § 22、design §11、§17 第 15 條，ADR 0034，ADR 0025 §決定 9 的 2026-10-15 更正）：

- 設定頁新的「備份與還原」區：「匯出備份」存成 `fmp-backup-<UTC>.db`；「從備份檔還原」取代目前的資料並重啟。
- 還原保留這台目前的登入（憑證、登入 WebView、`accounts` 列）與只屬於這台的值。
- Debug 頁的「從備份還原」改走同一條還原路徑，不再清憑證與登入 WebView。

流程、格式、清單都已由擁有者定案（ADR 0034，2026-10-15），本 PR 不需要新的擁有者決定。計畫沒涵蓋、會改變行為或範圍的決定，停下回報。

## 現況（以程式碼為準）

- `lib/data/database/database_backups.dart`：`DatabaseBackups` 有 `create`（`VACUUM INTO` 到 `backups/fmp-<時間>.db`）、`list`、`exists`、`restore`（關閉、原檔改名、換檔）、`erase`。
- `lib/app/data_reset.dart`：`DataReset`（`backUp`、`backups`、`resetAndRestart`、`restoreAndRestart`），實作 `AppDataReset`；`restoreAndRestart` 目前會清 secure storage 與登入 WebView。
- `lib/ui/debug/debug_data_actions.dart`：Debug 頁的備份、還原、重設。
- 平台層：`FileDialogs.pickFile({required String extension})`、`saveFile(name, bytes, mimeType)`（`lib/platform/files/`）；重啟是 `appRestarterProvider`（`PlatformCapabilities.restartsItself`：Windows 真、Android 假）。
- 設定頁分組 `SettingsSection`（`lib/ui/settings/settings_page.dart`）。
- 安裝確認框列網域的元件：`lib/ui/plugins/plugins_page.dart`（`hosts:`）、ADR 0030 §決定 8 的警告文案。
- schema 目前是 v18（PR 19 加了 `match_results`、`track_origins`）。

## 需求

### 1. `DatabaseBackups`（design §11）

- **兩份常數**：
  - `backupExcludedTables`：`layout_state`、`accounts`、`plugin_storage`、`scheduler_runs`。
  - `backupDeviceColumns`：`playback_settings` 的輸出裝置兩欄、`developer_settings.plugin_dev_folder`。
  - 外加 `installed_plugins` 裡 `from_dev_folder` 的標記列（匯出時刪掉）。
  - 「帶走」清單（其餘所有表）也寫成常數。
- **`export(File target)`**：`VACUUM INTO` 到資料目錄的暫存檔 → 以 `sqlite3` 開暫存檔，清空排除的表、把裝置欄位設成預設或空值、刪掉標記列 → `VACUUM` → 關閉 → 移到 `target`。失敗時刪掉暫存。
- **`stage(...)`**：設定頁給位元組，Debug 頁給 `backups/` 裡的檔 → `StagedBackup`。
  - 寫到 `backups/staged-<UTC>.db`，依序檢查：
    1. SQLite 標頭 `SQLite format 3\0`；
    2. `user_version`：0 → 不是 FMP 的備份；大於 `schemaVersion` → 較新版；
    3. `PRAGMA integrity_check`；
    4. **安全**：開暫存檔時 `PRAGMA trusted_schema = OFF`；migration 之後，`sqlite_master` 的物件（表、索引、trigger、view）必須是 App 的 schema 會建出的那一組（拿一個全新的 in-memory `AppDatabase` 的 `sqlite_master` 比對名稱與類型）；多出 trigger、view 或不認得的物件就當成不是 FMP 的備份。
       - 理由：備份檔是外來檔案，`carryOver` 會在它上面寫入，裡面的 trigger 會被觸發。
       - 這一條是本計畫在 ADR「缺必要的表就拒絕」之上補的，回報時列出實作方式。
    5. 以 `AppDatabase` 開啟並跑 migration 到目前版本；
    6. 讀 `installed_plugins` 每列的 id、名稱、版本、`allowedHosts`（從 manifest 解析）給確認框；
    7. 關閉。
  - 任何一步失敗：刪暫存，拋 `BackupRejected`，原因分三種：`newerVersion`、`notFmpBackup`、`corrupt`。目前的資料庫完全不動。
- **`carryOver(StagedBackup, CarriedState)`**：
  - 把這台目前的 `accounts` 列、`layout_state` 列、輸出裝置兩欄、`plugin_dev_folder`，以及 `from_dev_folder` 標記列（若有）寫進暫存檔。
  - 寫之前先刪暫存檔裡的同類資料。
  - `CarriedState` 從目前的資料庫讀。
- **`restoreStaged(StagedBackup)`**：同 M3 的 `restore`：關閉、原檔改名留著、以暫存檔取代 `fmp.db`。
- **表的歸類閘門**：`backupExcludedTables` 加上「帶走」清單要剛好等於 `AppDatabase.allTables` 的表名，新表沒有歸類就紅。
  - 雙向變異寫在測試檔內：漏一張會紅；改清單順序或格式不紅。

### 2. 流程 `lib/app/backup.dart`

- **匯出**：
  - `export` 到暫存 → 讀位元組 → `FileDialogs.saveFile(name: 'fmp-backup-<UTC>.db', mimeType: 'application/vnd.sqlite3')` → 刪暫存。
  - 存好時提示位置；使用者取消就什麼都不說；失敗提示原因。
- **還原**：
  1. `FileDialogs.pickFile(extension: 'db')` 選檔。
  2. `stage`；被拒時依原因提示：
     - 「這份備份來自較新版的 FMP」；
     - 「這不是 FMP 的備份」；
     - 「備份檔損壞」。
  3. 確認框：
     - 列出備份裡的插件：名稱、版本、會連的網域，沿用插件頁列網域的寫法；
     - ADR 0030 §決定 8 的警告；
     - 「目前的資料會被取代；取代前會自動備份」。
     - 取消時刪掉暫存。
  4. `DatabaseBackups.create` 自動備份；失敗就停，提示原因，刪暫存，什麼都不取代。
  5. 從目前的資料庫讀 `CarriedState` → `carryOver` → `LogFile.flush` → `restoreStaged` → 重啟，照 M3 的平台重啟：Windows 自己重開；Android 沿用 M3 現有的做法。
- **Debug 頁的「從備份還原」**（`backups/fmp-*.db`）走同一條：以檔案 `stage` → 確認框 → 自動備份 → `carryOver` → 換檔 → 重啟。
- **`DataReset.restoreAndRestart`**：不再清 secure storage 與登入 WebView。介面若要改成吃 `StagedBackup`，連同 `debug_data_actions.dart` 一起改，舊路徑直接刪。
- **「重設資料」**不變，照舊清全部。

### 3. 設定頁「備份與還原」區

- 新的 `SettingsSection`（放在 `plugins` 與 `about` 之間），圖示選 Material 內建、不和其他分組或導覽列撞。
- 內容：
  - 一段說明：
    - 備份含歌單、設定、已安裝的插件等；
    - 不含登入、Cookie、快取、下載的檔案；
    - 還原會取代目前的資料、保留這台的登入。
  - 「匯出備份」與「從備份檔還原」兩個按鈕。
  - 進行中按鈕停用並顯示進度。
- 寫法照既有設定區與 ADR 0024。

### 4. 字串三語言（slang）

## 驗收

- **測試**（ADR 0034 §如何確認，以真的檔案資料庫）：
  - **匯出**：
    - 排除的表為空、裝置欄位為空、標記列不在；
    - 在 `plugin_storage` 寫一個假 cookie 值（例如 `fake-cookie-***-marker`）後匯出，檔案位元組裡找不到它；
    - 匯出的檔開得起來，其他表的筆數相同。
  - **stage**：
    - 較新版、`user_version` 為 0、損壞（標頭對但內容壞、標頭不對）的檔被拒絕，目前的資料庫不變（比對檔案位元組或各表筆數）；
    - 較舊版（例如 v17 的快照建的檔）migration 後開得起來；
    - 帶多餘 trigger 或 view 的檔被拒絕；
    - 插件清單與網域正確。
  - **還原**：
    - 還原後 `accounts` 是還原前這台的列；
    - `CredentialStore` 沒被清（`data_reset_test.dart` 跟著改）；
    - 輸出裝置、開發資料夾、`layout_state` 是這台的值；
    - 自動備份失敗時不取代；
    - 取消確認框時刪掉暫存、不取代。
  - **表的歸類閘門**：雙向變異。
  - **確認框的 widget 測試**：列出插件、網域、警告與取代說明；取消。
  - **設定區的 widget 測試**：匯出成功與取消、還原被拒的三種提示。
  - **guideline 測試**：設定區、確認框。
- 驗證指令：
  - `dart format --output=none --set-exit-if-changed lib test integration_test tool`
  - `build_runner` 後沒有實質變動
  - `dart run slang`
  - `dart analyze --fatal-infos`
  - `flutter analyze`
  - `flutter test` 全過
- **文件**：
  - `app/AGENTS.md` 的備份段落與閘門清單；
  - `.trellis/spec/app/data/index.md` 加「新表要歸類」，並指向閘門；
  - 需要的話，`.trellis/spec/app/ui/index.md`。
- **實機**（主對話做；Android 與 Windows，因為檔案對話框與重啟是平台各自的實作）：
  - 兩平台各一次：登入 `fmp-test`、建歌單 → 匯出 → 另一平台還原 → 確認框列出插件與網域 → 重啟後歌單在、`fmp-test` 仍登入、輸出裝置是這台的、`backups/` 有還原前的自動備份。
  - 較新版的檔（把 `user_version` 改大）被拒、資料不變。
  - Android SAF 能不能篩到 `.db`：篩不到就讓 `FileDialogs` 支援不篩選，交給 `stage` 驗內容（design §11）。這一條等實機結果再改。

## 不做

- 舊版 JSON 備份的匯入（M5）。
- 自動定期備份、合併匯入、可勾類別。
- 下載的檔案（M6）。
