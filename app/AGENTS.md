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
| drift 的 table 或資料庫類別（`lib/data/database/`） | 先 `dart run build_runner build`，再跑第一列；改了 schema 另照 § 資料層 存新快照 |

- `flutter test` 不加參數：`live` 預設跳過（見「零聯網」）。CI 的 `app` job 跑上表前兩列
  與產生檔檢查（見「資料層」）；
  `fmp_lints` 的測試另外以 `TEST_ANALYZER_WINDOWS_PATHS=true` 再跑一次（Windows 路徑）。
- `flutter analyze` 看不到 analyzer 插件的診斷、照樣回 No issues（flutter/flutter#187999），
  所以兩個都要跑：插件規則看 `dart analyze`，Flutter 專屬的診斷看 `flutter analyze`。
- `test/identity/windows_identity_test.dart` 要 `cmake`：CI 的 ubuntu runner 內建；
  Windows 的 PATH 上沒有時，測試以 vswhere 找 Visual Studio 附的那一份。
- 不帶 `--flavor` 的 run／build 是 dev（`pubspec.yaml` 的 `default-flavor`）。
- 插件執行環境的測試在裸 `flutter test` 裡跑真的 QuickJS：`test/flutter_test_config.dart`
  經 `test/support/quickjs.dart` 先以絕對路徑載入 flutter_js 內附的原生庫（Windows、Linux），
  不必先建置桌面版；插件的背景 isolate 以檔名開到同一份（整個行程共用）。找不到就拋錯，CI 不會
  默默跳過。macOS 不支援。看門狗的測試會留下一條忙著的執行緒，到那個測試檔的行程結束為止。
- 插件執行環境的實機量測：`flutter test integration_test/plugin_runtime_benchmark_test.dart -d <裝置>`
  （dev flavor；結果是 `FMP_BENCH` 開頭的行）。數字與方法在
  `.trellis/tasks/archive/2026-09/09-30-js-runtime/research/notes.md` §4。

### 實機驗證

- 預設用 dev flavor 加測試插件，或把插件切成重播模式（ADR 0027 §決定 1）。
- 只有改動本身是插件、網路層、登入或正在錄 fixture 時才用真實連線，只做最少的
  操作，回報寫明「模式：真實」與做了哪些請求（ADR 0027 §決定 2）。
- 每個使用者看得到的 PR 都要在 Android 模擬器與 Windows 驗（ADR 0027 §決定 3）。
- `app/` 版的 `verify-on-device` skill 在 M1 PR 11 才建立；在那之前照上面三條手動
  驗，回報寫明平台與模式。根目錄的 `verify-legacy-on-device` 只給舊專案用。

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

