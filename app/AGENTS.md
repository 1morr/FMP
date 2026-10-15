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
| 系統媒體控制與 `MainActivity`（`lib/platform/media_controls/`、`lib/playback/now_playing_publisher.dart`、`android/app/src/main/`） | 第一列，加 `flutter build apk --flavor dev --debug` 與 `flutter build windows --flavor dev`、Android 模擬器實機驗（§ 平台層的 `MainActivity` 覆寫、通知、`dumpsys media_session`、媒體鍵）；Windows 建置要有 `rustup`（見下方），並實機驗（`smtc_probe.ps1 -AppFilter com.personal.fmp.dev`、音量浮層的媒體卡片；指令經工作階段 API 只送給 FMP，不按全域媒體鍵，見 skill 的 `references/windows.md`） |
| 提示宿主或外殼（`lib/ui/toast/`、`lib/ui/shell/`、`lib/app/`） | 第一列，加 Windows 與 Android 模擬器各跑一次 `flutter test integration_test/toast_layering_test.dart -d <裝置>`（提示在對話框、全螢幕頁之上，ADR 0023 §如何確認） |
| 發版（`../.github/workflows/app-release.yml`、`tool/release/`、`windows/installer/`、release-please 設定） | 第一列，加 actionlint（本機沒有就 `docker run --rm -v <repo>:/repo -w /repo rhysd/actionlint:latest .github/workflows/app-release.yml`）；改了 `.iss` 以 Inno Setup 6 編一次（本機沒有就用 `amake/innosetup` 映像） |
| 插件安裝與清單、搜尋頁、播放控制器（`lib/plugins/install/`、`lib/plugins/plugin_registry.dart`、`lib/ui/search/`、`lib/playback/playback_controller.dart`、`lib/playback/playback_session.dart`） | 第一列，加 Windows 跑一次 `flutter test integration_test/install_search_play_test.dart -d windows`（CI 另在 Linux 跑） |

- Windows 建置要有 `rustup`：`smtc_windows` 每次建置都從原始碼編 Rust（套件的 cargokit 沒有預編譯二進位）。
  CI 的 Windows runner 映像內建 Rust，不必另裝。建過之後 `build/windows/x64/<flavor>/plugins/smtc_windows/cargokit_build/`
  底下有 cargokit 自己產生的 `.dart`，`dart format … .` 會報它「Changed」而回非零：只有 `build/` 底下的那一個時不是
  格式問題（CI 的格式檢查沒有 `build/`），其他檔案照常要修。
- `flutter test` 不加參數：`live` 預設跳過（見「零聯網」）。CI 的 `app` job 跑上表前兩列
  與產生檔檢查（見「資料層」）；
  `fmp_lints` 的測試另外以 `TEST_ANALYZER_WINDOWS_PATHS=true` 再跑一次（Windows 路徑）。
- CI 另有五個平台的建置 job（都是 `--flavor prod --release`，iOS 加 `--no-codesign`；macOS、
  iOS 再建一次 `--flavor dev --debug`），以及 Linux（xvfb）與 Windows 的整合測試 job：
  `install_search_play_test.dart`、`toast_layering_test.dart`，Windows 另跑 `secure_storage_test.dart`。
  真後端的契約與插件量測只在實機手動跑。
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
  錄製寫檔前（`Redactor` 之後）把 IP 位址（IPv4、全球單播 IPv6，含版本字串如 `Chrome/156.0.0.0`）換成文件位址（`lib/core/network/fixture/ip_scrub.dart`）；
  手寫的 fixture 也受同一道檢查。閘門：`ip_scrub_test.dart`、`credential_scan.dart` 的 `ipProblems`（`contract_test.dart` 與 `fixture_scan_test.dart` 都經 `scanFixture`）。
- golden 測試（`alchemist`）在裸 `flutter test` 裡，只比 CI 版（文字畫成色塊，Windows 產生的圖
  在 CI 的 Linux 上逐像素相同；平台版在 `test/flutter_test_config.dart` 關掉）。改了版面就
  `flutter test --update-goldens <那個測試檔>`，看過 `goldens/ci/` 的圖再提交；比對失敗的差異圖
  寫在旁邊的 `failures/`（gitignore），CI 失敗時上傳成 artifact。
- 插件執行環境的實機量測：`flutter test integration_test/plugin_runtime_benchmark_test.dart -d <裝置>`
  （dev flavor；結果是 `FMP_BENCH` 開頭的行；`--dart-define=FMP_BENCH_PLUGIN=<路徑>` 另量一個外部插件的載入）。數字與方法在
  `.trellis/tasks/archive/2026-09/09-30-js-runtime/research/notes.md` §4。

### 實機驗證

操作步驟在 skill `.claude/skills/verify-on-device/`；根目錄的 `verify-legacy-on-device` 只給舊專案。
規則是 ADR 0027，實機驗證無法寫成測試，守它的是 review：

- **預設重播**：dev flavor 加內附測試插件（以 `--fmp-dev-plugin` 安裝 `fmp-test`，操作走 UI）；
  App 有每插件的重播開關之後也可以用它（§決定 1）。
- **真實連線的條件**：改動本身是插件、網路層、登入，或正在錄 fixture；只做最少的操作，
  不批次、不迴圈（§決定 2）。
- **每個使用者看得到的 PR 都要在 Android 模擬器驗一次；改到平台各自實作的才另驗 Windows**（§決定 3 的 2026-10-13 修訂）：
  平台層 `lib/platform/`、播放後端 `lib/playback/backends/`、原生設定 `android/`、`windows/` 與帶原生程式碼的依賴、
  只在桌面出現的互動（快捷鍵、焦點區、滑鼠右鍵與 hover、視窗、輸出裝置、右側面板）。寬版版面在模擬器橫向驗。
  里程碑驗收兩個平台都走完整流程。
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
系統媒體控制的 manifest 設定（三個前景服務權限、`AudioService` 的屬性與 intent filter、
`MediaButtonReceiver`、沒有 `POST_NOTIFICATIONS`）由 `test/identity/android_manifest_test.dart` 以 XML
解析斷言，附變異案例（缺一項會紅，改屬性順序、縮排、註解不紅）。媒體工作階段的通知不受 Android 13 的
通知權限限制，所以不宣告 `POST_NOTIFICATIONS`；M6 的下載通知另行處理（ADR 0020 §決定 9）。
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
  「沒有」、沒有實作檔；`main()` 看到沒有資料目錄就只開「此平台尚未支援」的畫面（`main()` 的分支沒有測試，review 時看）。
- 新能力連同實作一起加：宣告欄位、各平台實作、組裝點的分支、測試列在同一個 PR，
  不先為之後的里程碑預留欄位。
- 平台判斷（`defaultTargetPlatform`、`TargetPlatform`、`Platform.isXxx`）只寫在組裝點
  `lib/platform/platform.dart`；其他程式從 `AppPlatform` 拿宣告與實作。
- 實作在播放後端的能力（`PlaybackSupport.outputDeviceSelection`：Windows 能選輸出裝置、
  Android 不能）不在 `AppPlatform`：引擎只准在 `lib/playback/backends/`，宣告與後端的
  `outputDevices` 是否為空由那裡的組裝點 `createAudioBackend` 的 assert 對齊。閘門：
  `platform_test.dart` 的宣告值；assert 在 debug 建置執行，真後端契約（經
  `createAudioBackend` 建後端）的 `output devices follow the platform declaration…` 在兩個平台
  手動跑時一起檢查。

- Secure storage（`lib/platform/secure_storage/`，ADR 0012 §決定 3、ADR 0029 §決定 5）：`PlatformCapabilities.secureStorage`
  （Android、Windows）。鍵只准小寫英數、`.`、`-`（Windows 直接當檔名），實作加上 `fmp-dev.`／`fmp.` 前綴，
  `deleteAll` 只刪自己前綴的鍵、不呼叫套件的全刪。Android 的 `resetOnError` 一律關：套件預設讀取失敗就清空，
  違反「讀取失敗不刪除」。`flutter_secure_storage` 只准在平台層（lint `fmp_layer_imports` 的 `platformPackages`）。閘門：
  `test/platform/secure_storage_test.dart`（前綴、鍵檢查、`deleteAll` 只刪自己、`resetOnError`）、
  `platform_test.dart`；真的寫讀刪是 `integration_test/secure_storage_test.dart`（手動，Windows 另在 CI）。
- 系統媒體控制（`lib/platform/media_controls/`，design §8）：`PlatformCapabilities.mediaControls`
  （`supportsSeek`）；Android 以 `audio_service` 實作。宣告在組裝點，實作在 `main()` 開好資料庫之後、
  `runApp` 之前由 `AppPlatform.withMediaControls` 初始化，失敗時記 log、宣告改為沒有，App 照常啟動。
  `audio_service` 與 `smtc_windows` 的擁有者都是 `lib/platform/`（`platformPackages`）。
- Windows（SMTC，`media_controls_windows.dart`，`smtc_windows` 釘 1.1.0）：宣告 `supportsSeek: false`、
  `positionRefresh: 5 秒`（SMTC 的 timeline 不會自己前進，`NowPlayingPublisher` 播放中依它從進度 stream 節流重推位置，
  用 `clock.now()` 比對、不開計時器；Android 為 `null`，照舊只在狀態改變與 seek 時推）。轉換都是純函數
  （`smtcMetadataOf`、`smtcTimelineOf`、`smtcStatusOf`、`smtcConfigOf`、`mediaCommandOf`）。`MediaPhase.idle`
  （含啟動恢復後還沒播）呼叫 `disableSmtc`、媒體卡片不顯示，建構時也是停用的（`init` 的 `SMTCWindows(enabled: false)`，只有實機驗）；有曲目再 `enableSmtc`。
  封面交曲目封面挑出來的那張的 `https` 網址（`NowPlaying.artworkUrl`，和 Android 的 `artworkFile` 同一張，
  `pickArtwork(…, 512)`）：只收 host 不空、連接埠不超過 65535 的 `https`，交出前以 `Uri.tryParse` 重新驗過，因為套件讀
  `thumbnail` 時 `CreateUri(..).unwrap()`，不合法的字串會讓 Rust 端 panic（`Uri` 接受任何連接埠，`CreateUri` 不收超過
  65535 的；百分比編碼的空白、非 ASCII 收得下）。套件的 `updateMetadata` 只設不是 `null` 的欄位：上一首有、這一首沒有的
  上傳者或封面要先 `clearMetadata`（`smtcClearsMetadata`），否則留著上一首的。**已知例外**：這張圖由 Windows 自己下載，不經 App 的
  媒體 client（不帶 App 的 header 或 cookie；網址在 DTO 解碼時已通過 manifest 的 `allowedHosts`）。實測
  結論：`file:///` 封面在未封裝 App 的 SMTC 讀不到（2026-10-07），所以不交快取檔。
  停止鍵：有曲目（非 idle）時 `smtcConfigOf` 啟用 stop，否則系統送的停止指令不會轉給 App；`MediaStop` 由控制器當
  暫停。浮層的隨機、循環鈕（ADR 0018 §決定 8 的補充，#263）：套件的 `shuffleChangeStream`、`repeatModeChangeStream` 只是系統的
  「要求」，轉成 `MediaSetShuffle`、`MediaSetRepeat`，`NowPlayingPublisher` 決定照不照做（直播不理；Mix 不理隨機，要求「全部」
  時照 Mix 的輪轉 off → one → off；值相同不理；不理的記 debug log `System media command ignored`），再把 App 實際的
  `NowPlaying.shuffle`／`repeat` 推回去（變了才呼叫 `setShuffleEnabled`／`setRepeatMode`）。SMTC 不能單獨停用這兩顆鈕，所以用「不理」代替；
  Android 的通知不顯示，新欄位收下不用。
  **釘版**：`pubspec.yaml` 直接依賴 `flutter_rust_bridge: 2.11.1`，必須等於 `smtc_windows` 的 `rust/Cargo.toml`
  釘的版本（`=2.11.1`）。套件的 `pubspec.yaml` 只寫 `^2.11.1`，不釘的話 Dart 端解析到較新版本，執行時
  `SMTCWindows.initialize()` 丟 `codegen version … should be the same as runtime version …`；初始化失敗只記
  log、App 照常啟動，所以沒有測試就沒人發現。升級 `smtc_windows` 時一起改。
  閘門：`smtc_bridge_version_test.dart`（經 `.dart_tool/package_config.json` 找套件、比對 `Cargo.toml` 與
  `pubspec.lock`，含解析函式的雙向變異案例）。
  閘門：`media_controls_windows_test.dart`（轉換、封面只收 https 與合法連接埠、停止鍵啟用、按鍵含停止對應指令、隨機與循環的對應和要求轉指令、只推變了的；
  `the adapter` 群組以假的 `SMTCWindows` 守 idle 不啟用、離開 idle 先啟用再推全部、回到 idle 清掉並停用、只推變了的部分、
  缺欄位先清）、`platform_test.dart`
  的 `system media controls on Windows`（宣告與初始化失敗）、`now_playing_publisher_test.dart` 的
  `position refresh`、`artwork url`、`shuffle and repeat`（一般、Mix、直播、相同值）、`queue_model_test.dart` 的 `setLoopMode`；`layer_imports_test.dart` 的 `smtc_windows` 案例守「只在 `lib/platform/`」。
- Android 的前景服務與中斷（`media_controls_android.dart`）：`androidStopForegroundOnPause: true`，暫停時
  `audio_service` 放掉前景服務、通知可以滑掉（舊版也是這樣，省電）。來電等中斷把播放暫停後，掛斷時控制器
  自動續播，`audio_service` 的 `enterPlayingState` 要重新 `startForegroundService`，但 App 這時在背景，
  Android 12 起拒絕（`ForegroundServiceStartNotAllowedException`，logcat `Background started FGS:
  Disallowed`），例外只進 `AudioService.asyncError`；之後服務不在前景，約 1 分鐘 `am_stop_idle_service`、
  再約 1.5 分鐘 `am_freeze`，音樂就停了（模擬器實測，2026-10-08）。所以只在「因中斷而暫停」的期間
  （`MediaPhase.interrupted`）對 `audio_service` 回報 `playing: true` 加 `AudioProcessingState.buffering`：
  `exitPlayingState` 不會跑、前景服務不放，buffering 讓系統不推算進度；續播時不必從背景重新啟動前景服務。
  不改成永遠不放前景服務：一般暫停放掉是想要的行為。轉換是純函數 `androidPlaybackStateOf`；Windows 的
  `smtcStatusOf` 把 `interrupted` 對成 SMTC 的暫停（Windows 沒有這個問題，也不會出現這個 phase，列舉要完整）。
  `AudioService.asyncError` 由 `AndroidSystemMediaControls` 在初始化後聽，以 `log.report`（tag
  `media-controls`）記下，不提示使用者（`AppPlatform.withMediaControls(log:)` 交給實作）。閘門：
  `media_controls_android_test.dart`（`interrupted` → playing 加 buffering 加暫停鍵、一般階段不變；`reportAsyncErrors`
  記 log、取消後不再記）、`media_controls_windows_test.dart` 的 `status`、`now_playing_publisher_test.dart` 的中斷案例。
  **沒有自動閘門、要實機驗**：`audio_service` 的 `asyncError` stream 是私有的，`AndroidSystemMediaControls`
  聽的是不是它、以及真的來電後前景服務有沒有留住，只能在 Android 模擬器驗：背景播放中
  `adb emu gsm call 5551234`、`gsm cancel 5551234`，掛斷後音樂續播，`logcat` 沒有 `Background started FGS:
  Disallowed`，`logcat -b events` 之後沒有 `am_stop_idle_service`、`am_freeze`；`dumpsys media_session` 在中斷期間
  是 `BUFFERING`（2026-10-08 實測通過：關螢幕 3 分鐘照常播、前景服務一直在）。**已知限制**：Android 的媒體卡片對
  `BUFFERING` 畫轉圈圖示、不是暫停鍵，通話期間不能從卡片暫停，掛斷後照常續播（實測）。
- Android 媒體鍵修正（#233，`android/app/src/main/java/com/personal/fmp/MediaKeyFix.java`）：`audio_service` 0.18.19 把真正的
  `KEYCODE_MEDIA_PLAY`／`KEYCODE_MEDIA_PAUSE` 都當 `MediaButton.media`、Dart 端切換，已暫停時收到「暫停」鍵會開始播放。
  不能繼承服務（套件的 `MediaBrowserCompat` 與 `startForegroundService` 都以 `AudioService.class` 指名），所以
  `MainActivity` 登記頻道 `fmp/media_keys`，Dart 的 `MediaKeyFix.install()` 在 `audio_service` 初始化後與每次非 idle 的
  `publish` 呼叫，原生端用反射把服務的 `mediaSessionCallback` 換成把 PLAY／PAUSE 改成套件的 `KEYCODE_BYPASS_PLAY`／
  `KEYCODE_BYPASS_PAUSE` 的子類別（可重複呼叫，失敗只記 log）。依賴非公開欄位 `instance`、`mediaSession`、
  `mediaSessionCallback`，R8 的 keep 規則在 `android/app/proguard-rules.pro`。閘門：`audio_service_internals_test.dart`
  釘版 0.18.19（升級時重查欄位與 `onMediaButtonEvent`）、`media_controls_android_test.dart` 的 `the media key fix`
  （呼叫時機、失敗不影響播放）。**反射與鍵碼改寫沒有自動閘門、要實機驗**：暫停時 `adb shell input keyevent
  KEYCODE_MEDIA_PAUSE` 仍暫停、播放時 `KEYCODE_MEDIA_PLAY` 仍播放，`KEYCODE_MEDIA_PLAY_PAUSE` 仍切換。
  **已知限制**：行程不在時由媒體鍵喚起服務、沒開 Activity 的那段期間，引擎是服務自己建的、沒有這個頻道，
  媒體鍵都是套件原本的切換，開了 Activity 後的下一次非 idle `publish` 才裝上；服務重建後到下一次非 idle
  `publish` 之前也一樣。
- Android 的 `MainActivity` 繼承 `AudioServiceActivity`（與 audio_service 的服務共用 `FlutterEngine`），
  下面的覆寫**沒有自動閘門，改動後要在 Android 模擬器實機驗**：
  - `provideFlutterEngine`：audio_service 0.18.19 的 `AudioServicePlugin.getFlutterEngine` 以
    `DartEntrypoint.createDefault()` 啟動引擎、不帶 intent 的 `dart_entrypoint_args`，原樣用的話
    `--fmp-dev-plugin` 在 Android 失效。覆寫成快取裡沒有引擎時自己建、帶 `getDartEntrypointArgs()`
    啟動，放進 `FlutterEngineCache`（鍵 `AudioServicePlugin.getFlutterEngineId()`）。升級
    audio_service 時重看它的 `getFlutterEngine` 有沒有改。
  - `popSystemNavigator`：Flutter 預設在根 route 沒得 pop 時 `finish()`，返回鍵直接結束 App；覆寫成
    `moveTaskToBack(true)` 並回 `true`，App 退到背景、Activity 與引擎都留著。
  - `setFrameworkHandlesBack` 一律以 `true` 交給父類別，`onCreate` 也先登記一次：返回鍵一律交給 Flutter，
    上一條才走得到。Android 16 起 targetSdk 36（`flutter.targetSdkVersion`）預設啟用 predictive back，
    返回不再經 `onBackPressed`；Flutter 在沒得 pop 時（搜尋分頁）取消登記自己的 `OnBackInvokedCallback`
    交給系統，系統只對從桌面啟動的 task 退到背景（`ActivityClientController.shouldMoveTaskToBack`），
    adb、通知、別的 App 開的一律 `finish()`，`popSystemNavigator` 不會被呼叫（M2 驗收實測，2026-10-08）。
    代價是根 route 沒有系統的「回到桌面」預覽動畫。不用 manifest 的
    `enableOnBackInvokedCallback="false"`：官方文件寫的是暫時的退出。接回 audio_service 留著的引擎時
    Dart 端不重送返回的狀態，所以 `onCreate` 要自己登記。
  實機驗證：`--fmp-dev-plugin` 啟動後測試插件仍裝得上；以 adb 啟動（不是從桌面），在歷史頁按返回回到搜尋，
  在搜尋再按一次 App 退到背景，`logcat -b events` 沒有 `wm_finish_activity`，從桌面圖示回來時沒有新的
  `App started`、搜尋字與分頁都在；播放中按返回音樂繼續。

- 結束並重啟（`lib/platform/app_restart/`，M3 design §12.2）：`PlatformCapabilities.restartsItself`（Windows 真、Android 假），`AppPlatform.restarter`（`appRestarterProvider`）。重設資料與從備份還原用它，呼叫前先 `LogFile.flush`。
  - Windows（`WindowsAppRestarter`）：以 `Platform.resolvedExecutable` 脫離式啟動新行程，**只帶** `--fmp-restarted-from=<目前 pid>`（不沿用原本的命令列，例如 `--fmp-dev-plugin`），再 `exit(0)`；啟動失敗就不結束並把錯誤丟出。
    `windows/runner/main.cpp` 看到這個參數時先 `OpenProcess(SYNCHRONIZE)` 等舊行程結束（最多 10 秒），**再**建立單一實例的 mutex，否則新行程會被舊行程還握著的 mutex 擋掉。Dart 端的參數解析（`devPluginPath`）只認自己的參數，忽略它。
    閘門：`app_restart_test.dart` 的 `Windows`（假的 launcher：參數、先啟動再結束、啟動失敗不結束、前綴字串）、`platform_test.dart`。**`main.cpp` 的等待沒有自動閘門**（C++ 沒有單元測試）：改動後建置 Windows 並實機驗（重設或還原後視窗自己回來、log 有新的 `App started`）。
  - Android（`AndroidAppRestarter`）：沒有正規的「重啟自己」，先 `publish(NowPlaying.nothing)` 加 `dispose()` 收掉系統媒體工作階段與前景服務，再 `exit(0)`，由使用者再開（對話框寫明）。
    **為什麼不能只靠 `SystemNavigator.pop`**：它只結束 Activity；`MainActivity` 與 audio_service 共用的 `FlutterEngine`、前景服務讓行程活著。實測（2026-10-14，Android 模擬器）暫停播放（media session 還在）時按返回鍵回到桌面，
    行程 pid 不變，再開 App 只是把原本的 task 帶回前景（`am start` 回 "Activity not started, its current task has been brought to the front"），log 的 `App started` 沒有增加、`main()` 沒重跑；那樣 App 會拿著已被刪掉重建的資料庫繼續跑。
    `AndroidSystemMediaControls.dispose()` 要 `await` 平台介面的 `stopService`（`audio_service_platform_interface`）：`audio_service` 自己是在 `playbackState` 的監聽裡非同步呼叫它，
    緊接著 `exit(0)` 時平台還沒收到，`NO_CLEAR` 的媒體通知留在通知清單（2026-10-14 實測：改前重設後 `dumpsys notification` 還有一筆，改後播放中、暫停中都是 0 筆）。沒有自動閘門，改動後實機看 `dumpsys notification`。
    收掉工作階段丟錯也照樣 `exit`（`finally`）。閘門：`app_restart_test.dart` 的 `Android`（先收工作階段再結束、收不掉也結束、沒有媒體控制照常結束）、`platform_test.dart`。行程結束後通知消失、重開時 `main()` 重跑只能實機驗。

- 版本號、平台名稱與系統版本（`lib/platform/app_info/`，M3 design §12.1；`osVersion` 是組裝點給的 `Platform.operatingSystemVersion`，錯誤報告用）：`AppPlatform.appInfo`，Android 與 Windows 共用
  `PackageInfoAppInfo`（`package_info_plus`；Windows 端是 FFI 讀執行檔的 `ProductVersion`，沒有原生的 plugin registrant）。
  不是能力宣告：沒有畫面依它決定入口，只有能跑主 App 的平台有，`main()` 在 `runApp` 之前讀一次、以 `appInfoProvider`
  注入。`homeDirectory`（Windows 是 `USERPROFILE`，Android 為空：沙盒路徑不含使用者名稱）給畫面把資料目錄顯示成
  `~\…`（`homeRelativePath`）；`AppInfoReader.homeDirectory` 是同步的 getter，`main()` 在寫第一筆 log 之前就用它登記遮蔽（見「Log 與遮蔽」）。閘門：`platform_test.dart`（兩個平台的實作、平台名稱與家目錄，未驗證平台為空）、
  `app_info_test.dart`（以套件的 `setMockInitialValues` 讀版本）；真的版本號只能實機看（「關於」的版本列）。

- 開網址（`lib/platform/url_opener/`，ADR 0023 §決定 4）：`PlatformCapabilities.urlOpener`（Android、Windows），一個實作
  `UrlLauncherOpener`（`url_launcher`，`launchUrl(mode: LaunchMode.externalApplication)`：一律交給外部瀏覽器；開不了或
  `PlatformException` 回 `false`，不拋）。Android 11 起要在 `AndroidManifest.xml` 的 `<queries>` 宣告能開 https 的 intent。
  `url_launcher` 只准在平台層（lint `fmp_layer_imports` 的 `platformPackages`）。閘門：`url_launcher_opener_test.dart`（模式、
  失敗回 `false`）、`platform_test.dart`、`layer_imports_test.dart` 的 `test_platformPackageOutsidePlatform`／`test_ownerDirectoriesMayImport`、
  `android_manifest_test.dart` 的 https query（含變異案例）。真的開瀏覽器只能實機驗。
- 檔案對話框（`lib/platform/files/`）：`PlatformCapabilities.files`，Android 與 Windows 共用一個實作
  `FilePickerDialogs`（`file_picker` 13.x；Windows 端是 FFI，沒有原生的 plugin registrant）。有
  `pickFile(extension:)`（插件頁的「從檔案安裝」）與 `saveFile(name:, bytes:, mimeType:)`（診斷包與 log 檔的存檔：桌面是存檔對話框，
  Android 走 SAF 的建立文件；取消回 `null`）與 `pickDirectory()`（插件開發資料夾；回絕對路徑，取消回 `null`）。副檔名只是篩選：Android
  把它轉成 MIME（`MimeTypeMap`）交給 SAF，選到的內容由呼叫端照格式驗（插件安裝檔解析標頭）。閘門：
  `platform_test.dart` 的宣告與實作型別、`file_picker_dialogs_test.dart`（以假的 `FilePickerPlatform`：篩選是
  `FileType.custom` 加副檔名、讀出內容、存檔的檔名／內容／MIME、選資料夾、取消是 `null`）；系統對話框本身只能實機驗。
- 插件開發工具（M3 PR 16b，ADR 0025 §決定 7）：`PlatformCapabilities.pluginDevTools`，Windows 真、Android 假（讀任意目錄要 SAF，
  另立 ADR）；依賴 `files` 的 `pickDirectory`。Debug 頁的「插件開發」區塊與 `PluginDevelopment` 的載入都看它。閘門：
  `platform_test.dart`（Android 假、Windows 真、未驗證的平台假）、`debug_page_test.dart` 的 `the plugin development section`。
- 檔案分享（`lib/platform/share/`，ADR 0025 §決定 10，M3 design §12.4）：`PlatformCapabilities.shareFiles`（Android、Windows 真；Linux 不能分享檔案；
  Windows 10 1809 以前 `share_plus` 會拋錯，經提示顯示），一個實作 `SharePlusFileSharer`（`share_plus`，`SharePlus.instance.share` 從建構子注入）。
  `shareFiles` 回 `true`＝平台回報了分享的結果（完成或取消），回 `false`＝視窗開了但平台不回報（Windows 的 `DataTransferManager` 一開視窗就回
  `unavailable`、接收端之後才讀檔），呼叫端據此決定能不能馬上刪暫存檔（Android 的 `share_plus` 先把檔案複製到它的 `cacheDir/share_plus/`，
  那份留到下一次分享才清，在 App 的私有快取裡）。`share_plus`（含 `share_plus_*`）只准在平台層（lint `fmp_layer_imports` 的
  `platformPackages`）。閘門：`share_plus_file_sharer_test.dart`（檔案與 MIME、`true`／`false` 的對應、開不起來拋出）、`platform_test.dart`、
  `layer_imports_test.dart` 的 `test_platformPackageOutsidePlatform`。系統分享視窗本身只能實機驗。

- 登入 WebView（`lib/platform/login_webview/`，ADR 0029 §決定 9）：`PlatformCapabilities.loginWebView`（Android、
  Windows），一個實作 `InAppLoginWebView`（`flutter_inappwebview` 釘 6.2.0-beta.3，理由在 `pubspec.yaml`；Windows 要
  `windows/CMakeLists.txt` 的 STL1011 define 才建得起來）。介面只開頁、報「一頁載入完成」、讀 cookie、清全部 cookie、重建環境，
  完成與否由呼叫端判斷（見「帳號」）。
  - UA 由這一層決定，不由插件給：Android 是系統 WebView 的 UA 拿掉 `; wv`／`;wv`（`androidLoginUserAgent`，R1：桌面 UA
    與帶 `wv` 的都被 Google 擋），Windows 不設（WebView2 預設就能登入）。
  - Windows 的 WebView2 使用者資料在資料目錄的 `webview/`（`loginWebViewDirectoryName`；不給的話是程式旁的
    `fmp.exe.WebView2`，dev 與 prod 混在一起），環境第一次用到才建，`reset` 後重建（同一個目錄，登入狀態留著）。
    cookie 的讀刪也都經這個環境，否則讀到的是預設環境的。環境這一段（目錄位置、延後建立、`reset`、讀刪經同一個
    環境）沒有閘門：`login_webview_test.dart` 注入的是沒有環境的實作，review 時看；實機看資料目錄下有 `webview/`、程式旁沒有 `fmp.exe.WebView2`。
  - `cookies(hosts)` 只回問到的網址讀得到的（`getCookies`），同名時前面的網址優先。刪除只有 `clearAll`
    （`deleteAllCookies`）：Google 會把工作階段 cookie 寫到地區網域、分區（CHIPS）cookie 以網址刪不到，所以不以網址刪
    （ADR 0029 §決定 11 更正）；平台可能靜默失敗，由呼叫端用 `cookies` 確認。
  - 閘門：`login_webview_test.dart`（UA 三種、只回問到的網址、`clearAll`）、`platform_test.dart`。cookie 真的刪掉只能
    實機驗（登出後以名稱檢查）。
  - Linux 沒有登入 WebView（ADR 0012 §決定 8）：App 直接依賴本機的 `packages/flutter_inappwebview_linux_stub`（純 Dart、
    什麼都不登記），Flutter 選它而不選套件預設、要裝 WPE WebKit 才建得起來的 `flutter_inappwebview_linux`。閘門：
    `webview_stub_test.dart`（`.flutter-plugins-dependencies` 的 Linux、macOS 解析、
    `linux/flutter/generated_plugins.cmake`、`macos/Flutter/GeneratedPluginRegistrant.swift`）。
  - macOS 同樣沒有登入 WebView：`flutter_inappwebview_macos` 1.2.0-beta.3 在目前的 Xcode 編不過，改依賴本機的
    `packages/flutter_inappwebview_macos_stub`（作法同 Linux），macOS 的 WebView 在 macOS 平台任務決定。

