# 資料層（`app/lib/data/`）

加表、改 schema、寫 repository 時適用。規則（只有 `lib/data/` 碰資料庫、產生檔提交、
持久化格式）與閘門見 `app/AGENTS.md` § 資料層；為什麼選 drift、schema 原則，見
ADR 0010。這裡只寫怎麼做。

## 目錄

```
lib/data/
  database/
    app_database.dart        # @DriftDatabase、schemaVersion、MigrationStrategy
    app_database.g.dart      # build_runner 產生，提交
    tables.dart              # 所有 table
    converters.dart          # 列舉與時間的 TypeConverter（持久化格式）
    open_app_database.dart   # 開資料目錄裡的 fmp.db
  repositories/
    <名稱>_repository.dart   # 值型別＋repository，上層只看得到這一層
  cache/                     # 快取庫（cache.db），見下方「快取庫」
drift_schemas/app_database/  # 每版的 schema 快照（drift_schema_v<N>.json）
drift_schemas/cache_database/
test/drift/app_database/     # 快照測試；generated/ 是 drift_dev 產生的輔助碼
test/drift/cache_database/
```

`build.yaml` 的 `databases:` 讓 `drift_dev make-migrations` 找到資料庫類別，上面兩個
`drift_schemas/`、`test/drift/` 的位置是它的預設值。

## 寫一張表

- 類別名 `<名稱>Table`，`tableName` 寫 SQL 名稱（snake_case、複數）；
  `@DataClassName('<名稱>Row')`。`*Row` 只在 `lib/data/` 內用。
- 欄位用 `late final`（drift 文件現行寫法）。自我參照的 `check()` 要寫明型別：
  `late final IntColumn id = integer().check(id.equals(1))();`，否則推不出型別。
- 列舉：Dart 端是 `lib/domain/` 的 enum，資料庫存字串，轉換寫在 `converters.dart`，
  字串逐一寫死、讀到不認得的值拋 `FormatException`。不用 drift 的 `textEnum`：它存
  enum 的 `name`，改名就改了資料。
- 時間：`integer().map(const EpochMillisecondsConverter())()`（UTC epoch 毫秒）。不用
  `dateTime()`，它預設存秒。
- 關係交給資料庫：`references(..., onDelete: KeyAction.cascade)` 這類外鍵與
  `primaryKey` 的複合鍵。
- 單列設定表：`id` 加 `CHECK (id = 1)`，欄位全部 `nullable()`，空＝沒設定過
  （ADR 0011 §決定 7）。

## 寫一個 repository

- `final class <名稱>Repository`，建構子收 `AppDatabase`；本身就是上層注入的單位，
  不另外抽介面（要換掉就換一個接記憶體資料庫的實例）。
- 回傳自己的 `@immutable` 值型別（含 `==`／`hashCode`），不回傳 `*Row`、不讓 drift 型別
  （`Value`、companion）出現在公開方法的參數或回傳值。
- 只加有人呼叫的方法。
- 更新用 `insertOnConflictUpdate`（`ON CONFLICT DO UPDATE`），不要用
  `InsertMode.insertOrReplace`：REPLACE 會先刪列，觸發外鍵的 cascade，把子表一起清掉
  （`plugin_repository_test.dart` 的 `updating a plugin keeps its storage` 守著）。

## 改 schema（第二版起）

官方文件：https://drift.simonbinder.eu/migrations/（make-migrations）、
https://drift.simonbinder.eu/migrations/step_by_step/、
https://drift.simonbinder.eu/migrations/tests/。

1. 改 `tables.dart`，`AppDatabase.schemaVersion` 加一。
2. `dart run build_runner build --delete-conflicting-outputs`。
3. `dart run drift_dev make-migrations`。它會：
   - 存 `drift_schemas/app_database/drift_schema_v<N>.json`；
   - 產生 `lib/data/database/app_database.steps.dart`（`stepByStep`）；
   - 重產 `test/drift/app_database/generated/`，第一次還會產生
     `test/drift/app_database/migration_test.dart`（每對版本的空資料升級測試）。
