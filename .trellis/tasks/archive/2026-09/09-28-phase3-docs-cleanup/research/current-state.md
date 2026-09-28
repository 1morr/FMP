# 階段三現況盤點（current-state）

- 盤點對象：branch `docs/audit`，HEAD `94b2a3e2`。
- 除特別註明，`file:line` 皆指 repo 根目錄下的檔案；指令在 repo 根目錄執行。
- 依研究指示排除 `.trellis/tasks/archive/`（歷史紀錄，不改）與 `docs/audit/`（凍結快照）。
- 證據優先序：程式碼與測試 > 文件敘述。凡引用 `docs/audit/` 者只在「佐證文件自己的宣稱」時使用。

---

## a. mattpocock 殘留

### a.1 `docs/agents/` 三個檔的內容

`docs/agents/` 共 3 檔（`ls docs/agents/`）：`domain.md`、`issue-tracker.md`、`triage-labels.md`。

**`docs/agents/domain.md`（53 行）**

- `:5` 宣告本 repo 是 **single-context**：root 一份 `CONTEXT.md` ＋ 一份 `docs/adr/`。這個檔名慣例來自 mattpocock 的 domain-modeling skill（`docs/audit/engineering.md:477`）。
- `:7-11` 「探索前先讀」：`CONTEXT.md`（source auth 與 media handoff 的 ubiquitous language）＋ `docs/adr/`（讀與你工作範圍相關的 ADR）。
- `:13` 提到 `/domain-modeling`、`/grill-with-docs`、`/improve-codebase-architecture` 三個 skill 名稱。
- `:15-24` 三份文件的分工：`CONTEXT.md` 管 vocabulary、`docs/adr/` 記 why、`AGENTS.md` 記 binding rules。這一段與 `design.md` §2 的分工表同義，但用詞是模板的。
- `:26-35` 檔案結構圖（`CONTEXT.md` / `AGENTS.md` / `docs/adr/NNNN-<slug>.md` / `lib/`）。
- `:37-41` 要求輸出用 glossary 的詞（例：寫 **Media Request Credentials** 不要寫 "playback headers"）。
- `:43-47` 「Flag ADR conflicts」，範例引用 **「ADR-0007 (event-sourced orders)」** —— 與本 repo 的 ADR 0007（Isar 停在 v3）無關，是模板殘留字串。
- `:49-53` 語言政策：ADR 用繁中（台港用語）；`CONTEXT.md` 保留英文術語名。**這條與 `docs/README.md:21` 的「中英分工」是同一個政策**，而 `docs/README.md:21` 依 design-docs R7 要刪。

**`docs/agents/issue-tracker.md`（58 行）**

- `:3-5` Issues/PRD 用 GitHub Issues on `1morr/FMP`，一律用 `gh`。
- `:9-14` gh 操作慣例：create / view / list / comment / label / close（含 `--json`＋`jq` 範例）。
- `:16-21` 「刻意沒有 issue template」：觸發條件是「**第一個非擁有者開的 issue**」，不是 repo 大小。
- `:25` `PRs as a request surface: **no**`（旗標供 `/triage` 讀）。
- `:35-41` 「skill 說 publish to the issue tracker」→ 開 GitHub issue。
- `:43-48` **語言**：issue 標題與內文用繁中（台港用語）；code identifier、log string、commit message、branch name、label string 保留英文；**並回指 `docs/README.md § 分工`**（該節在階段三會被改寫）。
- `:50-59` **Wayfinding operations**（`/wayfinder` 用）：map 是單一 issue（label `wayfinder:map`）、child ticket 用 sub-issue、blocking 用 GitHub native issue dependencies、frontier query、claim、resolve。用到 5 個 label 字串：`wayfinder:map`、`wayfinder:research`、`wayfinder:prototype`、`wayfinder:grilling`、`wayfinder:task`。

**`docs/agents/triage-labels.md`（17 行）**

- `:5-11` 五個 triage 角色的 label 對照表，左欄（mattpocock/skills）與右欄（our tracker）**逐列相同**：`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`。
- `:15-17` 「FMP uses the defaults unchanged」；label string 保留英文，即使 issue body 是繁中。

### a.2 AGENTS.md「Agent skills」段

`AGENTS.md:7-14`，只有三條 bullet，全部指向 `docs/agents/`：

- `AGENTS.md:9-10` Issue tracker → `docs/agents/issue-tracker.md`
- `AGENTS.md:11-12` Triage labels → `docs/agents/triage-labels.md`
- `AGENTS.md:13-14` Domain docs（single-context: `CONTEXT.md` + `docs/adr/`）→ `docs/agents/domain.md`

`AGENTS.md` 全檔除這段外，只有 `:82` 引到 ADR 0002（見 § c）。

### a.3 design-docs implement §B 的兩條 git grep 結果

指令原文 `implement.md:27`：

```
git grep -n -E "docs/agents|CONTEXT\.md|Agent skills|wayfinder|grill-with-docs" -- . ':!.trellis/tasks/archive' ':!docs/audit'
git grep -n -E "adr/000[1-7]|ADR 000[1-7]" -- . ':!.trellis/tasks/archive' ':!docs/audit'
```

**第 1 條命中（`implement.md:27`）**

| 檔案:行 | 命中的字串 |
|---|---|
| `AGENTS.md:7` | `## Agent skills` |
| `AGENTS.md:10,12,14` | `docs/agents/...` |
| `AGENTS.md:13` | `CONTEXT.md` |
| `docs/README.md:21` | `docs/agents/` |
| `docs/README.md:23` | `docs/agents/`（並提到 `/setup-matt-pocock-skills`） |
| `docs/adr/0012-network-layer-and-accounts.md:16` | `CONTEXT.md`（併入聲明） |
| `docs/agents/domain.md:5,9,13,19,30,39,52` | `CONTEXT.md`；`:13` 另有 `/grill-with-docs` |
| `docs/agents/issue-tracker.md:52,54,55` | `/wayfinder`、`wayfinder:map`、`wayfinder:<type>` |
| `.trellis/spec/data/index.md:9` | `CONTEXT.md` |
| `.trellis/spec/data/sources.md:81` | `CONTEXT.md` |
| `.trellis/spec/guides/cross-layer-thinking-guide.md:51` | `CONTEXT.md` |
| `.trellis/spec/services/download-and-auth.md:3,38` | `CONTEXT.md` |
| `.trellis/spec/services/index.md:8,24` | `CONTEXT.md` |
| `.trellis/tasks/09-26-fmp-rewrite/phase2-plan.md:23,113,209,258` | `CONTEXT.md` |
| `.trellis/tasks/09-26-fmp-rewrite/prd.md:13,18,85,86,88,92,186,190` | `CONTEXT.md`、`docs/agents`、`Agent skills` |
| `.trellis/tasks/09-28-phase3-docs-cleanup/prd.md:5` | `CONTEXT.md`（英文描述行） |
| `.trellis/tasks/09-28-phase3-docs-cleanup/task.json:5` | `CONTEXT.md`（英文描述行） |

