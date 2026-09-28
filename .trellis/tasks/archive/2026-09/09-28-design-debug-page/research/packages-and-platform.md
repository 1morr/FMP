# packages-and-platform

查證日：2026-09-28

查證方式：pub.dev API、context7、官方文檔、GitHub gh api（固定 commit SHA permalink）、tavily

> 版本號一律以 `https://pub.dev/api/packages/<name>` 或官方頁面核對；GitHub 連結為查證當下的 commit SHA permalink。

---

## 1. drift 官方 DevTools extension

### 它是什麼

- drift 官方把它叫做 "DevTools extension"，**不是**獨立套件：extension 的資產直接隨 `drift` 這個 pub package 出貨（repo 內目錄 `drift/extension/devtools/`，內含 `config.yaml`）。`drift/extension/devtools/config.yaml` 的內容是 `name: drift`、`version: 0.0.1`，沒有設 `requiresConnection`，因此依 `devtools_extensions` 預設為 `true`（需要連上執行中的 app）。
  出處：<https://github.com/simolus3/drift/blob/1c0beee12a528a0d0cc66a2a08b6c62a674fdecc/drift/extension/devtools/config.yaml#L1-L7>
- 官方文件頁：<https://drift.simonbinder.eu/tools/devtools/>（repo 原始檔：<https://github.com/simolus3/drift/blob/1c0beee12a528a0d0cc66a2a08b6c62a674fdecc/docs/content/tools/devtools.md>）
- pub.dev 上叫 `drift_devtools_extension` 的套件**不存在**（`https://pub.dev/api/packages/drift_devtools_extension` 回 404）。名稱相近的是第三方 `drift_devtools` 0.0.17（2026-04-06），見第 2 節。

### 功能

| 功能 | 事實 | 出處 |
|---|---|---|
| 列出目前開啟中的 drift 資料庫與其 class 定義位置 | 是 | devtools.md L41-L43 |
| 檢視各 table 內容 | 是 | devtools.md L43 |
| **修改** table 內容（不是唯讀） | 是 | devtools.md L43 |
| Validate schema：比對預期 schema 與實際 schema | 是 | devtools.md L48-L57 |
| 匯出資料庫（download） | 是，僅 native（`isExportSupported = true`）；web / unsupported 為 `false` 並 throw | `drift/lib/src/runtime/devtools/platform_native.dart#L7`、`platform_unsupported.dart#L4-L13` |
| 清空資料庫（`clear`，刪 `sqlite_master` + `VACUUM`） | 是（破壞性） | `drift/lib/src/runtime/devtools/service_extension.dart#L99-L123` |
| 執行任意 SQL：select / insert / update / delete / custom statement | 是 | 同上 #L56-L84 |

- 內部實作用了 `drift_db_viewer`（Koen Van Looveren），但官方明說「你不必對那個套件加依賴，它只在 DevTools context 內執行」。
  出處：devtools.md L44-L46
- 機制：app 內用 `dart:developer` 的 `registerExtension('ext.drift.database', ...)` 註冊 VM service extension，DevTools 端呼叫它。
  出處：<https://github.com/simolus3/drift/blob/1c0beee12a528a0d0cc66a2a08b6c62a674fdecc/drift/lib/src/runtime/devtools/service_extension.dart#L140-L162>

### 怎麼裝 / 啟用

1. 用 `flutter run`（會印出 DevTools 連結）、`dart run --observe`，或從 VSCode / IntelliJ / Android Studio 開 DevTools。
2. 第一次要在 DevTools 視窗上方點 extensions 圖示，把 `package:drift` 設為 enabled（enablement 狀態存在專案根目錄的 `devtools_options.yaml`，見第 3 節）。
3. 之後 DevTools 會出現 drift 分頁。
出處：devtools.md L14-L33；enablement 機制 <https://docs.flutter.dev/tools/devtools/extensions>

### 版本 / 支援平台

- **沒有獨立版本號**：以「drift 版本 + Flutter 版本」為準。官方 community tools 頁寫「Starting with Drift 2.13 and Flutter 3.16」。
  出處：<https://github.com/simolus3/drift/blob/1c0beee12a528a0d0cc66a2a08b6c62a674fdecc/docs/content/community_tools.md#L41-L43>
- 查證當下 `drift` latest = **2.35.0**（2026-09-09），`drift_dev` = 2.35.0（2026-09-09）。
  出處：<https://pub.dev/api/packages/drift>、<https://pub.dev/api/packages/drift_dev>
- 平台：extension 本體跑在 DevTools（瀏覽器端）；被檢視的 app 端程式碼在 Android / iOS / Linux / macOS / Windows 都能用（`drift_db_viewer` 支援 Android, iOS, Linux, macOS, Web, Windows）。
  出處：<https://pub.dev/packages/drift_db_viewer>

### 限制（重點）

