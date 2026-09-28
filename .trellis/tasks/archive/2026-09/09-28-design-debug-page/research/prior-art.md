# prior-art

查證日：2026-09-28

查證方式：
- 第一部分（成熟 App 的內建除錯工具）：`gh api` 取固定 commit SHA 的原始碼（permalink）、
  官方文件與官方網頁；未實際執行任何 App。
- 第二部分（Flutter 生態的除錯套件與插件開發者工具）：`https://pub.dev/api/packages/<name>`（版本／發佈日）
  與 `/score`（分數／likes／下載量）、context7、官方文檔、`gh api`（固定 commit SHA permalink）。

本檔分兩部分。第一部分是 9 個成熟 App 的內建除錯工具；第二部分是 Flutter 生態的 App 內除錯套件，
以及插件／腳本開發者工具的先例。各部分保留自己的標記說明、SHA 對照與「查不到／推測」附錄。

---

## 第一部分：成熟 App 的內建除錯工具


### 標記說明

- 每一條事實後面以 `（<permalink>）` 標出來源；GitHub 一律用固定 40 字元 commit SHA 的 permalink，網頁用 URL。
- `**推測**`：原始碼或文件只給出間接線索，結論是我從現有證據推出來的，不是原文直述。
- 「查不到」：在該專案預設分支的原始碼與可見文件中找不到對應實作或頁面，不代表該版本一定沒有。
- 文中不出現任何實際的 cookie / token / key 值；若來源範例含有這類值，一律以 `***` 表示。

### 目標清單與 SHA

| App | repo | commit SHA |
|---|---|---|
| NewPipe | TeamNewPipe/NewPipe | `7e5df38aad4b2c035332b3f71aee3064d4fdaae4` |
| Immich mobile | immich-app/immich | `aa023378477fb1a65d24f4614de0940f6a769794` |
| AppFlowy | AppFlowy-IO/AppFlowy | `5cf3a365dec0d59f64bad1ee4bb1050471a39b93` |
| LocalSend | localsend/localsend | `6f6cd3ee496903e2206c51ffa3a13a5d10bc340b` |
| Spotube | KRTirtho/spotube | `69a310c78f5ceaf4eab7dfee98f187d38211c9ba` |
| Namida | namidaco/namida | `acb1e1622600440cc793f389f497e6771c732c5e` |
| Firefox Android（fenix） | mozilla-firefox/firefox | `b478a70dbe9b20189bb57f12c05bc0d6a8f323bd` |
| Signal Android | signalapp/Signal-Android | `6151a523373e02f37d6a367fe448bd15a3de1a72` |
| Home Assistant companion | home-assistant/android | `47e0f53ac9f96f8002e0f022df7c28ee1c24a06a` |

---

### NewPipe

**入口與啟用**：Debug 是**主設定頁的一般可見項目**，不是隱藏入口、也沒有 build flag 守門。`main_settings.xml` L56-61 的 `<PreferenceScreen android:fragment="...DebugSettingsFragment" android:icon="@drawable/ic_bug_report" android:key="@string/debug_pref_screen_key" android:title="@string/settings_category_debug_title"/>`；字串 `settings_category_debug_title` 值為 `Debug`（https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/res/xml/main_settings.xml、https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/res/values/strings.xml）。同時在 `SettingsResourceRegistry` 以 `add(DebugSettingsFragment.class, R.xml.debug_settings).setSearchable(false)` 註冊，因此**不出現在偏好搜尋結果**（https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/settings/SettingsResourceRegistry.java）。

**有哪些區塊**：`debug_settings.xml` 是單一 PreferenceScreen；`DebugSettingsFragment` 提供開關與動作兩類（https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/settings/DebugSettingsFragment.java、https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/res/xml/debug_settings.xml）：

- 開關：allow heap dumping、show memory leaks、allow disposed exceptions、show original time ago、show crash the player。
- 動作：check new streams（`NotificationWorker.runNow`）、crash the app（`throw new RuntimeException("Dummy")`）、show error snackbar、create error notification。

**LeakCanary 的 build 相依**：透過 build-variant-dependent（BVD）介面 `DebugSettingsFragment.DebugSettingsBVDLeakCanaryAPI`，由實作類別以 `Class.forName(...)` 反射載入；`DebugSettingsBVDLeakCanary.java` 只存在於 `app/src/debug/` source set，內容是把 `getNewLeakDisplayActivityIntent()` 轉呼叫 `LeakCanary.INSTANCE.newLeakDisplayActivityIntent()`（https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/debug/java/org/schabi/newpipe/settings/DebugSettingsBVDLeakCanary.java）。實作類別不存在時，相關偏好以 summary `leak_canary_not_available` 呈現（停用）。`app/src/` 下的 source set 為 `androidTest`、`debug`、`main`、`test`。

**Log 檢視**：查不到 app 內 log viewer（無 live 串流、level 篩選、搜尋或條目上限的實作）。

**網路檢視**：查不到 HTTP request 檢視頁。

**狀態檢視**：查不到即時播放／佇列狀態面板；Debug 頁只有開關與觸發動作。

**Export / Share**：主要落在錯誤流程 `ErrorActivity`（https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/error/ErrorActivity.kt）：

- 顯示欄位：user action、request、content language/country、app language、service、timestamp（ISO8601 帶 offset）、package、version、OS，以及 stack traces。
- 按鈕：email（`mailto:crashreport@newpipe.schababi.org`）、複製 markdown 到剪貼簿（`ShareUtils.copyToClipboard(this, buildMarkdown())`）、開 GitHub issue 頁；選單「share error」以 `ShareUtils.shareText` 分享 JSON。`buildMarkdown()` 產生 GitHub issue 用 markdown，多個 exception 用 `<details>` 折疊。
- 觸發鏈：`AcraReportSender` 把 ACRA 的 stack trace 交給 `ErrorUtil.openActivity(context, new ErrorInfo(new String[]{report.getString(ReportField.STACK_TRACE)}, UserAction.UI_ERROR, "ACRA report", null, R.string.app_ui_crash))`（https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/error/AcraReportSender.java）；`ErrorUtil` 另有 `showSnackbar`、`createNotification`（id 5340681，靜音＋toast）與前景／背景判斷（`KEY_IS_IN_BACKGROUND`）（https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/error/ErrorUtil.kt）。

**遮蔽（Redaction）**：查不到自動 redaction 機制；email／GitHub 送出前有一個隱私政策對話框作為告知 gate（https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/error/ErrorActivity.kt）。

---

### Immich mobile

**入口與啟用**：profile drawer 的一列 ListTile（`Icons.assignment_outlined`，label `profile_drawer_app_logs`）→ `context.pushRoute(const AppLogRoute())`（https://github.com/immich-app/immich/blob/aa023378477fb1a65d24f4614de0940f6a769794/mobile/lib/widgets/common/app_bar_dialog/app_bar_dialog.dart L103-109、L290）。路由以 `AutoRoute(page: AppLogRoute.page, guards: [_duplicateGuard])` 註冊，`AppLogDetailRoute` 同（https://github.com/immich-app/immich/blob/aa023378477fb1a65d24f4614de0940f6a769794/mobile/lib/routing/router.dart L135-136）。

**有哪些區塊**：App log 頁、App log detail 頁、app bar server info（app version+build、server version、server URL、version warning banner）、settings 的 sync status 頁（https://github.com/immich-app/immich/blob/aa023378477fb1a65d24f4614de0940f6a769794/mobile/lib/pages/common/app_log.page.dart、https://github.com/immich-app/immich/blob/aa023378477fb1a65d24f4614de0940f6a769794/mobile/lib/pages/common/app_log_detail.page.dart、https://github.com/immich-app/immich/blob/aa023378477fb1a65d24f4614de0940f6a769794/mobile/lib/widgets/common/app_bar_dialog/app_bar_server_info.dart、https://github.com/immich-app/immich/blob/aa023378477fb1a65d24f4614de0940f6a769794/mobile/lib/pages/settings/sync_status.page.dart）。

**Log 檢視**：`AppLogPage` 讀 `LogService.I.getMessages()`；level 以顏色點表示（info=primary、severe=redAccent、warning=orangeAccent、其他=grey），tile 背景依 level 上色；每筆顯示 `at HH:mm:ss.SSS in <logger>`，訊息經 `truncateLogMessage(msg, 4)`，點擊進入 detail。detail 頁分 MESSAGE / DETAILS / FROM（logger）/ STACK TRACE 四段，每段一個複製 IconButton（`Clipboard.setData` + snackbar `copied_to_clipboard`），文字用 `SelectableText`。頁面動作：clear logs（`immichLogger.clearLogs()`）、share（`ImmichLogger.shareLogs`）。

**條目上限與 level 來源**：`LogService` 包 dart `logging`，監聽 `Logger.root.onRecord`，先緩衝進 `LogRepository`（DB），5 秒 flush timer；init 時 `logRepository.truncate(limit: kLogTruncateLimit)`；docstring 說超過 `maxLogEntries`（預設 500）會刪舊。level 取自設定 `SettingsKey.logLevel`，`Logger.root.level = Level.LEVELS.elementAtOrNull(...)`；`getMessages()` 回 `[..._msgBuffer.reversed, ...logsFromDb]`（https://github.com/immich-app/immich/blob/aa023378477fb1a65d24f4614de0940f6a769794/mobile/lib/domain/services/log.service.dart）。`kLogTruncateLimit` 的實際數值查不到。

