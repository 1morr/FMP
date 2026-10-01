# 0010 — 新專案用 drift（SQLite），首次啟動自動匯入舊資料

- 狀態：已採納
- 日期：2026-09-27
- 影響範圍：`app/` 的資料層與設定存放、`app/lib/legacy_import/`、備份格式、舊版使用者的升級路徑

## 背景

舊專案的資料全在 `isar_community` 3.3.2（Isar v3 的社群 fork）：11 個 collection、沒有任何 IsarLink，
歌單與曲目的關係靠手動維護的 id 與字串鍵；沒標 `@ignore` 的 getter 也被持久化；migration 用自建的
`kFmpSchemaVersion`，其中 v3→v4 無條件改寫了使用者的設定（`docs/audit/data.md` §1–§2、`docs/audit/accounts-network.md` §7）。
手動維護關係的結構造成過資料遺失：啟動時的下載同步重建曲目的歌單關聯，對不上就丟，接著孤兒清理把曲目刪掉
（`docs/audit/downloads.md` §4.4）。

擁有者要求舊資料庫、登入憑證、已下載檔、舊備份檔在新 App 全部自動遷移（`docs/audit/questions.md` A3），
而新 App 沿用舊 App 身分（ADR 0008）。本 ADR 對新專案取代 ADR 0002、0007；那兩份仍描述根目錄舊專案，
在切換 PR 隨舊專案刪除。

## 考慮過的選項

### 留在 isar_community（v3）

能原地打開舊檔，遷移最簡單。但長期依賴一個自述「主要做 v3 bug 修正」的 fork（上游 Isar 2023 年起停更）；
手動維護關係的結構會帶進新專案；Linux、macOS、iOS 從未驗證。

### drift（SQLite）（採用）

見下方決定。

### 其他

- **ObjectBox**：五平台，但 schema 遷移細節與全文搜尋的證據不足。
- **Hive CE**：輕量鍵值儲存，不適合當關聯資料的主資料層。
- **Realm**：一年以上未發版，且核心賣點（雲端同步）用不上。
- **設定用 `shared_preferences`**（Spotube、Finamp 的做法）：檔案位置由平台決定，無法跟著 Portable 版放在程式旁的 `data/`。
- **遷移後自動刪除舊檔**：失敗或有漏時無法回頭。
- **遷移成功一版後就移除 legacy 模組**：舊版允許跳版升級，跳過那一版的使用者會拿不到舊資料。

## 決定

1. **選型**：`drift`＋`sqlite3`（native assets 自動打包五平台原生庫）。資料庫檔在 ADR 0009 定義的資料目錄。
   只有資料層（repository）能存取資料庫。
2. **Schema 原則**：
   - 關係交給資料庫：外鍵、`ON DELETE` 規則、唯一鍵；歌單與曲目用關聯表（含排序欄位）。
   - 曲目以 `TrackKey` 字串（含 cid，ADR 0005）為唯一鍵。
   - 只存事實：不持久化推導值、格式化字串、與時間有關的推導狀態；串流 URL 不進資料庫。
   - 下載紀錄獨立成表。
   - 設定存在同一個資料庫的設定表。
   - 時間存 UTC epoch 毫秒；音源 id 用字串。
3. **Schema 演進**：每版以 `drift_dev schema dump` 存快照；每個 migration 有升級測試；migration 不得改寫使用者設定過的值，
   只能影響沒設定過的列；migration 失敗整個回滾，App 顯示錯誤頁而不在半升級的資料庫上啟動。
4. **舊資料匯入（legacy import）**：
   - 位於 `app/lib/legacy_import/`，是唯一依賴 `isar_community` 與 `flutter_secure_storage` 10.x 的地方。
   - 首次啟動偵測到舊資料時：唯讀開啟舊 Isar、用與舊版相同的 secure storage 版本讀憑證、登記舊下載檔（不搬檔），
     轉換後寫入**暫存**資料庫；驗證筆數、抽樣比對、外鍵完整後，才換成正式資料庫並寫入匯入紀錄。
   - 失敗時不留半套資料，顯示錯誤頁：重試、匯出診斷、或先以空白資料啟動（之後可再匯入）。
   - 讀不到的憑證只把該音源標為「需要重新登入」。
   - 舊版被 migration 強制改過的設定無法還原原值，照現值匯入。
   - 舊備份檔可匯入，與資料庫匯入共用同一套轉換。
   - 永遠不自動刪舊檔；匯入成功後，設定頁提供「刪除舊版資料」。
   - 模組與其舊依賴保留到另立 ADR 移除；移除前需公告最低升級路徑。

採用的慣例：drift 官方的 schema 快照與 migration 測試工具；Spotube 的 drift＋sqlite3 組合；
一次性遷移「先寫暫存、驗證後才換上」的保守做法。

## 後果

- 好的：關係完整性由資料庫保證；schema 演進可測；資料檔可用通用 SQLite 工具檢視；舊版使用者升級不需手動操作。
- 壞的：新 App 帶著 `isar_community` 與舊版 secure storage 兩個舊依賴，直到另立 ADR 移除；要重新設計 schema 與轉換規則。
- 之後要注意：
  - `isar_community` 與 `sqlite3` 兩套原生庫共存沒有直接先例，第一個里程碑在 Android、Windows 實測；若衝突，legacy import 改成由新 App 啟動的獨立一次性小程式。
  - `sqlite3` 原生庫的 Android 16KB page size 對齊，第一個里程碑用官方對齊檢查確認。
  - 實測結果（2026-09-29，M1 PR 5 期間）：`isar_community` 3.3.2 與 `sqlite3` 3.6.0 在 Android（debug、release，16KB 頁的模擬器）與 Windows 共存、各自讀寫成功；Android 所有 `.so` 的 LOAD 段 p_align ≥ 0x4000，`zipalign -c -P 16` 通過。不需要獨立小程式。紀錄在 `.trellis/tasks/archive/2026-10/09-28-m1-skeleton-tracer/research/isar-sqlite3-coexistence.md`。
  - `isar_community_generator` 3.3.2 要求 `analyzer <11`，與 `app/` workspace 的 analyzer 13 衝突，無法在 workspace 內跑 Isar codegen；M5 在 workspace 外產生 `*.g.dart` 後提交（上述實測已證實可行），或等 generator 放寬。
  - 新憑證存放處在網路與帳號的 ADR 決定；`flutter_secure_storage` 升到 11.x 的條件同樣在那裡處理。

## 如何確認

- Schema 快照與每個 migration 的升級測試在 CI 執行。
- 「migration 不改使用者設定過的值」有專門測試：先寫入使用者值，跑 migration，斷言值不變。
- 資料庫只由資料層存取、`legacy_import/` 不被其他模組 import：lint `fmp_layer_imports`（ADR 0015）。
- 切換前，在擁有者真實資料的副本上完整跑一次匯入，並把筆數比對結果附在切換 PR 的 review 指南。