閘門：`test/platform/platform_test.dart` 以注入的平台值逐平台核對宣告與實作（未驗證
平台必須全部為沒有；含 Android 與 Windows 系統媒體控制初始化失敗時宣告為沒有）；lint `fmp_platform_checks` 擋
`lib/platform/` 以外的平台判斷。
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
- `tracks`（曲目顯示資料，鍵是 `TrackKey` 的字面輸出）、`queue_entries`、`player_state` 是 schema v4
  （design §3.1、§3.2）。`queue_entries.track_key` 以外鍵參照 `tracks`、`ON DELETE RESTRICT`：被佇列
  參照的曲目刪不掉，孤兒清理（`TracksRepository.deleteOrphans`，啟動維護清單）只刪沒人參照的列，
  之後加表的 PR（下載紀錄、匹配結果）各自把自己加進那個查詢；`play_history`、`playlist_entries` 已在裡面（見下一條與 `playlists` 一條）。寫入曲目用
  `ON CONFLICT DO UPDATE`（`TracksRepository.upsert`），不用 REPLACE（REPLACE 會先刪再插，撞上 `RESTRICT`；沒有直接的閘門，review 時看）。`queue_entries` 的主鍵是位置，
  位移時先改成負值再改回，所以那張表不能加 `position >= 0` 的檢查。`player_state` 單列，音量與
  靜音隨佇列存在這裡、不是設定；隨機排列存成每個位置的名次（`shuffle_rank`），不存排列本身。`queue_entries.track_key`
  有索引，否則孤兒清理每刪一列掃一次佇列（一萬孤兒約 9 秒，有索引約 14 ms）；閘門：`migration_test.dart`
  的 `indexes queue_entries.track_key`（升級來的與全新建的兩例，漏了 `m.create` 時升級驗證與該例會紅）。
  閘門：`queue_repository_test.dart`（`RESTRICT` 與孤兒、差量編輯的隨機序列、`a write is one transaction`、
  `stored format`、一萬首整份取代的耗時）、`migration_test.dart` 的 v3→v4 三例。
- `player_state` 的 Mix 五欄是 schema v13（M3 PR 19）：`mode`（空或 `queue`＝一般佇列，`mix`；字串在 `PlayerModeConverter`）、
  `mix_plugin_id`、`mix_id`、`mix_title`、`mix_cursor`。讀回時 `mode = mix` 而身分欄位缺任何一個（`mix_cursor` 除外，空＝這個
  Mix 沒有更多）就當一般佇列，不猜。臨時播放與直播不持久化，所以沒有它們的 `mode`。閘門：`migration_test.dart` 的
  `migration from v12 to v13 keeps the stored queue state`（舊列的值原樣、新欄位是空）與 `migration from v$from to v13 adds the
  mix columns`（每個舊版升級、全新建的資料庫各一例）、`queue_store_test.dart` 的 `a mix` 群組
  （`a stored mode of queue, or no mode at all…`、`a stored mix with a missing field…`）。
- `tracks` 的分 P 兩欄是 schema v14（M3 PR 20）：`part_index`（分 P 的序號，從 1 起）與 `parent_title`（影片標題），都可空，
  只有分 P 曲目有值；分 P 曲目的 `title` 是分 P 的標題，顯示用 `TrackInfo.displayTitle`（兩欄都有時是「影片標題 · P2 分 P 標題」，
  否則是 `title`）。搜尋結果的 `partCount` 只在記憶體，不存。曲目鍵照舊含 cid（ADR 0005），所以每個分 P 是一列。M5 匯入時舊的
  `pageNum` 對應 `part_index`、`parentTitle` 對應 `parent_title`。閘門：`migration_test.dart` 的 `migration from v13 to v14 keeps the
  stored tracks`（舊列原樣、新欄位是空）與 `migration from v$from to v14 adds the part columns`（每個舊版升級、全新建的資料庫各一例）、
  `queue_repository_test.dart` 的 `stored format`（欄位名與值）與 `reads back the queue…`（含分 P 曲目）、`play_history_repository_test.dart` 的
  `a part keeps its index and the video title`、`queue_store_test.dart` 的 `brings back a multi-part track…`。
- `play_history` 是 schema v5（design §3.2、§7.8）：一次播放一列（`id` 自增、`track_key` 外鍵 `tracks`
  `ON DELETE RESTRICT`、`played_at` UTC epoch 毫秒），同一首聽兩次是兩列。孤兒的定義是「沒有被佇列也沒有被
  播放歷史參照」：`TracksRepository.deleteOrphans` 與啟動維護的 `orphan-tracks` 都排除歷史參照的曲目；清除歷史
  之後那些曲目才成為孤兒。`track_key` 與 `played_at` 各有索引（`play_history_track_key`：同 `queue_entries`，
  `RESTRICT` 的檢查靠它；`play_history_played_at`：倒序分頁）。`PlayHistoryRepository.record` 一個 transaction
  做 upsert 曲目、插入、裁掉超過保留筆數的最舊列（依 `played_at`、同刻依 `id`）；讀是依
  `played_at`、`id` 倒序的 `LIMIT/OFFSET` 分頁，一萬筆的第一頁與最後一頁各約 1–2 毫秒。閘門：
  `play_history_repository_test.dart`（順序與分頁、刪一筆只刪那一筆、清除、保留筆數的邊界與 `trimTo`、`RESTRICT`
  與外鍵、`orphan cleanup keeps tracks the history refers to`、`stored format`、`the first page of ten thousand
  entries…`）、`migration_test.dart` 的 v4→v5 與 `migration from v<N> to v5 creates play_history…`（v1–v4 各一例：
  表、兩個索引、`RESTRICT`）、`a new database has play_history and its two indexes`。

- `layout_state` 是 schema v6（design §3.4）：依裝置記住的版面狀態，單列（`player_tab`：播放頁右欄上次選的分頁，
  `lyrics`／`queue`／`details` 寫死在 `PlayerTabConverter`；`panel_expanded`、`panel_width`：右側「正在播放」面板的展開與寬度，
  M2 PR 19 接上，欄位在 v6 就建好、沒有再升 schema）。欄位為空＝沒記過；`panel_width` 在資料庫只擋明顯的壞值（> 1600），實際範圍讀取時
  依視窗夾取。不屬於任何設定組，M4 的備份不收它：設定包含在備份裡，還原到另一台裝置時不該帶來這台的面板
  寬度。`LayoutStateRepository` 讀寫這三欄，`write` 沒給（`null`）的欄位不動。閘門：`layout_state_repository_test.dart`
  （`stored format`（含面板的布林與 dp）、不認得的字串拋錯、`write` 沒給的欄位不動（含 `a write only changes the fields it is given`）、`watch`、`reads back the panel fields`）、`migration_test.dart` 的 v5→v6
  （既有表的使用者值不變）與 `migration from v<N> to v6 creates layout_state…`（v1–v5 各一例：單列 CHECK、
  寬度 > 1600 寫不進去）、`a new database has layout_state with its checks`。

- `installed_plugins` 的 `enabled`、`source_index_url`、`checks_json` 與 `plugin_indexes` 是 schema v7（ADR 0030
  §決定 6、7）。`enabled` 預設真，升級前裝好的插件仍啟用；更新（`PluginRepository.install` 的 upsert）不動
  `enabled`，停用的插件更新後仍停用，`source_index_url` 與 `checks_json` 則每次安裝都以傳入的值覆蓋（新版本的
  檢查案例驗證不過時，舊版本的不留）。閘門：
  `migration_test.dart` 的 v6→v7 資料完整性與 `migration from v<N> to v7 adds the plugin lifecycle schema`
  （v1–v6 各一例）與 `a new database has the plugin lifecycle schema`、`plugin_repository_test.dart` 的
  `enabled and index source`、`custom indexes`。
- `accounts` 與 `source_settings` 是 schema v8（ADR 0029 §決定 6）：帳號的非機密顯示資訊與每音源設定，主鍵
  都是插件 id，**沒有外鍵到 `installed_plugins`**（插件移除後的清理由 `PluginInstaller.remove` 做）。是否登入只看
  `CredentialStore`，`accounts` 不存「已登入」。新表升級後是空的，其他表的值不動。閘門：`migration_test.dart` 的
  v7→v8 資料完整性與 `migration from v<N> to v8 adds the account schema`（v1–v7 各一例）、
  `a new database has the account schema`、`account_repository_test.dart`（含 `stored format…`）。移除插件時
  兩張表都清掉的閘門是 `plugin_installer_test.dart` 的 `removing` 群組。
- `developer_settings` 是 schema v9（ADR 0025 §決定 1、M3 design §3.3）：「開發者」組，單列、四欄全可空，一次建好
  （`plugin_dev_folder` 給插件開發工具，`report_reminder_dismissed` 給錯誤詳細頁）。`log_level` 存 `debug`／`info`
  （與 log 檔的層級字串相同，寫在 `LogLevelSettingConverter`）。新表升級後是空的。閘門：`migration_test.dart` 的 v8→v9
  資料完整性與 `migration from v<N> to v9 adds the developer settings`（v1–v8 各一例：單列、四欄為空）、`a new database
  has the developer settings`、`developer_settings_repository_test.dart`（`stored format`、只寫給的欄位、`clear`）。
- `installed_plugins.from_dev_folder` 是 schema v10（M3 PR 16b，插件開發 design §3.4）：真＝這一列是插件開發工具為了
  `plugin_storage` 的外鍵補的，不是使用者裝的；預設假，升級前的列都是假。存在資料庫而不是記憶體集合：App 在開著開發資料夾時
  被結束，下次啟動才分得出哪一列是補的。`PluginDevelopment` 每次套用資料夾（含啟動、資料夾為 `null`）時刪掉不屬於資料夾的
  標記列（storage 經外鍵一起刪），所以殘留列在**下一次啟動**清掉；`PluginRegistry.build` 略過標記列。
  `PluginRepository.install` 一律寫假（開發中被正式安裝的插件，那一列轉成已安裝的列，卸載時不會被刪）；
  `putDevFolderRow` 遇到已安裝的列一個欄位都不動、回傳假。閘門：`migration_test.dart` 的 v9→v10 資料完整性與
  `a new database defaults from_dev_folder to false`、`plugin_repository_test.dart` 的 `development folder rows`
  （只刪標記列、`install` 轉成已安裝）、`plugin_development_test.dart`（殘留列刪除且已安裝的列與 storage 留下）。
- `scheduler_runs` 是 schema v11（ADR 0017 §決定 2、M3 design §3.1）：排程器的上次成功時間，`job_id` 為主鍵、`last_success_at` 為
  UTC epoch 毫秒；不建外鍵到 `installed_plugins`（工作 id 只是字串）。新表升級後是空的＝所有工作視為從沒成功過。
  閘門：`migration_test.dart` 的 v10→v11 資料完整性（使用者設定過的值不變）與 `migration from v<N> to v11 adds scheduler_runs`
  （v1–v10 各一例：主鍵、時間格式）、`a new database has scheduler_runs`。
- `radio_stations` 與 `network_settings.radio_status_interval_minutes` 是 schema v12（ADR 0031 §決定 1、M3 design §3.1）：電台清單
  （`plugin_id`＋`room_id` 唯一、`sort_order`、最後一次查到的 `live_status`／`live_title`／`status_checked_at`）。不建外鍵到
  `installed_plugins`：插件停用、移除後電台保留；`live_status` 只有 `live`／`offline`，**「查詢失敗」不存**（D10，只在記憶體，見 § 電台）。
  `RadioRepository.add` 在 transaction 裡先查重再接在 `max(sort_order)` 後面，重複回 `false`（不用 `insertOrIgnore`：它不說有沒有寫）；
  `reorder` 整批重寫 `sort_order`。間隔欄位的語意見 § 設定的「網路」組。
  閘門：`migration_test.dart` 的 v11→v12 資料完整性（使用者設定過的快取上限不變、新欄位是空的）與 `migration from v<N> to v12 adds
  radio_stations…`（v1–v11 各一例：狀態字串、毫秒時間、唯一鍵）、`radio_repository_test.dart`（含 `stored format`）、
  `network_settings_repository_test.dart` 的 `radio status interval`。

- `playlists` 與 `playlist_entries` 是 schema v15（ADR 0033 §決定 1、M4 design §3.1，PR 1）：`playlists.kind` 只有 `local`／`imported`／`mix`
  （字串在 `PlaylistKindConverter`）；Mix 三欄（`mix_plugin_id`、`mix_seed_source_id`、`mix_seed_cid`）靠表級 CHECK：`mix` 時前兩欄非空，否則三欄都空。
  `playlist_entries.playlist_id` 連帶刪除、`track_key` 是 `RESTRICT`（有索引 `playlist_entries_track_key`，理由同 `queue_entries`），
  順序是（`position`, `id`）：`position` 不唯一，`removeEntries` 留下空洞、`moveEntries` 整批重寫；同一首曲目可以在同一份歌單出現多次。
  遠端三欄（`remote_item_id`、`unavailable`、`seen_generation`）只有匯入歌單用。`PlaylistRepository.addTracks` 以 `TracksRepository.upsert` 寫曲目。
  閘門：`migration_test.dart` 的 `migration from v14 to v15 keeps existing data`、`migration from v<N> to v15 adds the playlist tables`
  （v1–v14 各一例；`migrateAndValidate` 比對 CHECK、外鍵動作與索引欄位）與 `a new database has the playlist tables`、
  `playlist_repository_test.dart`（CHECK、連帶刪除、`RESTRICT`、順序重寫、`stored format`）、`queue_repository_test.dart` 的 `a track in a playlist is not an orphan`。

- `playlist_remote` 是 schema v16（ADR 0033 §決定 1、M4 design §3.1，PR 8a）：只有 `imported` 歌單有。`playlist_id` 是主鍵並連帶刪除，（`plugin_id`,
  `remote_id`）唯一（重新匯入同一張靠它認出），沒有外鍵到 `installed_plugins`；`writable` 與三個 `*_overridden` 預設假、`refresh_generation`
  預設 0、`status` 預設 `active`（`active`／`sourceGone`／`authRequired`，字串在 `PlaylistRemoteStatusConverter`）、`last_result` 空＝還沒刷新完過
  （`complete`／`partial`／`failed`，`PlaylistRefreshResultConverter`）、`last_refreshed_at` 只在 `complete` 或 `partial` 時寫。寫入口是
  `PlaylistRepository.createImported`（兩張表一個 transaction）與 `beginRefresh` 回傳的 `PlaylistRefreshSession`（行為見 § 音樂庫）。
  閘門：`migration_test.dart` 的 `migration from v15 to v16 keeps existing data`、`migration from v<N> to v16 adds playlist_remote`（v1–v15 各一例：
  預設值與狀態字串、唯一鍵、連帶刪除）與 `a new database has playlist_remote`、`playlist_remote_repository_test.dart`。

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
  （`cacheDirectoryProvider`，`lib/platform/cache_directory/`）、flavor（`appFlavorProvider`，`lib/core/core_providers.dart`）
  與版本號（`appInfoProvider`，`lib/platform/app_info/`）只由 `main()` 以
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
  追加 header 與鍵名、以 `setMediaCdns` 設媒體 CDN；憑證的值與帳號的 `userId` 由 `CredentialStore` 以 `registerSecret` 逐值登記，見「帳號」；
  全是數字的已知值只在數字邊界換（`aid=9123456780` 不被 id `12345678` 切碎）。
  閘門 `redactor_test.dart` 的 `known credential values`）。門面在交給 talker 之前就把 error、stackTrace 轉成遮蔽過的字串，原始物件不進
  歷史。閘門：`test/core/logging/log_test.dart`（假憑證經訊息、error、stackTrace、深層
  欄位寫入後，記憶體歷史與 log 檔都沒有原值）、`test/core/redaction/redactor_test.dart`。
  網路紀錄經門面寫入，閘門見「網路」；診斷包的遮蔽測試見「診斷包」。
- 使用者的家目錄由 `Redactor.registerHomeDirectory` 登記，輸出裡出現就換成 `~`（M3 design §12.4：資料目錄的路徑含使用者名稱，log 檔與診斷包因此是 `~\…`）。
  分隔符 `\`、`/` 與 JSON 跳脫過的 `\\` 都算，不分大小寫，只換整段目錄名稱（`C:\Users\al` 不吃掉 `C:\Users\alice`，也不吃 `C:\Users\al.b`）；
  `null`、空字串與去掉結尾分隔符後短於 4 個字元的路徑不登記。**`main()` 必須在寫 `App started` 之前登記**（用 `AppInfoReader.homeDirectory`）：順序在 `main()` 裡，
  **沒有自動閘門**（`main()` 沒有測試），改動 `main()` 時 review 看，實機看 log 檔的 `App started` 是 `~\…`。閘門：`redactor_test.dart` 的 `home directory`
  （三種寫法、整段目錄名稱、結尾分隔符、不登記的路徑、再次登記取代）、`log_test.dart` 的 `the home directory is ~ in the history and the log file`。
  登記之前（更早的版本）寫進 log 檔的行在本機不改寫（過了 7 天保留期限自然消失）；送出裝置的診斷包與「匯出 log 檔」以現在的遮蔽函式重遮（`redactLogLines`，見「診斷包」）。
- 遮蔽本身拋錯時，門面把那筆換成只有層級與失敗型別的 `Redaction failed` 紀錄，不退回
  原文。閘門：`log_test.dart` 的 `a record that cannot be redacted`。
- log 檔：資料目錄的 `logs/fmp.jsonl`，JSON Lines，單檔 2MB，輪替成 `fmp.1.jsonl`、
  `fmp.2.jsonl`，共 3 個。欄位名稱與層級字串是持久化格式（Debug 頁的「含之前的紀錄」讀舊檔）。
  閘門：`test/core/logging/log_record_test.dart` 的 `stored format`、`log_file_test.dart`。
- 刪檔與讀檔都排在 `LogFile` 的寫入佇列上，不從外面動 `logs/`：`Log.clear()`（清記憶體歷史加 `LogFile.clear()`）刪掉全部 log 檔，
  清除之前排入的行先寫完再刪、`clear()` 之後寫的行不受影響（寫入以「批」排隊，`clear()` 封起目前這一批）；`LogFile.readStored()`
  在 isolate 讀回檔案，最多 `logReadLimitBytes`（6MB，剛好是 3 個 2MB 檔），從最新的檔往回讀，放不下的檔只取尾端（被切開的第一行是半截 JSON，
  當壞行略過）。`Log.changes` 在每筆進歷史與清除時同步發一次（Debug 頁靠它更新）。閘門：`log_file_test.dart` 的 `clear`、
  `readStored` 群組，`log_test.dart` 的 `clear`（含 `is queued behind the writes in flight`）。這次執行寫的每一筆在記憶體與檔案裡
  逐字相同（Debug 頁合併去重靠它）：閘門 `log_test.dart` 的 `the history and the log file hold the same records`。
- 寫檔失敗不拋出、不影響 App，次數與最後一個錯誤留在 `LogFile.failureCount`／
  `lastFailure`。沒有資料目錄的平台只有記憶體歷史。
- 層級：建置的預設是 debug build 為 `debug`、profile／release 為 `info`（`buildDefaultLogLevel`，ADR 0011 §決定 2），
  `main()` 以它建門面；之後跟著「開發者」組的生效層級（見「設定」）：`FmpApp` 監看 `developerProvider`、把
  `Log.minimumLevel` 改成生效的層級（改了記一筆 `Log level applied`）。閘門：`fmp_app_test.dart` 的 `the log level setting
  decides whether debug records reach the history`（建置固定為 release：預設 info、debug 進歷史、改回 info 與關掉開發者模式
  後不進）與 `in a debug build debug records reach the history by default, also with developer mode off`。console 只在
  debug build。
  未捕捉的錯誤（`FlutterError.onError`、`PlatformDispatcher.onError`）經門面以 `error`
  寫入；是 `AppError` 的改走 `log.report`（才寫得出原因），以 `level` 參數固定為
  `error`，不依 `expected`（沒人接就是沒處理）。`level` 只給這裡用，處理過的錯誤不傳。
  `main()` 在解析資料目錄之後才接上，之前的錯誤走 Flutter 預設處理。閘門：
  `test/core/logging/uncaught_errors_test.dart`（預期內的 `AppError` 未捕捉仍是 `error`，
  原因經遮蔽寫出）。
- 媒體 CDN 的名單刻意不遮 B 站的 `deadline`（到期的 unix 秒，公開的時間戳、不是憑證）：簽名
  與帶身分的參數（`e`、`upsig`、`uparams`、`mid`、`oi`、`trid`、`buvid`、`hdnts`）照樣拿掉，
  網址仍然不能用；fixture 留著期限，契約的 `expiresAtPattern` 才核對得了 `expiresAt`（見
  「插件」）。閘門：`redactor_test.dart` 的 `strips signed parameters and keeps the others`
  （`deadline` 留著、其他參數拿掉，含 Akamai 的 `hdnts=exp=…~hmac=…`）。
- 媒體 CDN 的名單同樣不遮 YouTube `googlevideo.com` 的 `expire`（到期的 unix 秒）：`sig`、`lsig`、
  `ip` 等照樣拿掉。閘門：`redactor_test.dart` 的 `strips signed parameters and keeps the others`
  的 googlevideo 案例。
- 保留期限（`LogFile.deleteExpired`）：輪替出來的 `fmp.N.jsonl` 最後修改超過 7 天
  就刪，目前寫入的 `fmp.jsonl` 不動，與大小輪替並存，不做設定項。只動 `logs/` 這一層
  符合檔名的檔案。排在 `LogFile` 的寫入佇列裡，不和輪替的改名交錯；失敗交給呼叫端，
  之後的寫入照常。由啟動維護清單的 `log-retention` 項目呼叫。閘門：`log_file_test.dart`
  的 `retention` 群組。
- 啟動維護清單：`lib/app/startup_maintenance.dart` 的
  `startupMaintenanceTasksProvider`（有序清單，新項目加在那裡）。`FmpApp` 在第一幀之後
  （`initState` 排的 post-frame callback，每次掛上只一次；`main()` 只掛一次）依序跑；
  每項各自 try，失敗經 `log.report` 進錯誤歷史後接著跑下一項，不重試；每項跑完寫一筆
  tag `maintenance` 的 log（`id`、`outcome`）。清單目前依序是 `log-retention`、`diagnostics-temp`（刪資料目錄底下殘留的診斷包分享暫存 `diagnostics-tmp/`，見「診斷包」）、`orphan-tracks`
  （刪沒有被佇列、播放歷史參照的 `tracks` 列，記 `Deleted orphan tracks` 與 `count`；閘門：
  `startup_maintenance_test.dart` 的 `orphan-tracks…`、`play_history_repository_test.dart` 的 `orphan cleanup keeps tracks…`）。項目一個接一個 await，卡住的項目會擋住
  後面的，所以項目只放有限的本機工作。閘門：`test/app/startup_maintenance_test.dart`
  （畫過第一幀才跑、重建不重跑、失敗隔離、預設清單的 `log-retention`、`diagnostics-temp`、`orphan-tracks`）。不跳提示（清單
  拿不到 `Toaster`）、不放空的登記點、週期性工作不放這裡（放 § 排程器）沒有閘門，
  review 時看。

## 錯誤

`lib/core/errors/`（ADR 0013）。怎麼加錯誤類型或 i18n key、音源怎麼寫對應表：
`.trellis/spec/app/errors/index.md`。

- 音源邊界以上只看得到 `AppError`：音源把自己的錯誤碼轉好，其他例外在邊界以
  `AppError.wrap` 包成 `UnexpectedError`。閘門：`plugin_runtime_test.dart` 的 `errors` 群組（結構化錯誤轉成該類別、
  其他拋出的值是 `UnexpectedError`）、插件契約執行器（`contract_runner_test.dart`：失敗案例比 `AppError` 類別）。
- `AppError` 沒有可以直接顯示的字串：使用者訊息只有 `messageKey`／`messageArgs`；
  `messageArgs` 是 `Map<ErrorMessageArg, int>`，放不進插件或伺服器的文字；音源名稱由呈現層
  以 `pluginId` 查。原始 error 與 stackTrace 是函式庫私有欄位，`toString()` 不含它們。閘門：
  `test/core/errors/app_error_surface_test.dart`（列出全部公開成員；型別參數裡的
  `String`／`Object`／`dynamic` 也算，含變異案例）、`app_error_test.dart` 的 `toString`。
- 被處理的錯誤一律經 `log.report(...)`（`report_error.dart`，`app_error.dart` 的 `part`）
  寫進錯誤歷史，那是唯一讀得到原始 error 的路徑。閘門：`report_error_test.dart`
  驗層級、欄位與遮蔽；「處理了卻沒 report」沒有閘門，review 時看。
- 錯誤報告（`error_report.dart`，ADR 0023 §決定 4）：`ErrorReport.fromRecord` 由 `log.report` 寫的那筆已遮蔽的 `LogRecord` 組成
  （`Log.write`／`report` 回傳寫進歷史的那筆，被層級濾掉時是 `null`），不另存報告 id，也沒有第二條路拿到原始 error 或 stackTrace。
  請求摘要以 `fields.networkRecordId` 在**傳入的**記憶體歷史找 tag `network`、`id` 相同的那筆（還要音源相同、時間不晚於錯誤）：
  `networkRecordId` 只在同一次執行唯一，所以前幾次執行的紀錄（log 檔讀回）呼叫端傳空清單，報告就沒有請求摘要；詳細頁以「紀錄是
  不是記憶體歷史裡的那個物件」判斷，所以 Debug 頁的 `mergeLogRecords` 對兩邊都有的那筆留記憶體的物件。組報告時每個文字欄位
  （含版本字串等外來欄位）再過一次 `Redactor`（之後才登記的憑證值；頁面顯示的欄位與 Markdown 是同一份），整份 Markdown 輸出前
  再遮一次。code block 用 `~` 的 fence：`bug_report.yml` 的 `render: markdown` 把欄位包進反引號的 code block，內層用反引號會
  提早結束它。閘門：`error_report_test.dart`（欄位、有無請求、撞號與前次執行不誤配、Markdown 格式與 `~` fence、假 cookie／token／
  簽名網址／query 不出現在 Markdown，含「紀錄沒遮乾淨時最後一道擋住」與「組報告時每個欄位再遮一次」）、`report_error_test.dart` 的
  `returns the record it wrote…`、`debug_log_state_test.dart` 的 `a record in both lists is the memory instance`。
- 重試只有網路層一層，用 `retry_policy.dart` 的純函數；Riverpod 的重試已關（見
  「Riverpod」）。閘門：`retry_policy_test.dart`；網路層的重試見「網路」。
- 禁止空 catch 與靜默吞錯。閘門：lint `fmp_no_empty_catch`（只擋空的本體；catch 了
  只 `return null` 之類的吞錯沒有閘門）。
- `report` 的欄位名稱與 `type` 的值（寫死的類別名，不是 `runtimeType`）進 log 檔，
  是持久化格式。閘門：`report_error_test.dart` 的 `writes the structured fields`。

## 網路

`lib/core/network/`（ADR 0012 §決定 1–2、ADR 0013 §決定 2、4）。怎麼發請求、改攔截器、
寫測試：`.trellis/spec/app/network/index.md`。網路層自己的測試在 `test/core/network/`。

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
  冪等請求、次數上限、`Retry-After`、取消不重試）。語意冪等的 POST（innertube 查詢等）由
  插件在請求標 `idempotent: true`（`false` 則連 GET 都不重試），只影響重試，不影響認證、限流、
  網路紀錄（ADR 0028 §決定 2）。閘門：`retry` 群組的 `a POST marked idempotent…`、
  `a GET marked not idempotent…`；`plugin_runtime_test.dart` 的 `http.request passes idempotent…`。
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
  不重試、不 report。閘門：`source_http_client_test.dart` 的 `a cancelled request is not retried`、
  `requests that were not sent or were cancelled report nothing`。
- cookie：每插件一個記憶體 jar，網路層不持久化。匿名 cookie（B 站 `buvid`）要跨重啟
  時，由插件從回應的 `Set-Cookie` 取值寫進自己的 storage（`plugin_storage`，ADR 0014
  §決定 5），下次以 `Cookie` header 帶上（cookie 管理會併進 jar 的 cookie，同名以 header 為準）。合併這半條的閘門：
  `auth_test.dart` 的 `Cookie merging` 群組（`the plugin header wins over the jar when nothing is attached`、
  `with only the jar, the jar is sent`）；插件自己存取 `buvid` 在插件 repo，本 repo 沒有閘門。
- 網路紀錄：tag `network`，每次送出一筆，欄位 `id`、`pluginId`、`client`（`source`／
  `media`／`host`，`host` 的 `pluginId` 是空字串）、`method`、`host`、`path`、`query`、`status`、`ms`、`bytes`、`error`、
  `credentials`、`retry`；不記 body。未登入而拒絕的 `required` 請求沒送出，也有一筆（沒有
  `status`、`ms`），`AuthRequired` 帶它的 id。失敗或狀態碼 ≥ 400 用 `warning`，其餘
  `info`（ADR 0025 §決定 4：release 的預設層級也看得到）。網址先整個遮過（`Log.redactUrl`）再拆成
  `host`、`path`、`query`，拆開後遮蔽函式認不出媒體 CDN 的簽名參數。欄位名稱與 `client` 的值是 log 檔的持久化格式（`network_log.dart`）；網路層
  產生的 `AppError` 帶那一筆的 `networkRecordId`。兩種 client 的工廠與宿主請求（`hostFetchProvider`，
  `lib/plugins/repository/plugin_downloader.dart`）共用一個 `NetworkRecordIds`（`networkRecordIdsProvider`），id 在同一次
  執行裡不重複。閘門：兩個 client 測試的 `network log` 群組（欄位逐一比對；query 裡的假憑證與 body 不出現在記憶體
  歷史與 log 檔；`media CDN signatures are redacted before the URL is split`）、`media_http_client_test.dart` 的 `no Cookie or Authorization…`（兩種
  client 的 id 接續）；provider 的接線沒有閘門，review 時看。
- 認證：請求宣告 `AuthRequirement`，攔截器只依 `decideAuth` 的表注入；認證來源是 `CredentialSource`
  （實作是 `CredentialStore`，見 § 帳號），回傳憑證材料（cookie 表與標頭），不回拼好的 `Cookie` 字串。
  attach 時把憑證的 cookie 併進請求自己的 `Cookie` header（同名憑證為準），再加憑證的標頭與請求的
  `authHeaders`；omit、refuse、`never`、已失效時 `authHeaders` 一個都不加，跨 host 的轉址也丟掉。閘門：
  `auth_test.dart`（三種標記 × 三種狀態、`Cookie` 三方合併、`authHeaders`）。
- 憑證的 cookie 不從 cookie jar 送出（ADR 0029 §決定 4）：cookie 管理併 jar 時，跳過請求 `Cookie` header 已有的
  名稱與該插件憑證的 cookie 名稱，不論這次有沒有帶憑證、憑證有沒有失效。閘門：`auth_test.dart` 的
  `credential cookies never come from the jar`（jar 先放同名 cookie：attach、開關關閉、`never`、已失效）。
- 登入期間 jar 不存回應的 `Set-Cookie`（ADR 0029 §決定 2）：`ScriptSourcePlugin` 跑 `login*` 匯出時包在
  `SourceHttpClient.withoutSavingCookies` 裡，範圍是整個 client（不分是哪一次插件呼叫，同 design §4.9 的理由），重疊時
  最後一個結束才恢復；回應的 header 照樣交給插件。閘門：`auth_test.dart` 的 `a login does not store its cookies`（之後的
  回應照存、重疊、失敗也恢復）、`script_source_plugin_test.dart` 的 `responses during a login export…`、
  `account_service_test.dart` 的 `after a real QR login, never and a switched-off preference carry no credential cookie`。
- `SourceResponse.credentialsAttached`（插件看到的 `HttpResponse.credentialsAttached`）只在這次送出的那一跳
  真的 attach 時為真；插件的「憑證無效」判定只能在它為真的回應上成立。閘門：`auth_test.dart`、
  `source_http_client_test.dart` 的 `credentialsAttached describes the hop…`。`authHeaders` 的名稱由
  `PluginHost` 加進 `Redactor` 的 header 名單（`plugin_runtime_test.dart` 的 `the authHeaders names join…`）。
- 網路狀態（`network_status.dart`，ADR 0016 §決定 6）：輸入只有平台層的介面變化與
  HTTP client 每次送出的結果（`RequestOutcomeSink`）。拿到回應不論狀態碼都是
  `responded`（被轉成 `RateLimited` 的 429 也是）；`NetworkError` 是失敗；沒送出的
  （網域不符、未登入的 `required`）、取消與其他錯誤不回報；每次重試、每一跳各算一次。
  播放後端的串流錯誤不是請求，不回報。任何回應都讓 `noInterface`、`unreachable` 回到
  `online`；失敗不改變 `noInterface`（介面消失前送出的請求晚一點才失敗）。回到前景時查到
  有介面不算「介面變化」，`unreachable` 留著。時間以 `clock` 讀，不開計時器。閘門：
  `network_status_test.dart`（轉換表逐列；fakeAsync 裡跑完後沒有待執行的計時器）、
  兩個 client 測試的 `network status` 群組。兩個工廠的 provider（`plugin_registry.dart`）與 `hostFetchProvider` 都
  接同一個 `NetworkStatusNotifier.report`；接線沒有閘門，review 時看。
- 網路狀態不擋使用者發起的請求，`noInterface` 也照送（ADR 0016 §決定 7 的更正）：
  Windows 的 `connectivity_plus` 只把 Network List Manager 判定「連得上網際網路」
  （NCSI）的連線算成有介面，在 proxy、VPN 後面會誤報 `noInterface`，送出去拿到回應才
  回得到 `online`。不在 `online` 時不發背景請求（§決定 6）：目前的背景請求只有啟動刷新（頁面打開時讀的插件 index 不算，是那一頁的內容），它等第一次 `online`
  （閘門見「帳號」的啟動刷新）；之後加的背景工作各自補閘門。使用者發起的那半條的閘門：`network_status_test.dart` 的 `a response`（`noInterface` 收到回應回到
  `online`）、`search_page_test.dart` 的 `offline` 群組（`noInterface` 仍送出搜尋）。
- Android 8 起背景收不到介面變化，`FmpApp` 在回到 `resumed` 時以 `recheckInterfaces`
  再查一次。閘門：`fmp_app_test.dart` 的
  `returning to the foreground checks the network interfaces again`。
- 媒體 header：媒體 client 的每一跳、交給播放後端的串流 headers，一律先經
  `mediaRequestHeaders`：只留 `Referer`、`User-Agent`、`Origin`、`Range`。閘門：
  `media_headers_test.dart`；後端確實經過它，見「播放」。

### 宿主自己的請求

`host_fetch.dart`（ADR 0030 §決定 5）：讀插件 index、下載插件檔與 `checks.json`。底層是媒體 client（規則不另寫一份）：
不帶憑證、沒有 cookie jar、只准 `https`、不准 user info、逾時與大小上限（index 1 MiB、插件檔 8 MiB、checks 256 KiB）。
差別只有兩個：允許網域是該網址自己的 host，**不含子網域**（`AllowedHosts(exact: true)`），轉址換 host 就失敗；
網路紀錄的 `client` 是 `host`，`pluginId` 欄位是空字串；請求丟出的 `AppError` 的 `pluginId` 是 `null`（不是 `''`：
呈現層會拿它去查「音源未安裝」）。內容先寫進每次不同的暫存目錄、讀完就刪。閘門：`test/core/network/host_fetch_test.dart`
（無憑證、只准 https、轉址到別的 host 與子網域都不發出、超過上限、不留暫存目錄、網路紀錄、`an error from a host request carries no plugin id`）；
`toaster_test.dart` 的 `an error without a plugin id never names an uninstalled source`、`allowed_hosts_test.dart`
的 `exact lists…`。

### 媒體 client

`media_http_client.dart`（ADR 0012 §決定 1、design §4.1）。測試在
`test/core/network/media_http_client_test.dart`，下面寫的群組都在這個檔。

- 每插件一個，`PluginRegistry` 在插件加入清單時（啟動載入、安裝、更新）以 manifest 的
  `allowedHosts` 建立，`mediaClient(pluginId)` 取得；插件被取代或清單釋放時關閉。閘門：
  `plugin_installer_test.dart` 的 `media clients` 群組（允許網域與 manifest 一致、更新後
  換成新網域、舊的關閉）。
- 每插件的那一個目前唯一的呼叫端是封面（宿主請求每次另建一個不屬於插件的，見上一節）：`artworkCacheManagerProvider(pluginId)`
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

## 帳號

`lib/plugins/accounts/`（ADR 0012、0029），畫面在 `lib/ui/accounts/`（見「介面」的帳號頁）。

- 憑證只有一個來源 `CredentialStore`：secure storage 的 `credentials.<插件 id>`（`LoginCredentials` 的 JSON）。
  記憶體只放讀進來的狀態，請求只讀記憶體；每個查詢都等 `ready`（啟動載入完成），所以啟動時的請求不會在憑證
  讀進來之前以匿名送出。是否登入只看它。啟動只讀 manifest 宣告 `login` 的已安裝插件加上有帳號列的（design §6.1）。
  閘門：`credential_store_test.dart` 的 `a plugin that does not declare login is not read`。
- 讀取失敗（含內容壞掉）時該插件為 `unreadable`：不帶、**不刪**，30 秒後重讀一次（一次性 `Timer`），重讀仍失敗就
  維持，不再排。啟動載入時帳號列與憑證不一致就刪掉多的那一邊並記 warning。載入、重讀與每個寫入（`save`、`delete`、`replace`、
  `recordRefresh`、`invalidate`）排成一條依序執行：重讀從 storage 拿到的舊值不能蓋掉期間的登出或重新登入（否則登出後又帶憑證）。閘門：
  `credential_store_test.dart`（`a read failure`，含 `… during the re-read …` 兩例；`loading at startup`）。
- 已失效（`accounts.status = invalidated`）的憑證保留、不帶，`fmp.credentials.get()` 也回 `null`，但它的 cookie 名稱
  照樣擋在 jar 之外。閘門：`credential_store_test.dart`、`plugin_runtime_test.dart` 的 `credentials`。
- 遮蔽：載入與寫入時把每個 cookie 值、`extra` 值與帳號列的 `userId` 登記到 `Redactor`，登出、換帳號與移除時取消；
  短於 `Redactor.minimumSecretLength` 的值略過（`registerSecret` 對它們會拋錯，而 B 站會一起回 `home_feed_column=5`）。
  `userId` 另外登記，因為網易雲、YouTube 的 id 不在 cookie 裡；只登記自己的 id，瀏覽的 UP 主、主播的 id 照留（除錯用得到）。
  閘門：`credential_store_test.dart` 的 `redaction` 與 `the account id`。
- 登出（`AccountService.logout`）：憑證 → 登入 WebView 的 cookie → `accounts` 列 → 該插件的記憶體 cookie jar；
  `source_settings` 保留。每一步可重複，失敗停在那一步。WebView 那一步只在平台有登入 WebView、插件（還在
  `installed_plugins`）的 manifest 宣告 `login.webView` 時做：`clearAll` 清登入 WebView 的全部 cookie，再讀
  `loginWebViewHosts`（`cookieHosts` 與登入頁 `url`），還讀得到就丟 `StateError`（訊息只有數量）。登入頁那一端也是登入狀態，
  不清的話下次一開就直接登入；Google 寫到地區網域的 cookie 與分區 cookie 以網址刪不到，所以清全部。移除插件走同一條
  （design §7.4 的順序：憑證 → WebView → 帳號列）。
  閘門：`credential_store_test.dart` 的 `logging out`、`account_service_test.dart` 的 `logging out clears the login web view`、
  `plugin_installer_test.dart` 的 `clears the login web view…`。
- 登入（`AccountService.login`，三種方式共用）：插件的 `loginVerify` 通過才寫入——先 secure storage、再帳號列
  （`active`、登入時間）、再登記遮蔽（`CredentialStore.save`）；驗證丟錯什麼都不寫，寫入失敗包成 `AppError`（登入失敗）。
  `loginVerify`／`loginRefresh` 呼叫前就把傳入憑證的值登記到遮蔽（失敗也不取消；短值同上略過），`loginRefresh` 回的新憑證
  也登記。閘門：`account_service_test.dart` 的 `login` 群組、`script_source_plugin_test.dart` 的 `loginVerify registers…`、
  `loginRefresh gives new credentials…`。
- QR 登入（`QrLogin`，`qr_login.dart`）：`loginQrStart` 之後每 2 秒 `loginQrPoll`，以一次性 `Timer` 接力（上一次回來才排
  下一次，不是週期計時器）；`scanned` 照常續輪詢、`expired` 停、`done` 交 `AccountService.login`；`start` 重新產生時舊的
  結果作廢；`dispose`（離開畫面）取消計時器，還在路上的輪詢回來後不再排。失敗經 `log.report`（tag `accounts`）後停在
  失敗狀態。閘門：`account_service_test.dart` 的 `QR login` 群組（fakeAsync，結束時沒有待執行的計時器）。
- 網頁登入（`WebLogin`，`web_login.dart`）：**完成只看 cookie、只看 `cookieHosts`**——每一頁載入完成就讀 `cookieHosts`
  的 cookie，`doneCookies` 都有值就完成，交出 `cookieHosts` 讀到的全部 cookie。不看網址（Android 登入後會先插入 Google 的
  提示頁，最後落在 `m.youtube.com`）；別的網域的同名 cookie 不算（Google 帳號的 `SID` 等在 `.google.com`，跳回 YouTube
  之前就有）。**跳轉卡住**：登入頁 `url` 讀得到的 cookie 已經有全部 `doneCookies`（登入頁那一端已經登入，R1 看到的情況），
  `cookieHosts` 卻 15 秒內沒齊；只看「`url` 有 cookie」會把還在輸入密碼的使用者當成卡住（登入頁一打開就有 cookie）。計時是
  一次性 `Timer`，到時再讀一次 cookie 才下結論。重試先拿掉 WebView、等那一幀畫完才 `LoginWebView.reset`（環境不能在
  WebView 還用著時丟掉），重試過還卡住就改請使用者重開 App。cookie 的值不進 log。閘門：`web_login_test.dart`（含
  fakeAsync 的計時、換掉的 WebView 的計時器不作用、離開時取消、log 掃描）。
- 貼上 cookie（`parseCookieText`，`cookie_text.dart`）：逐行判斷，`Cookie` 標頭（`name=value; …`，可帶 `Cookie:`）與
  Netscape `cookies.txt`（7 欄、tab 或被換成的空白；`#HttpOnly_` 開頭的是 cookie，其他 `#` 是註解）可以混著貼；讀不懂的
  行或片段略過，同名以後面的為準，值原樣保留。輸入的內容不進 log 與錯誤報告（對話框只 `log.report` 驗證的錯誤，
  `loginVerify` 之前值已登記遮蔽）。閘門：`cookie_text_test.dart`、`accounts_section_test.dart` 的 `pasting cookies…`
  （外殼的 log 不登記這些值，寫進去就會原樣出現）。
