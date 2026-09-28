# 執行計畫：階段三

一個 PR：沿用 `docs/audit` 分支與 draft PR #173。每步一個 commit。

1. [ ] `docs(adr): 0027 on-device verification`：新增 ADR 0027；ADR 0015、0026 各加一句指向。
2. [ ] `docs: remove mattpocock skill residue`：
   - 刪除 `docs/agents/`；
   - AGENTS.md 的「Agent skills」段改為 `## Issues`。
3. [ ] `docs: fold CONTEXT.md into ADR 0012`：
   - ADR 0012 補上轉址原則；
   - 刪除 `CONTEXT.md`；
   - spec 的 7 處改指 ADR 0012。
4. [ ] `docs(adr): mark old ADRs as legacy-only`：0001、0003–0006 加註記。
5. [ ] `docs: rewrite the docs map`：`docs/README.md` 照 design §2 改寫。
6. [ ] `docs: align agent notes with trellis setup`：
   - AGENTS.md Trellis 段補三句（`.agents/`／`.codex/`、check 子代理、journal commit）；
   - 「Test waits」縮窄。
7. [ ] 本機（不進 git）：
   - 把 `.agents/` 版的實測筆記併進 `.claude/skills/verify-on-device/references/`，這部分會 commit：`docs(skill): keep measured notes from the local copy`；
   - 刪除本機 `.agents/`。
8. [ ] 驗證：
   - design §8 的兩條 `git grep`；
   - `flutter test test/support/wait_convention_static_rule_test.dart test/support/static_rule_placement_static_rule_test.dart`。
9. [ ] 更新 parent `phase2-plan.md` §10：階段三完成，下一步 M1。`task.py finish` 後再 `archive --no-commit --skip-branch-validation`，commit，push。

回退：全部是文件，revert 對應 commit 即可。本機 `.agents/` 刪除前，實測筆記已併進受版控的 skill。