**第 2 條命中（舊 ADR 編號）**：見 § c.3 的分組表。

兩條都還有大量命中；設計要求的「只能命中仍存在、刻意保留的檔案」目前尚未達成。

### a.4 `.trellis/spec/` 的 7 處 `CONTEXT.md` 引用（design.md §4 指定的清單）

`design.md:62` 與 `implement.md:20` 點名 7 處：`.trellis/spec/data/index.md:9`、`data/sources.md:81`、`guides/cross-layer-thinking-guide.md:51`、`services/download-and-auth.md:3`、`services/download-and-auth.md:38`、`services/index.md:8`、`services/index.md:24`。實際 grep 命中與此清單完全一致（另加 `AGENTS.md:13`、`docs/adr/0012:16`、`docs/README.md` 間接、`docs/agents/*` 本身）。

### a.5 哪些慣例仍需要、哪些沒有消費者

**仍需要（design.md:72、R6 只保留這一條）：**

- **「issue 用繁中撰寫」**：`docs/agents/issue-tracker.md:43-48`。同一條 policy 也寫在 `docs/agents/domain.md:49-53`（ADR 用繁中）與 `docs/README.md:21`（語系分工）。parent prd `prd.md:187` 明說「若『issue 用繁體中文撰寫』等慣例仍需要，搬一句到 AGENTS.md」。

**repo 內查不到消費者（`git grep -n -E "needs-triage|needs-info|ready-for-agent|ready-for-human|wontfix|wayfinder"` 排出 archive、`docs/agents` 後零命中）：**

- `triage-labels.md` 的 5 個 label 字串：沒有任何 workflow、script、hook、`.claude/` 設定引用。
- `wayfinder:*` 5 個 label 字串：同樣零命中。
- `.github/` 只有 `dependabot.yml` 與 `workflows/`（`ls .github/`），**沒有** `.github/ISSUE_TEMPLATE/`（`docs/agents/issue-tracker.md:18-21` 說這是刻意的）。
- 反之，`issue-tracker.md:9-14` 的 gh create/view/list/comment/label/close 慣例是通用 `gh` 用法，repo 內也沒有別的檔案寫。

**`docs/agents/domain.md` 的前提已經消失**：它整份繞著 `CONTEXT.md`（`:5,9,19,30,39,52`）—— 而 `CONTEXT.md` 在階段三要刪（design.md §4、`implement.md:20`）。

**沒有 CLAUDE.md**：`design.md:14` 與 `docs/audit/engineering.md:626` 都指出本 repo 沒有 `CLAUDE.md`，Claude Code 直接載入 `AGENTS.md`；`.claude/settings.json:72` `"enabledPlugins": {}`，mattpocock skills 來自使用者全域環境，不是專案設定。

---

## b. `docs/README.md`

（全文 25 行，`docs/README.md`）

### b.1 現況地圖

`docs/README.md:3` 開頭：root `README.md` 是產品入口；AI agent 規則在 `AGENTS.md`，人類貢獻者適用同一套。

表頭 `:5-6`：「文件 | 什麼時候讀 | 什麼變了要更新它」——**只有三欄，沒有文件類型欄**。

| 列 | 文件 | 備註 |
|---|---|---|
| `:7` | `README` | 產品入口；使用者可見功能、截圖、下載入口、專案定位 |
| `:8` | `building.md` | 本機建置 |
| `:9` | `development.md` | 架構與主要模組；VM Service 查 running app |
| `:10` | `build-and-release.md` | 發版、CI、產物命名、簽名 secrets、應用內更新資產 |
| `:11` | `troubleshooting.md` | 建置或 runtime log 噪音、繞不過的行為 |
| `:12` | `.trellis/spec/` | 明寫 **「（英文，給 agent 讀）」** |
| `:13` | `adr/` | 跨模組決定「當初為什麼這樣選」 |
| `:14` | `verify-on-device skill`（`.claude/skills/verify-on-device/SKILL.md`） | 改了使用者可見行為的強制實機驗證 |
| `:15` | `agents/` | **「（給 engineering skills 讀，不是給人讀）」**；更新時機寫「換 issue 追蹤系統或標籤詞彙」 |

**沒有 `docs/audit/` 這一列。**

`## 分工`（`:17-24`）共 6 條：

- `:19` 單段程式碼的理由寫在旁邊；只有程式碼查不到的跨檔契約與地雷才進 `AGENTS.md`。
- `:20` 同一條規則只寫在一個地方。
- `:21` **語系分工**：「`AGENTS.md`、`docs/agents/` 與 `.trellis/spec/` 維持英文…`docs/` 其餘文件與根目錄 `README.zh-Hant.md` 以繁體中文撰寫。」
- `:22` `.claude/skills/` 放 Claude Code skill；`.gitignore` 另外追蹤 Trellis 接線（`.claude/` 下的 `agents/`、`commands/`、`hooks/`、`settings.json`）；`.claude/` 其餘與 `.trellis/workspace/` 是本機狀態。
- `:23` **`docs/agents/` 三個檔是 `/setup-matt-pocock-skills` 的產出再加上 FMP 專屬修改**（repo 釘死 `1morr/FMP`、繁中語言政策），重跑那個 skill 會用泛用模板覆蓋。
- `:24` 「審查記錄不進 `docs/`。一輪審計的結論寫進它所描述的檔案、開成 issue，或留在 git 歷史。」

### b.2 依 design-docs §1／§B.2 要改的地方