- **release build 不可用**，且 drift 原始碼有硬性編譯期開關：`const _releaseMode = bool.fromEnvironment('dart.vm.product'); const _enable = !_releaseMode;` —— release 時整個追蹤程式碼不進 build。
  出處：<https://github.com/simolus3/drift/blob/1c0beee12a528a0d0cc66a2a08b6c62a674fdecc/drift/lib/src/runtime/devtools/devtools.dart#L15-L19>（`handleCreated` 的 `if (_enable)` 在 #L44-L50）
- 需要能連上 app 的 VM Service（DevTools 是 attach 到執行中 app）；VM Service / service extension 在 release mode 被關掉。Flutter 官方 build modes 表：debug「Service extensions are enabled」「DevTools can connect」；profile「Some service extensions ... enabled」「DevTools can connect」；release「Service extensions are disabled」「Debugging is disabled」「Debugging information is stripped out」。
  出處：<https://docs.flutter.dev/testing/build-modes>
- **profile mode 是否可用：文件沒明說**；依 `_enable`（只看 `dart.vm.product`）與 profile 有 VM Service 推論「profile 可能可用」，但官方文件未確認 → **推測**。
- 匯出在 web 不支援 → **推測**（原始碼是 `platform_unsupported` 選 `dart.library.io` 以外時 throw；web 屬 unsupported 分支，故 web 上匯出會 throw）。
- 只列出「目前開啟中」的 drift 資料庫（透過 drift runtime 建立並被 `handleCreated` 追蹤者）。
  出處：devtools.md L41-L42；devtools.dart #L44-L50
- 破壞性能力（`clear` 清空整個 DB、任意 insert/update/delete）沒有任何只讀模式開關。
  出處：service_extension.dart #L56-L123

---

## 2. 在 App 內檢視 drift 資料庫

### drift 官方是否提供 App 內檢視器

- **沒有**。drift 官方 `/tools` 頁只導向 "Devtools extension" 與 "Community tools" 兩頁，沒有官方 App 內 viewer widget。
  出處：<https://drift.simonbinder.eu/tools/>（側欄）、<https://drift.simonbinder.eu/community_tools/>
- 官方認可的 App 內方案是 community 套件 `drift_db_viewer`（"is a package to view a moor or drift database in your Flutter app directly. It includes a graphical user interface showing you all rows for each table."）。
  出處：community_tools.md <https://github.com/simolus3/drift/blob/1c0beee12a528a0d0cc66a2a08b6c62a674fdecc/docs/content/community_tools.md#L34-L39>

### drift_db_viewer（官方 community 頁推薦）事實

- latest = **2.1.0**（2024-04-08，距今約 2.5 年未更新）；publisher `vanlooverenkoen.be`（verified）；dependency constraint `drift >=2.0.0 <3.0.0`。
  出處：<https://pub.dev/api/packages/drift_db_viewer>、<https://pub.dev/packages/drift_db_viewer>
- 平台：Android, iOS, Linux, macOS, Web, Windows（pub.dev 標示）。
- 用法：`Navigator.of(context).push(MaterialPageRoute(builder: (context) => DriftDbViewer(db)));`（db 需為 singleton）。
- **唯讀**：DB 存取只有 `customSelect` / `customSelectStream` / `count`（皆 SELECT）；`runCustomStatement` 雖定義在介面上，但 viewer 畫面沒有呼叫它（在 screen / viewmodel 內 grep 不到任何 delete/update/insert/customStatement 呼叫）。
  出處：<https://github.com/vanlooverenkoen/db_viewer/blob/775d1597326f86950b6f8c551f339ea40818c4a8/drift_db_viewer/lib/src/model/db/drift_db_viewer_database.dart#L84-L107>
- 已知限制：使用 named columns 時欄位要加 `@JsonKey`，否則該 table 無法處理（README "Drift Config" 段）。
  出處：<https://github.com/vanlooverenkoen/db_viewer/blob/775d1597326f86950b6f8c551f339ea40818c4a8/drift_db_viewer/README.md#L30-L45>
- README 未說是否支援 release build；文中只說用在 "our development app"（暗示 dev context，未明講）→ **推測**：官方定位是開發期工具。

### drift_db_viewer 的替代（第三方，皆為 pub.dev 描述，未深入查證原始碼）

| 套件 | latest | 發布日 | pub.dev 描述 | 形式 |
|---|---|---|---|---|
| `drift_devtools` | 0.0.17 | 2026-04-06 | "A Flutter package that provides a visual interface for inspecting and debugging Drift databases in real-time." | App 內即時檢視 |
| `drift_db_inspector` | 0.2.0 | 2026-07-12 | "A standalone browser-based database inspector for Drift databases, connected through the Dart VM Service." | 瀏覽器 + VM Service |
| `saropa_drift_advisor` | 4.4.1 | 2026-09-08 | "Debug-only HTTP server that exposes SQLite/Drift table data as JSON and a minimal web viewer." | debug-only HTTP server |
| `local_database_visual_debugger` | 0.0.1 | 2026-04-29 | "A plug-and-play in-app database viewer and inspector for Flutter." | App 內 |