4. 在 `AppDatabase.migration` 加 `onUpgrade`。ADR 0010 §決定 3 要求失敗整個回滾，而
   drift 不會自己把 `onUpgrade` 包進交易，所以以 `Migrator.runMigrationSteps` 的
   dartdoc（drift 2.35.0）為底，改兩處：
   - 順序：關外鍵（`PRAGMA foreign_keys` 在交易內無效，要在交易外）→
     `transaction(...)`，裡面依序跑 `m.runMigrationSteps(...)`、
     `PRAGMA foreign_key_check`（有結果就拋錯）、`PRAGMA user_version = <to>` →
     開外鍵。
   - 外鍵檢查放進交易、不只 debug：dartdoc 把它放在交易之後、只在 debug 斷言，那時
     已經提交，拋錯也回滾不了。
   - `user_version` 在交易內寫：drift 在 `onUpgrade` 回傳之後、交易外才寫版本
     （`engines.dart` 的 `_runMigrations`），中間中斷的話，下次開啟會在已升級的
     資料上再跑一次 migration。
5. 測試，每個 migration 都要有：
   - `migration_test.dart` 的空資料升級（make-migrations 產生，跑得過就好）；
   - 資料完整性：用 `verifier.schemaAt(N-1)` 與 `generated/schema_v<N-1>.dart` 的舊版
     資料類別寫入資料，升級後讀回；
   - **不改使用者設定過的值**（ADR 0010 §決定 3）：舊版先寫入使用者值，跑 migration，
     斷言值不變；只有沒設定過（空）的列可以被 migration 影響。
6. `schema_test.dart` 不用改：它比對的是「程式碼建出的 schema」與「最新快照」。

開發中改 schema 還沒發版時，一樣走上面的步驟；不要改已提交的快照。

Windows 上 checkout 出來的快照若是 CRLF，`make-migrations` 以字串比對會說「v<N> 已存在而且
不同」：先把那個快照轉成 LF（`sed -i 's/\r$//' <快照>`）再跑；內容沒變，git 不會顯示差異。

## 佇列與曲目（`queue_repository.dart`、`tracks_repository.dart`）

規則與閘門見 `app/AGENTS.md` § 資料層；欄位與理由見 design §3.1、§3.2。

- `QueueRepository.write` 是唯一的寫入口，一個 transaction 裡依序：套用 `QueueRangeEdit`（把位置
  `[from, from + removed)` 換成 `inserted`，其後平移）、改隨機名次、寫 `player_state`。插入、移除、移動、
  整份取代都寫成一個 range 編輯；誰算前後綴相同的列（`QueueStore.commonEnds`）在播放層，repository 只做
  「換掉一段」。
- 平移用兩個 `UPDATE`：先把受影響的列設成 `-(position + delta) - 1`，再設成 `-position - 1`。SQLite 逐列
  檢查主鍵，直接 `position = position + 1` 會在中途撞到下一列。
- 寫曲目一律 `TracksRepository.upsert`（`ON CONFLICT DO UPDATE`）；被佇列參照的列用 REPLACE 會因為
  `RESTRICT` 失敗。同一個曲目鍵在同一批裡出現多次時，最後一份的顯示資料留下。
- 孤兒清理的查詢（`deleteOrphans`）是各參照者的 `NOT IN` 子查詢，條件寫在 `TracksRepository._orphanCondition`，
  Debug 頁的 `countOrphans` 共用它；加一張參照 `tracks` 的表時，同一個
  PR 把它加進去，並在 `queue_repository_test.dart` 的 `tracks` 群組加一個被它參照的案例（照
  `a track in a playlist is not an orphan`：漏加時 `deleteOrphans` 撞上 `RESTRICT` 而拋錯）。
  `queue_entries.track_key` 有索引（`queue_entries_track_key`）：`RESTRICT` 的檢查在刪每一列曲目時
  要查佇列，沒有索引就是每列掃一次。一萬首佇列加一萬個孤兒（清空一份大佇列之後）：沒有索引約 9.3 秒，
  有索引約 14 ms。之後參照 `tracks` 的表（下載紀錄、匹配結果）同理，加表時也要替它的
  `track_key` 建索引；`play_history`、`playlist_entries` 已照辦（`play_history_track_key`、`playlist_entries_track_key`）。
