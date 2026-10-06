# app/AGENTS.md

新 App（ADR 0008）。每條行為以 `docs/adr/` 的 ADR 為準；這裡只寫從程式碼查不到的
契約，以及有閘門守著的規則（每條寫出它的閘門）。

## 驗證

在 `app/` 內執行：

| 改動 | 最少要跑 |
|---|---|
| 任何改動 | `dart format --output=none --set-exit-if-changed .`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` |
| `packages/fmp_lints/`、`analysis_options.yaml` 的 `plugins:` | 上一列，加 `packages/fmp_lints/` 內的 `dart test` 與 `dart run tool/lint_sentinel.dart` |
| 原生身分（`android/app/`、`windows/runner/`） | 第一列，加 `flutter build apk --flavor dev --debug`／`--flavor prod --debug` 與 `flutter build windows --flavor dev`／`--flavor prod` |
| Xcode 專案（`ios/`、`macos/`） | 第一列；本機沒有 Mac 時建置交給 CI 的 iOS、macOS job（prod release 與 dev debug 各一次） |
| drift 的 table 或資料庫類別（`lib/data/database/`、`lib/data/cache/`） | 先 `dart run build_runner build --delete-conflicting-outputs`，再跑第一列；改了 schema 另照 § 資料層 存新快照 |
| 翻譯（`lib/i18n/*.i18n.json`）或 `slang.yaml` | 先 `dart run slang`，再跑第一列 |
| 播放後端（`lib/playback/backends/`） | 第一列，加 Windows 與 Android 模擬器各跑一次 `flutter test integration_test/audio_backend_contract_test.dart -d <裝置>`（見 § 播放） |
| 提示宿主或外殼（`lib/ui/toast/`、`lib/ui/shell/`、`lib/app/`） | 第一列，加 Windows 與 Android 模擬器各跑一次 `flutter test integration_test/toast_layering_test.dart -d <裝置>`（提示在對話框、全螢幕頁之上，ADR 0023 §如何確認） |
| 發版（`../.github/workflows/app-release.yml`、`tool/release/`、`windows/installer/`、release-please 設定） | 第一列，加 actionlint（本機沒有就 `docker run --rm -v <repo>:/repo -w /repo rhysd/actionlint:latest .github/workflows/app-release.yml`）；改了 `.iss` 以 Inno Setup 6 編一次（本機沒有就用 `amake/innosetup` 映像） |
| 插件安裝與清單、搜尋頁、播放控制器（`lib/plugins/install/`、`lib/plugins/plugin_registry.dart`、`lib/ui/search/`、`lib/playback/playback_controller.dart`、`lib/playback/playback_session.dart`） | 第一列，加 Windows 跑一次 `flutter test integration_test/install_search_play_test.dart -d windows`（CI 另在 Linux 跑） |

- `flutter test` 不加參數：`live` 預設跳過（見「零聯網」）。CI 的 `app` job 跑上表前兩列
  與產生檔檢查（見「資料層」）；
  `fmp_lints` 的測試另外以 `TEST_ANALYZER_WINDOWS_PATHS=true` 再跑一次（Windows 路徑）。
- CI 另有五個平台的建置 job（都是 `--flavor prod --release`，iOS 加 `--no-codesign`；macOS、
  iOS 再建一次 `--flavor dev --debug`），以及 Linux（xvfb）與 Windows 的整合測試 job：
  `install_search_play_test.dart`、`toast_layering_test.dart`。真後端的契約與插件量測只在實機
  手動跑。
- 桌面裝置一次 `flutter test` 只能跑一個整合測試檔：flutter_tools 每個桌面裝置只有一個 log
  reader，第一個檔案的 App 結束時就關了，第二個檔案的 App 報 `Unable to start the app on the
  device`（`desktop_device.dart` 的 `DesktopLogReader`）。多個檔案就分開下指令，CI 也是一檔一步。
- `flutter analyze` 看不到 analyzer 插件的診斷、照樣回 No issues（flutter/flutter#187999），
  所以兩個都要跑：插件規則看 `dart analyze`，Flutter 專屬的診斷看 `flutter analyze`。
- `test/identity/windows_identity_test.dart` 要 `cmake`：CI 的 ubuntu runner 內建；
  Windows 的 PATH 上沒有時，測試以 vswhere 找 Visual Studio 附的那一份。
- 不帶 `--flavor` 的 run／build 是 dev（`pubspec.yaml` 的 `default-flavor`）。
- 插件執行環境的測試在裸 `flutter test` 裡跑真的 QuickJS：`test/flutter_test_config.dart`
  經 `test/support/quickjs.dart` 先以絕對路徑載入 flutter_js 內附的原生庫（Windows、Linux），
  不必先建置桌面版；插件的背景 isolate 以檔名開到同一份（整個行程共用）。找不到就拋錯，CI 不會
  默默跳過。macOS 不支援。看門狗的測試會留下一條忙著的執行緒，到那個測試檔的行程結束為止。
- 插件契約執行器（`test/plugins/contract/`，ADR 0015 §決定 6）就在裸 `flutter test` 裡：
  `contract_test.dart` 以 fixture 重播跑 `test/fixtures/plugins/` 底下每個插件目錄的
  `checks.json`，CI 沒有另外的步驟。
- 對 `app/` 以外的插件目錄跑契約檢查（插件庫的 CI 以固定的 FMP ref 這樣跑）：
  `FMP_PLUGIN_DIR=<絕對路徑> flutter test test/plugins/contract/contract_test.dart`
  （PowerShell：`$env:FMP_PLUGIN_DIR='<絕對路徑>'; flutter test test/plugins/contract/contract_test.dart; Remove-Item Env:FMP_PLUGIN_DIR`；
  不刪的話它留在整個 session，之後裸 `flutter test` 的契約測試也改跑那個目錄）。
  路徑是一個插件目錄，或每個子目錄都是插件目錄的目錄；插件目錄的格式見 § 插件。
- 錄 fixture（真實連線，ADR 0027 §決定 2；只限不需要登入的案例）：
  `FMP_PLUGIN_DIR=<絕對路徑> flutter test --run-skipped --tags live test/plugins/contract/record_test.dart`。
  每個案例的 fixture 整組重寫；有 `meta.edited` 的案例略過（手寫的錯誤案例不被蓋掉）；結果不符
  checks.json 期望的案例（例如連線失敗）什麼都不寫、原本的檔案不動。閘門：`record_test.dart`。
  錄完同一個測試以重播再跑一次。
- golden 測試（`alchemist`）在裸 `flutter test` 裡，只比 CI 版（文字畫成色塊，Windows 產生的圖
  在 CI 的 Linux 上逐像素相同；平台版在 `test/flutter_test_config.dart` 關掉）。改了版面就
  `flutter test --update-goldens <那個測試檔>`，看過 `goldens/ci/` 的圖再提交；比對失敗的差異圖
  寫在旁邊的 `failures/`（gitignore），CI 失敗時上傳成 artifact。
- 插件執行環境的實機量測：`flutter test integration_test/plugin_runtime_benchmark_test.dart -d <裝置>`
  （dev flavor；結果是 `FMP_BENCH` 開頭的行）。數字與方法在
  `.trellis/tasks/archive/2026-09/09-30-js-runtime/research/notes.md` §4。

### 實機驗證

操作步驟在 skill `.claude/skills/verify-on-device/`；根目錄的 `verify-legacy-on-device` 只給舊專案。
規則是 ADR 0027，實機驗證無法寫成測試，守它的是 review：

- **預設重播**：dev flavor 加內附測試插件（以 `--fmp-dev-plugin` 安裝 `fmp-test`，操作走 UI）；
  App 有每插件的重播開關之後也可以用它（§決定 1）。
- **真實連線的條件**：改動本身是插件、網路層、登入，或正在錄 fixture；只做最少的操作，
  不批次、不迴圈（§決定 2）。
- **每個使用者看得到的 PR 都要在 Android 模擬器與 Windows 各驗一次**（§決定 3）。
- **回報要有「平台」與「模式：重播／真實」**，真實時列出做了哪些請求；缺任一項 review 退回。
  截圖與回報不得含個人資訊（log 的 `App started` 帶含使用者名稱的資料目錄路徑）。
- 驗證只用 dev flavor；模擬器上的舊版 `com.personal.fmp` 不碰，prod APK 不安裝。

## App 身分

prod 與舊版相同，舊資料與憑證才讀得到（ADR 0008 §決定 3），改任何一項都要另立
ADR；dev 每一項都不同（ADR 0015 §決定 8）。

| 項目 | prod | dev | 設定在 |
|---|---|---|---|
| Android `applicationId` | `com.personal.fmp` | `com.personal.fmp.dev` | `android/app/build.gradle.kts` |
| Android App 名稱 | `FMP` | `FMP Dev` | `android/app/src/<flavor>/res/values/strings.xml` |
| Windows AppUserModelID | `com.personal.fmp` | `com.personal.fmp.dev` | `windows/runner/app_identity.cmake` |
| Windows 單一實例 mutex | `Local\FMP_MainInstance` | `Local\FMP_MainInstance-dev` | 同上（`Local\` 前綴在 `main.cpp`） |
| Windows 視窗標題、FileDescription | `FMP` | `FMP Dev` | 同上 |
| Windows ProductName | `fmp` | `fmp-dev` | 同上 |
| Windows 執行檔 | `fmp.exe` | `fmp.exe` | `windows/CMakeLists.txt` 的 `BINARY_NAME` |
| iOS／macOS bundle identifier | `com.personal.fmp` | `com.personal.fmp.dev` | `ios/`、`macos/` 的 `Runner.xcodeproj/project.pbxproj`：App target 每個 build configuration 的 `PRODUCT_BUNDLE_IDENTIFIER` |
| iOS／macOS 顯示名稱 | `FMP` | `FMP Dev` | 同上的 `APP_DISPLAY_NAME`；`Info.plist` 的 `CFBundleDisplayName`（macOS 另有選單列讀的 `CFBundleName`）指向它 |
| macOS App 套件 | `fmp.app` | `fmp.app` | `macos/Runner/Configs/AppInfo.xcconfig` 的 `PRODUCT_NAME` |

iOS、macOS 的舊版沒有發過，prod 沿用 Android 的 `com.personal.fmp`。

閘門：`test/identity/android_identity_test.dart`（含 main manifest 的 INTERNET）、
`test/identity/windows_identity_test.dart`、`test/identity/apple_identity_test.dart`；CI 的 Android
建置 job 另以 `aapt2 dump permissions` 看 release APK 合併後的權限。
沒有測試的兩處：mutex 的 `Local\` 前綴，以及 `main.cpp`／`Runner.rc` 確實讀這些定義；
改到它們時，檢查建置出的 exe 的版本資源與內嵌的寬字串。

- INTERNET 權限只寫在 main 的 manifest；`debug/`、`profile/` 的那一份是 Flutter 工具連進 App 用的，
  release 不合併，少了 main 那一行 release 就連不了網路。
- iOS、macOS 的 flavor 是 Xcode scheme（照 docs.flutter.dev/deployment/flavors-ios）：flutter 工具以
  `--flavor` 找同名的 `dev`、`prod` scheme，再找 `<Debug|Profile|Release>-<flavor>` 的 build
  configuration，並從 configuration 名稱取回 `appFlavor`，所以 scheme 名稱必須是小寫的 flavor 名。
  每個 target（含 `RunnerTests`、macOS 的 `Flutter Assemble`）的 configuration list 都要有這六個，
  少了的 target 會退回它的預設 configuration；`apple_identity_test.dart` 查這件事。
- 範本的 `Runner` scheme 與不帶 flavor 的 Debug／Release／Profile 照官方文件留著，身分是 prod，
  但 `appFlavor` 是上一次 flutter 指令寫進 `Flutter/Generated.xcconfig` 的 flavor：在 Xcode 裡不要用它
  建置，選 `dev` 或 `prod`。
- flutter_js 只有 podspec，iOS、macOS 建置時 flutter 會自己產生 Podfile（沒提交）。產生的 Podfile
  只對應 Debug／Profile／Release，其他 configuration CocoaPods 一律當 release（`Debug-dev` 的 pod
  也用 release 編）；要在 Xcode 除錯 pod 時，提交 Podfile 並照官方文件補上六個 configuration。
- Android namespace 兩個 flavor 都是 `com.personal.fmp`；只有 applicationId 帶後綴。
- Windows 的第二個實例以「視窗類別＋標題」找第一個實例帶到前景，所以兩個 flavor
  的標題必須不同；之後若在 Dart 端改視窗標題，要一併改 `main.cpp` 的尋找方式。
- Windows 的 ProductName 決定 path_provider 的目錄（`%APPDATA%\com.personal\<ProductName>`），
  dev 的 application support、cache 等目錄因此全部與 prod 分開。

## 發版

`../.github/workflows/app-release.yml`，設定在 repo 根的 `release-please-config.json`、
`.release-please-manifest.json`（ADR 0022 §決定 1–4）。測試都在 `test/release/`。

- 只能手動觸發，M9 才加 `push: branches: [main]`：重寫期間不發版。閘門：
  `release_workflow_test.dart` 的 `only workflow_dispatch triggers it`。
- 一個 run 內：release-please 維護發版 PR；發版 PR 合併後的那次 run 由它建 tag `v{版本}`
  與**草稿** release，接著建置、verify、publish（上傳後才轉正式，`releases/latest` 不會指到缺檔的
  版本）。沒有新 release 時建置以後的 job 全部跳過。閘門：同檔的 `nothing runs without a new
  release`、`only verified assets are published`；`release_please_test.dart`（`draft`、
  `force-tag-creation`、tag 不帶 component）。
- 版本號只由發版 PR 改：`pubspec.yaml` 的 `version` 等於 manifest，而且整行只能是
  `version: X.Y.Z`——release-please 的 `dart` 策略會把數字的 build number 加 1，同一行的註解會被
  當成 build number。versionCode 由 workflow 從 tag 算（`major*1000000 + minor*1000 + patch`，
  舊版的公式）以 `--build-number` 帶入；本機建置的 versionCode 是 1。閘門：
  `release_please_test.dart`；verify 核對 APK 的 versionName、versionCode。
- 第一版 2.0.0 由設定檔 `packages.app.release-as` 指定，不用 commit footer（落在哪個 commit、
  squash 後還在不在都難保證）。那一版發出後要刪掉，否則下一個發版 PR 又提同一版。閘門：
  `release_please_test.dart`（`release-as` 必須大於 manifest；2.0.0 的發版 PR 合併後 main 的 CI
  會紅，刪掉那一行就好，也可以合併前在發版 PR 上加一個刪它的 commit）。
- `bootstrap-sha` 是 `app/` 出現前 main 的最後一個 commit：第一個發版 PR 只收之後的 commit，
  release-please 只算動到 `app/` 的那些。有了第一個 release 之後它不再被讀。
- Android 與舊版同一把金鑰（ADR 0008 §決定 3），secrets 沿用舊 `release.yml` 的
  `KEYSTORE_BASE64`、`KEYSTORE_PASSWORD`、`KEY_PASSWORD`、`KEY_ALIAS`，缺一個 job 就失敗。
  workflow 寫出 `android/key.properties`（gitignore）；沒有這個檔時 release 用 debug 簽名，本機與
  CI 的建置照常能跑；檔案在但缺欄位時建置失敗。密碼寫進 Java properties，`\` 會被當成跳脫字元。
  閘門：verify 擋 debug 簽名與四個 APK 簽名不一。
- Windows 安裝檔是手寫的 `windows/installer/fmp.iss`，不用舊版的 inno_bundle（它不認得 flavor 的
  輸出目錄，舊版還要以 regex 修補它產生的腳本）。AppId、安裝位置、捷徑的 AppUserModelID 與舊版
  相同，理由在檔頭。閘門：`windows_installer_test.dart`。zip 與安裝檔包的是同一個程式目錄，另外
  放了 VC++ runtime 的三個 DLL（安裝檔會先清空安裝目錄，舊版附的那一份也在其中）。
- verify 是 `tool/release/verify_release_assets.dart`：檔名集合、checksums、別名逐位元相同、APK
  的 applicationId／版本／簽名、安裝檔的 PE 標頭、zip 根目錄就是程式目錄，以及舊版更新器相容
  （`tool/release/legacy_updater.dart`，移植自舊專案 `update_service.dart`；切換 PR 刪舊專案時它
  留著，v1.x 還在使用者手上）。閘門：`verify_release_assets_test.dart`、`legacy_updater_test.dart`
  （含 v1.11.0 的真實 asset 與 checksums）。
- 建置或 verify 失敗時 release 還是草稿（使用者看不到），tag 已建。暫時性的失敗在同一個 run
  重跑失敗的 job；要改程式就修好合併，下一個發版 PR 照常發布，失敗的草稿與 tag 手動刪。
- Linux、macOS 的發佈物由各自的平台任務加進 workflow 與 `expectedAssets`。

## 平台層

`lib/platform/`（ADR 0009）。怎麼加一個能力：`.trellis/spec/app/platform/index.md`。

- `PlatformCapabilities` 只含已經有實作的能力。Linux、macOS、iOS 驗證前宣告全部為
  「沒有」、沒有實作檔；`main()` 看到沒有資料目錄就只開「此平台尚未支援」的畫面。
- 新能力連同實作一起加：宣告欄位、各平台實作、組裝點的分支、測試列在同一個 PR，
  不先為之後的里程碑預留欄位。
- 平台判斷（`defaultTargetPlatform`、`TargetPlatform`、`Platform.isXxx`）只寫在組裝點
  `lib/platform/platform.dart`；其他程式從 `AppPlatform` 拿宣告與實作。

閘門：`test/platform/platform_test.dart` 以注入的平台值逐平台核對宣告與實作（未驗證
平台必須全部為沒有）；lint `fmp_platform_checks` 擋 `lib/platform/` 以外的平台判斷。
lint 的範圍是整個 `lib/platform/`，組裝點以外的平台層檔案、以及「不預留欄位」沒有
自動閘門，review 時看。

## 資料目錄

`lib/platform/app_data_directory/`（ADR 0009 §決定 7）。閘門：
`test/platform/app_data_directory_test.dart`。

- Windows 以程式目錄有沒有 `unins000.exe` 分安裝版與免安裝版（ADR 0022 §決定 5）。
  `flutter run` 出來的是免安裝版，dev 的資料在 `build/windows/x64/dev/runner/<模式>/userdata-dev/`，
  `flutter clean` 會一起清掉。
- dev 解析到舊版正式資料的位置（Windows 的 `Documents\FMP` 與
  `%APPDATA%\com.personal\fmp`、Android 舊版沙盒 `com.personal.fmp`）或其下，`main()` 在
  `runApp` 之前就拋 `LegacyDataLocationException`：Windows 的原生視窗仍會開，但內容空白。

## 資料層

`lib/data/`（ADR 0010）。怎麼加表、改 schema：`.trellis/spec/app/data/index.md`。

- 只有 `lib/data/` import `drift`／`sqlite3`。閘門：lint `fmp_layer_imports`。上層拿到的是
  repository 自己的值型別（`AppearanceSettings`、`InstalledPlugin`），不是 drift 產生的
  `*Row` 類別；這半條沒有閘門，review 時看。
- 資料庫是資料目錄下的 `fmp.db`，`main()` 在 `runApp` 之前開啟並跑一次查詢；開不起來只
  顯示 `DatabaseErrorApp`，不在半開的資料庫上啟動（ADR 0010 §決定 3）。閘門：
  `test/data/database/open_app_database_test.dart`（損壞的檔案在開啟時就拋）。`main()`
  的分支本身沒有測試。
- 外鍵每次開啟都在 `beforeOpen` 打開（SQLite 預設關、只對當前連線有效；ADR 0019 §決定 1）。
  閘門：`test/data/database/app_database_test.dart` 與 repository 測試的 cascade 案例。
- drift 與 slang（§ 介面）產生的 `*.g.dart` 提交進 repo（`app/.gitignore` 覆寫根目錄對
  `*.g.dart` 的忽略），拉下來不用先跑 codegen。改了 table、`@DriftDatabase` 就重跑
  `dart run build_runner build --delete-conflicting-outputs`，改了翻譯檔就重跑 `dart run slang`（不用
  slang_build_runner：它在乾淨的 checkout 會把已提交的產生檔當成衝突），並提交產生檔。閘門：CI `app` job 的
  「Check generated code is up to date」；本機沒有東西擋。在 Windows 上重跑會把產生檔與
  `linux/`、`macos/`、`windows/` 的 plugin registrant 改成 LF，內容沒變的（`git diff
  --ignore-all-space --ignore-cr-at-eol` 為空）直接還原。
- schema 快照在 `drift_schemas/app_database/`。閘門：`test/drift/app_database/schema_test.dart`
  ——程式碼建出的 schema 必須等於最新快照，`schemaVersion` 必須等於最新快照的版本。
- 持久化格式：列舉存 `lib/data/database/converters.dart` 寫死的字串（不是 enum 的
  `name`）、時間存 UTC epoch 毫秒、`TrackKey`（`lib/domain/track_key.dart`）的字面輸出
  與舊版逐字相同（M5 匯入要對得上）。改任何一個就是改資料格式。閘門：repository 測試的
  `stored format` 案例、`test/domain/track_key_test.dart`。
- `sqlite3` 3.x 以 build hooks 在建置時從它的 GitHub releases 下載預先編譯的 SQLite；
  第一次建置或 `flutter test` 要能連 GitHub。

### 快取庫

`lib/data/cache/`（ADR 0016 §決定 1–4、design §4.2–§4.4）。測試在 `test/data/cache/`，下面寫的
群組都在 `cache_store_test.dart` 或 `image_cache_manager_test.dart`。

- 快取目錄是平台快取目錄底下的 `fmp_cache/`（`cache.db`、`files/`、`staging/`），由
  `lib/platform/cache_directory/` 解析；那個目錄在 `lib/` 只准快取模組、組裝點
  `platform/platform.dart` 與 `main.dart` import，其他模組拿不到快取目錄。閘門：lint
  `fmp_layer_imports` 的 `restrictedImports`（`layer_imports_test.dart` 的
  `test_cacheDirectoryFromOutside`：能力宣告、同前綴的 `cache_directory_helpers.dart` 也報；
  `test_cacheDirectoryFromAllowedImporters`：`cache_sizes/` 這類相近名稱不報）。
- `cache.db` 是第二個 drift 資料庫，和主資料庫的規則不同：可以隨時丟。`cacheStoreProvider`
  第一次被讀時才開（`main()` 只注入 `cacheDirectoryProvider`）；開不起來（損壞）就清空
  `fmp_cache/` 重開一次、記 warning，不顯示錯誤頁；第二次也失敗是 `AsyncError`，封面只顯示
  佔位圖。版本不同（升級或 revert 後的降級）就刪掉所有表照目前的 schema 重建，不寫逐步
  migration。重建只清 `fmp_cache/` 裡面，平台快取目錄的其他東西不動。閘門：`opening` 群組
  （不是資料庫的檔、別的版本的檔、旁邊的檔案留著）、`cacheStoreProvider` 群組（開不起來是
  `AsyncError` 並記 error）、`test/drift/cache_database/schema_test.dart`（改了表沒加版本會
  紅）。清空之後第二次 `_open` 也失敗的那一支沒有測試（造不出清空後仍開不起來的目錄）。
- 開好之後先對帳才交出去：清空 `staging/`，刪掉檔案不見的列與 `files/` 裡不在索引的檔（寫到
  一半被關掉的 App、刪不掉的舊檔）。閘門：`opening` 群組的 `reconciles the index…`。
- 一個總上限（設定頁「網路」組的快取上限，沒設定就是平台宣告的預設），寫進索引之後超過就
  不分類別、不分插件，依 `last_access` 由舊到新刪到上限以下；`setLimit` 也馬上淘汰一次。不用
  計時器。`cacheStoreProvider` 開啟時取當時的值，之後設定一改就 `setLimit`，不重開快取庫。它
  直接訂閱 `NetworkSettingsRepository.watch()`、自己套用平台預設，不經 `networkProvider`：
  設定層在資料層之上（lint 擋 `data/` import `settings/`），兩邊的預設都讀
  `PlatformCapabilities.cache`，沒有另寫數字。訂閱的是 drift 的 stream，沒有人聽這個 provider
  時（Riverpod 會暫停它的 provider 訂閱）也照樣套用。閘門：`cacheStoreProvider` 群組的
  `a limit the user set replaces the platform default`、`changing the limit evicts down to it
  right away`（都沒有 listen 這個 provider）。寫索引、淘汰、清除、移除插件一個接一個跑；刪檔失敗只記 log，留給下次開啟的對帳。閘門：`eviction` 群組、
  `clear and remove` 群組。M2 只有 `image` 一個類別，「不分類別」是查詢沒有類別條件，沒有
  兩個類別的測試。
- 用量（`watchUsage`）每次索引變動都重發，設定頁靠它跟上下載、淘汰與清除。聽的是 drift 的
  `tableUpdates`、不是 `watch()` 查詢：後者在最後一個 listener 離開時排一個計時器，widget 測試
  結束時算成沒跑完的計時器，而 `createInBackground` 的連線關不掉它。閘門：`clear and remove`
  群組的 `the usage is sent again after a write, an eviction and a clear`。
- 鍵在「類別＋插件」內唯一：兩個插件給同一個網址各存一份、各經自己的允許網域下載，移除插件
  只刪自己的（design §4.2 寫 `key` 唯一，這裡加上兩欄）。閘門：`removing a plugin deletes
  only that plugin's entries`。
- 持久化格式：類別存 `cache_tables.dart` 的轉換器寫死的字串，時間是 UTC epoch 毫秒。閘門：
  `stored format`。
- `flutter_cache_manager` 只准在 `lib/data/cache/`、`cached_network_image` 只准在
  `lib/ui/artwork/` import；上層拿到的 cache manager 型別是 `cache_store.dart` 轉出的
  `BaseCacheManager`。閘門：lint `fmp_layer_imports`（`test_imageCachePackagesOutsideTheirOwners`、
  `test_imageCachePackagesInTheirOwners`）。轉出只有 `BaseCacheManager` 這一個型別，沒有閘門，
  review 時看。
- `FmpImageCacheManager`（`image_cache_manager.dart`，`cache_store.dart` 的 `part`）把
  `flutter_cache_manager` 的索引、檔案、下載三個介面換掉：
  - 它自己的淘汰（`getObjectsOverCapacity`、`getOldObjects`）一律回空，每次讀索引之後排的
    10 秒清理計時器因此什麼都不刪；它取檔前會先看檔案在不在，所以被快取庫淘汰的檔是未命中、
    重新下載。閘門：`the unified store is the only one evicting` 群組。
  - 索引以鍵寫入、不看 id：它記憶體裡的物件可能帶著已被淘汰的那一列的 id。閘門：
    `an update that carries the id of an evicted entry is written again`。
  - 讀到索引時才更新 `last_access`（記憶體裡已有的那份不更新），而且不等那次寫入；測試以
    `cache_harness.dart` 的 `read` 等它。那次寫入可能晚於清除或淘汰，所以寫索引和淘汰、清除、
    移除插件排在同一條隊伍，寫之前看檔案：不在就不寫，大小取磁碟上的（它的 `putFile` 對
    已有的鍵沿用舊的 `length`）。閘門：`last access` 群組（含 `a last-access update that lands
    after the file was removed…`）、`the size in the index is the size on disk`。
  - 下載經插件的媒體 client（上限 `artworkMaxBytes` 10 MiB），先完整寫進 `staging/` 底下每次
    不同名的檔，讀進記憶體才交給它寫檔。所以同一個 `destination` 不會同時下載兩次，它的
    `WebHelper` 串流中途出錯時不刪寫一半的檔的問題也碰不到（寫檔本身失敗留下的檔由對帳刪）。
    同一個 manager 同時要同一張圖只下載一次（`WebHelper` 合併）。閘門：`sharing` 群組、
    `failures` 群組的 `a connection that breaks mid-body leaves nothing behind`。
  - 新鮮度照它的 `HttpGetResponse`：`max-age`（大於 0）、`no-cache`，沒有就 7 天；它加的
    `If-None-Match` 不在 `mediaRequestHeaders`，過期就整個重新下載。副檔名只給認得的圖片
    類型，不由伺服器的字串組成檔名。閘門：`downloading` 群組。
  - 下載失敗以 `log.report`（tag `cache`）記下。閘門：`a failed download leaves no file…`。
- `flutter_cache_manager` 帶進 `sqflite`；App 不用它的預設索引，但不給 `cacheManager` 的
  `CachedNetworkImage` 會用 `DefaultCacheManager`（另一套索引與目錄、直接以 `http` 連線），
  所以 `CachedNetworkImage` 只在 `ArtworkImage` 用、而且一定給 cache manager（見「介面」）。

## Riverpod

- `main()` 的每個 `runApp` 都包在 `lib/app/app_scope.dart` 的 `appProviderScope`：全域
  `retry` 關閉（ADR 0013 §決定 4）。閘門：`test/app/app_scope_test.dart`（含一個預設
  重試會重試的對照案例）；lint `missing_provider_scope` 擋沒有 `ProviderScope` 的 `runApp`。
- 開好的資料庫（`appDatabaseProvider`，`lib/data/providers.dart`）、資料目錄
  （`dataDirectoryProvider`，`lib/platform/app_data_directory/`）、網路介面
  （`networkInterfacesProvider`，`lib/platform/connectivity/`）與快取目錄
  （`cacheDirectoryProvider`，`lib/platform/cache_directory/`）只由 `main()` 以
  `overrides` 注入；沒 override 就讀會拋錯。快取庫不由 `main()` 開，見「快取庫」。測試照樣
  override（記憶體資料庫、`test/support/fake_network_interfaces.dart`；不看介面的整合測試給
  `null`）。
  「只有 `main()` 開庫」沒有閘門，review 時看。
- 不用 `riverpod_generator`：provider 少，手寫。

## Log 與遮蔽

`lib/core/logging/`、`lib/core/redaction/`（ADR 0011、ADR 0025 §決定 3）。怎麼加遮蔽
名單、怎麼寫 log：`.trellis/spec/app/logging/index.md`。

- 門面 `Log` 是唯一的 log 入口；`print`、`debugPrint`、`dart:developer` 的 `log`、
  `package:talker*` 只准在 `lib/core/logging/`。閘門：lint `fmp_log_facade`。
- `Redactor` 是唯一的遮蔽函式，名單只在 `redaction_lists.dart`（插件以 `addRules`
  追加）。門面在交給 talker 之前就把 error、stackTrace 轉成遮蔽過的字串，原始物件不進
  歷史。閘門：`test/core/logging/log_test.dart`（假憑證經訊息、error、stackTrace、深層
  欄位寫入後，記憶體歷史與 log 檔都沒有原值）、`test/core/redaction/redactor_test.dart`。
  網路紀錄經門面寫入，閘門見「網路」；診斷包（M3）出現時各自補測試。
- 遮蔽本身拋錯時，門面把那筆換成只有層級與失敗型別的 `Redaction failed` 紀錄，不退回
  原文。閘門：`log_test.dart` 的 `a record that cannot be redacted`。
- log 檔：資料目錄的 `logs/fmp.jsonl`，JSON Lines，單檔 2MB，輪替成 `fmp.1.jsonl`、
  `fmp.2.jsonl`，共 3 個。欄位名稱與層級字串是持久化格式（Debug 頁在 M3 讀舊檔）。
  閘門：`test/core/logging/log_record_test.dart` 的 `stored format`、`log_file_test.dart`。
- 寫檔失敗不拋出、不影響 App，次數與最後一個錯誤留在 `LogFile.failureCount`／
  `lastFailure`。沒有資料目錄的平台只有記憶體歷史。
- 層級：debug build 為 `debug`，profile／release 為 `info`；console 只在 debug build。
  未捕捉的錯誤（`FlutterError.onError`、`PlatformDispatcher.onError`）經門面以 `error`
  寫入；是 `AppError` 的改走 `log.report`（才寫得出原因），以 `level` 參數固定為
  `error`，不依 `expected`（沒人接就是沒處理）。`level` 只給這裡用，處理過的錯誤不傳。
  `main()` 在解析資料目錄之後才接上，之前的錯誤走 Flutter 預設處理。閘門：
  `test/core/logging/uncaught_errors_test.dart`（預期內的 `AppError` 未捕捉仍是 `error`，
  原因經遮蔽寫出）。
- 保留期限（`LogFile.deleteExpired`）：輪替出來的 `fmp.N.jsonl` 最後修改超過 7 天
  就刪，目前寫入的 `fmp.jsonl` 不動，與大小輪替並存，不做設定項。只動 `logs/` 這一層
  符合檔名的檔案。排在 `LogFile` 的寫入佇列裡，不和輪替的改名交錯；失敗交給呼叫端，
  之後的寫入照常。由啟動維護清單的 `log-retention` 項目呼叫。閘門：`log_file_test.dart`
  的 `retention` 群組。
- 啟動維護清單：`lib/app/startup_maintenance.dart` 的
  `startupMaintenanceTasksProvider`（有序清單，新項目加在那裡）。`FmpApp` 在第一幀之後
  （`initState` 排的 post-frame callback，每次掛上只一次；`main()` 只掛一次）依序跑；
  每項各自 try，失敗經 `log.report` 進錯誤歷史後接著跑下一項，不重試；每項跑完寫一筆
  tag `maintenance` 的 log（`id`、`outcome`）。項目一個接一個 await，卡住的項目會擋住
  後面的，所以項目只放有限的本機工作。閘門：`test/app/startup_maintenance_test.dart`
  （畫過第一幀才跑、重建不重跑、失敗隔離、預設清單的 `log-retention`）。不跳提示（清單
  拿不到 `Toaster`）、不放空的登記點、週期性工作不放這裡（M3 的排程器）沒有閘門，
  review 時看。

## 錯誤

`lib/core/errors/`（ADR 0013）。怎麼加錯誤類型或 i18n key、音源怎麼寫對應表：
`.trellis/spec/app/errors/index.md`。

- 音源邊界以上只看得到 `AppError`：音源把自己的錯誤碼轉好，其他例外在邊界以
  `AppError.wrap` 包成 `UnexpectedError`。閘門：PR 9 的插件契約測試；在那之前沒有。
- `AppError` 沒有可以直接顯示的字串：使用者訊息只有 `messageKey`／`messageArgs`；
  `messageArgs` 是 `Map<ErrorMessageArg, int>`，放不進插件或伺服器的文字；音源名稱由呈現層
  以 `pluginId` 查。原始 error 與 stackTrace 是函式庫私有欄位，`toString()` 不含它們。閘門：
  `test/core/errors/app_error_surface_test.dart`（列出全部公開成員；型別參數裡的
  `String`／`Object`／`dynamic` 也算，含變異案例）、`app_error_test.dart` 的 `toString`。
- 被處理的錯誤一律經 `log.report(...)`（`report_error.dart`，`app_error.dart` 的 `part`）
  寫進錯誤歷史，那是唯一讀得到原始 error 的路徑。閘門：`report_error_test.dart`
  驗層級、欄位與遮蔽；「處理了卻沒 report」沒有閘門，review 時看。
- 重試只有網路層一層，用 `retry_policy.dart` 的純函數；Riverpod 的重試已關（見
  「Riverpod」）。閘門：`retry_policy_test.dart`；網路層的重試見「網路」。
- 禁止空 catch 與靜默吞錯。閘門：lint `fmp_no_empty_catch`（只擋空的本體；catch 了
  只 `return null` 之類的吞錯沒有閘門）。
- `report` 的欄位名稱與 `type` 的值（寫死的類別名，不是 `runtimeType`）進 log 檔，
  是持久化格式。閘門：`report_error_test.dart` 的 `writes the structured fields`。

## 網路

`lib/core/network/`（ADR 0012 §決定 1–2、ADR 0013 §決定 2、4）。怎麼發請求、改攔截器、
寫測試：`.trellis/spec/app/network/index.md`。測試都在 `test/core/network/`。

- 每插件兩個 client：API 用的 `SourceHttpClient`（`SourceHttpClientFactory.create`）與
  抓圖片、檔案的 `MediaHttpClient`（`MediaHttpClientFactory.create`）。`Dio` 只在
  `lib/core/network/` 建立（目前就是這兩個 `create`），`dio`（含 `dio_cookie_manager`）與
  `cookie_jar` 只准在 `lib/core/network/` import。閘門：lint `fmp_http_client_owner`、
  `fmp_layer_imports`（看目錄，不看是哪個函式）。
- 網域、轉址、HTTP 通用的限流語意（429、帶 `Retry-After` 的 503）與傳輸錯誤的對應只寫在
  `http_rules.dart`，兩種 client 都呼叫它，不各寫一份。閘門：兩個 client 測試的
  `allowed hosts`、`redirects`／`allowed hosts and redirects`、`error mapping` 群組各自
  斷言同樣的結果；「沒有另寫一份」沒有閘門，review 時看。
- 攔截器順序：認證 → cookie → 錯誤對應 → 限流 → 網路紀錄。dio 的 onRequest、
  onResponse、onError 都依加入順序執行，回程不反轉。攔截器 reject 一律帶第二個參數
  `true`，否則後面的 onError 全被跳過：限流拿不回位置、網路紀錄少一筆。閘門：
  `source_http_client_test.dart` 的 `interceptors run in the ADR 0012 order`（看得到的
  前後關係）、`a failed request gives its place back`。
- 重試在 `SourceHttpClient` 的迴圈裡，不在攔截器：每次重試重新走整條攔截器鏈（重新
  判斷認證、重新排限流），每次送出各一筆網路紀錄。閘門：同一檔的 `retry` 群組（只重試
  冪等請求、次數上限、`Retry-After`、取消不重試）。
- 網域：只准 `https`，host 等於 manifest 允許清單的項目或是它的子網域（帶百分比編碼的
  host 一律不准）；不符就不發請求，丟 `Unsupported`。轉址手動跟隨
  （`followRedirects: false`），每跳都檢查，最多 5 次，`Location` 解析不了也是
  `Unsupported`；跨 host 的下一跳拿掉原請求的 `Cookie`、`Authorization`，之後各跳都不再
  帶憑證。閘門：`allowed_hosts_test.dart`、`redirects` 群組。
- cookie 只存給設它的 host：`dio_cookie_manager` 原本會把轉址回應的 `Set-Cookie` 也存給
  `Location` 的 host，`cookie_jar` 也不檢查 `Domain` 屬性；這裡兩處都改了，`Domain`
  必須涵蓋回應的 host 而且本身在允許清單內，否則丟掉。閘門：`redirects` 群組的
  `a cross-host hop drops Cookie…`、`Set-Cookie Domain`。
- 狀態碼：網路層只把 429 與帶 `Retry-After` 的 503 轉成 `RateLimited`，其他回應原樣
  交給插件對應；傳輸錯誤轉 `NetworkError`。閘門：`error mapping` 群組。
- 取消（`abortTrigger`）丟 `RequestCancelled`，不是 `AppError`：只有取消的一方收到，
  不重試、不 report。
- cookie：每插件一個記憶體 jar，網路層不持久化。匿名 cookie（B 站 `buvid`）要跨重啟
  時，由插件從回應的 `Set-Cookie` 取值寫進自己的 storage（`plugin_storage`，ADR 0014
  §決定 5），下次以 `Cookie` header 帶上（cookie 管理會併進 jar 的 cookie）。沒有閘門，
  review 時看。
- 網路紀錄：tag `network`，每次送出一筆，欄位 `id`、`pluginId`、`client`（`source`／
  `media`）、`method`、`host`、`path`、`query`、`status`、`ms`、`bytes`、`error`、
  `credentials`、`retry`；不記 body。未登入而拒絕的 `required` 請求沒送出，也有一筆（沒有
  `status`、`ms`），`AuthRequired` 帶它的 id。失敗或狀態碼 ≥ 400 用 `warning`，其餘
  `debug`。欄位名稱與 `client` 的值是 log 檔的持久化格式（`network_log.dart`）；網路層
  產生的 `AppError` 帶那一筆的 `networkRecordId`。兩種 client 的工廠共用一個
  `NetworkRecordIds`（`networkRecordIdsProvider`），id 在同一次執行裡不重複。閘門：兩個
  client 測試的 `network log` 群組（欄位逐一比對；query 裡的假憑證與 body 不出現在記憶體
  歷史與 log 檔）、`media_http_client_test.dart` 的 `no Cookie or Authorization…`（兩種
  client 的 id 接續）；provider 的接線沒有閘門，review 時看。
- 認證：請求宣告 `AuthRequirement`，攔截器只依 `decideAuth` 的表注入。M1 的認證來源是
  `NoCredentials`（每個音源都未登入）。閘門：`auth_test.dart`（三種標記 × 三種狀態）。
- 網路狀態（`network_status.dart`，ADR 0016 §決定 6）：輸入只有平台層的介面變化與
  HTTP client 每次送出的結果（`RequestOutcomeSink`）。拿到回應不論狀態碼都是
  `responded`（被轉成 `RateLimited` 的 429 也是）；`NetworkError` 是失敗；沒送出的
  （網域不符、未登入的 `required`）、取消與其他錯誤不回報；每次重試、每一跳各算一次。
  播放後端的串流錯誤不是請求，不回報。任何回應都讓 `noInterface`、`unreachable` 回到
  `online`；失敗不改變 `noInterface`（介面消失前送出的請求晚一點才失敗）。回到前景時查到
  有介面不算「介面變化」，`unreachable` 留著。時間以 `clock` 讀，不開計時器。閘門：
  `network_status_test.dart`（轉換表逐列；fakeAsync 裡跑完後沒有待執行的計時器）、
  兩個 client 測試的 `network status` 群組。兩個工廠的 provider（`plugin_registry.dart`）都
  接同一個 `NetworkStatusNotifier.report`；接線沒有閘門，review 時看。
- 網路狀態不擋使用者發起的請求，`noInterface` 也照送（ADR 0016 §決定 7 的更正）：
  Windows 的 `connectivity_plus` 只把 Network List Manager 判定「連得上網際網路」
  （NCSI）的連線算成有介面，在 proxy、VPN 後面會誤報 `noInterface`，送出去拿到回應才
  回得到 `online`。不在 `online` 時不發背景請求（§決定 6；M2 還沒有背景請求，出現時
  補閘門）。閘門：`network_status_test.dart` 的 `a response`（`noInterface` 收到回應回到
  `online`）、`search_page_test.dart` 的 `offline` 群組（`noInterface` 仍送出搜尋）。
- Android 8 起背景收不到介面變化，`FmpApp` 在回到 `resumed` 時以 `recheckInterfaces`
  再查一次。閘門：`fmp_app_test.dart` 的
  `returning to the foreground checks the network interfaces again`。
- 媒體 header：媒體 client 的每一跳、交給播放後端的串流 headers，一律先經
  `mediaRequestHeaders`：只留 `Referer`、`User-Agent`、`Origin`、`Range`。閘門：
  `media_headers_test.dart`；後端確實經過它，見「播放」。

### 媒體 client

`media_http_client.dart`（ADR 0012 §決定 1、design §4.1）。測試在
`test/core/network/media_http_client_test.dart`，下面寫的群組都在這個檔。

- 每插件一個，`PluginRegistry` 在插件加入清單時（啟動載入、安裝、更新）以 manifest 的
  `allowedHosts` 建立，`mediaClient(pluginId)` 取得；插件被取代或清單釋放時關閉。閘門：
  `plugin_installer_test.dart` 的 `media clients` 群組（允許網域與 manifest 一致、更新後
  換成新網域、舊的關閉）。
- 目前唯一的呼叫端是封面：`artworkCacheManagerProvider(pluginId)`
  （`lib/plugins/plugin_artwork.dart`）以快取庫加上那個插件的媒體 client 組出 cache manager；
  清單裡那個插件的實例換掉（更新）時跟著重建、拿到新的 client，其他插件的變動不重建。閘門：
  `test/plugins/plugin_artwork_test.dart`。
- 不帶憑證：沒有認證、cookie 攔截器，也沒有 cookie jar；呼叫端給的 header 先經
  `mediaRequestHeaders`，每一跳都只帶這些。閘門：`credentials` 群組（同一插件的 API
  client 帶著憑證、jar 裡有 cookie 時，媒體請求仍沒有 `Cookie`、`Authorization`）。
- 網域與轉址照 API client 的規則（只准 `https`、每跳檢查、最多 5 次）；不符的那一跳不
  發出。另外網址或轉址的下一跳帶 user info（`https://user:pass@host/`）也是 `Unsupported`、
  不發出：dart:io 的 `HttpClient` 會把它變成 `Authorization: Basic …`，繞過
  `mediaRequestHeaders`（假 adapter 看不到這個 header，所以只能整個拒絕）。這條只在媒體
  client：API client 的 header 本來就由插件給。閘門：`allowed hosts and redirects` 群組
  （含 user info 的網址與轉址）。
- 下載到呼叫端給的 `destination`：內容先寫進旁邊的 `.part`（收到第一塊資料才建立），完成才
  改名；失敗（任何原因）就刪掉 `.part`，`destination` 原本的檔案不動。`maxBytes` 先比
  `Content-Length`，再邊收邊數，超過就中止、丟 `Unsupported`。同一個 `destination` 不要
  同時下載兩次（共用 `.part`）：封面的 cache manager 每次下載用不同的暫存檔（見「快取庫」）。
  閘門：`size limit` 群組（暫存目錄裡沒有留下檔案）。
- 不讀的回應（轉址、錯誤狀態碼、超過上限）以取消那一跳的 `CancelToken` 關掉連線：dio 的
  回應串流沒有人聽時不會自己關。閘門：各群組裡斷言 `released` 的案例。
- 逾時：連線 10 秒、等標頭與兩次收到資料之間 15 秒，交給 dio 的 `connectTimeout`、
  `receiveTimeout`（連線與等標頭由 `IOHttpClientAdapter` 計時，資料之間由 dio 核心計時）；
  整個下載（含每一跳）30 秒是自己的 `Timer`，到時取消目前那一跳。三種都是
  `NetworkError`；下載結束（成功或失敗）時取消那個 `Timer`。閘門：`timeouts` 群組
  （資料之間與整個下載以 fakeAsync 跑、`no timer is left once a download ends`；連線逾時
  只驗兩個值確實交給 adapter，計時本身在 dio 的 adapter 裡，沒有閘門）。
- 狀態碼：2xx 是成功；429 與帶 `Retry-After` 的 503 是 `RateLimited`，404、410 是
  `NotFound`，其他（含沒有 `Location` 的 3xx）是 `UnexpectedError`，狀態碼在網路紀錄。
  不重試。閘門：`error mapping` 群組。
- 網路紀錄每一跳一筆，在那一跳結束時寫（收內容時的失敗與已收的 `bytes` 也在同一筆）；
  `credentials` 永遠是 `false`、`retry` 永遠是 0。網路狀態每一跳最多回報一次：
  `NetworkError`（含收內容時中斷、逾時）是 `networkError`，其他拿到回應的是
  `responded`，取消與沒送出的不回報。已關閉的 client（插件更新後還拿著舊的）丟
  `UnexpectedError`、不送出：關閉後的 dio 丟 `connectionError`，交給它會被當成連不上。
  閘門：`network log`、`network status`（含 `a closed client sends nothing and reports
  nothing`）、`timeouts`、`cancel` 群組，以及 `allowed hosts and redirects` 的
  `… is refused without a request`。

## 插件

`lib/plugins/`（ADR 0014）。怎麼寫插件、怎麼加宿主 API：`.trellis/spec/app/plugins/index.md`；
給插件作者的型別定義：`lib/plugins/types/fmp-plugin.d.ts`。

- 安裝檔是單一 `.js`：開頭（前面只准 BOM 與空白）以 `/* ==FMP Plugin==`、`==/FMP Plugin== */`
  包一段 JSON manifest，之後是 ES module。讀 manifest 不執行腳本。manifest 與 DTO 的物件是封閉的：
  不認得的欄位整個拒收。閘門：`test/plugins/manifest/`。
- 能力與匯出函式同名、雙向一致：宣告了沒匯出、匯出了能力名稱卻沒宣告，都拒絕載入
  （`Unsupported`）；其他名稱的匯出不管。`apiVersion` 必須等於 `hostApiVersion`。閘門：
  `script_source_plugin_test.dart` 的 `exports and capabilities`、`plugin_manifest_test.dart`。
- manifest 的 `allowedHosts` 管插件交給宿主的每個網址：`fmp.http.request`（網路層擋，見「網路」）、
  串流候選（另外只准 `asset:///`，給測試插件）、封面、圖示。閘門：`script_source_plugin_test.dart`
  的 `returned values`、`plugin_runtime_test.dart` 的 `a host outside the manifest…`。