- 「以登入身分瀏覽與播放」讀 `source_settings.browse_as_logged_in`，空就是 manifest 的 `login.browseAsLoggedInDefault`
  （沒宣告是開）：`ScriptPluginLoader` 載入成功時把它交給 `CredentialStore.setBrowseAsLoggedInDefault`，請求都來自載入了的
  插件。帳號頁的開關以同一條規則顯示，寫入經 `AccountService.setBrowseAsLoggedIn`。閘門：`account_service_test.dart` 的
  `browse as logged in` 群組。
- 失效與刷新（`AccountGuard`，`account_guard.dart`，design §6.5）：判定在插件，插件丟 `CredentialInvalid` 時由守衛在**插件呼叫層**
  處理，不在 dio 的攔截器（判定在 JS 內）。`ScriptSourcePlugin` 的能力呼叫（`search`、`resolveStream`，`_invoke` 一處）
  都經它；`login*` 匯出不經（它們自己負責憑證）。只有 `CredentialInvalid` 觸發，而且呼叫開始時要有可用憑證；網路錯誤、
  限流、風控不觸發。流程：同一插件單飛刷新（共用 `Future`）；呼叫開始時的憑證和現在的不同＝已被別的呼叫刷新過，直接重跑，
  不再刷新。宣告 `refresh`：`loginRefresh(目前憑證)` 拿到新憑證就寫入（`CredentialStore.replace`，`refreshed`）並**重跑原呼叫
  一次**（新的呼叫讀到新憑證）；回 `null` 或丟 `CredentialInvalid` 就標 `invalidated`（`CredentialStore.invalidate`，保留憑證、
  不再帶）；沒宣告 `refresh` 直接標。重跑又被拒也標，不再重跑。刷新時的其他錯誤（網路、限流）不標失效，記 `failed` 並丟出
  那個錯誤。併進進行中的啟動刷新而它回 `null`（`unchanged`）時，被拒的那次照樣標失效。寫入（`replace`、`recordRefresh`、
  `invalidate`）只對刷新或被拒的那組憑證做：`CredentialStore` 以記憶體裡現在的憑證比對，刷新期間登出（憑證已刪、帳號列還在）
  或重新登入時那次的結果丟掉，不復活、不蓋掉、不標失效。每次從 `active` 轉成 `invalidated` 發一次 `AccountInvalidated`
  （`accountInvalidationsProvider`），外殼以 `Toaster.credentialInvalidated` 提示一次「{音源}的登入已失效」附「登入」（到設定頁的
  帳號區塊）；它佔住 `CredentialInvalid`＋該音源的錯誤去重鍵，同一個失敗接著從搜尋、播放以 `Toaster.error` 送來的錯誤提示被
  去重（仍寫錯誤歷史），畫面上只留附「登入」的那則（ADR 0013 §決定 5）。重新登入回到 `active` 後下一次失效再提示。閘門：
  `account_guard_test.dart`（`a rejected credential`：重跑帶新憑證、三個並行刷新一次、不支援刷新、`null`、被拒、重跑又被拒不
  循環、刷新網路錯誤；`while a refresh is in flight`：登出、重新登入、併進啟動刷新；`other failures`：限流、網路錯誤、
  匿名的 401，風控 `VerificationRequired` 沒有案例，靠守衛只 catch `CredentialInvalid`）、
  `toaster_test.dart` 的 `an invalidated sign-in`、`accounts_section_test.dart` 的 `a rejected credential prompts…` 與
  `a rejected credential during a user action`（搜尋、播放各一，只有一則提示）。
- 啟動刷新（`AccountService.refreshOnStartup`、`accountStartupRefreshProvider`）：宣告 `refresh: 'onStartup'` 且有可用憑證的
  插件，在第一幀之後（`FmpApp` 讀 provider）、**網路狀態第一次是 `online` 時**各 `loginRefresh` 一次（與失效時的刷新共用
  單飛），整個執行只跑一次；先等網路狀態的第一次介面檢查（`NetworkStatusNotifier.whenFirstChecked`），因為網路狀態的預設是 `online`，沒查過就不知道有沒有網路。不是排程器
  工作、不在啟動維護清單。結果寫帳號列的 `last_refresh_at`／`last_refresh_result`：新憑證 `refreshed`、`null` `unchanged`、
  被拒標失效並 `failed`（提示一次）、網路錯誤等 `failed` 但帳號仍可用。帳號頁對宣告 `refresh` 的插件顯示最後刷新的時間與
  結果。不做全面驗證（啟動時不對每個帳號打帳號資訊 API）。閘門：`account_guard_test.dart` 的 `startup refresh`、
  `the startup refresh provider`（離線不發、上線後發一次、之後不再發）、`accounts_section_test.dart` 的
  `shows the last refresh…`、`a failed refresh…`。`FmpApp` 在第一幀之後讀這個 provider 的那一行沒有閘門，review 時看。
- 「憑證無效」判定表（`credentialsAttached` 為真的 401、`-101` 等）在各插件的目錄內，由插件 repo 的 Node 測試守（輸入回應
  與 `credentialsAttached`），不是契約 fixture（ADR 0015 §決定 4 每能力一條案例；PR 1 的先例）。沒有閘門：本 repo 不守。
- 憑證的值只用假值寫測試（`FAKE_…`）。

## 插件

`lib/plugins/`（ADR 0014）。怎麼寫插件、怎麼加宿主 API：`.trellis/spec/app/plugins/index.md`；
給插件作者的型別定義：`lib/plugins/types/fmp-plugin.d.ts`。

- 安裝檔是單一 `.js`：開頭（前面只准 BOM 與空白）以 `/* ==FMP Plugin==`、`==/FMP Plugin== */`
  包一段 JSON manifest，之後是 ES module。讀 manifest 不執行腳本。manifest 與 DTO 的物件是封閉的：
  不認得的欄位整個拒收。閘門：`test/plugins/manifest/`。
- 能力與匯出函式同名、雙向一致：宣告了沒匯出、匯出了能力名稱卻沒宣告，都拒絕載入
  （`Unsupported`）；其他名稱的匯出不管。`login` 例外：它的匯出是 `loginVerify`，methods 含 `qr` 時加 `loginQrStart`、
  `loginQrPoll`，宣告 `refresh` 時加 `loginRefresh`（`PluginManifest.requiredExports`），同樣雙向一致。`live` 也例外：
  匯出是 `liveSearch`、`liveRoomFromUrl`、`liveStatus`、`resolveLive` 四個，宣告就要全有（`LiveExports`），也沒有名叫 `live` 的匯出。
  `importPlaylist` 也例外：匯出是 `playlistFromUrl`、`importPlaylist` 兩個，宣告就要全有（`ImportPlaylistExports`）。
  `apiVersion` 必須等於 `hostApiVersion`。閘門：`script_source_plugin_test.dart` 的 `exports and capabilities`、`login exports`、
  `live_capability_test.dart`、`import_playlist_capability_test.dart` 的 `exports and capabilities`、`plugin_manifest_test.dart`。
- `live`（ADR 0028 §決定 3；電台見 § 電台，收聽見 § 播放的「直播」）：`liveStatus` 查詢失敗一律拋錯，
  不能回 `offline`（D10）：宿主把拋錯顯示成「查詢失敗」，`offline` 只表示查到了而且沒開播；插件吞掉錯誤回 `offline` 是插件的 bug，
  宿主分不出來，本 repo 沒有閘門守（`fmp-test` 的 `live-broken` 只示範正確的行為）。
  四個呼叫都經 `AccountGuard`（`CredentialInvalid` 時刷新重跑），但帶不帶憑證仍是插件在每個請求上標 `auth: 'userPreference'`
  決定（宿主沒有「這個呼叫是直播」的資訊，ADR 0012 §決定 2 的「電台」由插件落實）。`liveRoomFromUrl` 回 `null` 是「不是我的網址」。
  閘門：`live_capability_test.dart`（回傳值驗證、拋錯保持拋錯、`credentials follow the user preference`）。
- manifest 的 `login`（ADR 0029 §決定 1）：有 `login` 能力才有、反之亦然；methods 不空、不重複，含 `webView` 才有
  `webView`（反之亦然），它的 `url`、`cookieHosts` 都是 `allowedHosts` 內的 `https`；格式錯是 `ParseError`，不認得的方式或
  刷新時機是 `Unsupported`。閘門：`plugin_manifest_test.dart` 的 `login` 群組、`rejects as Unsupported`。
- `mix`（ADR 0028 §決定 4）：匯出就叫 `mix`（和能力同名），開始（`MixSeedQuery`）與續取（`MixContinueQuery`）是同一個匯出，
  形狀在 `fmp-plugin.d.ts`。**回傳的 `cursor` 沒有或 `null` 是這個 Mix 沒有更多**（d.ts 寫成選填，因為欄位表的必填不收 `null`；
  空字串拒收），宿主下一次補歌改以佇列最後一首當 `seed` 開新的一批，`mixId` 可以換。`tracks` 的曲目鍵第一段由宿主填成插件 id。
  請求怎麼標 `auth` 由插件決定，同 `live`。去重是宿主做的（`QueueModel.extendMix`，見 § 播放），插件不必管佇列裡有什麼。閘門：`mix_capability_test.dart`（匯出與能力一致、
  兩種輸入的 JSON、回傳值驗證、`fmp-test` 的三批）、`type_definitions_test.dart` 的 `the mix export is named after the capability…`、
  `the cursor of a mix batch is optional…`（兩個都含變異）。
- `multiPart`（ADR 0028 §決定 5）：匯出就叫 `multiPart`（和能力同名），回傳至少一個分 P（`index` 從 1 起）；`TrackSummary` 的選填
  `partCount`（正整數）。形狀在 `fmp-plugin.d.ts`。**`partCount` 只是提示**：空是不知道
  （B 站的搜尋回應沒有，所以多半是空），1 是確定單 P。每個分 P 是一首曲目（`MultiPart.toTrackInfo(video)`：`sourceId` 是影片的、`cid`、
  `title`、時長用分 P 的，上傳者與封面沿用影片，`part_index` 與 `parent_title` 見 § 資料層）。請求怎麼標 `auth` 由插件決定。閘門：
  `multi_part_capability_test.dart`（匯出與能力一致、輸入的 JSON、回傳值驗證、`partCount` 的讀取、由分 P 建出的曲目、`fmp-test` 的三種狀況）、
  `type_definitions_test.dart` 的 `the multiPart export is named after the capability…`、`partCount and the part fields match…`（含變異）。
- `trackDetail`（ADR 0028 §決定 6）：匯出就叫 `trackDetail`（和能力同名），回傳的欄位都可以沒有或 `null`，形狀在 `fmp-plugin.d.ts`。
  `publishedAt` 是 UTC epoch 毫秒（非負、不超過 `DateTime` 的上限）；`uploaderAvatar` 的網域照 `Artwork`；`stats.kind` 是封閉的 union
  （`TrackStatKind`），**不認得的 `kind` 整筆拒收成 `ParseError`**（不會悄悄丟掉）：宿主依 `kind` 挑圖示與翻譯，不顯示插件給的文字，
  所以新的種類要先改宿主。閘門：`track_detail_capability_test.dart`（匯出與能力一致、輸入的 JSON、回傳值驗證含未知 `kind`／負的
  `count`／頭像網域）、`type_definitions_test.dart` 的 `the trackDetail export is named after the capability…`、`the stat kinds match
  TrackStatKind`、`the trackDetail fields match…`（含變異）。
- `importPlaylist`（ADR 0032 §決定 1、2；宿主端的匯入與刷新見 § 音樂庫）：`playlistFromUrl` 回 `null`
  （不是我的網址）、`{playlistId}` 或 `{mixSeed}`（`PlaylistRef`），`mixSeed` **只收宣告 `mix` 的插件**（否則 `ParseError`）；
  `importPlaylist` 回一頁 `{playlist, items, cursor, total?}`：`items` 可以是空陣列，`cursor` 沒有或 `null` 是最後一頁（d.ts 寫成選填，
  同 `mix`；空字串拒收），`total` 非負、只在確定等於會回傳的筆數時才給，`playlist` 每一頁都要給。`TrackSummary` 的選填
  `partIndex`（正整數）與 `parentTitle`（不空）**要嘛都給、要嘛都不給**（只給一個是 `ParseError`），宿主寫進 `TrackInfo`；分 P 曲目
  一定要給，否則宿主的 upsert 會清掉這兩欄。錯誤：不存在或沒權限讀 `NotFound`、要登入而沒登入 `AuthRequired`。**請求一律標
  `userPreference`，被拒時以 `required` 重送一次**由插件做（宿主沒有「這是歌單」的資訊），宿主沒有閘門，由各插件 repo 的 Node 測試守。
  閘門：`import_playlist_capability_test.dart`（匯出與能力一致、輸入的 JSON、回傳值驗證、`mixSeed` 與 `mix` 的關係、分 P 兩欄）、
  `test_plugin_bundle_test.dart` 的 `playlists`（`fmp-test` 的七張歌單）、`type_definitions_test.dart` 的 `the importPlaylist exports…`、
  `the importPlaylist page fields…`、`partIndex and parentTitle…`（都含變異）。
- `checks.json` 的 `live`、`mix`、`multiPart`、`trackDetail`、`importPlaylist` 案例各呼叫那個能力一次（`live` 跑 `liveStatus`、`mix` 以 `seed` 開始），
  檢查的清單是回傳的那一份（直播間、`tracks`、`parts`、那一筆詳細），`nonEmpty` 的名稱是該 DTO 的欄位名；重播照跑、命令列錄製照錄
  （匿名）。`importPlaylist` 案例先跑 `playlistFromUrl`（輸入 `{url}`，用公開歌單）、再跑第一頁，檢查的清單是 `items`，`nonEmpty` 的名稱是
  `RemotePlaylistItem` 的（`track`、`remoteItemId`、`unavailable`）；網址認不得或回 `mixSeed` 案例失敗（`ParseError`）。閘門：
  `checks_test.dart` 的 `the live check`／`the mix check`／`the multiPart check`／`the trackDetail check`／`the importPlaylist check`、
  `contract_runner_test.dart` 的 `a live check…`／`a mix check…`／`a multiPart check…`／`a trackDetail check…`／`an importPlaylist check…`（五種都有「沒宣告能力」；
  `live`、`mix`、`trackDetail`、`importPlaylist` 另有期望不符，`live`、`mix`、`importPlaylist` 另有改無關處不紅）、`health_check_test.dart` 的 `a live case`／`a mix case`／
  `a multiPart case`／`a trackDetail case`／`an importPlaylist case`、`dev_case_runs_test.dart` 的 `a live case…`／`a mix case…`／`a multiPart case…`／`a trackDetail case…`／`an importPlaylist case…`。
- `checks.json` 的 `login` 案例跑 `loginVerify`（輸入是假憑證，fixture 在 `fixtures/login/`），必須標
  `requiresLogin: true`；重播照跑，命令列錄製略過（design §4.8）。閘門：`checks_test.dart` 的 `the login check`、
  `record_test.dart` 的 `skips a case that requires a login`。
- 案例可標 `mutates: true`（`PluginCheck.mutates`，每種案例的欄位表都收這個選填欄位、只准 `true`；M4 PR 12 加，第一個用它的是
  `libraryWrite`，它的案例改成必填）：會改動遠端的案例，健康檢查（`HealthSkip.mutates`）、命令列錄製（`recordCase` 回
  `<能力>: mutates the remote`）、App 內開發工具的真實與錄製（`DevSkip.mutates`）一律略過、**不呼叫插件**（連 `playlistFromUrl`
  這類前置呼叫也不行）；`runIsolatedCase` 對真實連線的 `mutates` 案例直接丟 `StateError`（呼叫端漏略過也不會送出）。重播與契約測試照跑，
  fixture 手寫。閘門：`checks_test.dart` 的 `mutates`（含每種案例形狀都收它）、`case_runner_test.dart` 的 `a mutates case…`／`skips a mutates case…`、
  `health_check_test.dart` 的 `a mutates case`、`dev_case_runs_test.dart` 的 `a mutates case`、`record_test.dart` 的 `skips a case that mutates the remote…`／
  `replays a case that mutates the remote`。
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
  `hostApiShapes`，`FmpHost` 對 prelude 實際建出的 `fmp`，能力、錯誤名稱、`Unavailable` 原因、音質與登入
  （`LoginMethod`、`LoginRefresh`、`LoginQrStatus`）與 `LiveRoomStatus` 的 union，`FmpPluginExports` 含 `LiveExports` 對 Dart 的列舉。閘門：`test/plugins/type_definitions_test.dart`（含變異案例）。函式參數的
  型別不比對，review 時看。
- 插件庫與生命週期（`lib/plugins/repository/`、`install/plugin_installer.dart`，ADR 0030，UI 在插件頁）：
  - `PluginIndex.parse` 欄位封閉（表外欄位 `ParseError`），`indexVersion` 不是 1 回
    `IndexRejected(appUpdateRequired)`（預期內的結果，不是 `AppError`、也不是例外：UI 要分得出「需要更新 FMP」）；`apiVersion` 不是
    `hostApiVersion` 的那一筆照樣解析（`isCompatible` 為假），到 `prepare` 才以同一個理由拒絕、不下載。
    `prepare` 回 `PrepareRejected` 而不丟例外：`hashMismatch`（提示「插件庫剛更新，請稍後再試」）、`manifestMismatch`、
    `appUpdateRequired` 都是預期內的結果，其餘失敗（網路、解析）仍丟 `AppError`。
    閘門：`plugin_index_test.dart`；`prepare` 的那一條是 `plugin_installer_test.dart` 的 `an apiVersion the host
    does not support…`。
  - `PluginDownloader.prepare`：下載 → SHA-256（針對位元組）→ 解析標頭 manifest → 與 index 那一筆比 id、版本、
    `apiVersion`、能力、網域，不符都拒裝且不寫資料庫。確認內容取自下載到的 `.js`。`checks.json` 驗證不過或下載失敗
    只記 warning，插件照裝、`checksJson` 為空。新安裝、或更新時能力或網域增加（`PreparedPlugin.needsConfirmation`）而沒確認
    （`installPrepared(confirmed: false)`）會丟 `StateError`。閘門：`plugin_installer_test.dart` 的 `plugin repository`
    群組。
  - `updateStatus`：semver 只升不降（`pub_semver` 只准在 `lib/plugins/repository/`），只從 `source_index_url` 相同的
    index 更新；`apiVersion` 不相容是 `needsAppUpdate`。閘門：同群組的 `update status…`、lint
    `fmp_layer_imports` 的 `test_pubSemver*`。
  - 停用（`PluginRegistry.setEnabled`）：存進資料庫、移除它的排程器工作、關閉 runtime 與媒體 client，憑證與 storage 保留；啟動不載入停用的
    插件；啟用時載入失敗則旗標不變。「沒有回應」不寫資料庫（沒有測試，review 時看）。更新停用中的插件寫進新版本但不加入清單。
    停用後佇列裡它的曲目照「音源已停用」、移除後照「音源未安裝」跳過，準備好的前瞻放掉（見「播放」）。閘門：
    `plugin_registry_test.dart`（storage 保留有測，憑證保留沒有：`setEnabled` 不碰 `CredentialStore`，review 時看）、
    `plugin_installer_test.dart` 的 `updating a disabled plugin…`。
  - 移除（`PluginInstaller.remove`）：排程器的工作（`unregisterPlugin`，第一步：後面幾步的期間到期的工作不會拿到已關閉的插件）→ 關閉
    runtime → 憑證與遮蔽登記、`accounts`、`source_settings`（`AccountService.removePlugin`）→ `CacheStore.removePlugin` → 刪 `installed_plugins` 列（storage
    cascade）；曲目保留。快取庫開不起來（`cacheStoreProvider` 是錯誤）時略過快取那一步、記 warning，不擋移除。每一步可重複，失敗停在那一步。登入 WebView 的 cookie 在帳號那一步裡（見「帳號」的登出）。
    閘門：
    `plugin_installer_test.dart` 的 `removing` 群組（含 `skips the cache step…`）。
  - 從網址安裝：`PluginDownloader.downloadFile` 經同一個宿主 client 下載（上限同插件檔）並只讀標頭 manifest，
    安裝走 `installSource`（沒有來源 index、沒有 checks、之後不會有更新）。閘門：`plugin_installer_test.dart` 的
    `downloading from a URL…`、`downloading something that is not a plugin…`。
  - `PluginRepository.changes()`、`PluginIndexRepository.changes()`：聽 drift 的 `tableUpdates`（理由同歷史表），插件頁
    以它重讀。閘門：`plugin_repository_test.dart` 的 `changes fires…` 兩例。
  - 顯示名稱 `pluginNameProvider`（`lib/ui/plugins/plugin_name.dart`）：清單上是 manifest 的 `name`，停用的是
    「音源已停用」，沒安裝的是「音源未安裝」，清單未載入完是 `null`。閘門：`test/ui/plugins/plugin_name_test.dart`。
  - 不可用原因 `sourceUnavailableProvider`（同檔）：音源停用回「音源已停用」、沒安裝回「音源未安裝」，在清單上（已安裝且啟用）
    與清單未載入完時是 `null`；`pluginNameProvider` 在清單以外的插件上就是它的值。佇列與歷史列、跳過提示用它。閘門：
    `test/ui/plugins/plugin_name_test.dart`。
  - `Redactor` 的媒體 CDN 規則以插件 id 為鍵（`setMediaCdns`），插件更新、重新載入時取代而不累加；header 與鍵名
    名單仍只增不減。閘門：`redactor_test.dart` 的 `setting a plugin again replaces…`。
