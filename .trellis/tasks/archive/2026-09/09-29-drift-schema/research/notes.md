# drift 最小 schema：查證紀錄

- 查證日期：2026-09-29。
- 本次子代理環境沒有 context7／WebFetch 工具，改以 `curl` 直接抓官方頁面與 pub.dev
  JSON API，並讀 pub cache 裡 drift 2.35.0／drift_dev 2.35.0 的原始碼。

## 1. 版本（pub.dev JSON API，`latest`）

| 套件 | 版本 | 發佈 | 備註 |
|---|---|---|---|
| `drift` | 2.35.0 | 2026-09-09 | 依賴 `sqlite3 ^3.4.0` |
| `drift_dev` | 2.35.0 | 2026-09-09 | dev |
| `sqlite3` | 3.6.0 | 2026-09-13 | 依賴 `hooks`、`code_assets`、`native_toolchain_c` |
| `build_runner` | 2.16.1 | 2026-09-02 | `analyzer >=13.3.0 <15.0.0`，與 `fmp_lints` 釘的 13.3.0 相容 |
| `drift_flutter` | 0.3.1 | 2026-07-11 | 依賴 `path_provider`、`sqlite3_flutter_libs ^0.6.0+eol`、`sqlcipher_flutter_libs ^0.7.0+eol` |
| `sqlite3_flutter_libs` | 0.6.0+eol | 2026-02-15 | 空殼，沒有依賴 |

## 2. 開庫方式：`NativeDatabase.createInBackground`，不用 `drift_flutter`

- drift Setup（https://drift.simonbinder.eu/setup/）的「Dart (sqlite3)」依賴組合就是
  `drift` + `sqlite3` + `drift_dev` + `build_runner`；Flutter 版另列 `drift_flutter` +
  `path_provider`，並給了「Manual database setup」用 `NativeDatabase.createInBackground(file)`。
- Platforms 總覽（https://drift.simonbinder.eu/platforms/）：「Starting from drift version
  2.32.0 depending on versions 3.x of the sqlite3 package, no further setup is required and
  an up-to-date copy of SQLite will automatically be bundled with your app」；「It is no
  longer necessary to depend on sqlite3_flutter_libs or sqlcipher_flutter_libs」。
- Native 頁（https://drift.simonbinder.eu/platforms/vm/）：`NativeDatabase.createInBackground`
  由 drift 開背景 isolate 跑 SQLite，建議行動裝置使用。
- sqlite3 `UPGRADING_TO_V3.md`（https://github.com/simolus3/sqlite3.dart/blob/main/UPGRADING_TO_V3.md）：
  不再依賴 `sqlite3_flutter_libs`；`applyWorkaroundToOpenSqlite3OnOldAndroidVersions` 可以
  移除；原生庫改由 hooks 打包，預設從 GitHub releases 下載預先編譯的版本。
- sqlite3 `doc/hook.md`：預設編譯選項含 `SQLITE_TEMP_STORE=2`（暫存放記憶體）。drift 文件提到
  Android 要設 `sqlite3.tempDirectory` 避免複雜查詢 OOM，那是針對暫存寫檔的情況；M1 的查詢
  很小，且預設二進位把暫存放記憶體，所以不設（也就不必在 `lib/data/` 碰 `path_provider`）。

**決定**：`drift` + `sqlite3` 3.x，`NativeDatabase.createInBackground(File(<資料目錄>/fmp.db))`。
不用 `drift_flutter`：它的價值是用 `path_provider` 決定目錄，而目錄已由平台層
（`AppPlatform.dataDirectory`）決定；它還會把 EOL 的 `sqlite3_flutter_libs` 空殼帶進依賴樹，
PRD 要求不用。

## 3. 外鍵

- drift 文件的 Migrations 頁 `beforeOpen` 範例與 `Migrator.runMigrationSteps` 的 dartdoc
  （drift 2.35.0，`lib/src/runtime/query_builder/migration.dart`）都在 `beforeOpen` 或
  migration 後執行 `PRAGMA foreign_keys = ON`。
- `GeneratedDatabase.beforeOpen`（`lib/src/runtime/api/db_base.dart`）的順序：onCreate／
  onUpgrade → `MigrationStrategy.beforeOpen`。所以放在 `beforeOpen`，每次開啟都設，
  migration 期間維持關閉（drift 建議 migration 時關外鍵）。
