# 資料持久化層研究：候選比較、同類播放器、設定存放

範圍：`.trellis/tasks/09-27-design-data` 研究項目 1、2、5。標記慣例：「查不到」＝已查
但沒有可信來源；「推測」＝有間接證據但未直接證實。每個具體宣稱附來源 URL。

## 1. 候選資料層比較

候選：drift（SQLite）、sqflite/sqlite3 直接用、isar_community（留在 v3）、
ObjectBox、Hive CE（`hive_ce`）、Realm。

### 1.0 版本與維護狀態（pub.dev API，2026-09-27 查）

| 套件 | 最新版 | 發布日期 | 來源 |
|---|---|---|---|
| `drift` | 2.28.2（依查詢當下） | 持續 2026-09 內有發布 | https://pub.dev/api/packages/drift |
| `sqlite3` | 3.x 系列 | 持續 2026-09 內有發布 | https://pub.dev/api/packages/sqlite3 |
| `sqlite3_flutter_libs` | 0.6.0+eol | 2026-02-15，**明確標記 EOL** | https://pub.dev/packages/sqlite3_flutter_libs |
| `isar_community` | 3.x（社群 fork） | 2026-03-23 | https://pub.dev/api/packages/isar_community |
| `objectbox` / `objectbox_flutter_libs` | 最新穩定 | 2026-05-20 | https://pub.dev/api/packages/objectbox |
| `hive_ce` / `hive_ce_flutter` | 最新穩定 | 持續 2026-09 內有發布 | https://pub.dev/api/packages/hive_ce |
| `realm` | 20.2.0 | 2025-09-24，**其後無任何新版**（查詢時已隔一年未更新） | https://pub.dev/api/packages/realm |

Realm／MongoDB Atlas Device SDK 結論：最新版距今逾一年沒有更新，維護狀態明顯停滯，
列為候選但不建議採用；本專案不需要雲端同步，Realm 的核心賣點（Device Sync）用不上。

### 1.1 五平台支援（含原生函式庫打包）

- **drift + sqlite3**：官方文件確認 `sqlite3` 套件 v3.x 起改用 Dart build hooks
  （native assets／`code_assets` 機制）**自動打包**原生 SQLite，Android／iOS／
  macOS／Windows／Linux 五平台都不再需要手動加 `sqlite3_flutter_libs` 或
  `sqlcipher_flutter_libs` 這類外掛套件（兩者官方文件都寫「no longer
  necessary... can be removed」）。若要換成加密版 SQLite（SQLite3MultipleCiphers），
  在 `pubspec.yaml` 用 `hooks: user_defines: sqlite3: source: sqlite3mc` 即可換源，
  Windows／Linux 端的 native_assets 目錄會被 Flutter 標準建置流程自動複製進 bundle。
  來源：context7 `drift` 官方文件（native assets／build hooks 章節）；
  https://pub.dev/packages/sqlite3_flutter_libs；https://pub.dev/packages/sqlcipher_flutter_libs。
  Namida 本身也是用同一個 `hooks: user_defines: sqlite3: source: sqlite3mc` 機制換成加密 SQLite。
- **isar_community**：五平台支援沿用上游 isar 的成熟度，FMP 現行版本已在
  Android＋Windows 生產驗證（`docs/adr/0007-isar-stays-on-v3.md`）；fork 的 Android
  library 已確認 16 KB page-size 對齊（同 ADR）。Linux／macOS／iOS 未在 FMP 內驗證過，
  上游 isar 過去有五平台支援紀錄，但 fork 是否對每個平台都持續打包需要在
  child task 實測，本研究不下定論。
- **ObjectBox**：官方套件 `objectbox_flutter_libs` 涵蓋 Android／iOS／macOS／
  Linux／Windows 五平台原生函式庫打包；非 Flutter 的 Dart-only 場景需另外跑
  `install.sh` 或走 fallback 搜尋路徑（Windows 找當前目錄與
  `%WINDIR%\system32`；macOS 找 `/usr/local/lib`；Linux 找 `/lib`、`/usr/lib`）。
  來源：context7 `/objectbox/objectbox-dart` 官方文件／README。FMP 是 Flutter app，
  用 `objectbox_flutter_libs` 這條路徑，不受此限制影響。
- **Hive CE**：純 Dart 實作，無原生函式庫依賴，理論上五平台都能跑；沒有找到
  Hive CE 在 Linux／macOS／iOS 的官方相容性聲明之外的額外限制，視為「查得到但
  非重點候選」（純 key-value／物件儲存，見下方「不建議理由」）。