出處：`https://pub.dev/api/packages/<name>` 各自查詢（2026-09-28）。

### 自寫查詢的官方 API 與唯讀限制

- `select(table)` → `get()` / `watch()`；`selectOnly`、`selectExpressions`。單值變體 `getSingle` / `getSingleOrNull` 等。
  出處：<https://drift.simonbinder.eu/dart_api/select/>
- `customSelect(String query, {variables, readsFrom})` 回 `Selectable<QueryRow>`；stream 版為 `customSelectStream` 或 `.watch()`；官方建議帶 `readsFrom` 讓 stream 知道要重發。`customInsert` / `customUpdate` / `customStatement` 是寫入路徑。
  出處：<https://drift.simonbinder.eu/sql_api/custom_queries/>、<https://github.com/simolus3/drift/blob/1c0beee12a528a0d0cc66a2a08b6c62a674fdecc/drift/lib/src/runtime/api/connection_user.dart#L383-L439>
- **唯讀**：drift **沒有**官方唯讀模式 / 唯讀 API（drift 端 grep 不到 readOnly 開關）。`customSelect` 底層呼叫 executor 的 `runSelect`；sqlite3 back end 的 `_selectResults` **不檢查**傳進來的語句是不是 SELECT（只 `_step()` 取值），所以 `customSelect` 不構成唯讀保證。
  出處：<https://github.com/simolus3/drift/blob/1c0beee12a528a0d0cc66a2a08b6c62a674fdecc/drift/lib/src/runtime/query_builder/statements/select/custom_select.dart#L50-L52>、<https://github.com/simolus3/sqlite3.dart/blob/4b038c5086016809f9654139bff73a95938381ae/sqlite3/lib/src/implementation/statement.dart#L104-L133>
- sqlite3 層有 `isReadOnly`（`sqlite3_stmt_readonly()`），但 drift 未使用它做閘門；sqlite3 也有 `OpenMode.readOnly`（直接開 sqlite3 connection 時可用），drift 的 `NativeDatabase` 未暴露等價參數。
  出處：statement.dart #L322；drift 端 `grep readOnly/OpenMode` 於 `drift/lib/src/sqlite3/database.dart`、`connection_user.dart` 無對應參數。
- schema 列舉可用 `db.allTables`（`drift_db_viewer` 就是這樣列 table 的）。
  出處：drift_db_viewer_database.dart #L17-L31

---

## 3. Flutter DevTools extensions 機制

### 套件與版本

- `devtools_extensions` latest = **0.5.1**（2026-05-04），publisher `flutter.dev`。
  出處：<https://pub.dev/api/packages/devtools_extensions>
- 官方建置指南：<https://docs.flutter.dev/tools/devtools/custom-tool>；套件 README：<https://github.com/flutter/devtools/blob/295d4b4a5a23648860d7854ff626b94f53a2fb4d/packages/devtools_extensions/README.md>

### 套件如何提供自己的 DevTools 分頁

- extension 是**一個 Flutter web app**，被嵌進 DevTools 內的 iframe（tab）。使用者必須依賴提供 extension 的 pub package，tab 才會出現。
  出處：<https://docs.flutter.dev/tools/devtools/extensions>
- 目錄結構：package 內要有 `extension/devtools/`，含 `config.yaml` 與預編譯好的 `build/`。companion extension 建議原始碼放在另一個 package（如 `foo_devtools_extension/`）以免膨脹主套件。
- `config.yaml` 必填欄位：`name`、`version`、`issueTracker`、`materialIconCodePoint`；選填 `requiresConnection`（預設 `true`：是否要連上執行中的 Dart/Flutter app）。
- `lib/main.dart` 用 `DevToolsExtension` widget 包住 root；可存取三個 global：`extensionManager`、`serviceManager`（連上的 VM service，if present）、`dtdManager`（Dart Tooling Daemon，if present）。
- 發佈流程：`dart run devtools_extensions validate --package=...` → `dart run devtools_extensions build_and_copy --source=. --dest=<pkg>/extension/devtools` → `pub publish`（缺 `config.yaml` 或空 `build/` 會 warning）。git-ignored build 目錄要在 `.pubignore` 加 `!build`。
  出處：custom-tool 頁與 README（同上）。

### `devtools_options.yaml`

- extension 的 enablement 狀態存在**使用者專案根目錄**的 `devtools_options.yaml`（類似 `analysis_options.yaml`）。進版控＝全專案共用；加進 `.gitignore`＝每人各自設定。格式：`extensions: [- provider: true, - shared_preferences: true, - foo: false]`。
  出處：<https://docs.flutter.dev/tools/devtools/extensions#configure-extension-enablement-states>
