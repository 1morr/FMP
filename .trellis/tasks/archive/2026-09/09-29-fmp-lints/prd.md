# fmp_lints 與接線哨兵（M1 PR 3）

父任務：`../09-28-m1-skeleton-tracer`（design §2、§3「M1 的 lint」；implement「3.」）。

依據：
- ADR 0015 §決定 2（規則表、`analyzer_testing`、接線哨兵）；
- 各 ADR 的「如何確認」：0008、0009、0010、0016、0018、0020、0021、0022 的 `fmp_layer_imports`；0023 `fmp_toast_entry`；0024 `fmp_design_tokens`。

## 做什麼

1. **套件**：
   - `app/packages/fmp_lints/`，用官方 `analysis_server_plugin`（目前 stable，版本以 pub.dev 為準，`research/m1-tooling-facts.md` 記 0.3.23）。
   - 加進 `app/pubspec.yaml` 的 `workspace:`。
   - `app/analysis_options.yaml` 以頂層 `plugins:` 接上 `fmp_lints`，並在 `diagnostics:` 逐條開啟。
   - 寫法先以 context7 或官方文件查證，把來源記在 `research/notes.md`。
2. **規則**：12 條。
   - ADR 0015 的十條核心規則，加上 `fmp_toast_entry`、`fmp_design_tokens`；`fmp_periodic_timer_owner` 留到 M2。
   - 允許清單用 `app/lib/` 的相對路徑，照父任務 design §2 的目錄：

   | 規則 | M1 的允許清單 |
   |---|---|
   | `fmp_layer_imports` | 依賴方向表見下 |
   | `fmp_no_empty_catch` | 無豁免；catch 本體沒有陳述式就違規，變數名 `_` 不豁免 |
   | `fmp_log_facade` | `print`、`debugPrint`、`dart:developer` 的 `log`、`package:talker*` 只准在 `lib/core/logging/` |
   | `fmp_source_id_literal` | 官方插件 id 字串（M1 只有 `bilibili`；清單集中在規則內一處，M3 加 `youtube`、`netease`）只准在 `lib/legacy_import/` 與 `test/` |
   | `fmp_url_literal` | `http://`、`https://` 字面值只准在一個端點檔 `lib/core/endpoints.dart`（本 PR 不建，第一個需要網址的 PR 建） |
   | `fmp_no_for_testing` | `lib/` 不得宣告名稱以 `ForTesting` 結尾的成員 |
   | `fmp_http_client_owner` | `Dio(` 只准在 `lib/core/network/` |
   | `fmp_test_waits` | `test/` 內直接呼叫 `pumpEventQueue` 只准在 `test/support/pump_until.dart` |
   | `fmp_ignore_reason` | `// ignore: fmp_…` 與 `// ignore_for_file: fmp_…` 同一行必須寫理由（規則名之後有 ` — ` 或 ` - ` 加文字） |
   | `fmp_platform_checks` | `Platform.isXxx`、`Platform.operatingSystem`、`defaultTargetPlatform`、`TargetPlatform` 只准在 `lib/platform/` |
   | `fmp_toast_entry` | `SnackBar(`、`ScaffoldMessenger.of`／`.maybeOf`、`showSnackBar`、`clearSnackBars` 只准在 `lib/ui/toast/` |
   | `fmp_design_tokens` | `lib/ui/`（`lib/ui/theme/` 除外）：`EdgeInsets.*`、`EdgeInsetsDirectional.*`、`SizedBox` 的寬高與 `SizedBox.fromSize` 的 `Size(`、`BorderRadius.circular`／`.all`、`BorderRadiusDirectional.*`、`Radius.circular`／`.elliptical`（含巢狀）、`fontSize:` 不得用數字字面值（`0` 除外）；`Color(…)`、`Color.fromARGB`／`fromRGBO`／`from` 不得有數字字面值（含 `0`）；不得寫 `Colors.*` |

   **`fmp_layer_imports` 的依賴方向表**：
   - `app/` 不得 import 根目錄舊專案，也就是以相對路徑跳出 `app/`，或 `package:fmp/` 指向舊專案。`app/` 的 package 名也是 `fmp`，所以只能用路徑判斷。
   - `lib/legacy_import/` 不被其他目錄 import；`package:isar_community*` 只准在 `lib/legacy_import/`。
   - `package:drift*`、`package:sqlite3*` 只准在 `lib/data/`。
   - 平台套件只准在 `lib/platform/`：
     - `path_provider`、`window_manager`、`tray_manager`、`hotkey_manager`、`launch_at_startup`；
     - `desktop_multi_window`、`flutter_overlay_window`；
     - `permission_handler`、`smtc_windows`、`audio_service`、`audio_service_mpris`；
     - `connectivity_plus`、`file_picker`、`package_info_plus`；
     - `flutter_inappwebview`、`flutter_secure_storage`。
     
     清單集中一處，之後的 ADR 再加。
   - `package:just_audio*`、`package:media_kit*` 只准在 `lib/playback/backends/`。
   - `package:dio*` 只准在 `lib/core/network/`。
   - `package:flutter_js*` 只准在 `lib/plugins/runtime/`。
   - `package:background_downloader*` 只准在 `lib/downloads/`（M6 才有，先列入）。
   - `lib/core/` 與 `lib/domain/` 不 import `lib/ui/`、`lib/playback/`、`lib/plugins/`、`lib/data/`、`lib/settings/`。設定的 Notifier 讀資料層，所以放在 `lib/settings/`，不在 `core/`（本 PR 同步修正父任務 design §2）。
   - `lib/data/` 不 import `lib/ui/`。
   - ADR 0018 的細部規則（結束原因型別、串流窄介面）在 PR 10 加。
