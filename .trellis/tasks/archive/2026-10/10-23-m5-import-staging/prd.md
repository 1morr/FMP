# 匯入包、暫存庫寫入與驗證、schema v19

## 目標

M5 PR 2（上層 `implement.md` § 2；design §2.1、§6.1、§6.2、§6.4、§9）：在 `lib/data/import/` 定義新格式的匯入包 `ImportBundle`，把它寫進**全新的暫存庫**（保留原始時間）並驗證；加 schema v19 的兩張匯入紀錄表。這是首次啟動那一種（全新的庫）；設定頁的取代（在現有庫的副本上清掉再寫）是 PR 7。

範圍、做法都已由擁有者核准（2026-10-23）。計畫沒涵蓋、會改變行為、範圍或對外介面的決定，停下回報，不自行拍板。

## 現況（以程式碼為準）

- `lib/data/database/app_database.dart`：`schemaVersion => 18`；表在 `tables.dart`；改 schema 的流程在 `.trellis/spec/app/data/index.md` §「改 schema（第二版起）」。
- `lib/data/database/backup_format.dart`：`backupExcludedTables`／`backupCarriedTables`，`test/data/database/backup_format_test.dart` 的歸類閘門對著 `AppDatabase.allTables`。
- `lib/data/repositories/database_inspector.dart`：`DatabaseInspector.check`（`integrity_check`、`foreign_key_check`、孤兒曲目數，:163 用 `TracksRepository.countOrphans()`）。
- 寫入要保留 `created_at`、`updated_at`、`played_at`、`added_at`、`last_refreshed_at` 的原值，要批次寫歷史、寫 `playlist_entries.unavailable`；現有 repository 沒有這些入口（上層 `research/target-schema.md` §10），所以 `StagingImport` 直接用 drift 的表寫。

## 需求

1. **`ImportBundle`**（`lib/data/import/import_bundle.dart`）：純值、以**新版的語彙**寫（`TrackInfo`、`PlaylistKind` 這類既有型別，設定用既有的值型別），不出現任何舊版概念（舊 id 除外，見下）。內容對應 design §5 會寫的每張表：
   - 曲目（含 `part_index`、`parent_title`、封面）；
   - 歌單（`kind`、Mix 欄位）、`playlist_remote`、項目（順序、`unavailable`）；每張歌單帶一個可空的 `legacyPlaylistId`，給 `legacy_playlist_ids`；
   - 佇列項目與 `player_state`；播放歷史；電台；`track_origins`；
   - 帳號列（`accounts`）。**憑證不在 bundle 裡**（只在記憶體，由 PR 4 處理）；
   - 設定：每個設定組的欄位都是可空的，空＝不寫（新版預設生效）；`source_settings.browse_as_logged_in`（每個插件）；`layout_state`；
   - 匯入紀錄的欄位：`source`（`database`／`backup`）、`legacySchemaVersion`、`backupVersion`、`summary`（每個 collection 的 read／written／skipped{理由: 筆數}、不匯入的設定清單、需要重新登入的平台）。summary 的型別要能序列化成 `summary_json`。
   - 欄位名照目標表的欄位；先看 `tables.dart` 與既有 repository 的值型別再定，能用既有型別就不另造。PR 3 的轉換器會填它，所以介面要完整，但不為想像的需求加欄位。
2. **schema v19**（design §6.4）：
   - `legacy_imports`：`id` int PK 自增、`source` text、`imported_at` epoch ms、`legacy_schema_version` int?、`backup_version` int?、`summary_json` text、`acknowledged` bool（預設 false）。
   - `legacy_playlist_ids`：`legacy_import_id`（FK `legacy_imports`，`ON DELETE CASCADE`）、`legacy_playlist_id` int、`playlist_id`（FK `playlists`，`ON DELETE CASCADE`）；PK（`legacy_import_id`, `legacy_playlist_id`）。
   - 照 spec 的改 schema 流程：schema dump、migration step、升級測試、新庫有表。
   - 兩張都加進 `backupExcludedTables`，**不**加進 `backupKeptOnDeviceTables`（還原另一台的備份後，這台的匯入紀錄與歌單對照都不再成立）；`backup_format_test.dart` 照舊通過。
3. **`LegacyImportsRepository`**（`lib/data/repositories/` 或 `lib/data/import/`，照現有慣例）：讀最新一列未看過的（結果對話框用）、標成看過、有沒有任何紀錄（設定頁提示用）。寫入由 `StagingImport` 在同一個 transaction 做。
4. **`StagingImport.write`**（design §6.1）：
   - 參數：`ImportBundle`、暫存庫的 `File`（呼叫端給 `<資料目錄>/legacy-import/staging-<UTC>.db`；**不放 `backups/`**，原因見 design §6.1）、匯入時間。
   - 以 `AppDatabase` 建全新的庫，**同一個 transaction** 寫完整個 bundle、一列 `legacy_imports`、`legacy_playlist_ids`。歷史一萬筆一次寫（批次）。
   - 任何一步失敗：關庫、刪暫存檔（含 `-wal`、`-shm`），拋 `LegacyImportFailed(step, reason)`。`step` 是列舉（至少 `write`、`verify`；PR 6 的流程會加 `read`、`convert`、`swap`、`credentials`，型別放在 `lib/app` 與 `lib/legacy_import` 都 import 得到的地方：`lib/data/import/`）。`reason` 是一句不含使用者資料的英文。
5. **`StagingImport.verify`**（design §6.2）：全部通過才算成功；任何一項失敗刪暫存檔並拋 `LegacyImportFailed(verify, …)`：
   1. 筆數：每張匯入的表的列數等於 bundle 的筆數；
   2. 抽樣：曲目、歌單（含項目順序）、歷史、電台各隨機抽 50 筆（不到就全部），**以 repository 讀回**比對每個欄位；隨機數可注入，測試固定種子；
   3. `DatabaseInspector.check` 的 `integrity_check` 為 ok、`foreign_key_check` 為空；
   4. 孤兒曲目為 0。
   成功時關庫，暫存檔留給呼叫端換上。
6. **測試**（design §9「暫存庫」「中途失敗」「schema v19」）：
   - 真的檔案資料庫（spec 的測試慣例）：寫入後筆數與時間原值相同；`legacy_imports` 與 `legacy_playlist_ids` 寫入正確（`legacy_playlist_ids` 的讀者是 M6，閘門就是這個寫入測試）。
   - 注入壞資料：讓外鍵檢查失敗、讓抽樣比對不符（例如寫入後以 SQL 改一列）、讓寫入中途拋錯 → 拋 `LegacyImportFailed`，暫存檔與 `-wal`／`-shm` 都不在。
   - 一萬筆歷史＋一萬首佇列的寫入與驗證時間：量一次，寫進回報（PR 描述用），不寫成會因機器快慢而紅的斷言。
7. **文件**：`app/AGENTS.md` § 資料層加 `legacy_imports`、`legacy_playlist_ids` 與「暫存庫不放 `backups/`」；`.trellis/spec/app/data/index.md` 加一節（schema v19，寫法同其他表的節）。

## 不做

讀舊資料、轉換器、憑證、換上（rename）、設定頁的取代、UI（PR 1、3–7）。

## 驗收

- 上面的測試全綠；`dart format --output=none --set-exit-if-changed .`、`build_runner` 後沒有實質變動、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 通過。
- 回報：改了哪些檔、`ImportBundle` 的形狀（列出每個型別與欄位）、一萬筆的時間、計畫沒涵蓋而做了判斷的地方。
