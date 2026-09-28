# 設計第 6 項：資料層與相容

## 目標

選定新 App 的持久化方案（五平台），定下 schema 原則，並設計舊資料（資料庫、登入憑證、已下載檔、備份檔）
在新 App 首次啟動時的自動遷移。

需求來源：parent `prd.md` 階段二第 6 項；`questions.md` A2（不確定，請推薦）、A3（全部自動遷移）、
A4（資料位置，按推薦）、B6（串流 URL 不存資料庫）、M3／M4（migration 不得改使用者設定值）；ADR 0008、0009。

## 已確認的前提

- 新 App 沿用舊 App 身分（ADR 0008），才讀得到 Android 私有目錄的舊資料與 Keystore 保護的憑證。
- 資料目錄：安裝版用系統 App 資料目錄、Portable 版在程式旁 `data/`、舊 `Documents\FMP` 首次啟動搬遷（ADR 0009 §7）。
- 串流 URL 只放短期快取，不進資料庫（B6，第 17 項細節）。
- migration 不得改寫使用者自己設定過的值（M3、M4）。
- `TrackKey` 字串格式（含 cid）確認沿用（ADR 0005）。

## 現況（證據）

- 舊資料層：`isar_community` 3.3.2，11 個 collection、沒有 IsarLink，關係靠手動 id／字串鍵；沒標 `@ignore` 的 getter 也被持久化（`docs/audit/data.md` §1）。
- 舊 migration：`kFmpSchemaVersion`，整段包在一個交易；v3→v4 無條件改寫使用者設定（`data.md` §2；`accounts-network.md` §7）。
- 舊憑證：`flutter_secure_storage` 刻意固定在 10.x：v10 第一次讀取時重新加密 Android 憑證，11.x 移除了 9.x 的 cipher，沒跑過 10.x 的安裝升到 11.x 會讀不出憑證（`pubspec.yaml:68-73`、`.github/dependabot.yml:46-54`）。

## 研究結論（`research/persistence-options.md`、`research/migration-feasibility.md`）

- **drift（SQLite）**：2.35.0（2026-09-09），五平台；`sqlite3` 3.x 以 native assets 自動打包原生庫，不再需要 `sqlite3_flutter_libs`；
  有官方 schema 版本快照與 migration 測試工具；反應式查詢、isolate、FTS5；資料檔可用任何 SQLite 工具檢視。Spotube 採用。
- **isar_community**：可留在 v3 原地打開舊檔；但長期依賴社群 fork，migration 靠自建機制，Linux／macOS／iOS 未驗證。
- **ObjectBox**：五平台，但 schema 遷移細節與 FTS 證據不足。**Realm**：一年以上未發版，不建議。**Hive CE**：輕量 KV，不適合當主資料層。
- 同類播放器：Spotube drift＋shared_preferences；Finamp isar fork＋hive_ce（長期共存）；Namida 加密 sqlite3＋JSON 設定檔；Harmony 純 hive。
- 換庫遷移：新 App 需暫時依賴 `isar_community` 讀舊檔；Finamp 證明 Isar 能與另一個資料庫長期共存，但 isar＋sqlite3 兩套原生庫共存沒有直接先例（原理上風險低），需在第一個里程碑實測。
- sqlite3 的 Android 16KB page size 問題上游已修，仍需用對齊腳本實測一次。

## 已決定

- D1（使用者 2026-09-27）：換成 drift（SQLite）。
- 其餘依研究與「按推薦」寫入 design.md：設定存資料庫（因 Portable 版目錄）、legacy import 模組、舊檔不自動刪、
  模組保留到另立 ADR、ADR 0002／0007 隨舊專案在切換時刪除。

## 需求

- R1 資料庫只由資料層存取（import lint，第 8 項）。
- R2 關係用外鍵與關聯表；不持久化推導值與串流 URL；`TrackKey` 為曲目唯一鍵。
- R3 每版 schema 有快照，每個 migration 有升級測試；migration 不改使用者設定過的值，有對應測試。
- R4 首次啟動自動匯入舊資料庫、憑證（讀不到則標記需重新登入）、已下載檔（不搬檔）；舊備份可匯入；全部先寫暫存、驗證通過才換上，失敗不留半套資料。
- R5 遷移不刪舊檔；匯入成功後提供手動刪除入口。
- R6 第一個里程碑實測：isar＋sqlite3 共存、16KB 對齊；切換前在真實資料副本上跑通遷移。

## 驗收標準

- [x] design.md 涵蓋選型、schema 原則、schema 演進、legacy import 流程與失敗處理、實測風險、舊 ADR 處理。
- [x] `docs/adr/0010-*.md` 依範本寫成；ADR 0002、0007 加註只適用舊專案。
- [x] `phase2-plan.md` 標記第 6 項完成並記下第一個里程碑的必要驗證。