- 腳本的全域只有 JS 內建、唯讀的 `fmp`（宿主 API v1）與轉到 `fmp.log` 的 `console`。不用
  flutter_js 的 `getJavascriptRuntime()`（會裝繞過網路層的 `fetch`／`XMLHttpRequest`），它建構子裝的
  `console`、`setTimeout`、`sendMessage` 也不裝。閘門：`plugin_runtime_test.dart` 的
  `the global object has only the built-ins, fmp and console`。
- 每插件一個背景 isolate，裡面是那個插件的 QuickJS（prd 擁有者決定 7、ADR 0014 2026-09-30 補充）。
  宿主 API 的網路、storage、憑證、log 在主 isolate 執行、以訊息回覆，網域與插件 id 的檢查只在主
  isolate；`crypto` 在背景 isolate 算。`PluginHost` 在建構時綁定插件 id，腳本沒有辦法指定別的插件。
  閘門：`runtimes do not share globals`、`storage belongs to one plugin`。
- 錯誤：結構化錯誤 `throw {fmpError: '<AppError 類別名>', retryAfterSeconds?, reason?, message?}`
  （或 Error 帶這些屬性）轉成那個類別，`message` 只進 log；宿主 API 丟出的錯誤被腳本再拋出時原樣
  交出（保留網路紀錄 id）；其他拋出的值是 `UnexpectedError`，載入時的語法錯誤與形狀不對的回傳值是
  `ParseError`。閘門：`plugin_runtime_test.dart` 的 `errors` 群組、`a host error thrown on keeps its
  network record`。