- 播放歷史（`play_history_repository.dart`，schema v5）：`record` 一個 transaction 做 upsert 曲目、插入、
  `_trim`（`DELETE … WHERE id NOT IN (SELECT id … ORDER BY played_at DESC, id DESC LIMIT ?)`）；`page` 是 join
  `tracks` 的 `LIMIT/OFFSET`，順序鍵與索引一致，所以是索引掃描；`changes()` 聽 `tableUpdates`（不是 `watch()`，
  理由同快取庫的 `watchUsage`）。drift 的 `delete().go()` 沒刪到列時不通知串流，`customStatement` 寫的資料也
  不通知：測試用 `markTablesUpdated`。孤兒查詢已把 `play_history` 加進去，測試是
  `play_history_repository_test.dart` 的 `orphan cleanup keeps tracks the history refers to`。
  `make-migrations` 在 Windows 上可能對別的資料庫的 CRLF 快照報「已存在而且不同」並中止；app_database 的輸出
  （快照、steps、`generated/`）在它中止前已寫好，`migration_test.dart` 的新 import 要自己補。
- 測試：差量編輯以固定種子的隨機序列比對一個 `List`（`a seeded run of random edits…`）；
  一萬首整份取代的耗時（目前約 150–230 ms）印在測試輸出，超過 500 ms 要在 PR 描述說明。

## 歌單（`playlist_repository.dart`，schema v15）

規則與閘門見 `app/AGENTS.md` § 資料層的 `playlists`、`playlist_entries`。

- `entries` 是 `playlist_entries` join `tracks`，依（`position`, `id`）；`addTracks` 一個 transaction：`TracksRepository.upsert`、
  取歌單內 `max(position) + 1`、`batch.insertAll`。`moveEntries` 用 `batch.update` 逐項寫新位置（不像佇列有主鍵衝突，`position` 不唯一）。
  一萬首的歌單：`addTracks` 約 0.3–0.4 秒、`entries` 約 0.1–0.2 秒、`moveEntries` 約 0.1 秒（PR 1 在開發機的記憶體資料庫量一次，沒有測試重量）。
- Mix 欄位的 CHECK 跨 `kind` 與三欄，寫成表級 `customConstraints`，不掛在某一欄的 `check()`；它進快照與 steps，升級路徑由
  `migrateAndValidate` 比對。測試用 raw SQL 插入違規列，因為 repository 不開放 Mix 欄位；斷言比對 SQLite 的訊息
  （`RESTRICT` 以 trigger 實作，擴充碼不是 `SQLITE_CONSTRAINT_FOREIGNKEY`）。
- `create` 只建 `local`：匯入與 Mix 歌單要連同 `playlist_remote` 或 Mix 三欄一起寫，由建它們的 PR 另加寫入口。
- `overviews()`（歌單卡）是一個查詢：`playlists` left join 第一首的 `tracks`，首數與第一首的曲目鍵是相關子查詢（同一張表的兩個
  alias）。回 `Future`、畫面以 `changes()` 重讀，不給 `watch()` 版：join 了 `tracks`，每寫一次曲目都會觸發重查。

## 匯入歌單的遠端資料（`playlist_repository.dart`，schema v16）

規則與閘門見 `app/AGENTS.md` § 資料層的 `playlist_remote` 與 § 音樂庫。

- `createImported` 一個 transaction 寫 `playlists`（`kind = imported`）加 `playlist_remote`，（插件, 遠端 id）已存在回 `null`、什麼都不寫；`remote`／`findRemote`
  讀回 `PlaylistRemote`。
- 刷新的寫入全在 `PlaylistRefreshSession`（`beginRefresh` 回傳，同一個檔案）：`beginRefresh` 在一個 transaction 裡把 `refresh_generation` 加一並讀出現有項目，
  建立記憶體裡的比對佇列（鍵是 `remote_item_id` 或曲目鍵）；`writePage`、`apply`、`markPartial`、`markFailed`、`markStatus` 各一個 transaction，進去先檢查代際與
  `isCurrent`，過期什麼都不寫。新項目用一次 `batch.insertAll` 再依 `position`（接在現有最大值之後）讀回 id，不逐筆插入；`apply` 只更新 `position` 真的變了的項目。