- `implement.md:18`（§B.2）：地圖表**加 Diátaxis 類型欄**；刪 `:21` 的中英分工規則；刪 `:23` 的 `docs/agents/` 說明；`docs/audit/` 註明為**凍結快照**。
- `design.md:10`（§1 地圖）：`docs/*.md` 讀者是「人類開發者」，放操作指南／參考／說明，**不放 agent 規則**；採 Diátaxis，且「不預建四個空資料夾」，地圖表加一欄標每份文件的類型。
- `design.md:18`＋R7（`prd.md:28`）：**所有文檔繁中**（含 ADR、`docs/`）；README 例外維持英／繁雙語。→ `:21` 整條刪；`:12` 的「（英文，給 agent 讀）」與 R7 衝突，需改。
- `:15` 的 `agents/` 列依 `implement.md:18` 一起刪（`docs/agents/` 整個目錄刪除）。
- `:24` 與 `docs/audit/` 的例外：`design.md:66` 說凍結期保留這個例外，**最後一個里程碑**的 PR 刪 `docs/audit/` 並把 `:24` 恢復成無例外。
- `:22` 的 Trellis 接線敘述需與 AGENTS.md「Trellis」段（`AGENTS.md:107-112`）一致：目前 `:22` 沒提 journal 留本機與 `.agents/`。

---

## c. 舊 ADR 0001–0007

檔案行數：0001 138、0002 77、0003 104、0004 77、0005 101、0006 101、0007 54。

### c.1 是否已有「只適用舊專案」註記

`git grep -n "只適用舊專案" -- . ':!.trellis/tasks/archive'` 只有 **`docs/adr/template.md:7`**（規則本身）。實際加註的只有兩份：

| ADR | 註記 | 位置 |
|---|---|---|
| 0002 | **有** | `docs/adr/0002-repository-boundary.md:3`：「只適用根目錄舊專案；新專案（`app/`）見 ADR 0010…本檔在切換 PR 隨舊專案刪除（ADR 0008）。」 |
| 0007 | **有** | `docs/adr/0007-isar-stays-on-v3.md:3`：同句。 |
| 0001 | 無 | 檔頭 `0001-...md:1-5` 只有標題＋狀態／日期／影響範圍 |
| 0003 | 無 | 同上（`:1-5`） |
| 0004 | 無 | 同上（`:1-5`） |
| 0005 | 無 | 同上（`:1-5`） |
| 0006 | 無 | 同上（`:1-5`；狀態是「已實作」不是「已採納」） |

`docs/adr/template.md:7` 的例外規則：「被取代的舊 ADR 若仍描述凍結中的根目錄舊專案，改在舊檔開頭加註「只適用舊專案」，於切換 PR 隨舊專案刪除（ADR 0008）」。→ 目前 5 份（0001、0003、0004、0005、0006）未加。

### c.2 被哪一份新 ADR 取代（design.md §4 ＋ 新 ADR 本文）

phase-2 項目編號 → ADR 的對應見 `.trellis/tasks/09-26-fmp-rewrite/phase2-plan.md:15-33`（1→0014、6→0010、11→0020、12→0012、13→0018、18→0011、19→0022）。

| 舊 ADR | design.md §4 的處理 | 對應新 ADR（檔內證據） |
|---|---|---|
| 0001 字串音源 id ＋ 每源設定清單 | 字串 id 確認沿用；每源設定清單由第 6／18 項取代；第 1 項寫插件 ADR 時把字串 id 併進去，0001 同時刪除（`design.md:54`） | 字串 id → `docs/adr/0014-...md:37`（manifest `id`（字串音源 id））；每源設定 → `docs/adr/0011-...md`（設定分組）＋ `docs/adr/0012-...md:49`（每音源設定表）。**沒有任何新 ADR 寫「取代 ADR 0001」** |
| 0002 Isar 只在 repository 層 | 第 6 項決定後換庫則刪；原則寫進新資料層 ADR（`design.md:55`） | `docs/adr/0010-...md:16`：「本 ADR 對新專案取代 ADR 0002、0007；那兩份仍描述根目錄舊專案」 |
| 0003 兩個音訊後端 | 第 13 項重新決定，新 ADR 取代（`design.md:56`） | `docs/adr/0018-playback-core.md:17`：「本 ADR 延續舊 ADR 0003「兩個後端」的形狀，適用於 `app/`；舊 ADR 0003 仍描述根目錄舊專案」 |
| 0004 Android 所有檔案存取權 | 第 11 項重新決定，新 ADR 取代（`design.md:57`） | `docs/adr/0020-...md:18`：「舊 ADR 0004（Android 以 `MANAGE_EXTERNAL_STORAGE`＋路徑、不用 MediaStore）描述舊專案；本 ADR 在 `app/` 延續其儲存做法」 |
| 0005 曲目識別鍵包含 cid | 確認沿用（也是舊資料遷移要用的格式）；第 6 項視需要改寫（`design.md:58`） | `docs/adr/0010-...md:45`（曲目以 `TrackKey` 字串（含 cid，ADR 0005）為唯一鍵）、`docs/adr/0019-...md:39`（ADR 0005 的曲目鍵格式照搬） |
| 0006 Release 自動發布 | 確認沿用；第 19 項補「發佈說明由 CHANGELOG 產生」後改寫（`design.md:59`） | `docs/adr/0022-...md:19`：「本 ADR 延續舊 ADR 0004（不上架商店）與 0006（驗過直接發布、不留人工閘門），適用於 `app/`；這兩份仍描述根目錄舊專案」 |
| 0007 Isar 停在 v3 | 隨 0002 一起處理（`design.md:60`） | `docs/adr/0010-...md:16` |

切換 PR 的刪除清單：`docs/adr/0026-milestones-and-cut-over.md:122`「切換 PR 同時刪除 ADR 0001–0007（`docs/adr/template.md` 的例外規則）與 `docs/audit/`」。

### c.3 所有引用（`git grep -n -E "adr/000[1-7]|ADR 000[1-7]"`，排除 archive 與 docs/audit）

**屬舊專案的檔案（切換 PR 會一起刪或改指向 `app/`）**

