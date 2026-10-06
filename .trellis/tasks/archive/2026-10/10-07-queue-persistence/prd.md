# 佇列持久化與啟動恢復（M2 PR 14）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §3.1（`tracks` 表提前到 M2，擁有者已核准 §12 第 1 條）、§3.2（主資料庫的新表、差量寫入、外鍵 `RESTRICT`、位置位移的負值技巧、固定種子閘門）、§7.7（持久化與啟動恢復，臨時播放不持久化 §12 第 6 條）、§3.3（`restart_rewind_seconds`，表已在 PR 10 建好）、§6（啟動維護清單）。PR 13 定案：音量與靜音分開記（design §7.6）。執行清單在父任務 `implement.md`「14.」。本檔只列做什麼與驗收。

## 目標

重開 App 時回到上次的佇列、目前這首、播放位置、循環與隨機（含隨機順序）、音量與靜音；恢復時不發任何解析請求，按播放才解析並從倒退後的位置開始。

## 做什麼

1. **表**（主資料庫 schema v3 → v4）：`tracks`、`queue_entries`、`player_state`，欄位照 design §3.1、§3.2（`player_state` 單列含 `current_position`、`position_ms`、`loop_mode`、`shuffle_enabled`、`volume`、`muted`、`updated_at`；隨機順序依 design 存放）。repository：差量寫入、外鍵 `RESTRICT`、位置位移先改負值再改回避開主鍵衝突。照 data spec 的完整 migration 流程（快照、`stepByStep`、三種 migration 測試、`schema_test`）。
2. **`queue_store.dart`**（寫入時機）：佇列操作當下寫入；播放中每 10 秒寫位置；暫停、seek、App 進入 `hidden`／`paused` 時寫位置；音量與靜音變更時寫；臨時播放期間不覆寫快照（寫的是快照那首與快照位置，design §7.7）。
3. **啟動恢復**：狀態 `Idle`，帶佇列、目前這首、位置、循環、隨機、音量、靜音；**不解析、不預取**；按播放才解析，從「位置 −『重啟恢復時倒退秒數』」開始（「記住播放位置」關時從頭）；恢復後的第一次播放不記歷史（給 PR 15）。「重啟恢復時倒退秒數」的 setter 與設定頁「播放」組一列（預設 0，選項同臨時播放倒退）。
4. **孤兒曲目**：登記到啟動維護清單（PR 6 的 `StartupMaintenanceTask`），只刪沒有任何參照的 `tracks` 列。
5. 文件：`app/AGENTS.md`（§ 資料層、§ 播放、§ 設定、§ 啟動維護）、data／playback／settings spec；ADR 0019 若 design §11 列了一行更正就加；每條寫閘門。

## 不做

- 播放歷史（PR 15，`play_history` 表在 v5）。
- 臨時播放的持久化（不做，design §12 第 6 條）。
- 音量 UI（PR 17）。

## 驗收

- [ ] 測試：repository 以固定種子的隨機操作序列比對 `QueueModel`（每一步讀回等於模型狀態）；一萬筆整份取代的耗時（記錄數字，超過 500 ms 在 PR 描述說明）；`RESTRICT` 反例；migration 三種；恢復的四種組合（記住位置開關 × 倒退秒數）；臨時播放中重啟回到快照；恢復時沒有解析；孤兒清理只刪無人參照的列；設定頁一列；寫入時機（操作、10 秒、暫停、seek、生命週期、音量）。
- [ ] 驗證清單全綠（父任務 implement.md「每個 PR 的固定流程」第 5 步）。
- [ ] 實機（主對話做；重播，測試插件）：兩平台建五首佇列、開隨機與循環、播到中間 → 關 App → 重開：佇列、隨機順序、循環、音量、位置都回來，log 沒有解析 → 按播放從倒退後的位置開始。
