# M1 工具事實：套件版本與 Trellis `packages:` 機制

- 查證日期：2026-09-28（全部數字皆為當日所見）
- 來源規則：pub.dev JSON API（`https://pub.dev/api/packages/<pkg>`）、官方文檔、GitHub raw 檔與 `gh api`。
  沒有一條來自記憶。每條事實後附來源與所見版本／日期。
- 用途：餵 M1（`../prd.md`）的開工決策，以及 `../09-26-fmp-rewrite/phase2-plan.md` §7、§10 的未決事項。

---

## Part A — Trellis `packages:` 的實際行為（含實測）

實測方式：在 scratchpad 複製一份最小 repo（`.trellis/scripts`、`.trellis/spec`、`.claude/hooks/session-start.py`），
填不同 `config.yaml` 後直接 import hook 的函式呼叫，並跑 `task.py create`。

### A0 現況（尚未宣告 packages）

- `.trellis/config.yaml:58-78` 的 `packages:` / `default_package:` 整段被註解掉；`config.yaml:34` 是
  `session_auto_commit: false`，**沒有 `session:` 區塊** → `get_spec_scope` 回 `None`（`config.py:462-482`）。
- 因此 `is_monorepo()` 為 `False`（`config.py:391-393`），spec 目錄是扁平的
  `.trellis/spec/<layer>/`（`config.py:396-405` 的 `get_spec_base` 回 `"spec"`）。
- 現有兩個 active task 的 `task.json` 都是 `"package": null`。

### A1 spec 檔該放哪、扁平的能不能混用、有沒有 migration

- 宣告 `packages:` 後 spec 必須放 `.trellis/spec/<package>/<layer>/`：
  `get_spec_base` 回 `f"spec/{package}"`（`config.py:403-405`），
  `get_spec_dir` = `repo_root / .trellis / get_spec_base(package)`（`paths.py:491`），
  `_scan_spec_layers` 掃 `spec_dir / package`（`packages_context.py:30-41`）。
- **可以混用，而且不會有任何提示**。舊的扁平 `.trellis/spec/<layer>/` 不會被刪、不會被擋、也不會被納入
  package 掃描；在 `get_context.py --mode packages` 的輸出裡它們只是消失（實測：宣告一個 `legacy` 套件後，
  扁平層 `data/services/shared/testing/ui` 全部不出現，該套件顯示 `Spec: not configured`）。
- **沒有 migration 指令**。Trellis CLI 0.6.17 只有 `init / update / upgrade / uninstall / ablate / restore / mem /
  workflow / platforms / channel`。唯一的相關提示是 `_check_legacy_spec`（`session-start.py:561-607`），
  而它**寫死只認 `backend` 與 `frontend`**（`session-start.py:575`）；FMP 的層名是
  data/services/shared/testing/ui，實測回 `None` → 宣告 packages 後**不會出現任何「扁平 spec 已成孤兒」的警告**。
- 要注意的細節：spec 目錄名來自**package 名**，不是 `path`。所以 `app: path: app` 與
  `legacy: path: .` 會產生 `.trellis/spec/app/` 與 `.trellis/spec/legacy/`，磁碟上不重疊。
- 另：`_scan_spec_layers` 排除的是字面值 `"guides"`（`packages_context.py:40`），
  `session-start` 另外排除 `.` 開頭的目錄（`session-start.py:677`）。

### A2 任務怎麼綁 package、session-start 與 subagent 怎麼選 index

- 建立時：`task.py create ... --package <pkg>`。`task_store.py:363-376` 是 fail-fast 三段：
  非 monorepo → 只印 `Warning: --package ignored in single-repo project` 然後清成 `None`；
  monorepo 且給的值不合法 → `Error: unknown package '<x>'. Available: ...` 並 `return 1`；
  沒給 → `resolve_package(repo_root=repo_root)`，順序是 **task_package → `default_package` → None**
  （`config.py:420-440`）。值寫進 `task.json` 的 `"package"`（`task_store.py:536`）。