- 開發入口：dev flavor 啟動時安裝 `--fmp-dev-plugin=<路徑>` 或環境變數 `FMP_DEV_PLUGIN` 指的檔案；
  Android 以 `adb shell am start -n com.personal.fmp.dev/com.personal.fmp.MainActivity --esal
  dart_entrypoint_args --fmp-dev-plugin=<App 讀得到的路徑>` 帶參數。prod 不讀：這條路徑跳過安裝前的
  確認（ADR 0014 §決定 6），參數與環境變數都能由別的程式帶入。`devPluginPath` 在 prod 一律回
  `null`。閘門：`plugin_installer_test.dart` 的 `development entry`（含 `prod reads neither…`）。
- 測試插件 `test/fixtures/plugins/test_plugin/`（`fmp-test`）只以 dev flavor 的 asset 打包，串流指向
  同目錄的 `tone.wav`（`asset:///…`）。prod 的建置只留下空目錄，沒有檔案。實機以
  `--fmp-dev-plugin` 裝它的 `.js`，搜尋任何關鍵字都有結果、都播得出來；關鍵字剛好是 `fail`
  時以 `RateLimited` 失敗（離線看錯誤提示）；`missing`、`preview`、`flaky`、`unavailable` 給播放
  恢復的實機驗證；假的 QR 登入（第二次輪詢就完成，憑證 `fake-session-0000`）與貼上 cookie（任何值不空的 `fmp_test_session`）給帳號頁的
  實機驗證，登入後的關鍵字 `expired`（刷新後成功）、`expired-hard`（刷新也被拒、轉成已失效）與啟動刷新（`unchanged`）給失效與
  刷新的實機驗證。它不發請求，
  帶不帶憑證要看 `account_service_test.dart`（細節在 `test_plugin/README.md`）。閘門：
  `test/plugins/test_plugin_bundle_test.dart`（搜尋與播放的關鍵字、只在 dev 打包）；登入只有 `checks.json` 的 `login` 案例經
  `contract_test.dart` 跑 `loginVerify`，QR、`expired`、`expired-hard` 沒有閘門，實機驗。第二個測試插件
  `http_test_plugin/`（`fmp-test-http`）會發請求（`*.fmp.test`），只給契約執行器，不打包。
- 插件目錄（契約檢查與 App 內開發工具的單位；讀取在 `lib/plugins/dev/plugin_folder.dart`）：剛好一個 `.js` 安裝檔、`checks.json`（鍵是能力名稱，所以每能力最多
  一條；只收 `SourcePlugin` 已有方法的能力）、`fixtures/<能力>/*.json`（依檔名是請求順序）。格式
  寫在 `fmp-plugin.d.ts` 的 `FmpChecks`、`FmpFixture`。每個案例在隔離環境（`lib/plugins/dev/case_runner.dart` 的
  `runIsolatedCase`：各開一份記憶體資料庫、空的憑證存放、新的 runtime 與 client）裡跑，命令列契約執行器
  （`test/plugins/contract/`，只留憑證掃描與網域檢查）與 App 內開發工具共用；執行器檢查：能力與匯出一致、DTO 驗證、案例期望（成功的筆數與非空欄位，或失敗的 `AppError`
  類別與 `Unavailable` 原因）、沒試著連清單外的網域、串流 headers 不帶憑證、log 與 fixture 都遮蔽
  過。閘門：`test/plugins/contract/contract_runner_test.dart`（每種違反一個會紅的變異，另有改無關
  處不紅的案例）、`checks_test.dart`。
- `resolveStream` 的案例可帶 `expiresAtPattern`（ADR 0016 §如何確認）：剛好一個擷取群組、擷取
  unix 秒的正規式，只能配成功的期望。網址對得上的候選，`expiresAt` 必須等於擷取到的時間；一個都
  對不上也算違反（期限參數被遮掉時檢查不會默默恆真）。它也算期望，不符時錄製不寫檔。閘門：
  `contract_runner_test.dart` 的 `when expiresAt agrees…`、`when an unrelated part of the stream URL
  changes`、`an expiresAt that disagrees…`、`a missing expiresAt…`、`an expiresAtPattern that no URL
  matches`；`checks_test.dart` 的群組數、錯誤期望、非正規式。
- `StreamRequest.quality`（`high`／`medium`／`low`，選填）與依格式偏好排過的 `formats` 是插件 API
  v1 內的擴充（ADR 0014 §決定 5 的補充）：宿主一律送 `quality`，插件沒給時自己決定。字面值由
  `audioQualityWireName` 寫死。閘門：`type_definitions_test.dart` 的 `the audio qualities match
  AudioQuality`、`stream_resolver_test.dart` 的 `each quality goes to the plugin by its wire name`。
- 重播：第 n 個請求對第 n 個 fixture，比 method 與網址（實際網址先經 `Redactor`；query 不分順序；
  fixture 裡值為 `***` 的 query 參數與路徑段不比值）。對不上或用完就讓那次請求失敗、不送出；沒用
  到的 fixture 也算違反。header 與 body 不比。閘門：`contract_runner_test.dart`、
  `fixture_scan_test.dart` 的 `replay matching`。
- fixture 寫檔前經 `Redactor`（`HttpFixture.redacted`：網址與文字 body 用 `redact`、header 與
  `jsonBody` 用 `redactValue`，`set-cookie` 只遮值、留名稱與屬性，重播時才解析得了）；不是
  UTF-8 的 body 不錄。`app/` 內每個 fixture 都要「再遮一次不變」且名單上的欄位值是 `***`。閘門：
  `fixture_scan_test.dart`（`every fixture in app/ is redacted`，兩道檢查各有會紅與不紅的案例）、
  `record_test.dart`（假上游錄出的檔案沒有假憑證、重播通過）。
- 插件開發工具（M3 PR 16b，ADR 0025 §決定 7；`lib/plugins/dev/`）：
  - 開發資料夾的每個插件目錄載入成「開發中」，取代同 id 的已安裝版（`PluginDevelopment`：卸下上一次的、掃描、對齊
    `installed_plugins` 標記列、恢復已安裝版、載入新的；所有動作排進同一條序列）。沒有已安裝的列就補一列標記列（見「資料層」的
    `from_dev_folder`）；有就沿用，version／manifest／script／enabled 不動、storage 共用。卸載（資料夾變 `null`、關閉開發者模式、
    平台沒有 `pluginDevTools`）時刪標記列、恢復已安裝版。載入失敗（含重新載入、manifest 的 id 改變）**不退回已安裝版**：插件不在
    清單上，卡片標「載入失敗」與已遮蔽的原因。不監看檔案：「重新載入」「重新掃描資料夾」都是手動。
    閘門：`plugin_development_test.dart`（沒有／有同 id 的列、殘留列、關閉開發者模式、平台沒有能力、重新載入關掉舊 runtime、載入失敗、
    id 重複、重新掃描、id 改變）。
  - **真實｜錄製｜重播只決定「跑案例」的方式**，不是 App 裡那個插件的網路開關：`DevCaseRuns` 每個案例各自在隔離環境以對應的
    adapter 跑（重播＝`ReplayTransport`、錄製＝`NetworkTransport(record)`、真實＝`NetworkTransport`），預設重播；App 其他地方用到
    的開發中插件一律真實連線。理由：在帶著 storage 快取的插件上錄的 fixture（B 站 `wbiKeys` 有值就少發請求）在 CI 的空 storage
    重播會對不上。錄製走 `recordCase`，與命令列 `recordContract` 同一個函式（結果符合 `checks.json` 且錄製沒有問題才寫、手改過的
    略過、寫檔前經 `Redactor`）；寫檔前檢查代際（跑的途中換資料夾或卸載就不寫）。`requiresLogin`：重播用 `checks.json` 的假憑證，
    真實與錄製用已存的憑證，沒登入略過、不連網：login 案例當 `loginVerify` 的輸入；其他 `requiresLogin` 的案例
    （M4 PR 12，`libraryRead` 起）由 `runIsolatedCase` 放進隔離環境的記憶體憑證存放（transport 是真實連線、案例標 `requiresLogin` 才放，
    重播的 `ReplayTransport` 一律不放；請求依 ADR 0012 帶它，網路紀錄記 `credentials: true`）。失效處理（`AccountGuard`）看的是另一份空的存放：
    憑證被拒時案例照實失敗，不會呼叫 `loginRefresh`——刷新會換掉音源端的 token，新 token 卻只活在這個案例的記憶體。遮蔽函式不認得帳號名稱，所以
    所有 `requiresLogin` 的案例 `recordCase` 寫檔前先以帳號（login 是結果，其他是 `accounts` 列，`loginAccountOf`；列不在或頭像讀不懂就不錄）的
    `userId`、`displayName` 換掉錄到的流量（`scrubAccount`，頭像網址換成 `<scheme>://<主機>/***`），再用 `accountLeaks` 檢查，
    換完仍看得到就不寫（fixture 進公開的插件 repo）。不靠鍵名：鍵名分不出自己和別人，會弄壞別人的 id、頭像。
    換值只認 id、名稱、頭像，登入後的回應還有 email、手機號、等級之類，所以錄到的檔案不原樣提交：刪減到只剩插件讀的欄位，
    或改用手寫的，並在 `meta.edited` 寫明（ADR 0015 §決定 7 的更正；閘門在插件庫的 `test/login_fixtures_test.dart`）。
    閘門：`account_scrub_test.dart`、`case_runner_test.dart`（三種模式帶不帶憑證、被拒不刷新、換值後才寫、殘留不寫、無關欄位不擋、沒有帳號列不錄）。回傳值經 `Redactor.redactValue` 顯示，`LoginAccount` 一律顯示
    `***`。一次只跑一個案例（整個區塊）。閘門：`dev_case_runs_test.dart`（預設重播、隔離不碰 App 的 storage、錄製的檔案沒有假憑證
    且與命令列逐位元組相同、手改過的略過、結果不符不寫、帳號資訊換值後仍可重播、`requiresLogin` 兩種、一次一個、換資料夾與
    卸載的代際丟棄、每案例一筆 log）。
  - 健康檢查對開發中的插件讀資料夾的 `checks.json`（`PluginDevelopment.checksJsonFor`）。閘門：`health_check_test.dart`。
  - 已知限制（沒有閘門）：registry 重建會丟掉開發版（registry 目前從不重建）；開發版 manifest 比已安裝版多的能力（如 `login`），
    讀列的元件（例如 `CredentialStore`）看到的是已安裝版的 manifest；只有開發資料夾才有的插件卸載時只刪列與 storage，帳號列與憑證
    保留（要清就先在帳號頁登出）；帶憑證錄的流量只換 id、名稱、頭像（見上），
    而短於 4 個字元的名稱只換整個值相等的字串：嵌在別的字串裡（例如歌單標題「<名稱>喜歡的音樂」）換不到、`accountLeaks` 也看不到，刪減時要人工看；隔離環境的「以登入身分瀏覽」開關讀的是空的設定表，
    不是使用者在帳號頁設的值，`userPreference` 的請求依 manifest 的預設決定帶不帶；debug build 下案例與 App 的資料庫同時開著，drift 會印「多個資料庫」的警告（無害）。
  - 插件頁（見「介面」）：開發中的卡片不能啟用、更新、移除，閘門 `plugins_page_test.dart` 的 `plugins in development`。
- 執行器看不到的：插件接住並吞掉「網域不在清單」的錯誤（網路層照樣不送出）；插件自己拋的
  `ParseError` 與 DTO 驗證失敗的 `ParseError` 分不出來。沒有閘門，已知限制。

## 排程器

`lib/scheduler/background_scheduler.dart`（ADR 0017，M3 PR 17）：會發網路請求的週期工作的唯一擁有者。目前的工作：
`radio-status:<pluginId>`（§ 電台）與收聽直播時的 `live-info`（§ 播放）；排行與匯入歌單的刷新在 M4。`backgroundSchedulerProvider` 由 `FmpApp` 常駐（Riverpod 3 沒人聽的 provider 會被暫停）。

登記一個工作：`ref.read(backgroundSchedulerProvider.notifier).register(SchedulerJob(id:, pluginId:, interval:, run:))`。

- `id` 也是 `scheduler_runs` 的鍵；同 id 再登記是取代，舊的進行中那次視為過期。`pluginId` 非空時，同一個插件的工作依序執行，
  插件停用（`PluginRegistry.setEnabled`）或移除（`PluginInstaller.remove`，在刪 `installed_plugins` 列之前）時整批移除。
  `interval` 為 `null` 是關閉：不自動跑，只有 `runNow` 會跑它。
- `run` 長時間的工作要看 `JobContext.isCurrent`：工作被移除、被取代或排程器釋放後為假，這時丟掉結果、不寫任何東西；排程器也不替
  那一次記上次成功時間。
- 工作丟錯：排程器經 `log.report`（tag `scheduler`，`AppError.wrap` 帶工作的 `pluginId`）寫進錯誤歷史，再記一行 info
  `Background job backed off`（`jobId`、`pluginId`、`failures`、`retryInMs`），不跳提示；退避 1、2、4… 分鐘，上限為該工作的間隔，
  `AppError.retryAfter` 優先；退避只往後延，不會讓工作比「上次成功加間隔」更早跑；成功後歸零。手動刷新（`runNow`）失敗時同樣退避，
  但把錯誤重新丟給呼叫端、排程器不記 log：手動操作的錯誤由呼叫端決定要不要提示（ADR 0013 §決定 5）。
- `runNow` 不看間隔也不看 App 是否可見，但離線不發，且一樣受並行限制（沒有空位就排隊，先於自動的工作）。排隊期間工作被移除、
  斷線或排程器釋放，就不執行、以 `unknown`／`offline` 結束。
- 只有一個一次性 `Timer`，對準最早到期（含退避中）的工作；到期、生命週期或網路狀態改變、登記變動時重算。App 不可見
  （`hidden`、`paused`）或網路不是 `online` 時沒有計時器；進行中的工作跑完、不開新的。回到可見或在線時，已到期的工作各跑一次。
  沒有上次成功時間的工作視為已到期（App 啟動視同變可見），但啟動時先等網路狀態的第一次介面檢查（`whenFirstChecked`；狀態預設是
  `online`），離線啟動才不會先發出去。全域同時最多 2 個。
- 週期計時器只准在 `lib/scheduler/` 與 `lib/playback/`（lint `fmp_periodic_timer_owner`）；排程器不 import `ui/`、`radio/`、
  `plugins/`，`core/`、`domain/`、`data/` 不 import `scheduler/`、`radio/`（`fmp_layer_imports` 的 `forbiddenLayerImports`）。
- 閘門：`test/scheduler/background_scheduler_test.dart`（ADR 0017 §如何確認的七項、同插件依序、全域最多 2 個、手動刷新排隊與
  排隊中結束、取代與移除時的過期、手動失敗不提早自動跑、錯誤經 `report`、等第一次介面檢查），`plugin_registry_test.dart` 的 `disabling a plugin removes its scheduler jobs…`，
  `plugin_installer_test.dart` 的 `removing`（工作最先移除、中途失敗重跑可完成）。排程器在真機上的行為（最小化、切到背景、
  飛航模式）沒有自動閘門，在電台頁實機看。

## 電台

`lib/radio/`（ADR 0031 §決定 1、2、6；畫面見 § 介面的電台頁）：使用者存的直播間清單，沒有外鍵到 `installed_plugins`（schema 見
§ 資料層）。`lib/radio/` 用資料、插件與排程器，不 import `ui/`，`scheduler/` 不認得它（lint 見 § Lint）。

- **「查詢失敗」只在記憶體**（`radioQueryFailuresProvider`，D10）：不寫進資料庫、不當成未開播，重啟回到資料庫存的狀態；下一次查詢
  成功就清掉。畫面的四種狀態（`RadioEntry.status`）由資料庫的狀態加這份標記合成。
- **新增**（`RadioService.addFromUrl`）只問已啟用（在 `pluginRegistryProvider` 裡）而且宣告 `live` 的插件，第一個認得網址的勝出；**寫入與
  判斷重複用 `liveStatus` 回傳的 `roomId`**，不用網址裡的（B 站短號回長號）。失敗一律是 `AppError`、不寫入，插件拋錯就停、不再問下一個。
- **狀態工作**（`RadioStatusJobs`，`FmpApp` 常駐）：每個「已啟用、宣告 `live`、清單裡有電台」的插件一個 `radio-status:<pluginId>`，
  間隔是「網路」組的電台狀態刷新間隔（關閉＝`interval: null`，只有手動刷新會跑）。**單一電台失敗只標那一列「查詢失敗」，其他繼續；
  全部失敗才丟錯讓排程器退避**（一個壞房間不讓整個插件退避）。只在插件實例、間隔或「有沒有電台」改變時重新登記，電台增減不打斷進行中
  的那次（工作每次跑都重讀清單）。不在 `onDispose` 移除工作：生命週期裡不能碰別的 provider，它跟排程器一樣常駐到 App 結束。
- **手動刷新**（`RadioService.refresh`）對每個登記中的工作 `runNow`；離線回 `offline`（沒有發請求），某個插件的工作全部失敗時錯誤在全部
  結束後重新丟出，由呼叫端提示。
- 閘門：`test/radio/radio_test.dart`（以網址新增：第一個認得的勝出、都不認得、用長號判斷重複、停用或沒有 `live` 的插件不會被問到、插件失敗不寫入、不是 `AppError` 的失敗包成 `UnexpectedError`；加為電台與重複；
  四種狀態；狀態工作：依序查並存、單一失敗只標那一列且工作不退避、全部失敗退避、過期結果被丟掉、停用／重新啟用／電台增減／間隔改變（含 0 只關排程不關手動）、
  離線不跑；手動刷新三種結果與錯誤）、`radio_repository_test.dart`。

## 音樂庫

`lib/library/`（ADR 0033 §決定 2、M4 design §5；畫面與排程工作在後面的 PR）：匯入歌單的匯入與刷新。`lib/library/` 用資料、插件與排程器，不 import
`ui/`；`core/`、`domain/`、`data/`、`scheduler/` 不認得它（閘門：lint `fmp_layer_imports`，見 § Lint）。

- **匯入**（`PlaylistImporter.importUrl`）依 `pluginRegistryProvider` 的順序問已啟用、宣告 `importPlaylist` 的插件 `playlistFromUrl`，第一個認得的勝出，
  插件拋錯就停、不問下一個；失敗一律是 `AppError`。結果型別：`ImportUnrecognized`、`ImportMixSeed`（Mix，PR 11 處理）、`ImportMetadataOnly`
  （插件沒有 `resolveStream`，PR 19 處理，不取任何一頁）、`ImportedPlaylist`。（插件, 歌單 id）已在 `playlist_remote`＝重新匯入，直接刷新那一列，
  名稱、間隔等本地設定不動；否則**第一頁成功才建列**（名稱取遠端標題、不唯一、不自動改名，間隔 24 小時），第一頁交給刷新器當 `firstPage`（不再取一次），
  其餘頁由刷新器取。
- **刷新**（`PlaylistRefresher.refresh`）全 App 一個 FIFO 鎖（provider 持有的單一物件），同時只刷一張。每頁一個 transaction 寫進正式表，以
  `refresh_generation`（開始時加一得到 g）標出這次見過的項目；完整（每頁成功、最後 `cursor` 為空、有 `total` 時筆數相等；一直回同一個 `cursor`
  的插件在 `cursor` 第一次重複時就停、當作沒讀完）才一個 transaction 刪 `seen_generation < g`、重寫 `position`、未覆寫的名稱／描述／封面跟遠端、寫 `writable`
  （`null` 保留上次的值）。不完整只寫 `partial`，不移除不重排。**第一頁以外的頁失敗是 `partial`，第一頁就失敗才是 `failed`**；`NotFound`／
  `AuthRequired` 任何一頁都只改 `status`（`sourceGone`／`authRequired`）；都不碰既有項目。成功（含 `partial`）把 `status` 設回 `active`。
  寫入資料庫本身丟的例外（不是插件的錯）原樣丟出，不記 `failed`。
- **比對鍵**：遠端項目有 `remote_item_id` 就用它；沒有就用（曲目鍵, 第 k 次出現）：現有項目依目前（`position`, `id`）排成佇列，遠端第 k 次出現取第 k 個，
  重複影片不合併。兩種鍵各自一池：有 `remote_item_id` 的現有項目只會被同一個 id 比到，同一首在有 id 與沒 id 的回應之間切換（例如登入前後）時是新項目，
  完整時舊的被刪、`partial` 時兩個都留著。比對規則在 `PlaylistRefreshSession`（`lib/data/`，要查表），頁迴圈與完整性在 `PlaylistRefresher`。
- **過期**：每個寫入先在同一個 transaction 內檢查代際仍是 g 與 `RefreshTrigger.isCurrent`，另外插件還是註冊表裡那一個（停用、移除、更新換掉都算過期）；
  過期就丟掉、不寫，結果是 `RefreshDiscarded`。`RefreshTrigger` 只有 `isCurrent`：手動用 `RefreshTrigger.manual`，排程工作傳
  `JobContext.isCurrent`（PR 10）。插件已停用或移除：`RefreshSourceUnavailable`，連代際都不動。
- 閘門：`test/library/playlist_refresher_test.dart`（ADR 0019 §如何確認的刷新差異：新增、移除、順序、元資料、三個覆寫旗標、部分失敗不移除、重複影片保留、
  來源失效；比對鍵兩種；完整性三條件各缺一個；中途停下與頁內例外後再刷新；代際與觸發者過期不寫；刷新中途刪歌單；`writable`；FIFO 鎖與例外釋放鎖；插件停用）、
  `playlist_importer_test.dart`（問哪個插件、`mixSeed`、僅元資料來源、第一頁失敗不建列、同一網址同時匯入只建一列、重新匯入不覆寫設定、重新匯入時來源失效記在那一列）、
  `playlist_remote_repository_test.dart`。

## 播放

`lib/playback/`（ADR 0018）。怎麼改後端、寫播放測試、跑實機驗證：
`.trellis/spec/app/playback/index.md`。控制器的入口：臨時播放（`playTemporary`）、收聽直播（`playLive`、`stopLive`，見下方「直播」）、開始 Mix（`startMix`，見下方「Mix」）、加入
（`addToQueue`）、下一首播放（`playNext`）、跳到（`jumpTo`）、移除（`removeAt`）、拖曳
（`move`）、移到下一首（`moveToNext`）、清空（`clear`）、隨機（`setShuffle`）、循環輪轉（`cycleLoopMode`）、播放與暫停、
上一首與下一首、seek、音量（`setVolume`）、靜音（`toggleMute`）、速度（`setSpeed`）、輸出裝置
（`selectOutputDevice`）。佇列、循環、隨機與音量持久化（見「持久化與啟動恢復」）。

- `PlaybackController` 是 UI 唯一的播放入口，也是 `PlaybackState` 唯一的寫入者；
  `QueueModel`、`PlaybackSession`、`routePlaybackEvent`（`playback_event_router.dart`，純函數）、
  `decideRecovery`（純函數）只回報。沒有閘門，review 時看。
- `just_audio`、`media_kit`（含 `media_kit_libs_*`）與 `audio_session`（Android 的音訊中斷，
  後端自己聽）只准在 `lib/playback/backends/` import。閘門：lint `fmp_layer_imports`
  （`layer_imports_test.dart` 的 `test_playbackEnginesOutsideTheBackends`：同前綴的
  `lib/playback/backends_helpers.dart` 也報；`test_playbackEnginesInTheBackends`：後端目錄與
  `media_kitchen`、`audio_sessions` 這類相似套件名不報）、`tool/lint_sentinel.dart`。
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
- 插件停用或移除（從 `PluginRegistry` 的清單拿掉）時，它的曲目照「音源未安裝」跳過：組裝點把清單的
  每次改變交給控制器（`pluginChanges`），session 放掉屬於那個插件的前瞻、清掉後端的
  （`Look-ahead dropped: source unavailable`），之後要準備前瞻時先查插件（單曲循環的下一圈不經快取，
  不查就會重播）、解析中的前瞻回來時再查一次；所以引擎不會自己接上它，
  手動下一首也拿不到它，到那首時 `StreamResolver` 先查插件、快取裡的那筆也不給，回 `Unsupported`、
  照恢復表立即跳過（解析器的 `Unsupported` 只有通用訊息；`app_shell.dart` 在錯誤是 `Unsupported` 且 `error.pluginId` 的音源不可用時，把提示的原因換成 `sourceUnavailableProvider` 的「音源已停用」／「音源未安裝」，其他錯誤不動。閘門：`app_shell_test.dart` 的 `a song of a disabled source is skipped with that as the reason`、`stopping at the only song of a disabled source says so`）。
  正在播的那一首不停（單曲循環的下一圈算下一次播放，不播）。閘門：`playback_controller_test.dart` 的
  `a source that was disabled or removed` 群組、`stream_resolver_test.dart` 的 `a cached stream is not
  given out once its plugin is disabled or removed`、`playback_providers_test.dart` 的 `a plugin that
  is disabled or removed`（停用與移除各一例，經真的 `PluginRegistry`）。
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
- 進度 stream（`PlaybackController.progress`，來自 session）一直是目前這首的：後端只保證播放中與 seek 後回報
  （`AudioBackend.progress`），ExoPlayer 對暫停中開的來源到按播放前都不回報（just_audio 0.10.6 的
  `positionStream` 只在播放中與引擎事件時發出，載入的那些事件落在 `JustAudioBackend` 的清單修改期間、被丟掉；
  M2 驗收 2026-10-08 實機：臨時播放結束、佇列那首只載入不播，進度條停在臨時曲目的位置與時長）。所以 session
  在開始要求一首（`beginRequest`）與交給後端（`_open`）時先發出起點，不等後端；時長在同一首重開（重試、換
  候選）時沿用，換了一首是 `null`。假後端照 ExoPlayer 的形狀：暫停中 `open` 不回報位置。閘門：
  `playback_controller_test.dart` 的 `progress of the current song` 群組（暫停中換歌、解析中、解析中 seek、
  重試沿用時長）與 `temporary play` 群組的 `a queue that was paused reports its own start…`。
- 臨時播放中不準備前瞻（舊版「臨時播放不預取」）：臨時曲目播完回到的那一首要從快照的位置
  開始，不能由引擎從頭接上。閘門：`temporary play` 群組的 `prepares no look-ahead…`。
- 單曲循環：前瞻是目前這首的同一份解析結果（`NextTrack` 的位置為 `null`），引擎無縫重播，
  交接時佇列不動；網址快過期時由前瞻原本的過期計時器重新解析。前瞻沒來得及接上時路由器給
  `RepeatTrack`，從頭再開（網址從快取拿）。臨時播放中循環的是臨時曲目，模式維持
  `temporary`。閘門：`loop one` 群組（兩圈只有一次 `Resolving stream`、快過期時重新解析、
  臨時播放中仍回到快照）、`playback_event_router_test.dart` 的 `completed under loop one…`。
- 網址快取（ADR 0016 §決定 5）在 `StreamResolver` 內、只在記憶體，前瞻與播放都經它：
  - 鍵是曲目鍵（含分 P）加上送給插件的偏好（音質、格式偏好）；最多 64 筆，淘汰最久沒用的。
    閘門：`stream_resolver_test.dart` 的 `the key is the whole track key…`、`keeps the 64 most
    recently used streams`。
  - 偏好在每次解析時經 `streamPreferencesProvider` 讀一次（組裝點訂閱它，改設定不重建控制器）：
    換了偏好就是另一個鍵、重新解析，換回來時舊的那筆還有效就照用。音質原樣送給插件；格式偏好
    把那兩個編碼依偏好排到最前面，其他格式照平台的順序接在後面，平台不能播的編碼不加。已經準備
    好的前瞻不因改偏好而重新解析：下一首可能還是舊的偏好，沒有閘門，已知限制。閘門：
    `stream_resolver_test.dart` 的 `preferences` 群組、`playback_controller_test.dart` 的 `after
    the quality changes the track is resolved again with it`、`playback_controls_test.dart` 的 `a
    quality and a format chosen here go to the plugin`（經 `ShellHarness` 的接線；組裝點
    `playback_providers.dart` 那幾行沒有閘門，review 時看）。
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
  `PlaybackStopped`（停在 `Failed`，帶連著播不了的首數）、`PreviewPlaying`、`OutputDeviceFailed`。
  外殼以一個 `ref.listen(playbackEventsProvider)` 轉成提示：跳過與只有一首播不了時以 `Toaster.error` 的
  `sentence` 說是哪一首、什麼原因（ADR 0013 類別表的訊息），去重是 `Toaster` 的同類同音源 5 秒；
  連續播不了停下時是一則警告「連續 n 首無法播放」（每首的原因已在跳過時提示過，同類的被去重，
  用錯誤提示會被去重吞掉）。閘門：`app_shell_test.dart` 的 `playback toasts` 群組、
  `playback_controller_test.dart` 斷言事件的案例。
