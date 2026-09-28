# repo-mechanics — 里程碑怎麼變成 task／PR 的機制事實

- 任務：`09-28-design-milestones`。本檔只列機制事實，附 `file:line` 或指令輸出。**不決定**里程碑方案。
- 三塊：§1 Trellis 任務機制；§2 CI 現況與 ADR 0015 對 `app/` 的規劃；§3 可追蹤里程碑的 GitHub 功能與 repo 現況；§4 工具鏈版本。

---

## 1. Trellis 任務機制（本 repo）

### 1.1 指令面（`python ./.trellis/scripts/task.py --help`）

可用子命令：`create / add-context / validate / list-context / start / current / finish / set-branch / set-base-branch / set-scope / set-meta / rename / archive / list / add-subtask / remove-subtask / list-archive`。

里程碑相關的關鍵參數：

- `create`：`python ./.trellis/scripts/task.py create "<title>" [--slug <name>] [--parent <dir>]`（`.trellis/workflow.md:46`）。`--parent` 建立 subtask 連結（`create --help`）。另有 `--description`（**必填非空**，空字串在 archive 時會被拒）、`--priority P0-P3`、`--package`、`--base-branch`（PR 目標分支）、`--meta k=v`、`--no-start`（建立但不設為本 session active）、`--force`。
- `archive`：`task.py archive <name> [--no-commit] [--skip-branch-validation]`（:50）。`--no-commit` 跳過自動 git commit；`--skip-branch-validation` 供「從未 PR-backed」的任務在缺 branch metadata 時仍可 archive。
- `add-subtask <parent> <child>` / `remove-subtask`：連結既有任務或解除（:69, :175）。
- `list-archive`（:52）。

### 1.2 parent / child 的語意（**這是重點**）

- 用途：一個使用者請求含多個可獨立驗證的交付物時，用 parent ＋ child（`.trellis/workflow.md:169-175`）。
- **「Parent/child structure is not a dependency system」**：child 之間若有先後，**必須寫在該 child 的 `prd.md` / `implement.md`，不能靠樹狀位置暗示**（:173, :358-359）。
- 建法：**先建 parent，再逐個用 `--parent <parent-dir>` 建 child**；不要因為有 child 就把 parent `start`；要 start 的是「持有下一個可獨立驗證交付物」的那個 child（:333, :359）。
- 狀態機：`create` 產生目錄並（在能取得 session 身分時）自動把「本 session active-task 指標」指過去；`start` 冪等地寫同一指標並把 `task.json.status` 由 `planning` 翻成 `in_progress`；`finish` 只刪 session 檔、**不改 status**；`archive` 會寫 `status=completed`、把目錄搬到 `archive/{year-month}/`、並清掉仍指向它的 runtime session 檔（:78, :230）。

### 1.3 本 repo 現況

| 項目 | 事實 | 來源 |
|---|---|---|
| parent task | `.trellis/tasks/09-26-fmp-rewrite/`，`task.json` 的 `id=fmp-rewrite`、`status=planning`、`priority=P2`、`base_branch=main` | `task.json` |
| parent 內容 | `prd.md`（216 行）、`phase2-plan.md`（269 行）、`task.json`、`check.jsonl`、`implement.jsonl` | `ls` |
| parent 的 children | 21 個名稱：`09-26-audit`、`09-27-design-docs`、`09-27-design-rewrite-strategy`、`09-27-design-platform`、`09-27-design-data`、`09-27-design-settings-logging`、`09-27-design-network-accounts`、`09-27-design-errors`、`09-27-design-source-plugins`、`09-27-design-testing`、`09-27-design-cache-offline`、`09-27-design-background-tasks`、`09-27-design-playback-core`、`09-28-design-library-sync`、`09-28-design-downloads`、`09-28-design-lyrics`、`09-28-design-release-update`、`09-28-design-toast`、`09-28-design-ui-ux`、`09-28-design-debug-page`、`09-28-design-milestones` | `task.json` `children` |
| 本項 task | `09-28-design-milestones/`：`task.json`（`id=design-milestones`、`status=planning`、`parent=09-26-fmp-rewrite`、`children=[]`）、`prd.md`（20 行，Requirements/Acceptance 仍 `TBD`）、`check.jsonl`、`implement.jsonl`、`research/` | `task.json`、`prd.md` |
| archive 目錄 | `.trellis/tasks/archive/2026-09/` 共 24 個目錄，含已完成的設計 child（例：`09-27-design-rewrite-strategy`、`09-28-design-debug-page`） | `ls .trellis/tasks/archive/2026-09/` |