- 看門狗：每次呼叫（含載入，從 isolate 起來後算）30 秒。到期時探測背景 isolate：2 秒內有回應就只是
  在等（例如網路），這次呼叫 `NetworkError`、插件照常；沒有回應（同步卡住）或背景 isolate 意外結束，
  插件轉成 `PluginHealth.unresponsive`：進行中與之後的呼叫都是 `UnexpectedError`（插件的 bug）、留在
  清單上但停用到 App 重啟，並 `Isolate.kill`。閘門：`plugin_runtime_test.dart` 的 `timeouts and
  disposal` 群組（真的 `while(true){}`、主 isolate 照常、另一個插件照常、背景 isolate 當掉）、
  `plugin_installer_test.dart` 的 `a plugin that stops responding…`。
- **卡住的執行緒回收不了**：QuickJS 的原生碼中斷不了，`Isolate.kill` 要等 isolate 回到 Dart 才生效，
  那條執行緒一直忙到 App 結束。沒有閘門，已知限制。
- `flutter_js` 只准在 `lib/plugins/runtime/` import（`fmp_layer_imports`），版本釘死
  （`pubspec.yaml` 的註解）。它的 Linux 建置不會把 QuickJS 的 `.so` 裝進 App 的 `bundle/lib`，
  `linux/CMakeLists.txt` 自己補；少了它插件在 Linux 一載入就失敗，閘門是 CI 的 Linux 整合測試。