- `add_session.py:1514-1537` 同一套，但推斷來源是**當前 active task 的 `package`** → `default_package`。
  `task.py list` 會多一個 `@<pkg>` 標籤（`task.py:453`）。
- session-start：`_load_trellis_config`（`session-start.py:517-557`）直接讀 active `task.json` 的
  `package` 字串（`539-546`），再交 `_resolve_spec_scope`（`609-659`）決定 `allowed_pkgs`。
- **subagent 注入完全不看 package**：`inject-subagent-context.py:483` 的 `get_agent_context` 只讀
  `<task>/implement.jsonl` 與 `check.jsonl`（空的時候回一段說明文字），
  `get_implement_context`（`534`）的順序固定是 jsonl → prd.md → design.md → implement.md。
  整個檔案裡沒有 package 或 spec_scope 的分支。**要注入 spec，就寫進 jsonl。**
- 已知落差：`.claude/agents/trellis-implement.md:59` 已寫 package-aware 的
  `.trellis/spec/<package>/<layer>/`，但 `.claude/agents/trellis-check.md:86` 仍寫死扁平的
  `.trellis/spec/<layer>/index.md`（monorepo 模式下會指到不存在的位置）。

### A3 根目錄（`.`）當一個 package、與其他 package 重疊

- 可以宣告，實測 `legacy: path: .` 只回報 `Path: .`，沒有錯誤。
- spec 路徑不會重疊（見 A1：目錄名用 package 名）。
- 真正的地雷在**命名**，兩個都實測過：
  - package 取名 `.` → `_scan_spec_layers` 的 `spec_dir / "."` 解析成 spec 根，
    列出 `app, data, services, shared, testing, ui`，路徑長成 `.trellis/spec/./data/index.md`。
  - package 取名與既有扁層同名（例：`data`）→ `_scan_spec_layers` 掃 `spec/data/` 底下沒有子目錄，
    回 `[]` → 輸出 `Spec: not configured`；**但** `spec/data/index.md` 仍會被當扁平層注入（見下）。
- **扁平層繞過 scope 過濾（本次最重要的發現）**：`_collect_spec_index_paths`
  （`session-start.py:666-695`）的迴圈裡，`index_file.is_file()` 為真就 `append` 並 `continue`
  （`680-682`），**這行在 `allowed_pkgs` 檢查（`685`）之前**。實測：`spec_scope: active_task` 且只允許
  `{app}` 時，扁平的 `data/services/shared/testing/ui` 五個 index 全部照樣注入。
  結論：宣告 packages 之後若不搬 spec，等於每個 session 都多載入舊專案的 spec，而且沒有任何警告。
  （`spec/guides/index.md` 一律注入，是設計如此，`session-start.py:668-670`。）

### A4 加 packages 對「現在跑得動的東西」有什麼改變

- package 目前**純屬 metadata**：沒有任何分支／worktree／路徑命名用到它
  （`resolve_session_branch`，`add_session.py:222`，只看 task.json 的 `branch` 或當前 git 分支）。
  既有任務是 `package: null`，不會被回頭改寫。
- 因為 root 本身是 git repo，`_discover_child_git_repos` 的 `discover_unconfigured=not isRepo`
  永遠是 `False`（`session_context.py:533/615/779/852`）→ polyrepo 掃描本來就不會啟動，宣告 packages 亦然。
- 實際會變的行為只有四項：
  1. session-start 與 `get_context.py --mode packages` 改走 monorepo 輸出格式；
  2. `default_package` 會**自動蓋到新建立**的 task（`task_store.py:376`、`add_session.py:1528`）；
  3. `--package` 給未知值從「被忽略」變成**硬錯誤 exit 1**（`task_store.py:370-373`）——
     既有文檔／指令若寫了亂七八糟的 package 名，從此會失敗；
  4. 扁平 spec 仍被注入（A3 的 bug），沒有任何警告（A1）。
- 沒有動到任何既有 task 的資料，也沒有動到 journal（`add_session.py:465` 的 package 只寫進 session 記錄，
  不影響既有檔案）。