| 檔案:行 | 引用 |
|---|---|
| `.github/workflows/release.yml:359` | `docs/adr/0006`（註解：不建草稿、不等人按 publish） |
| `tool/release/verify_release_assets.dart:6` | `docs/adr/0006` |
| `test/workflows/release_workflow_test.dart:131` | `docs/adr/0006` |
| `test/workflows/release_assets_verification_test.dart:9` | `docs/adr/0006` |
| `lib/data/repositories/lyrics_repository.dart:64` | `ADR 0005` |
| `lib/data/repositories/search_history_repository.dart:10` | `docs/adr/0002-repository-boundary.md` |
| `AGENTS.md:82` | `ADR 0002`（Isar access 邊界規則） |
| `docs/build-and-release.md:159` | `ADR 0006` |
| `docs/build-and-release.md:210` | `ADR 0007` |
| `docs/development.md:12` | `ADR 0003` |
| `.trellis/spec/data/index.md:22` | `ADR 0001` |
| `.trellis/spec/data/index.md:23` | `ADR 0005` |
| `.trellis/spec/data/index.md:25` | `ADR 0002` |
| `.trellis/spec/data/persistence.md:3` | `ADR 0007`、`ADR 0002` |
| `.trellis/spec/data/persistence.md:28` | `ADR 0001` |
| `.trellis/spec/data/persistence.md:68` | `ADR 0002` |
| `.trellis/spec/data/persistence.md:118` | `ADR 0005` |
| `.trellis/spec/guides/cross-layer-thinking-guide.md:37` | `ADR 0001` |
| `.trellis/spec/guides/cross-layer-thinking-guide.md:46` | `ADR 0005` |
| `.trellis/spec/services/audio.md:3` | `ADR 0003` |
| `.trellis/spec/services/download-and-auth.md:3` | `ADR 0004` |
| `.trellis/spec/services/index.md:22` | `ADR 0003` |
| `.trellis/spec/services/index.md:23` | `ADR 0004` |
| `.trellis/spec/services/service-conventions.md:25` | `ADR 0002` |

**屬新設計的檔案（`docs/adr/0008+`，階段三只收尾不改）**

| 檔案:行 | 引用 |
|---|---|
| `docs/adr/0010-drift-data-layer-and-legacy-import.md:16` | 取代 `ADR 0002`、`0007` |
| `docs/adr/0010-...md:45` | `ADR 0005` |
| `docs/adr/0018-playback-core.md:17` | `ADR 0003` |
| `docs/adr/0019-library-and-sync.md:39` | `ADR 0005` |
| `docs/adr/0020-downloads-and-permissions.md:18` | `ADR 0004` |
| `docs/adr/0022-release-and-in-app-update.md:19` | `ADR 0004`、`0006` |
| `docs/adr/0026-milestones-and-cut-over.md:122` | `0001–0007`（切換 PR 刪除清單） |

**屬進行中任務（`09-26-fmp-rewrite`，非 archive）**

| 檔案:行 | 引用 |
|---|---|
| `.trellis/tasks/09-26-fmp-rewrite/milestones.md:120` | `ADR 0001–0007`（切換 PR 刪除） |
| `.trellis/tasks/09-26-fmp-rewrite/phase2-plan.md:255` | 舊 `ADR 0001–0007` 於切換 PR 刪除 |

---

## d. `CONTEXT.md`

`CONTEXT.md` 共 53 行＋檔尾換行。整份英文（Han 字元 0 行）。`:3-5` 定位：cross-platform music player，從 Bilibili、YouTube、Netease 解析；記錄 source auth 與 media handoff 的專案語彙。

### d.1 五個術語（`:9-40`）

| # | 術語（行） | 定義摘要 |
|---|---|---|
| 1 | **Source Auth Context**（`:9-13`） | 決定某個 source operation 可以用哪些 source credentials 的 policy 概念；與 account login、credential storage 不同。_Avoid_: auth helper、header utility、account service |
| 2 | **Media Handoff**（`:15-20`） | 從 resolved stream URL 到 audio/download backend 的轉移，含 redirect 檢查、per-hop media headers、續傳的 range headers、Source Auth Context 憑證收斂成 Media Request Credentials。_Avoid_: playback URL helper、download header helper |
| 3 | **Stream Resolution Auth**（`:22-26`） | 向 source adapter 解析／刷新 stream URL 時用的憑證；比 media request credentials 寬（可能含不得送到 media/CDN 的 B 站／YouTube auth）。_Avoid_: media auth、playback headers |
| 4 | **Auth For Play**（`:28-32`） | 使用者設定，閘門範圍是 stream resolution、playback handoff、download、track detail、auth-aware metadata/detail service paths；**不含** playlist import、playlist refresh、search。_Avoid_: import auth、search auth |
| 5 | **Media Request Credentials**（`:34-40`） | 允許出現在實際 audio byte request 的憑證；現行 policy 下是**空集合**：`SourceHttpPolicy.mediaHeaders(String sourceType)`（`lib/data/sources/source_http_policy.dart`）只收 source id，故沒有 cookie/token 能到 media host；舊的 Netease media allowlist 已於 `c09aec10` 移除。_Avoid_: stream auth、source auth |

`:42-53` 一段 Example Dialogue（Developer/Reviewer 對話，示範三個術語的用法）。

### d.2 原則是否已在 ADR 0012（或其他新 ADR）出現

`docs/adr/0012-network-layer-and-accounts.md:16` 明文：「`CONTEXT.md` 記錄的原則經審計驗證仍成立，併入本 ADR：**憑證只用在向音源解析串流與 API 請求，實際抓取音訊位元組的請求一律不帶憑證**」。

| 原則（CONTEXT.md 出處） | ADR 0012 的對應句 | 是否已涵蓋 |
|---|---|---|
| 憑證只用在解析串流與 API 請求；位元組請求不帶憑證（全份原則，`:9-40`） | `0012:16`（併入聲明）；`0012:30-31`「另有一個**媒體 client** 專抓音訊位元組，只加媒體 headers（Referer、UA），不掛認證攔截器與 cookie 管理」 | 是 |
| Source Auth Context＝哪個 operation 用哪些憑證（`:9-13`） | `0012:32-36`「每個請求在音源插件的定義處宣告 `AuthRequirement`…認證攔截器只依此標記注入」——概念沿用，**術語名換成 `AuthRequirement`** | 是（概念） |
| Stream Resolution Auth（`:22-26`） | `0012:34` `userPreference` 列舉含「串流解析」；`0012:33` `required` 含讀收藏夾／私人歌單 | 是 |
| Auth For Play 的閘門範圍（`:28-32`） | `0012:49`「**「以登入身分瀏覽與播放」**：每個音源一個開關（每音源設定表，ADR 0011），控制所有 `userPreference` 請求，三個音源語意一致」；`0012:50-51` 預設由音源宣告、legacy import 以舊開關值作使用者設定 | 是 |
| Media Request Credentials 為空集合（`:34-40`） | `0012:30`（媒體 client 不掛認證）＋`0012:70`（契約測試：媒體請求不含 Cookie/Authorization） | 是 |
| Media Handoff 的 **redirect 檢查、per-hop headers、續傳 range headers**（`:15-20`） | 0012 無「redirect」或「range」字樣（`grep -nE "redirect|轉址|Range|range" docs/adr/0012-*.md` 零命中）。下載端的續傳在 `docs/adr/0020-...md:12`（續傳只送 `Range`、不驗證）與 `:76`（RFC 9110 的 `If-Range`／強 ETag 續傳語意） | **部分／未涵蓋** |