- 音量與速度（E19，design §7.6）：控制器交給後端，後端在 `open` 之前收到也生效、換來源與接上
  前瞻後維持；速度夾到 0.5–2.0、音量 0–1（`backend_rules.dart` 的 `clampSpeed`（定義在 `lib/domain/playback_speed.dart`、由它轉出）、`clampVolume`，
  兩個後端都經過）。速度不持久化，控制器對外給 `speed`、`speedChanges`（`playbackSpeedProvider`，播放頁的「⋯」與 `NowPlayingPublisher` 讀）；音量與靜音隨佇列存（見「持久化與啟動恢復」）。靜音只把後端的音量設成 0，
  控制器的 `volume` 不變，取消靜音回到它；靜音中 `setVolume` 就是取消靜音（舊版拖音量條的
  行為）。閘門：後端契約的 `volume and speed set before open hold across a handover and a new
  source`（2 倍速時兩首在一首半的時間內播完：引擎真的照速度播）、`the speed is clamped…`；
  `backend_rules_test.dart` 的 `speed and volume`；`playback_controller_test.dart` 的 `volume,
  mute and speed` 群組。
- Android 的音訊中斷與拔耳機（design §7.6、舊版 `playback.md` §3.7）：`JustAudioBackend` 以
  `handleInterruptions: false` 關掉 just_audio 的內建處理（0.10.6 在 duck 結束時無條件把音量乘 2），
  自己聽 audio_session：duck 只把引擎輸出乘 0.5，不改使用者音量、不通知上層；duck 以外的任何
  中斷事件都還原（`duckedAfter`：duck 中轉成暫停類或 unknown 類中斷時，audio_session 之後報的是
  暫停類的結束或什麼都不報，等不到 duck 的結束）。暫停類中斷發 `Interrupted(transient: true)`，
  unknown 類（`AUDIOFOCUS_LOSS`：別的播放器開始播，之後沒有結束的事件）發 `Interrupted(transient: false)`，
  暫停類結束發 `InterruptionEnded(resume: true)`，拔耳機發
  `BecameNoisy`（對應表是 `respondToInterruption`）。焦點的取得與釋放仍由 just_audio 的
  `handleAudioSessionActivation` 管，「換歌不放焦點」不變。暫停與續播由路由器決定、控制器執行：
  在出聲時中斷才暫停並記下「因中斷而暫停」；中斷結束只續播這種暫停；使用者在中斷期間按了播放或
  暫停、拔耳機都清掉它（拔耳機後不從喇叭續播）；中斷期間按下一首不清掉它，新的那首載入後停著、
  中斷結束時續播；永久失去焦點只暫停、不記「因中斷而暫停」，來電中又失去焦點的也清掉它（等不到
  結束，留著的話系統媒體控制一直裝成在播放、前景服務不放）；`Idle` 時的中斷不會在結束時開始播放；等重試時
  的中斷取消那次重試，結束時從原位置重新開流。Android 8 起系統自動 duck
  （`setWillPauseWhenDucked(false)` 是 audio_session 的預設），App 收不到 duck 的回呼，所以實機
  幾乎看不到 duck 那一支。控制器對外給 `pausedByInterruption`、`pausedByInterruptionChanges`
  （只在改變時發出，唯讀；`NowPlayingPublisher` 讀，見 § 系統媒體控制）：中斷暫停起為真，使用者
  按播放或暫停、拔耳機、停下為假；中斷結束的續播發出後到後端報出播放之前（狀態仍是 `Paused`）
  仍為真（`_resumingFromInterruption`），否則系統那邊會在續播前一刻先看到暫停。閘門：
  `backend_rules_test.dart` 的 `audio interruptions (Android)`、`playback_event_router_test.dart` 的
  `output events`、`playback_controller_test.dart` 的 `audio interruptions` 群組（名稱含 `flag` 的五個案例，
  其中兩個是永久失去焦點）。`JustAudioBackend` 接
  audio_session 的那幾行在 `flutter test` 裡建不起來，沒有自動閘門：實機以模擬器的來電觸發
  （見 spec）。
- 輸出裝置（只有 Windows，design §7.6）：`AudioBackend.outputDevices` 列 mpv 的
  `audio-device-list`，不含 `auto`（系統預設是 `null`）與 `openal` 這類 mpv 內部的輸出
  （`isSelectableOutputDevice`，`backend_rules.dart`，擁有者 2026-10-07；`MediaKitBackend` 轉換清單時
  套用，那一行在 `flutter test` 裡建不起來，沒有直接的閘門，實機看選單），選擇是 `audio-device`。
  控制器對外給 `outputDeviceState`／`outputDeviceChanges`（清單與目前選的，`null` 是系統預設；
  選擇、記住的裝置套用、失敗改回預設都會發出），播放列的選單讀它。記住的裝置
  （「播放」組的 `output_device_id`＝mpv 的裝置名、`output_device_name`＝描述）在清單第一次
  就緒時套用一次，之後插拔不蓋掉當下的選擇；不在清單裡就用系統預設、偏好不清掉；使用者在清單
  就緒前選過就以使用者的為準。`selectOutputDevice` 選擇並寫進偏好（`null` 清掉）。閘門：
  `playback_controller_test.dart` 的 `output devices` 群組（含 `the state follows the list…`）、
  `backend_rules_test.dart` 的 `isSelectableOutputDevice`；後端契約的 `output devices follow the
  platform declaration and choosing the system default keeps playing`。組裝點
  `playback_providers.dart` 讀寫偏好的兩行沒有閘門，review 時看。
- 輸出裝置失敗（design §7.5）：mpv 只記 log，一次失敗是一串 `[ao/wasapi]`、`[ao]`、
  `[cplayer] Could not open/initialize audio device -> no sound.`（`isOutputDeviceFailure`，樣本是
  2026-10-07 錄的），`MediaKitBackend` 只發一次 `OutputDeviceFailed`（開流、播放、換裝置時重來）；
  `[cplayer]` 那一行也進 media_kit 的 error stream，後端不把它算成來源開不起來（舊專案 issue
  #41）。mpv 同時結束目前的檔案，`completed` 可能比這幾行早到（實測早 1 毫秒），先成了提前結束、
  排了重試。所以控制器收到時暫停並放掉來源（換一代：已經排好的重試、晚到的結束都丟掉，舊專案
  issue #106），記下位置，按播放時從那裡重新開流（mpv 才會再開一次輸出）；不跳過；發
  `OutputDeviceFailed` 事件，外殼提示一則警告。`Idle`、`Failed` 時只提示。失敗的是選過的裝置時
  （記住的或使用者選的），來源停下之後這次執行改用系統預設輸出（`selected` 變 `null`），按播放才不會
  再撞同一個裝置；記住的偏好不清（`saveOutputDevice` 不呼叫），下次啟動或清單第一次就緒時照常套用。
  失敗的本來就是系統預設時不選。事件的 `fellBack` 分這兩種，提示依它：改用了是「音訊輸出裝置無法使用，
  已改用系統預設」（`outputDeviceFellBack`），本來就是系統預設是 PR 13 的「…已暫停播放」
  （`outputDeviceFailed`）。已知：先到的提前結束已經在錯誤歷史記了一筆 `Stream ended early`。閘門：
  `backend_rules_test.dart` 的 `isOutputDeviceFailure`（錄下的行與反例）、`playback_controller_test.dart`
  的 `a failed output device` 群組（兩種先後，各例斷言 `fellBack`）與它的 `falls back to the system
  default output`（使用者選的、記住的、系統預設本身失敗、`Idle`）、`app_shell_test.dart` 的 `a failed
  system default output says playback paused` 與 `a failed output device falls back to the system
  default`（提示文字、偏好還在、按播放不再選回）。
  `MediaKitBackend` 接 log 的那幾行沒有自動閘門（播放中拔裝置要實機）。
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
- 佇列：移到下一首（`QueueModel.moveToNext`，佇列選單的「下一首播放」）等於移除再以 `playNext` 加回，但項目是
  同一個實例（`QueueStore` 以實例判斷換了一首）、不檢查上限：移到目前這首之後、接在連續「下一首播放」的後面
  （`_playNextRun` 加 1，已在那一串裡的移到串尾）；隨機時它的排序也移到同一處，所以下一首（或接著的那幾首
  之後）一定播它，連本輪已播過的也是，這和 `move` 的「只換歌、不改排列」不同；臨時播放中排在快照那首之後；目前
  這首（`currentIndex`，臨時播放中是快照那首）不做事；空佇列沒有合法的位置，同其他編輯拋 `RangeError`。控制器做完呼叫 `_queueEdited()`（前瞻改指新的下一首、`QueueStore`
  存檔）。閘門：`queue_model_test.dart` 的 `move to next` 群組與 `a seeded run of edits…`（種子測試的操作
  之一，每個位置一輪恰好播一次；本輪已播過的那首被移後，先從本輪的紀錄拿掉，播到時再算一次）、
  `playback_controller_test.dart` 的 `moving a song to play next`、`queue_store_test.dart` 的 `moving a song to
  play next is written` 與隨機序列。
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
- 持久化與啟動恢復（ADR 0018 §決定 10、design §7.7）在 `queue_store.dart` 的 `QueueStore`：
  - 它不碰引擎也不改控制器的狀態，只聽控制器的佇列、狀態、`seeks`、`volumeChanges` 與 App 的生命週期，
    把變動轉成 `QueueRepository.write` 的差量（前後各相同的列不動、中間換掉、其後平移）。連續的觸發合併，
    寫入一個接一個；寫失敗只經 `log.report` 記下，下一次觸發以資料庫實際的樣子重算（閘門：`a failed
    write is reported and the next change writes what it missed`）。恢復完成前不寫，空佇列才不會蓋掉
    上次的資料；恢復前使用者已經動了佇列時不恢復、存的位置作廢（閘門：`a queue built before the
    restore finished…`）。組裝在 `playbackControllerProvider`：建好控制器就 `attach`，
    重啟倒退的兩個設定在恢復時讀一次（等資料庫的值）。閘門：`queue_store_test.dart` 的 `writing`、
    `restoring` 與 `the whole path against the queue model`（固定種子的隨機操作，每一步讀回等於控制器的
    佇列，最後重啟比對）、`playback_providers_test.dart`（接線）。生命週期進組裝點的那兩行沒有閘門，
    review 時看。
  - 存檔時機：佇列操作當下；播放中每 10 秒（`Timer.periodic`，只在 `Playing` 時開，`QueueStore` 是
    ADR 0018 §決定 11 的播放模組）；暫停、seek、App 進入 `hidden` 或 `paused`；音量與靜音改變。
    閘門：`writing` 群組逐項斷言（含 10 秒只在播放中、暫停之後兩分鐘不再寫、`inactive` 不寫）。
  - 換了一首就從 0 開始，狀態回到 `Idle`（播完、清空）也是 0；「換了一首」比的是目前那個佇列項目
    本身（`QueueModel` 編輯時沿用實例），不是位置或曲目鍵：拖曳讓目前這首落在差量的中間段時位置照留。
    `Idle`、`Failed` 時的位置存檔不動：
    重啟恢復後還沒按播放時控制器的位置是倒退過的，存回去會越退越多。閘門：`a new song starts at 0…`、
    `dragging songs around the current one keeps its position`、`a drag across the current song after a
    restart keeps the stored position`、
    `nothing is saved over the stored position while idle after a restart`、`restarting twice without
    playing keeps the rewind from adding up`。
  - 臨時播放不持久化（design §12 第 6 條）：它期間資料庫停在佇列那一首與進入時的快照位置，各種存檔
    時機都不覆寫；重啟回到佇列的那個點。閘門：`a temporary play leaves the snapshot in the database`、
    `a restart after a temporary play returns to the snapshot`。
  - 不變式：存的 `player_state.position` 永遠是使用者真正的位置，不是倒退過的起點；重啟倒退每次重啟只在
    恢復時套用一次。恢復的那一首還沒真的播出來之前（`QueueStore` 的 `_holdingRestored`），store 不拿控制器的
    位置覆寫它：位置存檔（含暫停、背景）、`Idle` 歸 0、臨時播放的快照位置都不動它。到佇列自己的那一首
    進入 `Playing`（臨時曲目的 `Playing` 不算）、或目前這首換了（含清空）才結束；使用者在這期間 seek
    是真的位置，照存。臨時播放期間控制器另外收著恢復的位置（`_keptRestored`），臨時播放結束、佇列仍
    停著時放回去，所以按播放仍從倒退後的位置開始（`startedFromRestore` 為真）；佇列那一首換了（跳到、
    移除、清空）就作廢。閘門：`restoring` 群組的 `a temporary play while idle after a restart does not
    store the rewound position`、`closing before the restored song is audible keeps the stored position`
    （倒退大於 0，停在 `Loading` 時進背景）、`once the restored song plays, its real position is stored`、
    `a seek before playing is a real position and is stored`、`the restored position survives a temporary
    play…`、`the kept restored position is dropped when the queue song changes…`、`jumping to a song
    during the temporary play drops the kept restored position`、`restart, temporary play, it ends, restart
    again: the rewind is applied once`（端到端：存 83 秒、倒退 10 秒，重啟兩次後仍是 83 與 73）。
  - 啟動恢復（`PlaybackController.restore`）：狀態是 `Idle`，帶佇列、目前這首、循環、隨機排列、音量與
    靜音；不解析、不預取、後端沒有來源。按播放才開始，從「存的位置 − 重啟恢復倒退秒數」（不低於 0）開始，
    「記住播放位置」關著時從頭；只有恢復後的第一次播放用這個位置（`startedFromRestore` 為真，
    「Track requested」的 log 帶 `restored`，M2 PR 15 的播放歷史不記這一次）。資料讀不回來（壞掉）時
    記 error（`Stored playback could not be read; starting empty`）、清掉存的佇列與播放狀態（`tracks` 留著，
    交給孤兒清理）、從空的開始，之後照常寫。閘門：`restoring` 群組的 `stored data that cannot be read is
    dropped and reported`。其他閘門：`restoring` 群組（四種「記住位置 × 倒退」組合、倒退超過
    位置、沒有存過、資料壞掉）、`QueueStore.restoredPosition` 的單元測試。
- 播放歷史（design §7.8）：控制器只對外報「這一首算一次播放」（`PlaybackController.plays`，帶 `TrackInfo` 與
  `clock.now()`），`PlayHistoryRecorder`（`lib/playback/`，照 `QueueStore` 的分工，控制器不碰資料層）聽它、
  經 `PlayHistoryRepository.record` 寫進 `play_history`，保留筆數每次寫入時讀「播放」設定。一次「開始一首」在
  第一次出聲（`MarkReady` 且在播）時算一筆，之後同一次開始裡不再算：
  - 算：換歌（下一首、上一首、跳到、播完往下、移除正在播的那首）、臨時播放、前瞻接上（交接當下算）、單曲循環的每一圈
    （前瞻接上與 `RepeatTrack` 兩條路）、暫停中換到的歌（按播放、出聲時才算）。
  - 不算：同一次開始裡的重試、重新解析、換候選；啟動恢復後的第一次播放（含恢復後先臨時播放、再按播放那次）；臨時播放
    結束回到佇列那首（`_beginTrack(countsAsPlay: false)`）；「上一首」在播超過 3 秒回到開頭（是 seek）；暫停後繼續、
    seek；輸出裝置失敗後按播放；一直沒出聲就換走或失敗的那首（跳過的歌不算）。
  - 寫入失敗只經 `log.report`（tag `play-history`）記下，不提示、不影響播放，後面的寫入照常（一筆一筆依序）。
  閘門：`playback_controller_test.dart` 的 `play history counting` 群組（`counts`、`does not count`、`after a
  restart` 三組，每個算與不算的情況各一例；含 `every lap of loop one by look-ahead…` 與 `…that restarts the song
  (no look-ahead)`）、`play_history_recorder_test.dart`（順序、保留筆數、`a failed write is reported…`、
  `nothing is written or reported after dispose`）、
  `playback_providers_test.dart` 的 `play history`（組裝點接線與設定讀取）。
- 直播（`playLive`／`stopLive`，ADR 0018 §決定 9、ADR 0031 §決定 7、M3 design §9.4；畫面見 § 介面的「直播版」）。契約：
  - **模式**：`QueueMode.live`，`QueueState.live`（`LivePlay`：目標加進入時的佇列快照）與臨時播放互斥；進入時記快照（佇列目前位置、播放位置、
    是不是在播），已在臨時播放或直播時只換內容、**快照維持第一次進入時的那份**；回到佇列的規則就是臨時播放的（含「臨時播放回佇列倒退秒數」，
    design §9.4 的更正）。直播時 `QueueState.current` 是 `null`（直播不是曲目；佇列照舊在 `entries`），
    `hasNext` 為假、上一首、下一首、seek 都不做事；在佇列點一首（`jumpTo`）、臨時播放、清空都會離開直播。
  - **不持久化**：`QueueStore` 把直播和臨時播放一樣當「佇列以外」（`QueueState.isOutsideQueue`／`returnSnapshot`），各種存檔時機不覆寫資料庫，
    也沒有 `player_state` 的直播欄位；直播中關 App，重開回到進入時的佇列。直播不排前瞻、不算播放歷史。
  - **取流**：`StreamResolver.resolveLive` 每次都問插件（不進網址快取）；`PlaybackSession.resolveLive` 先停掉目前的來源，同音樂的 `resolve`。
    **開直播時進行中的音樂解析結果以代際丟掉**（`beginRequest` 換代），不播出也不再因它發解析（ADR 0018 §決定 6 的更正）。
  - **暫停就是停止串流**：`pause()` 換代、放掉來源、狀態 `Paused`；再按播放重新 `resolveLive`（`Idle`、`Failed` 時按播放也是重新取流）。
  - **失敗與提前結束**（`PlaybackSnapshot.live` 讓路由器把「來源結束」不論原因都當提前結束）：`decideLiveRecovery`（`recovery_policy.dart`，純函數）決定——
    網路類的失敗（解析時的 `NetworkError`、`RateLimited`，開不起來、中斷、提前結束、緩衝飢餓）離線時等網路（不計次數）；在線時重連次數沒用完就 `ConfirmThenReconnect`：**先問 `liveStatus`**，是 `live` 才等 1／3／9 秒重新取流（共 3 次，
    每次失敗都再問一次；正常收聽 10 秒後次數歸零），不是 `live` 停在「直播已結束」，拋錯停在「查詢失敗」（D10，**不當成未開播**）；用完 `LiveGiveUp`＝直播已結束；
    解析時插件說無法取得、需登入等重試不會好的錯誤 `LiveStop`＝`Failed`，不重連。
  - **給畫面的狀態**：`PlaybackController.live`／`liveChanges`（`playbackLiveProvider`）是 `LiveInfo`（目標、最新的標題、主播、封面、人數、`LivePhase`：
    `listening`／`ended`／`statusFailed`）；已收聽時間是進度 stream 的位置（每次重新取流從 0 起算）。`ended` 的 `PlaybackState` 是 `Idle`、
    `statusFailed` 與 `LiveStop` 是 `Failed(error)`，重連是 `Retrying`；三種都**留在直播模式**，按播放重試，`stopLive()` 才回佇列。
  - **`live-info`**：`playLive` 時經建構子的 `registerLiveInfoJob` 登記到排程器（`liveInfoJobId`＝`live-info`、`liveInfoInterval`＝固定 1 分鐘、所屬插件
    是直播間的插件，組裝點 `playbackControllerProvider` 接上），每次到期呼叫 `liveStatus` 更新 `LiveInfo` 的標題、主播、封面與人數；失敗只記 warning、不中斷播放、排程器不退避；
    離開直播（或停在已結束、查詢失敗）時移除；換到同插件的別的直播間不重新登記。控制器釋放時（`playbackControllerProvider` 重建，例如改 log 層級）
    也移除：組裝點用登記時拿到的排程器、在 onDispose 回呼結束後才移除（回呼裡不能碰別的 provider），不然舊控制器的工作會每分鐘失敗一次。
    工作 id 固定，上次成功時間照樣寫進 `scheduler_runs`：上次成功不到 1 分鐘就重新登記（停了又開、換到別的插件的直播間）時不會馬上跑，等到期（沒有閘門）。
  - **Debug 頁與診斷包**：直播時 `PlaybackDiagnostics.trackKey`／`pluginId` 是直播間（`插件:房間`），`queue.live` 為真、`currentIndex` 是回到的那一首；
    佇列分頁不標任何一列是在播的（同臨時播放，`QueueState.isOutsideQueue`）。
  閘門：`live_playback_test.dart`（進入記快照停止回佇列、回佇列照倒退秒數、暫停原本停著的佇列仍停著、換台快照不變、點佇列離開、上一首下一首 seek 不動、臨時播放接手同一份快照、
  暫停＝停止再播放重新取流、`liveStatus` 先問、重連間隔 1／3／9 秒共 3 次與用完、`offline` 不重連、拋錯顯示查詢失敗不重連、離線等網路、10 秒後次數歸零、
  取不到流不重連、解析中開直播音樂結果被丟掉且 `resolveStream` 次數不變、`live-info` 登記／更新／失敗不中斷／結果過期被丟、`decideLiveRecovery` 的表）、
  `live_info_wiring_test.dart`（真的排程器：登記後馬上一次、之後每分鐘、停止後不再跑；收聽中重建控制器後工作不在）、
  `live_playback_test.dart` 的 `the playback diagnostics report the room…`、`player_page_test.dart` 的 `in a live room no queue row is marked current`、`queue_model_test.dart` 的 `live play`、
  `playback_event_router_test.dart` 的 `a live room`、`queue_store_test.dart` 的 `a live room is never stored…`／`a restart during a live room…`。
- Mix（`startMix`，ADR 0031 §決定 8–11、M3 design §10；入口在曲目選單，見 § 介面）。契約：
  - **模式**：`QueueMode.mix`＝`QueueState.mix`（`MixIdentity`：插件 id、`mixId`、標題、`cursor`）有值，且不在臨時播放或直播（那兩個期間 `mode` 是
    它們，`mix` 仍在，結束回到 Mix 佇列）。開始時 `MixSession.start` 向插件要第一批，`QueueModel.startMix` **取代整個佇列**（原佇列不另存、
    臨時播放與直播就此結束、隨機關掉；循環是「全部」就改成「關」，Mix 中 `cycleLoopMode` 只在關與單曲之間輪轉，`restore` 的 Mix 同樣處理，ADR 0031 §決定 9 的補充）；插件的錯誤原樣丟出、佇列不動，由 UI 顯示。
  - **被拒絕的操作**：隨機（`setShuffle(true)`）、加入佇列、下一首播放在 `QueueModel` 被拒（`append`／`playNext` 回 `false`、隨機不開），
    控制器的 `_add` 先擋並**不發 `QueueFull`**（入口本來就停用，不是佇列滿了）。拖曳、移除單首、佇列選單的「下一首播放」（移到下一首，是重排）照常。
    清空佇列或移除最後一首就退出 Mix（`mix` 清掉、一般佇列）；`replace` 也是。
  - **修剪**：`QueueModel._trimMix` 在每次發佈佇列時，已播（排在目前這首之前）超過 `maxMixPlayed`＝100 首就刪最舊的；剛好 100 首不刪，目前這首與
    還沒播的不動。佇列項目沿用實例，持久化的差量（`QueueStore`）因此是「前面少一段、其後平移」。
  - **補歌**（`lib/playback/mix_session.dart`，**不經排程器**，是播放核心的事件，請求經 `StreamResolver.mix`／`PlaybackSession.mix`）：每首開始時
    （`_beginTrack` 與前瞻接上）之後只剩 1 首以下就呼叫 `mix({mixId, cursor})`；`cursor` 空就以佇列最後一首當 `seed`，Mix 身分換成回傳的
    `mixId` 與標題。回來的曲目以曲目鍵去重（`extendMix`）後附加。**標題只在回傳的 `mixId` 與目前的不同時才換**：續取的批次插件不一定給得出原標題
    （重啟後沒有地方記，YouTube 插件回 `Mix`），照原本的。同時只有一個補歌；補到之前 Mix 被換掉或退出（`MixIdentity` 不相等）就丟掉結果。失敗或去重後
    一首都沒有時只 `log.report`（tag `mix`），不提示；**同一個佇列項目內不重試**，下一首開始再試。插件停用或移除時不補（靜默），它的曲目照一般的
    「音源未安裝」跳過。
  - **播到底**：佇列沒有下一首而補歌還在跑時，控制器停在 `Loading`、等補歌結束（`MixSession.whenIdle`）再決定：有下一首就往下播，沒有才停在 `Idle`；
    等的期間使用者換了歌（播放代變了）就不再接手。最後一首播不了而要跳過（`SkipTrack`）時同樣先等補歌，有下一首才跳、沒有才 `Failed`
    （只有一首的 Mix 照連續跳過的上限直接停，ADR 0018 §決定 7）。
  - **持久化與恢復**：`player_state` 存 `mode` 與 `mix_*`（見 § 資料層），`QueueStore` 照佇列寫入、恢復時交給 `restore(mix:)`（存的資料有 Mix 又開著隨機時以 Mix 為準）；
    重啟後是 `Idle`，按播放那首開始時照常補歌（`cursor` 空一樣換種子）。
  閘門：`queue_model_test.dart` 的 `mix` 群組（取代佇列、拒絕、清空退出、修剪 100／101、`extendMix` 去重與上限、臨時播放與直播回到 Mix、恢復）、`mix_session_test.dart`
  （補歌時機、續取／換種子、標題規則、單一補歌、同一首不重試、結果過期丟掉、`whenIdle`、開始）、`mix_playback_test.dart`（控制器上的三批與換種子、
  被拒絕的操作不發事件、臨時播放回到 Mix、播到底等補歌與其三種結果、最後一首被跳過時等補歌的兩種結果）、`queue_store_test.dart` 的 `a mix` 群組（寫入、補歌後的 cursor、修剪與補歌同一次寫入的差量、臨時播放與直播期間身分仍在資料庫、重啟恢復、舊列的 `mode` 為空）。
- 系統媒體控制（design §8.2）：`NowPlayingPublisher`（`lib/playback/`，照 `QueueStore` 的分工，只聽控制器的
  輸出、不改它的狀態）是唯一出口，在 `playbackControllerProvider` 組裝點、平台宣告有 `mediaControls` 而且
  初始化成功時才建。規則：
  - 只在值改變時推（`NowPlaying` 值相等），推送一個接一個、不重疊（等上一次 `publish` 完成）；推送失敗只記
    log，不影響播放。
  - 位置只在狀態改變與 seek 時推（系統依速度自己外推，所以速度改變也推，`NowPlaying.speed` 是控制器的實際速度）；進度 stream 只用來取得時長，播放中不因位置前進而推。例外：平台宣告 `positionRefresh`（Windows 5 秒）時，播放中距上次推送滿該間隔才從進度 stream 重推一次位置。
  - 按鈕依能力推導：有目前曲目才有上一首；播放中、`Loading`、`Buffering`、`Retrying` 是暫停鍵，其他是播放鍵；
    有下一首或循環全部才有下一首。
  - 還沒按播放的 `Idle`（含啟動恢復後）是 `MediaPhase.idle`：系統不顯示通知、不搶前景。
  - 因音訊中斷而暫停（`Paused` 且 `pausedByInterruption`）是 `MediaPhase.interrupted`、`playing: true`、按鈕是
    暫停鍵（Android 的卡片實際畫成緩衝的轉圈，見 § 平台層），位置照暫停（不外推）。理由在 § 平台層的 Android 前景服務：這段期間對 Android 要裝成還在播放，
    前景服務才不會放掉。使用者從通知按暫停時控制器的 `pause()` 清掉旗標，phase 回到 `ready`、`playing: false`，
    前景服務照常放掉；平常的暫停（使用者按的、其他原因）不經這條，耗電行為不變。
  - 封面經 `artworkCacheManagerProvider`（design §4.3）取得本機檔、以 `file://` 交給平台（`artworkFile`，Android 用），晚於
    其他欄位送出；拿不到就不帶封面。同一張的原網址另放 `artworkUrl`，和曲目一起送出（Windows 用，見 § 平台層）。啟動恢復時快取庫與插件清單多半還沒好，組裝點先等它們（`cacheStoreProvider.future`、
    `pluginRegistryProvider.future`）再拿 cache manager：publisher 每首只問一次。
  - 系統指令一律呼叫控制器：播放、暫停、上一首、下一首、seek；停止當作暫停（擁有者決定：位置與佇列保留，
    之後按播放從原處繼續）。
  - 收聽直播時（`queue.live != null`）系統看到的是直播間，不是佇列：標題用 `LiveInfo.title`（`live-info` 更新後跟著變）、
    上傳者是主播、封面取直播間的（`LiveInfo.toTrackInfo`，同一條 `artworkCacheManagerProvider` 路徑）；**沒有時長**（後端回報什麼都不採用）、
    `NowPlaying.seekable` 為假（Android 不給 `seek` 系統動作）、按鈕只有播放／暫停（沒有上一首、下一首）。Windows 的 SMTC 時長為 0、
    上一首、下一首不啟用。閘門：`now_playing_publisher_test.dart` 的 `a live room`（含後端回報時長仍為空、封面取直播間的、停止後佇列那首的時長
    與按鈕回來）、`media_controls_android_test.dart` 與 `media_controls_windows_test.dart` 的 `a live room`。
  閘門：`now_playing_publisher_test.dart`（推什麼、何時推、封面、六種指令含停止＝暫停、`position refresh`、`artwork url`；
  中斷：`a pause by an interruption holds the session as playing`、`the held session never shows paused…`（續播前一刻不先推暫停，
  拿掉控制器的 `_resumingFromInterruption` 會紅）、`pausing from the notification during an interruption…`、`a pause by the user is not held`、
  `a permanent loss of focus is not held`）、
  `playback_providers_test.dart` 的 `system media controls`（組裝點接線、`the artwork of the restored song waits for
  the cache store`）；Android 的通知、鎖定畫面、
  `dumpsys media_session` 與媒體鍵，Windows 的媒體卡片、封面與經工作階段送的指令，都沒有自動閘門，實機驗。
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
  分辨「跟隨系統」。閘門：「只寫改動的欄位」見各組的 repository 測試；`stored` 沒有直接的閘門，review 時看。
- 語言沒設定過時跟隨系統的語言偏好清單（執行中改變也跟）：取清單中第一個對得到
  zh-TW／zh-CN／en 的，全都對不到才用 base locale zh-TW（ADR 0024 §決定 7）。閘門：`appearance_settings_test.dart` 的
  `an unset language follows the system as it changes`、`fmp_app_test.dart` 的 `an unset language follows the system`。
- 「網路」組（`network_settings`）有快取上限（MiB，空＝平台宣告的預設，選項 128／256／
  512／1024）與電台狀態刷新間隔（`radioStatusInterval`：空＝5 分，`0`＝關閉，對外是 `Duration?`，`null`＝關閉；選項
  `radioStatusIntervalOptionsMinutes` 0／1／3／5／10，`setRadioStatusInterval` 收別的值丟 `ArgumentError`；設定頁「網路」組在清除快取之後，沒設定過的 5 分標「（預設）」，閘門 `network_controls_test.dart` 的 `an unset radio interval…`、`picking a radio interval writes only that field`）；
  舊版的快取設定不匯入（ADR 0016 §決定 3）。閘門：`network_settings_test.dart` 的 `the radio status interval`、
  `test/settings/network_settings_test.dart`（改預設後使用者值不變、未設定的跟著預設、清回
  未設定）、`network_settings_repository_test.dart`（`clear` 群組直接查表是 `NULL`、
  `stored format`）。