- `fmp-plugin.d.ts` 與 Dart 端一致：interface 的欄位與必填對 `manifestShapes`、`sourceDtoShapes`、
  `hostApiShapes`，`FmpHost` 對 prelude 實際建出的 `fmp`，能力、錯誤名稱、`Unavailable` 原因三個
  union 對 Dart 的列舉。閘門：`test/plugins/type_definitions_test.dart`（含變異案例）。函式參數的
  型別不比對，review 時看。
- 開發入口：dev flavor 啟動時安裝 `--fmp-dev-plugin=<路徑>` 或環境變數 `FMP_DEV_PLUGIN` 指的檔案；
  Android 以 `adb shell am start -n com.personal.fmp.dev/com.personal.fmp.MainActivity --esal
  dart_entrypoint_args --fmp-dev-plugin=<App 讀得到的路徑>` 帶參數。prod 不讀：這條路徑跳過安裝前的
  確認（ADR 0014 §決定 6），參數與環境變數都能由別的程式帶入。`devPluginPath` 在 prod 一律回
  `null`。閘門：`plugin_installer_test.dart` 的 `development entry`（含 `prod reads neither…`）。
- 測試插件 `test/fixtures/plugins/test_plugin/`（`fmp-test`）只以 dev flavor 的 asset 打包，串流指向
  同目錄的 `tone.wav`（`asset:///…`）。prod 的建置只留下空目錄，沒有檔案。實機以
  `--fmp-dev-plugin` 裝它的 `.js`，搜尋任何關鍵字都有結果、都播得出來；關鍵字剛好是 `fail`
  時以 `RateLimited` 失敗（離線看錯誤提示）；`missing`、`preview`、`flaky`、`unavailable` 給播放
  恢復的實機驗證（`test_plugin/README.md`）。閘門：
  `test/plugins/test_plugin_bundle_test.dart`。第二個測試插件
  `http_test_plugin/`（`fmp-test-http`）會發請求（`*.fmp.test`），只給契約執行器，不打包。