閘門：`test/identity/android_identity_test.dart`、`test/identity/windows_identity_test.dart`。
沒有測試的兩處：mutex 的 `Local\` 前綴，以及 `main.cpp`／`Runner.rc` 確實讀這些定義；
改到它們時，檢查建置出的 exe 的版本資源與內嵌的寬字串。

- Android namespace 兩個 flavor 都是 `com.personal.fmp`；只有 applicationId 帶後綴。
- Windows 的第二個實例以「視窗類別＋標題」找第一個實例帶到前景，所以兩個 flavor
  的標題必須不同；之後若在 Dart 端改視窗標題，要一併改 `main.cpp` 的尋找方式。
- Windows 的 ProductName 決定 path_provider 的目錄（`%APPDATA%\com.personal\<ProductName>`），
  dev 的 application support、cache 等目錄因此全部與 prod 分開。

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
- drift 產生的 `*.g.dart` 提交進 repo（`app/.gitignore` 覆寫根目錄對 `*.g.dart` 的忽略），
  拉下來不用先跑 codegen。改了 table 或 `@DriftDatabase` 就重跑
  `dart run build_runner build` 並提交產生檔。閘門：CI `app` job 的
  「Check generated code is up to date」；本機沒有東西擋。
- schema 快照在 `drift_schemas/app_database/`。閘門：`test/drift/app_database/schema_test.dart`
  ——程式碼建出的 schema 必須等於最新快照，`schemaVersion` 必須等於最新快照的版本。
- 持久化格式：列舉存 `lib/data/database/converters.dart` 寫死的字串（不是 enum 的
  `name`）、時間存 UTC epoch 毫秒、`TrackKey`（`lib/domain/track_key.dart`）的字面輸出
  與舊版逐字相同（M5 匯入要對得上）。改任何一個就是改資料格式。閘門：repository 測試的
  `stored format` 案例、`test/domain/track_key_test.dart`。
- `sqlite3` 3.x 以 build hooks 在建置時從它的 GitHub releases 下載預先編譯的 SQLite；
  第一次建置或 `flutter test` 要能連 GitHub。

## Riverpod

- `main()` 的每個 `runApp` 都包在 `lib/app/app_scope.dart` 的 `appProviderScope`：全域
  `retry` 關閉（ADR 0013 §決定 4）。閘門：`test/app/app_scope_test.dart`（含一個預設
  重試會重試的對照案例）；lint `missing_provider_scope` 擋沒有 `ProviderScope` 的 `runApp`。
- 開好的資料庫（`appDatabaseProvider`，`lib/data/providers.dart`）與資料目錄
  （`dataDirectoryProvider`，`lib/platform/app_data_directory/`）只由 `main()` 以
  `overrides` 注入；沒 override 就讀會拋錯。測試照樣 override（記憶體資料庫）。
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

## 錯誤

`lib/core/errors/`（ADR 0013）。怎麼加錯誤類型或 i18n key、音源怎麼寫對應表：
`.trellis/spec/app/errors/index.md`。

- 音源邊界以上只看得到 `AppError`：音源把自己的錯誤碼轉好，其他例外在邊界以
  `AppError.wrap` 包成 `UnexpectedError`。閘門：PR 9 的插件契約測試；在那之前沒有。
- `AppError` 沒有可以直接顯示的字串：使用者訊息只有 `messageKey`／`messageArgs`；
  原始 error 與 stackTrace 是函式庫私有欄位，`toString()` 不含它們。閘門：
  `test/core/errors/app_error_surface_test.dart`（列出全部公開成員，含變異案例）、
  `app_error_test.dart` 的 `toString`。
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

- 每插件一個 `SourceHttpClient`，由 `SourceHttpClientFactory.create` 建立；`Dio` 只在
  那裡建立，`dio`（含 `dio_cookie_manager`）與 `cookie_jar` 只准在 `lib/core/network/`
  import。閘門：lint `fmp_http_client_owner`、`fmp_layer_imports`。
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
- 網路紀錄：tag `network`，每次送出一筆，欄位 `id`、`pluginId`、`method`、`host`、
  `path`、`query`、`status`、`ms`、`bytes`、`error`、`credentials`、`retry`；不記
  body。未登入而拒絕的 `required` 請求沒送出，也有一筆（沒有 `status`、`ms`），
  `AuthRequired` 帶它的 id。失敗或狀態碼 ≥ 400 用 `warning`，其餘 `debug`。欄位名稱是 log 檔的持久化格式；
  網路層產生的 `AppError` 帶那一筆的 `networkRecordId`。閘門：`network log` 群組
  （欄位逐一比對；query 裡的假憑證與 body 不出現在記憶體歷史與 log 檔）。
- 認證：請求宣告 `AuthRequirement`，攔截器只依 `decideAuth` 的表注入。M1 的認證來源是
  `NoCredentials`（每個音源都未登入）。閘門：`auth_test.dart`（三種標記 × 三種狀態）。
- 媒體 client 延到 M6。交給播放後端的串流 headers 一律先經 `mediaRequestHeaders`：只留
  `Referer`、`User-Agent`、`Origin`、`Range`。閘門：`media_headers_test.dart`；後端確實
  經過它，由 PR 10 的測試接手。

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
  （`pubspec.yaml` 的註解）。
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
  同目錄的 `tone.wav`（`asset:///…`）。prod 的建置只留下空目錄，沒有檔案。

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
| `fmp_layer_imports` | 相對路徑跳出 `app/` 或非 `package:`／`dart:` 的 URI（全 package）；外部套件只准在擁有它的目錄；`lib/legacy_import/` 只被自己 import；`core/`、`domain/` 不 import `ui/`、`playback/`、`plugins/`、`data/`、`settings/`，`data/` 不 import `ui/` | `rules/layer_imports.dart` 的 `externalPackageOwners`、`platformPackages`、`forbiddenLayerImports`、`sealedDirectories` |
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
- `tool/lint_sentinel.dart` 暫放違規檔跑 `dart analyze`，斷言每條開啟的規則都報出來。插件
  沒載入或編譯失敗時 `dart analyze` 會照樣綠，只有它會紅。

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