- 注意：檔名是 `devtools_options.yaml`（使用者專案）；套件端設定檔是 `extension/devtools/config.yaml`。兩者不同，勿混。

### 能否取代部分 App 內工具 / 關鍵限制

- 可以取代「開發期」的 App 內除錯工具（在 DevTools 內操作，不必在 app 裡做 UI）。**但無法取代 release build 內使用者可見的工具**：
  - extension 需要 DevTools 連上執行中的 app（`requiresConnection` 預設 true）；
  - DevTools 的 VM Service 只在 debug / profile 可用，release 的 service extensions 被關掉。
    出處：<https://docs.flutter.dev/testing/build-modes>（見第 1 節引文）
- `requiresConnection: false` 的 extension 可不連 app、只從 IDE 開 DevTools 使用；此時需要 Dart SDK ≥ 3.5 且 Flutter SDK ≥ 3.23（README）。建置 extension 本身的最低需求：**Flutter SDK ≥ 3.17、Dart SDK ≥ 3.2**（custom-tool 頁）。
- 查證當下 repo master 的 `devtools_extensions` pubspec 已到 `0.5.2-wip`，`sdk: ^3.11.0`、`flutter: ^3.41.0`。
  出處：<https://github.com/flutter/devtools/blob/295d4b4a5a23648860d7854ff626b94f53a2fb4d/packages/devtools_extensions/pubspec.yaml#L10-L12>
- 限制：analysis-server 形式的工具「只在規劃中」（README 原文："planned for the future"）。
- **查不到**：官方頁面沒有明文寫「extension 必須 debug/profile build」。這個結論是從 build-modes 頁（VM Service / service extensions 僅 debug、profile）+ `requiresConnection` 推得，屬強推論而非原文。

---

## 4. 桌面「選資料夾」與監看檔案變更

### 版本

| 套件 | latest | 發布日 | 出處 |
|---|---|---|---|
| `file_selector` | 1.1.0 | 2025-11-21 | <https://pub.dev/api/packages/file_selector> |
| `file_picker` | 13.1.0 | 2026-09-15 | <https://pub.dev/api/packages/file_picker> |
| `watcher` | 1.2.1 | 2026-01-08 | <https://pub.dev/api/packages/watcher> |

### file_selector（flutter.dev）

- 平台最低需求（README 支援矩陣，1.1.0 版）：Android SDK 21+、iOS 12+、Linux Any、macOS 10.14+、Web Any、Windows 10+。
  出處：<https://pub.dev/packages/file_selector>（README 表格；main 分支 README 已改成 SDK 24+/iOS 13+/macOS 10.15+，屬尚未發佈版本）
- API：`openFile`、`openFiles`、`getSaveLocation`、`getDirectoryPath`（另有 `getDirectoryPaths`）。
- 功能矩陣：

| 功能 | Android | iOS | Linux | macOS | Windows | Web |
|---|---|---|---|---|---|---|
| 選單一檔案 | 可 | 可 | 可 | 可 | 可 | 可 |
| 選多個檔案 | 可 | 可 | 可 | 可 | 可 | 可 |
| 選儲存位置 | × | × | 可 | 可 | 可 | × |
| 選資料夾 | 可 | × | 可 | 可 | 可 | × |

  出處：<https://github.com/flutter/packages/blob/ba0364a650af47374ffb1412595e3bf789ae5c99/packages/file_selector/file_selector/README.md#L109-L116>
- macOS 需 sandbox entitlement（`com.apple.security.files.user-selected.read-only` 或 `read-write`）。
- 型別過濾跨平台不一致（`extensions` 不支援 Web；`mimeTypes` 不支援 Windows/iOS，macOS 需 Big Sur+；`uniformTypeIdentifiers` 只有 iOS/macOS；`webWildCards` 只有 Web），傳錯會 `ArgumentError`。
  出處：同上 README #L93-L107

### file_picker（現由 vicajilau 維護）

- 平台：Android, iOS, Linux, macOS, Web, Windows（各自有 platform package：`android_file_picker`、`file_picker_darwin`、`file_picker_linux`、`file_picker_web`、`windows_file_picker`）。
  出處：<https://pub.dev/api/packages/file_picker>
- API 矩陣：

| API | Android | iOS | Linux | macOS | Windows | Web |
|---|---|---|---|---|---|---|
| `pickFile()` / `pickFiles()` | 可 | 可 | 可 | 可 | 可 | 可 |
| `saveFile()` | 可 | 可 | 可 | 可 | 可 | 可 |
| `getDirectoryPath()` | 可 | 可 | 可 | 可 | 可 | × |
| `pickFileAndDirectoryPaths()` | × | × | × | 可 | × | × |
| `clearTemporaryFiles()` | 可 | 可 | × | × | × | × |

  出處：<https://github.com/vicajilau/flutter_file_picker/blob/4b3380187646f452a43b5b7bb92fe7c9eb05ddc3/packages/file_picker/README.md#L43-L47>