- drift **不會**自己把 `onUpgrade` 包進交易（同檔）。ADR 0010 §決定 3 的「失敗整個回滾」要
  照 `runMigrationSteps` dartdoc 的寫法自己包：關外鍵 → `transaction(runMigrationSteps)` →
  `PRAGMA foreign_key_check` → 開外鍵。寫進 `.trellis/spec/app/data/index.md`，第一個
  migration 時做。
- 檢查時修正：dartdoc 的 `foreign_key_check` 在交易提交之後、只在 debug 斷言，拋錯已回滾
  不了；而 drift 寫 `user_version` 在 `onUpgrade` 回傳之後、交易外
  （`lib/src/runtime/executor/helpers/engines.dart` 的 `_runMigrations`）。所以 spec 改成
  外鍵檢查與 `PRAGMA user_version = <to>` 都放進同一個交易。

## 4. schema 快照與驗證

- Schema exports（https://drift.simonbinder.eu/migrations/exports/）：`drift_dev schema dump`
  存 `drift_schema_vN.json`；「We recommend exporting the initial schema once」。
- Migrations 總覽（https://drift.simonbinder.eu/migrations/）：推薦 `make-migrations`；
  `build.yaml` 的 `databases:` 設資料庫位置，預設 `schema_dir: drift_schemas/`、
  `test_dir: test/drift/`。
- 讀 `drift_dev` 2.35.0 `lib/src/cli/commands/make_migrations.dart`：只有一個版本時它只寫
  快照（`writer.schemas.length == 1` 就 `continue`），不產生測試輔助碼；第二版起才產生
  steps 檔、`generated/schema_v*.dart` 與 `migration_test.dart`。
- 所以 v1：`dart run drift_dev make-migrations`（存到 `drift_schemas/app_database/`）＋
  `dart run drift_dev schema generate drift_schemas/app_database/ test/drift/app_database/generated/`
  （產生 `GeneratedHelper`）。之後每版只要 `make-migrations`，目錄已對齊它的預設。
- `make-migrations` 產生的 `migration_test.dart` 只測「舊快照升級後等於新快照」，不比對
  **程式碼**與最新快照：程式碼改了、卻沒 bump 或沒存快照時它照樣綠。所以另寫
  `test/drift/app_database/schema_test.dart`：用記憶體資料庫讓程式碼的 onCreate 建表，
  `SchemaVerifier.migrateAndValidate(db, schemaVersion)` 與快照比對
  （`drift_dev/lib/src/services/schema/verifier_common.dart`：reference 取自
  `startAt(expectedVersion)`，actual 取自 db 本身）；再加一個多一欄就必須拋
  `SchemaMismatch` 的反例，證明比對不是空轉。
- 測試寫法（https://drift.simonbinder.eu/testing/）：`DatabaseConnection(NativeDatabase.memory(),
  closeStreamsSynchronously: true)`。

## 5. 表的寫法

- Tables 頁（https://drift.simonbinder.eu/dart_api/tables/）：「In table classes, columns are
  defined as late final fields」。`check()` 自我參照時 `late final` 要寫明型別
  （實測：不寫會 `top_level_cycle`；用 getter 寫法則觸發 `recursive_getters` info，
  `--fatal-infos` 會紅）。
- nullable 欄位接非 nullable 的 `TypeConverter`，drift 產生 `NullAwareTypeConverter.wrap`
  （見產生的 `app_database.g.dart`），converter 只處理非空值。
- `dateTime()` 預設存 unix 秒；ADR 0010 要 UTC epoch 毫秒，所以用 `integer()` + converter。

## 6. 產生檔

- drift 產生的 `app_database.g.dart` 開頭有 `// ignore_for_file: type=lint`，`fmp_lints`
  對它也沒有診斷；`dart analyze --fatal-infos` 乾淨，所以 `analysis_options.yaml` 不排除。
- 根目錄 `.gitignore` 有 `*.g.dart`（舊專案）；`app/.gitignore` 以 `!*.g.dart` 覆寫。
- 刪掉 `.dart_tool/build` 後在已有產生檔的狀態下跑 `dart run build_runner build`，不需要
  `--delete-conflicting-outputs`，也不產生差異（CI 的情況）。

## 7. 自我檢查（變異）

手動做過、沒有編碼成測試的兩個變異，確認測試抓得到：

- 拿掉 `beforeOpen` 的 `PRAGMA foreign_keys = ON`：四個測試紅（pragma、開檔、cascade、
  外鍵拒絕）。
- `PluginRepository.install` 改成 `InsertMode.insertOrReplace`：`updating a plugin keeps its
  storage` 紅（REPLACE 觸發 cascade）。
