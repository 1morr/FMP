# M1 PR 2 查證紀錄

- 查證日期：2026-09-29。本機 Flutter 3.47.5（`6a19cca564`）／Dart 3.13.4。
- 官方文件以 `gh api repos/flutter/website/contents/...`、`repos/dart-lang/site-www/contents/...`
  讀原始 Markdown；SDK 與套件行為讀本機 Flutter SDK 與 pub cache 的原始碼。

## 1. Windows flavor

- https://docs.flutter.dev/deployment/flavors-windows
  （`flutter/website` `sites/docs/src/content/deployment/flavors-windows.md`）：
  - 「Built-in support for flavors on Windows requires Flutter 3.47 or later.」
  - `--flavor` 時 flutter 把 flavor 寫進 `windows/flutter/ephemeral/generated_config.cmake` 的
    `FLUTTER_APP_FLAVOR`；它在頂層 `CMakeLists.txt` 的 `add_subdirectory(${FLUTTER_MANAGED_DIR})`
    之後才可見，`windows/runner/CMakeLists.txt` 讀得到。
  - 建置目錄依 flavor 分開：`build/windows/<arch>/<flavor>/runner/<Config>/`。
  - 「If you omit `--flavor`, `appFlavor` matches the default flavor configured in `pubspec.yaml`.」
  - 客製原生設定的建議做法是在 `runner/CMakeLists.txt` 依 `FLUTTER_APP_FLAVOR` 設值。
    文件用 `configure_file` 產生到原始碼目錄；本 PR 改用 `target_compile_definitions`
    （Flutter 範本傳 `FLUTTER_VERSION` 給 `main.cpp` 與 `Runner.rc` 的同一個機制），
    不產生要 gitignore 的檔案。
- 實作 PR：flutter/flutter#187034（commit `0145a67ea8f`，`git tag --contains` 從 3.47.0 起）。
  合併版的 `lib/src/cmake.dart:110-117` 註明「The default template does not use it」——
  PR 描述裡「BINARY_NAME 加 `-<flavor>` 後綴」的範本改動沒有進 3.47.5 的範本
  （`templates/app/windows.tmpl/CMakeLists.txt.tmpl:7` 仍是 `set(BINARY_NAME "{{projectName}}")`），
  所以兩個 flavor 的執行檔都是 `fmp.exe`，符合 prd。
- `default-flavor` 的解析：`flutter_tools/lib/src/runner/flutter_command.dart:1498-1503`，
  `cliFlavor ?? defaultFlavor`，並加進 dart-define `FLUTTER_APP_FLAVOR`；Windows、Linux、
  macOS、Android、iOS 裝置的 `supportsFlavors` 都是 true。
- 實測：`flutter build windows --flavor dev`／`--flavor prod` 的 exe 版本資源與寬字串：
  dev `ProductName=fmp-dev`、`FileDescription=FMP Dev`、`com.personal.fmp.dev`、
  `Local\FMP_MainInstance-dev`；prod `fmp`、`FMP`、`com.personal.fmp`、`Local\FMP_MainInstance`。

## 2. Android flavor

- https://docs.flutter.dev/deployment/flavors（`.../deployment/flavors.md`）：
  - Kotlin DSL：`flavorDimensions += "default"`、`productFlavors { create("staging") { dimension = ...; applicationIdSuffix = ".staging" } }`。
  - App 名稱放 `src/<flavor>/res/values/strings.xml`，manifest 的 `android:label="@string/app_name"`。
  - 「If your project sets `app_name` with `resValue()` … builds with AGP 9.0 or later fail by default」→ 不用 `resValue()`。
- 實測（`aapt2 dump badging`）：`app-dev-debug.apk` 是 `com.personal.fmp.dev`／`FMP Dev`，
  `app-prod-debug.apk` 是 `com.personal.fmp`／`FMP`。

## 3. `material_ui`

- https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui
  （`.../release/breaking-changes/material-ui-and-cupertino-ui.md`）：
  - 「In Flutter 3.47, developers can opt in to these packages ahead of the formal deprecation
    of the in-framework design libraries.」框架內的 Material／Cupertino 自 3.44 凍結。
  - 手動遷移：`flutter pub add material_ui`，`import 'package:material_ui/material_ui.dart';`。
