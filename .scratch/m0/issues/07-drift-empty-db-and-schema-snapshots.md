# 07: drift 空庫與 schema 快照

**What to build:** 新版的 drift 資料庫在四個平台都開得起來（還沒有業務資料表），並建立往後每次改 schema 都要走的流程：產生 schema 快照、寫升級測試。之後加資料表的票照這個流程走。

讀：plan §1.2、§1.3、§1.4、§3；brief §12；spec〈共同規則〉

**Blocked by:** 02

**Status:** done

- [x] 只有 `data/` import drift（依賴規則測試已涵蓋）；資料庫檔案路徑由 `platform/` 提供。
- [x] schema 版本 1 的快照已提交；產生快照與升級測試的指令寫進 `AGENTS.md` 或 `check.dart`，快照跟程式不一致時閘門會紅（造一次不一致證明會紅）。
- [x] 有一條升級測試的範本，下一個 schema 版本照抄即可。
- [x] 四平台實跑，啟動時開庫成功（log 或畫面為證）。
- [x] `dart run tool/check.dart` 完整版綠燈。

## Comments

### 決定與取捨

- 依賴：drift 2.35.4、drift_dev 2.35.3、build_runner 2.17.1、path_provider 2.1.6；sqlite3 3.9.1 由 drift 帶進來，不直接宣告。sqlite3 3.x 用 build hook 自帶 SQLite，`sqlite3_flutter_libs` 已 EOL（brief 事實 K14）。沒用 `drift_flutter`：它會在 `data/` 裡自己找路徑，票要求路徑由 `platform/` 給。
- 組裝：`platform/database_file.dart` 的 `databaseFile()`（和票 06 的 `log_directory.dart` 並列） 給 application support 目錄下的 `fmp.sqlite`；`main` 用它開 `AppDatabase.open`，先查一次 `PRAGMA user_version`（`storedSchemaVersion()`）讓庫真的開起來，再以 `appDatabaseProvider` override 進 `ProviderScope`。開不了庫時 `main` 在 `runApp` 前就拋錯；錯誤怎麼呈現留給之後的票。log 先用 `debugPrint`，票 06 的 log 門面合進來後再改。
- 快照與閘門：`make-migrations` 在同版本快照不同時會報錯，但版本加一卻忘了跑時不會有任何檢查，所以不直接拿它當閘門。閘門的 `schema snapshot (drift)` 用 `drift_dev schema dump` 出目前的 schema，跟版本最高的快照逐字比對；`migration_test.dart` 斷言 `schemaVersion` 等於最新快照的版本。兩者合起來，改表沒加版本、加版本沒產生快照都會紅。
- `*.g.dart` 照舊不進 git：閘門在 slang 後加 `codegen (build_runner)`，`winpc` 的 `build.ps1` 也加了這步。
- 升級測試範本：只有一個版本時 `make-migrations` 不產生測試，所以手寫 `test/drift/app_database/migration_test.dart`，結構照 drift_dev 之後會產生的範本（`make-migrations` 不覆寫已存在的這個檔）；`generated/` 用 `drift_dev schema generate` 產生，之後由 `make-migrations` 重寫。

### 驗證

- 造不一致：把 `schemaVersion` 改成 2、不跑 make-migrations → `migration_test.dart` 兩條紅（`Expected: <1> Actual: <2>`）；加一張 `Probes` 表、不加版本 → `schema snapshot (drift)` 紅並提示 `dart run drift_dev make-migrations`；還原後兩者都綠。改註解等無關內容不影響 dump。
- 四平台實跑（啟動前刪掉資料庫檔，啟動後讀回）：macOS 與 iOS 模擬器重建出 `fmp.sqlite`、`user_version` = 1、畫面是佔位頁；Android logcat 有 `database opened, schema version 1`，取出的檔案 `user_version` = 1；Windows 啟動後 `%APPDATA%\com.personal.fmp\FMP Dev\fmp.sqlite` 建立、`user_version` = 1、`foreground_is_fmp=True`。各平台的路徑寫進 plan §2。
- 完整閘門前兩次各有一步紅，原因都在環境：第一次是 Windows 的 integration_test 建置報 MSB8066（`winpc` 剛藍屏重開，之後的 build_runner 也出過一次編譯錯，記在 plan §2〈其他已知怪癖〉）；第二次是別的 session 停掉 adb daemon，Android 找不到模擬器（plan §2 已記）。第三次全綠：

```
ok   i18n (slang)
ok   codegen (build_runner)
ok   format
ok   analyze
ok   test
ok   schema snapshot (drift)
ok   doc gate
ok   build macos
ok   build ios
ok   build android
ok   build windows
ok   integration_test macos: integration_test/app_test.dart
ok   integration_test ios: integration_test/app_test.dart
ok   integration_test android: integration_test/app_test.dart
ok   integration_test windows: integration_test/app_test.dart
```

### code-review 未處理的發現

- 只有 v1 時，`migration_test.dart` 的「simple migrations」迴圈產生 0 條測試，要到第二個版本才真正跑；資料完整性測試只附 drift 文件的連結，沒有程式骨架（drift_dev 到時會印出建議）。
- 資料庫名稱與路徑分在 `build.yaml`、`tool/src/schema_gate.dart`（`databaseSource`、`snapshotDir`）、`test/drift/app_database/` 三處；只有一個資料庫，先不收攏。
- 加 path_provider 讓 Windows 多編一個 `jni` FFI 插件；閘門已在 `winpc` 建置通過。
- integration_test 用的是平台上真實的 dev 資料檔，Android 有 `--no-uninstall`，閘門多半驗到「重開舊檔」；「首次建立」由主機上的 `test/data/app_database_test.dart` 與上面的手動刪檔實跑涵蓋。