---

## Part B — 版本事實

參照點：**Flutter stable 3.47.5（2026-09-18，內含 Dart 3.13.4）**。
來源：官方 releases manifest `https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json`
（`current_release.stable` = `hash 6a19cca56475dbfba1478ee68d7bd0c2ef891da1`）。
`release.yml` 目前釘 `FLUTTER_VERSION: '3.47.1'`（Dart 3.13.1）→ 落後現行 stable 四個 patch。
近幾版：3.47.0/Dart 3.13.0 (2026-08-12)、3.47.1/3.13.1 (2026-08-19)、3.47.2/3.13.2 (2026-08-27)、
3.47.3/3.13.3 (2026-09-09)、3.47.4/3.13.3 (2026-09-11)、3.47.5/3.13.4 (2026-09-18)。

### 表格

版本與日期全部取自 pub.dev JSON API（`https://pub.dev/api/packages/<pkg>`，欄位
`latest.version` / `latest.published` / `latest.pubspec.environment`），所見日期 2026-09-28。
「平台」取自 `latest.pubspec.flutter.plugin.platforms`。

| package | version | date | 平台 | notes |
|---|---|---|---|---|
| Flutter / Dart SDK | 3.47.5 / Dart 3.13.4 | 2026-09-18 | — | 現行 stable；CI 釘的 3.47.1 需更新 |
| `flutter_riverpod` | 3.4.3 | 2026-09-03 | 純 Dart | sdk `^3.12.0` |
| `riverpod_lint` | 3.1.9 | 2026-09-03 | 純 Dart | sdk `>=3.13.0-0`；**已遷移到新插件系統**，依賴 `analysis_server_plugin ^0.3.0` |
| `drift` | 2.35.0 | 2026-09-09 | 純 Dart | sdk `>=3.10.0 <4.0.0` |
| `drift_dev` | 2.35.0 | 2026-09-09 | 純 Dart | 與 drift 同版 |
| `drift_flutter` | 0.3.1 | 2026-07-11 | 純 Dart | |
| `sqlite3` | 3.6.0 | 2026-09-13 | 純 Dart | **3.x 內建 build hooks**，自行打包原生庫 |
| `sqlite3_flutter_libs` | 0.6.0+eol | 2026-02-15 | — | **已 EOL**。ADR 0010 不可用這個 |
| `isar_community` | 3.3.2 | 2026-03-23 | android/ios/linux/macos/windows | 只在 `legacy_import` 用（ADR 0010） |
| `isar_community_flutter_libs` | 3.3.2 | 2026-03-23 | android/ios/linux/macos/windows | 隨上面 |
| `flutter_secure_storage` | 11.2.0 | 2026-09-16 | android/ios/linux/macos/web/windows | 舊專案 pubspec 用 10.x 是**發版順序**考量，非技術阻礙 |
| `talker` | 5.1.20 | 2026-07-28 | 純 Dart | 日誌核心（ADR 0011） |
| `talker_flutter` | 5.1.20 | 2026-07-28 | 純 Dart | |
| `dio` | 5.11.1 | 2026-09-04 | 純 Dart | 與舊專案同版 |
| `slang` | 4.19.2 | 2026-09-12 | 純 Dart | |
| `slang_flutter` | 4.19.0 | 2026-08-06 | 純 Dart | |
| `slang_build_runner` | 4.19.0 | 2026-08-06 | 純 Dart | |
| `go_router` | 18.0.1 | 2026-09-02 | 純 Dart | flutter `>=3.44.0` |
| `just_audio` | 0.10.6 | 2026-06-29 | android/ios/macos/web | 後端 A（ADR 0018）；無 Windows/Linux |
| `media_kit` | 1.2.6 | 2025-12-13 | 純 Dart（＋libs 套件） | 後端 B；距今 9 個月 |
| `media_kit_libs_windows_audio` | 1.0.9 | 2023-09-27 | windows | **停在 2023-09**，與 ADR 0018 的註記相符 |
| `media_kit_libs_linux` | 1.2.1 | 2025-03-24 | linux | |
| `audio_service` | 0.18.19 | 2026-06-29 | android/ios/macos/web | 舊專案 pubspec 寫 0.18.15 |
| `audio_service_mpris` | 0.2.1 | 2026-03-15 | linux | |
| `smtc_windows` | 1.1.0 | 2025-08-18 | windows | 距今約 1 年 |
| `flutter_js` | 0.8.7 | 2026-01-27 | android/ios/linux/macos/windows | QuickJS／JSC + dart:ffi；見下方專節 |
| `window_manager` | 0.5.2 | 2026-07-04 | linux/macos/windows | **仍在出貨**；ADR 0021 說法有誤 |
| `nativeapi` | 0.4.0 | 2026-09-25 | 純 Dart | sdk `^3.13.0` |
| `nativeapi_flutter` | 0.4.0 | 2026-09-25 | —（未宣告 plugin platforms） | sdk `^3.13.0`、flutter `>=3.47.0`；**強制 Flutter 3.47+** |
| `tray_manager` | 0.7.0 | 2026-09-19 | linux/macos/windows | **大改**：改寫在 `nativeapi ^0.3.0` 上，flutter `>=3.47.0` |
| `hotkey_manager` | 0.2.3 | 2024-05-18 | linux/macos/windows | **最舊的一個**，約 2 年 4 個月無 release |
| `launch_at_startup` | 0.5.1 | 2025-04-01 | linux/macos/windows | 約 1 年 5 個月無 release |
| `desktop_multi_window` | 0.3.1 | 2026-08-26 | linux/macos/windows | |
| `connectivity_plus` | 7.3.1 | 2026-07-23 | android/ios/linux/macos/web/windows | |
| `file_picker` | 13.1.0 | 2026-09-15 | android/ios/linux/macos/web/windows | 聯邦化；v13 有 breaking |
| `path_provider` | 2.1.6 | 2026-06-15 | android/ios/linux/macos/windows | Flutter 官方維護，最穩 |
| `package_info_plus` | 10.2.1 | 2026-07-15 | android/ios/linux/macos/web/windows | |
| `permission_handler` | 13.0.2 | 2026-09-04 | android/ios/web/windows | v13 有 breaking；**macOS 未宣告** |
| `flutter_inappwebview` | 6.1.5 | 2024-10-08 | android/ios/macos/web/windows | stable 停在 2024-10；6.2 一直 beta |
| `share_plus` | 13.3.0 | 2026-07-23 | android/ios/linux/macos/web/windows | |
| `inno_bundle` | 0.12.0 | 2026-08-18 | windows（build-time） | v0.12 有 breaking |
| `flutter_lints` | 6.0.0 | 2025-05-27 | 純 Dart | 與舊專案同版 |
| `analysis_server_plugin` | 0.3.23 | 2026-09-11 | 純 Dart | 仍是 0.x；見下方專節 |
| `analyzer_testing` | 0.4.2 | 2026-09-11 | 純 Dart | 同名系列，一起升 |
| `analyzer` | 14.4.0 | 2026-09-11 | 純 Dart | sdk `^3.11.0` |
| `custom_lint` / `custom_lint_builder` | 0.8.1 | 2025-09-09 | 純 Dart | ADR 0015 已否決；最後發版 2025-09 |
| `alchemist` | 0.14.0 | 2026-03-13 | 純 Dart | CI golden |
| `googleapis/release-please-action` | **v5.0.0** | 2026-04-22 | node24 | 見下方專節 |
| `dorny/paths-filter` | **v4.0.3** | 2026-08-05 | node24 | 見下方專節 |

