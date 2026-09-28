# 階段三待決事項（open-questions）

只列 **repo 自己回答不了、必須由擁有者決定** 的事。每項先列相關事實（附 file:line），不給建議。

---

## 1. 根目錄 `AGENTS.md` 與 `.trellis/spec/` 的翻譯時機

**決定點**：階段三就翻成繁中，還是留到最後里程碑的切換 PR。

事實：

- 兩者描述的是**凍結中的舊專案**：`AGENTS.md` 開頭即說 FMP 是「Flutter music player for Android and Windows that plays from Bilibili, YouTube and NetEase」，即舊版；`docs/adr/0008-rewrite-as-new-app-in-same-repo.md:45-46` 說舊專案留根目錄、凍結，`app/` 有自己的 `AGENTS.md`（agents.md 慣例：讀離它最近的那一份）。→ 根目錄 `AGENTS.md` 與 `.trellis/spec/` 的 20 檔在切換 PR 會隨舊專案一起消失。
- 體量：`AGENTS.md` 134 行（含漢字行 1）；`.trellis/spec/` 6 層 20 檔共 1444 行（含漢字行共 3）。`docs/` 與 `docs/adr/*` 已是繁中（`docs/README.md` 76%、`docs/build-and-release.md` 47%、ADR 平均 65–90%）。→ R7 未落地的部分**只有這兩塊**。
- R7 的原文：`prd.md:28`「所有文檔繁中（含 ADR、`docs/`）」；`design.md:18` 另說 README 例外、維持英／繁雙語。
- 七處 `CONTEXT.md` 引用（`.trellis/spec/data/index.md:9`、`data/sources.md:81`、`guides/cross-layer-thinking-guide.md:51`、`services/download-and-auth.md:3,38`、`services/index.md:8,24`）無論如何都要改（`design.md:62`、`implement.md:20`），改句子時會動到檔內其他行。
- `.trellis/spec/` 的規則本身沒有閘門測試守著（`AGENTS.md:75-76` 只對 `test/**/static_rules/` 的規則宣告閘門）。翻譯不算行為變更，沒有測試會紅。
- 翻譯後 `docs/README.md:12` 的「（英文，給 agent 讀）」需要同步改。

---

## 2. `app/` 的 spec 放哪

**決定點**：`.trellis/spec/<layer>/` 沿用單一層集，還是啟用 Trellis 的 monorepo `packages:` 分層。

事實：

- `.trellis/config.yaml:57-78` 有一段 **`packages:` 區塊，目前整段被註解掉**；`:62-75` 是 Trellis 的範例（`- path: packages/frontend`、`layers: [...]` 形式）。→ 這個機制存在但目前未啟用。
- `.trellis/spec/` 現在是單層集：`data`、`guides`、`services`、`shared`、`testing`、`ui` 六個子目錄，**沒有頂層 `index.md`**（`.trellis/config.yaml:144-147` 的 context-injection caps 也沒區分 package）。
- 目前的 spec **全部描述舊專案**：`.trellis/spec/data/persistence.md:3` 引 ADR 0007、0002；`services/audio.md:3` 引 ADR 0003；`services/download-and-auth.md:3` 引 ADR 0004；`data/index.md:22-25` 引 ADR 0001、0005、0002。→ 這些 ADR 都在切換 PR 刪除，這些 spec 檔也隨舊專案結束。
- `app/` **還不存在**（`ls -d app` → No such file or directory）。`docs/adr/0008-...md:46` 說 `app/` 會有自己的 `AGENTS.md`，但沒說 spec 放哪。
- `docs/adr/0015-...md:96` 要求「`AGENTS.md`（`app/`）列出的每條靜態規則都寫出對應規則名；沒有規則守的不寫進去」→ `app/` 的 spec 內容要被 `app/AGENTS.md` 引用。
- Trellis 的 spec 載入路徑寫死 `.trellis/spec/<package>/<layer>/index.md`（`.claude/skills/trellis-check/SKILL.md:34`、`.trellis/workflow.md`）；子代理的 context 由 `python ./.trellis/scripts/get_context.py --mode packages` 決定（`.claude/skills/trellis-check/SKILL.md:28`）。
- `AGENTS.md:104-106`（Trellis 段，在 managed 區塊外）已把規則分工定成「binding rules 在 `AGENTS.md`、`.trellis/spec/<layer>/` 寫該層怎麼寫」——這是舊專案的形狀。