3. **`material_ui` 的閘門**：
   - PR 2 的 `test/static_rules/material_import_static_rule_test.dart` 改成規則 `fmp_material_import`：`lib/` 不得 import `package:flutter/material.dart` 與 `package:flutter/cupertino.dart`。
   - 刪掉那個測試。
   - 在 ADR 0015 的「後續 ADR 新增的規則」補一句，說明它守的是 ADR 0024 §決定 1 的 import 路徑。
4. **`riverpod_lint`**：
   - 若已支援新插件系統（研究說 3.1.9 依賴 `analysis_server_plugin ^0.3.0`），一起接上 `plugins:`；
   - 不行就記在 notes，留到第一個用 Riverpod 的 PR。
5. **測試**：
   - 每條規則用 `analyzer_testing` 做雙向變異：
     - 至少一個違規案例會報；
     - 至少一個相鄰、無關的寫法不報：允許目錄內、重新命名、改格式、註解或字串裡提到規則字樣。
   - 在 `app/packages/fmp_lints/` 內 `dart test`。
6. **接線哨兵**：一支可在 CI 與本機跑的 Dart 腳本 `app/tool/lint_sentinel.dart`。
   - 在 `app/lib/` 暫放一個違反每條規則的檔案，跑 `dart analyze --fatal-infos`；
   - 斷言失敗，而且輸出含每一條規則名；
   - 最後刪掉暫放檔，失敗時也要刪。
7. **CI**：`app` job 加三步：
   - `dart analyze --fatal-infos`（在 `app/`）；
   - 哨兵；
   - `fmp_lints` 的測試。
   
   `flutter analyze` 留著，因為它有 Flutter 專屬的診斷。在註解裡寫明 flutter/flutter#187999。
8. **文件**：
   - `app/AGENTS.md` 加 lint 段，列每條規則名、它守什麼、允許清單在哪裡改（ADR 0015 §如何確認：列出的每條規則寫對應規則名）；
   - 原本由 static-rule 測試守的 `material_ui` 那句改指規則名；
   - 建 `.trellis/spec/app/lints/index.md`（繁中），寫新規則怎麼加（雙向變異、哨兵、AGENTS.md）；
   - 不建 `spec/app/index.md`。
   - `trellis-check.md`、`trellis-implement.md` 的 `app` 分支加 `dart analyze --fatal-infos`。

## 驗收

- [ ] `app/`：`dart analyze --fatal-infos` 零問題；`flutter analyze`、`flutter test` 通過。
- [ ] `app/packages/fmp_lints/`：`dart test` 全綠，12＋1 條規則各有報與不報的案例。
- [ ] 哨兵在本機會紅，輸出含 13 個規則名；暫放檔在結束後不存在。
- [ ] 實測（§7）：
  - 同一個違規檔，`dart analyze` 報出插件診斷，`flutter analyze` 看不到；
  - 把兩者的輸出寫進 PR 描述。
- [ ] CI 的 `app` job 綠。