- 沒有叫 `pickFolder` 的 API；選資料夾就是 `getDirectoryPath()`。
- v13 起 `androidSafOptions` 併入統一的 `androidOptions` / `FilePickerAndroidOptions`。
  出處：同上 README #L68-L70
- iOS 需 14.0+（用 `PHPickerViewController`）。

### watcher（dart-lang/tools）

- 純 Dart 套件（pubspec 只有 `sdk: ^3.8.0`，無 `flutter` 欄位）；平台標示 Android, iOS, Linux, macOS, Windows。repo 主線版本為 `1.2.2-wip`。
  出處：<https://pub.dev/api/packages/watcher>、<https://github.com/dart-lang/tools/blob/d87eaf7946e7939592c876ea6fb2fa1d72929efe/pkgs/watcher/pubspec.yaml>
- `DirectoryWatcher` 的平台分派：
  - 有 custom watcher 先用；
  - Linux → `LinuxDirectoryWatcher`（走 VM 原生 watcher，即 inotify；有 `WatchTree` 處理 directory move 問題）；
  - macOS → `RecursiveDirectoryWatcher(runInIsolate: false)`（底層 `Directory.watch(recursive: true)`，即 FSEvents）；
  - Windows → `RecursiveDirectoryWatcher(runInIsolate: true)`（同 `Directory.watch(recursive: true)`，即 ReadDirectoryChangesW；`runInIsolateOnWindows: false` 可關掉 isolate 以減少 buffer exhaustion）；
  - 其餘（含 `isWatchSupported == false`）→ `PollingDirectoryWatcher`（預設 1 秒輪詢）。
  出處：<https://github.com/dart-lang/tools/blob/d87eaf7946e7939592c876ea6fb2fa1d72929efe/pkgs/watcher/lib/src/directory_watcher.dart#L34-L68>、`.../recursive/recursive_native_watch.dart#L14`、`.../linux/native_watch.dart#L12-L40`
- 限制：Linux 是 inode 導向，directory 被搬移時會誤判成 delete 並關閉 watch（原始碼註解明列三種問題，無法復原，只能重新列目錄）。
  出處：同上 linux/native_watch.dart #L13-L40
- 未在 web 可用（用 `dart:io` 的 `Platform` / `FileSystemEntity`）→ **推測**。

### file_picker 在 Android 選資料夾 + 讀取其中 JS 檔（SAF 限制）

以下是查到的硬事實：

1. **選資料夾可行**：`getDirectoryPath()` 走 `ACTION_OPEN_DOCUMENT_TREE`。
   出處：<https://github.com/vicajilau/flutter_file_picker/blob/4b3380187646f452a43b5b7bb92fe7c9eb05ddc3/packages/file_picker_android/android/src/main/kotlin/com/mr/flutter/plugin/filepicker/FileUtils.kt#L201>（`Intent.ACTION_OPEN_DOCUMENT_TREE`）
2. **回傳值是「真路徑」或「content:// tree URI」二選一**：
   - 沒帶 SAF options 時，file_picker 用 `getFullPathFromTreeUri` 把 tree URI 轉成檔案系統路徑（`/storage/<volume>/<path>`；`primary` → `Environment.getExternalStorageDirectory()`）。**該函式只處理 external storage 類 volume**；`parts.size <= 1` 或非 Downloads 的 provider 會回 `null` → 上層回錯誤 `unknown_path`。
   - 帶 `FilePickerAndroidOptions(safOptions: ...)` 時，**直接回 content:// URI 字串**（`finishWithSuccess(data.data.toString())`），不做路徑轉換。
   出處：FileUtils.kt #L110-L128、#L807-L825、#L828-L855
3. **SAF grant 選項（v13）**：`AndroidSAFOptions(grant: transient | lifetime, accessMode: readOnly | readWrite, persistGrant: bool = true)`。只有 `grant: lifetime` 且 `persistGrant` 為 true 時才會呼叫 `takePersistableUriPermission`；**預設是 `transient`，不會 persist**。
   出處：<https://github.com/vicajilau/flutter_file_picker/blob/4b3380187646f452a43b5b7bb92fe7c9eb05ddc3/packages/file_picker_android/lib/src/file_picker_android_options.dart#L1-L51>、FileUtils.kt #L72-L94