---

## 3. `verify-on-device` 的平台延伸與真實 API 曝險

**決定點**：Linux VM、macOS runner、iOS 模擬器各自要驗什麼、用什麼指令；以及如何降低打真實 API 的比例。

事實：

- 現況 skill 只覆蓋 **Android（必要）＋ Windows（Windows 專屬改動才加）**：`.claude/skills/verify-on-device/SKILL.md:15-18`。`:20-21` 的驗證環境寫死 Windows 11 host、AVD `Medium_Phone`、Flutter 3.47.x。reference 只有 `android.md`、`windows.md`、`runtime-state.md`，`scripts/` 只有 `ax_flatten.py`、`msaa_tree.ps1`、`smtc_probe.ps1`。
- AGENTS.md 的規則把 on-device 綁在 Android emulator：`AGENTS.md:37-42`「Run the `verify-on-device` skill on the Android emulator (add Windows only for Windows-specific work)…When the emulator cannot come up or the change cannot be reached, report that blocker by name」。
- skill **會打真實來源**：`.claude/skills/verify-on-device/references/runtime-state.md:35-36`「all three sources can be unavailable at once on a dev machine (Bilibili `playurl` answering HTTP 412, YouTube demanding sign-in, nothing downloaded)」；`references/android.md:62` 教用 `adb shell svc wifi disable` 製造 `Failed host lookup` 以到達真正的錯誤路徑——反向說明正常路徑是打真 API 的。
- ADR 0015 的零聯網機制**不含**這個 skill：`docs/adr/0015-...md:55-56` 的 `dart_test.yaml` `live` skip preset 與 `HttpOverrides.global` 只管 `flutter test`；skill 跑的是真實 `flutter run`。
- ADR 0015 另有可用的重播槓桿：`:59-66` fixture 錄製／重播在 dio `HttpClientAdapter`，`:58`「檢查案例一份四用」含 Debug 頁健康檢查（真實連線，App 內）；`:65-66` 開發者模式可「每插件切換真實／錄製／重播」。
- 平台任務的排程已定：`docs/adr/0026-milestones-and-cut-over.md:84-91`——Linux 在 M1 之後開，驗收在 VMware Workstation Pro 的 Ubuntu LTS VM，**X11 與 Wayland 各一次**，日常開發用 WSL2，之後每個里程碑在 VM 跑一次冒煙測試；macOS／iOS 在 Mac 到貨後開，到貨前只靠 GitHub macOS runner 編譯與 iOS 模擬器測試（ADR 0009）。
- `docs/adr/0026-...md:90`：iOS 要不要實機、要不要付費帳號，**留給該任務決定**。
- `AGENTS.md:23`（Verification 表）：UI 變更的最小驗證是 `test/ui` 目標測試＋`flutter analyze`＋on-device。Linux／macOS／iOS 的 UI 變更算不算「user-visible change」需不需要各自 on-device，表上沒寫。
- 本機另有一份 **`.agents/skills/verify-on-device/SKILL.md`（399 行／22166 bytes）**，與 `.claude/` 版不同（見 § 4 與 current-state § g.4）。

---

## 4. 本機 `.agents/` 怎麼處理

**決定點**：`.agents/` 刪掉、保留、還是把它的內容併回 `.claude/skills/verify-on-device/`。

事實：