**注意**：parent 的 `children` 是**名稱清單**，不是路徑；已 archive 的 child（目錄在 `archive/2026-09/`）仍留在這份清單裡。`children` 不表達順序或依賴。

### 1.4 本項的固定流程（parent 檔案已寫定）

`phase2-plan.md:257`：

> `每項固定流程：建 child task（task.py create --parent .trellis/tasks/09-26-fmp-rewrite --no-start）→ 派研究子代理（sonnet，寫進 task 的 research/）→ 核對關鍵事實 → prd → 一次一問（附建議與取捨）→ design＋implement → 最終摘要 → 使用者「核准」後 task.py start、寫 ADR、更新本檔 §3 標記完成、task.py finish＋archive --no-commit --skip-branch-validation、commit＋push。`

`phase2-plan.md:254`：**下一份 ADR 編號 0026**。

---

## 2. CI 現況與 `app/` 的 CI 規劃

### 2.1 現在的 `.github/workflows/ci.yml`

- 標題 `CI`；觸發 `pull_request`（target `main`）、`push`（`main`）、`workflow_dispatch`（`ci.yml:9-16`）。
- **沒有 path filter**，理由寫在檔頭註解：Markdown 也載著測試會強制的規則，所以純文件 commit 正是最不該跳過 `validate` 的那一種；`paths-ignore` 是 trigger 層級、無法只跳過 build job；**實測總時長 23 分鐘（validate 7、Android 6、Windows 10）**，不值得為省時間加一個 changed-files job（`ci.yml:3-8`）。
- `concurrency`：以 `ci-<workflow>-<PR 的 ref 或 main 的 sha>` 分組、`cancel-in-progress: true`；註解說明 2026-09 查到 main 上有 20 個 commit 因以 ref 分組被取消而永遠沒有 CI 結果（`ci.yml:22-25`）。
- `env`：`FLUTTER_VERSION: '3.47.1'`、`JAVA_VERSION: '17'`、`JAVA_DISTRIBUTION: 'temurin'`（`ci.yml:27-30`）。

| job | name | runs-on | timeout | needs | 內容 |
|---|---|---|---|---|---|
| `validate` | Analyze and Test | ubuntu-latest | 15 min | — | checkout（`fetch-depth: 0`）→ Flutter → `pub get` → `dart format --output=none --set-exit-if-changed lib test tool` → `build_runner build` → `dart run slang` → `flutter analyze` → `flutter test --coverage --exclude-tags live` → 上傳 coverage（`ci.yml:32-84`） |
| `build-android` | Android Build Smoke | ubuntu-latest | 20 min | validate | Java 17 → Flutter → codegen → `flutter build apk --release --target-platform android-arm64`（`ci.yml:86-122`） |
| `build-windows` | Windows Build Smoke | windows-2022 | 20 min | validate | `flutter config --enable-windows-desktop` → codegen → `flutter build windows --release`（`ci.yml:124-150`） |

### 2.2 最近的 CI run（`gh run list --limit 20`，read-only，取樣當下）

- 最近 20 筆全名為 `CI`。成功的兩筆：`2026-09-28T13:37:09Z → 13:57:54Z`（約 **20 分 45 秒**）、`2026-09-28T10:35:51Z → 10:53:18Z`（約 **17 分 27 秒**）。其餘多數 `conclusion=cancelled`（PR 上連續 push 被 concurrency 取消），最新一筆 `conclusion` 尚為空（進行中）。

