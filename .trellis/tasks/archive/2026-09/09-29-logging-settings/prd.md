# 設定、log 門面與遮蔽（M1 PR 6）

父任務：`../09-28-m1-skeleton-tracer`（design §3 的「log 檔格式」；implement「6.」）。

依據：
- ADR 0011 §決定 1–3、7：門面、輸出、遮蔽函式、設定分組；
- ADR 0025 §決定 3：JSON Lines 欄位；
- ADR 0013 §決定 4：Riverpod 自動重試全域關閉。

## 做什麼

1. **Riverpod**：`flutter_riverpod` 3.x（pub.dev 最新 stable）。
   - 不用 `riverpod_generator`：M1 的 provider 少，手寫即可，也少一套 codegen。
   - `main()` 以 `ProviderScope` 包住 App，全域 `retry` 關閉（ADR 0013 §決定 4），並有測試斷言。
   - 開好的資料庫與資料目錄由 `main()` 以 `overrides` 注入 provider，其他地方不自己開庫。
   - `app/analysis_options.yaml` 重新開啟 `riverpod_lint` 的 `missing_provider_scope`。PR 3 暫時關閉它，並在 AGENTS.md 註記。
2. **外觀設定**：`lib/settings/appearance_settings.dart`。
   - 一個 Notifier，監看 `appearance_settings` 那一列，只寫改動的欄位（ADR 0011 §決定 7）。
   - 對外的值是「套用預設後」的結果：
     - 主題模式沒設定過時為 `system`；
     - 語言沒設定過時，跟隨系統語言。系統語言屬於 zh-TW／zh-CN／en 之一就用它，否則用 `zh-TW`（ADR 0024 §決定 7 的 base locale）。系統是 `zh-HK`、`zh-Hant` 時對到 zh-TW，`zh-Hans`、`zh-SG` 對到 zh-CN。
   - 同時提供「使用者是否設定過」，讓設定頁之後能顯示「跟隨系統」。
   - 測試（ADR 0011 §如何確認）：
     - 寫入使用者值後，把程式預設改掉，讀到的仍是使用者值；
     - 沒設定的欄位讀到新預設；
     - 系統語言各種情況的對應。
3. **log 門面**：`lib/core/logging/`。
   - 單一入口，參數：訊息、tag、error、stackTrace、結構化欄位（`Map<String, Object?>`）。層級：`debug`、`info`、`warning`、`error`。
   - 門面先遮蔽，再交給 `talker`。`talker` 只用它的歷史與分派，版本以 pub.dev 為準。
   - **輸出**（ADR 0011 §決定 2）：
     - 記憶體歷史最近 1,000 筆；
     - 檔案在資料目錄的 `logs/`，JSON Lines，單檔 2MB、保留 3 個（輪替），寫入失敗不影響 App；
     - console 只在 debug build；
     - 層級：release 是 `info`，debug build 是 `debug`。開發者模式在 M3。
   - **JSON Lines 欄位**（ADR 0025 §決定 3）：時間（UTC ISO 8601）、層級、tag、訊息、error、stackTrace、結構化欄位，一筆一行。
     - 讀取函式遇到壞行時略過，不中止（ADR 0025 §如何確認），本 PR 提供並測試；Debug 頁在 M3 使用。
   - **未捕捉錯誤**：`FlutterError.onError` 與 `PlatformDispatcher.instance.onError` 經門面以 `error` 寫入。
   - `core/` 不得 import 平台層以上的東西：log 目錄路徑由 `main()` 傳入。
4. **遮蔽函式**：`lib/core/redaction/`，全 App 唯一一個（ADR 0011 §決定 3）。
   - 依序套用：
     1. header 名單：`Cookie`、`Set-Cookie`、`Authorization` 等，值換成 `***`；
     2. key 名單：query 與 body 的 `access_key`、`SESSDATA`、`bili_jct`、`token`、`csrf` 等；
     3. 已知媒體 CDN 的簽名參數去除：舊專案的相關邏輯在 `lib/core/logger.dart` 與 `lib/services/audio/*`，參考它的名單；
     4. 已知憑證值逐字替換：提供登記與取消登記的 API，帳號層在 M3 使用。
   - 套用在訊息、error 的字串、stackTrace、結構化欄位（遞迴）。
   - 名單集中一處，並提供給插件追加名單的 API（M1 的 B 站插件在 PR 9 使用）。
   - 舊專案的遮蔽做法可參考 `lib/core/logger.dart`，但以 ADR 為準。不得寫出任何真實憑證值，測試用明顯是假的值，例如 `FAKE_SESSDATA_123`。
5. **測試**（ADR 0011 §如何確認）：
   - 以一組假憑證與假簽名 URL 經門面寫入後，log 檔與記憶體歷史都不再出現原值；
   - 包括原值只出現在 stackTrace、error 的 `toString()`、結構化欄位深層的情況；
   - 輪替：寫超過 2MB 會切檔，最多 3 個；
   - 寫入失敗（例如目錄不可寫）不拋出；
   - 壞行略過。
   
   網路紀錄與診斷包的遮蔽在 PR 8 與 M3 各自測。
6. **文件**：
   - `app/AGENTS.md` log 段：門面是唯一入口（`fmp_log_facade` 守）、遮蔽函式唯一、log 檔位置與格式；
   - 設定段：欄位為空表示沒設定過，改預設不需 migration；
   - `.trellis/spec/app/logging/index.md` 與 `.trellis/spec/app/settings/index.md`（繁中）：怎麼加一個設定欄位（改表、快照、Notifier、預設、測試），怎麼加一個遮蔽名單項目。
   
   加設定欄位會改 schema，要依 `spec/app/data` 的步驟做。

## 驗收

- [ ] `app/`：
  - format 通過；
  - codegen 沒有變動；
  - `dart analyze --fatal-infos`（含重新開啟的 `missing_provider_scope`）、`flutter analyze` 零問題；
  - `flutter test` 全綠；
  - 哨兵通過。
- [ ] Windows dev 版開啟後，`userdata-dev/logs/` 有一個 JSON Lines 檔，內容含啟動那一筆（主對話實機）。
- [ ] Android dev 版的 `files/logs/` 同上。