**匯出檔案**：`ImmichLogger.shareLogs(context)` 寫 `${tempDir}/Immich_log_$isoDateTime.log`，行格式 `created | level(padRight 8) | logger(padRight 20) | message | error |` 後接 stack，再用 `Share.shareXFiles([XFile(filePath)], subject: "Immich logs $dateTime")`，分享完刪檔。docstring 稱格式為 CSV，但程式實際寫的是純文字行（https://github.com/immich-app/immich/blob/aa023378477fb1a65d24f4614de0940f6a769794/mobile/lib/services/immich_logger.service.dart）。

**網路檢視**：查不到 HTTP request 檢視頁；`network.service.dart` 只處理 Wi-Fi 名稱與權限（https://github.com/immich-app/immich/blob/aa023378477fb1a65d24f4614de0940f6a769794/mobile/lib/services/network.service.dart）。

**狀態檢視**：sync status 頁顯示 entity counts，並有三個動作（https://github.com/immich-app/immich/blob/aa023378477fb1a65d24f4614de0940f6a769794/mobile/lib/widgets/settings/beta_sync_settings/sync_status_and_actions.dart）：export database（WAL checkpoint 後複製 `immich.sqlite` → `immich_export_$ts.sqlite`，`Share.shareXFiles`，30 秒後自動刪）、clear file cache、reset SQLite DB（附確認對話框）。

**遮蔽**：查不到。

---

### AppFlowy

**入口與啟用**：行動版 Settings → Support 群組；桌面版 Settings → Manage data（https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/mobile/presentation/setting/support_setting_group.dart、https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/workspace/presentation/settings/pages/settings_manage_data_view.dart）。桌面 Settings 對話框本體已 import `share_log_files.dart`（https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/workspace/presentation/settings/settings_dialog.dart）。

**有哪些區塊**：

- mobile Support 群組：Join Discord、Report issue（bottom sheet 內含「Report issue on GitHub」連結與「Export log files」→ `shareLogFiles(context)`）、Clear cache（呼叫 `WorkspaceDataManager.checkViewHealth(dryRun: false)`）。
- desktop Manage data：export data、`FixDataWidget`、SettingsCategory「Export log files」（用 `shareLogFiles`）。

**Log 檢視**：查不到 app 內 log 檢視頁（無 live、level、篩選、搜尋）。

**匯出**：`shareLogFiles(context)` 遞迴列 `getApplicationSupportDirectory()` 下 basename `startsWith('log.')` 的檔，用 `archive` 的 `ZipEncoder` 打包成 `appflowy_logs.zip`；Android/iOS 以 `Share.shareXFiles` / `Share.shareUri` 分享後刪檔；桌面以 `afLaunchUri` 開資料夾；沒有檔案時 toast `noLogFiles`（https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/util/share_log_files.dart）。

**網路檢視**：查不到。

**狀態檢視**：查不到即時狀態面板（`checkViewHealth` / `FixDataWidget` 是資料修復動作，不是狀態呈現）。

**遮蔽**：查不到。

**除錯基礎設施（非使用者可見頁面）**：`DebugTask` 用 `talker` + `talker_bloc_logger`，只在 `kDebugMode` 設 `Bloc.observer = TalkerBlocObserver(...)`，行動版 debug 時隱藏鍵盤，rust tracing 被註解掉（https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/debug_task.dart）；`platform_error_catcher.dart` 只在非 debug 掛 `PlatformDispatcher.instance.onError`，`ErrorWidget.builder` 在 debug 顯示紅橫幅、release 回 `SizedBox.shrink()`（https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/platform_error_catcher.dart）。`shared/feedback_gesture_detector.dart` 的 `FeedbackGestureDetector` 只做 haptics，**推測**與除錯入口無關（https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/shared/feedback_gesture_detector.dart）。

---

### LocalSend

**入口與啟用**：About 頁一個純 TextButton「Debugging」→ `context.push(() => const DebugPage())`；**無 `kDebugMode` 守門**，一般使用者可達（https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/pages/about/about_page.dart L168-173）。

**有哪些區塊**：`DebugPage`（標題 `Debugging`）：DebugEntry 列（Debug Mode=`kDebugMode`、Portable Mode、Executable Path、Working Directory、Settings Path、App Arguments、Dart SDK=`Platform.version`）＋按鈕 Security、Discovery、HTTP Logs、Refena Tracing（僅 `if (kDebugMode)`）、Clear settings（https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/pages/debug/debug_page.dart）。

**Log 檢視**：

- HTTP Logs：`HttpLogsPage` 監看 `httpLogsProvider`，有「Clear」按鈕；清單項為 `CopyableText`，行首 `[HH:mm:ss] ` 綠色粗體（https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/pages/debug/http_logs_page.dart）。
- Discovery：`DiscoveryDebugPage` 監看 `discoveryLoggerProvider`，按鈕「Announce」（`StartMulticastScan`）＋「Clear」，同樣 `[HH:mm:ss]` 清單（https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/pages/debug/discovery_debug_page.dart）。
- 條目上限：`addLog` 做 `[...state, LogEntry(now, log)].take(200).toList()` → **上限 200 筆**；無 level、無搜尋、僅存記憶體（https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/provider/logging/http_logs_provider.dart、https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/provider/logging/discovery_logs_provider.dart）。`LogEntry{DateTime timestamp, String log}`（https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/model/log_entry.dart）。

**網路檢視**：有 —— HTTP Logs 頁（見上）。`addLog` 的呼叫點在 `nearby_devices_provider.dart` 與 `receive_controller.dart`（https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/provider/network/nearby_devices_provider.dart、https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/provider/network/server/controller/receive_controller.dart）。

**狀態檢視**：查不到即時播放／連線狀態面板。

**匯出／分享**：清單項可逐筆複製（`CopyableText`）；`troubleshoot_page.dart` 的排解卡（症狀／解法，含 Windows 防火牆 `netsh advfirewall` 指令且可複製）（https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/pages/troubleshoot_page.dart）。查不到整批檔案匯出。

**遮蔽**：查不到；`SecurityDebugPage` 直接顯示 Certificate SHA-256 fingerprint、Certificate、Private Key、Public Key 的原始值，未見遮蔽（https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/pages/debug/security_debug_page.dart）。

---

### Spotube

**入口與啟用**：Settings → Developers 區塊的單一 ListTile「Logs」→ `context.navigateTo(const LogsRoute())`；`settings.dart` 以 `if (!kIsWeb) const SettingsDevelopersSection()` 掛載（https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/pages/settings/sections/developers.dart、https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/pages/settings/settings.dart）。

**有哪些區塊**：只有 Logs 一頁。

**Log 檢視**：`LogsPage`（`@RoutePage`，name `logs`）讀 `logsProvider`（`StreamProvider.autoDispose`，逐行讀 `.spotube_logs` 檔），body 是 Card 內 `SelectableText(value)`，空狀態 `no_logs_found`（Undraw 插圖）（https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/pages/settings/logs.dart、https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/logs/logs_provider.dart）。無 level 篩選、無搜尋、無條目上限的實作。

**寫入端**：`AppLogger`（https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/logger/logger.dart）：

- `initialize(bool verbose)` 設 `Logger(level: kDebugMode || (verbose && kReleaseMode) ? Level.all : Level.info)`；`main.dart` 以 CLI 參數呼叫 `AppLogger.initialize(arguments["verbose"])`（https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/main.dart L66）。
- `_initInternalPackageLoggers()` 只在 `kDebugMode`（橋接 `YoutubeExplode.StreamsClient`）。
- `runZoned` 掛 `FlutterError.onError`、`PlatformDispatcher.instance.onError`、isolate 錯誤監聽；`reportError` **只在 `kReleaseMode`** 追加寫檔。
- log 路徑：Android `getExternalStorageDirectory()`；Windows/macOS `getApplicationDocumentsDirectory()` 或 `Library/Logs`；Linux `$XDG_STATE_HOME/spotube` 或 `~/.local/state/spotube`；檔名 `.spotube_logs`。
- `AppLoggerProviderObserver` 上報 provider 失敗。

**網路檢視**：查不到；`services/dio/dio.dart` 的 `final globalDio = Dio();` 沒有掛 interceptor，因此沒有 HTTP log（https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/dio/dio.dart）。`collections/http-override.dart` 只對 `spotify.com` 放行壞憑證（https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/collections/http-override.dart）。

**狀態檢視**：查不到。

**匯出／分享**：頁面 trailing 動作：複製全部到剪貼簿（`Clipboard.setData` + toast `copied_to_clipboard`）、垃圾桶 → `ref.invalidate(logsProvider)` 並 `logsFile.writeAsString("")`。查不到檔案分享（https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/pages/settings/logs.dart）。

**遮蔽**：查不到。

---

### Namida

**入口與啟用**：About 頁的 `NamidaAboutListTile(icon: Broken.clipboard_text, title: lang.shareLogs)`，另附一個寄送按鈕（email 經 `FlutterMailer.send`，遇 `MissingPluginException` 退回 `NamidaUtils.shareFiles`）；`onTap` → `shareFiles(filePaths)`；同頁另有 reportAnIssue 對話框（`_IssueReporter`）（https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/ui/pages/about_page.dart L425-451）。