- `.agents/` **存在但被 gitignore**：`.gitignore:95` `/.agents/`（同在 local agent/tool state 段，`:93` `/.codex/`、`:92` `/.trellis/workspace/`）。另 `.trellis/.gitignore:14` 也有 `.agents/`（指 `.trellis/` 底下，不同路徑）。
- 內容是 `.agents/skills/verify-on-device/`：`SKILL.md` 399 行／22166 bytes（Sep 10 19:14）、`scripts/` 只有 `ax_flatten.py`、`smtc_probe.ps1`（**缺** `msaa_tree.ps1`）、**沒有** `references/`。
- `.claude/skills/verify-on-device/`：`SKILL.md` 149 行／6206 bytes（Sep 25 14:58）＋ `references/{android,windows,runtime-state}.md` ＋ `scripts/` 三支。
- 兩份**互有對方沒有的東西**：`.agents` 版 `SKILL.md` 尾端有「Measured during the 2026-09-07 UI acceptance run」實測筆記（`adb shell am force-stop` 會讓 `flutter run` 靜默失效、toast 斷言要靠 burst screenshot 等）；`.claude` 版有拆出的 references 與 `msaa_tree.ps1`。
- `design.md:73` 說它是「stale copy of the one in `.claude/skills/`」；`implement.md:21`（§B.5）說「also delete the local `.agents/`」。
- `AGENTS.md:128-130`（Trellis managed 區塊內）仍宣告 `.agents/skills/` 是 "reusable Trellis skills"、`.codex/agents/` 是 "optional custom subagents"；`.codex/` **不存在**。
- `.claude/settings.json:72` `"enabledPlugins": {}`；`git grep` 查不到任何 `.agents/skills` 的讀取端（除了 `AGENTS.md:129`）。

---

## 5. `docs/agents/` 哪些慣例留下、哪些隨目錄刪除

**決定點**：parent prd 說「若『issue 用繁體中文撰寫』等慣例仍需要，搬一句到 `AGENTS.md`」——「等」字要涵蓋哪些？5 個 triage label 與 5 個 `wayfinder:*` label 要不要保留在 repo 內？

事實：