4. grant 生命週期（Android 官方）：SAF 預設 URI 授權**只到裝置重開機為止**；`takePersistableUriPermission()` 後可跨重開機存活，但文件被移動或刪除就失效。ACTION_OPEN_DOCUMENT_TREE 從 API 21+ 可用，授權整個目錄樹（含子目錄）；Android 11+ 不能要求內部儲存根目錄、reliable SD 卡根目錄、`Download` 目錄，也不能從 `Android/data` / `Android/obb` 選檔案。persisted grant 有數量上限（Android 官方頁未寫數字；file_picker issue #1825 稱 API 30+ 為 512、舊版 128）。
   出處：<https://developer.android.com/training/data-storage/shared/documents-files>、<https://github.com/miguelpruivo/flutter_file_picker/issues/1825>（已由 PR #1989 實作，即 v13 的 SAF options）
5. **選「檔案」時，Android 端會把檔案複製到 app cache 再回傳該路徑**：`openFileStream` 把 content:// 內容寫到 `cacheDir/file_picker/<millis>/<name>`，`PlatformFile.path` 指向這個複本（另有 `uri` 與 `safHandle`）。`AndroidPlatformFile.readAsBytes()` 讀的是這個 cache 複本。
   出處：FileUtils.kt #L741-L805、<https://github.com/vicajilau/flutter_file_picker/blob/4b3380187646f452a43b5b7bb92fe7c9eb05ddc3/packages/file_picker_android/lib/src/android_platform_file.dart#L71-L107>
6. **scoped storage**：Android 11 起（targetSdk ≥ 30）direct file path 存取只對 media 檔案開放（`File` / `fopen` 可讀 media）；非 media 的任意檔案要靠 MediaStore、SAF，或申請 `MANAGE_EXTERNAL_STORAGE`（"all files access"，需 `Environment.isExternalStorageManager()` 且上架 Google Play 受政策限制：僅限檔案管理、備份還原、防毒、文件管理等核心用途）。`ACTION_OPEN_DOCUMENT_TREE` 的授權本身不會因 `MANAGE_EXTERNAL_STORAGE` 而增加能力。
   出處：<https://developer.android.com/about/versions/11/privacy/storage>、<https://developer.android.com/training/data-storage/manage-all-files>
7. `getDirectoryPath()` 只回一個路徑 / URI，**file_picker 沒有提供「列出被授權目錄樹內檔案」或「用 SAF URI 讀檔」的 Dart API**；Dart 的 `dart:io` `File` 不能開 `content://` URI。
   出處：API 矩陣（同 #3 節 file_picker README）、`file_picker_android.dart` 公開方法僅 `pickFile`/`pickFiles`/`pickFileAndDirectoryPaths`/`getDirectoryPath`/`clearTemporaryFiles`/`saveFile`/`releaseSAFGrant`（<https://github.com/vicajilau/flutter_file_picker/blob/4b3380187646f452a43b5b7bb92fe7c9eb05ddc3/packages/file_picker_android/lib/src/file_picker_android.dart#L32-L237>）；`dart:io` 不支援 content:// 屬 Dart/Android 平台事實 → 前半為事實、結論為 **推測**。

**綜合結論（Android 選資料夾讀 JS 檔）**：能「選到資料夾」（拿真路徑或 content:// tree URI），但**用 file_picker 單獨讀取該資料夾內任意 `.js` 檔並不成立**——沒帶 SAF 時拿到的真路徑在 scoped storage 下對非 media 檔案通常不可直接讀（除非有 `MANAGE_EXTERNAL_STORAGE`）；帶 SAF 時拿到 content:// URI，但要靠額外 SAF/content resolver 能力才能列目錄與讀檔（file_picker 沒提供）。此段為 **推測**（由 #5 #6 #7 交叉推得，未實機驗證）。

---

## 5. log 檔輪替

### 三個套件對「檔案輸出與輪替」的原生支援

| 套件 | latest | 發布日 | 檔案輸出 | 輪替 |
|---|---|---|---|---|
| `logging` | 1.3.0 | 2024-10-17 | **無**（只提供 `onRecord` stream，輸出全自理；README 範例就是 `print`） | **無** |
| `talker` | 5.1.20 | 2026-07-28 | **無**（README 只講 console / in-memory history / TalkerScreen UI / observer；沒有 file output、沒有 rotation） | **無** |
| `logger` | 2.8.0 | 2026-09-05 | **有**：`FileOutput`、`AdvancedFileOutput` | **有**（僅 `AdvancedFileOutput`，依大小） |

出處：<https://pub.dev/api/packages/logging>、<https://pub.dev/api/packages/talker>、<https://pub.dev/api/packages/logger>；<https://pub.dev/packages/logging>（onRecord）、<https://pub.dev/packages/talker>（無 file 段）

### logger 的細節

- `FileOutput`（基本款）：ctor 只有 `{required File file, bool overrideExisting = false, Encoding encoding = utf8}` —— **沒有**任何輪替參數。
  出處：<https://pub.dev/documentation/logger/latest/logger/FileOutput-class.html>