`design.md:62` 指定：這些原則「併進第 12 項的 ADR 與 spec」，術語依新設計命名；階段三刪 `CONTEXT.md` 並改掉 `.trellis/spec/` 的 7 處引用。對應的 spec 是 `.trellis/spec/services/download-and-auth.md`（`:3`、`:38` 目前指向 `CONTEXT.md`）。

### d.3 所有 `CONTEXT.md` 引用（`git grep -n "CONTEXT\.md"`，排除 archive）

**舊專案／文件（階段三要改）**

- `.trellis/spec/data/index.md:9`
- `.trellis/spec/data/sources.md:81`
- `.trellis/spec/guides/cross-layer-thinking-guide.md:51`
- `.trellis/spec/services/download-and-auth.md:3`
- `.trellis/spec/services/download-and-auth.md:38`
- `.trellis/spec/services/index.md:8`
- `.trellis/spec/services/index.md:24`
- `AGENTS.md:13`（「Agent skills」段的 Domain docs bullet）
- `.trellis/tasks/09-26-fmp-rewrite/phase2-plan.md:23,113,209,258`
- `.trellis/tasks/09-26-fmp-rewrite/prd.md:13,18,86,88,92,190`
- `.trellis/tasks/09-28-phase3-docs-cleanup/prd.md:5`（英文描述行）
- `.trellis/tasks/09-28-phase3-docs-cleanup/task.json:5`（英文描述行）

**新設計／已刪除對象本身**

- `docs/adr/0012-network-layer-and-accounts.md:16`（併入聲明，**保留**）
- `docs/agents/domain.md:5,9,19,30,39,52`（檔案本身要刪）
- `CONTEXT.md`（檔案本身要刪）

---

## e. design-docs §6 各衝突的現況

（`design.md:68-79` 列出六項；本節逐項對照現況。）

### e.1 AGENTS.md 的 Trellis 自動區塊提到不存在的 `.codex/`、被 gitignore 的 `.agents/`

- `AGENTS.md:114` `<!-- TRELLIS:START -->`、`:134` `<!-- TRELLIS:END -->` 圍住的區塊；`:128-130`：
  - 「If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:」
  - `:129` `.agents/skills/` — reusable Trellis skills
  - `:130` `.codex/agents/` — optional custom subagents
- `.codex/`：**不存在**（`ls -la .codex` → No such file or directory）。
- `.agents/`：**存在**（本機）：`.agents/skills/verify-on-device/`，內含 `SKILL.md`（22166 bytes）與 `scripts/`（`ax_flatten.py`、`smtc_probe.ps1`）。
- `.agents/` 被 gitignore：`.gitignore:95` `/.agents/`（同在「Local agent/tool state」段，`:93` 另有 `/.codex/`、`:92` `/.trellis/workspace/`）。另有 `.trellis/.gitignore:14` `.agents/`（指 `.trellis/` 底下的 agent runtime 檔，不是根目錄那份）。
- `.agents/skills/verify-on-device/` 是過期副本（`design.md:73`）：與 `.claude/skills/verify-on-device/` 不同，詳見 § g.4。

### e.2 check 子代理三份定義

| 檔案 | 角色 | 客製？ |
|---|---|---|
| `.claude/agents/trellis-check.md`（122 行） | Claude Code subagent 定義（frontmatter `name: trellis-check`，`tools: Read, Write, Edit, Bash, Glob, Grep`，`:1-6`）。`:11-17` 遞迴守衛；`:19-24` 依 `<!-- trellis-hook-injected -->` 決定要不要自己載入 task artifacts；`:80-90` Step 4 Run Verification **指向 AGENTS.md § Verification**（`:86`）並在 `:90` 說 on-device 它跑不了、要回報主 session | **已客製**（見 § f.3） |
| `.claude/skills/trellis-check/SKILL.md`（111 行） | Claude Code Skill（frontmatter `name: trellis-check`，`:1-4`）。通用 6 步（Step 1 Identify → Step 6 Report and Fix）；`:28` 用 `.trellis/scripts/get_context.py --mode packages`；`:34` 讀 `.trellis/spec/<package>/<layer>/index.md`；**全檔沒有提到 AGENTS.md § Verification、也沒有 on-device 步驟** | 未客製（hash 相符，見 § f.3） |
| `.trellis/agents/check.md`（70 行） | Trellis channel runtime 的 agent 定義（frontmatter `name: check`、`provider: claude`、`labels: [trellis, check]`，`:1-7`）。`:11` 說明它由 `trellis channel spawn --agent check` 產生；`:32-38` 明列禁止 `git commit`／`push`／`merge`；`report format` 是 typecheck/lint | 未客製（hash 相符） |

**Claude Code 實際用哪一份**：`.trellis/workflow.md:237` 寫「`trellis-check` exists as both; **prefer the Agent form when verifying after code changes**」——Agent form 即 `.claude/agents/trellis-check.md`。`:238` 的流程 `trellis-implement` → `trellis-check` → `trellis-update-spec` 也用 agent 名。workflow.md 全檔（`grep -n "\.trellis/agents"`）**沒有**引用 `.trellis/agents/`。第三份只在 Trellis channel runtime 被用到，本 repo 沒有 channel 設定（`.trellis/config.yaml:103-109` 只有註解掉的範例）。

### e.3 Trellis 文件描述 journal commit，但設定已關閉