### 2.3 現在的 `.github/workflows/release.yml`

- 觸發：push `v*` tag 或 `workflow_dispatch`（帶 `tag` 輸入）（`release.yml:3-12`）。`env` 同 ci.yml（Flutter 3.47.1、Java 17）。
- job：`prepare`（驗 tag 格式並算 `version_code = major*1000000+minor*1000+patch`）→ `build-android`（matrix 4 ABI：arm64-v8a／armeabi-v7a／x86_64／universal，順帶產 `fmp-latest-android-*` 別名）、`validate`（`flutter analyze` + `flutter test --exclude-tags live`）→ `build-windows`（ZIP、Inno Setup 安裝檔、ISS patch 驗證閘門、LGPL 授權檔隨二進位）→ `verify`（下載全部 artifact、產 checksums、`tool/release/verify_release_assets.dart` 檢查）→ `release`（組 release body、`softprops/action-gh-release` 直接發布，`draft: false`）（`release.yml` 全文）。
- release body 由 commit 訊息自動分組產生（feat／fix／perf／deps），並附 compare 連結；檔內註解說明 body 也是 App 內更新對話框的來源（`release.yml`）。

### 2.4 ADR 0015 對 `app/` 的 CI 規劃（**尚未實作**，是里程碑要落地的部分）

`docs/adr/0015-testing-gates-and-dev-environment.md:31-38`（決定 9）：

> `CI：dorny/paths-filter 依專案切分——app/** 與 .github/** 觸發 app 的 job，app/ 以外的任何變動（含文件）觸發舊專案的 job；一個 always() 彙總 job 當唯一必要檢查。app 的 job：format、dart analyze、接線哨兵、flutter analyze、lint 規則測試、不加參數的 flutter test、契約執行器、Android／Windows／Linux／macOS／iOS（不簽名）建置、Linux 與 Windows 的整合測試。舊專案的 job 維持現狀，只在根目錄變動時跑，app/ 的 PR 不被舊專案的不穩測試擋住。`

ADR 0008 的後果也記了這件事：切換期 CI 要跑兩個專案、時間變長；CI 依專案切分，舊專案測試只在根目錄變動時跑、不擋 `app/` 的 PR（`docs/adr/0008-rewrite-as-new-app-in-same-repo.md:64-68`）。ADR 0009 要求 CI 建置矩陣**從第一個里程碑起**含 Linux／macOS／iOS 不簽名（`docs/adr/0009-platform-layer-with-declared-capabilities.md:82`）。

→ 也就是：**`app/` 的 CI job 與 5 平台建置矩陣目前都不存在**；`ci.yml` 只有舊專案的 3 個 job。里程碑 1 要把它們生出來。

---

## 3. 可追蹤里程碑的 GitHub 功能與 repo 現況

### 3.1 功能事實（來源限 docs.github.com）

| 功能 | 事實 | 來源 |
|---|---|---|
| **Milestones** | 在**單一 repo** 內追蹤一組 issue／PR；milestone 頁顯示說明、到期日、**完成百分比**、open／closed 計數與清單；可直接開預設掛在該 milestone 的 issue；open 項目可拖曳排序，但**超過 500 個 open issue 就不能排序** | <https://docs.github.com/issues/using-labels-and-milestones-to-track-work/about-milestones> |
| **Sub-issues** | 把大工作拆成子 issue；**每個 parent 最多 100 個 sub-issue、最多 8 層嵌套**；parent 與 sub-issue 進度在 Projects 可見（可依 parent 篩選／分組）；CLI：`gh issue create --parent <PARENT-NUMBER>`、`gh issue edit <PARENT> --add-sub-issue <N>` | <https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues> |
| **Projects** | user 或 org 層級的 table／board／roadmap，整合 issue 與 PR；可自訂 field（metadata）、多個 view（filter／sort／slice／group）、可設定圖表 | <https://docs.github.com/issues/planning-and-tracking-with-projects/learning-about-projects/about-projects> |