- 「播放」組（`playback_settings`）的整張表在 M2 PR 10 一次建好（design §3.3 的十個欄位，
  schema v3），repository 的 `write`／`clear` 涵蓋全部欄位；Notifier（`playbackPreferencesProvider`）
  與設定頁接上全部十個欄位：音質（預設高，選項高／中／低）、格式偏好（預設 Opus 優先，
  選項 Opus 優先／AAC 優先，兩者照舊版的預設，見「播放」的網址快取）、記住播放位置（預設開）、
  臨時播放回佇列倒退秒數（預設 10，選項 0／3／5／10／15／30）、跳過試聽片段（預設開，見
  「播放」）、重啟恢復時倒退秒數（預設 0，選項同上，設定頁在「跳過試聽片段」之後；啟動時讀一次，
  見「播放」的持久化與啟動恢復）、播放歷史保留筆數（預設 10000，選項 1000／5000／10000／50000，設定頁在重啟恢復
  倒退之後；寫入時依它裁，`setPlayHistoryLimit` 寫完當下依生效的筆數 `trimTo`，所以改小馬上刪，見「播放」）、輸出裝置（沒有預設：沒設定過就是系統預設；`setOutputDevice` 兩欄一起寫、一起清，
  見「播放」；設定列在 PR 17 的播放列）、切歌時捲到目前歌曲（預設關，設定頁在播放歷史保留筆數之後，見「介面」的
  播放頁佇列）。音質、格式偏好的列舉存
  `high`／`medium`／`low`、`opus,aac`／`aac,opus`（後者與舊版字面相同）。閘門：
  `test/settings/playback_settings_test.dart`、`playback_settings_repository_test.dart`
  （`stored format`、`clear`、只寫改動的欄位）、`test/drift/app_database/migration_test.dart`
  的 v2→v3 兩例、`test/ui/settings/playback_controls_test.dart`（含兩列倒退秒數各寫各的欄位、
  沒記住位置時兩列都停用、`choosing a play history limit writes only that field`、`the scroll switch…`）、`playback_settings_test.dart`
  的 `lowering the play history limit trims the history right away`。
- 「開發者」組（`developer_settings`，ADR 0025 §決定 1、M3 design §3.3）：開發者模式沒設定過時 dev flavor 開、prod 關
  （預設讀 `appFlavorProvider`）；log 層級的生效值是「開發者模式開著 → 存的值，沒存過是建置預設；關著 → 建置預設」，存的值
  不動。建置預設讀 `buildLogLevelProvider`（debug build 是 debug，其他是 info；App 不 override，測試一律 override，因為
  `flutter test` 永遠是 debug build）。關閉開發者
  模式是**一筆寫入**（`DeveloperSettingsRepository.turnOffDeveloperMode`：`developer_mode` 假、`log_level` 與
  `plugin_dev_folder` 清空），監看的一方看不到「模式關了、層級仍是 debug」的中間值；開啟只寫 `developer_mode`。開發資料夾跟著
  變成 `null`，開發中的插件卸載（§ 插件的插件開發工具）。閘門：`test/settings/developer_settings_test.dart`（兩個 flavor 的預設、使用者值優先、關著時
  層級是 info、開啟只寫一欄、關閉的下一個值就全部清掉、層級的 setter 只寫一欄與清回）、
  `developer_settings_repository_test.dart` 的 `turning developer mode off` 群組（`is a single write`）；兩種建置的預設與生效值：
  `developer_settings_test.dart` 的 `an unset log level is the build default…`、`the stored log level counts only while developer
  mode is on…`、`in a debug build the notifier defaults to debug`。
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
  `locale_handling: false`，slang 不產生全域 `t`／`LocaleSettings`，語言狀態只有外觀設定一份。沒有閘門，review 時看。
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
  `Toaster` 同步送出：看狀態變化跳提示時在 `ref.listen` 的 callback 呼叫，不在 `build` 裡（沒有閘門，review 時看）。
- 提示與錯誤詳細頁（`lib/ui/errors/error_detail_page.dart`，ADR 0023 §決定 4，M3 design §13）：
  - `Toaster.error` 的動作（每則最多一個）：呼叫端給的 `action` 優先；沒給時開發者模式開著附「詳細」，否則 `Unsupported`、
    `UnexpectedError` 附「回報」，其餘沒有；`log.report` 回傳 `null`（層級被濾掉）時沒有紀錄可看，不附。動作開同一個詳細頁，
    頁面是 `rootNavigatorKeyProvider`（`lib/app/root_navigator.dart`，給 `MaterialApp.navigatorKey`）的 Navigator 上推的全螢幕路由，
    `ToastHost` 包在 Navigator 外面，所以頁面之上仍看得到提示。閘門：`toaster_test.dart` 的 `error actions`、`error_detail_page_test.dart`
    的 `the toast actions open this page`、`fmp_app_test.dart` 的 `an error toast opens the detail page through the root navigator`
    （App 裡真的 `toasterProvider` 與 `FmpApp` 的 `navigatorKey`）、`integration_test/toast_layering_test.dart`（詳細頁）。
  - 詳細頁顯示 `ErrorReport` 的欄位（文字可選取）；「複製」複製 Markdown；「在 GitHub 回報」先複製，再以 `UrlOpener` 開
    `endpoints.dart` 的 `newIssueUrl`，**報告內容不進網址**（網址會被瀏覽器記錄、有長度上限）。第一次按先跳「送出前請檢查」
    對話框（repo 是公開的），勾「不再提醒」並繼續才寫 `developer_settings.report_reminder_dismissed`，取消什麼都不做；設定還沒載入完
    時當成沒關過（頁面 `watch` 著 `developerProvider`：Riverpod 3 會暫停沒有人聽的 provider，只 `read` 拿不到值）。平台沒有 `urlOpener` 能力、或開不了時，頁面顯示網址文字讓使用者自己開。報告一律回報到 `1morr/FMP`
    （插件的問題由維護者 Transfer 到插件庫）。閘門：`error_detail_page_test.dart`（複製的是 Markdown、開的網址等於常數且不含報告內容、
    提醒只問一次、取消不開不寫、沒有能力時只複製並顯示網址）、`guidelines_test.dart` 的 `the error detail page`（窄與寬、淺色與深色，
    含提醒對話框）。
  - `.github/ISSUE_TEMPLATE/bug_report.yml`（繁中）：必填「問題描述」「錯誤報告」（`render: markdown`）、標籤 `bug`。閘門：
    `test/github/bug_report_template_test.dart`（解析 YAML，含改壞會紅、改文字與順序不會紅的變異案例）。
- 設定頁的區塊（`SettingsSection`）：第一個是「帳號」，之後外觀、播放、網路是 ADR 0011 的設定組（design §9.8 的順序），
  之後是「插件」、最後是「關於」（帳號、插件、關於不是設定表，M3 design §6.7）；開發者模式下清單最後多一列 Debug，它開 Debug 頁
  （另一個 route），不是區塊。清單本身會捲動（七列在矮的視窗放不下）。帳號頁與插件頁
  自己有捲動的清單（或置中的空狀態），所以不包在設定組那個捲動的欄裡，填滿右側（窄版是點進去的那一頁）。寬版預設選的是
  帳號。閘門：`settings_page_test.dart` 的 `… accounts come first, plugins after network and open the plugin page`
  （1000、400 寬）、`expanded and wider: groups on the left…`。
- 帳號頁（`lib/ui/accounts/`，ADR 0029 §決定 8，M3 design §6.7）：
  - 每個宣告 `login` 的**已啟用**插件一張卡（讀資料庫的已安裝清單，不讀插件清單：沒有這種插件時不建 `CredentialStore`；
    登入時才向插件清單要那個插件）。沒有就是空狀態加「前往插件頁」。區塊一直在，不隨插件有無出現或消失（設定頁的順序與寬版
    預設的第一組不跳）。閘門：`accounts_section_test.dart` 的 `without a plugin that declares login…`、`one card per…`。
  - 登入按鈕是「methods ∩ 這個 App 在這個平台做得到的」（`availableLoginMethods`）：沒有 secure storage 一個都沒有；`qr`
    與 `cookie` 一律有；`webView` 要平台宣告 `loginWebView`。沒有任何一種時寫「這個平台還不能登入」。
    閘門：`accounts_section_test.dart` 的 `availableLoginMethods…`、`one card per…`、`without secure storage…`。
  - 已登入：頭像（帳號列的 `avatar_json`，經那個插件的封面快取）、名稱、狀態（正常／已失效／暫時無法讀取，取自
    `CredentialStore.state`）、「以登入身分瀏覽與播放」開關（`automationRisk` 時附說明）、登出（先確認）；已失效時多「重新
    登入」（只有一種方式時；幾種時照列每一種）；宣告 `refresh` 的插件另有一行「最後刷新：時間，結果」（時間用裝置本地時間與
    `MaterialLocalizations`，同歷史頁）。離線照常可用，登入照送，失敗才在登入對話框顯示離線狀態。閘門：
    `accounts_section_test.dart` 的 `a QR login with the test plugin…`、`an invalidated account…`、`unreadable credentials…`、
    `offline…`。
  - 網頁登入是全螢幕頁（`web_login_page.dart`，`fullscreenDialog`，推在根 Navigator 上：左上角關閉、沒有確認鈕）：整塊是 WebView，載入中
    頂端有進度條，卡住時 WebView 上方是警告色的「登入沒有完成」加「重試」。完成時頁面自己關閉、交回 cookie，**關頁之後**
    才在帳號頁驗證與寫入（design §6.4；頁面開著時設定頁可能換位置重建，那時照樣驗證，只是沒有進度條）。全螢幕頁、裡面是
    平台的 WebView，所以進 `toast_layering_test.dart`（開 `about:blank`，平台沒有登入 WebView 時跳過）。閘門：
    `accounts_section_test.dart` 的 `web login` 群組（蓋住外殼的導覽、只看 `cookieHosts`、登出清 WebView、卡住、重試、重開 App 的提示）。
  - 貼上 cookie 是對話框（`cookie_login_dialog.dart`）：多行輸入框（關掉個人化學習）、「如何取得」的通用步驟（不指名
    音源）與警告；讀不到 cookie 或驗證失敗時留在對話框、輸入不清，錯誤寫在輸入框下（不在 online 時寫離線的原因，不換成
    整塊的離線空狀態，輸入才留得住）。閘門：`accounts_section_test.dart` 的 `pasting cookies…`。
  - 登入時插件以 `CredentialInvalid` 拒絕（`loginVerify` 不接受這次的憑證）不顯示類別表的「登入已失效，請重新登入」——那是
    已存的憑證被拒；QR 對話框與網頁登入的提示用 `loginErrorMessage`（`accounts.loginRejected`），貼上 cookie 用
    `accounts.cookieRejected`。閘門：`accounts_section_test.dart` 的 `a sign-in the plugin rejects…` 群組與 `pasting cookies…`。
  - QR 登入是對話框（`qr_login_dialog.dart`，不是全螢幕頁，所以不進 `toast_layering_test.dart`）：QR 碼一律白底黑點（不跟
    主題，`AppLayout.qrBackground`），過期時蓋遮罩並給「重新產生」，失敗時給「重試」；Esc、取消或點外面關閉並停止輪詢。
    `qr_flutter` 只准在 `lib/ui/accounts/`（`fmp_layer_imports`）。閘門：`closing the QR dialog stops the login`、guideline
    測試的 `the QR login at …`。
- 設定頁依 ADR 0011 的分組（外觀、播放、網路，design §9.8 的順序）：expanded 以上是
  list-detail（左分組、右內容，預設第一組），compact 與 medium 先是分組清單、點進去看內容，
  標題旁的返回鈕與系統返回鍵回到清單；選了哪一組由頁面記著，視窗寬度跨過斷點時不丟。系統返回鍵只有
  外殼的 `PopScope` 一個（見下一條）：它先問設定頁（`SettingsBack.release`）有沒有一組要退回清單，
  外殼以 `IndexedStack` 留著沒選的頁面，所以設定頁只在外殼正顯示它時（`visible`）接住。「網路」組
  顯示快取上限、封面用量（跟著索引變動）與「清除快取」：確認後清快取庫並清 Flutter 的
  `ImageCache`（`clear` 加 `clearLiveImages`；畫面上正在用的圖只有後者清得掉）；清除失敗記
  error、不報成功。閘門：`test/ui/settings/settings_page_test.dart`（寬、窄兩種版面、跨斷點、
  系統返回鍵、`400 wide: a group left open does not hold the back key on another page`）、
  `network_controls_test.dart`（預設標明、選擇寫入、用量跟著變、取消不清、清除後索引與檔案與
  `ImageCache` 都空、清除失敗）。
- 返回鍵（擁有者決定 7，design §9.1，ADR 0033 §決定 5）：播放頁、面板、對話框是根 Navigator 上的 route，
  Navigator 先關最上面的；外殼是 `PopScope(canPop: 在第一個目的地而且它沒有內頁)`，依序：退出目前目的地巢狀
  Navigator 的內頁 → 窄版設定頁點進某一組時回到分組清單 → 不在第一個目的地時回到第一個（首頁）→ 在第一個時放行，
  Android 端由 `MainActivity.popSystemNavigator` 退到背景（見 § 平台層）。內頁的 route 在巢狀 Navigator 裡、
  不在根 Navigator 上，所以系統返回鍵（含 predictive back）一定先到外殼的 `PopScope`；`canPop` 跟著內頁的增減重建
  （每個巢狀 Navigator 一個 `NavigatorObserver`），有內頁時 Android 不預覽「離開 App」。不要在頁面內另放
  `PopScope`（也不用 `NavigatorPopHandler`，它就是一個 `PopScope`）：同一次返回所有 `PopScope` 的 callback 都會執行，
  會和外殼同時動作（「不另放」沒有閘門，review 時看）。閘門：`app_shell_test.dart` 的 `the back key`（在搜尋、音樂庫、
  電台、設定按返回回到首頁；在首頁放行）與 `nested navigation`（先退內頁再回首頁、首頁的內頁先退才放行、對話框與播放頁
  先關）、`settings_page_test.dart` 的窄版返回案例。
- 淺色與深色主題下，示範畫面、四種提示，以及外殼裡的搜尋頁（搜尋前、有結果加播放列、沒有介面
  或連不上時搜尋失敗、直播間模式的結果）、首頁（空的、最近播放加播放列）、音樂庫（空的、有歌單的清單與收起面板的格狀、
  卡片選單、新增歌單的對話框、刪除的確認框）、歷史頁（空的、有紀錄加播放列；從音樂庫開，標題有返回鈕）、電台頁（空的、四種狀態）、播放列與播放頁的直播版、設定頁（外觀、播放、網路三組與「關於」）、Debug 頁（概覽；窄版另驗區塊清單）、插件頁（已安裝、可安裝、安裝的
  確認框）與帳號頁（三種狀態的卡、QR 登入與貼上 cookie 的對話框、網頁登入卡住時的頁面）在窄（400）與寬（1000）視窗通過點擊區與對比度 guideline。閘門：`test/ui/guidelines_test.dart`。
  新頁面要加進去（沒有閘門，review 時看）。搜尋框因此用 `TextField` 而不是 M3 的 `SearchBar`（後者整條可點的那層沒有
  語意名稱、輸入框只有 24dp 高）。
- 插件頁（`lib/ui/plugins/plugins_page.dart`，ADR 0030 §決定 6–11，M3 design §7.5）：
  - 讀什麼：已安裝的插件讀資料庫（`installedPluginsProvider`，含停用的，離線照常）；每份 index（官方的在前、自訂的照加入
    順序）在打開插件頁時讀一次（`indexOutcomeProvider(url)`，autoDispose，頁面不在就丟掉），「檢查更新」整個 family
    `invalidate` 重讀（ADR 0014 §決定 7：只在這兩個時候比對）。讀失敗是 `IndexFailed` 結果、`log.report` 一次，不丟出。
    更新只看插件自己的 `source_index_url`，而且那份要在目前的清單上（刪掉的自訂插件庫不再檢查）。閘門：
    `plugins_page_test.dart` 的 `updates` 群組（`opening the page shows updates…`、`a plugin is not updated from another
    repository`、`an older version in the repository is never offered`、`check for updates reads the repositories again`）。
  - 標記：已停用（`installed_plugins.enabled`）、沒有回應（清單上那個實例的 `health`）、有更新（`updateStatus` 不是
    `none`）；`apiVersion` 不相容的新版本是停用的「需要更新 FMP」按鈕，可安裝那一筆同樣。「開發中」見 § 插件的插件開發工具。
    閘門：`the installed tab`、`the available tab` 群組。
  - 啟用開關只經 `PluginRegistry.setEnabled`；開關自己是一個語意節點、名稱是「啟用「插件名」」（不包 container 的話會
    併進 Card 的節點、名稱變成卡上所有的字）。搜尋頁的音源 chip 讀插件清單，停用就消失。閘門：`the switch disables and
    enables a plugin and writes it`、`test/ui/search/search_sources_test.dart`。
  - 確認框（`plugin_dialogs.dart` 的 `confirmInstall`）：內容一律取自要裝的那份 `.js` 的 manifest（從 index 裝的是
    `prepare` 下載並驗過的），列名稱、作者、版本、翻譯過的能力（`capabilityName`，exhaustive）、網域與「以你的登入身分」
    警告；不是官方插件庫來的（自訂插件庫、檔案、網址）另加「非官方來源」；更新只在 `needsConfirmation` 時問、只列新增的能力與
    網域，「全部更新」逐個問這種、其餘直接更新；從檔案或網址裝到已安裝的 id 上時寫出被取代的版本。預期內的拒絕
    （`PrepareRejected`）是警告提示、記 warning，不開確認框。移除先確認，經 `PluginInstaller.remove`（憑證與帳號列一起刪）。
    閘門：`the available tab`（`installing asks with the downloaded manifest…`、`the confirmation shows the downloaded file…`、
    `a repository whose … differs from the file…`、`… unofficial`、`a file that does not match the repository…`）、`updates`
    （`… lists only those…`、`update all asks only…`）、`installing from a file or a URL`、`removing asks first…`。
  - 動作在等網路或資料庫時頁面頂端有進度條，其他動作停用（一次只做一件事，對話框開著不算）；動作用的 provider 在第一個
    `await` 之前讀好，之後只在 `mounted` 時碰 `ref`（對話框期間視窗跨斷點，設定頁會換位置重建這一頁）。這條沒有閘門，
    review 時看。
  - 離線：可安裝分頁所有 index 都讀不到時，不在 `online` 是共用的 `OfflineMessage` 加「重試」，在 `online` 是一般的失敗；
    只有部分讀不到時那一段寫「無法讀取」加重試。已安裝分頁不受影響。閘門：`offline (…)` 兩例、`one unreadable repository…`、
    `online but unreadable…`。
  - 管理插件庫：官方的一列不能刪；加入先提示「非官方來源」，只收 `https`（`parseHttpsUrl`：有主機、沒有 user info），已在
    清單上的（含官方的）不重複加。閘門：`repositories`、`repositories already listed` 群組、`only https URLs…`。
- 「關於」（`lib/ui/settings/about_section.dart`，ADR 0024 §決定 9，M3 只有版本列）：版本列是「版本號（flavor）」，連點 7 次
  開啟開發者模式（ADR 0025 §決定 1）：第 2 次起 `Toaster.info`「再點 n 次…」、第 7 次寫入後「已開啟」，已經開著時每次點都
  說已開啟；計數在這個區塊被換掉或外殼換到別的分頁（`visible` 變假）時歸零。設定還沒讀出來時不計數。提示照常經 5 秒去重：
  離開又回來後 5 秒內的同一則不會再出現。閘門：`about_section_test.dart`（7 次與每則提示、只寫 `developer_mode`、離開區塊與
  離開設定頁都歸零、dev 預設開）。
- Debug 頁（`lib/ui/debug/`，ADR 0025 §決定 1、2，M3 design §12.1）：
  - 入口只有設定頁清單最後那一列，`openDebugPage` 在**根** Navigator 上推一般的 `MaterialPageRoute`（標題列有返回鈕、不是
    fullscreenDialog；設定頁在外殼的巢狀導覽裡，不指定根就會開在內容區裡）；是全螢幕 route，所以進 `toast_layering_test.dart`。
    不在外殼底下：播放類快捷鍵在這一頁不作用（沒有包 `PlaybackShortcuts`）。
  - 路由閘門：`developerProvider` 讀到關著（或讀取失敗）時頁面不顯示任何工具，並在那一幀之後關掉自己（最上層就 pop，
    被蓋住就 `removeRoute`），回到設定頁；直接開進來與在概覽關掉總開關都是這一條。設定還沒讀出來時也不顯示內容。閘門：
    `debug_page_test.dart` 的 `the route gate` 群組（拿掉閘門兩例都紅）與 `the settings entry` 群組（入口只在開著時、在「關於」之後）。
  - 版面照設定頁的 list-detail，看整個視窗的 `WindowClass`（這一頁在根 `WindowClassScope` 之下、外殼之外）。區塊是
    `DebugSection`（ADR 0025 §決定 2 的八個）；插件開發只在平台宣告 `pluginDevTools` 時列出，清單與內容都看它。窄版點進區塊後，標題列的返回鈕與系統返回鍵
    先回到清單：這一頁自己有 `PopScope`（外殼的那一個在下面的 route，不會同時動作，「不另放 `PopScope`」只說外殼底下的頁面）。
    閘門：`debug_page_test.dart` 的 `layout` 群組。
  - 概覽：總開關（`setDeveloperMode(false)`，見「設定」）、log 層級（顯示生效的層級，建置預設標「（預設）」，選了就寫）、版本／flavor／平台／資料目錄
    （家目錄換成 `~`，`homeRelativePath`：不分大小寫、只比對整段目錄名稱）、快取用量（各類加總）的連結：先 pop 這一頁再經
    `SettingsBack.show(network)` 選設定頁的「網路」；最下面是診斷包（見「診斷包」）。閘門：`debug_page_test.dart` 的 `the overview`（含 release 與 debug build 的預設標示）、`homeRelativePath` 群組。
  - Log 與錯誤歷史（`debug_log.dart`、`debug_log_state.dart`，ADR 0025 §決定 3，M3 design §12.3）：預設是這次執行的記憶體歷史
    （`logHistoryProvider`，`Log.changes` 後 250ms 合併成一次快照），最新的在最上面；「含之前的紀錄」（只在有 log 檔的平台出現）
    把 `LogFile.readStored()` 與記憶體歷史合成一份（`mergeLogRecords`）：同一筆的判準是整行內容（`toJsonLine`）逐字相同，同時間的
    檔案在前。篩選是層級（以上）、tag（完全相同）、文字（不分大小寫，比對 `formatLogRecord` 的全文）；「只看錯誤」＝警告以上
    （ADR 0011 §決定 5 的錯誤歷史，`isErrorRecord`）。點一筆在原地展開欄位、error、stackTrace；`Log.report` 寫的錯誤紀錄（有 `fields.type`）展開後另有「詳細」，開錯誤詳細頁（見「提示與錯誤詳細頁」）。「複製已篩選」複製
    篩選後的純文字（由舊到新），「清除 log」確認後呼叫 `Log.clear()`。閘門：`debug_log_state_test.dart`（合併、篩選、格式）、
    `debug_log_network_test.dart` 的 `the Log section`（篩選、只看錯誤、複製、清除要確認、清除後記憶體與檔案都空、含之前的紀錄不重複、錯誤紀錄的「詳細」開詳細頁而別的紀錄沒有）。
  - 音源健康檢查（`debug_health.dart`、`lib/plugins/health/`，ADR 0025 §決定 6，M3 design §12.5）：對已安裝且啟用的插件，以
    **App 已載入的那個插件**（真實連線、帶已存憑證）跑 `installed_plugins.checks_json` 的案例；`checks.json` 的解析與期望
    （`PluginCheck`、`parseChecks`、`checkShapes`、`CheckExpectation`）只有 `lib/plugins/health/checks.dart` 一份，契約執行器
    （`test/plugins/contract/`）與健康檢查共用。手動觸發「全部檢查」或單一插件，**一次只跑一個插件**：`HealthCheck.busy` 為真時
    再按不開第二輪，全部依序跑，每個插件開跑前重讀一次（前面的插件跑的期間被停用或移除的不跑）。停用的插件與沒有 `checks_json` 的插件（從檔案、網址或開發入口安裝）不跑，畫面標「已停用」「沒有檢查案例」；啟用卻不在已載入清單上的標「沒有載入」（`notLoaded`）。
    `requiresLogin` 的案例：該音源已登入就用 `CredentialStore.activeCredentials` 的憑證當 `loginVerify` 的輸入（不是案例檔的假值），
    未登入標「略過」、不發請求；其他 `requiresLogin` 的案例在已登入時就用 App 已載入的插件跑（請求自己帶憑證）；`mutates` 的案例標「略過：會改動遠端」、不呼叫插件。`loginVerify` 回的帳號（名稱、頭像）只拿來比對期望，不進結果與 log。結果（通過／失敗／略過、耗時、`AppError` 類別、說明）只留在記憶體，說明經遮蔽函式（錯誤只用 `toString()`，不含原始 error）；
    每個案例另以 tag `health` 寫一筆 log（`pluginId`、`capability`、`result`、`durationMs`、`errorType`），沒有新表。插件丟出 `AppError`
    以外的東西或期望不符都只標失敗、不中斷整輪。閘門：`health_check_test.dart`（略過與已存憑證、結果與 log 沒有帳號名稱與憑證值、一次一個與不開第二輪、跑的期間被停用、沒有載入、停用與無案例、
    log 欄位、失敗說明、非 `AppError`）、`debug_health_test.dart`（清單、進度、結果）、`guidelines_test.dart` 的 `the Debug Health section`。
  - 插件開發（`debug_plugin_dev.dart`、`lib/plugins/dev/`，ADR 0025 §決定 7，M3 PR 16b；規則見「插件」）：單欄，上面一張資料夾卡（選擇資料夾、
    重新掃描、卸載、套用中的進度條、資料夾層級的問題），下面每個插件一張卡片——標記（開發中、取代已安裝 x、載入失敗與原因）、模式
    `SegmentedButton`（重播｜錄製｜真實）、重新載入、查看 log、全部執行；每個案例一列（狀態、耗時、模式、錯誤類別），點開看錯誤與問題、
    錄製的「已寫入 n 個 fixture」、回傳值（縮排 JSON，可選取與複製）。選錄製時卡片顯示一行警告（不跳確認框：誤錄用 `git checkout` 還原）。
    套用中停用選擇／重新掃描／卸載／重新載入；有案例在跑時停用所有執行鈕與那個插件的模式切換。「查看 log」切到 Log 區塊並把 tag
    篩選設成該插件 id（`DebugLog.initialTag`，以 `ValueKey` 重設；之後從清單點 Log 不帶篩選）。閘門：`debug_plugin_dev_test.dart`、
    `debug_page_test.dart` 的 `the plugin development section`、`guidelines_test.dart` 的 `the Debug Plugin Development section`
    與 `the installed plugins in development`。
  - 網路（`debug_network.dart`、`debug_network_state.dart`，ADR 0025 §決定 4）：資料就是記憶體歷史裡 tag `network` 的紀錄
    （`NetworkEntry.tryParse` 讀 `writeNetworkRecord` 的欄位，不另存、不讀 log 檔），最新的在最上面。篩選是音源（空字串＝宿主自己的請求）、狀態碼類別（2xx／3xx／4xx／5xx，
    沒有狀態碼＝失敗，`StatusClass`）、文字。單筆詳細是對話框，列出遮過的 query、錯誤類型與 `networkRecordId` 對得上該筆 `id` 的
    錯誤紀錄（`matchingErrors`；id 只在同一次執行唯一，所以只比對記憶體歷史）。閘門：`debug_network_state_test.dart`（欄位對得上
    `writeNetworkRecord`、依音源與狀態碼類別篩選、`matchingErrors`）、`debug_log_network_test.dart` 的 `the Network section`（含
    `fake credentials never reach the detail or the copied log`：詳細與 Log 區塊複製出去的都只有遮過的值）。
  - 播放狀態（`debug_playback.dart`、`lib/playback/playback_diagnostics.dart`，ADR 0025 §決定 5，M3 design §12.3）：唯讀，區塊裡沒有播放控制。
    快照 `PlaybackDiagnostics` 由 `PlaybackController.diagnostics(backend:)` 組：控制器既有的 `PlaybackState` 與 `QueueState`（不改兩者的形狀）、
    `PlaybackSession.streamDiagnostics`（選中候選的容器、編碼、位元率、網路或 asset、第幾個候選、網址）與 `selectedOutputDevice`（後端 `outputDevices.selected`，
    Android 與選系統預設時為空），後端名稱由 `playbackDiagnosticsProvider` 依平台宣告的 `AudioBackendKind` 給。`Retrying` 的下次重試時間是控制器記的
    `_stateSince`（`_setState` 時的 `clock.now()`）加 `Retrying.delay`，等網路時沒有。佇列只列曲目鍵，前後各 `QueueDiagnostics.window`（5）首，依佇列在畫面上的順序（不是隨機的播放順序）。
    位置跟著進度 stream（`playbackProgressProvider`）每秒重算，不開計時器。「複製快照」輸出 `toJson(redactor)` 的 JSON：每個字串（含串流網址）都經
    `Redactor`，不含曲目標題、標頭與引擎給的原始錯誤（錯誤只有 `typeName`）；區塊畫面上插件給的字串（曲目鍵、插件 id、容器、編碼、裝置名）也經同一個函式，網址不顯示。
    收聽直播時區塊標「直播中」，曲目那一列換成「直播間」（`插件:房間`，`QueueDiagnostics.live`）；閘門 `debug_playback_database_test.dart` 的 `a live room says so…`。
    佇列是 Mix 時佇列區塊多一列「Mix」（`插件:mixId`，`QueueDiagnostics.mix`），JSON 的 `queue.mix` 只有插件 id、`mixId` 與 `hasCursor`：標題與插件的 cursor 不輸出；
    閘門 `debug_playback_database_test.dart` 的 `a mix names its identity…`／`a plain queue has no mix row`、`playback_diagnostics_test.dart` 的 `a mix is reported by its identity…`。
    閘門：`playback_diagnostics_test.dart`（簽名網址、假 token、登記的憑證值都不出現在 JSON）、`debug_playback_database_test.dart` 的 `copies a redacted JSON snapshot`（畫面與 JSON 都沒有登記的值）、
    `playback_controller_test.dart` 的 `diagnostics` 群組（欄位、前後各 5 首在頭尾的邊界、重試時間）、`debug_playback_database_test.dart` 的 `playback section`。
  - 資料庫（`debug_database.dart`、`lib/data/repositories/database_inspector.dart`，ADR 0025 §決定 8，M3 design §12.2）：唯讀，只有 `lib/data/` 碰 drift。
    `DatabaseInspector` 列 `allTables` 與筆數；`rows(表, 頁)` 每頁 `pageSize`（50）列，表名必須在 `allTables` 裡（才進得了 SQL 字串），讀的是儲存的原值（時間是 epoch 毫秒）；
    每個值經 `Redactor.redact`，`plugin_storage.value` 整欄是 `***`（`maskedColumns`）；`installed_plugins.script` 只顯示長度（`lengthOnlyColumns`：公開的插件原始碼，YouTube 約 800 KB，整份跑遮蔽要上百毫秒）。`check()` 報告 `PRAGMA integrity_check`、`PRAGMA foreign_key_check`
    與孤兒曲目數，不修；孤兒的條件與 `TracksRepository.deleteOrphans` 共用同一個常數（`_orphanCondition`），新的參照者只加在那裡。「檔案遺失的下載數」等 M6 有下載紀錄再加。
    備份、還原、重設見下一條。閘門：`database_inspector_test.dart`（50 列分頁、`plugin_storage` 整欄遮蔽、`script` 只顯示長度、其他欄經遮蔽、外鍵關掉寫一筆違規列後報告列出它、乾淨的資料庫無問題、孤兒數＝`deleteOrphans` 刪的筆數、非資料庫的表名被拒）、
    `debug_playback_database_test.dart` 的 `database section`。
  - 備份、從備份還原與重設資料（`debug_data_actions.dart`、`debug_reset.dart`、`lib/app/data_reset.dart`、`lib/data/database/database_backups.dart`，ADR 0025 §決定 8、9，M3 design §12.2）：
    - 備份是 SQLite 的 `VACUUM INTO`，檔案 `<資料目錄>/backups/fmp-<UTC 時間，毫秒，不含冒號>.db`，是一個能直接開的完整資料庫。**不含憑證**（憑證在 secure storage），還原後要重新登入。
      目標已存在（同一毫秒）就拋、不覆蓋；失敗時清掉寫到一半的檔。閘門：`database_backups_test.dart` 的 `create`（備份開得起來且各表筆數相同、檔名、同名拒絕、目錄建不起來）。
    - 重設資料的順序（`DataReset` 介面，實作 `AppDataReset`，UI 只依介面）：UI 先 `backUp()`，**失敗就停在那裡、什麼都不清**（toast 顯示原因）；成功才開對話框列出備份位置（家目錄換成 `~`），
      勾選「我了解」才能按「清空並重啟」（第二道確認）；確認後 `resetAndRestart(備份)` 依序：`SecureStorage.deleteAll()` → 登入 WebView `clearAll()`（平台沒有就略過）→ 快取（`CacheStore.clear()` 加記憶體 `ImageCache`）→
      資料庫（`DatabaseBackups.erase`：關閉後刪 `fmp.db` 與 `-wal`／`-shm`／`-journal`，下次啟動重建空的）→ 寫完 log（`LogFile.flush`）→ `AppRestarter.restart()`。不動 log 檔與 `backups/`。
      `resetAndRestart` 收的是剛做的備份，檔案不在或是空的就丟 `StateError`、什麼都不清，所以沒有備份就清不了；某一步丟錯就停在那一步，之後的不做（不回滾：前面清掉的憑證已經沒了）。
      **資料庫一關閉就沒有回頭路**：`DatabaseBackups.restore`／`erase` 在關閉之後才失敗（`isClosed` 為真）時，`AppDataReset` 記下錯誤、照樣寫完 log 並重啟再丟出，不讓 App 留在已關閉的資料庫上跑；關閉之前的失敗（備份不見、複製失敗）只丟出，App 還能用。
      閘門：`data_reset_test.dart`（順序與 log 在重啟前已寫進檔、重設後資料庫是空的／憑證存放是空的（`CredentialStore` 為 `none`、不給憑證）／log 與備份還在、備份裡有被清掉的資料、備份不見時什麼都不清、
      沒有 WebView 的平台略過、中途失敗停在那一步）、`debug_reset_test.dart` 的 `reset section`（先備份、沒勾不能按、取消不清、備份失敗不開對話框也不清、Android 寫手動重開、Windows 寫自動重啟）。
    - 從備份還原：Debug 頁「資料庫」的「從備份還原」列出 `backups/`（時間、大小，最新在前）→ 選一個 → 確認 → `DatabaseBackups.restore`：先把備份複製成 `fmp.db.restoring`（失敗時原資料庫還沒動）→ 關閉資料庫 →
      原 `fmp.db`（與 `-wal`／`-shm`／`-journal`）改名 `….before-restore-<時間>` 留著 → 暫存檔改名 `fmp.db`（換上去失敗就改回來）→ 重啟。還原前先清 secure storage 的憑證與登入 WebView 的資料（備份不含憑證，留著會配上備份裡的 `accounts` 列；`data_reset_test.dart` 的 `replaces the data, clears the credentials, then restarts`），快取不動。
      不先驗備份檔內容：壞的備份會讓下次啟動停在資料庫錯誤頁，原檔仍在旁邊。閘門：`database_backups_test.dart` 的 `restore`（資料等於備份、原檔改名留著、殘留 journal 被移開、換檔失敗時原檔改回來、備份不見時資料庫仍可用）、`data_reset_test.dart` 的 `restoring`（含關閉之前失敗不重啟、關閉之後失敗照樣重啟）、`debug_reset_test.dart` 的 `database section`。
    - 「資料庫」區塊另有「立即備份」；「檢查」有問題（`integrity_check` 或外鍵）時報告卡片多「從備份還原」「重設資料」兩個按鈕（孤兒曲目不算問題）。閘門：`debug_reset_test.dart` 的 `a check with problems offers restore and reset`、`a clean check offers no recovery buttons`。
    - 這個流程中途關了資料庫，之後到行程結束之間，仍在跑的資料庫查詢（佇列持久化、設定串流）會丟 `StateError`，預期由 `routeUncaughtErrors` 記進 log（沒有實測）。沒有自動閘門。
    - guideline：`the Debug reset section`（區塊、確認對話框、勾選後）、`the Debug restore dialogs`（資料庫區塊、備份清單、確認），400／1000 寬、淺色深色。
  - 播放狀態與資料庫也過 guideline：`the Debug Playback section`（空狀態與在播）、`the Debug Database section`（表清單、有列的表、檢查結果）。
  - 這兩個區塊自己有捲動的清單，不包在區塊的捲動欄裡（`DebugPage` 的 `filling`，同設定頁）；窄與寬版都在 `guidelines_test.dart` 的
    `the Debug Log section`、`the Debug Network section` 過 guideline（含展開的一筆與單筆詳細的對話框）。
