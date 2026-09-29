# drift 最小 schema 與 TrackKey（M1 PR 5）

父任務：`../09-28-m1-skeleton-tracer`（design §3 的「M1 的 drift 表」；implement「5.」）。

依據：
- ADR 0010 §決定 1–3：drift＋sqlite3、只有資料層存取、schema 原則與演進；
- ADR 0019 §決定 1：`PRAGMA foreign_keys = ON`；
- ADR 0011 §決定 7：設定每組一張單列表，欄位為空表示沒設定過；
- ADR 0014 §決定 5、8：每插件 storage，移除插件時清除；
- ADR 0005：`TrackKey` 格式。

## 做什麼

1. **依賴**：`drift`、`sqlite3` 3.x（內建 build hooks，不用已 EOL 的 `sqlite3_flutter_libs`）、`drift_dev`、`build_runner`。
   - 版本以 pub.dev 為準；
   - 開庫方式（`NativeDatabase` 或 `drift_flutter`）照 drift 官方文件對 sqlite3 3.x 的建議，來源記在 `research/notes.md`。
2. **資料庫**：`lib/data/database/`。
   - 檔案放在平台層的 App 資料目錄（PR 4 的 `AppPlatform`）底下，檔名 `fmp.db`。
   - 開啟時執行 `PRAGMA foreign_keys = ON`。
   - 只有 `lib/data/` 能 import drift，`fmp_layer_imports` 已守。
3. **Schema v1**：

   | 表 | 欄位 | 備註 |
   |---|---|---|
   | `appearance_settings` | `id`（固定 1）、`theme_mode`（可空文字：`system`／`light`／`dark`）、`locale`（可空文字：`zh-TW`／`zh-CN`／`en`） | 單列；空＝沒設定過（ADR 0011） |
   | `installed_plugins` | `id`（音源 id，主鍵）、`version`、`manifest_json`、`script`、`installed_at`（UTC epoch 毫秒） | 從檔案安裝（ADR 0014） |
   | `plugin_storage` | `plugin_id`（外鍵 → `installed_plugins.id`，`ON DELETE CASCADE`）、`key`、`value`；主鍵 (`plugin_id`, `key`) | 每插件 key/value（ADR 0014 §決定 5）；B 站匿名 `buvid` 放這裡（ADR 0012） |

   - 列舉值在 Dart 端用 enum 轉換，資料庫存字串。
   - 沒有 `tracks` 等音樂庫表，那些在 M4。
4. **Repository**（`lib/data/repositories/`），只做 M1 用得到的操作：
   - `AppearanceSettingsRepository`：讀單列（沒有就回全空）、寫入部分欄位、`watch`；
   - `PluginRepository`：安裝或更新、依 id 讀、列出、移除（連帶清掉 storage）；
   - `PluginStorageRepository`：依插件 id 讀、寫、刪 key。
   
   介面讓上層以 provider 注入，本 PR 還不接 Riverpod。
5. **Schema 演進工具**：
   - 以 drift 官方工具存 v1 快照：`drift_schemas/` 與 `drift_dev schema dump`／`generate`。
   - 測試：用 drift 官方的 schema 驗證 API，確認目前程式碼的 schema 等於 v1 快照。
   - 在 `.trellis/spec/app/data/index.md` 寫下之後每加一版要做的事：bump `schemaVersion`、dump、寫 step-by-step migration、升級測試，並附官方文件連結。
   - 「migration 不改使用者設定過的值」的測試要等第一個 migration 出現才有意義。spec 寫明它是每個 migration 的必備測試。
6. **產生的程式碼**：drift 產生的 `*.g.dart` 提交進 repo。
   - CI 的 `app` job 加一步：跑 `dart run build_runner build`，然後 `git diff --exit-code`，確認產生的程式碼是最新的。
   - `app/AGENTS.md` 寫明改了 table 要重跑 build_runner。
   - 理由：舊專案把產生檔 gitignore，結果新 worktree 常因為沒跑 codegen，出現像原始碼錯誤的「missing getter」（根目錄 `lib/AGENTS.md` 有記）。提交產生檔並檢查它是最新的，拉下來就能用。
   - 產生檔若違反 `fmp_lints` 或 analyzer 規則，在 `analysis_options.yaml` 排除 `**/*.g.dart`，並寫明原因。
7. **`TrackKey`**：`lib/domain/track_key.dart`。
   - 照舊版 `lib/data/models/track_key.dart` 的格式與行為原樣搬（ADR 0008 檔頭補充：葉節點照搬）：
     - `format`、`formatGroup`、`tryParse`；
     - 以 cid 區分分 P。
   - 測試用寫死的字面值釘住輸出，照舊版 `test/data/models/track_key_test.dart`。
   - 在 dartdoc 說明為什麼釘死：它是持久化格式，M5 匯入舊資料要對得上。
8. **`main()`**：啟動時開資料庫。開啟失敗時照 ADR 0010 §決定 3 顯示錯誤頁，不在半開的資料庫上啟動。M1 只要一個最小的錯誤畫面（字串先寫死繁中，PR 12 接 slang）。
9. **文件**：
   - `app/AGENTS.md` 資料段：
     - 只有 `lib/data/` 碰資料庫（lint 守）；
     - 改 table 的步驟與閘門（快照測試、產生檔檢查）；
     - `TrackKey` 是持久化格式。
   - `.trellis/spec/app/data/index.md`（繁中）。

## 驗收

- [ ] `app/`：
  - format 通過；
  - `dart analyze --fatal-infos`、`flutter analyze` 零問題；
  - `flutter test` 全綠；
  - 哨兵通過。
- [ ] `dart run build_runner build` 之後 `git diff --exit-code` 乾淨。
- [ ] 測試：
  - schema 等於 v1 快照；
  - 外鍵生效：刪除插件時 storage 一起消失，插入不存在的 `plugin_id` 會失敗；
  - 外觀設定沒有列時讀到全空，寫入後讀回；
  - `TrackKey` 字面值與來回一致。
- [ ] Windows、Android 的 dev 版開啟後，資料目錄出現 `fmp.db`（主對話實機）。
