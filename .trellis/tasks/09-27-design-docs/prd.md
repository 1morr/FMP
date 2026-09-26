# 設計第 9 項：文檔結構與 ADR／CONTEXT.md 去留

## 目標

定下重寫後「給人看的文檔」與「給 AI 看的指令」各放什麼、互不重複，ADR 機制怎麼運作，
以及舊 ADR（0001–0007）、`CONTEXT.md`、mattpocock 殘留、`docs/audit/` 的去留。
之後每個設計項目產出的 ADR 都照這裡的規則寫。

需求來源：parent `prd.md` 階段二第 9 項、階段三；`phase2-plan.md` §5（使用者已確認「按推薦」）。

## 背景（證據）

- 人類文檔：`README.md`（英）＋`README.zh-Hant.md`、`docs/` 5 份繁中文件與 `docs/README.md` 文件地圖；`docs/adr/` 7 份繁中 ADR。
- AI 指令：`AGENTS.md`（134 行，英文）、`.trellis/spec/` 6 層 20 檔（英文）、`.trellis/workflow.md`、`.claude/{agents,commands,hooks,skills}`、`orca.yaml`；沒有 `CLAUDE.md`，本 session 的 Claude Code 直接載入了 `AGENTS.md`。
- `docs/README.md:21` 規定中英分工；`:24` 規定「審查記錄不進 `docs/`」，與 `docs/audit/` **不一致**。
- 重複與衝突見 `docs/audit/engineering.md` §8.2；mattpocock 殘留與引用見 §9。
- ADR／`CONTEXT.md` 的引用還出現在 `.github/workflows/release.yml`、`tool/release/verify_release_assets.dart`、`test/workflows/*`、`lib/data/repositories/lyrics_repository.dart`、`search_history_repository.dart`。
- 採用的慣例：Diátaxis（反對預建空結構）、agents.md、MADR（design.md 詳述）。

## 需求

- R1 三者分工：`.trellis/spec/` 寫「這一層的程式碼怎麼寫」、不寫歷史；task `design.md` 寫「這次任務怎麼做」、隨任務歸檔；`docs/adr/` 寫「跨模組決定的理由與被否決的方案」、長期保留。
- R2 新架構的每個重大決定各寫一份 ADR，從 0008 接續、不重用編號，用 `docs/adr/template.md`（含「如何確認」一節）。
- R3 舊 ADR 被新 ADR 推翻或不再適用時，同一個 commit 刪除舊檔、改掉所有引用、以 `git grep` 確認；確認沿用的保留（必要時改寫）。各份處理見 design.md §4。
- R4 `CONTEXT.md` 的原則併入第 12 項的 ADR 與 spec，術語隨新設計命名；階段三刪除 `CONTEXT.md` 並改掉引用。
- R5 人類文檔依 Diátaxis 分類，不預建空資料夾；`docs/README.md` 地圖標出每份文件的類型。
- R6 mattpocock 殘留在階段三移除（`docs/agents/`、AGENTS.md「Agent skills」段、`docs/README.md:21,23`）；「issue 用繁中撰寫」搬一句進 AGENTS.md。
- R7 語言（使用者 2026-09-27 決定）：所有文檔繁中，包括 `AGENTS.md`、`.trellis/spec/`、ADR、`docs/`；程式碼識別字、指令、檔名、log 字串、commit message 保留原文；README 維持英／繁雙語。`docs/README.md:21` 的中英分工規則刪除。
- R8 `docs/audit/`（使用者 2026-09-27 決定）：重寫期間凍結保留、只允許核查更正，作為完成定義的基準；最後一個里程碑的 PR 刪除，並恢復「審查記錄不進 `docs/`」無例外。
- R9 AGENTS.md 的每條規則都要附守著它的 test 或 lint，否則補閘門或刪除。

## 驗收標準

- [x] `design.md` 給出目標文檔地圖、規則放置表、ADR 機制、舊 ADR 與 `CONTEXT.md` 的逐項處理、`docs/audit/` 生命週期、階段三衝突清單。
- [x] `docs/adr/template.md` 存在，章節與 design.md §3 一致。
- [x] `implement.md` 列出階段三的執行步驟與 `git grep` 驗證指令。
- [x] `phase2-plan.md` 標記第 9 項完成。

## 範圍外

- 各設計項目本身的 ADR 內容（在各自的項目裡寫）。
- 階段三的實際執行（刪檔、改引用、翻譯）另開 child task。
- 本任務不改 `AGENTS.md`、`docs/README.md`、`.trellis/spec/`。
