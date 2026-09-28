# 指令檔與 spec 分家（M1 PR 1）

父任務：`../09-28-m1-skeleton-tracer`（擁有者決定 1；做法見父任務 `design.md` §1）。

## 做什麼

1. **根目錄 `AGENTS.md`** 換成共用版，全文照 `new-root-agents.md`（主對話定稿）。`TRELLIS:START`／`END` 之間的管理區塊原樣保留在檔尾。
2. **`lib/AGENTS.md`**（新檔，英文）：
   - 原根目錄 `AGENTS.md` 的 `## Verification`、`## Conventions`、`## Boundaries` 三段原封搬來，連同段落裡的路徑與測試引用；
   - 開頭加一段說明：這份是凍結舊專案的規則，只收緊急修正，路徑相對 repo 根。
3. **spec 搬家**：
   - `git mv .trellis/spec/{data,services,shared,testing,ui} .trellis/spec/legacy/`，`guides/` 留在原地；
   - 更新每一處指向舊路徑的引用：spec 之間的相對連結、`lib/AGENTS.md`、`docs/README.md`、`.claude/agents/*`；
   - 任務 archive 與 `docs/audit/` 是歷史紀錄，不改。
4. **`.trellis/config.yaml`**：在 packages 註解區塊後加上
   ```yaml
   packages:
     legacy:
       path: .
     app:
       path: app
   default_package: app
   ```
   `09-26-fmp-rewrite`、`09-28-m1-skeleton-tracer` 與本任務的 `task.json` 設 `"package": "app"`。
5. **`.claude/agents/trellis-implement.md`、`trellis-check.md`**：
   - spec 路徑寫成 `.trellis/spec/<package>/<layer>/`；
   - 驗證步驟改成讀 `task.json` 的 `package`：`legacy` 跑 `lib/AGENTS.md` § Verification，`app` 跑 `app/AGENTS.md` § 驗證。
6. **skill 改名**：
   - `git mv .claude/skills/verify-on-device .claude/skills/verify-legacy-on-device`；
   - SKILL.md 的 `name:` 改成 `verify-legacy-on-device`，description 開頭註明只給舊專案緊急修正用；
   - 內容不動，只更新 skill 內指向自身的路徑。
7. **其他引用**：
   - `orca.yaml:14` 的註解改指 `lib/AGENTS.md` § Verification；
   - `docs/README.md` 地圖的 spec 與 skill 兩列、語言段落改成新路徑。
8. **ADR 更正**，只在「之後要注意」或相關段落加一句，不改決定：
   - 0015：`flutter analyze` 看不到插件診斷的 issue 改引 flutter/flutter#187999，#193203 已以重複關閉；
   - 0021：`window_manager` 0.5.2 於 2026-07 發佈，pub.dev 沒有停止維護的標示；
   - 0027：根目錄舊 skill 已改名 `verify-legacy-on-device`，內容不變。

## 驗收

- [ ] `rg -n "trellis/spec/(data|services|shared|testing|ui)/|skills/verify-on-device" --glob '!.trellis/tasks/**' --glob '!docs/audit/**'` 沒有結果。
- [ ] `lib/AGENTS.md` 與原根目錄三段逐字相同，只有路徑引用的更新與開頭說明。
- [ ] `flutter test --exclude-tags live test/support test/workflows` 全綠。
- [ ] `python ./.trellis/scripts/get_context.py --mode packages` 列出 `legacy` 與 `app`。
- [ ] 以 `app` 任務為 current task 模擬 SessionStart，spec 索引只剩 `guides`，不含 `legacy/*`。
