# 設計：階段三清理

原則：
- 根目錄的 AGENTS.md、`.trellis/spec/` 描述凍結中的舊專案，**只做必要修改、維持英文**（已決定 1）；
- Trellis 管理的檔案（`.trellis/.template-hashes.json` 的 84 筆，以及 AGENTS.md 標記區塊內）**不改**，因為 `trellis update` 會覆寫。需要說明的，寫在 AGENTS.md 標記區塊外的 Trellis 段。

## 1. mattpocock 殘留

- 刪除 `docs/agents/` 三個檔。
- AGENTS.md 的「Agent skills」段（`:7-14`）改成一段 `## Issues`，只留一條慣例：
  > Issue titles and bodies are written in Traditional Chinese (Taiwan/Hong Kong usage); identifiers, log strings, commit messages, branch and label names stay in English. Issues live on `1morr/FMP` and are handled with `gh`.
- 5 個 triage label、5 個 `wayfinder:*` label 在 repo 內沒有任何使用者，隨目錄刪除。GitHub 上既有的 label 不動（不在 repo 內，也沒有人在用）。
- `docs/agents/issue-tracker.md:16-21` 的「刻意沒有 issue 範本」不搬：ADR 0023 已定 M3 新增 `bug_report.yml`。

## 2. `docs/README.md`

- 地圖表加「類型」欄（Diátaxis：操作指南、參考、說明；ADR 屬說明）：
  - 刪 `agents/` 一列；
  - 加 `audit/` 一列，類型「快照（凍結）」，說明「重寫前的現況與驗收基準，切換 PR 刪除（ADR 0008、0026）」；
  - `.trellis/spec/` 一列改為「英文，描述根目錄舊專案；`app/` 的 spec 從 M1 起繁中」。
- `## 分工`：
  - `:21` 改為：「新文件一律繁中；根目錄 `AGENTS.md` 與 `.trellis/spec/` 描述舊專案，維持英文到切換 PR；README 維持英／繁雙語。」
  - `:22` 補一句：`.agents/`、`.codex/` 是 gitignore 的本機狀態。
  - `:23`（`docs/agents/` 說明）刪除。
  - `:24` 補例外：「`docs/audit/` 在重寫期間凍結保留，切換 PR 刪除」。

## 3. 舊 ADR 0001、0003–0006

各在標題下加一行（格式同 0002、0007 已有的註記）：

| ADR | 註記指向 |
|---|---|
| 0001 | 新專案的字串音源 id 見 ADR 0014，每源設定見 ADR 0011、0012 |
| 0003 | ADR 0018 |
| 0004 | ADR 0020 |
| 0005 | 格式由 ADR 0010、0019 沿用 |
| 0006 | ADR 0022 |

每一行的結尾都是「本檔在切換 PR 隨舊專案刪除（ADR 0008）」。
- 引用它們的舊專案檔案（`lib/`、`test/`、`tool/`、`.github/`、`.trellis/spec/`、AGENTS.md、`docs/*.md`）不改，切換 PR 一起處理。

## 4. `CONTEXT.md`

- ADR 0012 §決定 1 補一句 Media Handoff 裡唯一沒有對應的原則：
  > 轉址：宿主 HTTP 跟隨轉址時，每一跳都要在 manifest 網域內，最多 5 跳（舊版 `SourceUrlPolicy.resolveRedirects` 的做法）；媒體 client 跟隨轉址時，每一跳都只帶媒體 headers。
- 刪除 `CONTEXT.md`。
- `.trellis/spec/` 的 7 處引用改指 ADR 0012，維持英文。
  - `services/download-and-auth.md` 仍描述舊程式碼的 `SourceHttpPolicy`，只換出處，不改規則。
- AGENTS.md `:13` 隨「Agent skills」段一起刪除。

## 5. 衝突

- **AGENTS.md 標記區塊**：`.codex/`、`.agents/` 那兩行不改。在標記區塊外的 Trellis 段加一句：「The managed block's `.agents/` and `.codex/` lines do not apply here: both are gitignored local state.」
- **本機 `.agents/`**：
  - 先把 `.agents/` 版獨有的「2026-09-07 實測筆記」併進 `.claude/skills/verify-on-device/references/`：Android 的部分進 `android.md`，toast 斷言進 `runtime-state.md`，已有的不重複。
  - 再刪除本機 `.agents/`。它被 gitignore，不影響 repo。
- **check 子代理**：三份都不改。在 Trellis 段加一句：「Claude Code runs `.claude/agents/trellis-check.md` (customised); the `trellis-check` skill and `.trellis/agents/check.md` are Trellis-generated and left as shipped.」
- **journal／archive commit**：Trellis 管理的敘述不改。在 Trellis 段補一句：「With `session_auto_commit: false`, archive and journal steps make no commits: commit task changes by hand.」
- **「Test waits」**：AGENTS.md 的宣稱縮成閘門實際守的範圍：
  > No direct `pumpEventQueue` outside `test/support/pump_until.dart`: use its `pumpUntil` / `drainEventQueue` — `test/support/wait_convention_static_rule_test.dart`.
  - 「條件進入時為 false」「`drainEventQueue` 用於否定」原本就寫在 `.trellis/spec/testing/test-conventions.md:91-94`，不重複。
- **`merge=union` 的指示**：保留。它防的是 `trellis update` 重新加回那一行，這個情況每次更新都可能再發生。

## 6. 實機驗證（已決定 2）→ ADR 0027

新 ADR `0027-on-device-verification.md`，內容：
- 預設重播；
- 改用真實連線的條件與限制；
- 平台分工表；
- skill 在 M1 為 `app/` 改寫，舊 skill 維持原樣；
- 如何確認：
  - `app/AGENTS.md` 的驗證段寫明模式；
  - 回報格式含「模式：重播／真實」；
  - 里程碑驗收表含 Linux 冒煙測試。

ADR 0015、0026 各加一句指向 0027。

## 7. 範圍外

- `app/` 的 spec 放在哪（Trellis `packages:` 或其他）：M1 開 `app/` 時決定。
- 根目錄 AGENTS.md、spec 的翻譯：不做（已決定 1）。
- GitHub 上的 label 清理。

## 8. 驗證

```bash
git grep -n -E "docs/agents|CONTEXT\.md|Agent skills|wayfinder|grill-with-docs" -- . ':!.trellis/tasks/archive' ':!docs/audit'
git grep -n -E "adr/000[1-7]|ADR 000[1-7]" -- . ':!.trellis/tasks/archive' ':!docs/audit'
```

- **第一條**只允許命中：
  - ADR 0012 的併入聲明；
  - parent 任務文件（歷史敘述）；
  - 本任務文件。
- **第二條**只允許命中：
  - 仍存在的 0001–0007 本身；
  - 屬舊專案的引用（切換 PR 處理）；
  - 新 ADR 裡的延續或取代說明。
- 另外跑 `flutter test test/support/wait_convention_static_rule_test.dart`：AGENTS.md 改字不影響它，但確認閘門仍綠。