- pub.dev API：`material_ui` 1.5.0（2026-09-28），`sdk ^3.13.0`、`flutter >=3.47.0`。
- SDK 內的 data-driven fix：`packages/flutter/lib/fix_data/fix_material/fix_material.yaml:30-35`
  把 `package:flutter/material.dart` 換成 `package:material_ui/material_ui.dart`。

## 4. pub workspace

- https://dart.dev/tools/pub/workspaces（`dart-lang/site-www` `src/content/tools/pub/workspaces.md`）：
  根 pubspec 以 `workspace:` 列成員，成員寫 `resolution: workspace`；Dart 3.11 起可用 glob。
- 實測：`workspace: []` 在 `flutter pub get` 下可解析。

## 5. 零聯網

- package:test 的 preset（pub cache `test-1.31.2/doc/configuration.md:845-877`）：tag 內可寫
  `presets: {force: {skip: false}}`，以 `-P force` 解除。
- **`flutter test` 沒有 `--preset`**：`flutter_tools/lib/src/test/runner.dart:75-91` 組給
  package:test 的參數只有 `--tags`／`--exclude-tags`／`--run-skipped` 等，沒有 preset；
  `flutter test -h` 同樣沒有。所以 ADR 0015 §決定 3 的「以 preset 解除」在 `flutter test`
  做不到，改用 `flutter test --run-skipped --tags live`。實測：裸 `flutter test` 顯示該條
  `Skip: live: …`；`--run-skipped --tags live` 時該條執行並通過（斷言被第二道擋下）。
- flutter_test 的 binding 初始化時會設 `HttpOverrides.global = _MockHttpOverrides()`
  （`packages/flutter_test/lib/src/_binding_io.dart:26-28`，由 `binding.dart:1289` 呼叫）。
  所以 `flutter_test_config.dart` 先 `TestWidgetsFlutterBinding.ensureInitialized()` 再設自己的
  override。實測：拿掉那一行後 `test/zero_network_test.dart` 有 3 條失敗。

## 6. 資料目錄與舊版位置

- `path_provider_windows` 2.3.0 `lib/src/path_provider_windows_real.dart:119-120,180-210`：
  application support 是 RoamingAppData 下的 `<CompanyName>\<ProductName>`（取自 exe 版本資源）。
- `flutter_secure_storage_windows` 4.1.0 `lib/src/flutter_secure_storage_windows_ffi.dart:234,253`：
  `flutter_secure_storage.dat` 寫在 application support。舊版 `Runner.rc:92,98` 是
  `com.personal`／`fmp`，所以舊版憑證在 `%APPDATA%\com.personal\fmp`。
- 舊版資料庫與 log：`lib/data/database/database_provider.dart:15,23-24,51`、
  `lib/core/log_file_sink.dart:25-26`（`getApplicationDocumentsDirectory()` 下的 `FMP`）。
- 安裝版判斷：ADR 0022 §決定 5（程式目錄有 `unins000.exe`），與舊版
  `lib/services/update/update_service.dart:54-57` 相同。

## 7. CI

- `dorny/paths-filter` v4.0.3 → `ceb8a2b8f2d89434be7ff52d3de7ec3738c5cc9d`
  （`gh api repos/dorny/paths-filter/git/ref/tags/v4.0.3`，輕量 tag 直指 commit）。
- README（v4.0.3）：`pull_request` 以 REST API 取變動清單，需要 `pull-requests: read`；
  push 以 git 比對，需先 checkout；推到 base 同一分支時與推送前的 commit 比。
  `predicate-quantifier: some-with-excludes` 才能表達「符合 `**` 且不符合 `!app/**`」。

## 8. 建置時發現

- MSVC 以系統字碼頁（本機 950）讀 `main.cpp`，繁中註解觸發 C4819，Flutter 範本的
  警告即錯誤讓建置失敗。`runner/CMakeLists.txt` 對 CXX 加 `/utf-8`。
