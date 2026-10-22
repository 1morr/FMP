# 舊 Isar 模型與讀取器

## 目標

M5 PR 1（上層 `implement.md` § 1；design §0.3、§2.1、§2.3、§4.1、§9）：把舊版的 Isar 資料庫**先複製再開副本**讀成純值的 `LegacySnapshot`，原檔一個位元組都不動。附合成舊庫的產生工具與只印筆數的計數工具。

範圍、做法都已由擁有者核准（2026-10-23）。計畫沒涵蓋、會改變行為、範圍或對外介面的決定，停下回報，不自行拍板。

## 現況（以程式碼為準）

- `app/pubspec.yaml` 還沒有 `isar_community`；lint `fmp_layer_imports`（`app/packages/fmp_lints/lib/src/rules/layer_imports.dart`）已經把 `isar_community` 的擁有者設成 `lib/legacy_import`（:13-14），`lib/legacy_import` 在 `sealedDirectories`（:118）。PR 1 不改封住的設定（`lib/main.dart` 的例外在 PR 6）。
- 舊版的模型在 repo 根目錄 `lib/data/models/`（11 個 collection、2 個 embedded，附 `*.g.dart`），舊 migration 在 `lib/data/database/database_migration.dart`。舊專案凍結，只讀不改。
- 規劃時的探針：`<暫存目錄>/isar-spike/`（不在 repo 裡，實際路徑在派工的 prompt）是 workspace 外的 package，`lib/data/models/` 有複製的模型與以 `isar_community_generator` 3.3.2 產生的 `*.g.dart`，`test/spike_test.dart` 示範測試裡怎麼載入 `libisar` 並開庫。紀錄見上層 `research/isar-copy-spike.md`。可以直接沿用它的產生結果，但要確認與舊專案的 `*.g.dart` schema 一致（下面的凍結閘門）。
- 測試設定 `app/test/flutter_test_config.dart` 目前載入 QuickJS（`support/quickjs.dart`），找不到就拋錯；libisar 照同樣做法。
- CI 的 `app/` 單元測試在 **Linux** 跑；確認 `isar_community_flutter_libs` 3.3.2 有 Linux 的 `libisar.so` 可載入。沒有的話停下回報。

## 需求

1. **依賴**：`isar_community`、`isar_community_flutter_libs` 固定 `3.3.2`（不加 `^`；舊庫格式）。上 pub.dev API 核對一次版本。`isar_community_generator` 不進 workspace（analyzer 衝突，ADR 0010 後果）。
2. **`lib/legacy_import/isar/`**：舊 11 個 collection 與 2 個 embedded 的模型，自舊 `lib/data/models/` 複製，**只留欄位與 Isar 註記**（沒標 `@ignore` 的 getter 在舊版會被持久化，它們是 schema 的一部分，保留成欄位或 getter 讓 schema 不變；推導邏輯不用搬）。提交的 `*.g.dart` 在 workspace 外產生；`lib/legacy_import/isar/README.md` 寫產生步驟，並寫明舊 schema 已凍結、之後不再產生。產生檔照 repo 慣例排除在 analyzer／format 之外（看現有的 `*.g.dart` 怎麼處理）。
3. **凍結閘門** `test/legacy_import/legacy_schema_test.dart`：
   - `test/legacy_import/fixtures/legacy_schema.json` 由**舊專案**的 `*.g.dart` 產生一次（collection 名、schema id、每個 property 的名稱與型別、index、embedded）。產生腳本放 `tool/` 或寫在 README，說明一次性。
   - 測試比對提交的 `lib/legacy_import/isar/*.g.dart` 的 schema 物件與 fixture 相同。
   - 雙向變異寫在測試檔內（`.trellis/spec/app/testing/index.md`）：改一個 property 名、改型別 → 紅；fixture 的鍵順序或 JSON 格式不同 → 不紅。