- `AdvancedFileOutput`（有輪替）：ctor 參數
  `path`（必填）、`overrideExisting=false`、`encoding=utf8`、`fileHeader`、`fileFooter`、`writeImmediately`（列出的 level 立即 flush）、`maxDelay=2s`、`maxBufferSize=2000`、`maxFileSizeKB=1024`、`latestFileName='latest.log'`、`fileNameFormatter`、`maxRotatedFilesCount`（預設 null = 不刪）、`fileSorter`、`fileUpdateDuration=1min`。
  出處：<https://github.com/SourceHorizon/logger/blob/c4d65c3ecb2dbf275d32fc4ef0f2a7af3d45d0b7/lib/src/outputs/advanced_file_output.dart#L70-L101>
- 輪替機制：`_updateTargetFile()` 每 `fileUpdateDuration` 檢查，當前檔 `length() > maxFileSizeKB * 1024` 時把 `latest.log` rename 成 `fileNameFormatter(now)`（預設 `2024-01-01-10-05-02-123.log` 這種全日期名），再刪多餘輪替檔、重新開 sink。**只依大小**（`maxFileSizeKB > 0` 才啟用輪替模式；設 0 則不輪替）——**沒有**依日期切檔的原生開關（日期只體現在輪替後的檔名）。
  出處：advanced_file_output.dart #L129、#L131-L147、#L156-L174、#L197-L214
- 寫檔有緩衝（預設 2 秒 flush 一次，或 buffer 滿 2000 筆，或命中 `writeImmediately` 的 level）。
- `logger` 的 Windows 換行處理：`Platform.isWindows ? '\r\n' : '\n'`（advanced_file_output.dart #L191）。

### talker 若要檔案輪替

- 核心 `talker` 沒有；社群擴充 **`talker_persistent` 3.0.0+5（2026-05-27）** 提供：寫入輪替文字檔（`maxFileSizeMb` 預設 5.0，超過後「刪掉最舊一半的 entries」）、`saveAllLogs: true` 時檔名 `logName-YYYY-MM-DD.log` 並依 `retentionDays`（預設 3）刪舊檔、另可存 Hive（`maxCapacity` 預設 1000）、`bufferSize` 預設 100（0 = 立即寫）、`flushOnError`。平台 Android, iOS, Linux, macOS, Windows。
  出處：<https://pub.dev/api/packages/talker_persistent>、<https://pub.dev/packages/talker_persistent>
- 提醒：這是社群套件（repo `eduardohr-muniz/talker_persistent`），非 talker 官方 repo（talker 作者 frezycode.com）。**推測**：維護狀況未查。

### 生態常見輪替慣例（依官方文件可證者）

- `logging` 的做法：只給你 `onRecord`，實務上自己接 listener 開 `File` / `openWrite()`，輪替自己實作或交給別的套件（README 明講輸出全自理）。
  出處：<https://pub.dev/packages/logging>
- `talker` 的建議做法：實作 `TalkerObserver`（override `onError` / `onException` / `onLog`）把 log 導去別處；README 舉 Crashlytics / Sentry / Grafana 為例，自寫檔案 observer 同一套路。
  出處：<https://pub.dev/packages/talker>
- `logger` 是三者中唯一有內建 size-based rotation 的（`AdvancedFileOutput`）。

---

## 6. 分享與匯出

### share_plus

- latest = **13.3.0**（2026-07-23），publisher flutter.dev；平台 Android, iOS, Linux, macOS, Web, Windows。
  出處：<https://pub.dev/api/packages/share_plus>
- 內容支援矩陣（README）：

| 內容 | Android | iOS | macOS | Web | Linux | Windows |
|---|---|---|---|---|---|---|
| Text | 可 | 可 | 可 | 可 | 可 | 可 |
| URI | 可 | 可 | 可 | As text | As text | As text |
| Files | 可 | 可 | 可 | 可 | × | 可 |

  出處：<https://pub.dev/packages/share_plus>（Platform Support 表）