- 值型別：`RemoteEntry`、`RemotePlaylistInfo` 在 `lib/domain/playlist.dart`（資料層不認得插件的 DTO，由 `lib/plugins/source_dto.dart` 的 `toEntry`／`toInfo` 轉過來）。
- 一萬首的完整刷新（PR 8a 在開發機的記憶體資料庫量一次，頁 50–100 首）：全新加入約 0.3–0.5 秒、全部比對到且不變約 0.3–0.4 秒、整張倒序約 0.3 秒。
- 測試：`playlist_remote_repository_test.dart`（建列、重複、代際、過期、`stored format`）；比對與套用的行為由 `test/library/` 的假插件端到端測。

## 榜單設定（`chart_settings_repository.dart`，schema v17）

規則與閘門見 `app/AGENTS.md` § 資料層的 `chart_settings` 與 § 排行。

- `ChartSettingsRepository`：`watch`（全部的列，工作與之後的設定頁都從 `chartSettingsProvider` 讀）、`setEnabled`（`insertOnConflictUpdate`，只寫 `enabled`，同一列的 `sort_order` 不動）、
  `removePlugin`（`PluginInstaller.remove` 的一步，沒有列也不出錯）、`setOrder`（設定頁拖曳後，`batch.insertAllOnConflictUpdate` 只帶 `sort_order`，所以 `enabled` 不動；一個 batch 一次寫入通知）。
- 列只在使用者動過才有：沒有列＝啟用、依預設順序。讀的人（`ChartJobs`、`chartEntriesProvider`）以插件的 `chartList` 為準，插件拿掉的榜單的列留著無害。
- 測試：`chart_settings_repository_test.dart`；migration 的 `expectChartSettingsSchema` 查主鍵與空值。

## 匹配結果（`match_results_repository.dart`，schema v18）

規則與閘門見 `app/AGENTS.md` § 資料層的 `match_results` 與 § 音樂庫的「外部匯入」。

- 讀：`MatchResultsRepository.find(originPluginId, originIds)` join `tracks`（`leftOuterJoin`，選定為空的也讀回），每 500 個 id 一次查，回以外部 id 為鍵的 `MatchResult`。
- 寫：只有 `PlaylistRepository.createFromMatches`，在外層的 `transaction` 裡呼叫 `create` 與 `addTracks`（drift 的巢狀 `transaction` 用外層那一個），再以一個 batch
  `insertAllOnConflictUpdate` `match_results` 與 `track_origins`。選定的曲目一定要在 `tracks` 裡（外鍵）：它們就是歌單的曲目，`addTracks` 已經 upsert 過；沿用的選定曲目
  本來就在（`RESTRICT`）。
- `MatchResult`（值型別，與 `MatchTargetSetting` 都在 repository 的檔案裡）的 `selected` 是 `TrackInfo`，寫的時候轉成曲目鍵。
- 孤兒查詢的子查詢對可空的欄位要 `WHERE <欄位> IS NOT NULL`（`NOT IN` 遇到 NULL 不成立）；以後再有可空的參照者照做。
- `source_settings` 的兩欄見上面「帳號與每音源設定」：`setMatchTarget` 用 `insertOnConflictUpdate` 只帶那一欄、`setMatchRanks` 一個 batch。
- 測試：`match_results_repository_test.dart`（三張表一起寫、`stored format`、覆蓋、外鍵失敗時整個沒寫、分批讀）；行為由 `test/library/external_import_test.dart` 的假插件端到端測。

## 插件（`plugin_repository.dart`）

規則與閘門見 `app/AGENTS.md` § 資料層的 `installed_plugins`（schema v7）。

- `PluginRepository.install` 是 upsert，`enabled` 不在 companion 裡所以更新不動它；要改啟用用 `setEnabled`。
  `source_index_url`、`checks_json` 每次安裝都以傳入值覆蓋。
- `PluginIndexRepository`（`plugin_indexes`）：`add` 用 `insertOrIgnore`，同網址保留最早的加入時間。

## 帳號與每音源設定（`account_repository.dart`）

規則與閘門見 `app/AGENTS.md` § 資料層的 `accounts`、`source_settings`（schema v8）與 § 帳號。

- 同一個檔案放 `AccountRepository`（`accounts`）與 `SourceSettingsRepository`（`source_settings`）：兩者都以插件 id
  為鍵，沒有外鍵到 `installed_plugins`，移除插件時由 `PluginInstaller.remove` 明確刪。