- 插件目錄（契約檢查的單位）：剛好一個 `.js` 安裝檔、`checks.json`（鍵是能力名稱，所以每能力最多
  一條；只收 `SourcePlugin` 已有方法的能力）、`fixtures/<能力>/*.json`（依檔名是請求順序）。格式
  寫在 `fmp-plugin.d.ts` 的 `FmpChecks`、`FmpFixture`。執行器對每個案例各開一份資料庫、log 與
  client，檢查：能力與匯出一致、DTO 驗證、案例期望（成功的筆數與非空欄位，或失敗的 `AppError`
  類別與 `Unavailable` 原因）、沒試著連清單外的網域、串流 headers 不帶憑證、log 與 fixture 都遮蔽
  過。閘門：`test/plugins/contract/contract_runner_test.dart`（每種違反一個會紅的變異，另有改無關
  處不紅的案例）、`checks_test.dart`。
- 重播：第 n 個請求對第 n 個 fixture，比 method 與網址（實際網址先經 `Redactor`；query 不分順序；
  fixture 裡值為 `***` 的 query 參數與路徑段不比值）。對不上或用完就讓那次請求失敗、不送出；沒用
  到的 fixture 也算違反。header 與 body 不比。閘門：`contract_runner_test.dart`、
  `fixture_scan_test.dart` 的 `replay matching`。
- fixture 寫檔前經 `Redactor`（`HttpFixture.redacted`：網址與文字 body 用 `redact`、header 與
  `jsonBody` 用 `redactValue`，`set-cookie` 只遮值、留名稱與屬性，重播時才解析得了）；不是
  UTF-8 的 body 不錄。`app/` 內每個 fixture 都要「再遮一次不變」且名單上的欄位值是 `***`。閘門：
  `fixture_scan_test.dart`（`every fixture in app/ is redacted`，兩道檢查各有會紅與不紅的案例）、
  `record_test.dart`（假上游錄出的檔案沒有假憑證、重播通過）。
- 執行器看不到的：插件接住並吞掉「網域不在清單」的錯誤（網路層照樣不送出）；插件自己拋的
  `ParseError` 與 DTO 驗證失敗的 `ParseError` 分不出來。沒有閘門，已知限制。

## 播放

`lib/playback/`（ADR 0018）。怎麼改後端、寫播放測試、跑實機驗證：
`.trellis/spec/app/playback/index.md`。控制器的入口：臨時播放（`playTemporary`）、加入
（`addToQueue`）、下一首播放（`playNext`）、跳到（`jumpTo`）、移除（`removeAt`）、拖曳
（`move`）、清空（`clear`）、隨機（`setShuffle`）、循環輪轉（`cycleLoopMode`）、播放與暫停、
上一首與下一首、seek。佇列只在記憶體（持久化在 M2 PR 14）。

- `PlaybackController` 是 UI 唯一的播放入口，也是 `PlaybackState` 唯一的寫入者；
  `QueueModel`、`PlaybackSession`、`routePlaybackEvent`（`PlaybackEventRouter`，純函數）、
  `decideRecovery`（純函數）只回報。沒有閘門，review 時看。
- `just_audio`、`media_kit`（含 `media_kit_libs_*`）只准在 `lib/playback/backends/`
  import。閘門：lint `fmp_layer_imports`（`layer_imports_test.dart` 的
  `test_playbackEnginesOutsideTheBackends`：同前綴的 `lib/playback/backends_helpers.dart`
  也報；`test_playbackEnginesInTheBackends`：後端目錄與 `media_kitchen` 這類相似套件名
  不報）。
- 後端只有 `PlaybackSession` 碰：`backends/audio_backend.dart` 在 `lib/` 只准後端目錄、
  `playback_session.dart` 與組裝點 `playback_providers.dart` import；結束原因
  `TrackEndReason`（`backends/backend_rules.dart`）只准後端目錄與 `playback_event_router.dart`。
  所以 session 交給控制器的事件型別（帶結束原因）定義在路由器的檔案，session 傳值但不寫出
  型別名。閘門：lint `fmp_layer_imports` 的 `restrictedImports`（`layer_imports_test.dart` 的
  `test_restrictedPlaybackFilesFromOutside`：同前綴的 `backends_helpers.dart`、
  `playback_session_helpers.dart` 也報；`test_restrictedPlaybackFilesNearMisses`：
  `audio_backends.dart` 這類相近檔名與註解不報）。`test/` 不受限。lint 只看 import：
  `ref.watch(audioBackendProvider)` 不 import 也拿得到實例，這半條沒有閘門，review 時看。
- session 的事件同步交給控制器（`StreamController.broadcast(sync: true)`），控制器處理時
  不再經過一次微任務，時序與 M1 直接聽後端時相同；這靠後端在呼叫回來之前不送出回報，
  否則同步 broadcast 會在處理途中重入而拋錯。閘門：後端契約的 `reports arrive only after
  the call returns`（假後端在 `flutter test`，真後端照下一條手動跑）。
- 兩個後端共用的規則（結束分類 `classifyTrackEnd`、前瞻的清單修改 `LookAheadEdit`）只在
  `backends/backend_rules.dart`，後端只轉呼叫。閘門：`backend_rules_test.dart`；後端契約
  `test/playback/backends/audio_backend_contract.dart` 以同一份斷言跑假後端（`flutter
  test`）與平台的真後端（`integration_test/audio_backend_contract_test.dart`：Windows
  是 media_kit、Android 是 just_audio）。**真後端的那一份 CI 不跑**，改後端時照上面的
  驗證表在兩個平台手動跑。
- 交給後端的串流只能是 `BackendSource`，它在建構時就經過 `mediaRequestHeaders`，所以
  沒有別的路徑把 `Cookie` 之類交給播放引擎。閘門：`backend_rules_test.dart` 的
  `BackendSource`、`playback_controller_test.dart` 的 `the backend only gets media headers`。
- 引擎的錯誤（mpv 的 log 行、ExoPlayer 的例外）可能帶完整的簽名網址：後端只以
  `SourceFailed.cause` 交出或以 `error:` 交給門面，不放進訊息、不自己印。閘門：
  `playback_controller_test.dart` 的 `engine messages in the log`（假的 googlevideo 簽名
  網址經 mpv 行與例外兩種形狀，記憶體歷史與 log 檔都沒有原值）。media_kit 後端自己的
  那一行 warning 走同一個 `error:` 參數，但後端在 `flutter test` 裡建不起來，沒有直接的
  閘門。
- 整個 App 只有一個後端實例（`audioBackendProvider`）：just_audio 在 `play()` 經
  audio_session 要求 Android 音訊焦點，只在失去焦點或引擎卸載時放掉，換來源、`stop()`
  都不放；重建 `AudioPlayer` 才會（ADR 0018 §決定 3；來源在 `AudioBackend` 的
  dartdoc）。沒有自動閘門，實機以 `dumpsys audio` 確認（見 spec）。
- 前瞻：目前這首載入好後解析下一首一次，交接時不再解析；候選的 `expiresAt` 前 5 分鐘
  （`ResolvedStream.expiryMargin`，與網址快取同一個常數）作廢快取、重新解析並換掉前瞻，
  手動下一首也先檢查。閘門：`playback_controller_test.dart` 的 `hands over to the
  look-ahead…`、`pausing and resuming…`、`expiry` 群組；`stream_resolver_test.dart` 的
  `the margin is five minutes`。
- 前瞻跟著佇列：每個編輯（拖曳、加入、下一首播放、移除、隨機、循環）之後控制器呼叫
  `PlaybackSession.retargetLookAhead`，下一首還是同一首就留著（只改位置），換了就先清掉
  後端的前瞻再解析新的。清前瞻的修改還在後端排隊時引擎接上了舊的那首，session 先停下引擎、
  再把它當成目前這首播完（`SourceFinished`），控制器照一般的下一首重新開流；佇列沒有下一首
  時停在 `Idle`，被換掉的那首不出聲。閘門：
  `playback_controller_test.dart` 的 `editing the queue prepares the look-ahead again` 群組
  （拖曳、下一首播放、附加、移除、開隨機各一例，`an edit that keeps the next song…`、
  `the engine taking over the replaced look-ahead…`、`the engine taking over the look-ahead
  of a removed last song…`）。
