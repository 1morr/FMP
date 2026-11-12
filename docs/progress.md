# 進度

工作單位是票（`.scratch/<里程碑>/issues/NN-slug.md`），狀態在票的 `Status:` 行。這裡只記各里程碑的閱讀指引、session 紀錄、偏差與決定。

本檔只留進行中的里程碑。封存由里程碑的驗收票做，同一個 commit：它的 session 紀錄與偏差整段移到 `docs/archive/<里程碑>.md`，逐列比對沒有遺失；里程碑表的備註換成那個檔的連結。封存後再加一列 session 紀錄，票欄標下一個里程碑（例如 `M1 準備`），「下一步」寫它的開工指令，這一列留在本檔。

## 里程碑與閱讀指引

| 里程碑 | 票目錄 | 拆票前讀 | 備註 |
| --- | --- | --- | --- |
| M0 | `.scratch/m0/issues/` | `.scratch/m0/spec.md` | 2026-11-12 驗收，紀錄封存在 [`docs/archive/M0.md`](archive/M0.md) |
| D | 無 | `docs/design/DESIGN.md` | 2026-11-11 定稿（`docs/design/`），紀錄併在 [`docs/archive/M0.md`](archive/M0.md) |
| M1 | 還沒拆 | plan §5.3（含〈M0 留下的〉）、brief §6、`docs/design/DESIGN.md` | 下一個開工；`/to-tickets docs/plan.md 拆 M1 的票` 會把 plan §5.3 細化成 `.scratch/m1/spec.md` |

## Session 紀錄

| 日期 | 票 | 結果 | 下一步 |
| --- | --- | --- | --- |
| 2026-11-12 | M1 準備 | M0 已驗收並封存（[`docs/archive/M0.md`](archive/M0.md)）；plan §5.3、§5.4 多了〈M0 留下的〉，拆 M1 的票時要讀。開工前的待辦（plan §5.3）：擁有者檢查 `winpc` 硬體（記憶體診斷，M0 驗收時原生工具反覆存取違規、又有藍屏）；擁有者在四平台親耳聽一次播放（M0 驗收是 agent 代測，沒聽聲音） | 新 session 下 `/to-tickets docs/plan.md 拆 M1 的票`（先做完旁邊兩項待辦） |

## 偏差與決定

（M1 還沒有。）