### 需要改 ADR 的落差

1. **`sqlite3_flutter_libs` 不可用**（`0.6.0+eol`，2026-02-15）。ADR 0010 寫的「native assets 自動打包五平台原生庫」
   要靠 `sqlite3` 3.x 內建的 build hooks，不是這個套件。ADR 0010 的套件名要改。
2. **ADR 0021 對 `window_manager` 的敘述不成立**：0.5.2 於 2026-07-04 仍正常發版；真正的變化是
   `tray_manager` 0.7.0（2026-09-19）改寫到 `nativeapi` 之上，而 `nativeapi`／`nativeapi_flutter` 是 2026-09-25 的新套件。
3. **`hotkey_manager` 0.2.3（2024-05-18）是這個清單裡最舊的相依** —— 全域快捷鍵是 ADR 0009 宣告的能力之一，
   而它兩年多沒 release。M1 若要在 Windows 做全域快捷鍵，這條值得先確認能不能用（含 repo 是否仍在維護）。
4. **`tray_manager` 0.7.0 與 `nativeapi_flutter` 都把 Flutter 下限拉到 3.47.0**。專案目前用 3.47.5 沒問題，
   但這等於把「可用的 Flutter 版本」綁在很新的地方；`release.yml` 的釘版要一起往上。
5. **`media_kit_libs_windows_audio` 停在 2023-09-27**（ADR 0018 已註記），目前仍是最新版。