4. **`LegacySnapshot`**（`lib/legacy_import/legacy_snapshot.dart`）：純值、不帶任何 Isar 型別，涵蓋全部 11 個 collection，包括 M6–M8 會用到的欄位（`Track.playlistInfo[]` 含 `downloadPath`、`DownloadTask`、`LyricsMatch`、歌詞與桌面設定的欄位）。推導值與過期值（`audioUrl`、`audioUrlExpiry`、被持久化的 getter、`LyricsTitleParseCache`）不讀。值照 Isar 讀到的原樣（`minLong`、NaN、false 這些型別預設不在這裡清理，§5 的轉換器處理）。
5. **`LegacyDatabaseReader`**（design §4.1 第 2–4 步）：
   - 介面：給舊庫檔 `File` 與工作目錄的根 `Directory`（`<資料目錄>/legacy-import/`），回 `LegacySnapshot`。找舊庫的位置是 PR 6 的 `LegacyDataLocator`，這裡只收路徑。
   - 複製到 `<根>/work-<UTC>/fmp_database.isar`（lock 檔不複製）→ 實例名 `fmp_database`、完整 11 個 schema、`maxSizeMiB: 2048`、不壓縮、開副本 → 每個 collection `findAll` → 關閉 → 刪工作目錄。成功與失敗都刪。
   - 失敗拋一個帶步驟（`copy`／`open`／`read`）的例外型別，訊息不含使用者資料。
   - log 只寫步驟與每個 collection 的筆數（`.trellis/spec/app/logging/index.md`）。
6. **舊 migration 補做**（design §4.1 最後一段）：`schemaVersion < 4` 時，以純函式在 snapshot 的設定上重做舊版的 0→4 與 `repairSettingsInvariants`（照舊 `database_migration.dart` 移植，只改 snapshot，不碰檔案）。
7. **合成舊庫**：
   - 測試用的 helper 以舊模型寫一份合成舊庫（每個 collection 幾筆，含缺欄的型別預設值、重複鍵、懸空 id、兩段與三段的 B 站鍵、多 P 與單 P 的 B 站曲目）。
   - `tool/legacy_fixture.dart`：把同一份合成舊庫寫到指定資料夾的 `fmp_database.isar`（給之後的實機驗證用）。
8. **`tool/legacy_counts.dart`**：參數是一份舊庫**副本**的路徑，用 `LegacyDatabaseReader` 讀，只印每個 collection 的筆數與 `schemaVersion`，不印任何內容。
9. **測試**（design §9 前四列）：
   - 讀取器不寫舊檔：合成舊庫的 SHA-256 與修改時間讀前讀後相同，工作目錄已刪；開檔失敗（壞檔）時同樣不留工作目錄。
   - 讀取器讀全：合成舊庫 → snapshot 的筆數與值。
   - 舊 migration：`schemaVersion` 0、1、3 的合成設定，補做後等於舊版跑完 migration 的值。
   - 凍結閘門（上面第 3 條）。
10. **建置**：`flutter build apk --flavor dev --debug`，以 `zipalign -c -P 16` 與 LOAD 段 `p_align` 確認 `libisar.so` 的 16KB 對齊（ADR 0010 後果記了 M1 的做法）；`flutter build windows --flavor dev --debug` 能建。plugin registrant 因 `isar_community_flutter_libs` 改變是預期的，要提交；只有換行差異的還原。
11. **文件**：`app/AGENTS.md` 新節「舊資料匯入」：先複製再開副本（為什麼）、凍結的 schema 與它的閘門、`libisar` 在測試的載入。只寫查不到的契約，每條寫出閘門。

## 不做

轉換器、找舊資料的位置、憑證、JSON 備份、UI、dev 入口（PR 3–7）。**不讀擁有者的真實資料**（`Documents\FMP`、`%APPDATA%\com.personal\fmp`、模擬器上的 `com.personal.fmp`）：真實副本的計數由主對話在合併前另外做。

## 驗收

- 上面的測試全綠；`dart format --output=none --set-exit-if-changed .`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 通過；動到 lint 時 `dart run tool/lint_sentinel.dart`。
- Android dev APK 的 `libisar.so` 16KB 對齊；Windows dev 建置成功。
- 回報：改了哪些檔、libisar 在 Linux CI 的載入方式、16KB 檢查的輸出、計畫沒涵蓋而做了判斷的地方。
