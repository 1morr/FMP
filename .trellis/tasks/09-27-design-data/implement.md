# 執行計畫

本任務只產出設計與 ADR；資料層與 legacy import 在里程碑中實作。

- [ ] 寫 `docs/adr/0010-drift-data-layer-and-legacy-import.md`：design.md §1–§6，被否決的選項（留在 isar_community、ObjectBox、Hive CE、Realm、設定用 shared_preferences、遷移後自動刪舊檔、遷移成功一版後就移除 legacy 模組），「如何確認」（schema 快照＋migration 測試、「不改使用者值」測試、真實資料副本遷移、import lint）。
- [ ] 在 ADR 0002、0007 開頭加一行：「只適用根目錄舊專案；新專案見 ADR 0010；切換時隨舊專案刪除」。
- [ ] 第 9 項規則的細化寫進 `docs/adr/template.md` 的註解（被取代但仍描述凍結舊專案的 ADR，切換時刪除）。
- [ ] `phase2-plan.md` 標記第 6 項完成，並在「第一個里程碑的必要驗證」記下 design.md §5 三項。
- [ ] 歸檔本任務。

驗證：Mermaid 以 mermaid-cli 渲染；`git grep -n "ADR 0002\|ADR 0007\|0002-repository\|0007-isar"` 的命中都仍指向存在的檔案。
