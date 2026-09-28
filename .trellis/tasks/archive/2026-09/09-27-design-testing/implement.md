# 執行計畫：第 8 項（設計任務，只產出文件）

1. [x] 核准後寫 `docs/adr/0015-testing-gates-and-dev-environment.md`（MADR-lite，依 `docs/adr/template.md`），內容取自 `design.md` §1–§7；
   舊 static-rule 去向表放 ADR 附錄或連回本任務歸檔的 `design.md`（ADR 只留原則與「第幾項決定」的指向）。
2. [x] ADR 0008 的「如何確認」與「之後要注意」補一句：`app/` 不 import 舊專案由 L1 守、CI 切分已在 ADR 0015 決定。
   ADR 0009、0010、0011、0014 的「如何確認」寫「測試策略 ADR 落實／選定工具後加上」的地方，改成指向 0015 的規則名。
3. [x] `phase2-plan.md`：§3 第 8 項標 ✅（ADR 0015）；§7 加入 `design.md` §8 的四項實測；§10 交接段更新進度與下一項（17 快取與離線）。
4. [x] 驗證：Mermaid 以 mermaid-cli 渲染成功（設計圖已驗）；`git grep -n "測試策略 ADR"` 確認沒有漏改的指向。
5. [x] `task.py finish`、`task.py archive design-testing --no-commit --skip-branch-validation`；Conventional Commits 分開提交 ADR 與任務歸檔，推上 `docs/audit`。

回退：全部是文件，revert 對應 commit 即可。