- `AccountRepository.upsert` 是 `insertOnConflictUpdate`（重新登入覆蓋）；`SourceSettingsRepository` 的欄位空＝沒設定過，
  `setBrowseAsLoggedIn(value: null)` 清回空。每個 setter 的 companion 只帶自己那一欄（`ON CONFLICT DO UPDATE` 只改給的欄位），所以三欄互不清掉
  （`account_repository_test.dart` 的 `match target and rank are written on their own`）。
- `status`、`last_refresh_result` 的字串寫在 `converters.dart`；測試 `account_repository_test.dart` 的 `stored format`
  直接查表斷言。

## 備份與還原（`database_backups.dart`）

規則與閘門見 `app/AGENTS.md` § 介面的 Debug 頁「備份、從備份還原與重設資料」。

- 不是 repository：`DatabaseBackups(database, 資料目錄, log)` 管檔案（`backups/fmp-<UTC>.db`、還原、刪檔），因為
  `VACUUM INTO` 與「關閉後換檔」都得在 `lib/data/`。`restoreStaged`、`erase` 結束後資料庫已關閉，呼叫端必須接著結束行程。
- 測試用真的檔案資料庫（`openAppDatabase` 開在 `Directory.systemTemp`），不是 `memoryDatabase()`：要驗檔案本身。
  另開備份檔數筆數會觸發 drift 的「同一個類別開多次」警告，測試開頭設 `driftRuntimeOptions.dontWarnAboutMultipleDatabases`。

- **加表時要歸類**：新表必須加進 `backup_format.dart` 的 `backupCarriedTables`（跟著備份走）或 `backupExcludedTables`（裝置專屬、帶秘密或只對這台有意義：版面、帳號、插件的 key／value、排程的時間），
  否則 `test/data/database/backup_format_test.dart` 的 `table classification gate` 紅。表裡只有某幾欄屬於這台的（輸出裝置、開發資料夾）加進 `backupDeviceColumns`。規則與流程見 `app/AGENTS.md` § 介面的「備份與還原」。
- 不帶走的表（`backupExcludedTables`）還原時逐表處理：`backupKeptOnDeviceTables` 的帶這台的列（`accounts`、`layout_state`），其餘清空。新增不帶走的表時要決定屬於哪一種，並補 `database_backups_test.dart` 的 `every excluded table is either kept from this device or emptied` 裡的插入語句（沒補就紅）。裝置欄位加進 `backupDeviceColumns`，匯出、`readCarriedState`、`carryOver` 都照常數走，`the carried state and carryOver cover every constant` 守著。
- 匯出、`stage`、`carryOver` 用原始 `sqlite3`（不經 drift）在背景 isolate 動備份檔，全部先 `PRAGMA trusted_schema = OFF`；備份檔是外來檔案，`stage` 先擋 trigger 與 view，最後由 App 自己重建 schema（只複製全新表有的欄位），所以還原後的 schema 一定是 App 自己定義的。
## 插件開發工具補的列（`plugin_repository.dart`，schema v10）

規則與閘門見 `app/AGENTS.md` § 資料層的 `installed_plugins.from_dev_folder`。

- `putDevFolderRow`（沒有列就插入標記列、有標記列就更新內容、有已安裝的列一個欄位都不動，回傳是不是標記列）與 `removeDevFolderRows`
  （刪標記列中不在 `keep` 的）各一個 transaction，只由 `PluginDevelopment` 呼叫；`install` 一律寫 `from_dev_folder = false`。

## 排程器的上次成功時間（`scheduler_runs_repository.dart`）

規則與閘門見 `app/AGENTS.md` § 資料層的 `scheduler_runs`（schema v11）與 § 排程器。

- `SchedulerRunsRepository`：`all()`（排程器啟動時一次讀完）、`record(jobId, at)`（upsert）。工作移除時不刪列：同 id 再登記時沿用。
  時間存毫秒，排程器寫入前也先取到毫秒，記憶體與資料庫的到期時間才一致。

## 電台（`radio_repository.dart`，schema v12）

規則與閘門見 `app/AGENTS.md` § 資料層的 `radio_stations` 與 § 電台。

