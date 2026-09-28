# 執行計畫：第 4 項（設計任務，只產出文件）

1. [x] 核准後寫 `docs/adr/0025-debug-page-and-developer-mode.md`（依 `docs/adr/template.md`），內容取自 `design.md` §1–§11。
   被否決的方案：
   - 開發者模式不記住（J1 原狀）；
   - release 版只留 log 與診斷包；
   - App 內可編輯資料庫；
   - 重設前不備份；
   - `TalkerScreen`、alice、`drift_db_viewer`；
   - log 保留 3 天、30 天、只限大小、可調設定；
   - 移植 `scan/repair`；
   - 自動修復；
   - 每次啟動自動檢查；
   - 檔案監看自動重載插件。
2. [x] 其他 ADR 各加一句指向 ADR 0025：
   - 0011：開發者模式持久化、log 保留與 JSON Lines 格式；
   - 0015：插件開發工具版面；
   - 0017：啟動維護清單加入 log 保留與診斷包暫存清理；
   - 0023：Debug 頁錯誤歷史。
3. [x] 更新 `phase2-plan.md`（里程碑實測放在 §8「加入 Debug 頁的里程碑」，不在 §7）：
   - §3：第 4 項標 ✅（ADR 0025）；
   - §8：加入 Debug 頁的里程碑實測項目；
   - §10：交接段更新，下一項為 7「里程碑定稿」。
4. [x] 驗證：Mermaid 以 mermaid-cli 渲染；`git grep` 確認 ADR 間的引用。
5. [x] `task.py finish`，再 `task.py archive design-debug-page --no-commit --skip-branch-validation`；ADR 與歸檔分開提交，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
