# 執行計畫

本任務只產出設計與 ADR；不建立 `app/`（第一個里程碑才建）。

- [ ] 依 `docs/adr/template.md` 寫 `docs/adr/0008-rewrite-as-new-app-in-same-repo.md`，內容取自 design.md §1–§6，含被否決的選項（逐步替換、長期分支、新 repo）與「如何確認」。
- [ ] `phase2-plan.md` 把第 7 項（高層）標為完成，註明里程碑拆分留到定稿。
- [ ] 歸檔本任務。

驗證：ADR 的 Mermaid 圖（若有）以 mermaid-cli 渲染一次；`git grep` 確認 ADR 內引用的檔案與行號存在。