- 前瞻開不起來（`AudioBackend.setNext` 的 dartdoc）：後端不接上它，目前這首照常播完；先發
  `SourceFailed(前瞻, open)`、再發目前這首的 `SourceEnded`，不發 `SourceAdvanced`，之後不再說在播。
  ExoPlayer 換到沒預備好的前瞻時先報新的索引（`ready`、沒有時長），錯誤之後才到；mpv 預開失敗時記
  一行不帶項目的錯誤、播完換過去後再記一次。所以兩個後端都等前瞻載入（ExoPlayer 的事件有時長、mpv
  換過去後第一次回報位置或時長）才發 `SourceAdvanced`，這段期間前瞻被換掉或清掉時停下引擎、報目前
  這首結束。session 收到前瞻的失敗就作廢它的網址快取、放掉前瞻（`Look-ahead failed to open`）；到
  那首時控制器照一般的下一首重新解析，再失敗才走恢復；目前這首不重試、不跳過。閘門：後端契約的
  `a look-ahead that cannot be opened…`（Dart 端就失敗的 asset）與 `a look-ahead refused over
  HTTP…`（loopback 403，引擎開流時才失敗）；`playback_controller_test.dart` 的 `a look-ahead that
  cannot be opened` 群組。換過去、還沒載入時前瞻被換掉的那一段時機抓不到，沒有自動閘門，review 時看。
  已知限制：ExoPlayer 給不出時長的前瞻（沒有長度資訊的串流）一直不算接上，上一首不會結束
  （`JustAudioBackend._pendingHandover` 的註解）。
- `SourceFailed.httpStatus` 只有 Windows（mpv）拿得到：來自 ffmpeg 的 warn log `http: HTTP error 403
  Forbidden`（所以 `MediaKitBackend` 以 `MPVLogLevel.warn` 收 log，`httpStatusFromLogLine` 解析），
  mpv 只把 ffmpeg 的 log 交給行程裡第一個還活著的實例（media_kit 在 `dispose` 後 5 秒才銷毀），
  App 只有一個後端所以拿得到，契約的 `a source refused over HTTP…` 因此排第一（它斷言自己建的是
  第一個後端，順序被改了在假後端就紅）。just_audio 0.10.6
  交給 Dart 的只有 `ExoPlaybackException.getMessage()`（一律 `Source error`），Android 一律
  `null`。狀態碼進 log（`Stream failed`、`Look-ahead failed to open`、`Playback recovery` 的
  `httpStatus`），並決定開流失敗怎麼恢復（見下面「恢復」）。閘門：
  `backend_rules_test.dart` 的 `httpStatusFromLogLine`（錄下的 mpv 行與反例）、契約的 `a source
  refused over HTTP…`（`reportsHttpStatus`）。契約的 HTTP 案例由測試在 loopback 起一個一律回 403
  的伺服器；Android 的 debug 建置以 `android/app/src/debug/res/xml/network_security_config.xml`
  只對 127.0.0.1 放行明文，release 不合併這份。閘門：`test/identity/android_identity_test.dart` 的
  `cleartext traffic` 群組（只有 debug 的 manifest 指向設定、只有 debug 有設定檔、只放行
  127.0.0.1）與 `parser mutations` 的三個明文案例。
- 臨時播放中不準備前瞻（舊版「臨時播放不預取」）：臨時曲目播完回到的那一首要從快照的位置
  開始，不能由引擎從頭接上。閘門：`temporary play` 群組的 `prepares no look-ahead…`。
- 單曲循環：前瞻是目前這首的同一份解析結果（`NextTrack` 的位置為 `null`），引擎無縫重播，
  交接時佇列不動；網址快過期時由前瞻原本的過期計時器重新解析。前瞻沒來得及接上時路由器給
  `RepeatTrack`，從頭再開（網址從快取拿）。臨時播放中循環的是臨時曲目，模式維持
  `temporary`。閘門：`loop one` 群組（兩圈只有一次 `Resolving stream`、快過期時重新解析、
  臨時播放中仍回到快照）、`playback_event_router_test.dart` 的 `completed under loop one…`。
- 網址快取（ADR 0016 §決定 5）在 `StreamResolver` 內、只在記憶體，前瞻與播放都經它：
  - 鍵是曲目鍵（含分 P）加上送給插件的偏好（M2 PR 8 前只有平台格式的順序）；最多 64 筆，
    淘汰最久沒用的。閘門：`stream_resolver_test.dart` 的 `the key is the whole track
    key…`、`keeps the 64 most recently used streams`。
  - 鍵也含解析它的插件實例：插件更新後是新的實例，舊實例的結果（以舊 manifest 的網域檢查
    過）與還在進行的請求都不給新的呼叫。閘門：`stream_resolver_test.dart` 的 `a replaced
    plugin is asked again…`。
  - 有效到第一個候選的 `expiresAt` 減 5 分鐘；沒有 `expiresAt` 的解析後 5 分鐘；一回來
    就在餘裕內的不放；時間經 `clock`。閘門：`stream_resolver_test.dart` 的
    `a stream is valid until…`、`without expiresAt…`、`a stream already inside the
    margin…`。
  - 同一個鍵正在解析時共用同一個 `Future`；解析失敗不留下。所以前瞻還在解析時目前這首
    播完，那首只解析一次。閘門：`stream_resolver_test.dart` 的 `concurrent calls…`、
    `a failed resolution…`；`playback_controller_test.dart` 的 `a look-ahead slower than
    the current track…`、`playing a track the look-ahead resolved…`。
  - 串流本身失敗（路由器給 `Recover`：開不起來、中斷、提前結束；以及緩衝飢餓）時控制器呼叫
    `PlaybackSession.invalidateCurrentStream`，只作廢那一個解析結果（已被較新的取代就
    不動）；重試與之後再播都重新解析，換候選照用手上的結果。閘門：
    `playback_controller_test.dart` 的 `a stream that failed to open is resolved again…`
    （反例 `playing a track again uses the cached stream`）、`an interrupted stream
    retries from its position`（重試解析了第二次）；`stream_resolver_test.dart` 的
    `an invalidated stream…`。
  - 實機數解析次數：`Resolving stream`（tag `playback`）一筆就是一次插件
    `resolveStream`；`Stream URL reused` 的 `from` 是 `cache` 或 `pending`；
    `Stream URL invalidated` 是作廢。
- 恢復（ADR 0018 §決定 7、design §7.5）由純函數 `decideRecovery` 決定，計數只在控制器：重試
  次數（`_retries`）、重新解析次數（換一首才歸零）、換過候選、連續跳過。表（每列在
  `recovery_policy_test.dart` 至少一例）：
  - `NetworkError`、`RateLimited`、中斷、提前結束：`online` 時從目前位置重試 1／3／9 秒，
    仍失敗跳過；不是 `online` 時等網路（下一條）。
  - 其他錯誤類別（含插件丟的 `Unavailable(previewOnly)`）立即跳過。
  - 開流被 HTTP 403／404／410 拒絕，或開流失敗而沒有狀態碼（Android 一律如此，擁有者
    2026-10-06）：作廢網址快取、重新解析一次（`ReResolve`），仍失敗換候選一次，再不行跳過；
    跳過時的錯誤 404、410 是 `NotFound`，403 是 `Unavailable`（原因為空），其他是 `Unsupported`
    （`openFailureError`，在路由器）。其他狀態碼（mpv 的 5xx 等）只換候選一次。沒有狀態碼又不在
    `online` 時先等網路。
  - 緩衝飢餓：進 `Buffering` 開一次性的 15 秒計時器、離開就取消；到期時第一次重新解析，同一首
    第二次跳過。
  - 一首在 `Playing` 中位置前進累計 10 秒，重試計數歸零（不開計時器；兩次回報相差超過 2 秒的是
    seek，不算）。
  - 跳過在 `queue` 往下一首，在 `temporary` 回到佇列；連續跳過達佇列長度（最多 10；臨時播放中
    臨時那一首也算一首，佇列只有一首時才回得去）停在 `Failed`。
  閘門：`recovery_policy_test.dart`；`playback_controller_test.dart` 的 `recovery` 與
  `recovery: refused and unopenable streams`、`recovery: counting`（含 `periodicTimerCount`）、
  `recovery: buffering starved for 15 seconds` 群組、`temporary play` 群組的 `a temporary track that
  cannot be played returns to a queue of one song`；`playback_event_router_test.dart` 的
  `a source refused with … carries the status and its error`。
- 等網路（design §5.3）：網路狀態（`networkStatusProvider`，組裝點以 stream 交給控制器，不重建它）
  不是 `online` 時，上一條標「等網路」的失敗停在這首：狀態是 `Retrying(delay: null)`（`attempt`
  為 0）、後端停下，不計重試、不算跳過、不提示（全域離線提示已經在畫面上）。回到 `online` 立刻從
  原位置重試，重試計數不變；等的時候暫停、換歌就不再等。M2 沒有本機檔，「跳到下一首已下載的」
  在 M6。閘門：`recovery: offline (design §5.3)` 群組、`app_shell_test.dart` 的 `waiting for the
  network shows no toast`。兩者都經測試自己的接線（`Harness`、`ShellHarness` 的
  `playbackControllerProvider` override）；組裝點 `playback_providers.dart` 把網路狀態與「跳過試聽
  片段」交給控制器的那幾行沒有閘門，review 時看。
- 試聽片段：插件回 `StreamResult.previewOnly: true` 時，「跳過試聽片段」開（預設）就跳過並提示，
  關就照播、播放列標「試聽」並發一次 `PreviewPlaying`（同一首重播、重試不再發）。試聽片段不當前瞻
  （到那首時才依設定處理，所以不會無縫接上）。設定在遇到試聽時經 `skipPreviewClipsProvider` 讀。
  閘門：`recovery: preview clips` 群組、`app_shell_test.dart` 的 `a preview clip played as one…`。
- 單曲循環的前瞻是目前開著的那個候選（換過候選就是換過的那個），不再經網址快取：換候選時快取
  已經作廢，再解析會拿回開不起來的第一個。清前瞻的修改排隊期間換了歌就不設（和解析回來時一樣
  比對代）。閘門：`loop one after a candidate switch repeats the candidate that played`、
  `switching to loop one and then to another song does not prepare the previous song…`。
- 控制器的 `events`（design §7.9）：`QueueFull`、`TrackSkipped`（跳過，帶錯誤與曲目）、
  `PlaybackStopped`（停在 `Failed`，帶連著播不了的首數）、`PreviewPlaying`。外殼以一個
  `ref.listen(playbackEventsProvider)` 轉成提示：跳過與只有一首播不了時以 `Toaster.error` 的
  `sentence` 說是哪一首、什麼原因（ADR 0013 類別表的訊息），去重是 `Toaster` 的同類同音源 5 秒；
  連續播不了停下時是一則警告「連續 n 首無法播放」（每首的原因已在跳過時提示過，同類的被去重，
  用錯誤提示會被去重吞掉）。閘門：`app_shell_test.dart` 的 `playback toasts` 群組、
  `playback_controller_test.dart` 斷言事件的案例。
- 被取代的解析結果丟掉（結果仍進網址快取），但插件的 `resolveStream` 沒有取消參數，
  網路工作不取消（ADR 0018 §決定 6 的取消等插件 API 支援）。已知限制。
- 佇列（`QueueModel`）是純 Dart：不碰資料庫與後端、不 import Riverpod 與 UI；隨機經建構子
  注入的 `Random`，播放位置與設定值（記住播放位置、倒退秒數）由呼叫端傳入。項目是
  `QueueEntry(TrackInfo)`（`lib/domain/track_info.dart`，插件的 `TrackSummary` 以
  `toTrackInfo` 轉過來）。純度沒有閘門，review 時看。