- **Realm**：官方 SDK 過去主打 Android／iOS／macOS，Windows／Linux 桌面支援
  歷史上一直較弱，且維護已停滯（見上表），不再深入查證平台細節。

### 1.2 Schema migration 機制與可測試性

這是候選之間差距最大的一項。

- **drift**：一套完整、官方維護的遷移＋測試工具鏈：
  - `dart run drift_dev make-migrations` —— 版本號一變動就自動產生 step
    migration 骨架與對應的測試腳手架；
  - `dart run drift_dev schema dump` —— 把每個 schema 版本匯出成 JSON，進版控；
  - `dart run drift_dev schema generate` —— 依匯出的 schema JSON 產生遷移測試碼；
  - `SchemaVerifier`（`schemaAt`／`migrateAndValidate`／`startAt`／
    `InitializedSchema`）—— 讓測試能「在舊版本 schema 塞資料 → 跑遷移 → 驗證新
    版本資料正確」，是目前查到唯一有官方一條龍遷移測試工具的候選。
    來源：context7 `drift` 官方文件（schema migration 章節）。
- **isar_community**：沒有官方遷移測試工具；FMP 現行做法是手動維護
  `kFmpSchemaVersion` 並用 `test/manual/real_db_probe.dart` 對真實資料庫副本
  跑前後驗證（`docs/adr/0007-isar-stays-on-v3.md`）——等於自己補上 drift 內建的
  那一層。
- **ObjectBox**：官方文件宣稱「automatic」schema migration——「simply change
  your model, we handle the rest」，但查到的說明僅止於這句行銷語，沒有找到
  對「刪欄位」「改型別」「破壞性變更」這類場景的具體行為文件或遷移測試 API。
  這點標記「查不到」，若要採用 ObjectBox 需要在設計前再花時間查證破壞性
  schema 變更的實際行為，不能只憑這句話假設它總是安全。
- **Hive CE**：沒有 schema 遷移機制，型別演進靠手寫 `TypeAdapter`（見 Finamp
  案例，第 2 節）——本質上是「舊 binary 版面手動 parse 進新 class」，沒有版本
  化 schema 或自動化測試工具。

**結論**：schema migration 可測試性上 drift 明顯領先；這對「新資料層要長期維護、
且要能安全演進」的目標權重很高。

### 1.3 Reactive queries（watch／stream）

- **drift**：原生支援 `.watch()`／`.watchSingle()`／`.watchSingleOrNull()`，
  回傳 `Stream`，直接對接 Riverpod `StreamProvider`（官方文件範例即用這個組合）。
  來源：context7 `drift` 官方文件。
- **isar_community**：沿用上游 isar 的 `watchObjectLazy`／`watchLazy`／
  `.watch()` API（FMP 現行程式碼已在用，例如 Finamp 的
  `FinampUser.watchObjectLazy(0)` 模式，見第 3 節引用）。
- **ObjectBox**：`Query.watch()` 走 `entityChanges` broadcast stream，官方測試
  套件裡的 `isolates_test.dart` 證實可跨 isolate 生效。來源：context7
  `/objectbox/objectbox-dart` 文件與測試範例。
- **Hive CE**：`Box.watch()` 存在，但事件粒度是「整個 box 的 key 變化」，不像
  drift／isar／ObjectBox 能對查詢結果做細粒度 reactive。

### 1.4 Isolate 使用

- **drift**：`NativeDatabase.createInBackground(file)` 一行設定即可把整個資料庫
  操作丟到背景 isolate，不需要改查詢程式碼。來源：context7 `drift` 官方文件。
- **isar_community**：上游 isar 本身設計成可跨 isolate 共用同一個 `Isar`
  instance（`Isar.open` 於多個 isolate 可重複取得同一個開啟的實例），FMP 現行
  已依賴此特性。
- **ObjectBox**：`Store` 可跨 isolate 共用，`Query.watch()` 已驗證跨 isolate
  能收到事件（見上）。
- **Hive CE**：官方文件與社群討論显示 Hive 系列历史上对多 isolate 并发写入较
  敏感（同一 box 不建議多個 isolate 同時寫），這點沒有找到 hive_ce 有結構性改善
  的正式聲明，標記「推測」——沿用原始 Hive 的限制，需要在設計時避開多 isolate
  寫入同一個 box。

### 1.5 Codegen／build_runner 依賴