---

## 專節：ADR 直接問到的四件事

### 1. `analysis_server_plugin` 是不是 stable、怎麼開、診斷看不看得到

- 官方文件 `pkg/analysis_server_plugin/doc/using_plugins.md`（Dart SDK main 分支，2026-09-28 所見）：
  - 「Analyzer plugins are supported starting in Dart 3.10 (Flutter 3.38).」
  - 開法是在 **top-level `plugins:`**（不是 `analyzer:` 底下）：

    ```yaml
    plugins:
      fmp_lints:
        path: packages/fmp_lints
        diagnostics:
          fmp_no_empty_catch: true
    ```

  - 「Analyzer plugins cannot be enabled, disabled, or otherwise specified or configured in a nested analysis
    options file」→ **只能寫在 package 或 workspace 根**。若 `app/` 用 pub workspace，就必須寫在 workspace 根。
  - 外掛的 **warnings 預設開、lint rules 預設關**，要在 `diagnostics:` 逐條打開。
  - 「Dart 3.10 (Flutter 3.38) sets its own constraint on the `analysis_server_plugin` package, `^0.3.0`.
    This may change with each release of Dart and Flutter.」→ 版本由 SDK 綁定，不是自由挑。
  - 改過 `plugins:` 之後 **需要重啟 analysis server**；啟用時會用 `dart pub upgrade` 解析一個 synthetic package，
    所以 CI 要有 pub 存取。
  - 版本仍是 **0.x**（`analysis_server_plugin` 0.3.23、`analyzer_testing` 0.4.2，同為 2026-09-11）——
    依 pub 語意，0.x 代表沒有穩定保證。
- **`dart analyze` 看得到、`flutter analyze` 看不到**（實測引用）：
  - flutter/flutter#187999 **open**：
    「flutter analyze (CLI) does not report new-system analyzer plugin diagnostics that dart analyze reports」。
  - flutter/flutter#193203 **已於 2026-09-23 關閉**，是 #187999 的重複。
  - → ADR 0015 決定在 CI 跑 `dart analyze --fatal-infos` 是對的，但**引用的 issue 號要改成 #187999**，
    且它尚未修好（ADR 0015 §後果「bug 修好後可以拿掉重複步驟」仍然成立、還不能做）。
- ADR 0015 留的未決項有答案了：**`riverpod_lint` 3.1.9（2026-09-03）已遷移到新插件系統**，
  依賴 `analysis_server_plugin ^0.3.0`，且要求 sdk `>=3.13.0-0`。

### 2. `flutter_js`

- 版本 0.8.7（2026-01-27），是現行最新；0.8.6 同日發佈，**之後 8 個月沒有新 release**。
  repo `abner/flutter_js`：未 archive、最後 push 2026-01-27、542 stars、81 open issues
  （`gh api repos/abner/flutter_js`，2026-09-28）。