- 佇列：隨機以位置為單位（ADR 0018 §決定 5）。排列是位置的順序，編輯只動受影響的位置，
  其他未播位置的相對順序不變：拖曳只移動歌、不動排列（拖進本輪已播的位置本輪不再播）；
  下一首播放排在目前這首之後、連續加入依加入順序（目前這首換了或拖曳過就重新排）；附加插在
  下一首播放之後剩下未播的隨機一處；跳到某首把它的排序移到目前之後。一輪播完：循環全部時
  重排、剛播完的那個位置不排第一，否則停下。閘門：`queue_model_test.dart` 的 `shuffle`
  群組，其中 `a seeded run of edits plays every position once per round` 以固定種子跑一串
  編輯，比對「每個位置一輪恰好播一次」。
- 佇列：目前這首被拖到別的位置（自己被拖，或被別首推了一格）時，它的新舊位置交換排序，
  所以目前這首仍在本輪的進度上；這是「拖曳不動排列」唯一的例外。閘門：
  `dragging the current song keeps it current…`、上一條的種子測試。
- 佇列：上一首在播放超過 3 秒時回到開頭，否則往排列的前一個；隨機時一輪的開頭不往回繞。
  控制器傳的是來源最後回報的位置（解析中、等重試時是下次開始的位置）。單曲循環時佇列的
  上一首、下一首照「循環關」走，重播在控制器（見上面「單曲循環」）。閘門：
  `queue_model_test.dart` 的 `previous` 群組、`loop one leaves next and previous…`；
  `playback_controller_test.dart` 的 `previous within 3 s goes back…`。
- 佇列：任何加入（附加、下一首播放）會超過 10,000 首就整批不加、回傳 `false`，臨時播放
  不算；控制器另發 `QueueFull` 事件（`events`），外殼以 `ref.listen(playbackEventsProvider)`
  轉成警告提示。事件沒有 `const`、不覆寫 `==`：provider 以 `==` 決定要不要通知，連續兩次
  的 `QueueFull` 都要送到。閘門：`queue_model_test.dart` 的 `limit` 群組、
  `playback_controller_test.dart` 的 `adding past the limit adds nothing…`、
  `app_shell_test.dart` 的 `adding past the queue limit shows a toast each time`（第二次在
  去重的 5 秒之後）。
- 佇列：加入到空的佇列時第一首成為目前這首，但不開始播（播放列顯示它，按播放才解析）。
  閘門：`adding to an empty queue shows the song without playing it`。
- 佇列：臨時播放進入時記快照（播放位置、在不在播；回到的那一首是 `currentIndex`，佇列照常可
  編輯），已在臨時播放時只換曲目；下一首、上一首、播完、被跳過回到佇列並交回快照；單曲循環
  不改模式；點選佇列（`jumpTo`）、清空結束它並丟掉快照；下一首播放插在快照那首之後。閘門：
  `queue_model_test.dart` 的 `temporary play` 群組、`clear empties the queue and keeps loop
  and shuffle`。
- 臨時播放回到佇列（控制器，design §7.2）：「記住播放位置」開著時從快照的位置倒退「臨時播放
  回佇列倒退秒數」，關著時從頭；原本在播才自動播，原本暫停就只載入不播。進入時佇列那一首沒有
  載入（`Idle`、`Failed`、佇列是空的）就停在 `Idle`：臨時播放中才加進空佇列的歌也不自動播，
  播放列顯示佇列那一首，按播放從頭開始。臨時播放中佇列是空的時下一首可按（`hasNext` 為真），
  按下去結束臨時播放、停在 `Idle`。兩個設定值在回到佇列的當下經 `temporaryReturnSettingsProvider`
  讀（組裝點訂閱它，資料庫的值那時已讀出來）。閘門：`playback_controller_test.dart` 的
  `temporary play` 群組（三種觸發、四種設定組合、原本暫停、第二次臨時播放、空佇列兩例、
  臨時曲目播不了也回到佇列）、`playback_controls_test.dart` 的 `a rewind chosen here is used
  when a temporary play ends`。
- UI 開始播放：搜尋結果點一下是臨時播放；每首的選單（右鍵、長按、尾端「⋯」同一份）有播放
  （＝臨時播放，舊版 TrackAction 也是）、下一首播放、加入佇列，後兩者成功時提示一次（舊版的
  「已加入」）。播放列讀佇列項目的 `TrackInfo`。閘門：`search_page_test.dart` 的
  `playing a result` 群組、`integration_test/install_search_play_test.dart`。沒有播放的開發
  入口：實機驗證從搜尋頁點一首。

## 設定

`lib/settings/`（ADR 0011 §決定 7）。怎麼加一個設定欄位：`.trellis/spec/app/settings/index.md`。

- 設定表的欄位為空＝使用者沒設定過；預設值只在讀取時由 Notifier 套用，不寫進資料庫，
  所以改預設不需要 migration，也不會動到使用者設定過的值。閘門：
  `test/settings/appearance_settings_test.dart`（改預設後使用者值不變、未設定的欄位
  不被寫入）。
- 每組一個 Notifier，只寫改動的欄位；對外給套用預設後的值，另帶 `stored` 讓設定頁
  分辨「跟隨系統」。
- 語言沒設定過時跟隨系統的語言偏好清單（執行中改變也跟）：取清單中第一個對得到
  zh-TW／zh-CN／en 的，全都對不到才用 base locale zh-TW（ADR 0024 §決定 7）。
- 「網路」組（`network_settings`）目前只有快取上限（MiB，空＝平台宣告的預設，選項 128／256／
  512／1024）；舊版的快取設定不匯入（ADR 0016 §決定 3）。閘門：
  `test/settings/network_settings_test.dart`（改預設後使用者值不變、未設定的跟著預設、清回
  未設定）、`network_settings_repository_test.dart`（`clear` 群組直接查表是 `NULL`、
  `stored format`）。
- 「播放」組（`playback_settings`）的整張表在 M2 PR 10 一次建好（design §3.3 的十個欄位，
  schema v3），repository 的 `write`／`clear` 涵蓋全部欄位；Notifier（`playbackPreferencesProvider`）
  與設定頁只有已經有人用的欄位：記住播放位置（預設開）、臨時播放回佇列倒退秒數（預設 10，
  選項 0／3／5／10／15／30）、跳過試聽片段（預設開，見「播放」）。其他欄位的 setter 與設定列
  跟著用到它的 PR 加。音質、格式偏好的列舉存 `high`／`medium`／`low`、`opus,aac`／`aac,opus`
  （後者與舊版字面相同）。閘門：`test/settings/playback_settings_test.dart`、`playback_settings_repository_test.dart`
  （`stored format`、`clear`、只寫改動的欄位）、`test/drift/app_database/migration_test.dart`
  的 v2→v3 兩例。
- 「跟隨系統」是把欄位清回 `null`（repository 的 `clear`、Notifier setter 傳 `null`），不是
  存 `system` 之類的值；`write` 的 `null` 是「沒給、不動」。閘門：
  `appearance_settings_repository_test.dart` 的 `clear` 群組（直接查表是 `NULL`）、
  `appearance_settings_test.dart` 的 `null clears a field back to following the system`。

## 介面

`lib/ui/`、`lib/i18n/`（ADR 0023、ADR 0024）。怎麼用 token、加字串、跳提示：
`.trellis/spec/app/ui/index.md`。

- 間距、圓角、顏色只從 `lib/ui/theme/`（`AppTokens`、`AppLayout`、`ColorScheme`）取，字級只用
  `TextTheme` 的角色。閘門：lint `fmp_design_tokens`（`lib/ui/`，theme 目錄豁免）。`lib/app/`
  不在它的範圍，畫面都放 `lib/ui/`。
- 使用者看到的字串只來自 `lib/i18n/*.i18n.json`；base locale 是 zh-TW，缺字在執行時退回繁中，
  所以編譯擋不住漏翻。閘門：`test/i18n/translations_test.dart`（三個語言的 key 與 `{參數}`
  相同、每個 `ErrorMessageKey`／`UnavailableReason` 都有字串；含變異案例）。widget 裡寫死的
  字串沒有閘門，review 時看；時長（`3:05`、未知的 `-:--`）與語言名稱刻意不翻。
- 翻譯只經 `translationsProvider`（`lib/ui/i18n/ui_locale.dart`）注入：`slang.yaml` 設
  `locale_handling: false`，slang 不產生全域 `t`／`LocaleSettings`，語言狀態只有外觀設定一份。
- `MaterialApp.locale` 一律給帶書寫系統的 locale（`zh-Hant-TW`、`zh-Hans-CN`、`en`），由
  `flutterLocaleOf` 從 `LocaleSetting` 對出；它決定 Android 的繁簡字形與 Material 內建字串。
  `localizationsDelegates` 用 `material_ui` 的 `GlobalMaterialLocalizations.delegates`，不是
  `flutter_localizations` 的（後者給的是凍結的 material.dart 型別）。閘門：
  `test/ui/i18n/ui_locale_test.dart`（三種語言的 Material 字串）、`test/app/fmp_app_test.dart`
  的 `appearance` 群組。
- 主題的 `fontFamilyFallback` 取平台層依介面語言排序的清單（ADR 0024 §決定 2）；App 啟動與每次
  換語言寫一筆 `UI locale applied`（`locale`、`fontFallback`）。閘門：`fmp_app_test.dart` 的
  `the theme uses the platform fonts for the UI language`。字形是否正確只能實機看（設定頁的
  語言名稱、切到繁中與簡中介面）。
- 主題的每個文字樣式帶 `textLocaleOf` 的 locale（中文介面同介面語言，英文介面是繁中）：
  Android 不指名字型，英文介面的漢字不帶它就落到簡中字形。樣式的 locale 蓋過 `Text.locale`，
  要另一種字形的文字在樣式上指定。閘門：`app_theme_test.dart` 的
  `widgets inherit the text locale`、`fmp_app_test.dart` 的
  `CJK text takes the glyphs of the UI language`。
- 提示只經 `Toaster`（`toasterProvider`）：`SnackBar`、`ScaffoldMessenger.of` 等只准在
  `lib/ui/toast/`。閘門：lint `fmp_toast_entry`。`error` 只收 `AppError`，並自己
  `log.report`（被去重掉的也寫）。閘門：`test/ui/toast/toaster_test.dart`。背景工作不呼叫
  `Toaster`：沒有閘門，review 時看。
- `ToastHost` 在 `MaterialApp.builder`，以自己的 `Overlay`、`ScaffoldMessenger`、透明
  `Scaffold` 包住 Navigator：提示在全螢幕頁、對話框、底部面板之上，一次一則、新的取代舊的，
  時長 4／6 秒、帶動作也照時長消失、無障礙導覽時停留並有關閉鈕、App 在背景（hidden／paused）
  不顯示，位置避開 `toastBottomInsetProvider`。閘門：`test/ui/toast/toast_host_test.dart`。
  `Toaster` 同步送出：看狀態變化跳提示時在 `ref.listen` 的 callback 呼叫，不在 `build` 裡。
- 設定頁依 ADR 0011 的分組（外觀、播放、網路，design §9.8 的順序）：expanded 以上是
  list-detail（左分組、右內容，預設第一組），compact 與 medium 先是分組清單、點進去看內容，
  標題旁的返回鈕與系統返回鍵回到清單；選了哪一組由頁面記著，視窗寬度跨過斷點時不丟。外殼以
  `IndexedStack` 留著沒選的頁面，所以設定頁只在外殼正顯示它時（`visible`）攔返回鍵。Android
  返回鍵的整體分層（擁有者決定 7）在 M2 PR 16a，那時這個 `PopScope` 要併進外殼的規則。「網路」組
  顯示快取上限、封面用量（跟著索引變動）與「清除快取」：確認後清快取庫並清 Flutter 的
  `ImageCache`（`clear` 加 `clearLiveImages`；畫面上正在用的圖只有後者清得掉）；清除失敗記
  error、不報成功。閘門：`test/ui/settings/settings_page_test.dart`（寬、窄兩種版面、跨斷點、
  系統返回鍵、`a group left open does not hold the back key on another page`）、
  `network_controls_test.dart`（預設標明、選擇寫入、用量跟著變、取消不清、清除後索引與檔案與
  `ImageCache` 都空、清除失敗）。
- 淺色與深色主題下，示範畫面、四種提示，以及外殼裡的搜尋頁（搜尋前、有結果加播放列、沒有介面
  或連不上時搜尋失敗）與設定頁（外觀、播放、網路三組）在窄（400）與寬（1000）視窗通過點擊區與對比度 guideline。閘門：
  `test/ui/guidelines_test.dart`。
  新頁面要加進去。搜尋框因此用 `TextField` 而不是 M3 的 `SearchBar`（後者整條可點的那層沒有
  語意名稱、輸入框只有 24dp 高）。