- 首次啟動引導（`lib/ui/plugins/plugin_onboarding.dart`，ADR 0030 §決定 12，M3 design §7.6）：
  - 觸發：`searchSourcesProvider` 是空的（沒有已啟用、能搜尋、可用的插件）而且使用者沒按「稍後再說」，首頁與搜尋頁各顯示
    同一個 `PluginOnboarding`（ADR 0033 §決定 6；兩頁都在 `IndexedStack` 裡，各自一個 State：取消勾選只記在看到的那一頁）；dev flavor
    的 `fmp-test` 有 `search`，所以不出現，不另判 flavor。引導讀官方 index（`indexOutcomeProvider(officialPluginIndexUrl)`，與
    插件頁同一個 provider），官方插件預設全勾（只記取消勾選的）；已安裝（含已停用）的與需要更新 FMP 的列出但不能勾。
  - 按「安裝」先重讀官方 index（SHA 不符時提示的「請稍後再試」，再按一次才比得到新的那一份；讀不到就換成離線或失敗畫面、不裝），
    再一次確認（`confirmInstallAll`，每個插件的能力與網域取自下載並驗過的 `.js` manifest，一則共同警告）後依序安裝；下載階段被拒
    或裝失敗的記下來、其餘照裝，引導留著列出失敗、裝好的標「已安裝」（「關閉」收起；有失敗時不跳成功提示，它會蓋住底部的按鈕）。
    取消確認什麼都不裝。第一個插件裝好時搜尋頁就有音源了，所以整批結束前引導以 `OnboardingState.working` 留著，State 不會中途被拆掉。
  - 「稍後再說」只活在這次執行（`OnboardingState.dismissed`，不寫資料庫），連同失敗的清單一起收起；之後的空狀態附「前往插件頁」
    （`SettingsBack.show` 把外殼換到設定頁的「插件」區塊）。讀不到 index：不在 `online` 是 `OfflineMessage`，`online` 是一般的失敗
    畫面，都附「重試」。
  - 閘門：`test/ui/plugins/plugin_onboarding_test.dart`（零插件時列出、一次確認與裝好後消失、取消與取消勾選、全部停用時再出現、
    離線與重試、按安裝時重讀 index、部分失敗、全部失敗後再試、全部失敗後「稍後再說」、「稍後再說」與前往插件頁（1000、400 寬））、
    guideline 測試的 `the onboarding…` 400／1000 寬。
- 歷史頁（`lib/ui/history/`，design §9.7）：不是導覽項（ADR 0033 §決定 5），由音樂庫頂端的「歷史」與首頁「最近播放」的
  「查看全部」以 `openHistory` 推在那個目的地的巢狀 Navigator 上；下面還有頁時標題前有返回鈕（tooltip「返回（Esc）」，
  `ModalRoute.impliesAppBarDismissal`，同 AppBar 的判斷）。播放過的歌依時間倒序、以裝置本地日期分組（今天、昨天、日期；跨年才
  帶年份，日期與時刻以 `MaterialLocalizations` 依介面語言格式化，時刻固定 24 小時制 `HH:mm`），每列是封面、
  曲名、「作者 · 播放時刻」（音源停用或未安裝時，原因取代作者；閘門：`history_page_test.dart` 的 `a song of a source that is not installed shows why in place of the artist`）。資料經 `historyProvider` 分頁讀（一次 50 筆，捲到底讀下一頁，歷史表有變動就重讀已載入的
  那麼多筆），一萬筆不一次載入；本機資料，離線照常可用、封面讀不到是佔位圖。點一列是臨時播放；選單（右鍵、長按、
  尾端「⋯」）有播放、下一首播放、加入佇列、從歷史移除：移除只刪那一筆、不提示（擁有者決定），清除全部要確認，確認後
  提示「已清除播放歷史」（只有清除全部有提示；刪除或清除失敗才用 `Toaster.error`）。沒有紀錄是空狀態、清除鈕停用；讀取失敗不是空狀態：`HistoryNotifier` 把錯誤包成 `AppError`、`log.report` 一次（tag `history`，
  在 notifier 不在 build，重建不重報），頁面以 `EmptyState` 加錯誤圖示顯示 `errorMessage` 的文字（資料庫錯誤是 `errors.unexpected`）。
  不做舊版的搜尋、統計、排序、多選、日期篩選、折疊。閘門：`test/ui/history/history_page_test.dart`（`grouping by
  day` 以 `withClock` 固定現在、`playing from the history`、`removing`、`clearing everything`、空狀態、`a failed
  load shows the error…`、`it works
  offline…`、`paging`：只讀第一頁、`loadMore`、變動時重讀已載入的、`a page read while a reload is in flight…`、捲到底載入下一頁）、guideline 測試。
- `WindowClass` 與 M3 同值（600／840／1200／1600，下限含在高的一級）。閘門：
  `test/ui/layout/window_class_test.dart`。
- 外殼 `AppShell`（`lib/ui/shell/`）依整個視窗的等級換導覽：compact 底部 `NavigationBar`（播放列
  在它上面）、medium 與 expanded `NavigationRail`、large 以上常駐 `NavigationDrawer`；都是 Material
  內建元件（ADR 否決 `flutter_adaptive_scaffold`）。三種元件的導覽項都是首頁｜搜尋｜音樂庫｜電台｜設定（ADR 0033 §決定 5；
  `ShellDestination` 的順序就是 `IndexedStack` 與導覽項的順序，導覽項的圖示與文字只有 `_destinationLabel` 一份），App 開在
  首頁。播放列在內容區（與右側面板）下方、橫跨兩者，佇列是空的時不佔位置。閘門：`test/ui/shell/app_shell_test.dart` 的
  `navigation per window class`（每種元件五個項目與順序、`the app opens on Home`、`selecting <目的地> shows its page`）。
- 巢狀導覽（ADR 0033 §決定 5）：`IndexedStack` 的每一格是那個目的地自己的 `Navigator`，根頁是一個 `MaterialPage`（pages API：外殼重建時
  根頁跟著換成新的設定，設定頁的 `visible` 才跟得上）。內頁（歷史，之後的歌單詳情、探索）以 `Navigator.of(context).push` 開在
  內容區裡，導覽與播放列留著；全螢幕的頁（播放頁、Debug 頁、網頁登入、錯誤詳細）推在根 Navigator 上（`rootNavigator: true` 或
  `rootNavigatorKeyProvider`），`showDialog` 預設就在根上。換目的地不丟內頁（Material 每個目的地自己的 back stack）；再點一次
  目前的導覽項退回它的根；Ctrl+F 先把搜尋退回根再聚焦輸入框。地雷：
  - 每個巢狀 Navigator 包一個 `Semantics(container: true)`：route 的 `ModalBarrier` 是 `BlockSemantics`，不包的話擋掉的是同一個
    語意容器裡先畫的導覽元件與離線提示（螢幕閱讀器讀不到）。閘門：`app_shell_test.dart` 的 `screen readers hear it when it appears`
    （拿掉容器會紅）。
  - 巢狀 Navigator 自己的 `Focus` 是寫死的 `autofocus`，根頁的 route 加入時也把焦點拉進內容區：啟動與換目的地之後，焦點停在
    看不見、Tab 走不到的節點（Navigator 的節點或內容區的 scope 本身），所以 `focusNextRegion` 把停在 scope 本身或 `skipTraversal`
    節點上的焦點當成不在任何一區（F6 從導覽開始）；`focusInto` 選到內頁的 route scope 時再往裡面找頁面的項目。閘門：`app_shell_test.dart` 的 `focus regions` 群組（含
    `F6 goes into an inner page and out again`）。
  閘門：`app_shell_test.dart` 的 `nested navigation` 群組（內頁在內容區、導覽與播放列留著（400、1400 寬）、返回鍵與 Esc、內頁的
  返回鈕、再點導覽項回根、換目的地保留內頁、Esc 先關內頁上的選單、對話框與播放頁先關）、`Ctrl+F from an inner page of another destination`、
  `Ctrl+F from an inner page of Search goes back to its root`、
  `integration_test/toast_layering_test.dart` 的 `a toast shows above a page in the nested navigation`。
- 首頁（`lib/ui/home/`，ADR 0033 §決定 6，M4 design §10.2）：M4 PR 2 只有「最近播放」：`play_history` 最新 20 筆（`recentPlaysProvider`，
  不去重，歷史表變動就重讀），一排可橫向捲動的卡片（封面、兩行曲名、作者；音源不可用時是原因），點一下臨時播放；「查看全部」在首頁的
  巢狀導覽裡開歷史頁。區塊標題列（標題＋尾端「查看全部」）與一排卡片是之後我的歌單、電台、排行區塊的樣子。沒有可搜尋的音源時整頁是
  首次啟動引導（見下面「首次啟動引導」）；沒有內容是說明（「搜尋並播放歌曲，或匯入歌單」），沒有音源時附「前往插件頁」。本機資料，
  離線照常顯示。閘門：`test/ui/home/home_page_test.dart`（最新 20 筆不去重、點一下臨時播放、新的播放跟著出現、「查看全部」與返回、
  沒有內容的說明、引導的出現與裝好後消失、「稍後再說」後的說明與前往插件頁）。
- 音樂庫（`lib/ui/library/`、`lib/library/playlist_service.dart`，ADR 0033 §決定 8，M4 design §10.3、§10.5）：
  - 標題列「新增歌單」；頂端「歷史」一列；下面是歌單卡（封面＝第一首的封面、名稱、「本機 · n 首」）。卡片資料是
    `PlaylistRepository.overviews()`（一個查詢帶首數與第一首），`playlistOverviewsProvider` 以 `changes()` 重讀，不用 `watch()`：
    join 了 `tracks`，`watch()` 會在每次寫曲目時重查。代價是第一首的曲目資料（封面）更新時，卡片要等歌單或項目下一次變動才跟上。
  - 內容區 compact、medium 是清單（`ReorderableListView`，把手排序，同電台頁），expanded 以上是格狀（每張不超過
    `AppLayout.playlistCardMaxWidth`）：Flutter 沒有可排序的格狀清單，所以是把手上的 `Draggable` 加每張卡的 `DragTarget`，拖過某張卡就換到
    它的位置，放開才整批寫 `sort_order`。兩種都是資料庫追上之前照拖曳後的順序畫；寫入失敗回到資料庫的順序並提示。
  - 卡片選單（右鍵、長按、「⋯」，`TrackRowMenu`）：全部加入佇列、隨機加入佇列（先打亂再加入；佇列的隨機播放不動）、編輯、刪除（先確認）。
    加入走 `PlaybackController.addToQueue`：超過佇列上限整批拒絕、提示由外殼接 `QueueFull`；空歌單與 Mix 中兩項停用。
  - 建立與編輯是同一個對話框（`showPlaylistDialog`）：名稱必填（去掉空白後不能是空的）、描述選填、封面目前只顯示「第一首歌的封面」。
    design §10.5 的「自訂」（圖片網址）還沒做：封面只經某個插件的媒體 client 讀（每跳檢查那個插件的允許網域），使用者給的網址不屬於
    任何插件，要先定它的讀取路徑。
  - 閘門：`test/ui/library/library_page_test.dart`（歷史入口、空的說明、建立與必填、取消、編輯、刪除先確認、清單與格狀的拖曳寫入、
    寫入失敗回到資料庫的順序、全部加入與隨機加入、超過上限、空歌單與 Mix 中停用、離線）、`test/library/playlist_service_test.dart`（去空白、編輯保留封面、排序與刪除、
    依序加入、打亂、超過上限不加且發 `QueueFull`）、`playlist_repository_test.dart` 的 `overviews …`。
- 右側「正在播放」面板（`lib/ui/shell/now_playing_panel.dart`，design §9.4，ADR 0024 §決定 3）：
  - 出現：整個視窗 >= 840（expanded 以上，`hasNowPlayingPanel`）而且沒收起。compact、medium 沒有面板也沒有任何開關。
    面板在內容區（頁面）右邊、中間是拖曳把手；播放列在兩者下方橫跨，所以開關面板不改變播放列的分段。頁面的
    `WindowClassScope` 只量扣掉面板與把手後的寬度（視窗 1000 時頁面只剩 476、是 compact，設定頁是分組清單，視窗更寬才回到 medium）。外殼內容區的結構不隨面板
    有無而變，視窗跨過 840 時頁面不重建（設定頁選的組留著）。內容是標題列（「正在播放」加收起鈕）與目前這首的
    `TrackDetails`（與播放頁「詳細」同一個 widget），佇列空的時是空狀態；底色是主題的 surface，不是毛玻璃（毛玻璃只在播放頁）。
    記住收起的狀態時，佇列是空的就沒有地方展開它（播放列沒出現、播放頁也開不了），加歌之後才有入口。
    閘門：`now_playing_panel_test.dart` 的 `when it shows`（400／700／839／840／1000／1800、收起、空狀態、有歌、
    `pages measure the width left of the panel`）。
  - 寬度（`panelWidthFor`，數值在 `AppLayout`）：下限 320dp、上限視窗寬 x 0.4（上限低於下限時取下限，視窗 840 時是 336；
    也不超過 `AppLayout.panelMaxWidth` 1600，等於資料庫的 CHECK，視窗超過 4000 時沒有它寫入會失敗），預設 412、
    extraLarge 480。每次排版依目前視窗夾取畫面上的寬度，不改寫記住的值（資料庫只擋 > 1600）。閘門：`width` 群組
    （預設、extraLarge 預設、記住的在範圍內、超過 40%、低於下限、視窗 840、視窗縮放時記憶不變、`panelWidthFor` 的邊界含 1600）、
    `dragging` 群組的 `past 4000 wide the width stops at 1600…`。改其中一邊的 1600 時兩邊一起改。
  - 拖曳：把手往左拖面板變寬、往右變窄（寬度 = 按下時的寬度減指標總位移，夾在範圍內）；拖曳中只改畫面，放開才寫入
    `layout_state.panel_width` 一次；游標是左右調整。把手中間的線撐滿把手的高度（放在 `Center` 裡要給高度，否則是 0 高、看不到），聚焦、hover、拖曳時變色。閘門：`dragging` 群組（寫入以資料庫的通知數斷言：拖曳中 0 次、放開 1 次；`the divider line runs the full height and lights up on focus`）。
  - 鍵盤：把手可用 Tab 聚焦，← 讓面板變寬 16dp、→ 變窄 16dp，夾在範圍內，每按一次寫入一次；語意是有名稱、目前寬度
    與增減值的可調整元件（名稱在 `Semantics`，Tooltip 設 `excludeFromSemantics`，所以測試不能用 `find.byTooltip` 找把手）。
    寫入追上之前畫面維持剛設的寬度（連按不會跳回）；寫失敗時改回以儲存的為準，這一支沒有閘門。閘門：`keyboard`
    群組（`left widens by 16…`、`the keys stop at the range`、`the semantics name the handle and its value`）。
  - 開關（`panel_expanded`，沒記過是展開）有三個入口，切換同一個值並寫入：面板標題列的收起鈕；播放列的圖示鈕
    （整個視窗 >= 840 且播放列在第三段；播放列在 600–839 時是那一段「⋯」的勾選項，因為播放列自己量不出整個視窗，
    由外殼以 `PlayerBar.panelToggle` 給）；播放頁「⋯」的勾選項（expanded 以上才有）。閘門：`the toggles` 群組
    （收起與展開、播放列分段不變、medium 的勾選項、播放頁的項目與 compact／medium 沒有項目）。重開 App 仍記得由
    `layout_state` 的測試與 `layoutStateProvider` 保證，沒有整個 App 重開的測試。
  - 焦點：把手與面板在「內容」焦點區之內（F6 的三區不變）；F6 進內容區是頁面的第一個項目，Tab 走完頁面才到把手與面板。
    `focusInto` 向該區的走訪策略問第一個項目（`traversalDescendants` 是掛上的先後，不是走訪順序；改回它時 F6 不會落在頁面上）。
    閘門：`now_playing_panel_test.dart` 的 `the handle is in the tab order, after the pages`、`app_shell_test.dart` 的
    `focus regions` 群組。內容區另用 `OrderedTraversalPolicy`（頁面 0、面板 1）明訂順序：目前的版面裡預設的閱讀順序也是
    頁面先（把手從頂端到底，整區落在同一帶、由左而右），所以換掉它沒有測試會紅，review 時看。
  - 視覺：guideline 測試的 `the now playing panel at …`（淺色、深色 x 1000、1800）、golden
    `now_playing_panel_golden_test.dart`（1000、1800，只守版面結構）。
- 外殼量底部被佔住的高度（播放列＋底部導覽列＋安全區）發佈給 `toastBottomInsetProvider`；頁面
  不發佈。播放頁在最上層時（`playerPageOpenProvider`，由播放頁的 route 在 push、pop、被移除時設定）蓋住了
  播放列與導覽，外殼改發佈底部安全區（`viewPadding.bottom`），關掉後回到最後量到的高度。閘門：`app_shell_test.dart` 的
  `the bottom inset for toasts`、`toast_host_test.dart` 的 `position` 群組（含鍵盤：位移是鍵盤高度減
  `viewPadding`）、`player_page_test.dart` 的 `toasts`、`integration_test/toast_layering_test.dart` 的
  `a toast shows above the player page, on the safe area`。
- 播放列的控制項依它自己的寬度分三段（ADR 0024 §決定 5）：< 600 播放、下一首；600–839 上一首、
  播放、下一首、音量圖示（點開彈出式滑桿，裡面也能靜音）、「⋯」選單（隨機、循環、輸出裝置）；840 以上
  隨機、上一首、播放、下一首、循環，右側是（整個視窗 >= 840 時的）開關右側面板鈕、輸出裝置鈕、靜音鈕與音量滑桿（右側擠時滑桿先縮短）；曲名至少 160dp；medium 那一段的「⋯」在整個視窗 >= 840 時多一個「正在播放面板」勾選項（見上面「右側『正在播放』面板」）。輸出裝置只在
  平台宣告能選時（`outputDeviceSelectionProvider`，Android 沒有）出現，不是看後端有沒有清單。循環按一下
  依關閉 → 全部 → 單曲輪轉。點曲名與封面那一塊開播放頁（見下面「播放頁」）。閘門：`test/ui/player/player_bar_test.dart`
  的 `controls per width`（599／600／839／840 等邊界，各自有宣告與沒宣告輸出裝置的一組，Android 沒有輸出
  裝置鈕、「⋯」裡也沒有）、`shuffle and loop` 群組、golden `player_bar_golden_test.dart`（三個寬度，只守
  版面結構）。
- 播放列的音量（ADR 0018 §決定 10 的音量與靜音分開記）：滑桿 0–100%，拖曳當下就 `setVolume`（同時取消
  靜音）；音量拖到 0 不算靜音；靜音鈕切換 `toggleMute`，滑桿仍顯示記住的音量，圖示反映靜音與音量大小。
  Ctrl+↑／↓ 一次 ±5%（整數百分點，夾在 0–100%，靜音中就是取消靜音再調整）。UI 讀
  `playbackVolumeProvider`（建立時取控制器目前的值，之後跟著 `volumeChanges`；`restore` 不發 `volumeChanges`，
  所以靠播放列在恢復之後才出現）。閘門：`player_bar_test.dart` 的 `volume` 群組、`app_shell_test.dart` 的
  `Ctrl+Up and Ctrl+Down…`、`Ctrl+Up while muted…`。輸出裝置選單與其閘門：`player_bar_test.dart` 的
  `output devices` 群組（系統預設與裝置、目前的打勾、選了呼叫控制器、插拔、medium 的子選單）。
- 進度條在 `Idle`（沒有來源）時不讀進度 stream：它留著上一個來源最後的回報（臨時播放、清空之前的歌）。
  `Idle` 顯示按播放會從哪裡開始與目前曲目的時長：啟動恢復後還沒播（含先臨時播放、結束後停著）是控制器的
  `restoredPosition`，拖它或按 Shift+←／→ 就是改恢復的起點（`playbackSeeksProvider` 讓畫面跟上鍵盤）；
  其他是 0:00、不能拖（按播放從頭開始）；時長未知時維持不能拖的樣子。閘門：`player_bar_test.dart` 的
  `after a restore` 群組（含臨時播放之後、沒有恢復的 `Idle`）、`app_shell_test.dart` 的 `Shift+arrows
  move the restored start…`。
- 進度條在有來源的狀態讀進度 stream（一直是目前這首的，見 § 播放的「進度 stream」）；時長還沒回報（`null`，
  暫停中載入的那首在 Android 到按播放前都是）時用曲目的時長（`TrackInfo.duration`），所以照樣能拖。閘門：
  `player_bar_test.dart` 的 `a song loaded paused after a temporary play shows its own start and length…`
  （M2 驗收 2026-10-08 的情境）。
- 播放列的狀態標示（ADR 0018 §決定 7）：「等待網路連線」（`Retrying` 的 `delay` 為空）、「重試中」
  （其他 `Retrying`）、「試聽」（`playbackPreviewProvider`）以主色寫在曲名下那一行、上傳者之前，
  一行放不下就省略，三段寬度都在曲名欄裡、不另佔位置；狀態是 live region。閘門：
  `player_bar_test.dart` 的 `status labels` 群組（360／600／1000 三個寬度各三種）、guideline 測試的
  `the player bar waiting for the network`。
- 一列曲目的選單（搜尋結果、播放歷史、佇列）共用 `TrackRowMenu`（`lib/ui/tracks/`）：右鍵、長按與尾端「⋯」是
  同一份選單項目（由呼叫端給），「⋯」的 `FocusNode` 同時是 `MenuAnchor` 的 `childFocusNode`。右鍵的辨識器排除在
  語意樹外（`excludeFromSemantics`）：它會多一個沒有名稱的點擊動作，guideline 測試因此紅；同一份選單由「⋯」提供給
  輔助技術。閘門：guideline 測試的 `search results and the player bar`、`the queue at …`；三處各自的測試
  （右鍵、長按、「⋯」同一份，Esc 關得掉以按鈕打開的：`search_page_test.dart` 的 `playing a result` 群組、
  `history_page_test.dart` 的 `playing from the history` 群組、`queue_view_test.dart` 的 `the menu` 群組）。共用的機制
  本身沒有單獨的測試，靠這三處。
- App 內快捷鍵（ADR 0024 §決定 8）分兩張表，都綁在外殼：播放類在
  `lib/ui/shell/playback_shortcuts.dart` 的 `playbackShortcuts`（空白鍵、Ctrl+←／→、Shift+←／→ 5 秒、
  Ctrl+↑／↓ 音量、Ctrl+S 隨機、Ctrl+R 循環），由共用的 `PlaybackShortcuts` widget 包（外殼、播放頁與佇列的底部面板各包一層：播放頁與面板各是另一個
  route，不在外殼的 `Shortcuts` 之下）；Ctrl+L、Ctrl+Q 也在這張表（`ShowLyricsIntent`、`ShowQueueIntent`），但它們的
  action 不在 `PlaybackShortcuts`：外殼接（播放頁沒開、佇列不空時開播放頁）、播放頁接（切分頁）；導覽類在 `shell_shortcuts.dart` 的
  `navigationShortcuts`（Ctrl+F、Ctrl+,、F6、Esc）。輸入框裡的規則一句話：導覽類在輸入框內也有效，其餘
  都讓給輸入框。文字編輯的快捷鍵（`DefaultTextEditingShortcuts`）由 `WidgetsApp` 放在 App 根、比外殼遠，
  外殼會先接走按鍵；所以播放類的 action 一律用 `TextInputAwareAction`，焦點在輸入框時停用、按鍵交還
  輸入框。Esc 在外殼（`EscapeIntent`）：焦點在輸入框時離開它（焦點回到外殼），否則退出目前目的地的內頁，已在根就不處理
  （按鍵往上走）；對話框與彈出的選單、滑桿是自己的 route 或 overlay，由 Flutter 內建的 Esc 關閉，外殼不處理。選單的 Esc 只在焦點在選單的 anchor 或選單
  裡時有效，以滑鼠打開的選單焦點還在外殼，所以每個 `MenuAnchor` 都給 `childFocusNode`，並把同一個
  `FocusNode` 給打開它的按鈕（打開時焦點移過去）；閘門：`app_shell_test.dart` 的 `Esc closes the "…"
  menu`（播放列三個）、`search_page_test.dart`、`history_page_test.dart` 的 `Esc closes the menu opened
  from "⋯"`。Esc 關播放頁、Ctrl+L／Ctrl+Q 見「播放頁」。
  對話框開著時焦點在對話框的 route 裡，這些鍵不作用。閘門：`app_shell_test.dart` 的 `shortcuts` 群組
  （`text-editing keys in the search field stay in the field`：輸入框裡的空白鍵、Ctrl／Shift 加方向鍵不動
  播放；`in the search field Ctrl+S, Ctrl+R and Ctrl+Up stay with the field; Esc leaves it`；新鍵各一例；
  `with a dialog open playback shortcuts do nothing and Esc closes the dialog`）。
