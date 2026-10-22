# 舊版 Isar 模型（凍結）

舊版（repo 根目錄的 `lib/`，已凍結）把資料存在 Isar；M5 的舊資料匯入要用這 11 個
collection 與 2 個 embedded 的 schema 開舊資料庫的副本來讀。

- 模型自舊 `lib/data/models/` 複製，**只留欄位與 Isar 註記**。舊版沒標 `@ignore` 的
  getter（`Track.sourcePageKey`、`PlayQueue.length` 等）會被 Isar 存成欄位，是 schema 的
  一部分，所以留成 getter；推導邏輯不用搬，匯入也不讀它們。
- `*.g.dart` 是提交的產生檔，**這個 schema 已凍結，之後不再產生**。不要在 `app/` 跑
  `isar_community_generator`：它的 analyzer 版本和 workspace 衝突（ADR 0010），也沒有
  理由重產。
- 閘門：`test/legacy_import/legacy_schema_test.dart` 比對 `*.g.dart` 的 collection 名、schema
  id、property 的 id／名稱／型別、index、embedded，和 `test/legacy_import/fixtures/legacy_schema.json`
  （由舊專案的 `*.g.dart` 產生一次）。改了模型或重產讓 id 或型別變了，測試就紅。

## 產生 `*.g.dart`（一次性，已做過）

在 workspace **外**的暫存套件（`<暫存目錄>/isar-gen/`）：

1. `pubspec.yaml`：`isar_community: 3.3.2`；dev：`build_runner`、`isar_community_generator: 3.3.2`。
2. 把這個目錄的 `*.dart`（不含 `schemas.dart`、`schema_description.dart`）複製進它的 `lib/`。
3. `dart run build_runner build`，把產生的 `*.g.dart` 複製回這個目錄，`dart format`。

## 產生 fixture（一次性，已做過）

fixture 要從**舊專案**的 `*.g.dart` 產生，不是從這裡的檔案：

1. 暫存套件（package 名 `fmp`）放舊專案的 `lib/data/models/`（含 `*.g.dart`）與編得過所需的
   stub，再把這個目錄的 `schema_description.dart` 複製進它的 `lib/`。
2. 寫一個測試呼叫 `describeLegacySchemas([TrackSchema, … 11 個])`，以
   `JsonEncoder.withIndent('  ')` 寫成 `legacy_schema.json`，加結尾換行。
3. 複製到 `app/test/legacy_import/fixtures/legacy_schema.json`。

舊專案之後不會再變；fixture 也不重產。
