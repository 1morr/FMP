# M1 設計

各項行為以 ADR 0008–0027 為準。這份只寫：
- 跨 PR 的結構；
- ADR 留給「開工時決定」的技術選擇；
- 擁有者五個決定的落地方式。

「§3.x」指 `research/m1-scope-digest.md` 第 3 節的未定項。

## 1. 指令檔與 spec 分家（PR 1，擁有者決定 1）

分家後的樣子：

| 路徑 | 內容 | 何時載入 |
|---|---|---|
| `AGENTS.md` | 英文。repo 地圖（根目錄＝凍結的舊專案，只收緊急修正；`app/`＝新專案；`docs/adr/`；`.trellis/`）、Issues、ADR 規則（沒有已確認的 ADR 不寫程式碼；新決定寫新 ADR）、Trellis 段 | 每個 session |
| `lib/AGENTS.md` | 現在根目錄的 Verification、Conventions、Boundaries 原封搬來；路徑維持相對 repo 根的寫法 | 讀到 `lib/` 的檔案時 |
| `app/AGENTS.md` | 繁中，PR 2 建立，之後每個 PR 補自己那一層 | 讀到 `app/` 的檔案時 |

- 根目錄地圖寫明：「改舊專案先讀 `lib/AGENTS.md`；在 `app/` 工作先讀 `app/AGENTS.md`」。
  - 理由：子目錄的 AGENTS.md 只在讀到該目錄的檔案時才載入（Claude Code memory 文件）。只改 `test/` 的舊專案修正可能不會觸發 `lib/AGENTS.md`，這句用來補上。
- 根目錄 Trellis 段的「Rules vs patterns」「`trellis update`」兩條留在根目錄。它們指向的 § Verification 改成「任務所屬 package 的 `AGENTS.md` § Verification／§ 驗證」。
- 舊 spec 搬家：`git mv .trellis/spec/{data,services,shared,testing,ui} .trellis/spec/legacy/`，`guides/` 留在原地共用。
  - 更新所有引用：
    - `lib/AGENTS.md`（例如 `test-conventions.md`）；
    - `docs/README.md`；
    - spec 之間的相對連結；
    - `.claude/agents/*`；
    - `.trellis/workflow.md` 內 FMP 自己加的段落。
  - Trellis 管理檔（`.trellis/.template-hashes.json` 列的）不改。
- `.trellis/config.yaml`：
  ```yaml
  packages:
    legacy:
      path: .
    app:
      path: app
  default_package: app
  ```
  - package 名不用 `data` 或 `.`。研究查過：spec 目錄名取自 package 名；取 `data` 會回報 `Spec: not configured`，取 `.` 會讓掃描指到 spec 根。
  - 現有的 active task（`09-26-fmp-rewrite`、本任務）在 `task.json` 補 `"package": "app"`；兩者都不寫舊專案程式碼。
- `app/` 的 spec 在 PR 2 建 `.trellis/spec/app/index.md`，各層寫到時再加 `.trellis/spec/app/<layer>/index.md`（繁中）。
- `.claude/agents/trellis-implement.md`、`trellis-check.md` 是本機客製檔，可以改：
  - 驗證步驟改成「讀 `task.json` 的 package：legacy 跑 `lib/AGENTS.md` § Verification，app 跑 `app/AGENTS.md` § 驗證」；
  - spec 路徑改成 `.trellis/spec/<package>/<layer>/`。
- skill：`git mv .claude/skills/verify-on-device .claude/skills/verify-legacy-on-device`。
  - 同步改 SKILL.md 的 `name:` 與 description，說明只給舊專案緊急修正用。
  - 更新引用：`lib/AGENTS.md`、`docs/README.md`。
  - `verify-on-device` 這個名字在 PR 11 由 `app/` 版使用。
- 其他引用：
  - `orca.yaml:14` 的註解改指 `lib/AGENTS.md`；
  - 舊專案沒有測試讀 `AGENTS.md` 或 spec 的路徑（已搜尋 `test/`、`tool/`、`lib/`、`.github/`）。
- 閘門：
  - PR 1 的驗證：
    - `flutter test --exclude-tags live test/support test/workflows`；
    - 搜尋舊路徑 `.trellis/spec/(data|services|shared|testing|ui)/` 與 `skills/verify-on-device`，除了 archive 任務之外不得殘留；
    - 開一個新 session，確認 SessionStart 只列出 `guides` 與 `app` 的 spec 索引。
- 同一個 PR 更正 ADR 的事實錯誤，只加補充句、不改決定：
  - ADR 0021：`window_manager` 0.5.2 仍在發佈；
  - ADR 0015：issue 改引 flutter/flutter#187999；
  - ADR 0027：舊 skill 改名 `verify-legacy-on-device`。

## 2. `app/` 的結構

