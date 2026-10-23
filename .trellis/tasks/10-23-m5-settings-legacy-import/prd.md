# 設定頁：從舊版匯入（資料庫、JSON 備份）、`replaceWithImport`

## 目標

M5 PR 7（上層 `implement.md` § 7；design §3.2、§4.2、§6.1 第 2 點、§6.3、§7.4、§9「JSON 備份」「設定頁的取代」「設定頁」）：設定頁「備份與還原」區加「從舊版匯入…」，可選「舊版資料庫」（找得到時）或「舊版備份檔（.json）」。匯入是**取代**：換掉音樂庫與舊版有的設定，保留這台已安裝的插件、插件設定、排行設定與目前的登入；取代前自動備份；完成後重啟。

**使用者看得到**：Android 模擬器與 Windows 都要實機驗證。

範圍、做法都已由擁有者核准（2026-10-23，design §11 第 6、9 條）。計畫沒涵蓋、會改變行為、範圍或對外介面的決定，停下回報，不自行拍板。

## 現況（以程式碼為準）

- `lib/data/database/database_backups.dart`：`create()`（自動備份，:86）、`stageBytes`／`stageFile`／`_stage`（還原用，`_stage` 一開始刪 `backups/` 裡所有 `staged-` 開頭的檔）、`readCarriedState`／`carryOver`（還原的保留語意，**舊版匯入不用**）、`restoreStaged`（:447：舊檔改名成 `fmp.db.before-restore-<UTC>`、暫存檔改名成 `fmp.db`、失敗改回）。
- `lib/ui/settings/backup_controls.dart`：設定頁備份與還原區的按鈕；還原的確認框 `RestoreConfirmDialog`；重啟走 `appRestarterProvider`（Android 不會自己起來，照還原現有的提示）。
- PR 1–6 已在 `main`：`LegacyImport` 介面（`locate`、`stage`、`writeCredentials`）、`LegacyImporter`、`StagingImport.write`／`verify`、`LegacyConverter.convert`、`LegacySnapshot`、`replayLegacySettingsMigration`。
- 上層 `implement.md`「留下的後續」PR 2：`StagingImport.write` 會先刪目標檔、建全新的庫、設定整列插入；`verify` 要求「匯入包沒寫的表必須是空的」——設定頁的取代要另一個寫入入口。PR 1：JSON 備份讀取器**不能**沿用「看 `schemaVersion` 決定補不補舊 migration」。

## 需求

1. **`LegacyBackupReader`**（`lib/legacy_import/`，design §4.2）：舊 JSON 備份 v1–v5 → 同一個 `LegacySnapshot`（佇列、帳號、憑證、下載為空）。
   - 缺鍵走舊版預設；比 5 新的拒絕；同一版本號的欄位集合可能不同，逐鍵容錯。
   - 時間是沒有時區的本機時間字串，以匯入裝置的本機時區解讀。
   - v3 以前的六個每源鍵照舊版 `_readSourceSettings` 折疊（研究 L §4.5）。
   - 曲目以 `trackKeys` 參照；找不到曲目的項目略過並計數。
   - 舊版的格式與讀法以舊專案的備份程式碼為準（`lib/services/backup/` 一帶，凍結、只讀），測試註明來源檔。
2. **`LegacyImport.stageBackup(bytes, {progress})`**：讀 JSON → 轉換（`source: backup`、`backupVersion`、沒有憑證）→ 寫設定頁的暫存庫（第 3 條）。`stage` 在設定頁也走第 3 條（不是首次啟動的全新庫）。
3. **設定頁的暫存寫入**（design §6.1 第 2 點、§6.3 第 2 步）：
   - `VACUUM INTO` 目前的庫到 `<資料目錄>/legacy-import/staging-<UTC>.db`（不放 `backups/`）。
   - 在副本上清空音樂庫：`playlist_entries`、`playlist_remote`、`playlists`、`legacy_playlist_ids`、`match_results`、`track_origins`、`play_history`、`queue_entries`、`player_state`、`radio_stations`、`tracks`。
   - 設定組只覆寫 `ImportBundle` 有值的欄位，其他欄位保留這台的值；`source_settings.browse_as_logged_in` 以匯入值為準（三個音源）；`layout_state` 保留這台的值。
   - 帳號：這台有登入的平台保留這台的列，其餘寫匯入的列（§11 第 9 條）。
   - 保留不動：`installed_plugins`、`plugin_storage`、`plugin_indexes`、`chart_settings`、`developer_settings`、`scheduler_runs`、`legacy_imports` 的舊列（新增一列）。
   - 同一個 transaction 寫完 bundle；`verify` 改收「保留下來的列數」，取代「匯入包沒寫的表必須是空的」（首次啟動照舊）。