- **桌面行為（關鍵）**：
  - **Windows**：Win10 RS5（build 17763）以上時註冊 C++ plugin，用 `DataTransferManager` + `ShowShareUIForWindow(GetWindow())` 開**Windows 分享飛出視窗**（不是檔案總管）；檔案透過 `SetStorageItemsReadOnly` 帶入。**RS5 以下**走 Dart fallback：用 `mailto:`（url_launcher）**只能分享文字**，`params.files` 非空會 throw `UnimplementedError`。
    出處：<https://github.com/fluttercommunity/plus_plugins/blob/ca5582997a54f9011e06b4e0ceadf65c02898c96/packages/share_plus/share_plus/lib/src/share_plus_windows.dart#L11-L58>、<https://github.com/fluttercommunity/plus_plugins/blob/ca5582997a54f9011e06b4e0ceadf65c02898c96/packages/share_plus/share_plus/windows/share_plus_plugin.cpp#L44-L52>、#L190-L199
  - **Linux**：只用 `mailto:`（url_launcher_linux）分享文字；`params.files` 非空 throw `UnimplementedError('Sharing files not supported on Linux')`。**不會**開檔案總管。
    出處：<https://github.com/fluttercommunity/plus_plugins/blob/ca5582997a54f9011e06b4e0ceadf65c02898c96/packages/share_plus/share_plus/lib/src/share_plus_linux.dart#L19-L51>
  - **macOS**：走 `NSSharingServicePicker`（native share sheet）。
    出處：<https://github.com/fluttercommunity/plus_plugins/blob/ca5582997a54f9011e06b4e0ceadf65c02898c96/packages/share_plus/share_plus/macos/share_plus/Sources/share_plus/SharePlusMacosPlugin.swift#L4>、#L54-L60
  - **Android / iOS**：`ACTION_SEND` / `UIActivityViewController` 原生分享對話框（非檔案總管）。
- API：`SharePlus.instance.share(ShareParams(text: ..., files: [XFile(...)]))`；舊的 `Share.share()` / `Share.shareXFiles()` 已 deprecated。`XFile.fromData` 需用 `fileNameOverrides`（`name` 在多数平台被忽略）；`XFile.fromData` 會寫 temp 檔到 cache，需自行清理。
- 其他限制：iPad 建議帶 `sharePositionOrigin`（否則 popover 置中；舊版可能 crash）；無法辨識使用者動作的平台回 `ShareResultStatus.unavailable`；對 Facebook 系 app 的圖片+文字分享不可靠（官方明說相關 bug 會直接關閉）。
  出處：<https://pub.dev/packages/share_plus>

### file_selector 的「另存新檔」（`getSaveLocation`）

- 支援平台：**Linux / macOS / Windows 可；Android / iOS / Web ×**（見第 4 節功能矩陣）。
- 用法：`final FileSaveLocation? result = await getSaveLocation(suggestedName: 'name.txt');` → 使用者取消回 `null` → 自己把內容寫到 `result.path`（例：`XFile.fromData(...).saveTo(result.path)`）。
  出處：<https://github.com/flutter/packages/blob/ba0364a650af47374ffb1412595e3bf789ae5c99/packages/file_selector/file_selector/README.md#L65-L80>
- 1.1.0 新增 `canCreateDirectories` 參數（控制使用者在選位置時能否建目錄）。
  出處：<https://github.com/flutter/packages/blob/ba0364a650af47374ffb1412595e3bf789ae5c99/packages/file_selector/file_selector/CHANGELOG.md>
- 各平台底層是**原生儲存對話框**：
  - Windows：`IFileOpenDialog`（`file_dialog_controller.cpp`）。
    出處：<https://github.com/flutter/packages/blob/ba0364a650af47374ffb1412595e3bf789ae5c99/packages/file_selector/file_selector_windows/windows/file_dialog_controller.cpp#L11>、#L46-L47
  - Linux：GTK `GTK_FILE_CHOOSER_ACTION_SAVE`。
    出處：<https://github.com/flutter/packages/blob/ba0364a650af47374ffb1412595e3bf789ae5c99/packages/file_selector/file_selector_linux/linux/file_selector_plugin.cc#L111-L119>
  - macOS：`NSSavePanel`（`runModal` / `beginSheetModal`）。
    出處：<https://github.com/flutter/packages/blob/ba0364a650af47374ffb1412595e3bf789ae5c99/packages/file_selector/file_selector_macos/macos/file_selector_macos/Sources/file_selector_macos/FileSelectorPlugin.swift#L79>、#L157-L167>
- macOS 另需 sandbox entitlement（見第 4 節）。

---

## 查不到 / 不確定的點

- **查不到**：官方明文寫「DevTools extension 僅限 debug/profile build」。此結論是從 build-modes 的 VM Service / service extensions 限制推得。
- **推測**：drift DevTools extension 在 profile build 可用（drift 的 `_enable` 只看 `dart.vm.product`，profile 有 VM Service；但無官方確認）。
- **推測**：drift_devtools extension 在 web 上匯出資料庫會失敗（`platform_unsupported` 分支）。
- **推測**：`watcher` 不支援 web（用 `dart:io`）。
- **推測**：Android「選資料夾後用 file_picker 讀取其中 .js」不成立（由 cache 複製行為、scoped storage、缺 Dart 端 SAF 讀取 API 交叉推得，未實機驗證）。
- **推測**：`drift_db_viewer` 定位為開發期工具（README 只說用在 dev app，未明講 release 行為）。`talker_persistent` 的維護狀況未查。
- 未查：`drift_db_inspector` / `saropa_drift_advisor` / `local_database_visual_debugger` / `drift_devtools` 的原始碼與平台限制（僅取 pub.dev 描述）。
