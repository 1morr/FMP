# 進度

工作單位是票（`.scratch/<里程碑>/issues/NN-slug.md`），狀態在票的 `Status:` 行。這裡只記進行中里程碑的 session 紀錄、偏差與決定；里程碑的順序、狀態與閱讀指引在 `docs/roadmap.md`。

## 寫法與封存

- 做票的分支不改本檔：票的 Comments 留 `Session 紀錄：` 與 `偏差：` 行，合併的人在主分支抄成這裡的一列與一條（`AGENTS.md`〈每個 session 的流程〉）。
- session 紀錄一列、偏差一條，整行各不超過 200 字元；細節在票的 `## Comments`、brief、plan 或 ADR，這裡只放指向它們的一句話。
- session 紀錄的「票」欄與偏差每條的開頭都標里程碑（`M0 01`、`2026-11-12 M0 票 01：…`），封存時靠它分。
- 偏差每條標決定者：`（使用者定）`、`（使用者同意）` 或 `（Agent 定）`，意思在 `AGENTS.md`〈使用者確認〉。
- 里程碑驗收時（步驟在 `docs/agents/milestone.md`〈驗收票〉），把它的 session 紀錄與偏差整段移到 `docs/archive/<里程碑>.md`，逐列比對沒有遺失，`docs/roadmap.md` 里程碑表的狀態換成那個檔的連結。同一個 commit 把下一個里程碑標成進行中，「下一步」寫 `/1morr:checkpoint <封存的里程碑>`。本檔只留進行中的里程碑。
- 票序等細節寫在 `.scratch/<里程碑>/spec.md`。spec 與票留在原處、不搬。
- `python3 scripts/check_docs.py`（`app/` 的快速閘門會跑它）強制：三個 `##` 段的順序、session 紀錄是一整張表、每列每條的長度、偏差每條以日期開頭並標決定者、最後一列的下一步、進行中里程碑做完的票有 `Session 紀錄：` 行、`docs/roadmap.md` 最多一個進行中的里程碑、四個檔的字元上限、brief 與 plan 不寫票號、程式碼不引用 brief 與 plan 的章節號、`.scratch/` 的 spec 與驗收票、進行中里程碑的 spec 有〈使用者試〉、票的 `Status:` 行。其餘靠收尾自查。

## Session 紀錄

| 日期 | 票 | 結果 | 下一步 |
| --- | --- | --- | --- |
| 2026-11-12 | M1 準備 | M0 已驗收並封存（[`docs/archive/M0.md`](archive/M0.md)）；M0 留下的與開工前的兩項待辦在 roadmap〈M1 三音源與播放核心〉 | 新 session 下 `/1morr:checkpoint M0` |
| 2026-11-13 | 流程 | 對齊 project-init：路線圖搬到 `docs/roadmap.md`、事實搬到 `docs/research/facts-*.md`、票留 Session 紀錄由合併的人寫本檔、驗收加使用者試 | 新 session 下 `/1morr:checkpoint M0` |

## 偏差與決定

- 2026-11-13 流程（使用者同意）：文件與做票流程對齊 project-init 的新範本，章節號不再寫進程式碼；plan〈里程碑任務〉搬走後 §6、§7 改成 §5、§6。