- **drift**：需要 `drift_dev` + `build_runner`（`.drift` 檔或 Dart table 定義
  → 產生 `.g.dart`）。FMP 現行 isar 已經依賴 `build_runner`（Isar generator），
  對現有工作流沒有新增類別的負擔，只是換一套 generator。
- **isar_community**：需要 `isar_generator` + `build_runner`（FMP 現行做法）。
- **ObjectBox**：需要 `objectbox_generator` + `build_runner`。
- **Hive CE**：需要 `hive_ce_generator` + `build_runner`（`TypeAdapter` 產生）；
  也可以完全手寫 `TypeAdapter` 不跑 codegen，彈性略高但要自己維護 field 對應。

四個方案都要 `build_runner`，這項對比較結論影響不大——FMP 現有工具鏈已經有
這個依賴，換誰都不會多引入新的建置步驟類別。

### 1.6 Riverpod 相容性

- **drift**：context7 官方文件直接給了 `StreamProvider` 接 `.watch()` 的範例，
  是四個候選裡唯一在官方文件層級示範 Riverpod 整合的。
- 其餘三者（isar_community／ObjectBox／Hive CE）都是「stream／watch API 存在，
  自己包一層 Riverpod provider」，FMP 現行 isar 用法就是這個模式，技術上都可行，
  沒有相容性障礙，只是沒有官方文件示範。

### 1.7 全文檢索（FTS）

- **drift**：支援 FTS5，build option 開 `sqlite_module: [fts5]`，
  搭配 `package:drift/extensions/fts5.dart` 的 `bm25`／`highlight`／`snippet`
  等輔助函式可直接寫進查詢；FTS5 虛擬資料表**只能在 `.drift` 檔宣告，不能用純
  Dart class 定義**。來源：context7 `drift` 官方文件。
- **isar_community**：上游 isar 有自己的 index／filter 機制，但不是標準
  SQL FTS5，全文檢索能力有限（前綴比對、simple word index），FMP 現行程式碼
  沒有依賴 isar 的全文檢索能力。
- **ObjectBox**：多次查詢（context7 `/objectbox/objectbox-dart` 官方文件與
  README）都沒有出現 FTS／全文檢索相關 API 或說明，官方文件重點在向量搜尋
  （on-device ANN vector search）而非文字全文檢索。**標記「查不到」**——沒有
  查到 ObjectBox 有 FTS 功能的證據，也沒有查到「明確不支援」的官方聲明，需視為
  高機率不支援或功能非常有限。
- **Hive CE**：沒有內建全文檢索，需要自己實作（例如把 tokenize 後的關鍵字另存
  一份索引 box）。

FMP 若未來要做「搜尋歌單／曲目名稱」這類本地全文檢索需求，drift 是唯一有現成
標準 SQL FTS5 支援的候選。

### 1.8 效能數據（萬列等級）

- ObjectBox 官方發布的 Flutter 資料庫效能測試（廠商自測，需帶保留態度）：
  在 Kirin 980 真機、每批 10,000 筆物件、50 次取平均，比較 sqflite／Hive／
  ObjectBox／Drift(Moor)／Floor；ObjectBox 在 create／update 上比 sqflite
  快至多 70 倍；Hive 讀取快是因為記憶體快取造成的比較基準不公平（該報告自己
  也這樣註記）。來源：https://objectbox.io/flutter-databases-sqflite-hive-objectbox-and-moor
  （此為 ObjectBox 官方部落格，屬利害關係人自測數據，非獨立第三方基準，
  結論要打折扣看待）。
- **沒有查到** drift／sqlite3 或 isar_community 針對「數萬列」等級、非廠商
  自測的獨立效能比較數據——這點標記「查不到」。FMP 現行 isar 資料庫本身
  規模（依 `docs/audit/data.md` 所述約 1,534 列的真實資料庫副本）遠低於
  「數萬列」門檻，效能差異在 FMP 實際資料量下大機率都不是決策關鍵因素，
  比 schema migration 可測試性、五平台原生打包簡易度優先度低。

### 1.9 一般工具可檢視資料檔案

- **drift／sqlite3**：資料檔案就是標準 SQLite 檔案，任何 SQLite 瀏覽工具
  （DB Browser for SQLite、DBeaver 等）都能直接開啟檢視，不需要專案自己寫
  檢視器。這對「除錯時直接看資料庫內容」的日常開發體驗是明顯優勢。
- **isar_community**：專屬二進位格式，FMP 現行靠自己寫的
  `lib/data/database/database_catalog.dart`（`ADR 0002` 允許例外的檢視器）
  才能查看，也可以用官方 Isar Inspector（若 fork 相容）。