- **唯一被 repo 內其他檔案引用、且是 FMP 專屬的慣例**是 issue 語言規則：`docs/agents/issue-tracker.md:43-48`（標題／內文繁中、識別字與 label 英文），它**回指 `docs/README.md § 分工`**，而 `docs/README.md:21` 依 R7 要刪 → 搬移時那句話要改寫或移除引用。
- 同族政策另散在兩處：`docs/agents/domain.md:49-53`（ADR 用繁中、`CONTEXT.md` 保留英文術語名）、`docs/README.md:21`（語系分工）。三處講同一件事。
- **5 個 triage label 字串**（`docs/agents/triage-labels.md:5-11`：`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）在 repo 內**零消費者**：`git grep -n -E "needs-triage|needs-info|ready-for-agent|ready-for-human|wontfix"` 排除 archive 與 `docs/agents` 後無命中；`.github/` 只有 `dependabot.yml` 與 `workflows/`，**沒有** `ISSUE_TEMPLATE/`（且 `issue-tracker.md:18-21` 說這是刻意的）。
- **5 個 wayfinder label**（`docs/agents/issue-tracker.md:52-59`）同樣零消費者。
- `docs/agents/issue-tracker.md:9-14` 的 gh 操作慣例（create／view／list／comment／label／close）在 repo 內沒有第二份。
- `docs/agents/domain.md` 整份繞著 `CONTEXT.md`（`:5,9,19,30,39,52`），而 `CONTEXT.md` 在階段三要刪；`:47` 的範例引用「ADR-0007 (event-sourced orders)」與本 repo 的 ADR 0007 無關，是模板殘留。
- `docs/README.md:23` 說這三個檔是 `/setup-matt-pocock-skills` 的產出加 FMP 修改，重跑該 skill 會覆蓋；`.claude/settings.json:72` `enabledPlugins: {}`，那些 skill 來自使用者全域環境。
- **無法從 repo 回答**：GitHub 上實際存在哪些 label（要連網查 `gh label list`），以及別人的 issue 目前有沒有在用這套 label。

---

## 6. 5 份舊 ADR 的「只適用舊專案」註記何時加

**決定點**：現在補，還是留到切換 PR。

事實：

- 規則本身：`docs/adr/template.md:7`「被取代的舊 ADR 若仍描述凍結中的根目錄舊專案，改在舊檔開頭加註「只適用舊專案」，於切換 PR 隨舊專案刪除（ADR 0008）」。
- 現況 **2/7 已加**：`docs/adr/0002-repository-boundary.md:3`、`docs/adr/0007-isar-stays-on-v3.md:3`（兩句都寫「本檔在切換 PR 隨舊專案刪除（ADR 0008）」）。
- **5 份未加**：`0001-...md`、`0003-...md`、`0004-...md`、`0005-...md`、`0006-...md`（檔頭只有標題＋狀態／日期／影響範圍）。
- 加的成本很低（一行），但**這 5 份都在 `.trellis/spec/` 與舊專案程式碼裡被引用**（見 current-state § c.3），改檔頭不會動到引用。
- 5 份都被新 ADR 明示延續或取代（0003→`0018:17`；0004→`0020:18`；0006→`0022:19`；0005→`0010:45`、`0019:39`；0001 無任何新 ADR 寫「取代 ADR 0001」）。
- 切換 PR 的刪除清單已寫死：`docs/adr/0026-...md:122`、`.trellis/tasks/09-26-fmp-rewrite/milestones.md:120`、`phase2-plan.md:255`。

---

## 7. `AGENTS.md` 的「Test waits」宣稱要縮窄還是補閘門

**決定點**：改寫 `AGENTS.md:93-96` 的文字讓它只宣稱實際守得到的範圍，還是為 `pumpUntil` 條件／`drainEventQueue` 用法補上真閘門。

事實：

- 宣告：`AGENTS.md:93-96` 一條 bullet 同時宣稱三件事——`pumpUntil` 的條件「false on entry」、`drainEventQueue` 用於否定斷言、固定 pump 次數不穩——並在句尾掛上測試名 `test/support/wait_convention_static_rule_test.dart`。
- 實際閘門：`test/support/wait_convention_static_rule_test.dart`（99 行）**只**掃 `test/` 下有沒有非註解行直接呼叫 `pumpEventQueue`：`:21-30` 用 `RegExp(r'\bpumpEventQueue\b')`；`:11-15` allowlist 只有 `test/support/pump_until.dart`、`test/support/pump_until_test.dart`、本檔；`:48` `expect(scanned, greaterThan(200))` 防空過。
- **沒有**任何測試檢查「`pumpUntil` 的條件在進入時為 false」，也**沒有**檢查 `drainEventQueue` 的用法。後兩者只是 `test/support/pump_until.dart` 的 dartdoc 要求（`:19-20`）。
- `drainEventQueue` 有 20+ 實際使用點（例：`test/providers/account_status_check_test.dart:97`、`test/services/audio/audio_controller_handoff_and_errors_test.dart:173`、`test/services/audio/audio_controller_queue_test.dart:74`），但沒有規則描述「什麼時候該用它」。
- 全域規則（`~/.claude/CLAUDE.md`）說「沒有閘門的規則靠運氣被遵守」「新加的靜態規則要在測試檔內做雙向變異驗證」；`AGENTS.md:75-76` 自己也說 static-rule tests 的例外清單「add an entry with a reason, delete it when it goes away」。
- 這條文字**在 managed 區塊外**（`AGENTS.md:114` 的 `<!-- TRELLIS:START -->` 之前），所以改它不會被 `trellis update` 覆蓋。

---

## 8. 重複的 check 子代理要怎麼「修」

**決定點**：`design.md:74` 說「fix the duplicate check sub-agent」——三份定義要刪／合併哪一份，或在 `AGENTS.md` 補說明。

事實：

- 三份並存，各有不同角色，**都在 `.trellis/.template-hashes.json` 的 84 筆受管清單內**，`trellis update` 會覆寫：
  1. `.claude/agents/trellis-check.md`（122 行）— Claude Code subagent；`:86` 指向 `AGENTS.md § Verification`，`:90` 說 on-device 它跑不了。**本機已客製**（雜湊不符）。
  2. `.claude/skills/trellis-check/SKILL.md`（111 行）— Claude Code Skill；**通用版，不含 FMP 內容**（無 § Verification、無 on-device）。雜湊相符。
  3. `.trellis/agents/check.md`（70 行）— Trellis channel runtime 定義（`:11` `trellis channel spawn --agent check`；`:34-38` 禁止 git commit／push／merge）。雜湊相符。
- `AGENTS.md:107-108`（managed 區塊外）已明說要保留本機的 `.claude/agents/trellis-check.md` 與 `trellis-implement.md`（它們的 Verify 步驟跑 § Verification）→ 刪它會違反這條已寫下的客製。
- `.trellis/workflow.md:237`「`trellis-check` exists as both; prefer the **Agent** form when verifying after code changes」→ 官方立場傾向 agent 版；`.trellis/workflow.md` 全檔沒有引用 `.trellis/agents/`。
- 本 repo 沒有 channel 設定：`.trellis/config.yaml:103-109` 只有註解掉的範例。→ 第 3 份目前沒有啟動路徑。
- `docs/audit/engineering.md:440,446` 記錄了審計當時讀到的 check-agent 與 `.trellis/agents/` 狀況（凍結快照，僅供參照）。
- 任何對第 2、3 份的刪改都會被下次 `trellis update` 還原（只有第 1 份因已客製而「留得住」）。

---

## 9. journal／archive commit 的敘述與 `session_auto_commit: false` 怎麼對齊

**決定點**：改敘述檔（會被 `trellis update` 覆寫）、改設定、還是在 `AGENTS.md` 客製段加一段說明。

事實：

- 設定：`.trellis/config.yaml:34` `session_auto_commit: false`；`:21-33` 的說明寫「false: scripts do not touch git」；`:33` 有一行 FMP 客製註解「FMP: journals live in the gitignored `.trellis/workspace/` (public repo)」。**`config.yaml` 本機已客製**（雜湊不符）。
- 敘述（三個檔案都說會產生 commit）：
  - `.claude/commands/trellis/finish-work.md:51`「Each archive produces a `chore(task): archive ...` commit **via the script's auto-commit**」
  - `.claude/commands/trellis/finish-work.md:64`「This produces a `chore: record journal` commit」
  - `.claude/commands/trellis/finish-work.md:66` 排出 git log 順序
  - `.trellis/workflow.md:604`「work commits FIRST, then bookkeeping (archive + journal) commits land after」
  - `.trellis/workflow.md:647`「three-stage three-commit flow (work commits → archive commit → journal commit)」
- 這三個檔**都在** `.trellis/.template-hashes.json` 內且目前雜湊相符 → `trellis update` 會覆寫任何改動。
- `.trellis/config.yaml:12` `session_commit_message: "chore: record journal"`（訊息模板仍在，只是 `session_auto_commit: false` 讓它不自動跑）。
- `.trellis/workspace/` 確實被 gitignore：`.gitignore:92`。實際的 journal 有寫入（`.trellis/workspace/1morr/journal-1.md`，75 行）。
- `AGENTS.md:107-112`（managed 區塊外）已把「journals stay local…`session_auto_commit: false`」寫成要保留的客製，但沒說那三個敘述檔怎麼辦。
- `design.md:77` 對另一條 workflow 衝突（3.4 不 push vs 全域直接 push）判定為「層級不同、repo 內不衝突、保留原文」；journal 這條沒有同樣的判定。

---

## 10. `docs/README.md:22` 那條 Trellis 接線敘述要不要同步

**決定點**：`docs/README.md:22` 現在描述 `.claude/skills/` 與 gitignore 追蹤範圍，但沒提「journal 留本機」「`.agents/`」「`AGENTS.md` 的 Trellis 段」——要不要補成與 `AGENTS.md:107-112` 一致。

事實：

- `docs/README.md:22`「`.claude/skills/` 放 Claude Code skill；`.gitignore` 另外追蹤 Trellis 接線（`.claude/` 下的 `agents/`、`commands/`、`hooks/`、`settings.json`）；`.claude/` 其餘與 `.trellis/workspace/` 是本機狀態。」
- 實際 gitignore：`.gitignore:85-90`（`.claude/*` 加 negations 追蹤 `skills/`、`agents/`、`commands/`、`hooks/`、`settings.json`）、`:92` `/.trellis/workspace/`、`:93` `/.codex/`、`:95` `/.agents/`。→ `:22` 的敘述與 gitignore 一致，但漏了 `.agents/`、`.codex/` 與 journal 留本機的理由。
- `AGENTS.md:107-112` 是這些客製的唯一書面出處；`docs/README.md:20`「同一條規則只寫在一個地方」→ 兩處是否算同一條規則需判斷。
- `docs/README.md` 不在 `.trellis/.template-hashes.json` 內 → 改它不會被 `trellis update` 覆寫。
- `docs/README.md` 本來就要因 R7 改（`:21` 刪、`:12` 改、`:15` 刪、`docs/audit/` 補列）。

---

## 11. `docs/README.md` 是否要新增 `docs/audit/` 一列

**決定點**：`implement.md:18` 說「`docs/audit/` 註明為凍結快照」——是加一列進地圖表，還是在別處寫一句。

事實：

- 現況地圖表（`docs/README.md:5-15`）**沒有** `docs/audit/` 一列。
- `docs/README.md:24`「審查記錄不進 `docs/`。一輪審計的結論寫進它所描述的檔案、開成 issue，或留在 git 歷史。」與 `docs/audit/` 的存在表面衝突；`design.md:66` 說凍結期保留這個例外，最後里程碑刪 `docs/audit/` 並恢復無例外。
- `docs/audit/` 目前有 13 檔（`architecture.md`、`engineering.md`、`questions.md`、`perf-baseline.md`、`data.md`、`ui.md` 等，`ls docs/audit/`），被 `docs/adr/0008`（`:12,53,55`）、`0015`（`:10`）、`0026`（`:17,95`）等多處引用。
- 地圖表要在 `implement.md:18` 同時「加 Diátaxis 類型欄」——加欄與加列是同一張表的兩個改動。

---

## 12. `.gitattributes` 的 journal `merge=union` 目前不存在，要不要留一句

**決定點**：`AGENTS.md:111-112` 說「若 update 又把 journal 的 `merge=union` 行加回 `.gitattributes`，就把它拿掉」——這條指示是繼續留著當防守，還是連同情況消失一起移除。

事實：

- `.gitattributes`（17 行）**沒有** `merge=union` 行（`grep -n merge=union .gitattributes` 零命中）。→ 現況已符合要求，指示目前沒有觸發條件。
- `.gitattributes` 內容是 `text=auto`、`*.ps1 text eol=crlf`、二進位標記、`pubspec.lock linguist-generated=true`。
- 這條指示在 `AGENTS.md:111-112`（managed 區塊外），是防 `trellis update` 重新加回而寫的。
- 全域規則說「沒有閘門的規則靠運氣被遵守」「撤掉一條閘門時，同一個 commit 要交代接手的是什麼」；這條屬「防守未來 update」而非現行規則。
