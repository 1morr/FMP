# 執行計畫：第 7 項定稿（設計任務，只產出文件）

1. [x] 核准後寫 `docs/adr/0026-milestones-and-cut-over.md`（依 `docs/adr/template.md`），內容取自 `design.md` §1、§3，以及 §2 的排序原則。
   被否決的方案：
   - 舊資料匯入延到切換前；
   - Debug 頁提早到 M2；
   - 先蓋完一層再做下一層；
   - Linux 從 M1 起全面驗證；
   - 以 WSLg 驗收 Linux；
   - 租雲端 Mac；
   - 里程碑不開 PR 子任務；
   - 每個 PR 都完整走一次 brainstorm；
   - 加開 GitHub Milestones；
   - 拿存下的基準數字直接比；
   - 不留誤差範圍；
   - 試用 1 週、不設試用、4 週以上；
   - 切換後以降版退回。
2. [x] 新增 `.trellis/tasks/09-26-fmp-rewrite/milestones.md`：`design.md` §2 的清單，加上狀態欄。
3. [x] 更正與指向：
   - ADR 0008（功能清單來源）、parent `prd.md` 完成定義；
   - ADR 0009、0011、0014、0017 各加一句指向 0026。
4. [x] 更新 `phase2-plan.md`：
   - §3 第 20 列 ✅；
   - §7、§8 各項標上所屬里程碑；
   - §10 改為階段二完成、下一步階段三（Trellis／docs 清理），之後 M1。
5. [x] 驗證：Mermaid 以 mermaid-cli 渲染；`git grep` 確認 ADR 間的引用，以及沒有殘留「`features.md` 中勾」。
6. [x] `task.py finish`，再 `task.py archive design-milestones --no-commit --skip-branch-validation`；ADR 與歸檔分開提交，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
