# 進度

工作單位是票（`.scratch/<里程碑>/issues/NN-slug.md`），狀態與做票的 session 紀錄都在票上（`python3 scripts/ticket_notes.py <里程碑的目錄名>` 印出來）。這裡只記進行中里程碑裡不是做票的 session（訪談、規劃、開工、驗收、流程調整）；里程碑的順序、狀態與閱讀指引在 `docs/roadmap.md`，決定在 `docs/decisions.md`。

## 寫法與封存

- 做票的 session 不改本檔，紀錄留在票上（`AGENTS.md`〈每個 session 的流程〉）。
- 一列不超過 200 字元；細節在票、spec 或 brief，這裡只放指向它的一句話。
- 「票」欄標里程碑（`M1 開工`），封存時靠它分。
- 里程碑驗收時，它的列和各票的紀錄一起搬到 `docs/archive/<里程碑>.md`，步驟在 `docs/agents/milestone.md`〈驗收票〉。本檔只留進行中的里程碑。
- `python3 scripts/check_docs.py`（`app/` 的快速閘門會跑它）強制的規則列在腳本開頭；本檔的是：兩個 `##` 段的順序、session 紀錄是一整張表、每列的長度、最後一列的下一步。

## Session 紀錄

| 日期 | 票 | 結果 | 下一步 |
| --- | --- | --- | --- |
| 2026-11-12 | M1 準備 | M0 已驗收並封存（[`docs/archive/M0.md`](archive/M0.md)）；M0 留下的與開工前的兩項待辦在 roadmap〈M1 三音源與播放核心〉 | 新 session 下 `/1morr:checkpoint M0` |
| 2026-11-13 | 流程 | 對齊 project-init：路線圖搬到 `docs/roadmap.md`、事實搬到 `docs/research/facts-*.md`、票留 Session 紀錄由合併的人寫本檔、驗收加使用者試 | 新 session 下 `/1morr:checkpoint M0` |
| 2026-11-13 | 流程 | 決定集中到 `docs/decisions.md`；plan 拆成 `ARCHITECTURE.md` 與 `docs/development.md`，引用改成節的標題 | 新 session 下 `/1morr:checkpoint M0` |
| 2026-11-13 | 流程 | 決定改成跟著里程碑封存：M0 的搬回 `docs/archive/M0.md`，`docs/decisions.md` 只留進行中的 | 新 session 下 `/1morr:checkpoint M0` |
| 2026-11-13 | 流程 | 舊版的文件與審計快照搬進 `docs/legacy/`，新版的開發文件改名成 `docs/development.md`；`docs/` 第一層的檔都列在 `AGENTS.md`〈文件〉 | 新 session 下 `/1morr:checkpoint M0` |
| 2026-11-13 | 流程 | 里程碑表的狀態改成固定詞開頭（已驗收）；`scripts/check_docs.py` 換成新版：有票的目錄要列在表裡、還沒結束的里程碑每張票要有 `## 驗收` | 新 session 下 `/1morr:checkpoint M0` |
| 2026-11-14 | M0 回顧 | M1 拆成 M1（B 站：播放核心與照稿頁面）與 M1.5（YouTube、網易雲）；決定記在 `docs/decisions.md`，M0 封存補〈決定〉〈使用者試〉；修 7 處文件矛盾 | 新 session 下 `/to-tickets docs/roadmap.md 拆 M1 的票` |
| 2026-11-14 | M0 回顧追問 | 預載定為先解析再緩衝下一首開頭、第一版不做磁碟音訊快取、M1 拆票時寫〈快取〉策略；brief §6、§9 與 roadmap〈M1〉已改 | 新 session 下 `/to-tickets docs/roadmap.md 拆 M1 的票` |
| 2026-11-14 | 流程 | 對齊 project-init：做票的紀錄只留在票上（帶日期的 Session 紀錄、`決定：`、`變更：`），加 `CHANGELOG.md`、commit-msg hook 與兩支紀錄腳本 | 新 session 下 `/to-tickets docs/roadmap.md 拆 M1 的票` |