- 設定：`.trellis/config.yaml:34` `session_auto_commit: false`。`:21-33` 的說明：「true (default): scripts auto-stage and auto-commit journal / task changes after add_session.py / task.py archive runs」「**false: scripts do not touch git**」。`:33` 還有一行 FMP 客製註解：「FMP: journals live in the gitignored `.trellis/workspace/` (public repo).」這是本地客製（見 § f.3）。
- 敘述：`.claude/commands/trellis/finish-work.md:51`「Each archive produces a `chore(task): archive ...` commit **via the script's auto-commit**」；`:64`「This produces a `chore: record journal` commit」；`:66` 排出 git log 順序 `<work commits>` → `chore(task): archive` → `chore: record journal`。`.trellis/workflow.md:604`「produce work commits FIRST, then bookkeeping (archive + journal) commits land after」、`:647`「three-stage three-commit flow (work commits → archive commit → journal commit)」。
- `AGENTS.md:107-112` 已把「journals stay local」寫成客製。→ 敘述與設定不一致，但三份敘述檔（`.claude/commands/trellis/finish-work.md`、`.claude/commands/trellis/continue.md`、`.trellis/workflow.md`）都在 `.template-hashes.json` 內（`trellis update` 的目標）。
- `.trellis/workspace/` 確實被 gitignore：`.gitignore:92`。

### e.4 AGENTS.md 的「等待慣例」閘門範圍比實際寬