**有哪些區塊**：無獨立 log 檢視頁；除錯相關面有三個 —— About 頁的 share logs、Sync manager 頁的 diagnostics 與 actions log、Advanced 設定內的快取清除對話框。

**Log 檢視**：查不到 app 內 log viewer（無 live、level、篩選、搜尋頁）。

**Log 寫入**：`logs_controller.dart` 的 singleton `logger` 以 `RandomAccessFile` append 寫入 `AppPaths.LOGS` / `LOGS_FALLBACK`；條目以 FNV hash（error 內容＋前 8 個 stack frame，`_keyStackFrames = 8`）去重，stack 截到 `_maxStackFrames = 48`；重複次數以 `x0001`–`x9999` 就地 patch；`kDebugMode` 時另 `printo`（https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/controller/logs_controller.dart）。

**匯出**：`AppPaths.getAllExistingLogsAndSettingsAsZip()` 在 temp 建 `namida_logs_<yyyy-MM-dd HH.mm.ss>`，複製 `device_info.txt`、`permissions.txt`（Linux 略過），以及 `AppPaths.LOGS`、`LOGS_FALLBACK`、`LOGS_TAGGER` 的遮蔽副本（`_LogsRedactor`），再加 `_writeAllSettingsRedacted`（settings、equalizer、player、youtube、extra、sync、party、tutorial、shortcuts），打包成 `namida_logs_<ts>.zip`。`LOGS` = `$USER_DATA/Logs/logs<suffix>.txt`；`LOGS_FALLBACK` Android `/storage/emulated/0/Documents/namida_logs.txt`，Windows/Linux `<home>/Logs/namida_logs.txt` 或 systemTemp（https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/core/constants.dart L686 起、L955）。

**遮蔽**：`_LogsRedactor` 把 home 目錄換成 `~`，並 `removeExcludedDeviceInfo`（同上，`lib/core/constants.dart`）。

**網路檢視**：查不到 HTTP request 檢視頁。

**狀態檢視**：`SyncDiagnostics.run()` 產生文字報告：`namida <version> | <os> <osVersion> | sync v<kSyncVersion>`；區段 `== interfaces ==`（LAN/preferred/virtual roles）、`== server ==`（tcp addr:port、advertising IPs、client count）、`== windows network ==`（PowerShell `Get-NetConnectionProfile` / `Get-NetFirewallApplicationFilter`）、`== linux firewall ==`、`== discovery ==`；`_kMaxTraceLines = 200`（https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/controller/sync_manager/sync_diagnostics.dart）。呼叫點在 Sync manager 頁 app bar 動作：`_openRecentActionsLog()`（`SyncActionsLog.inst`）、`_openDiagnosticsDialog()`（`_SyncDiagnosticsDialog`）、`_openConnectByIpDialog()`（https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/ui/pages/sync_manager_page.dart）。

**設定入口**：`settings_page.dart` 的 sections 為 Theme、Indexer、Playback、Customization、YouTube、Extras、BackupAndRestore、AdvancedSettings；L324 `const NamidaSyncManagerPage().navigate()`（https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/ui/pages/settings_page.dart）。`advanced_settings.dart` 對 log / debug / diagnos / copy / export / clipboard 的 grep 無命中，只有快取刪除對話框（https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/ui/widgets/settings/advanced_settings.dart）。

---

### Firefox Android（fenix）

**入口與啟用**：

- Nightly：三點選單 → Settings → About Firefox Nightly → 連點 Firefox logo 直到出現 `Debug menu: (#) click(s) left to enable` → 回 Settings 就多出「Secret Settings」與「Secret Debug Info」（https://github.com/mozilla-firefox/firefox/blob/b478a70dbe9b20189bb57f12c05bc0d6a8f323bd/mobile/android/fenix/docs/Secret-settings-debug-menu-instructions.md）。
- 觸發器實作：`SecretDebugMenuTrigger`，**5 次點擊**啟用（`SECRET_DEBUG_MENU_CLICKS = 5`），第 2–4 次回報剩餘次數，`onResume` 時把計數歸零（https://github.com/mozilla-firefox/firefox/blob/b478a70dbe9b20189bb57f12c05bc0d6a8f323bd/mobile/android/fenix/app/src/main/java/org/mozilla/fenix/settings/about/SecretDebugMenuTrigger.kt）。
- 另有 build 期開關：`local.properties` 的 `secretSettings.<pref_key>=true`，只作用於 debug build、只接受 boolean（同上 docs）。

**有哪些區塊**：`debugsettings/` 套件目錄含 addons、addresses、autofill、cfrs、crashtools、creditcards、data、distributions、gleandebugtools、info、integrity、ipprotection、listentopage、logins、navigation、region、store、tabprocesstools、tabs、ui。`DebugDrawerRoute.kt` 枚舉的工具：TabTools、Logins、Addresses、CreditCards、Autofill、CfrTools、GleanDebugTools、RegionDebugTools、AddonsDebugTools、CrashDebugTools、IntegrityTools、TabGroupTools、TabProcessTools、DistributionTools、IPProtectionLocationTools、ListenToPageTools（https://github.com/mozilla-firefox/firefox/blob/b478a70dbe9b20189bb57f12c05bc0d6a8f323bd/mobile/android/fenix/app/src/main/java/org/mozilla/fenix/debugsettings/navigation/DebugDrawerRoute.kt）。

**UI 形式**：`DebugDrawer.kt` 是 Compose NavHost drawer（`DEBUG_DRAWER_HOME_ROUTE`，TopAppBar 返回鍵）；`DebugDrawerHome.kt` 以 LazyColumn 列出各 destination 並帶 app 名稱／版本表頭；`DebugOverlay.kt` 是可拖曳 FAB overlay，呈現 app-wide debug 內容（https://github.com/mozilla-firefox/firefox/blob/b478a70dbe9b20189bb57f12c05bc0d6a8f323bd/mobile/android/fenix/app/src/main/java/org/mozilla/fenix/debugsettings/ui/DebugDrawer.kt、https://github.com/mozilla-firefox/firefox/blob/b478a70dbe9b20189bb57f12c05bc0d6a8f323bd/mobile/android/fenix/app/src/main/java/org/mozilla/fenix/debugsettings/ui/DebugOverlay.kt）。

**Log 檢視**：查不到 app 內 log viewer。

**網路檢視**：查不到 HTTP request 檢視頁。

**狀態／資訊檢視**：`DebugInfoRepository.kt` 的區段（https://github.com/mozilla-firefox/firefox/blob/b478a70dbe9b20189bb57f12c05bc0d6a8f323bd/mobile/android/fenix/app/src/main/java/org/mozilla/fenix/debugsettings/info/DebugInfoRepository.kt）：

- Build：Version、VCS Commit、GeckoView、Application Services、Glean SDK、Build Date。
- Device：Android、Manufacturer、Model、Locale。
- Configuration：Telemetry、Crash reporting 的狀態徽章。
- Nimbus experiments：active experiment slug / branch。
- Homepage：feature 狀態。
- Toolbar：position、expanded、tab strip。

DSL 為 `buildSection(title) { textItem(label, value); statusItem(label, enabled) }`；`DebugInfoJson.kt` 用 `JsonWriter`（縮排 3 空白）把 `List<DebugInfoSection>.toJson()` 轉成 JSON；`DebugInfoContent.kt` 是區段檢視加一顆 `OutlinedButton("debug_info_view_json_report")`；`DebugInfoJsonReport.kt` 是 JSON 報告頁（`SelectionContainer` + Header 複製）；`DebugInfoBottomSheetFragment.kt` 用 `DebugInfoProvider.create(settings, nimbusApi, versionName, deviceLocale, secretSettingsKeys)`，版本字串格式 `"%s (Build #%s)"`（同目錄 `DebugInfoDsl.kt`、`DebugInfoJson.kt`、`ui/DebugInfoContent.kt`、`ui/DebugInfoJsonReport.kt`、`DebugInfoBottomSheetFragment.kt`）。

**匯出／分享**：查不到檔案匯出；JSON 報告頁可選取複製（同上）。

**遮蔽**：查不到。

**Nightly-only 與否**：文件把入口寫在 Nightly，但**推測** release / beta 是否同樣可啟用未逐條確認。

---

### Signal Android

**入口與啟用**：Settings → Help 的 `HelpSettingsFragment` 有一列 `HelpSettingsFragment__debug_log`，導向 `action_helpSettingsFragment_to_submitDebugLogActivity`；同頁 Version 長按可複製到剪貼簿並 toast（https://github.com/signalapp/Signal-Android/blob/6151a523373e02f37d6a367fe448bd15a3de1a72/app/src/main/java/org/thoughtcrime/securesms/components/settings/app/help/HelpSettingsFragment.kt）。其他啟動點：`calls/quality/CallQualityBottomSheetFragment`、`database/IssueReporter`、`messages/GroupSendEndorsementInternalNotifier`、`registration/fragments/RegistrationViewDelegate`、`registration/ui/shared/RegistrationScreen`、`mediapreview/MediaPreviewViewModel`。`HelpScreen.kt` L239-247 另有 `Checkbox(checked = state.includeDebugLog)` + 「include debug log」標籤 + 「What's this」TextButton（https://github.com/signalapp/Signal-Android/blob/6151a523373e02f37d6a367fe448bd15a3de1a72/app/src/main/java/org/thoughtcrime/securesms/help/HelpScreen.kt）。