- `RadioRepository`：`watch`／`list`（依 `sort_order`、再依 `id`）、`add`、`remove`、`reorder`、`updateStatus`，只加有人呼叫的方法。`add` 在
  transaction 裡先查（插件, 房間）再取 `max(sort_order) + 1`，重複回 `false`；刪掉中間的列後 `sort_order` 會有空洞，無妨（只比大小）。
- `RadioStation` 的封面存 `tracks.artwork_json` 同一種 JSON（重用 `TracksRepository.encodeArtwork`／`decodeArtwork`）。「查詢失敗」不是它的欄位。
- 測試：`radio_repository_test.dart`；`stored format` 直接查表斷言狀態字串與毫秒。

## 開發者設定（`developer_settings_repository.dart`）

規則與閘門見 `app/AGENTS.md` § 資料層的 `developer_settings`（schema v9）與 § 設定的「開發者」組。

- 單列設定表的一般形狀（`write`／`clear` 涵蓋四欄），另有 `turnOffDeveloperMode` 一次寫三欄（見 settings spec）。
- `log_level` 的字串在 `LogLevelSettingConverter`；Dart 端是 `lib/domain/developer.dart` 的 `LogLevelSetting`（只有 debug、info），
  對到門面的 `LogLevel` 在設定層（`Developer.minimumLogLevel`），資料層不碰 log。

## 版面狀態（`layout_state_repository.dart`）

規則與閘門見 `app/AGENTS.md` § 資料層；design §3.4。

- 單列表，欄位全可空（沒記過）。`LayoutState` 有 `playerTab`、`panelExpanded`、`panelWidth`，`write` 的參數也是這三個，
  沒給（`null`）的不動。
- 不屬於任何設定組：不進 `settings/`、不進備份。UI 經 `layoutStateProvider`（`lib/ui/layout/layout_state.dart`）讀，
  面板的寫入走同檔的 `rememberPanel`。
- 測試：`layout_state_repository_test.dart`；migration 的 `expectLayoutStateRules` 同時檢查單列 CHECK 與寬度上限。

## 快取庫（`lib/data/cache/`）

規則與閘門見 `app/AGENTS.md` § 資料層的「快取庫」；為什麼這樣做，見 ADR 0016 §決定 1–4。

```
lib/data/cache/
  cache_tables.dart          # cache_entries、CacheCategory 與它的轉換器
  cache_database.dart        # 第二個 @DriftDatabase；版本不同就清空重建
  cache_store.dart           # openCacheStore、CacheStore、cacheStoreProvider
  image_cache_manager.dart   # part：FmpImageCacheManager 與三個轉接
```

- 改 `cache_tables.dart`：`CacheDatabase.schemaVersion` 加一 → `build_runner` →
  `make-migrations`。它存新快照、重產 `test/drift/cache_database/generated/`，第二版起還會產生
  `lib/data/cache/cache_database.steps.dart` 與 `test/drift/cache_database/migration_test.dart`：
  steps 用不到（`onUpgrade` 是刪表重建），刪掉；migration_test 留著，它驗每個舊版開啟後的
  schema 等於新版（2026-10-02 以假的 v2 試過，刪掉 steps 也跑得過）。不寫資料完整性與「不改
  使用者值」的 migration 測試：快取沒有要保留的資料。
- 只有一版時 `make-migrations` 不產生 `generated/`，用
  `dart run drift_dev schema generate drift_schemas/cache_database/ test/drift/cache_database/generated/`。
- 新的類別：`CacheCategory` 加一個值、轉換器加一個寫死的字串，用它的 cache manager 或
  寫入路徑在索引記上類別；用量（`usage`）自動分開算。類別只是 `cache_entries.category` 的新字串，表沒變，
  不必動 `CacheDatabase.schemaVersion`；`watchUsage` 的結果多一個鍵，既有測試的期望要補（`CacheCategory.chart: 0`）。
  不經 cache manager 的內容（排行的 JSON）用 `CacheStore.put`／`get`／`remove`。
