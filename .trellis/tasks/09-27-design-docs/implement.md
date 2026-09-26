# 執行計畫

本任務（第 9 項）只產出設計；下列兩部分分別在不同時點執行。

## A. 本任務核准後立即做

- [ ] 在 `docs/adr/` 新增 `template.md`（design.md §3 的章節）。之後第 1 項起的 ADR 都從它複製。
- [ ] `phase2-plan.md` 把第 9 項標為完成，並連到本任務。
- [ ] 歸檔本任務。

不動 `AGENTS.md`、`docs/README.md`、`.trellis/spec/`：它們描述的是舊程式碼，在階段三與各里程碑改寫。

## B. 階段三 child task（階段二全部定案後）

依 design.md §4、§6：

1. 刪除 `docs/agents/`；刪除 AGENTS.md「Agent skills」段；把「issue 用繁中撰寫」寫進 AGENTS.md。
2. 改寫 `docs/README.md`：地圖表加 Diátaxis 類型欄；刪 `:21` 中英分工規則與 `:23` `docs/agents/` 說明；`docs/audit/` 註明為凍結快照。
3. 依使用者在 `questions.md` 的勾選與 design.md §4 處理舊 ADR（已被新 ADR 取代的，應已在寫新 ADR 時刪除；這裡只收尾）。
4. `CONTEXT.md` 內容併入第 12 項產出的 spec 後刪除；改掉 `.trellis/spec/data/index.md:9`、`data/sources.md:81`、`guides/cross-layer-thinking-guide.md:51`、`services/download-and-auth.md:3,38`、`services/index.md:8,24`。
5. 修正 design.md §6 其餘衝突（AGENTS.md Trellis 區塊、check 子代理重複、journal commit 敘述、等待慣例敘述）；本機刪除 `.agents/`。
6. AGENTS.md、`.trellis/spec/` 改寫為繁中（可隨各里程碑逐層改寫，不必一次翻完）。

驗證：

```bash
git grep -n -E "docs/agents|CONTEXT\.md|Agent skills|wayfinder|grill-with-docs" -- . ':!.trellis/tasks/archive' ':!docs/audit'
git grep -n -E "adr/000[1-7]|ADR 000[1-7]" -- . ':!.trellis/tasks/archive' ':!docs/audit'   # 只允許仍存在的 ADR
```

兩條都只能命中仍存在、刻意保留的檔案。

## C. 最後一個里程碑

- [ ] 刪除 `docs/audit/`；`docs/README.md` 恢復「審查記錄不進 `docs/`」無例外。
