# 階段三：Trellis 與文檔清理

## 目標

依 parent prd 的「階段三」與第 9 項的設計（`archive/2026-09/09-27-design-docs` 的 design §1、§2、§4、§6，implement §B）做以下事情：
- 移除 mattpocock 的殘留；
- 收尾舊 ADR 與 `CONTEXT.md`；
- 修正 agent 指令檔之間的衝突；
- 規劃 verify-on-device 如何擴充到新平台，以及實機驗證時如何少打真實 API。

## 現況（`research/current-state.md`，已抽查）

- **mattpocock 殘留**
  - `docs/agents/` 三個檔；AGENTS.md「Agent skills」段（`:7-14`）；`docs/README.md:21,23`。
  - 仍需要的慣例只有一條：「issue 用繁中撰寫」（`docs/agents/issue-tracker.md:43-48`）。
  - 5 個 triage label 與 5 個 `wayfinder:*` label 在 repo 內沒有任何使用者。
- **`docs/README.md`**
  - 地圖表只有三欄，沒有文件類型欄，也沒有 `docs/audit/` 這一列；
  - `:12` 寫 spec 是「英文，給 agent 讀」；
  - `:21` 是中英分工的規則（第 9 項 R7 要刪）。
- **舊 ADR 0001–0007**
  - 只有 0002、0007 加了「只適用舊專案」註記。
  - 0001、0003、0004、0005、0006 沒加，但都已被新 ADR 延續或取代；其中 0001 沒有任何新 ADR 寫「取代」。
  - 引用它們的地方都屬於舊專案：`lib/`、`test/`、`tool/`、`.github/`、`.trellis/spec/`、AGENTS.md、`docs/*.md`。這些在切換 PR 一起處理（ADR 0026）。
- **`CONTEXT.md`**：5 個術語。
  - 4 條原則在 ADR 0012 有對應句（`:16` 已寫明併入）。
  - Media Handoff 的「轉址時每一跳都檢查網域」在所有新 ADR 都沒有對應；舊版在 `source_url_policy.dart:81-122`，轉址目標要在允許清單內，最多 5 次。
  - 引用它的地方：spec 7 處、AGENTS.md `:13`、parent 任務文件。
- **衝突**
  - **AGENTS.md 的 Trellis 區塊**（`:128-130`）提到 `.codex/`（不存在）與 `.agents/`（本機、已 gitignore）。這個區塊由 Trellis 管理，`trellis update` 會覆寫。
  - **本機 `.agents/skills/verify-on-device/`**：與 `.claude/` 版互有對方沒有的內容。
    - `.agents/` 版有 2026-09-07 的實測筆記；
    - `.claude/` 版有 `references/` 與 `msaa_tree.ps1`。
  - **check 子代理三份定義**：Claude Code 實際用的是 `.claude/agents/trellis-check.md`（`workflow.md:237`，已依 AGENTS.md 客製）。另兩份是 Trellis 產生的 skill 與 channel 定義，會被 `trellis update` 覆寫。
  - **journal／archive commit**：三份 Trellis 管理的檔案描述會自動 commit，但 `config.yaml:34` 的 `session_auto_commit: false` 讓它不會發生。
  - **AGENTS.md「Test waits」**（`:93-96`）宣稱三件事，但閘門只守其中一件：禁止直接呼叫 `pumpEventQueue`。
- **Trellis 管理的檔案**：84 個，其中 81 個與模板相同、`trellis update` 會直接覆寫；3 個已客製（`trellis-check.md`、`trellis-implement.md`、`config.yaml`）。AGENTS.md 只有標記區塊內會被覆寫。
- **verify-on-device**
  - 只涵蓋 Android（必要）與 Windows；
  - 跑的是真實 App 對真實音源（`references/runtime-state.md:35-36`）；
  - ADR 0015 的零聯網只管 `flutter test`，不管這個 skill。
- **語言**：
  - 還是英文的只有 AGENTS.md（134 行）與 `.trellis/spec/` 20 檔（1444 行），兩者描述的都是凍結中的舊專案，切換 PR 時會被取代。
  - `docs/` 與 ADR 已是繁中。

## 已決定

1. **語言範圍**（2026-09-28，擁有者「按你建議」，縮小第 9 項 R7 的適用範圍）：
   - 根目錄 AGENTS.md 與 `.trellis/spec/` 描述凍結中的舊專案，維持英文到切換 PR，只做本次清理必要的修改；
   - `app/AGENTS.md` 與 `app/` 的 spec 從 M1 起用繁中；
   - `docs/README.md` 的中英分工規則改寫為：「新文件一律繁中；根目錄 AGENTS.md 與 `.trellis/spec/` 描述舊專案，維持英文到切換 PR」。
   - 理由：翻譯約 1,600 行即將被取代的內容；舊專案緊急修正時仍要依這些規則，改寫措辭有改掉規則原意的風險。

## 待決定（一次問一題）

2. verify-on-device 在新平台怎麼擴充，以及實機驗證時預設用真實連線還是重播。

## 驗收條件

- [ ] 兩條 `git grep`（第 9 項 implement §B）只命中刻意保留的檔案。
- [ ] `docs/agents/`、`CONTEXT.md` 已刪除；「issue 用繁中撰寫」寫進 AGENTS.md。
- [ ] 舊 ADR 0001、0003–0006 都有「只適用舊專案」註記。
- [ ] ADR 0012 補上 Media Handoff 的轉址網域檢查原則。
- [ ] 第 9 項 design §6 的衝突各有處置，並記在 AGENTS.md 的 Trellis 段（標記區塊外）。