4. **`DatabaseBackups.replaceWithImport(File staging)`**（design §6.3）：自動備份（`create()`，失敗就停，同還原）→ 關庫、換檔：把 `restoreStaged` 的「舊檔改名、暫存檔改名成 `fmp.db`、失敗改回」**抽成共用的私有方法**，還原與舊版匯入都呼叫它 → 呼叫端寫憑證（`writeCredentials`，只補這台沒登入的平台）→ 重啟。
5. **UI**（design §7.4）：
   - 「從舊版匯入…」：選「舊版資料庫」（`locate()` 找到時才能選）或「舊版備份檔（.json）」（檔案對話框）→ 進度對話框（`stage`／`stageBackup`）→ 確認框：「會取代目前的歌單、曲目、歷史、佇列與電台，以及舊版有的設定；保留已安裝的插件、插件設定與這台目前的登入；取代前自動備份」，列出要匯入的筆數；JSON 備份另寫明「舊備份不含佇列，取代後佇列是空的」→ 換上 → 重啟。失敗時刪暫存、顯示原因、資料庫不變。
   - 找得到舊資料庫、且 `legacy_imports` 沒有紀錄時（例如首次匯入失敗後以空白資料啟動），按鈕旁一句提示。
   - 文案三個語言；沿用既有元件（`RestoreConfirmDialog` 的版面、設定頁的按鈕列），不新增頁面。
   - 重啟後結果對話框（PR 6）照樣出現一次。
6. **測試**（design §9）：
   - JSON：v1、v2、v4、v5 各一份手寫的合成檔（含沒升版就加的鍵、缺鍵、v3 以前的六個每源鍵）→ snapshot；比 5 新被拒。
   - 取代：取代後插件、插件設定、排行設定、`browse_as_logged_in`、`layout_state` 的值；帳號合併的三種情況（只有這台、只有匯入、兩邊都有）；驗證失敗時資料庫不變、暫存刪掉；自動備份失敗時不取代。**還原的既有測試照舊通過**（共用的換檔方法）。
   - widget：兩種匯入的確認框（JSON 那個寫明佇列會清空）、沒有紀錄時的提示、`locate()` 找不到時「舊版資料庫」不能選。
7. **文件**：`app/AGENTS.md` § 舊資料匯入（設定頁的取代語意、與還原共用與不共用的部分）、`.trellis/spec/app/data/index.md` § 備份與還原補一句。
8. **實機驗證**（`verify-on-device`；合成資料、重播、不連網、不裝插件）：
   - Windows dev（先備份 `userdata-dev`）：先建一點新版資料（例如一張本機歌單）→ 設定頁「從舊版匯入…」→「舊版資料庫」（`--fmp-legacy-dir` 指向合成舊庫）→ 確認框 → 重啟 → 結果對話框、歌單換成舊版的、自動備份在；再做一次「舊版備份檔」（合成的 JSON）。驗完還原。
   - Android 模擬器 dev：同上至少一種（JSON 備份經檔案對話框）。不碰 `com.personal.fmp`。

## 不做

「刪除舊版資料」（M9）；合併式匯入；真實資料的驗收（主對話在 PR 7 之後做）。**不讀擁有者的真實舊資料或憑證。**

## 驗收

- 測試全綠；`dart run build_runner build --delete-conflicting-outputs` 與 `dart run slang` 後沒有實質變動、`dart format --output=none --set-exit-if-changed lib test tool integration_test`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`。
- 兩平台的實機驗證照第 8 條。
- 回報：改了哪些檔、取代的實作方式（哪些表清、哪些合併）、共用換檔方法的改動、實機驗證的結果、計畫沒涵蓋而做了判斷的地方。