- `AGENTS.md:93-96`（Boundaries 最後一條）：「**Test waits** — `pumpUntil` for a condition false on entry, `drainEventQueue` to assert something did *not* happen (`test/support/pump_until.dart`); a fixed pump count is flaky in both directions (#43, #55) — `test/support/wait_convention_static_rule_test.dart`。」——三個斷言綁在同一支測試名稱後面。
- 實際閘門：`test/support/wait_convention_static_rule_test.dart`（99 行）**只**掃 `test/` 下有沒有檔案直接呼叫 `pumpEventQueue`：
  - `:11-15` allowlist 只有 `test/support/pump_until.dart`、`test/support/pump_until_test.dart`、本檔。
  - `:21-30` 用 `RegExp(r'\bpumpEventQueue\b')` 掃（`stripDartComments` 後），可抓到空格與 tear-off。
  - `:34-57` 斷言 offenders 為空，且 `:48` `expect(scanned, greaterThan(200))` 防止路徑寫錯時空過。
  - `:59-67` 另一個 test 檢查 allowlist 每個檔案仍存在。
- **它不檢查**「`pumpUntil` 的條件必須在進入時為 false」、也**不檢查**「`drainEventQueue` 用在否定斷言」。後兩者是 `test/support/pump_until.dart` 的 dartdoc 要求（`:19-20`「[condition] 必須是『進入時還不成立』的東西」），沒有閘門。
- `drainEventQueue` 有大量實際使用（`grep -rn drainEventQueue test/` 命中 20+ 處，如 `test/providers/account_status_check_test.dart:97`、`test/services/audio/audio_controller_handoff_and_errors_test.dart:173` 等）。

### e.5 `.trellis/workflow.md` 3.4「不 push」與使用者全域「自己的 repo 直接 push」

`design.md:77` 已判定：層級不同，repo 內不衝突，保留 Trellis 原文，不在 repo 內處理。現況：`.trellis/workflow.md:642,648`（3.4 步驟 6、Rules）都寫「Never push to remote in this step」。

### e.6 `trellis update` 覆寫風險

`design.md:79`：`.trellis/`、`.claude/` 裡由 Trellis 產生的檔案，改動前先確認 `trellis update` 會不會覆蓋；AGENTS.md「Trellis」段已記錄要保留的客製。實測結果見 § f.3。

---

## f. Trellis 管理的檔案

### f.1 管理機制

- **雜湊清單**：`.trellis/.template-hashes.json`（v2 格式，`"__version": 2`），`hashes` 物件列出 **84 個**受管檔案（`.claude/agents/*`、`.claude/commands/trellis/*`、`.claude/skills/*`、`.claude/hooks/*`、`.claude/settings.json`、`.trellis/agents/*`、`.trellis/scripts/*`、`.trellis/config.yaml`、`.trellis/workflow.md`）。完整清單可由該檔取得。
- **版本**：`.trellis/.version` = `0.6.17`。
- **標記式管理**：`AGENTS.md:114-134` 的 `<!-- TRELLIS:START -->` / `<!-- TRELLIS:END -->` 區塊，`:132` 自述「Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`」。`git grep -n "Managed by Trellis"` 全 repo 只有 `AGENTS.md:132`；`TRELLIS:START/END` 也只有 `AGENTS.md:114,134`。
- **AGENTS.md 不在雜湊清單內**（84 筆裡沒有 `AGENTS.md`），所以它的非區塊內容不受 `trellis update` 影響，區塊內容會。

### f.2 AGENTS.md「Trellis」段要求保留的客製

`AGENTS.md:102-112`（在 Trellis 區塊**外**，所以是我的客製、不會被覆寫）：

- `:104-106` Rules vs patterns：binding rules 留 `AGENTS.md`；`.trellis/spec/<layer>/` 寫該層怎麼寫並連回 AGENTS.md；一條新規則只放其中一邊。
- `:107-112` `trellis update` 時要保留：
  1. 本機的 `.claude/agents/trellis-check.md` 與 `trellis-implement.md`（它們的 Verify 步驟跑 § Verification）。
  2. 日誌留本機（`.trellis/workspace/` 被 gitignore、`session_auto_commit: false`、`orca.yaml` 讓 Orca worktree 共用主 checkout 的那一份）。
  3. 「若 update 又把 journal 的 `merge=union` 行加回 `.gitattributes`，就把它拿掉。」
- 對照現況：`.gitattributes`（17 行）**沒有** `merge=union` 行 → 第 3 點目前是空的，沒有殘留。

### f.3 實測：`trellis update` 會覆寫哪些

以 `.template-hashes.json` 的雜湊對現況比對（sha256，比對前把 CRLF 正規化成 LF；全部 84 檔都存在）：

- **81 檔與模板雜湊相符** → `trellis update` 可安全覆寫，內容與模板一致，覆寫無損。
- **3 檔不符（本機客製，`trellis update` 可能覆蓋或報衝突）：**
  1. `.claude/agents/trellis-check.md` —— 客製在 `:80-90`（Step 4 改指向 AGENTS.md § Verification、`:90` 加上 on-device 由主 session 跑的要求）。`AGENTS.md:107-108` 明確要求保留。
  2. `.claude/agents/trellis-implement.md` —— 同組客製。`AGENTS.md:107-108` 明確要求保留。
  3. `.trellis/config.yaml` —— 客製在 `:33`（FMP 註解）與 `:34`（`session_auto_commit: false`）。`design.md:75` 指出的 journal commit 衝突根源就在這裡。

→ 階段三若動 `.claude/`、`.trellis/` 下任何在清單內的檔案（含 `.claude/skills/trellis-check/SKILL.md`、`.claude/commands/trellis/finish-work.md`、`.trellis/workflow.md`），改動下次 `trellis update` 會被覆蓋。只有這 3 檔的客製在機制上「留得住」（因為它們本就被視為已客製）。

### f.4 其他 Trellis 檔案

- `.trellis/.developer`（55 bytes，本機身分，`.trellis/.gitignore:2` 排除）。
- `.trellis/.gitignore`（32 行）：`.developer`、`.current-task`、`.runtime/`、`.ralph-state.json`、`.agents/`、`.agent-log`、`.session-id`、`.plan-log`、`*.tmp`、`.backup-*`、`*.new`、`__pycache__` 等。
- `.trellis/spec/`：6 個子目錄（`data`、`guides`、`services`、`shared`、`testing`、`ui`），**沒有**頂層 `index.md`；共 20 檔（見 § h）。
- `.trellis/config.yaml:57-78` 有 `packages:` 區塊（monorepo 用），目前**整段註解掉**；`:62-75` 是範例（`path: packages/frontend` 等）。這與「`app/` 的 spec 放哪」相關（見 open-questions）。

---

## g. `verify-on-device` skill

### g.1 涵蓋的平台與步驟

`.claude/skills/verify-on-device/SKILL.md`（149 行，6206 bytes）：

- frontmatter `:2-10`：`name: verify-on-device`；description 說「Run FMP on the **Android emulator or the Windows desktop build**…root AGENTS.md requires an on-device check」。
- `:15-18`：「Closed loop…**bring up → run → observe → act → hot reload → tear down.** The **Android emulator is the required platform**; add Windows for Windows-specific work. If the loop cannot be completed, report the blocker.」
- `:20-21` 驗證環境：Windows 11 host、Orca CLI 1.4.187、AVD `Medium_Phone`（Android SDK 37、x86_64）、Flutter 3.47.x。
- `:23-27` 三份 reference 的分工：
  - `references/android.md`（83 行）：Android tap／輸入／時序／冷啟動不如預期時讀。
  - `references/windows.md`（122 行）：驅動或量測 Windows build 時讀。
  - `references/runtime-state.md`（48 行）：用狀態而非像素、UI 到不了的前置條件、離線可播媒體時讀。
- 步驟骨架：`1. Bring up the emulator`（`:41-58`，`emulator.exe -list-avds`、detached 啟動、`adb wait-for-device` 等 boot）、`2. Run the app`（`:60` 起）…到 `8. Tear down`。
- 平台工具差異：Android 用 `adb`／`dumpsys media_session`（`references/runtime-state.md:16-19`）；Windows 用 PowerShell 與 `scripts/msaa_tree.ps1`（`.claude/skills/verify-on-device/scripts/` 內有 `ax_flatten.py`、`msaa_tree.ps1`、`smtc_probe.ps1`）。

### g.2 是否會打真實 API

**會。** 這個 skill 跑真實 App 對真實來源：

- `references/runtime-state.md:35-36`：「Playback verification needs playing media, and **all three sources can be unavailable at once on a dev machine (Bilibili `playurl` answering HTTP 412, YouTube demanding sign-in, nothing downloaded)**」。
- `references/runtime-state.md:27-29`（在 `Setting up a precondition` 段）教用 `ext.isar.editProperty` 直接改資料庫狀態以繞過 UI 到不了的入口。
- `references/android.md:62` 教「Turn the network off with `adb shell svc wifi disable && adb shell svc data disable`…the cheapest way to reach real error paths: search, radio playback, **login and remote playlist refresh** all fail immediately with `Failed host lookup`」——即正常情況下這些路徑是打真 API 的。
- 它與 ADR 0015 的「預設零聯網」**不衝突但也不套用**：ADR 0015 的聯網閘門只管 `flutter test`（`docs/adr/0015-...md:55-56`：`dart_test.yaml` 對 `live` tag 設 `skip`、`flutter_test_config.dart` 用 `HttpOverrides.global` 讓真實 `HttpClient` 失敗）；skill 是跑真實 `flutter run` 的 App，不在那兩個閘門內。

### g.3 AGENTS.md 的驗證表

- `AGENTS.md:16` `## Verification`；表 `:18-25`：

  | Change area | Minimum |
  |---|---|
  | Audio playback/controller/queue | `flutter test test/services/audio`（串流解析改動時加 `test/data/sources`） |
  | Source adapters / HTTP policy | `flutter test test/data/sources test/services/account test/services/radio` |
  | Download pipeline | `flutter test test/services/download test/providers/download` |
  | Isar models / migrations | `dart run build_runner build` + `flutter test test/providers/database_migration_test.dart` |
  | UI widgets/pages | `test/ui` 的目標測試 + `flutter analyze` + on-device |
  | i18n JSON | `dart run slang` + `flutter analyze` |

- `:27-35` 三條補充：codegen（`dart run build_runner build`／`dart run slang`，Orca worktree 在 `orca.yaml` setup 跑）；full run 是 `flutter test --exclude-tags live`；`flutter analyze` 與 `dart format lib test tool` CI 閘門涵蓋 `tool/`。
- `:37-42` **On-device verification is mandatory for user-visible changes** —— 用 Android emulator（Windows 專屬改動才加 Windows），要報觀察到的 element／log 行／screenshot；emulator 起不來或到不了就**具名回報 blocker**，「tests alone do not count」。
- `.claude/agents/trellis-check.md:86` 把 § Verification 的表當作 Step 4 的依據；`:90` 說 on-device 它跑不了，要回報主 session。`AGENTS.md:107-108` 要求保留這個客製。

### g.4 `.agents/skills/verify-on-device/`（本機副本）是否不同

**不同，且差很多。** `diff` 結果：

| | `.claude/skills/verify-on-device/` | `.agents/skills/verify-on-device/` |
|---|---|---|
| `SKILL.md` | 149 行／6206 bytes | **399 行／22166 bytes** |
| 結構 | 步驟 1–8、reference 拆成三檔 | 步驟 1–8 內嵌，**沒有 `references/` 目錄** |
| `scripts/` | `ax_flatten.py`、`msaa_tree.ps1`、`smtc_probe.ps1` | `ax_flatten.py`、`smtc_probe.ps1`（**缺 `msaa_tree.ps1`**） |
| 獨有內容 | `references/android.md`、`windows.md`、`runtime-state.md` 的整理版 | `SKILL.md` 尾端多一節「**Measured during the 2026-09-07 UI acceptance run**」（`adb shell am force-stop` 會讓 `flutter run` 靜默失效、toast 斷言要靠 burst screenshot、`adb shell svc wifi disable` 等實測筆記） |
| 時間戳 | `SKILL.md` Sep 25 14:58 | `SKILL.md` Sep 10 19:14 |

→ 兩份互有對方沒有的東西（`.claude` 有 `references/` 與 `msaa_tree.ps1`；`.agents` 有實測筆記），不是單純的舊版。`design.md:73` 稱它為「過期副本」，`implement.md:21`（§B.5）要「本機刪除 `.agents/`」。

---

## h. 語言現況（design-docs R7：所有文檔繁中；README 維持英／繁雙語）

統計法：以行計，含 CJK 漢字的行 ÷ 總行數。

**英文（R7 要求改成繁中）**

| 檔案 | 行數 | 含漢字行 | 比例 |
|---|---|---|---|
| `AGENTS.md` | 134 | 1 | 1% |
| `.trellis/spec/data/index.md` | 33 | 0 | 0% |
| `.trellis/spec/data/persistence.md` | 140 | 1 | 1% |
| `.trellis/spec/data/sources.md` | 152 | 0 | 0% |
| `.trellis/spec/guides/code-reuse-thinking-guide.md` | 36 | 0 | 0% |
| `.trellis/spec/guides/cross-layer-thinking-guide.md` | 54 | 0 | 0% |
| `.trellis/spec/guides/index.md` | 20 | 0 | 0% |
| `.trellis/spec/services/audio.md` | 88 | 0 | 0% |
| `.trellis/spec/services/download-and-auth.md` | 75 | 0 | 0% |
| `.trellis/spec/services/index.md` | 33 | 0 | 0% |
| `.trellis/spec/services/service-conventions.md` | 150 | 0 | 0% |
| `.trellis/spec/shared/code-style.md` | 66 | 0 | 0% |
| `.trellis/spec/shared/errors-and-logging.md` | 69 | 0 | 0% |
| `.trellis/spec/shared/index.md` | 21 | 0 | 0% |
| `.trellis/spec/testing/index.md` | 25 | 0 | 0% |
| `.trellis/spec/testing/static-rules.md` | 56 | 0 | 0% |
| `.trellis/spec/testing/test-conventions.md` | 99 | 0 | 0% |
| `.trellis/spec/ui/i18n-and-routing.md` | 39 | 0 | 0% |
| `.trellis/spec/ui/index.md` | 30 | 1 | 3% |
| `.trellis/spec/ui/riverpod.md` | 143 | 0 | 0% |
| `.trellis/spec/ui/widgets.md` | 115 | 1 | 1% |
| `CONTEXT.md` | 53 | 0 | 0% |

`.trellis/spec/` 合計 **6 層 20 檔 1444 行**，實質全英文（只有 3 檔各有 1 行漢字，可能是程式碼註解）。與 `design.md:14` 的敘述一致。

**中文（R7 已滿足；`docs/` 本來就是繁中）**

| 檔案 | 行數 | 含漢字行 | 比例 |
|---|---|---|---|
| `docs/README.md` | 25 | 19 | 76% |
| `docs/build-and-release.md` | 386 | 180 | 47% |
| `docs/building.md` | 207 | 76 | 37% |
| `docs/development.md` | 165 | 95 | 58% |
| `docs/troubleshooting.md` | 112 | 59 | 53% |
| `docs/adr/0001` | 138 | 83 | 60% |
| `docs/adr/0002` | 77 | 52 | 68% |
| `docs/adr/0003` | 104 | 81 | 78% |
| `docs/adr/0004` | 77 | 59 | 77% |
| `docs/adr/0005` | 101 | 69 | 68% |
| `docs/adr/0006` | 101 | 77 | 76% |
| `docs/adr/0007` | 54 | 35 | 65% |
| `docs/adr/0008`–`0026`（19 檔） | 75–211 | — | 72%–90% |
| `docs/adr/template.md` | 41 | 23 | 56% |

低比例者（`build-and-release.md` 47%、`building.md` 37%）是大量指令與程式碼區塊，本文仍為中文。

**尚未存在**：`app/`（`ls -d app` → No such file or directory）。ADR 0008 定案要在 `app/` 另建專案，但它還沒開始；`app/AGENTS.md`、`app/` 的 spec 都還不存在。

**R7 的落地範圍**：只需把 `AGENTS.md` 與 `.trellis/spec/` 20 檔翻成繁中；`docs/` 與 ADR 已是繁中。`design.md:18` 另說「README 例外，維持英／繁雙語」；`docs/README.md:12` 目前寫 spec 是「（英文，給 agent 讀）」，翻譯後要改。

---

## 附：本次使用的指令

```bash
git grep -n -E "docs/agents|CONTEXT\.md|Agent skills|wayfinder|grill-with-docs" -- . ':!.trellis/tasks/archive' ':!docs/audit'
git grep -n -E "adr/000[1-7]|ADR 000[1-7]" -- . ':!.trellis/tasks/archive' ':!docs/audit'
git grep -n "只適用舊專案" -- . ':!.trellis/tasks/archive'
git grep -n "CONTEXT\.md" -- . ':!.trellis/tasks/archive'
git grep -n "Managed by Trellis" -- .
git grep -n "TRELLIS:START\|TRELLIS:END" -- .
git grep -n -E "needs-triage|needs-info|ready-for-agent|ready-for-human|wontfix|wayfinder" -- . ':!.trellis/tasks/archive' ':!docs/agents'
grep -rn -E "CONTEXT\.md|docs/agents|AGENTS\.md" .claude/hooks/
# 雜湊比對（CRLF 正規化後 sha256）：.trellis/.template-hashes.json 的 84 筆 vs 現況
```