- 平台：pubspec 宣告 android / ios / linux / macos / windows（**無 web**）。
  實作方式：Android 與 Windows/Linux 用 QuickJS，iOS/macOS 用系統 JavascriptCore，全部走 **dart:ffi**
  （依賴 `ffi`、`http`、`sync_http`），README 明說「no PlatformChannels needed」。
- **能不能在 `flutter test` 裡跑** —— README §"Unit Testing javascript evaluation" 給了明確答案，而且有前置條件：
  > We can unit test evaluation of expressions on flutter_js using the desktop platforms (windows, linux and macos).
  > For `Windows` and `Linux` you need to build your app Desktop executable first: `flutter build -d windows` … On
  > Windows … add the path `build\windows\runner\Debug` … to your environment path … For `Linux` you need to export
  > an environment variable called `LIBQUICKJSC_TEST_PATH` pointing to
  > `build/linux/debug/bundle/lib/libquickjs_c_bridge_plugin.so`.
  - 也就是說：**裸 `flutter test` 不能直接載入 QuickJS**，要先做一次桌面建置、再把原生庫的路徑塞進
    `PATH`（Windows）或 `LIBQUICKJSC_TEST_PATH`（Linux）。
  - 這正是 `phase2-plan.md` §7 那條「契約執行器能否在 `flutter test` 內載入 QuickJS（不行改用桌面
    `integration_test`）」的答案：**可以，但不是乾淨的 `flutter test`** —— 它需要桌面建置產物與環境變數，
    等於 CI 的測試步驟要先跑 `flutter build windows`。若不想揹這個耦合，就走桌面 `integration_test`
    （那本來就會有建置產物）。這是 M1 要拍板的取捨。
- 上游周邊：QuickJS C wrapper 在 `abner/quickjs-c-bridge`，Android 原生庫在
  `fast-development/android-js-runtimes`（jitpack），兩者都不必自行編譯。

### 3. `googleapis/release-please-action`

- **現行 major 是 v5**，最新 tag `v5.0.0`（2026-04-22）。v5 的**唯一 breaking change 是升到 node24**
  （release notes #1188）；v4 最後一版 v4.4.1（2026-04-13）。
- **沒有 `dry-run`**。逐項核對 `v5.0.0` 的 `action.yml`：inputs 是
  `token / release-type / path / target-branch / config-file / manifest-file / repo-url / github-api-url /
  github-graphql-url / fork / include-component-in-tag / proxy-server / skip-github-release /
  skip-github-pull-request / skip-labeling / changelog-host / versioning-strategy / release-as`，
  沒有任何 dry-run 或「傳 CLI 參數」的入口；README 全文搜不到 "dry"。
  最接近的是 `skip-github-pull-request: true` / `skip-github-release: true`，但官方定位是「把開 PR 與
  tagging 拆成兩段」，**不是 preview，別當 dry-run 用**。
  → `phase2-plan.md` §7 說的「以測試 repo 或 dry-run 跑通」：**只有測試 repo 這條路**。
  真要用 CLI 的 `--dry-run`（global option，「reports the activity that would happen without taking effect」），
  得直接跑 CLI，例如 `npx release-please release-pr --repo-url=<owner/repo> --token=<PAT> --dry-run`。
- **子目錄（`app/`）支援：支援，但 `path` 不是 config 欄位。** 官方 manifest 文件的 `packages` 是
  **path → 設定的 map，path 就是 key**；`schemas/config.json` 沒有 `path`/`package-name`/`component`
  （schema 落後），但 `src/manifest.ts`／`src/strategies/*` 為準：
  `RepositoryConfig = Record<string, ReleaserConfig> // path => config`。
  `path` 這個名字只出現在 Action 的 `path` input 與 CLI 的 `--path`（都是「單一套件、不寫 manifest」模式）。