- **ObjectBox**：專屬二進位格式（FlatBuffers-based），沒有查到通用檢視工具，
  需要透過 ObjectBox 官方的 Admin 介面或自己寫程式讀取——標記「查不到」通用
  工具，需要專案自建或依賴 ObjectBox 自己的管理介面。
- **Hive CE**：專屬二進位格式，沒有查到成熟的通用圖形化檢視工具。

drift／sqlite3 在這項是唯一「不需要專案自己投資檢視工具、業界通用工具即可用」
的候選，對照 FMP 現在得自己維護 `database_catalog.dart` 的現況，是一個實質的
維運成本下降。

### 1.10 小結：候選比較結論

| 維度 | drift(sqlite3) | isar_community | ObjectBox | Hive CE | Realm |
|---|---|---|---|---|---|
| 五平台原生打包 | 自動（native assets） | 已驗證(Android+Win) | 有專用套件 | 純 Dart 無需打包 | 弱／停滯 |
| Schema 遷移工具 | 官方一條龍＋測試 API | 手動＋自建驗證腳本 | 宣稱自動，細節不明 | 手寫 TypeAdapter | 查不到 |
| Reactive watch | 有（Stream） | 有 | 有（含跨 isolate） | 有（box 粒度） | 查不到 |
| Isolate | 一行設定 | 已驗證 | 已驗證 | 推測有限制 | 查不到 |
| FTS | FTS5 完整支援 | 有限 | 查不到／推測無 | 無，需自建 | 查不到 |
| 通用工具可查看 | 是（任何 SQLite 工具） | 否（自建檢視器） | 否 | 否 | 否 |
| 維護狀態 | 活躍 | 活躍（社群 fork） | 中等活躍 | 活躍 | 停滯逾一年 |

**首選：drift（建立在 sqlite3 之上）。** 理由：五平台原生打包已經隨
`sqlite3` v3.x 的 native-asset 機制自動化、不必再手動管理平台外掛套件；
schema 遷移有官方測試工具鏈，直接補上 FMP 現行 isar 方案「自己手動維護版本號
+ 自建驗證腳本」的缺口；FTS5 是唯一標準化的全文檢索支援；資料檔案可以用任何
通用 SQLite 工具查看，比繼續維護專屬的 `database_catalog.dart` 更省力；
Riverpod 整合有官方範例。次要候選是 ObjectBox（若效能是關鍵瓶頸可再評估），
但其 schema 遷移細節與 FTS 支援目前查不到足夠證據，不適合在證據不足的情況下
選為首選。Realm 因維護停滯不建議列入候選。Hive CE 定位是輕量 KV／物件儲存，
不適合作為 FMP 這種有查詢／關聯需求的主資料層（更適合settings這類簡單資料，
見第 3 節）。

## 2. 同類播放器用什麼

四款同類 Flutter 音樂播放器的持久化選型（皆以 `pubspec.yaml` 直接查證，
GitHub API 讀取，2026-09-27）：

| 專案 | 主資料庫 | 設定存放 | 來源 |
|---|---|---|---|
| **Spotube** | `drift` + `sqlite3` + `sqlite3_flutter_libs` | `shared_preferences`（與 DB 分開） | https://github.com/KRTirtho/spotube/blob/master/pubspec.yaml |
| **Finamp** | `isar`（fork：`Komodo5197/isar-community.git`） + `hive_ce`（雙資料庫並存，長期） | `shared_preferences`（另外還有 `hive_ce` 存部分設定，見下方細節） | https://github.com/finamp-app/finamp/blob/master/pubspec.yaml |
| **Namida** | 自訂 SQLite（`sqlite3` + `sqlite3mc` 加密源） | 純 JSON 檔案，手寫 `SettingsFileWriter`，不經任何 DB／`shared_preferences` | https://github.com/namidaco/namida/blob/master/pubspec.yaml、`lib/base/settings_file_writer.dart` |
| **Harmony Music** | `hive`（原版，非 CE） | 同一套 `hive` box，與其他資料**混放**、無獨立機制 | https://github.com/anandnet/Harmony-Music/blob/master/pubspec.yaml |

四個樣本呈現四種不同組合，沒有一致的業界標準，但有兩個明顯的多數傾向：
（a）drift/SQLite 是新專案（Spotube）的選擇；（b）**設定與主資料庫分開存放**
是三分之三有明確劃分的專案（Spotube、Finamp、Namida）的共同做法，只有
Harmony Music 把設定混進主資料庫。細節見第 3 節。

