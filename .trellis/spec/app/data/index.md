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
- 孤兒清理的查詢（`deleteOrphans`）是各參照者的 `NOT IN` 子查詢；加一張參照 `tracks` 的表時，同一個
  PR 把它加進去，並在 `queue_repository_test.dart` 的 `only unreferenced tracks are orphans` 加一個
  被它參照的案例。`queue_entries.track_key` 有索引（`queue_entries_track_key`）：`RESTRICT` 的檢查在刪每一列曲目時
  要查佇列，沒有索引就是每列掃一次。一萬首佇列加一萬個孤兒（清空一份大佇列之後）：沒有索引約 9.3 秒，
  有索引約 14 ms。之後參照 `tracks` 的表（歌單項目、下載紀錄）同理，加表時也要替它的
  `track_key` 建索引；`play_history` 已照辦（`play_history_track_key`）。
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

## 版面狀態（`layout_state_repository.dart`）

規則與閘門見 `app/AGENTS.md` § 資料層；design §3.4。

- 單列表，欄位全可空（沒記過）。repository 目前只有 `playerTab`；PR 19 接面板時在 `LayoutState` 與 `write` 加
  `panelExpanded`、`panelWidth`（表已有欄位，不必升 schema）。
- 不屬於任何設定組：不進 `settings/`、不進備份。UI 經 `layoutStateProvider`（`lib/ui/player/player_page.dart`）讀。
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
  寫入路徑在索引記上類別；用量（`usage`）自動分開算。
- 測試用 `test/data/cache/cache_harness.dart` 的 `CacheHarness`：暫存目錄當平台快取目錄、
  假 adapter 的媒體 client、`open` 開真的檔案資料庫。`at(minute, …)` 固定時間（最後存取以它
  排序），`read` 從索引讀並等最後存取寫完（`flutter_cache_manager` 不等那次寫入，不等的話測試
  結束時關庫會撞上它）。

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