- `release-type: dart` 是內建策略（README：「`dart` | A repository with a pubspec.yaml and a CHANGELOG.md」）。

  最小可用設定（對 ADR 0022 的「manifest 模式、`dart` 策略管理 `app/`」）：

  `release-please-config.json`
  ```json
  { "release-type": "dart", "packages": { "app": { "release-type": "dart" } } }
  ```
  `.release-please-manifest.json`
  ```json
  { "app": "0.1.0" }
  ```
  workflow
  ```yaml
  - uses: googleapis/release-please-action@v5
    with:
      token: ${{ secrets.MY_RELEASE_PLEASE_TOKEN }}
      config-file: release-please-config.json
      manifest-file: .release-please-manifest.json
  ```
- **子目錄的 outputs 會帶 path 前綴**：`app--release_created`、`app--tag_name`、`app--version`、`app--sha`…
  含 `/` 的 path 要用 JS property access：`steps.release.outputs['app--release_created']`。
  （root component 才會有無前綴的 `release_created` / `upload_url` / `tag_name` / `version` /
  `major` / `minor` / `patch` / `body`。）ADR 0022 的「release-please 輸出為否時不建置」要寫成
  `if: steps.release.outputs['app--release_created'] == 'true'`。
- 另外 v4.4.0 加了 action input **`versioning-strategy` 與 `release-as`**，所以 ADR 0022 的
  「第一版以 `Release-As: 2.0.0` 指定」除了 commit footer，也可以直接用 `release-as: 2.0.0` 這個 input。
  相關旗標另有 `--draft-pull-request`、`--draft`、`--prerelease`、`--force-tag-creation`。
- 注意 `action.yml` v5.0.0 **沒有宣告 `outputs:` 區塊**，但 outputs 仍以 `core.setOutput` 提供（README 有列）——
  依賴的是「未宣告的 output 仍可讀」，不是文件化的介面。

### 4. `dorny/paths-filter`

- **現行 major 是 v4**，最新 `v4.0.3`（2026-08-05）。v4.0.0 的 breaking change **同樣只是升到 node24**
  （v3.0.4 同日有 backport）。
- `filters` input 吃「設定檔路徑或 YAML 字串」，兩種都支援：

  ```yaml
  - uses: dorny/paths-filter@v4
    id: changes
    with:
      filters: |
        app:
          - 'app/**'
        legacy:
          - '**'
          - '!app/**'
  - if: steps.changes.outputs.app == 'true'
    run: ...
  ```
- 其他 input：`predicate-quantifier`（`some`｜`every`｜`some-with-excludes`）、
  `list-files`（`none`｜`csv`｜`json`｜`shell`｜`escape`）、`base` / `ref` / `working-directory` / `token`。
  output 是 `changes`（JSON array）與每個 filter 的 `<name>` / `<name>_files`；glob 用 picomatch（`dot: true`）。
- v4.0.3 含一個安全性修正（multi-line 檔名在 list-files shell/csv 輸出的跳脫，GHSA-7hc6-8hq5-9q2m）
  → 新專案直接用 v4.0.3。ADR 0015 只說「用 `dorny/paths-filter`」，沒有指定版本。

---

## 未能查證 / 保留

1. `release-please-action` 未來版本會不會補 dry-run —— 只能確認 v5.0.0 沒有。
2. `nativeapi` / `nativeapi_flutter` 的實際原生庫交付機制（pubspec 未宣告 plugin platforms、
   依賴 `cnativeapi`，看起來是 build hooks／native assets，但我沒看到 `hook/build.dart` 的證據）。
   M1 真要採用 `tray_manager` 0.7.0 前，值得實測一次 Windows 建置。
3. `hotkey_manager` 0.2.3 的變更內容 —— 上游 repo 根目錄已無 `CHANGELOG.md`，只能報版本與日期。
4. `permission_handler` 的 macOS 支援 —— facade 只宣告 android/ios/web/windows。
   這是「未宣告」，不等於「已移除」。
5. A3 的 A3/A4 行為全部來自 scratchpad 的實測；Trellis 未提供 migration 指令這件事，
   是 0.6.17 的 CLI 子命令清單所見，未來版本可能補上。