**有哪些區塊**：`SubmitDebugLogActivity` 內以 WebView 呈現（`DebugLogsViewer`）（https://github.com/signalapp/Signal-Android/blob/6151a523373e02f37d6a367fe448bd15a3de1a72/app/src/main/java/org/thoughtcrime/securesms/logsubmit/SubmitDebugLogActivity.java）。

**Log 檢視**：搜尋（含大小寫敏感切換 `filterButton` / `isFiltered`）、level 篩選按鈕 **V / D / I / W / E / SignalUncaughtException**（組出 `[" V "," D ",...]` 形式的 filter string 傳給 `DebugLogsViewer.onFilterLevel`）、scroll-to-top / bottom。內容可能很慢時會先跳警告對話框（同上）。

**內容來源**：`SubmitDebugLogRepository` 的有序 `SECTIONS`：SystemInfo、Jobs、Constraints、Capabilities、Memory、LocalMetrics、RemoteConfig、Pin、Power(API≥28)、Battery、Notifications、NotificationProfiles、ExoPlayerPool、KeyPreferences、Stories、Badges、ChatFolders、RemoteBackups、Permissions、Trace、Threads、SuspiciousThreadDump、CurrentThreadDump、SenderKey（internal 才含）、DatabaseSchema、RemappedRecords、DatabaseIssues、Anr、Logcat、LoggerHeader；每段內容都先過 `Scrubber.scrub(...)`（https://github.com/signalapp/Signal-Android/blob/6151a523373e02f37d6a367fe448bd15a3de1a72/app/src/main/java/org/thoughtcrime/securesms/logsubmit/SubmitDebugLogRepository.java）。

**匯出／分享**：menu save → `Intent.ACTION_CREATE_DOCUMENT`，type `application/zip`，檔名 `signal-log-<ts>.zip`（zip 內含 `log.txt` + `signal.trace`）；submit → `viewModel.onSubmitClicked(...)` → 結果對話框顯示可複製的 debuglogs.org URL + 分享（`ShareCompat.IntentBuilder` 到 `support@signal.org`）。上傳到 `https://debuglogs.org`（先 GET 取 presigned multipart，再 POST），body 為 GZIP。帶 `ARG_VIEW_ONLY` 時 submit 按鈕改成關閉（https://github.com/signalapp/Signal-Android/blob/6151a523373e02f37d6a367fe448bd15a3de1a72/app/src/main/java/org/thoughtcrime/securesms/logsubmit/SubmitDebugLogActivity.java）。

**遮蔽**：`Scrubber.kt` 以 regex 處理下列樣式（https://github.com/signalapp/Signal-Android/blob/6151a523373e02f37d6a367fe448bd15a3de1a72/core/util-jvm/src/main/java/org/signal/core/util/logging/Scrubber.kt）：

- E164 電話號碼：以 HMAC-SHA256 雜湊成 `<8 hex>`（`KEEP_E164::` 前綴者保留原樣）。
- 前導零的 10 位數字。
- email（`...@...`）。
- group IDs v1 / v2、PNI、UUID（`********-****-****-****-*********`）。
- IPv4（`...ipv4...`）、IPv6（`...ipv6...`）。
- URL：host+path → `***.<tld>`，用 TOP_100_TLDS allowlist；例外保留原樣者為非 cdn 的 `*.signal.org` 與 `*.debuglogs.org`。
- call link keys、call link room IDs、MediaIds。

**容量**：`LogDatabase.kt` 定義 `MAX_FILE_SIZE = 20L.mebiBytes`、`DEFAULT_LIFESPAN = 3.days`、`LONGER_LIFESPAN = 21.days`；`trimToSize()` 先扣掉 `KEEP_LONGER = 1` 的量再裁，crash 用的 `trimToSize()` 刪 30 天以上（https://github.com/signalapp/Signal-Android/blob/6151a523373e02f37d6a367fe448bd15a3de1a72/app/src/main/java/org/thoughtcrime/securesms/database/LogDatabase.kt L176-178）。

**網路檢視**：查不到 HTTP request 檢視頁。

---

### Home Assistant companion

**入口與啟用**：Settings 的 `<Preference android:key="developer" android:icon="@drawable/ic_bug_report" android:title="@string/troubleshooting" android:summary="@string/troubleshooting_summary"/>`（`preferences.xml` L224-228）；`SettingsFragment.kt` L390 以 `findPreference<Preference>("developer")` → `replace(R.id.content, DeveloperSettingsFragment::class.java)`。可見、非隱藏（https://github.com/home-assistant/android/blob/47e0f53ac9f96f8002e0f022df7c28ee1c24a06a/app/src/main/res/xml/preferences.xml、https://github.com/home-assistant/android/blob/47e0f53ac9f96f8002e0f022df7c28ee1c24a06a/app/src/main/kotlin/io/homeassistant/companion/android/settings/SettingsFragment.kt）。

**有哪些區塊**：`DeveloperSettingsFragment` → `preferences_developer.xml`（https://github.com/home-assistant/android/blob/47e0f53ac9f96f8002e0f022df7c28ee1c24a06a/app/src/main/kotlin/io/homeassistant/companion/android/settings/developer/DeveloperSettingsFragment.kt、https://github.com/home-assistant/android/blob/47e0f53ac9f96f8002e0f022df7c28ee1c24a06a/app/src/main/res/xml/preferences_developer.xml）：

- `show_share_logs`（「Show and share logs」）→ `replace(R.id.content, LogFragment::class.java)`。
- `location_tracking`：僅 `BuildConfig.FLAVOR == "full"` 時存在。
- `webview_debug`（`remote_debugging`）：由 `DeveloperSettingsPresenterImpl` 的 `PreferenceDataStore` 接到 `WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG || value)`。
- `thread_debug`：`presenter.appSupportsThread()` 為真才顯示，多 server 時先走 `ServerChooserFragment`。
- `tag_clear_allowed`、`webview_clear_cache`。

**Log 檢視**：`LogFragment` 兩個 tab：process log（`LogcatReader.readLog()`，即時讀）與 crash log（`getLatestFatalCrash`）；有 refresh 與 share 選單；另連到 FAQs#android-crash-logs 的說明連結（https://github.com/home-assistant/android/blob/47e0f53ac9f96f8002e0f022df7c28ee1c24a06a/app/src/main/kotlin/io/homeassistant/companion/android/settings/log/LogFragment.kt）。

**Logcat 讀取**：`LogcatReader.kt` 用 `ProcessBuilder("logcat", "--pid=$pid", "-d")`，一次把輸出讀成一個 String；**無條目上限、無 level 篩選、無搜尋**（https://github.com/home-assistant/android/blob/47e0f53ac9f96f8002e0f022df7c28ee1c24a06a/app/src/main/kotlin/io/homeassistant/companion/android/util/LogcatReader.kt）。

**網路檢視**：查不到 HTTP request 檢視頁。

**狀態檢視**：查不到即時狀態面板（thread sync debug 只呈現同步結果）。

**匯出／分享**：`shareLog()` 先跳敏感資料 AlertDialog，字串 `share_logs_sens_message` 原文為 `Please note: by sharing the log, you could share sensitive data like location data or your Home Assistant URL.\n\nDo you want to continue?`；確認後寫 `<externalCacheDir>/logs/homeassistant_companion_log_MM-DD-YYYY_HH-MM-SS.txt`，經 FileProvider 以 `Intent.ACTION_SEND` type `text/plain` 分享，並以 `EXTRA_EXCLUDE_COMPONENTS` 排除 `com.github.android`（GitHub app）（https://github.com/home-assistant/android/blob/47e0f53ac9f96f8002e0f022df7c28ee1c24a06a/app/src/main/kotlin/io/homeassistant/companion/android/settings/log/LogFragment.kt、https://github.com/home-assistant/android/blob/47e0f53ac9f96f8002e0f022df7c28ee1c24a06a/common/src/main/res/values/strings.xml L824-825）。

**遮蔽**：只有分享前的警示對話框；查不到自動 redaction 實作。

---

### 跨對象對照（僅事實，不含建議）