- `WindowClass` 與 M3 同值（600／840／1200／1600，下限含在高的一級）。閘門：
  `test/ui/layout/window_class_test.dart`。
- 外殼 `AppShell`（`lib/ui/shell/`）依整個視窗的等級換導覽：compact 底部 `NavigationBar`（播放列
  在它上面）、medium 與 expanded `NavigationRail`、large 以上常駐 `NavigationDrawer`；都是 Material
  內建元件（ADR 否決 `flutter_adaptive_scaffold`）。播放列在內容區下方、與內容區同寬，佇列是空的時
  不佔位置。閘門：`test/ui/shell/app_shell_test.dart` 的 `navigation per window class`。
- 外殼量底部被佔住的高度（播放列＋底部導覽列＋安全區）發佈給 `toastBottomInsetProvider`；頁面
  不發佈。閘門：同檔的 `the bottom inset for toasts`、`toast_host_test.dart` 的 `position` 群組
  （含鍵盤：位移是鍵盤高度減 `viewPadding`）。
- 播放列的控制項依它自己的寬度分三段（ADR 0024 §決定 5，只放已經有的）：< 600 播放、下一首；
  600–839 上一首、播放、下一首、「⋯」選單（隨機、循環）；840 以上隨機、上一首、播放、下一首、
  循環（音量、輸出裝置在 M2 PR 13）；曲名至少 160dp。循環按一下依關閉 → 全部 → 單曲輪轉。
  隨機、循環的 tooltip 還沒附按鍵（Ctrl+S、Ctrl+R 在 PR 17）。閘門：
  `test/ui/player/player_bar_test.dart` 的 `controls per width`（599／600／839／840 等邊界）、
  `shuffle and loop` 群組、golden `player_bar_golden_test.dart`（三個寬度，只守版面結構）。
- 播放列的狀態標示（ADR 0018 §決定 7）：「等待網路連線」（`Retrying` 的 `delay` 為空）、「重試中」
  （其他 `Retrying`）、「試聽」（`playbackPreviewProvider`）以主色寫在曲名下那一行、上傳者之前，
  一行放不下就省略，三段寬度都在曲名欄裡、不另佔位置；狀態是 live region。閘門：
  `player_bar_test.dart` 的 `status labels` 群組（360／600／1000 三個寬度各三種）、guideline 測試的
  `the player bar waiting for the network`。
- 搜尋結果列的右鍵辨識器排除在語意樹外（`excludeFromSemantics`）：它會多一個沒有名稱的點擊
  動作，guideline 測試因此紅；同一份選單由「⋯」提供給輔助技術。閘門：guideline 測試的
  `search results and the player bar`。
- App 內快捷鍵（ADR 0024 §決定 8）只在 `lib/ui/shell/shell_shortcuts.dart` 的表，綁在外殼的
  `Shortcuts`：空白鍵、Ctrl+←／→、Shift+←／→（5 秒）、Ctrl+F、Ctrl+,、F6。文字編輯的快捷鍵
  （`DefaultTextEditingShortcuts`）由 `WidgetsApp` 放在 App 根、比外殼遠，外殼會先接走按鍵；所以
  同時是文字編輯鍵的那幾個用 `TextInputAwareAction`，焦點在輸入框時停用、按鍵交還輸入框。閘門：
  `app_shell_test.dart` 的 `shortcuts` 群組（`text-editing keys in the search field stay in the
  field`：輸入框裡的空白鍵、Ctrl／Shift 加方向鍵不動播放）。
- 焦點三區（導覽、內容、播放列）各是 `FocusScope`＋`FocusTraversalGroup`：Tab 只在區內循環，F6
  依序換區、跳過不在畫面上的播放列。只有圖示的按鈕有 tooltip（附按鍵）與語意標籤。閘門：同檔的
  `focus regions` 群組、guideline 測試（標籤）；tooltip 附按鍵沒有閘門，review 時看。
- 離線（ADR 0016 §決定 7、design §5.4）只有兩個呈現，都不是 toast：外殼內容區頂端的
  `OfflineBanner`（換頁仍在、`online` 時不佔位置、live region），以及頁面共用的
  `OfflineMessage`（`lib/ui/offline/`）。要網路的頁面不在 `online` 時照常送出使用者的
  操作（見「網路」），失敗時才顯示 `OfflineMessage` 與重試；已有的內容照常顯示。閘門：
  `app_shell_test.dart` 的 `the offline banner` 群組、`search_page_test.dart` 的
  `offline` 群組。
- `ToastHost` 的 `Overlay` 是 root overlay，文字選取工具列與放大鏡插在那裡，照常運作。閘門：
  `search_page_test.dart` 的 `text selection over the toast host`（Android 長按與放大鏡、Windows
  右鍵選單）。
- 封面只經 `ArtworkImage`（`lib/ui/artwork/`）：`CachedNetworkImage` 加上
  `artworkCacheManagerProvider(pluginId)` 的 cache manager，先看統一快取庫，沒有才經那個插件的
  媒體 client 下載（每跳檢查允許網域、不帶憑證與 header、10 MiB、逾時；見「快取庫」「媒體
  client」）。沒有 cache manager（快取庫開啟中或開不起來、插件不在清單上）、載入中與失敗都是同
  一個佔位圖；以高解碼（`memCacheHeight`）；不進語意樹（封面是裝飾）。呼叫端給曲目鍵的第一段
  當 `pluginId`。閘門：`test/ui/artwork/artwork_image_test.dart`（以假 cache manager：問的是哪個
  插件、挑哪一張、解碼高度、佔位圖、沒有封面就不要 cache manager、語意樹）。
- Flutter 記憶體的 `ImageCache` 大小由平台宣告（`PlatformCapabilities.cache`，Android 100 張／
  50 MiB、Windows 200 張／80 MiB，沿用舊版），`main()` 在 `runApp` 前套用，不開放設定。閘門：
  `platform_test.dart` 的宣告與數字；`main()` 的套用沒有測試。

## 零聯網

ADR 0015 §決定 3 的兩道防線：

- `dart_test.yaml` 讓 `live` tag 預設跳過。`flutter test` 沒有 package:test 的
  `--preset`，解除用 `flutter test --run-skipped --tags live`。
- `test/flutter_test_config.dart` 讓建立真實 `HttpClient` 直接拋錯；要聯網的測試在自己
  的 zone 以 `HttpOverrides.runWithHttpOverrides` 放行。

閘門：`test/zero_network_test.dart`——讀 `dart_test.yaml` 確認 `live` 預設跳過；斷言
建立 `HttpClient` 會被擋（含 widget 測試的 binding 之下）；另有一條 `live` 測試，解除
跳過後斷言仍被第二道擋下。

## Material

Flutter 3.47 起 Material 以獨立套件 `material_ui` 發佈，框架內的
`package:flutter/material.dart` 已凍結、之後會棄用
（https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui）。
`app/` 一律 `import 'package:material_ui/material_ui.dart'`；`widgets.dart`、
`services.dart` 等非設計系統的函式庫仍從 `package:flutter/` 匯入。Cupertino 同理用
`cupertino_ui`，需要時再加依賴。

閘門：lint `fmp_material_import`（見「Lint」）。

## Lint

`packages/fmp_lints/` 是自寫的 analyzer 插件（ADR 0015 §決定 2），在
`analysis_options.yaml` 的 `plugins:` 逐條開啟。規則都是 warning，`dart analyze` 失敗。

| 規則 | 守什麼（只看 `lib/`，除非另外寫） | 允許清單在 |
|---|---|---|
| `fmp_layer_imports` | 相對路徑跳出 `app/` 或非 `package:`／`dart:` 的 URI（全 package）；外部套件只准在擁有它的目錄；`lib/legacy_import/` 只被自己 import；列出的檔案或目錄只准列出的位置 import（目前是 `playback/backends/` 的 `audio_backend.dart`、`backend_rules.dart`，見「播放」；`platform/cache_directory/`，見「快取庫」）；`core/`、`domain/` 不 import `ui/`、`playback/`、`plugins/`、`data/`、`settings/`，`data/` 不 import `ui/`、`settings/`、`playback/`、`plugins/` | `rules/layer_imports.dart` 的 `externalPackageOwners`、`platformPackages`、`forbiddenLayerImports`、`sealedDirectories`、`restrictedImports` |
| `fmp_no_empty_catch` | catch 本體沒有陳述式（只有註解也算；全 package） | 無 |
| `fmp_log_facade` | `print`、`debugPrint`、沒以 `show` 排除 `log` 的 `dart:developer` import、`package:talker*` | `logFacadeDirectory`（`lib/core/logging/`） |
| `fmp_source_id_literal` | 字串整個等於官方插件 id（全 package） | `officialPluginIds`、`sourceIdAllowedDirectories`（`lib/legacy_import/`、`test/`） |
| `fmp_url_literal` | 含 `http://`／`https://` 的字串 | `endpointsFile`（`lib/core/endpoints.dart`） |
| `fmp_no_for_testing` | 名稱以 `ForTesting` 結尾（或就叫 `forTesting`）的方法、欄位、getter／setter、具名建構子、頂層函式與變數 | 無 |
| `fmp_http_client_owner` | 建立 `Dio`（任何建構子） | `networkDirectory`（`lib/core/network/`） |
| `fmp_test_waits` | `test/` 內直接呼叫 `pumpEventQueue` | `waitHelperFile`（`test/support/pump_until.dart`） |
| `fmp_ignore_reason` | 忽略 `fmp_` 規則的 `// ignore:`／`// ignore_for_file:` 沒在規則名後寫 ` — 理由` 或 ` - 理由`（全 package） | 無 |
| `fmp_platform_checks` | `Platform.isXxx`、`Platform.operatingSystem`、`defaultTargetPlatform`、`TargetPlatform` | `platformDirectory`（`lib/platform/`） |
| `fmp_toast_entry` | `SnackBar(`、`ScaffoldMessenger.of`／`.maybeOf`、`showSnackBar`、`clearSnackBars` | `toastDirectory`（`lib/ui/toast/`） |
| `fmp_design_tokens` | `lib/ui/` 內：`EdgeInsets`／`EdgeInsetsDirectional` 的參數、`SizedBox` 的 `width`／`height`／`dimension` 與傳給它的 `Size`、`BorderRadius.circular`／`.all`、`BorderRadiusDirectional`、`Radius.circular`／`.elliptical`、`fontSize:` 用 `0` 以外的數字字面值；`Color(…)`、`Color.fromARGB`／`fromRGBO`／`from` 帶數字字面值（`0` 也算）；`Colors` | `uiDirectory`、`themeDirectory`（`lib/ui/theme/` 豁免） |
| `fmp_material_import` | import／export `package:flutter/material.dart`、`cupertino.dart`（全 package） | `frozenDesignLibraries` |

允許清單都是 `packages/fmp_lints/lib/src/rules/` 裡的常數。閘門：

- 每條規則在 `packages/fmp_lints/test/rules/<規則>_test.dart` 有報與不報的案例；
  `test/plugin_test.dart` 斷言 `analysis_options.yaml` 開的正好是註冊的全部規則。
- `tool/lint_sentinel.dart` 暫放違規檔跑 `dart analyze`，斷言每條開啟的規則都報出來，同一條
  規則裡另加的表（`restrictedImports`）以 `_expectedMessages` 的訊息認。插件沒載入或編譯
  失敗時 `dart analyze` 會照樣綠，只有它會紅。

幾件從設定看不出來的事：

- 規則以名稱判斷（`Dio`、`SnackBar`、`Platform`），不查它來自哪個函式庫；同名的自訂型別
  也會被報。
- 忽略寫法：`// ignore: fmp_lints/fmp_url_literal — 理由`。理由接在名稱之後，analyzer 仍
  照常忽略。
- `fmp_lints` 釘 `analyzer` 13.3.0，不是 pub.dev 最新：它和 `flutter_test` 同一個
  workspace，`flutter_test` 釘的 `test_api` 讓 `analyzer_testing` 用不了 14.x。新 Flutter
  放寬後三個套件一起升（`.trellis/tasks/archive/2026-09/09-29-fmp-lints/research/notes.md` §1）。
- `riverpod_lint` 也接在 `plugins:`，規則全開。哨兵只驗 `fmp_` 規則，`riverpod_lint`
  沒載入時沒有東西會紅。
- 新規則怎麼加：`.trellis/spec/app/lints/index.md`。