- 播放頁（`lib/ui/player/player_page.dart`，design §9.3、§9.5、§9.6，ADR 0024 §決定 4）：
  - 開關：點播放列曲名與封面那一塊（`InkWell`，點擊區與右邊的按鈕分開，語意是按鈕、「開啟播放頁」放在 hint）開；
    佇列不空時 Ctrl+L、Ctrl+Q 在播放頁沒開時也會開。`openPlayerPage` 把 `_PlayerPageRoute`（`MaterialPageRoute` 的子類別，
    `fullscreenDialog`）推在根 Navigator 上，所以提示仍在它上面；已開著不再推第二個。`playerPageOpenProvider` 由這個 route
    設定：`didPush` 設成開，`didComplete`（pop 與 `removeRoute` 都經過，當下就呼叫）設成關，`dispose` 只補沒 complete 就被丟掉的。
    不等到轉場結束的 `dispose` 才報關：關閉轉場中的頁面不收點擊，點擊落到播放列又開了一個，舊的 route 晚報會把新的那個標成沒開。
    左上角收合鈕（tooltip「關閉播放頁（Esc）」，只有圖示、不另給 `semanticLabel`）、Esc（頁面自己的 `Shortcuts`，
    `Navigator.maybePop`；對話框與選單照 Flutter 內建先關，因為它們的焦點與 overlay 在更上層）、Android 返回鍵（route 先 pop，
    只關這一頁；頁面內不放 `PopScope`）都關。佇列變空或沒有目前這首時頁面自己 `removeRoute`（頁面第一次 build 時就已經空了
    也一樣，在那一幀之後移除）。關閉（轉場結束）後焦點回到開它的元件（播放列的點擊區，Ctrl+L／Q 開的是開頁當下的焦點）；
    那時又有播放頁開著就不還。閘門：`player_page_test.dart` 的 `opening and closing`（點空白處開、點按鈕不開、三個寬度、
    收合鈕、Esc、對話框與速度選單先關、返回鍵只關播放頁、焦點回到播放列、Ctrl+Q 開的焦點還原、`reopening it while it is
    still closing keeps it open`、佇列清空自動關閉、`it closes itself when the queue is empty by its first frame`）、
    `player_bar_test.dart` 的 `the title area is a button that opens the player`。
  - 版面依整個視窗的 `WindowClass`（根 `WindowClassScope` 在 Navigator 之上，所以播放頁讀到的是整個視窗）：compact、
    medium 是封面與歌詞切換（點封面或 Ctrl+L，不寫入記憶），控制在下方，佇列是右上角「佇列」鈕（`PlayerPage.queueKey`，tooltip「佇列（Ctrl+Q）」，只有這兩段有，與左上角的收合鈕
    對稱）與 Ctrl+Q 開的底部面板（見下面「佇列」）；
    expanded、large 兩半，左是封面（上限 `AppLayout.playerArtworkMax` 420dp，短視窗縮小）、曲名、上傳者與狀態、進度、
    五個控制加「⋯」，右是分頁「歌詞｜佇列｜詳細」；extraLarge 三欄約 1：1.15：0.9（封面與控制｜歌詞｜分頁「佇列｜詳細」）。
    五個控制（隨機、上一首、播放、下一首、循環）每個版面都有；狀態標示與進度條與播放列同一份
    （`player_controls.dart` 的 `playbackStatusLabel`、`ProgressRow`，啟動恢復後顯示恢復的位置也一樣）。閘門：
    `player_page_test.dart` 的 `layouts`（五個等級各自的控制項與分頁、封面上限、三欄比例、視窗縮放）、`status and
    progress`、golden `player_page_golden_test.dart`（1000、1400、1800 寬，只守版面結構）。
  - 「⋯」有播放速度（0.5、0.75、1.0、1.25、1.5、1.75、2.0，目前的打勾，`PlaybackController.speed`／
    `speedChanges`，不持久化，重啟回到 1.0；`NowPlayingPublisher` 推出的 `speed` 跟著實際速度，系統依速度外推進度才
    不會偏），以及 expanded 以上的「正在播放面板」勾選項（compact、medium 沒有面板，所以沒有；見上面的面板條目）。閘門：`player_page_test.dart` 的 `speed`、
    `playback_controller_test.dart` 的 `the speed is observable…`、`now_playing_publisher_test.dart` 的 `a new speed is
    pushed…`。
  - 歌詞 M2 一律是「沒有歌詞」的空狀態（M7 接內容）。佇列見下一條。詳細分頁是 `TrackDetails`（封面、曲名、上傳者、時長、音源名稱，以 `pluginNameProvider` 查（見 § 插件的
    「插件庫與生命週期」；清單還沒載入完是 `null`，用插件 id），右側面板共用。閘門：`player_page_test.dart` 的 `tabs`（含開啟時的捲動位置、
    臨時播放不標目前這首、查不到名稱時顯示插件 id、五千首只建看得到的列）、`test/ui/plugins/plugin_name_test.dart`。
  - 佇列（`lib/ui/player/queue_view.dart` 的 `QueueView`，design §7.3）：佇列分頁（expanded 以上）與底部面板
    （compact、medium，`showQueueSheet`）共用同一個 widget。標題列是首數與「清空佇列」（只有圖示、tooltip 當名稱；確認後
    `clear`、提示「已清空佇列」，取消不動；清空後播放頁與面板一起關，提示等它們關掉的那一幀之後才發：提示的位移在顯示當下
    決定，頁面還開著時是底部安全區，compact 的導覽列會被蓋住），隨機開著時下面多一行「隨機順序跟著位置；拖曳只換歌，
    不改順序」。每列是封面、曲名、上傳者、時長、「⋯」選單與拖曳把手（音源停用或未安裝時，原因取代上傳者，且列監看 `sourceUnavailableProvider`；閘門：`queue_view_test.dart` 的 `a song of a source that cannot be used shows why instead of the uploader`、`the reason follows the source becoming unavailable`）；目前這首以主色標示（臨時播放中不標，因為
    `currentIndex` 是回到佇列時的位置）；點一下 `jumpTo`；選單有「下一首播放」（`moveToNext`，目前這首沒有這項）與「從佇列
    移除」（`removeAt`，不提示，同歷史頁）。固定列高的 `ReorderableListView.builder`、`buildDefaultDragHandles: false`：
    只有把手（`ReorderableDragStartListener`）能拖，長按留給選單；放下呼叫 `move`（用 `onReorderItem`，它的 `newIndex`
    已扣掉被拿起的那一格，舊的 `onReorder` 往下拖要自己減 1）；列的鍵是佇列項目的實例（`ObjectKey`），同一首出現兩次也
    各有各的；一萬首也只建看得到的列；開啟時從目前這首前兩列開始。閘門：`queue_view_test.dart`（`the list`：點選、一萬首
    只建看得到的、`the same song twice is two rows…`；`dragging`：往下與往上各一例、只有把手能拖、隨機時拖曳後下一首與畫面一致；`the menu`；`clearing`；
    `the shuffle note`）、`player_page_test.dart` 的 `tabs`。
  - 底部面板（compact、medium）：`showModalBottomSheet`（`isScrollControlled`）加 `DraggableScrollableSheet`（高度占
    螢幕的 60%，最小 30%），清單的捲動接給面板的控制器，開啟後才捲到目前這首附近。是自己的 route：返回鍵與 Esc
    （面板自己的 `Shortcuts`）只關面板、不關播放頁；佇列變空（沒有目前這首）時面板以 `removeRoute` 自己關掉，不是 pop 最上面
    的（清空確認的對話框可能還開著），所以不會留下蓋在外殼上的面板。面板也包一層共用的 `PlaybackShortcuts`（它不在播放頁的
    那一層之下）：播放類快捷鍵（空白鍵、Ctrl+←／→、Shift+←／→、Ctrl+↑／↓、Ctrl+S、Ctrl+R）和寬版的佇列分頁一樣有效，焦點在
    某一列時空白鍵也是播放暫停、Enter 才跳到那首（同播放列按鈕的規則）；Ctrl+L、Ctrl+Q 在面板裡沒有 action，按了不做事（面板
    不關、不開第二個）。Ctrl+Q：播放頁開著時 compact、medium 開面板（已開著
    不開第二個）、寬版切到佇列分頁；播放頁沒開時外殼開頁，再依版面開面板或切分頁（`PlayerPageEntry.queue`）。閘門：
    `queue_view_test.dart` 的 `the bottom sheet`（compact、medium 各：按鈕開、返回與 Esc 只關面板、Ctrl+Q 開、連按兩次
    只開一個、`the playback keys work in the sheet`（含 Ctrl+L 不做事）、`Space on a focused row plays or pauses, Enter jumps`、頁面沒開時 Ctrl+Q 開頁加面板、清空時兩者都關（含從面板上的確認框清空：提示在外殼的導覽列之上、外殼收得到點擊）、
    面板上可以編輯；寬版沒有按鈕）、`player_page_test.dart` 的 `layouts`
    （Ctrl+Q 開面板）、guideline 測試的 `the queue at …`（400 寬是面板、1000 寬是分頁，淺色與深色，隨機說明在）。
  - 切歌時捲到目前歌曲（「播放」組的 `auto_scroll_to_current`，預設關，設定頁在播放歷史保留筆數之後）：開著時，清單開著而
    目前這首換了，就捲到目前這首前兩列（動畫 `AppLayout.queueScrollDuration`）。「換了」是 `currentIndex` 指的佇列項目
    （實例）換了，拖曳或 `move` 讓它換位置不算；使用者正在拖曳（`onReorderStart` 到 `onReorderEnd`；拖曳被取消時 `onReorderEnd` 不會來，以清單上最後一個指標放開為結束）時不捲；開啟時的捲動
    不看這個設定。閘門：`queue_view_test.dart` 的 `scrolling to the current song`（開著捲、連續切歌、關著不捲、
    `move` 不算、拖曳中不捲、取消的拖曳之後照常捲）、`playback_controls_test.dart` 的 `the scroll switch…`、`playback_settings_test.dart`
    的預設與 `scrolling to the current song is written alone…`。
  - 分頁記憶：使用者選的分頁寫進 `layout_state.player_tab`（`layoutStateProvider`；沒記過是歌詞，這次開著期間選的先於
    資料庫的值生效），依裝置記住，不進設定組。extraLarge 沒有歌詞分頁：記住的是歌詞時顯示佇列，但不覆寫記憶，回到兩欄時
    仍是歌詞。閘門：`player_page_test.dart` 的 `tabs`（選了會寫入、重開還在、`a tab chosen on the page wins over a stored value that arrives later`、extraLarge 記住歌詞時顯示佇列且不覆寫）。
  - 背景是模糊的封面加遮罩（遮罩用主題的 `surface`、不是黑色：淺色主題下深色封面不會把毛玻璃底下墊黑），控制區與右欄是
    `GlassPanel`（約 66% `surface` 加 `BackdropFilter` 一般模糊）；沒有封面是實色的佔位背景。數值在 `AppLayout`。
    系統開高對比時 `GlassPanel` 改不透明、不模糊（Flutter 3.47.5 的 `AccessibilityFeatures` 沒有「減少透明度」，ADR 0024
    §決定 1 的更正）。閘門：`player_page_test.dart` 的 `glass`、guideline 測試的 `the player page over …`（淺色、深色 ×
    最淺、最深、沒有封面 × 400／1000／1800 寬）。
  - 快捷鍵與焦點：頁面包共用的 `PlaybackShortcuts`，另有自己的 Esc、F6；Ctrl+L 右欄切到歌詞（extraLarge 焦點移到歌詞欄、
    compact／medium 切到歌詞那一面），Ctrl+Q 切到佇列（compact／medium 開底部面板）；輸入框規則照上面（`TextInputAwareAction`）。
    頁內焦點區是控制區｜（extraLarge 的）歌詞欄｜右欄分頁（各是 `FocusScope`＋`FocusTraversalGroup`），F6 在頁內循環
    （`focus_regions.dart` 的 `focusNextRegion`，外殼共用），Tab 只在區內；外殼的三區在播放頁底下不動。閘門：
    `player_page_test.dart` 的 `shortcuts`。
- 電台頁（`lib/ui/radio/`，ADR 0031 §決定 4，M3 design §9.3）：
  - 讀 `radioEntriesProvider`（本機資料，離線照常顯示存的狀態）。每列是封面、標題、狀態標記加主播、開播中而且和標題不同時的
    直播標題、「⋯」（刪除，先確認）、拖曳把手（同佇列：只有把手能拖，`onReorderItem` 後整批 `reorder`，資料庫追上之前照拖曳後的
    順序畫；寫入失敗時回到資料庫的順序並提示，閘門 `a reorder that fails to save goes back to the stored order`）。四種狀態的標記（`RadioStatusTag`）顏色與圖示都不同，「查詢失敗」是警告色，不是未開播的樣子（D10）；標記（含直播的
    `LiveBadge`）的字對背景在淺深兩種主題都 ≥ 4.5，閘門 `test/ui/radio/status_tag_test.dart`（guideline 測試的對比度以整列的語意節點
    量，量不到列裡標記的字）。音源停用或未安裝的
    列留著、主播換成 `sourceUnavailableProvider` 的原因，點了跳警告、不收聽。正在收聽的那一列以主色標示。閘門：
    `test/ui/radio/radio_page_test.dart` 的 `the list`、`listening`、`editing` 群組。
  - 「以網址新增」是對話框，結果三種各一則提示（加入是成功、已在清單是資訊、認不得是警告），插件拋的 `AppError` 照
    `Toaster.error`（「無法新增電台：原因」）。「刷新狀態」呼叫 `RadioService.refresh`：`offline`（排程器沒發請求）不跳提示，
    清單上方一行說明「沒有刷新、是上次查到的狀態」加重試，回到 `online` 就收起（外殼已有離線橫幅，清單是本機資料不換成
    `OfflineMessage`）；`nothingToRefresh` 是資訊提示。新增、刷新進行中頂端有進度條、兩個鈕停用（同插件頁）。閘門：
    `adding from a URL`、`refreshing` 群組。
- 搜尋頁的直播間模式（ADR 0031 §決定 5，M3 design §9.5）：選的音源宣告 `live` 時搜尋框下有「曲目｜直播間」
  （`SegmentedButton`），直播間模式另有「全部｜開播中｜未開播」（`ChoiceChip`，`SearchState.roomFilter` 傳進
  `LiveSearchQuery.status`）。模式在 `SearchNotifier`：換到沒宣告 `live` 的音源（使用者換，或音源清單變了）就退回曲目；換音源、
  模式、篩選與自動退回曲目都換代、清掉結果，再以**輸入框現在的文字**（`searchInputProvider`，還沒送出的也算；不放進 `SearchState`，
  打字才不重建整頁）重搜第一頁，去掉空白後是空的就停在初始畫面、不發請求；`keyword` 仍是上次送出的（重試、載入更多、「找不到」用它），
  `search` 不寫回輸入框的文字（#260）。結果列是封面、標題、狀態加主播、人數（只在開播中，未開播的不顯示、不管插件給了什麼值，#262）、「⋯」
  （收聽、加為電台）；點一下 `playLive`；錯誤、空結果、離線、載入更多與曲目共用 `_Results`。閘門：`test/ui/search/search_live_test.dart`
  （音源清單變了而退回曲目是 `the live source leaving the list goes back to songs`；重搜用輸入框的文字是 `re-searching uses the text in
  the field` 群組；人數是 `an offline room shows no viewers even with a count`）。
- 直播版（ADR 0031 §決定 7，M3 design §9.4）：直播時 `QueueState.current` 是 `null`，播放列、播放頁、右側面板、佇列面板與外殼
  判斷「有沒有在播」一律用 `hasNowPlaying`（曲目或直播間），直播內容讀 `nowPlayingLiveProvider`（`playbackLiveProvider` 還沒跟上
  佇列時先用佇列裡的目標）。三處都沒有進度條、上一首、下一首、隨機、循環；有停止鈕（`stopLive`）、主播、`LiveFacts`（「直播中」
  標記、出聲時的已收聽時間、人數）。階段：重新連線中、等待網路連線、已停止（暫停就是停止串流）、無法播放寫在主播前面
  （`liveStatusLabel`）；直播已結束、查詢失敗換掉「直播中」標記（`LiveBadge`，查詢失敗是警告色）。播放頁的「詳細」分頁與右側
  面板是 `LiveDetails`（面板多一個「停止收聽」鈕）；播放頁直播時的「⋯」只有面板勾選項（沒有播放速度）。佇列分頁照常是原佇列、
  沒有一列標成在播。閘門：`test/ui/player/live_player_test.dart`（三種寬度的播放列、三種階段、播放頁兩種寬度、佇列與詳細分頁、
  佇列是空的時停止就關、面板）、`player_page_test.dart` 的 `in a live room no queue row is marked current`。
- Mix 的介面（ADR 0031 §決定 8–9，M3 PR 19；佇列與補歌的契約見 § 播放的 Mix）：
  - 「開始 Mix」在搜尋結果、播放歷史與佇列的曲目選單（`TrackRowMenu`）；**只在曲目所屬的插件宣告 `mix` 時出現**
    （`canStartMixProvider`，讀 `pluginRegistryProvider`，停用或移除的插件為假），宿主沒有音源分支。點下去 `startMixFrom`：失敗用
    `Toaster.error` 顯示、佇列不動。
  - Mix 中（`inMixProvider`＝`QueueState.mix != null`）停用且附說明：搜尋與歷史選單的「加入佇列」「下一首播放」改寫成「…（Mix 中無法使用）」並
    `onPressed: null`；播放列與播放頁的隨機鈕（`ShuffleButton.locked`）tooltip 改成「Mix 中無法隨機播放」、播放列「⋯」選單的隨機勾選項改寫成
    「隨機播放（Mix 中無法使用）」並停用。循環鈕的 tooltip 與「⋯」選單的循環項目另註明 Mix 中沒有「全部」（`loopTooltip`、`loopLabel` 的 `inMix`）。Ctrl+S 照樣呼叫控制器，由佇列拒絕。沒有「打亂佇列」的入口，所以沒有要停用的。
    佇列選單的「下一首播放」是重排（`moveToNext`），Mix 中照常。
  - 佇列分頁的標題列下多一行 `Mix：<標題>`（`QueueView.mixNoteKey`，星形圖示加單行省略），位置就是隨機說明那一行（Mix 沒有隨機，兩者不同時出現）。
  閘門：`test/ui/player/mix_ui_test.dart`（選單項目依插件能力出現、開始與失敗、Mix 中的停用與說明、隨機鈕與 Ctrl+S、循環鈕、「⋯」的循環項目與 Ctrl+R、佇列標題兩種寬度、佇列列選單）、
  `history_page_test.dart` 的 `the Mix items of the menu`、`guidelines_test.dart` 的 `the queue of a mix`（寬 400／1000、淺色與深色）。
- 分 P 的介面（M3 PR 20，design §11.1、契約見 § 插件的 `multiPart`；狀態在 `lib/ui/search/video_parts.dart`）：
  - 搜尋結果的影片列尾有展開鈕：**插件宣告 `multiPart`，且 `partCount` 空或大於 1，且還沒取到「只有一個分 P」**
    （`showsExpandButton`）。展開才呼叫 `multiPart`，取過的存在記憶體（`videoPartsProvider`，鍵是 `TrackKey.formatGroup`），不再取；取到的只有一個分 P
    就自動收起、鈕不再顯示，不報錯。取不到時列下面多一列「無法載入分 P」與重試，同時以 `Toaster.error` 顯示。載入中鈕換成帶語意名稱的轉圈。
    新的搜尋（`SearchNotifier.search`，含換音源、換模式後的重搜）一開始就收起所有影片（`VideoParts.collapseAll`），取過的分 P 留著。
  - 展開後每個分 P 是縮排的一列（「P2 分 P 標題」、時長、「⋯」），一首獨立的曲目：點一下臨時播放，選單照曲目列。點影片本身照舊臨時播放，不帶 cid。
    分 P 的標題剛好是 `P<序號>`（插件在分 P 沒有標題時給的）只顯示一次（`TrackInfo.partLabel`，M3 PR 21；閘門：`track_info_test.dart` 的 `a part titled with its own number…`，
    `P30`、別的序號照樣加上序號）。
  - 影片選單的「下一首播放」「加入佇列」：顯示展開鈕的條件成立時（含 `partCount` 空）先取分 P，**多於一個就全部放進去，否則只放影片本身**；取不到時
    以統一提示顯示、什麼都不加。`partCount` 為 1 或插件沒宣告 `multiPart` 時不取。
  - 播放列、播放頁、右側面板、佇列、播放歷史、系統媒體控制與「已跳過」提示都顯示 `TrackInfo.displayTitle`。**佇列與歷史沒有依影片分組的版面**：
    佇列是固定列高、每列各自拖曳排序的清單，歷史只有日期標題；分 P 靠標題「影片標題 · P2 分 P 標題」認出是同一支影片，沒有群組標題（`TrackKey.formatGroup`
    目前只用在這裡的展開狀態鍵）。要分組得新設計版面，另開。
  閘門：`test/ui/search/search_parts_test.dart`（展開鈕的四種條件、展開呼叫 `multiPart` 且不重取、新的搜尋收起且不重取、點分 P 臨時播放、單一分 P 收起、
  失敗與重試、載入中轉圈、影片選單的全部分 P／未知數量取一個／已知單 P 不取／無能力不取／取不到不加、Mix 中影片與分 P 的兩項都停用）、
  `test/ui/tracks/part_display_test.dart`（播放列、播放頁、佇列、歷史、「已跳過」提示）、`now_playing_publisher_test.dart` 的 `a part pushes the video title…`、
  `guidelines_test.dart` 的 `search results with the parts expanded／failed`、`the queue with multi-part tracks`（寬 400／1000、淺色與深色）。
- 曲目的詳細區（M3 PR 21，design §11.2；`lib/ui/player/track_details.dart`、`track_detail_parts.dart`、`track_detail_provider.dart`）：播放頁「詳細」分頁與
  右側面板共用 `TrackDetails`。插件宣告 `trackDetail` 時，在音源欄下面多顯示發佈時間（`formatDate`，依介面語言）、專輯、統計（圖示加縮寫人數，語意名稱
  依 `kind` 翻譯）、簡介（預設收合在 4 行，放不下才有「展開」），上傳者旁加頭像；沒宣告時只有原本的欄位，也不呼叫。每首第一次顯示時呼叫一次，結果進
  `TrackDetailCache`（記憶體 LRU，32 筆，不持久化；鍵是曲目鍵含 cid），再次顯示讀快取（同步回傳，不閃佔位）；請求進行中切走分頁或收起面板再回來，接上同一個請求（`keepAlive` 到請求結束）。載入中是不動畫的灰條佔位；失敗只在這一區顯示
  「無法取得詳細資料」與「重試」（不跳提示），離線（`noInterface`、`unreachable`）時改說離線——請求照送（使用者開分頁就是使用者發起的請求，ADR 0016 §決定 7
  的更正），所以離線的說明只出現在失敗之後。直播的詳細（`LiveDetails`）不呼叫 `trackDetail`。閘門：`test/ui/player/track_details_test.dart`
  （沒宣告／宣告、空的詳細、cid、載入中、失敗與重試、離線、簡介收合、頭像、第二次顯示不再呼叫、快取命中第一格就有資料、載入中切走再回來不重發、LRU 的 32 筆與 33 筆淘汰）、`guidelines_test.dart` 的
  `the track details with data／that failed／while loading`（寬 400／1000、淺色與深色）。
- 直播時的快捷鍵：空白鍵照常（控制器的 `pause` 就是停止串流）；上一首、下一首、Shift+←／→、Ctrl+S、Ctrl+R 在
  `PlaybackShortcuts` 的 `_QueueAction` **接下按鍵、什麼都不做**——不是停用：停用會讓按鍵往上傳，App 根的預設快捷鍵把
  Ctrl+方向鍵當成捲動，去捲頁面的清單（debug 下 `PrimaryScrollController` 有多個位置時是 assertion）。閘門：
  `live_player_test.dart` 的 `shortcuts while listening`（Ctrl+S、Ctrl+R 不改佇列的設定，拿掉判斷會紅；每個鍵的 `handled` 都是真，
  改成直播時停用會紅）。
- 焦點三區（導覽、內容、播放列）各是 `FocusScope`＋`FocusTraversalGroup`：Tab 只在區內循環，F6
  依序換區、跳過不在畫面上的播放列；巢狀導覽的內頁在內容區之內（見「巢狀導覽」）。閘門：`app_shell_test.dart` 的 `focus regions` 群組。
- 只有圖示的按鈕以 tooltip 當名稱（附按鍵，如「隨機播放（Ctrl+S）」，翻譯檔的 `*Tooltip`），不另外給
  `Icon.semanticLabel`：兩個都給時輔助技術念成「X. X」。閘門：`player_bar_test.dart` 的 `semantics`
  （播放列每個按鈕的語意只有 tooltip、標籤是空的）、`search_page_test.dart` 的 `the more button is
  named once…`、`history_page_test.dart` 的 `the clear button is named once…`、guideline 測試（標籤）；
  tooltip 附上對的按鍵：`translations_test.dart` 的 `tooltips carry the shortcut`（三個語言的字串含按鍵，
  按鍵本身與快捷鍵表一致沒有閘門，改表時 review 看）。新的只有圖示的 `IconButton` 照這條寫，沒有
  自動閘門擋住（lint 不看這個），review 時看。
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

## 診斷包

`lib/app/diagnostics/`（ADR 0025 §決定 3、10，ADR 0011 §決定 6，M3 design §12.4）。UI 在 `lib/ui/debug/debug_export.dart`、概覽的診斷包區與 Log 區塊的「匯出 log 檔」。

- `DiagnosticsService` 產生時組裝一次：`diagnostics.txt` 與 `diagnostics.json` 來自同一份資料（`DiagnosticsReport.build`：整份先經 `Redactor.redactValue`，純文字輸出前再遮一次；
  **JSON 不再對編碼後的整段遮蔽**——header 名單的值遮到行尾，會連結尾引號一起吃掉、輸出不是合法 JSON），加上全部的 log 檔（`LogFile.readAll`，排在寫入佇列後，檔名照舊）。
  **log 檔送出前以現在的遮蔽函式重遮**（`redactLogFiles` → `redactLogLines`，在 isolate）：寫入時只遮得到當時登記的東西，家目錄登記之前（更早的版本）、
  憑證登記之前的行仍帶原值。解析得出的行逐欄位重遮再編碼（仍是 JSON Lines），壞行整行遮，空行略過；「匯出 log 檔」走同一條。
  資料見 `diagnosticsDataProvider`：版本／flavor／建置模式、平台名稱／系統版本／資料目錄、語系、各已安裝插件的 id／版本／啟用與（宣告 `login` 的）是否登入與憑證狀態、
  外觀／網路／播放／開發者各組的生效值。**不含**帳號名稱、輸出裝置名稱（只寫有沒有選）、插件開發資料夾的路徑（只寫有沒有設）、歌單內容。欄位名要避開遮蔽名單的鍵名（`…sid`、`…token`）。
- zip 由 `archive` 在 isolate 壓（`zipEntries`；`archive` 只准在 `lib/app/diagnostics/`，lint `fmp_layer_imports` 的 `externalPackageOwners`）。檔名 `fmp-diagnostics-<yyyyMMdd-HHmmss>.zip`、`fmp-logs-….zip`，本機時間、不含冒號。
- 動作：「複製摘要」（純文字進剪貼簿，不開提醒）；「存成檔案」（`FileDialogs.saveFile`，依 `capabilities.files`）；「分享」（`FileSharer`，只在 `capabilities.shareFiles` 的平台出現）。
  存檔或分享前先跳「送出前請檢查」（`confirmSubmitReminder`）：與 GitHub 回報**共用**「開發者」組的 `report_reminder_dismissed`，取消什麼都不做，勾「不再提醒」才寫入。使用者在存檔對話框取消不提示成功。
- 分享用的 zip 寫在**資料目錄**底下的 `diagnostics-tmp/`（不是快取目錄：快取目錄只給快取模組，lint `restrictedImports`，而且快取庫開啟時會清掉根目錄裡不認得的東西）。
  每次分享先清掉整個目錄；`shareFiles` 回 `true` 才立刻刪檔，回 `false`（Windows）留著，由下一次分享前的清理與啟動維護清單的 `diagnostics-temp` 刪。分享開不起來就刪檔並拋出。
- 閘門：`test/app/diagnostics_test.dart`（txt／json 同一份資料且都遮蔽、zip 內容與檔名、`lines written before the home directory was registered…`（登記之前寫的行在兩種 zip 都遮掉、仍是 JSON Lines）、假憑證／假簽名網址／假帳號名稱／假家目錄四種都不出現、`DiagnosticsExporter` 的存檔／取消／分享／不回報／開不起來、`deleteDiagnosticsTemp` 只刪暫存目錄）、
  `log_record_test.dart` 的 `redactLogLines`（逐欄位重遮、壞行與空行、已遮過的不變）、
  `debug_export_test.dart`（按鈕依能力顯示、提醒第一次問且與 GitHub 回報共用設定、存檔與分享流程、Log 匯出只有 log 檔）、`guidelines_test.dart` 的 `the Debug overview`／`the Debug export reminder`（400 與 1000 寬、淺色深色）。
  **沒有自動閘門**：系統存檔對話框與分享視窗本身、zip 在真實 App 裡打得開、Windows 的 `DataTransferManager`，只能實機驗。

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
| `fmp_layer_imports` | 相對路徑跳出 `app/` 或非 `package:`／`dart:` 的 URI（全 package）；外部套件只准在擁有它的目錄（`pub_semver` 在 `plugins/repository/`，`qr_flutter` 在 `ui/accounts/`，`archive` 在 `app/diagnostics/`；`share_plus` 在 `platformPackages`）；`lib/legacy_import/` 只被自己 import；列出的檔案或目錄只准列出的位置 import（目前是 `playback/backends/` 的 `audio_backend.dart`、`backend_rules.dart`，見「播放」；`platform/cache_directory/`，見「快取庫」；`core/network/fixture/` 只給 `plugins/dev/`，見「插件」）；`core/`、`domain/` 不 import `ui/`、`playback/`、`plugins/`、`data/`、`settings/`，`data/` 不 import `ui/`、`settings/`、`playback/`、`plugins/`，`playback/` 不 import `ui/`（`test_playbackImportsUi`、`test_uiMayImportPlayback`），`scheduler/` 不 import `ui/`、`radio/`、`plugins/`，`radio/` 不 import `ui/`，`core/`、`domain/`、`data/` 不 import `scheduler/`、`radio/`（`test_lowerLayersImportSchedulerOrRadio`、`test_schedulerImportsUiRadioOrPlugins`、`test_schedulerNearMisses`），`core/`、`domain/`、`data/`、`scheduler/` 不 import `library/`、`library/` 不 import `ui/`（`test_lowerLayersImportLibrary`、`test_libraryImportsUi`、`test_libraryNearMisses`） | `rules/layer_imports.dart` 的 `externalPackageOwners`、`platformPackages`、`forbiddenLayerImports`、`sealedDirectories`、`restrictedImports` |
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
| `fmp_periodic_timer_owner` | `Timer.periodic`、`Stream.periodic`（含建構子與函式引用的寫法；以名稱判斷，型別別名認不出；文件註解的引用不算） | `periodicTimerOwners`（`lib/scheduler/`、`lib/playback/`） |

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
