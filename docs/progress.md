# 進度

工作單位是票（`.scratch/<里程碑>/issues/NN-slug.md`），狀態在票的 `Status:` 行。這裡只記進行中里程碑的 session 紀錄；里程碑的順序、狀態與閱讀指引在 `docs/roadmap.md`，決定在 `docs/decisions.md`。

## 寫法與封存

- 做票的分支不改本檔：票的 Comments 留 `Session 紀錄：` 行，合併的人在主分支抄成這裡的一列（`AGENTS.md`〈每個 session 的流程〉）。
- 一列不超過 200 字元；細節在票的 `## Comments`，這裡只放指向它的一句話。
- 「票」欄標里程碑（`M0 01`），封存時靠它分。
- 里程碑驗收時（步驟在 `docs/agents/milestone.md`〈驗收票〉），把它的 session 紀錄移到 `docs/archive/<里程碑>.md` 的 `## Session 紀錄`、`docs/decisions.md` 裡它的決定移到同一個檔的 `## 決定`，逐列逐條比對沒有遺失，`docs/roadmap.md` 里程碑表的狀態換成那個檔的連結。同一個 commit 把下一個里程碑標成進行中，「下一步」寫 `/1morr:checkpoint <封存的里程碑>`。本檔只留進行中的里程碑。
- `python3 scripts/check_docs.py`（`app/` 的快速閘門會跑它）強制的規則列在腳本開頭；本檔的是：兩個 `##` 段的順序、session 紀錄是一整張表、每列的長度、最後一列的下一步。

## Session 紀錄

| 日期 | 票 | 結果 | 下一步 |
| --- | --- | --- | --- |
| 2026-11-12 | M1 準備 | M0 已驗收並封存（[`docs/archive/M0.md`](archive/M0.md)）；M0 留下的與開工前的兩項待辦在 roadmap〈M1 三音源與播放核心〉 | 新 session 下 `/1morr:checkpoint M0` |
| 2026-11-13 | 流程 | 對齊 project-init：路線圖搬到 `docs/roadmap.md`、事實搬到 `docs/research/facts-*.md`、票留 Session 紀錄由合併的人寫本檔、驗收加使用者試 | 新 session 下 `/1morr:checkpoint M0` |
| 2026-11-13 | 流程 | 決定集中到 `docs/decisions.md`；plan 拆成 `ARCHITECTURE.md` 與 `docs/development.md`，引用改成節的標題 | 新 session 下 `/1morr:checkpoint M0` |
| 2026-11-13 | 流程 | 決定改成跟著里程碑封存：M0 的搬回 `docs/archive/M0.md`，`docs/decisions.md` 只留進行中的 | 新 session 下 `/1morr:checkpoint M0` |
| 2026-11-13 | 流程 | 舊版的文件與審計快照搬進 `docs/legacy/`，新版的開發文件改名成 `docs/development.md`；`docs/` 第一層的檔都列在 `AGENTS.md`〈文件〉 | 新 session 下 `/1morr:checkpoint M0` |