```
app/
  AGENTS.md
  pubspec.yaml            # flutter: default-flavor: dev；resolution: workspace
  analysis_options.yaml   # plugins: fmp_lints（頂層 plugins:，非 analyzer:）
  dart_test.yaml          # tags: live: skip（ADR 0015 §決定 3）
  CHANGELOG.md            # release-please（PR 13）
  lib/
    main.dart             # 由 flavor 決定身分；組 ProviderScope（retry 關閉）
    app/                  # MaterialApp、路由、外殼、ToastHost
    core/                 # logging/、redaction/、errors/、network/、settings/
    data/                 # drift database、tables、repositories
    domain/               # TrackKey 等純型別
    platform/             # 每能力一目錄：<能力>.dart＋<能力>_<平台>.dart
    plugins/              # JS runtime、宿主 API、manifest、SourcePlugin 轉接
    playback/             # PlaybackController、AudioBackend 兩實作、QueueModel 最小集
    ui/                   # theme/（AppTokens、AppLayout）、shell/、search/、settings/、player_bar/、toast/
    i18n/                 # slang：zh-TW（base）、zh-CN、en
  packages/
    fmp_lints/            # analysis_server_plugin；analyzer_testing 測試
    plugin_contract/      # 契約執行器（重播 fixture 跑 checks.json）
  test/
    flutter_test_config.dart   # HttpOverrides.global 擋真實 HttpClient
    fixtures/plugins/test_plugin/   # 合成資料、播放本機音檔
  integration_test/
```

- 第一層目錄以 ADR 已定的名稱為準：`platform/`、`core/logging/`、`core/redaction/`、`legacy_import/`（M5 才建）、`packages/fmp_lints/`。
- 其他目錄照上表，`fmp_layer_imports` 的依賴表在 PR 3 寫成規則。
- Dart pub workspace：`app/` 是 workspace 根，`packages/*` 是成員。`analysis_server_plugin` 的 `plugins:` 只能寫在 package 或 workspace 根（研究 Part B）。

## 3. 技術選擇（ADR 留給開工時決定的）

| § | 項目 | 決定 | 理由 |
|---|---|---|---|
| 3.2 | Flutter 版本 | `app/` 用 3.47.5（Dart 3.13.4），CI 的 `app` job 釘這版；舊專案 job 維持 3.47.1。本機升到 3.47.5，舊專案同一個 minor，照常建置 | ADR「當時的 stable」 |
| 3.4 | `AuthRequirement` | M1 建型別與宣告點（manifest、請求 DTO），認證攔截器在沒有 `CredentialStore` 時一律不注入；`CredentialStore` 與三種標記的注入測試在 M3 | B 站搜尋與解串流不需登入；宣告點是插件 API 的一部分，晚加會改 DTO |
| 3.5 | `PermissionGateway` | M1 不建 | M1 沒有需要執行期權限的功能；ADR 0009「不寫空實作」 |
| 3.6 | 串流網址快取 | M1 不建；`StreamResolver` 每次呼叫插件 | ADR 0016 整包在 M2；兩首的佇列用不到 |
| 3.8 | log 檔格式 | 一開始就寫 JSON Lines（ADR 0025 §決定 3 的欄位），2MB×3 | 先寫純文字、M3 再改，等於改兩次；7 天保留仍在 M2 的維護清單 |
| 3.9 | M1 的 lint | 十條核心規則全做，加 `fmp_toast_entry`、`fmp_design_tokens`；`fmp_periodic_timer_owner` 留到 M2 | 規則要在第一批程式碼寫進來前就位，事後補會先累積違規；`BackgroundScheduler` 在 M2 |
| 3.10 | 最小 schema | 見下表 | M1 只持久化需要跨重啟的東西 |
| 3.11 | isar／sqlite3 共存 | PR 5 期間開探針分支：加 `isar_community` 3.3.2＋`sqlite3` 3.x，在 Android、Windows 建置並開兩個庫；檢查 APK 內 `.so` 的 16KB 對齊（`zipalign -c -P 16`）。結論寫進研究檔，不合併 | ADR 0010 規定 `isar_community` 只能在 `legacy_import/`（M5） |
| 3.13 | `material_ui` | PR 2 依 3.47.5 的官方遷移文件決定 import 路徑，寫進 `app/AGENTS.md` | ADR 0024 |
| 3.14 | `window_manager` | 用 pub 的 0.5.2；`tray_manager` 0.7.0 的 `nativeapi` 改寫留到 M8 | 0.5.2 仍在發佈（已查證） |
| 3.15 | 契約執行器與 QuickJS | PR 9 先試 `flutter test` 內載入（CI 先建置桌面產物，再設 `PATH`／`LIBQUICKJSC_TEST_PATH`）；不行就照 ADR 0015 改用桌面 `integration_test`。結果寫進 `app/AGENTS.md` 的驗證段 | ADR 0015 把這題留給 M1 實測 |
| 3.16 | 兩首的佇列 | 只在記憶體、只有 `queue` 模式、依序播放、不持久化；`QueueModel` 的介面照 ADR 0018，M2 補齊 | M2 才做完整佇列 |
| — | 系統媒體控制 | M1 不做（`audio_service`、SMTC 在 M2）；Android 只驗前景播放與換歌不放音訊焦點 | 屬 M2 |
| — | `orca.yaml` | PR 2 在 setup 加上 `app/` 的 `flutter pub get` 與 `dart run slang`，舊專案的步驟不動 | Orca worktree 要能直接跑 `app/`；切換 PR 再移除舊步驟 |