| 面向 | 有實作者 |
|---|---|
| HTTP request 檢視頁 | LocalSend（HttpLogsPage）；其餘 8 個查不到 |
| app 內 log 檢視頁 | immich（AppLogPage／AppLogDetailPage）、Spotube（LogsPage）、Signal（SubmitDebugLogActivity + WebView）、HA（LogFragment）；LocalSend 為 HTTP／Discovery 專用清單 |
| 有 level 篩選 | immich（顏色標示，非篩選按鈕）、Signal（V/D/I/W/E + SignalUncaughtException 篩選按鈕） |
| 有 log 搜尋 | Signal（含大小寫切換） |
| 明示條目／檔案上限 | LocalSend 200 筆（記憶體）、immich `maxLogEntries` 預設 500 + `kLogTruncateLimit`、Signal `MAX_FILE_SIZE` 20 MiB |
| 以檔案分享 | immich（shareXFiles）、AppFlowy（zip）、Namida（zip + email）、Signal（zip 存檔 + 上傳 debuglogs.org）、HA（txt 分享）、LocalSend 查不到 |
| 只有剪貼簿 | Spotube（複製全部）、NewPipe（複製 markdown） |
| 自動 redaction | Signal（`Scrubber` 最完整）、Namida（`_LogsRedactor` 換 home 為 `~`） |
| 僅告知／警示 | HA（分享前 AlertDialog）、NewPipe（隱私政策對話框） |
| 查不到 redaction | immich、AppFlowy、Spotube、LocalSend、Firefox |
| 隱藏入口手勢 | Firefox（logo 連點 5 次）；其餘皆為可見設定項或頁面按鈕 |
| 隱藏入口無 build 守門 | LocalSend（About 頁 TextButton） |
| 需要 build flag 的功能 | NewPipe（LeakCanary 僅 `debug` source set）、Firefox（`secretSettings.*` 僅 debug build）、LocalSend（Refena Tracing 僅 `kDebugMode`） |

---

## 第二部分：Flutter 生態的除錯套件與插件開發者工具


### A. Flutter 生態的 App 內除錯套件

套件版本／發佈日一律取自 `https://pub.dev/api/packages/<name>`（`latest.version` / `latest.published`），
分數／likes／下載量取自 `https://pub.dev/api/packages/<name>/score`。
GitHub 狀態取自 `gh api repos/OWNER/REPO` 與 `gh api repos/OWNER/REPO/commits?per_page=1`。
程式碼引用一律用固定 commit SHA 的 permalink（`/blob/<40 碼 SHA>/path#Lnn`）。

#### 總表（皆為 pub.dev API 查詢結果）

| 套件 | 版本 | 發佈日（UTC） | pub 分數 | likes | 30 天下載 | 平台標籤 |
|---|---|---|---|---|---|---|
| talker | 5.1.20 | 2026-07-28T20:30:11 | 160/160 | 859 | 279142 | 六平台 + wasm |
| talker_flutter | 5.1.20 | 2026-07-28T20:30:22 | 160/160 | 665 | 224239 | 六平台 + wasm |
| talker_dio_logger | 5.1.20 | 2026-07-28T20:30:31 | 160/160 | 150 | 153895 | 六平台 + wasm |
| alice | 1.10.0 | 2026-09-18T10:14:52 | 160/160 | 348 | 27591 | 六平台 + wasm |
| flutter_flipper | 0.0.2 | 2022-05-05T09:55:44 | 25/160 | 0 | 24 | **is:discontinued / is:unlisted** |
| inspector | 4.0.0 | 2026-03-30T07:22:58 | 150/160 | 87 | 496649 | 六平台 + wasm |
| requests_inspector | 5.5.1 | 2026-08-16T12:19:08 | 130/160 | 167 | 6407 | **僅 android + ios** |
| chucker_flutter | 1.9.2 | 2026-05-14T09:51:50 | 130/160 | 197 | 18896 | 六平台 |
| drift_db_viewer | 2.1.0 | 2024-04-08T19:22:05 | 130/160 | 106 | 21078 | 六平台 + wasm |
| isar_inspector | 3.1.0+3 | 2023-05-15T07:46:48 | 60/160 | 0 | 0 | **is:unlisted** |
| flutter_js | 0.8.7 | 2026-01-27T20:22:28 | 140/160 | 360 | 103466 | 五平台（無 web） |
| flutter_qjs | 0.3.7 | 2022-05-19T17:04:46 | 60/160 | 31 | 86 | 無平台標籤；sdk `<3.0.0` |

（talker 三套件同分鐘發佈，屬同一 monorepo；授權皆 MIT。alice 為 apache-2.0。
inspector 的 30 天下載 496649 與 likes 87 的比例明顯異常，**推測**為統計口徑或自動化下載所致，查不到解釋。）

---

#### talker / talker_flutter / talker_dio_logger

- **版本／日期**：三者皆 5.1.20，2026-07-28T20:30（pub.dev API，如上表）。
  授權 MIT。`talker_flutter` 要求 `sdk >=3.6.0 <4.0.0`、`flutter >=1.17.0`。
- **平台**：android / ios / linux / macos / web / windows 全列，並標 `is:wasm-ready`。
- **維護狀態**：repo `Frezyx/talker` 未 archived、MIT、846 stars、96 open issues。
  預設分支最後 commit `654391c1a81c6a0fa4a05d46562cc0d15241d964`（2026-07-28、"Release v5.1.20"），
  但 repo `pushed_at` 為 2026-09-24，晚於預設分支最後 commit，**推測**為其他分支的推送。
- **功能**：`Talker` 本體是 error handler + logger（`talker.handle` / `info` / `error` / `critical`）；
  `talker_flutter` 提供 `TalkerScreen` —— 在 app 內檢視 log、篩選、執行動作、調整設定，
  以及 log history（可設定最大保留筆數）、console 輸出開關、report 分享。
  `talker_dio_logger` 是 Dio interceptor，把 HTTP 呼叫導進同一條 log 流。
- **是否可以只在 debug/developer 模式啟用（release 是否剝離）**：
  **套件本身沒有內建 build-mode 閘門。**
  在預設分支以 `gh search/code` 查 `kReleaseMode` 與 `kDebugMode` 皆 0 筆
  （對照查詢：`TalkerScreen` 34 筆、可證明搜尋 API 正常運作，故 0 筆為真）。
  README 完全未提 release 模式下的行為；`TalkerScreen` 是開發者自己 push 的 widget：
  `Navigator.of(context).push(MaterialPageRoute(builder: (context) => TalkerScreen(talker: talker)))`。
  context7 條目 `/frezyx/talker`（316 snippets）同樣只示範自行 push，未提 release。
  `TalkerDioLoggerSettings` 有 `enabled`（預設 `true`）與 print 旗標，屬執行期開關而非編譯期閘門。

#### alice

- **版本／日期**：1.10.0，2026-09-18T10:14:52（pub.dev API）。授權 apache-2.0，publisher `hasoft.pl`。
  `sdk >=3.13.0 <4.0.0`、`flutter >=3.29.0`（門檻相當新）。
  pub.dev 上 1.4.0 → 1.10.0 一系列版本集中在 2026-09-15～09-18 之間發佈（快速補版）。
- **平台**：六平台全列，標 `is:wasm-ready`。
- **維護狀態**：repo `jhomlala/alice` 未 archived、636 stars、1 open issue，
  最後 commit `2943b1901aec10cbeed82e57d6cb9a3122a25304`（2026-09-18、
  "feat: Add programmatic call tagging and N+1 duplicate detection (#327)"）。
  GitHub API 的 `license` 欄位為 `null`（pub.dev 標 apache-2.0）。
- **架構**：monorepo 多套件：`alice`、`alice_dio`、`alice_http`、`alice_http_client`、
  `alice_chopper`、`alice_graphql_client`、`alice_objectbox`、`alice_test`
  —— 讓使用者只拉自己 HTTP client 對應的那一個。
- **功能**：HTTP 呼叫列表、單筆 request/response 詳情、JSON tree viewer、
  timeline（Gantt 時間軸）、統計 dashboard、N+1 重複呼叫偵測、程式化 tag（`alice.tag(...)`）、
  請求重送（replay）、搖一搖開啟、通知開啟、匯出 TXT/HAR、以 ObjectBox 持久化歷史。
