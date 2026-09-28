# 執行計畫：第 16 項（設計任務，只產出文件）

1. [x] 核准後寫 `docs/adr/0017-background-task-scheduler.md`（依 `docs/adr/template.md`），內容取自 `design.md` §1–§6；被否決的方案：
   各功能自開計時器（舊版）、`workmanager` 系統排程、桌面縮小時繼續跑、每工作各自退避、DNS 輪詢。
2. [x] ADR 0015：在 lint 表後加一句「後續 ADR 新增的規則：`fmp_periodic_timer_owner`（ADR 0017）」；ADR 0016 的「之後要注意」把背景刷新的指向改成 ADR 0017。
3. [x] `phase2-plan.md`：§3 第 16 項標 ✅（ADR 0017）；§10 交接段更新，下一項 13 播放核心。
4. [x] 驗證：Mermaid 以 mermaid-cli 渲染（設計圖已驗）；`git grep` 確認引用。
5. [x] `task.py finish`、`task.py archive design-background-tasks --no-commit --skip-branch-validation`；分開提交 ADR 與歸檔，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