M1 的 drift 表：

| 表 | 用途 | ADR |
|---|---|---|
| `appearance_settings`（單列） | 主題模式、語言；欄位空＝沒設定過 | 0011 §決定 7；擁有者決定 2 |
| `installed_plugins` | 從檔案安裝的插件：id、版本、manifest JSON、腳本、安裝時間 | 0014 |
| `plugin_storage` | 每插件的 key／value；B 站匿名 `buvid` 放這裡 | 0014 §決定 5、0012 §決定 1 |

- `tracks` 等音樂庫表留到 M4。`TrackKey` 在 M1 是 `domain/` 的純型別加測試，佇列用它當身分。
- schema 從 v1 起用 `drift_dev schema dump` 存快照，CI 驗證快照與程式碼一致。

## 4. B 站插件與 `1morr/fmp-plugins`（擁有者決定 5）

- PR 9 之前建立公開 repo `1morr/fmp-plugins`，只放 `README.md`（繁中，寫明開發中）與 `bilibili/`：
  - `manifest.json`；
  - `index.js`；
  - `fixtures/`；
  - `checks.json`。
- 插件以舊專案 `lib/data/sources/bilibili*` 為規格，用 JS 重寫（ADR 0008 檔頭補充）。M1 只需要 `search` 與 `resolveStream` 兩個能力。
- fixture 以真實連線錄製一次（ADR 0027 §決定 2），寫檔前經遮蔽函式；提交前人工確認沒有 cookie 或 token 原值。
- fmp-plugins 的變更以該 repo 自己的 PR 合併，本機跑 `app/packages/plugin_contract` 的執行器驗證。

## 5. CI（PR 2 起逐步擴充）

- `ci.yml` 改成兩半，用 `dorny/paths-filter@v4` 分流（ADR 0015 §決定 9）：
  - 舊專案的三個 job 原樣保留，只在 `app/` 以外有變動時跑；
  - `app` 的 job 由 `app/**` 與 `.github/**` 觸發；
  - 最後一個 `always()` 彙總 job 是唯一必要檢查。
- 彙總 job 的判斷：被跳過的 job 算通過，失敗或取消的算失敗。
- `main` 的 ruleset `protect-main` 目前只有 `deletion` 與 `non_fast_forward`，沒有必要檢查（2026-09-29 查）。
  - PR 2 合併後，在 ruleset 加上 `required_status_checks`，只列彙總 job，照 ADR 0015 的「唯一必要檢查」。
  - 這是擁有者自己 repo 的設定，直接改。
- `app` job 隨 PR 增加步驟：

  | PR | 加入的步驟 |
  |---|---|
  | 2 | format、`flutter analyze`、`flutter test` |
  | 3 | `dart analyze --fatal-infos`、接線哨兵、lint 規則測試 |
  | 5 | schema 快照檢查 |
  | 9 | 契約執行器 |
  | 13 | 五平台建置、Linux 與 Windows 整合測試 |

- 發版 workflow `app-release.yml`（擁有者決定 4）：
  - 只有 `workflow_dispatch`，沒有 push 觸發；
  - 內容照 ADR 0022 §決定 1、3、4；
  - 在 `1morr/fmp-release-sandbox` 用同一份檔案跑通，那邊加上 push 觸發與臨時金鑰；
  - sandbox 驗完封存。

## 6. `app/` 的 verify-on-device（PR 11，ADR 0027）

- 新的 `.claude/skills/verify-on-device/`：
  - `SKILL.md`：閉環「啟動 → 執行 → 觀察 → 操作 → 收尾」；
  - `references/android.md`、`references/windows.md`；
  - `references/runtime-state.md`：改成 drift 與 dev flavor 的資料目錄。
- 預設：dev flavor 加測試插件或重播模式。真實連線只在 ADR 0027 §決定 2 的條件下使用。
- 回報格式必含「平台」與「模式：重播／真實」。
- `scripts/` 的三支工具（AX／MSAA／SMTC）與平台有關、與專案無關，從舊 skill 複製一份。舊 skill 要原樣留給緊急修正，所以不共用。
- 每插件切換「真實、錄製、重播」是 M3 的插件開發工具（ADR 0015 §決定 7、ADR 0025）。
- M1 不另做切換機制，UI 與播放的實機驗證改用測試插件，這是 ADR 0027 §決定 1 允許的另一條路。
- B 站插件本身的端到端驗證屬「改動是插件」，用真實連線，只做最少操作。

## 7. 回滾

- 每個 PR 獨立合併，`app/` 以外只動 `ci.yml`、`orca.yaml`、指令檔與 spec。舊專案的程式與 `release.yml` 不動，緊急修正路徑不受影響。
- PR 1 的搬家與 PR 2 的 CI 改動是 M1 裡唯二會影響舊專案工作流程的地方，各自可以單獨 revert。