- **release 是否剝離**：**沒有 inspector 的 build-mode 閘門。**
  repo 內唯一用到 `kReleaseMode` 的地方是
  [`packages/alice/lib/src/utils/utils.dart#L7`](https://github.com/jhomlala/alice/blob/2943b1901aec10cbeed82e57d6cb9a3122a25304/packages/alice/lib/src/utils/utils.dart#L7)，
  用途僅是抑制 `debugPrint`：
  ```dart
  import 'package:flutter/foundation.dart' show kReleaseMode, debugPrint;
  class AliceUtils {
    static void log(String logMessage) {
      if (!kReleaseMode) {
        debugPrint(logMessage);
      }
    }
  }
  ```
  它不影響 inspector UI 是否掛載 —— 閘門要由 app 自己加。
- **context7**：**查不到** `jhomlala/alice` 條目。`resolve-library-id` 對 "Alice" 只回傳無關的同名套件
  （Go middleware `/justinas/alice`、PHP fixtures `/nelmio/alice`、Yandex Alice 等），故 alice 的
  敘述全部來自 pub.dev API 與 GitHub 原始碼／README。

#### flutter_flipper 與 inspector

兩者常被放在同一格討論，但性質差很多，分開列。

**flutter_flipper**（舊路線，已死）
- **版本／日期**：0.0.2，2022-05-05T09:55:44（pub.dev API）。pub 標記 **`is:discontinued` 與 `is:unlisted`**，
  分數 25/160、likes 0、30 天下載 24。`sdk: 2.14.3`（精確釘死，非範圍）、`flutter >=2.5.2`。
- **維護狀態**：repo `lwj1994/flutter_flipperkit` 未 archived 但實質停擺：1 star、0 open issues，
  最後 commit `66678eea25b815bb912498e9b7d8c57bad69033f`（2022-05-05、"Remove db and sp plugin"）。
- **上游**：`facebook/flipper` 本身**已 archived**（`gh api` `archived: true`）、13452 stars、
  506 open issues、最後 commit `13f95a067f56bb3772937a8f281b0a7eacda7080`（2025-09-26、
  "reroute public download to github releases (#5722)"）。
  **事實**：Flipper 桌面平台已終止，Flutter 綁定套件隨之無維護。

**inspector**（現行，純 widget 檢視器）
- **版本／日期**：4.0.0，2026-03-30T07:22:58（pub.dev API）。MIT，150/160，六平台 + wasm，
  `sdk >=2.12.0 <4.0.0`、`flutter >=3.22.0`。
- **維護狀態**：repo `kekland/inspector` 未 archived、60 stars、9 open issues，
  最後 commit `60f989097f168e384a93b7e738665109d8f8ee2c`（2026-03-30）。
  README 自述仍在開發中（WIP）。
- **功能**：掛在 `MaterialApp.builder` 上的 widget 檢視器 —— widget 尺寸／padding／
  顏色／TextStyle 檢視、縮放、鍵盤快捷鍵。**不涵蓋網路或 DB**，與 alice 那類 HTTP inspector 定位不同。
- **release 是否剝離**：**有內建 build-mode 閘門。** README 原文：
  > Optionally, you can pass `isEnabled` to the `Inspector` to disable it.
  > By default, the inspector is disabled when `kReleaseMode == true`.

#### requests_inspector

- **版本／日期**：5.5.1，2026-08-16T12:19:08（pub.dev API）。MIT。130/160、likes 167、30 天下載 6407。
  `sdk >=2.17.0 <4.0.0`、`flutter >=1.20.0`。
- **平台**：pub.dev 平台標籤**只有 `platform:android` 與 `platform:ios`**。
  README 卻記載 Web / Windows / MacOS / Linux 可用長按開啟 —— 兩者不一致（**事實陳述，未找到官方解釋**）。
- **維護狀態**：repo `Abdelazeem777/requests_inspector` 未 archived、MIT、21 stars、14 open issues，
  最後 commit `8c08c212e7b59d5c017564cbca5c886f52caa897`（2026-08-16、"chore: Release version 5.5.1"）。
- **功能**：HTTP + GraphQL + WebSocket log、請求中止器（可編輯後重送）、
  以 Log / cURL / HAR 格式分享。
- **release 是否剝離**：**沒有 build-mode 閘門。** repo 內 `kReleaseMode` / `kDebugMode` 皆 0 筆。
  掛載方式與預設值見
  [`lib/src/requests_inspector_widget.dart#L99`](https://github.com/Abdelazeem777/requests_inspector/blob/8c08c212e7b59d5c017564cbca5c886f52caa897/lib/src/requests_inspector_widget.dart#L99)：
  ```dart
  const RequestsInspector({
    super.key,
    bool enabled = true,          // 預設開啟
    bool hideInspectorBanner = false,
    ShowInspectorOn showInspectorOn = ShowInspectorOn.Both,
    required Widget child,
  });
  ...
  bool _isSupportShaking() =>
      kIsWeb ? false : Platform.isAndroid || Platform.isIOS;
  ```
  即 `enabled` 預設 `true`，且沒有 `kDebugMode` 之類的編譯期判斷；觸發方式依平台決定為搖晃或長按。

#### chucker_flutter

- **版本／日期**：1.9.2，2026-05-14T09:51:50（pub.dev API）。MIT。130/160、likes 197、30 天下載 18896。
  `sdk >=3.0.0 <4.0.0`。平台標籤六平台全列。
- **維護狀態**：repo `syedmurtaza108/chucker-flutter` 未 archived、MIT、84 stars、26 open issues，
  最後 commit `1ecae1b90430e7260516dc4179882a10657c9fcc`（2026-06-30），
  repo `pushed_at` 2026-09-24（晚於預設分支最後 commit）。
- **功能**：HTTP 呼叫列表、依狀態碼篩選、request/response 詳情、錯誤檢視、可由通知列開啟。
  Android 需 `minSdkVersion 22`。
- **release 是否剝離**：**有內建 build-mode 閘門。** 見
  [`lib/src/view/helper/chucker_ui_helper.dart#L189`](https://github.com/syedmurtaza108/chucker-flutter/blob/1ecae1b90430e7260516dc4179882a10657c9fcc/lib/src/view/helper/chucker_ui_helper.dart#L189)：
  ```dart
  ///[showOnRelease] decides whether to allow Chucker Flutter working in release
  ///mode or not. By default its value is `false`
  static bool showOnRelease = false;
  ///[isDebugMode] A wrapper of Flutter's `kDebugMode` constant
  static bool isDebugMode = kDebugMode;
  static final chuckerButton = (isDebugMode || ChuckerFlutter.showOnRelease)
      ? ChuckerButton.getInstance()
      : const SizedBox.shrink();
  ```
  README 原文：
  > By default Chucker Flutter only runs in `debug` mode but you can allow it to run
  > in release mode too using its `showOnRelease` property

  整合方式需提供 `ChuckerFlutter.navigatorKey`（舊的 `navigatorObserver` 因 nested Navigator 已 deprecated）。

#### drift_db_viewer

- **版本／日期**：2.1.0，2024-04-08T19:22:05（pub.dev API）。MIT。130/160、likes 106、30 天下載 21078。
  `sdk >=2.13.0 <4.0.0`、`flutter >=2.2.0`。平台標籤六平台 + wasm。
  **2.1.0 已約 2.5 年沒有新版**（但 repo 仍有 commit）。
- **維護狀態**：repo `vanlooverenkoen/db_viewer` 未 archived、47 stars、15 open issues，
  最後 commit `775d1597326f86950b6f8c551f339ea40818c4a8`（2026-02-06、
  "Fix horizontal scrolling on non-touch devices (#61)"）。GitHub `license` 欄位為 `null`。
- **功能／用法**：`DriftDbViewer(GeneratedDatabase db)` 是一個 StatefulWidget，
  `initState` 內 `DriftDbViewerDatabase.init(widget.db)`，build 出 `DbViewerNavigator`；
  pubspec 依賴 `db_viewer: ^1.1.0`、`drift: >=2.0.0 <3.0.0`、`provider: >=6.0.0 <7.0.0`。
  README 原文：
  > view our database in our development app without the need of exporting your database file.
  > Filtering is done at database level
- **release 是否剝離**：**沒有 build-mode 閘門**（README 以 "development app" 描述用途）。
- **適用範圍（事實）**：只支援 drift 的 `GeneratedDatabase`。
  FMP 的 DB 是 Isar（`pubspec.yaml` L18-19：`isar_community: ^3.3.2`、`isar_community_flutter_libs: ^3.3.2`），
  因此 **drift_db_viewer 不適用於 FMP**。

#### isar_inspector

- **版本／日期**：3.1.0+3，2023-05-15T07:46:48（pub.dev API）。
  pub 標記 **`is:unlisted`**（已下架），分數 60/160、likes 0、30 天下載 0。
  授權 apache-2.0。`sdk >=2.17.0 <4.0.0`（Dart 3 可解析，但仍未更新）。
  依賴：`isar ^3.1.0+1`、`vm_service ^9.0.0`、`web_socket_channel ^2.2.0`、
  `go_router ^5.0.0`、`google_fonts ^4.0.4`、`http ^0.13.6`、`universal_io`、`flutter_svg any`。
- **現況（repo `isar/isar`，最後 commit `713001bf1615ea15460d9bc8d3fb9c8cb4150a2e` 2025-06-14，
  Apache-2.0、4023 stars、185 open issues）**：
  `packages/isar_inspector/pubspec.yaml` 已標 `publish_to: "none"`、version 1.0.0+1、
  `go_router: ^15.1.2`、`vm_service: ^15.0.0`、`web: ^1.1.1`、`flutter_riverpod`，
  且有 `web/index.html` 與 `web/manifest.json` → 已改成 **Flutter web app**。
- **運作模型**：`packages/isar_inspector/lib/main.dart` L28 路由為 `/:port/:secret`，
  L18-19 歡迎字串原文：
  > Welcome to the Isar Inspector!
  > Please open the link displayed when running the debug version of an Isar app.

  → inspector 是獨立的 web 前端，透過 port + secret 連到 app；該連結**只在 app 的 debug build 印出**，
  這是此生態「只在 debug 可用」的實際機制。
- **release 是否剝離**：repo 內 `kDebugMode` 0 筆（`gh search/code`）。
  閘門不在 inspector 端，而在 app 端（debug 才印出連線連結）。
- **查不到**：isar.dev 官方文檔的 inspector 頁面目前 404，**無法確認現行官方 inspector 說明頁 URL**。
- **上游警語**：`isar` README 原文：
  > ISAR V4 IS NOT READY FOR PRODUCTION USE
  > If you want to use Isar in production, please use the stable version 3.

---

### B. 插件／腳本開發者工具的先例

#### MusicFree（maotoumao/MusicFree）

- **基本資料**：React Native；AGPL-3.0；27160 stars；281 open issues；預設分支 `master`；
  最後 commit `d118b18b3d0c904400f7eea7bf99c0ceec6c1aee`（2026-06-20、"修复：稳定性与跨平台优化"）；
  repo `pushed_at` 2026-09-13。
- **插件形態**：單一 CommonJS `.js` 檔。App 啟動時掃描固定資料夾；官方文檔站
  （musicfree.catcat.work）載明路徑：
  Android `Android/data/fun.upup.musicfree/files/plugins`；
  桌面 `C://Users/{userName}/AppData/Roaming/MusicFree/musicfree-plugins`。
  安裝時把 js 寫入該資料夾並以隨機檔名儲存；`platform` 相同時比較 `version`，
  **較舊版本不會覆蓋較新版本**（要先解除安裝）。
- **載入與沙箱**（`src/core/pluginManager/plugin.ts`，1121 行）：
  - `_require`（L69）：只暴露固定的純 JS 套件表 —— `axios`、`cheerio`、`dayjs`、
    `big-integer`、`qs`、`he`、`cookies`、`webdav`、`crypto-js`、`nanoid`、`immer`、
    `object-path`、`compare-versions`、`react-native-url-polyfill` 等。插件無法自行 `require` 任意模組。
  - `_consoleBind`（L75）：把插件的 `console` 導向自建 devLog。
  - `mountPlugin()`（L905）以 `new Function(...)` 包裹插件碼，注入
    `(require, __musicfree_require, module, exports, console, env, URL, process)`；
    見 [L934-949](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/pluginManager/plugin.ts#L934)：
    ```ts
    _instance = Function(`
        'use strict';
        return function(require, __musicfree_require, module, exports, console, env, URL, process) {
            ${funcCode}
        }
    `)(_require, _require, _module, _module.exports, _console, env, URL, _process);
    ```
  - 生命週期狀態機（Initializing / Loading / Error）；`loadFuncCode()` 搭配 `ensureMounted()`（L890）延遲載入。
- **App 內除錯面板**：`src/components/debug/index.tsx` 原文：
  ```tsx
  const showDebug = useAppConfig("debug.devLog");
  return showDebug ? (
    <View style={style.wrapper} pointerEvents="box-none"><VDebug /></View>
  ) : null;
  ```
  `VDebug` 來自 vendored 的 `@/lib/react-native-vdebug`（React Native 的 in-app log/網路面板），
  由 app config `debug.devLog` 開關。
- **檔案日誌**（`src/utils/log.ts`）：用 `react-native-logs` + `fileAsyncTransport`，
  寫出 `error-log-{date-today}.log` 與 `trace-log.log`；`trace()` 由
  `Config.getConfig("debug.traceLog")` 控制；`addLog`（來自 react-native-vdebug）另外餵面板。
  `src/core/appConfig.ts` 把舊鍵映射到 `debug.errorLog` / `debug.traceLog` / `debug.devLog`。
- **官方插件開發文檔章節**（文檔站）：`introduction`、`basic-type`、`protocol`、
  `how-to-develop`、`how-to-develop-with-ai`、`internal-pkgs`、`caution`。
  文檔把「除錯」寫成「在 Node.js 環境執行插件函式並檢查回傳值」；只允許純 JS 函式庫
  （不可有原生依賴）。**未見 devtools 或熱重載機制**。
- **註記**：網路上大量 MusicFree 插件教學是 AIGC 生成且互相抄襲，內容與原始碼不符；
  本文只採 GitHub 原始碼（固定 SHA）與官方文檔站。

#### LX Music（lyswhut/lx-music-desktop、lx-music-mobile）

- **基本資料**：
  - `lyswhut/lx-music-desktop`：Apache-2.0、54016 stars、1282 open issues、
    最後 commit `ad95d5091c9ed689fa72b5e5c849df65f5a679ce`（2026-09-19、"发布 v2.12.6"）；
    Electron 30+ / Vue 3。
  - `lyswhut/lx-music-mobile`：Apache-2.0、18469 stars、781 open issues、
    最後 commit `fb8480728d875fa5e0da25eebd3a26bb71723aae`（2026-09-19、"发布 v1.9.1"）；React Native。
  - `lyswhut/lx-music-source`：MIT、401 stars、1 open issue、
    最後 commit `55eb9881dad6ca895505352f3a0a7d1dfa3444e0`（2024-06-12、"修复kw url获取"）
    —— 自訂源腳本的 webpack 專案模板（`src/` + `dist/` + `webpack.config.js`）。
- **自訂源介面**（官方文檔 https://lxmusic.toside.cn/desktop/custom-source）：
  腳本為 UTF-8 JavaScript（ES6+），需 `@name / @description / @version / @author / @homepage`
  頭部註解。與 app 以事件溝通：
  - `inited`：payload `{ sources, openDevTools }`，文檔原文「`openDevTools`：是否打开 DevTools，
    此选项可用于开发脚本时的调试」→ **每個自訂源可選擇開啟 DevTools 除錯**。
  - `request`：handler `({ source, action, info })` 必須回傳 Promise；action 為
    `musicUrl` / `lyric` / `pic`。
- **執行模型（desktop）**：每個 user API 跑在**獨立的隱藏 Electron BrowserWindow**，
  見 `src/main/modules/userApi/main.ts`（155 行）：
  - `createWindow()`（L58）：先 `await closeWindow()`，再建
    [BrowserWindow](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/userApi/main.ts#L58)，
    `webPreferences` 為 `contextIsolation: true`（L84）、`nodeIntegration: false`、
    `nodeIntegrationInWorker: false`、`sandbox: false`（L88）、自訂 preload；
    對 `will-navigate` / `will-redirect` / `will-attach-webview` / `will-prevent-unload` /
    `media-started-playing` 一律 `preventDefault`。
    以 `loadURL('data:text/html;charset=UTF-8,' + encodeURIComponent(html))`（L123）載入空白頁，
    再於 `ready-to-show` 送出 `initEnv`（含 `script: await getScript(userApi.id)` 與 proxy）。
  - `closeWindow()`（L134）：清除 auth cache / storage / cache 後 `browserWindow.destroy()`。
  - `openDevTools()`（L151）：對該 window 的 `webContents` 開 DevTools。
- **重新載入模型**（`src/main/modules/userApi/index.ts`）：
  [`setApi(id)`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/userApi/index.ts#L24)（L24）
  若已有作用中的 api 先 `closeWindow()`（L25-27）再 `loadApi(id)`（L32）；`removeApi` 同樣關窗。
  → **切換／重新匯入自訂源 = 拆掉整個 JS runtime 再重建**，沒有原地熱重載；
  `inited` 事件的 `openDevTools` 是唯一內建除錯入口。

#### VS Code extension host 的 reload

- **架構**：extension host 是獨立程序，三種形態 —— local（Node.js）、web（WebWorker）、
  remote（Node.js）。官方頁面 `advanced-topics/extension-host` 只講這三種 host 的設定，
  **未描述任何 reload 指令或熱重載**。
- **官方開發流程**（`api/get-started/your-first-extension`）：F5 啟動 Extension Development Host 視窗；
  改完擴充程式碼後，在該視窗執行 **「Developer: Reload Window」** 即可讓改動生效，再重跑命令。
  該頁**未提及「Restart Extension Host」**，也**未描述熱重載**（查不到官方對熱重載的說明）。
- **原始碼**（`microsoft/vscode` @ `acfc00a9e482b98f6383b4e69ba3dd771cce02b1`）：
  - 字串 `restartExtensionHost` 出現 11 次，含
    [`src/vs/workbench/contrib/relauncher/browser/relauncher.contribution.ts#L296`](https://github.com/microsoft/vscode/blob/acfc00a9e482b98f6383b4e69ba3dd771cce02b1/src/vs/workbench/contrib/relauncher/browser/relauncher.contribution.ts#L296)
    （`await extensionService.stopExtensionHosts(localize('restartExtensionHost.reason', "Changing workspace folders"))`）
    與 `src/vs/workbench/contrib/extensions/browser/extensionsActions.ts`。
  - 指令 ID 字面值 `workbench.action.restartExtensionHost` 只出現在 3 個檔案
    （含 `src/vs/workbench/services/extensions/electron-browser/nativeExtensionService.ts` 與
    copilot 擴充），而 `workbench.action.reloadWindow` 出現 15 處
    （含 `src/vs/workbench/browser/actions/windowActions.ts`、
    `src/vs/workbench/electron-browser/actions/developerActions.ts`）。
  - `ExtensionMode` enum 定義於
    [`src/vs/workbench/api/common/extHostTypes.ts#L2719`](https://github.com/microsoft/vscode/blob/acfc00a9e482b98f6383b4e69ba3dd771cce02b1/src/vs/workbench/api/common/extHostTypes.ts#L2719)；
    `ExtensionMode.Development` 用於從開發路徑（`--extensionDevelopmentPath`）載入的擴充。

#### 從資料夾載入腳本並熱重載的一般做法

**Flutter 熱重載的限制**（官方 docs.flutter.dev/tools/hot-reload，原文節錄）：
- 「**Only Flutter apps in debug mode can be hot reloaded or hot restarted.**」→ 熱重載／熱重啟僅限 debug。
- 「it doesn't rerun `main()` or `initState()`」。
- 「Global variables and static fields are treated as state, and are therefore not reinitialized
  during hot reload」。
- 失敗案例包含：更動 enum 型別、更動泛型宣告、原生程式碼變更（需整支重啟）等。

**release 剝離的語言機制**：`kDebugMode` / `kReleaseMode` / `kProfileMode` 是 `const bool`，
值來自 `bool.fromEnvironment('dart.vm.product' | 'dart.vm.profile')`。
`packages/flutter/lib/src/foundation/constants.dart`（flutter @ `43596b3519f61ebd934229bb72c712caaefe6a9b`）
dartdoc 原文：
> Since this is a const value, it can be used to indicate to the compiler that a particular
> block of code will not be executed in release mode, and hence can be removed.

dartdoc 亦註明一般建議改用 `kDebugMode` 或 `assert`，因為 `kReleaseMode` 會引入 release/profile 差異。
→ 這是把整段除錯碼從 release 產物移除的既有機制。

**Dart `Isolate.spawnUri` 與 AOT**：
- API 文檔（`api.dart.dev/stable/dart-isolate/Isolate/spawnUri.html`）**未寫** AOT 限制。
- `dart-lang/sdk` issue #54528（已關閉）原文：
  > `spawnUri` throws an exception in AOT mode if `jit-snapshot`, `kernel` or a dart library
  > were given (e.g. ```The uri provided to Isolate.spawnUri() does not contain a valid AOT snapshot.```)
- SDK 測試 [`runtime/tests/vm/dart/spawn_uri_aot_test.dart`](https://github.com/dart-lang/sdk/blob/815bb2e3dd88f9b6325615aaa6f338886b94dab6/runtime/tests/vm/dart/spawn_uri_aot_test.dart)
  （dart-lang/sdk @ `815bb2e3dd88f9b6325615aaa6f338886b94dab6`）顯示 AOT runtime 在 `isAOTRuntime` 下
  可以 spawn 已編譯 `.dill` / AOT snapshot 的 isolate。
- → **AOT 下 spawnUri 必須指向合法的 AOT snapshot，不能餵原始 `.dart` 或 kernel。**

**嵌入 JS 引擎（flutter_js）**：
- 版本 0.8.7，2026-01-27T20:22:28（pub.dev API）；MIT；140/160；likes 360；30 天下載 103466；
  平台 android / ios / linux / macos / windows（無 web）；`sdk >=3.0.0 <4.0.0`。
  repo `abner/flutter_js`：MIT、542 stars、81 open issues、
  最後 commit `c3d4bba92278577c6cc73e7b10a69b358f23768b`（2026-01-27、"fix performance issue in toUTF8"）。
- 引擎配置（README）：**Android / Windows / Linux 用 QuickJS；iOS / macOS 用 JavaScriptCore**。
- 抽象介面 `JavascriptRuntime`（`lib/javascript_runtime.dart`）提供：
  `dispose()`、`evaluate(String code, {String? sourceUrl})`、`evaluateAsync`、
  `setInspectable(bool)`、`setupBridge(String channelName, void Function(dynamic) fn)`、
  `getEngineInstanceId()`、`executePendingJob()`、`convertValue<T>()`；入口 `getJavascriptRuntime()`。
- iOS JS 除錯（README）：`javascriptRuntime.setInspectable(true)`，並對 `evaluate` 傳入 `sourceUrl`
  （用 Safari Web Inspector）。
- README 明確**反對**在 iOS 使用 QuickJS，理由是 App Store Review Guidelines §4.7。
- **推測**：README 未描述「熱重載」；從 API 形狀看，重新載入一份腳本的單位是整個 runtime 實例
  （`dispose()` 後重建 `getJavascriptRuntime()`），但沒有官方文字這樣建議。
- 替代品 `flutter_qjs`（ekibun）0.3.7，2022-05-19T17:04:46（pub.dev API）、60/160、likes 31、30 天下載 86，
  且 `sdk: '>=2.12.0-0 <3.0.0'`（**不允許 Dart 3**）→ 已無法在 Dart 3 專案解析。
- 另查 `js_runtime` 套件：pub.dev API **NOT_FOUND（查不到）**。

**Electron 以 BrowserWindow 當沙箱 JS host**：見上方 B2 LX Music
（`sandbox` / `contextIsolation` / `nodeIntegration` 設定、data-URL 載入、銷毀重建）。

**Apple 審查條款**（developer.apple.com/app-store/review/guidelines/，原文節錄）：
- §2.5.2：
  > Apps should be self-contained in their bundles, and may not read or write data outside the
  > designated container area, nor may they download, install, or execute code which introduces
  > or changes features or functionality of the app, including other apps. Educational apps
  > designed to teach, develop, or allow students to test executable code may, in limited
  > circumstances, download code provided that such code is not used for other purposes. Such
  > apps must make the source code provided by the app completely viewable and editable by the user.
- §4.7（標題）：
  > Mini apps, mini games, streaming games, chatbots, plug-ins, and game emulators … Apps may
  > offer certain software that is not embedded in the binary, specifically HTML5 and JavaScript
  > mini apps and mini games, streaming games, chatbots, and plug-ins. Additionally, retro game
  > console and PC emulator apps can offer to download games.
- §4.7.1：須符合 1.2（使用者產生內容）與 3.1（付款）；§4.7.2：
  > Your app may not extend or expose native platform APIs or technologies to the software
  > without prior permission from Apple.
  §4.7.3：未經逐次明示同意不得分享資料或隱私權限；§4.7.4：須提供軟體索引與 metadata
  （universal links）；§4.7.5：須有年齡分級機制。
- 註：§2.5.2 與 §4.7 系列同時標註適用於 Notarization Review。

---

### 附錄：固定 SHA 出處清單

| 對象 | SHA（40 碼） | 備註 |
|---|---|---|
| Frezyx/talker | `654391c1a81c6a0fa4a05d46562cc0d15241d964` | 2026-07-28，預設分支最後 commit |
| jhomlala/alice | `2943b1901aec10cbeed82e57d6cb9a3122a25304` | 2026-09-18 |
| lwj1994/flutter_flipperkit | `66678eea25b815bb912498e9b7d8c57bad69033f` | 2022-05-05 |
| facebook/flipper | `13f95a067f56bb3772937a8f281b0a7eacda7080` | 2025-09-26；repo 已 archived |
| kekland/inspector | `60f989097f168e384a93b7e738665109d8f8ee2c` | 2026-03-30 |
| Abdelazeem777/requests_inspector | `8c08c212e7b59d5c017564cbca5c886f52caa897` | 2026-08-16 |
| syedmurtaza108/chucker-flutter | `1ecae1b90430e7260516dc4179882a10657c9fcc` | 2026-06-30 |
| vanlooverenkoen/db_viewer | `775d1597326f86950b6f8c551f339ea40818c4a8` | 2026-02-06 |
| isar/isar | `713001bf1615ea15460d9bc8d3fb9c8cb4150a2e` | 2025-06-14 |
| maotoumao/MusicFree | `d118b18b3d0c904400f7eea7bf99c0ceec6c1aee` | 2026-06-20 |
| lyswhut/lx-music-desktop | `ad95d5091c9ed689fa72b5e5c849df65f5a679ce` | 2026-09-19 |
| lyswhut/lx-music-mobile | `fb8480728d875fa5e0da25eebd3a26bb71723aae` | 2026-09-19 |
| lyswhut/lx-music-source | `55eb9881dad6ca895505352f3a0a7d1dfa3444e0` | 2024-06-12 |
| abner/flutter_js | `c3d4bba92278577c6cc73e7b10a69b358f23768b` | 2026-01-27 |
| microsoft/vscode | `acfc00a9e482b98f6383b4e69ba3dd771cce02b1` | 引用檔皆為此 SHA |
| flutter/flutter | `43596b3519f61ebd934229bb72c712caaefe6a9b` | `constants.dart` dartdoc |
| dart-lang/sdk | `815bb2e3dd88f9b6325615aaa6f338886b94dab6` | `spawn_uri_aot_test.dart`；issue #54528 |

### 附錄：查不到 / 推測清單

- **查不到**：context7 未收錄 `jhomlala/alice`（只找到同名無關套件）；alice 的資訊全部來自
  pub.dev API 與 GitHub 原始碼／README。
- **查不到**：isar.dev 官方文檔的 inspector 說明頁（目前 404），無法確認現行官方文件 URL。
- **查不到**：pub.dev `js_runtime`（NOT_FOUND）。
- **查不到**：VS Code 官方文檔對「擴充程式碼熱重載」的說明 —— 官方只給 Reload Window 流程。
- **查不到**：`inspector` 的 30 天下載 496649 相對 likes 87 的異常比例，未找到解釋。
- **推測**：`Frezyx/talker` 與 `syedmurtaza108/chucker-flutter` 的 `pushed_at` 晚於預設分支最後 commit，
  推測來自其他分支的推送。
- **推測**：flutter_js README 未描述熱重載；「重新載入腳本的單位是整個 runtime 實例」是從 API 形狀推得。
- **推測**：requests_inspector 的平台標籤與 README 描述不一致（README 記 Web/Desktop 可用長按），
  未找到官方解釋。