### 3.2 本 repo 現況（read-only 查詢）

| 查詢 | 結果 |
|---|---|
| `gh api repos/1morr/FMP/milestones` | `[]`（**沒有使用 milestone**） |
| `gh api repos/1morr/FMP/projects` | HTTP 404（repo 的 Projects (classic) 端點不存在／已停用） |
| `gh api graphql` 查 `projectsV2` | 失敗：token 缺 `read:project` scope（現有 scope：`gist, read:org, repo, workflow`）→ **Projects v2 用量無法確認** |
| `gh api repos/1morr/FMP` | `has_issues: true`、`open_issues_count: 3` |
| `.github/` 內容 | `dependabot.yml`、`workflows/`；**沒有 `ISSUE_TEMPLATE/`** |
| issue 範本 | ADR 0023 :89 明說「repo 目前沒有 issue 範本，落地時新增 `.github/ISSUE_TEMPLATE/bug_report.yml`」 |

→ 里程碑若要「一個里程碑＝一個 GitHub issue 或 milestone」在 GitHub 上追蹤，目前是從零開始；Trellis 的 parent／child 任務樹與 GitHub Issues 是**兩套並行的追蹤**，沒有任何自動同步（查無同步腳本；`tool/` 下未見）。

---

## 4. 工具鏈版本

| 項目 | 值 | 來源 |
|---|---|---|
| 舊專案版本 | `version: 1.11.0+1011000` | `pubspec.yaml:5` |
| Dart SDK 約束（舊專案） | `sdk: '>=3.9.0 <4.0.0'` | `pubspec.yaml:8-9` |
| CI 釘住的 Flutter | `3.47.1` | `.github/workflows/ci.yml:27`、`release.yml:21` |
| `.fvmrc` | **不存在**（`cat .fvmrc` → no such file） | 指令輸出 |
| 效能基準量測環境 | Flutter **3.47.1** stable（framework `6655482ec0`、engine `11d79658c4`）、Dart **3.13.1** | `docs/audit/perf-baseline.md:13` |
| Java | 17（temurin） | `.github/workflows/ci.yml:28-29` |
| **當前 Flutter stable**（官方 release JSON，取樣 2026-09-28） | **3.47.5**（Dart **3.13.4**，2026-09-18 發布，sha `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`） | <https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json> |
| 當前 beta | 3.49.0-0.1.pre（Dart 3.14.0，2026-09-21） | 同上 |
| 近期 stable 序列 | 3.47.5（09-18）、3.47.4（09-11）、3.47.3（09-09） | 同上 |

→ `app/` 若「從當前 stable 起」，會是 **Flutter 3.47.5 / Dart 3.13.4**（舊專案與基準是 3.47.1 / Dart 3.13.1）。差距是 patch 級，但切換條件的「效能不低於基準」要在 `perf-baseline.md:13` 記下引擎版本差異。

---

## 查不到／推測

- **查不到**：repo 是否使用 GitHub Projects v2。`gh` token 缺 `read:project`；classic Projects 端點 404。需以有該 scope 的 token 或直接在網頁確認。
- **查不到**：`release.yml` 的實測時長。取樣的 20 筆 run 全是 `CI`，沒有 release run。
- **查不到**：Trellis 任務樹與 GitHub Issues／Milestones 之間的任何同步機制或腳本。
- **推測**：`ci.yml` 檔頭「23 分鐘（validate 7、Android 6、Windows 10）」與本次取樣的成功 run 約 17–21 分鐘一致；實際時長隨 runner 快慢浮動。
- **推測**：parent `task.json` 的 `children` 清單同時含已 archive 的 child，代表 archive 不會把 child 從 parent 的 `children` 移除；里程碑定稿若要「以里程碑為單位列 child」，需自行維護另一份對照。