- 一律經 `openCacheStore` 開快取庫：同一個目錄的開啟一個接一個（等還在開、還在關的那一個，見 `app/AGENTS.md` 的「快取庫」）。不要改靠 `PRAGMA busy_timeout`：
  Linux 上 Dart VM 的取樣 profiler 會打斷 SQLite 的睡眠，`flutter test` 裡等不到設定的時間（CI 的 Linux 撞過）。測「等」用 `pendingCacheOpens`／`pendingCacheCloses`
  登記一個沒完成的 future，不要用計時放開的 `BEGIN EXCLUSIVE`——那測的是 SQLite 在各平台的睡眠，不是我們的保證。
- 測試用 `test/data/cache/cache_harness.dart` 的 `CacheHarness`：暫存目錄當平台快取目錄、
  假 adapter 的媒體 client、`open` 開真的檔案資料庫。`at(minute, …)` 固定時間（最後存取以它
  排序），`read` 從索引讀並等最後存取寫完（`flutter_cache_manager` 不等那次寫入，不等的話測試
  結束時關庫會撞上它）。

## 舊版資料匯入的暫存庫（`lib/data/import/`，schema v19）

規則與閘門見 `app/AGENTS.md` § 資料層的 `legacy_imports`、`legacy_playlist_ids`。

- `import_bundle.dart`（`ImportBundle` 與它的子型別）、`import_summary.dart`（`summary_json` 的型別）、`staging_import.dart`（寫入與驗證）、
  `legacy_import_failed.dart`（`LegacyImportStep`、`LegacyImportFailed`）、`legacy_imports_repository.dart`（讀與標「看過」）。`LegacyImportSource` 在 `lib/domain/legacy_import.dart`。
- `ImportBundle` 的設定欄位直接用既有的值型別（`AppearanceSettings`、`NetworkSettings`、`PlaybackSettings`、`LayoutState`），空欄位＝不寫；帳號用 `Account`，播放狀態用 `PlayerState`。
  新增一個要匯入的表時：bundle 加欄位、`StagingImport._writeAll` 寫、`_verifyCounts` 的 `expected` 加筆數（沒列在裡面的表必須是空的，所以漏加會紅）。
- 歌單、電台的 `sort_order` 與歌單項目的 `position` 由清單順序決定（0..n-1）；歷史依清單順序寫入，`played_at` 相同時後寫的算新。時間比對與寫入都到毫秒。
- 寫入的是新庫，所以用 `AppDatabase(NativeDatabase.createInBackground(file))` 的 `transaction`，不用 repository；驗證才用 repository（`PlaylistRepository.overviews`／`entries`／`remote`、
  `PlayHistoryRepository.page`、`RadioRepository.list`、`QueueRepository.readQueue`、`TracksRepository.find`）。驗證裡的 `LegacyImportFailed.reason` 不能帶曲名、歌單名：用固定字串，表名可以。
- 失敗清理：關庫、刪 `file`、`-wal`、`-shm`、`-journal`；刪不掉只寫 log（`legacy-import` tag），啟動時清 `legacy-import/` 由 PR 6 做。
- 測試：`test/data/import/`，資料在 `import_fixtures.dart`（時間都用 2020 年的固定值，寫入偷換成現在就紅）。壞資料用 `package:sqlite3` 直接改暫存檔（外鍵檢查預設關閉，才寫得進違規列）。
  一萬筆歷史＋一萬首佇列＋一萬首曲目的寫入與驗證時間印在測試輸出（開發機：寫入約 0.5–0.6 秒、驗證約 0.2–0.3 秒），不斷言。

## 測試

- 資料庫一律用 `test/support/memory_database.dart` 的 `memoryDatabase()`：和 App 同一個
  `AppDatabase`（外鍵、migration 策略都會跑），執行器是 `NativeDatabase.memory()`，
  測試結束自動關閉。不在 `lib/` 留測試用的建構子或開關。
- `watch` 的測試用 `StreamIterator` 先拿到第一個值再寫入；先寫再訂閱會漏掉初始值。
- 持久化格式用 `customSelect` 直接查表，斷言寫死的字面值（`stored format` 群組）。
- 真的開檔案的只有 `open_app_database_test.dart`，在 `Directory.systemTemp` 下跑。

## Quality Check

- `dart run build_runner build --delete-conflicting-outputs` 後 `git status` 沒有變動（CI 同一步）。
- `schema_test.dart` 綠；改過 schema 就有新快照與第 5 步的三種測試。
- `lib/data/` 以外沒有 drift 型別出現在 import 或公開 API。