### 2.1 Finamp 的 Isar + Hive CE 共存細節（同時是候選比較與遷移可行性的關鍵佐證，詳細分析見 `migration-feasibility.md` 第 1 節）

Finamp 目前生產環境**長期同時使用** Isar 與 Hive CE，不是「遷移後即將移除」的
過渡狀態：

- Isar 存放：`DownloadItem`、`IsarTaskDataSchema`（第三方套件
  `background_downloader` 的 `IsarPersistentStorage` 內部要求，非 Finamp 自己
  的選擇）、`FinampUser`（登入使用者，用 `.watchObjectLazy(0)` 做 reactive
  provider）、`DownloadedLyrics`。
- Hive CE 存放：一般設定（`FinampSettingsHelper`）、播放佇列
  （`QueueService`）等。
- `FinampUserHelper.migrateFromHive()` 是一次性遷移，把 `FinampUser` 資料
  從舊的 Hive box 結構搬進 Isar（方向是 Hive→Isar，不是反過來），由
  `hasCompletedIsarUserMigration` 設定旗標控制只跑一次。

來源：https://github.com/finamp-app/finamp/blob/master/lib/main.dart、
https://github.com/finamp-app/finamp/blob/master/lib/services/finamp_user_helper.dart

## 3. 設定存放：與資料庫合放 vs. 分開

FMP 現行做法（依 `docs/audit/data.md`）是設定也在 Isar 的一個 collection 裡；
以下是四個同類專案的實際做法，供設計新架構時參考：

- **Namida —— 純 JSON 檔案，完全不進 DB／`shared_preferences`**：
  `SettingsFileWriter` mixin，每個設定群組（`SettingsController` 的多個 part
  file，如 `settings.equalizer.dart`、`settings.player.dart`）各自序列化成
  JSON 直接寫入磁碟檔案，寫入用 2 秒 debounce 合併，避免頻繁磁碟 I/O：
  ```dart
  mixin SettingsFileWriter {
    String get filePath;
    Object get jsonToWrite;
    Duration get delay => const Duration(seconds: 2);
    Future<void> writeToStorage() async {
      if (_canWriteSettings) {
        _canWriteSettings = false;
        _writeToStorageRaw();
      } else {
        _writeTimer ??= Timer(delay, () {
          _writeToStorageRaw();
          _canWriteSettings = true;
          _writeTimer = null;
        });
      }
    }
    Future<void> _writeToStorageRaw() async {
      await File(filePath).writeAsJson(jsonToWrite);
    }
  }
  ```
  來源：https://github.com/namidaco/namida/blob/master/lib/base/settings_file_writer.dart
  優點：完全不依賴資料庫版本／schema，設定檔可以直接用文字編輯器查看或手動
  修復；缺點：要自己處理併發寫入與 debounce，沒有交易保證。

- **Spotube —— `shared_preferences`，與 `drift` 資料庫完全分開**：
  設定是設定、播放資料是資料，兩條路徑互不干擾，遷移或重建資料庫不影響設定。
  來源：`pubspec.yaml` 依賴清單（見上表）。

- **Finamp —— 以 `shared_preferences`／Hive CE 為主，與 Isar 分開**：
  一般設定不進 Isar；Isar 只保留「非設定」的功能性資料（下載項目、使用者、
  歌詞快取）。

- **Harmony Music —— 混放**：`settings_screen_controller.dart` 與
  `theme_controller.dart` 都直接呼叫 `Hive.box`，與其他業務資料共用同一套
  儲存機制，沒有獨立分層。來源：GitHub code search
  `repo:anandnet/Harmony-Music Hive.box` 命中上述檔案；同一次搜尋
  `SharedPreferences` 沒有任何命中，確認 Harmony Music 不用
  `shared_preferences`。

**傾向結論**：四分之三的專案把設定與主資料庫分開（Namida 用純檔案、
Spotube／Finamp 用 `shared_preferences`），只有 Harmony Music 混放。分開存放
的共同理由（可從程式碼行為推斷，非官方明文說明，標記「推測」）：設定的讀寫
頻率與資料型態（少量、扁平、常整包序列化）跟主資料庫的查詢型負載模式不同，
分開後設定變更不需要打開資料庫交易，資料庫 schema 遷移也不會牽動設定格式。
FMP 若採用 drift 作為主資料層，比照 Spotube／Finamp 的做法，用
`shared_preferences`（或功能對等的簡單 KV 方案）單獨存放設定，與 drift 資料庫
分離，是目前證據支持度最高、也最容易實作的路線。
