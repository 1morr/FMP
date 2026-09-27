# 套件與平台查證：下載引擎、權限、內嵌標籤、HTTP 續傳、平台沙盒

- **查證日期**：2026-09-28
- **查證方式**：優先 **context7** 官方文檔；context7 無對應條目時改用
  **tavily-search / tavily-extract** 取官方文檔、RFC 或平台官方頁面。
  套件版本與最後發佈日期一律以 **pub.dev**（頁面與 `https://pub.dev/api/packages/<name>` 的
  `published` 絕對時間戳）為準；repo 狀態用 `gh api`。README 抓不到時才用搜尋工具。
- **範圍限制**：全程唯讀。**未呼叫任何真實 API、未執行 app、未跑測試**。
  因此凡是「CDN 實際回應」一類需要打 API 才能確認的事實，一律標「**推測**」；
  找不到可靠來源的標「**查不到**」。
- **檔案結構**：本檔由兩份平行調查合併而成 —— **第一部（下載引擎與權限）**、
  **第二部（內嵌標籤、HTTP 續傳、平台下載位置）**。兩部各自有字母編號的章節與
  「與 FMP 決策相關的關鍵事實」，故字母在部內有意義，跨部不連續。

---

# 第一部：下載引擎與權限

## A. 背景下載套件

### A1. `background_downloader`

**版本與維護狀態**

- 最新版本 **9.6.3**，發佈 **2026-09-25T20:33:49Z**。來源：`https://pub.dev/api/packages/background_downloader`
- pub points **160/160**、likes **504**、30 天下載 **237,854**。來源：`https://pub.dev/api/packages/background_downloader/score`
- Repo 已從 `bbflight/background_downloader` 移到 **`781flyingdutchman/background_downloader`**（pubspec 的 `repository` 欄位；`bbflight` 路徑已 404）。default branch `main`，最後 push 2026-09-25，238 stars，open issues 0，未 archived。來源：`gh api repos/781flyingdutchman/background_downloader`、`https://pub.dev/api/packages/background_downloader`
- 版本節奏密：9.5.9（2026-08-29）→ 9.6.0（09-07）→ 9.6.1（09-10）→ 9.6.2（09-16）→ 9.6.3（09-25）。來源：同上 API
- 需求：Dart SDK `^3.13.0`、Flutter `>=3.47.0`（`pubspec.yaml`）。Android 端要求 Kotlin 2.1.0+。來源：`https://github.com/781flyingdutchman/background_downloader/blob/main/pubspec.yaml`、`README.md`

**平台支援**

- pubspec 宣告 `platforms: android / ios / linux / macos / windows`，**沒有 web**。來源：`https://github.com/781flyingdutchman/background_downloader/blob/main/pubspec.yaml`
- README 標題即寫「for iOS, Android, MacOS, Windows and Linux」；Windows 與 Linux「No setup is required」。來源：`https://github.com/781flyingdutchman/background_downloader/blob/main/README.md`

**底層實作（差異極大，是重點）**

- Android：`WorkManager` + `JobScheduler`（Android 14+ 的 UIDT，`UIDTJobService`）。iOS／macOS：background `URLSession`。來源：`https://github.com/781flyingdutchman/background_downloader/blob/main/doc/ARCHITECTURE.md`
- 桌面（Windows / Linux / macOS）：**純 Dart 實作**，`DesktopDownloader` + 每個任務一個 `Isolate` + `package:http`（`io_client`）。原文：「Unlike mobile, desktop OSs generally allow long-running processes, so `WorkManager` or `URLSession` equivalents are not used.」來源：同上
- 桌面**沒有系統級持久化**：「There is no 'system' persistence for tasks on Desktop. If the app closes, the Isolate dies, and the download stops.」Dart 側 `Database` 只保留 task 的*記錄*，重啟後可依 Range header 續傳（邏輯允許的話）。來源：同上
- 桌面對照表（同頁）：Background Engine = Dart `Isolate`、Persistence = **App Lifecycle only**。來源：同上

**通知**

- 只在 iOS / Android 產生通知（進度／完成／暫停／取消、可設進度條、`tapOpensFile`）。桌面上**完全不產生通知**，原文：「No notifications will be generated: On desktop platforms, as there is no true background mode」。來源：`https://github.com/781flyingdutchman/background_downloader/blob/main/doc/notifications.md`
- Android 13+ 需在 manifest 加 `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />`。來源：同上
- Android 14+ 用 `TransferHint.userInitiated` 或 `priority: 0`（UIDT）時，OS **要求**有使用者可見的通知；沒設定 notificationConfig 可能排不進去或被取消，且需 `android.permission.RUN_USER_INITIATED_JOBS`。來源：`doc/notifications.md`、`doc/parameters.md`

**暫停／續傳**

- 要開 `allowPause: true`（或 `TransferHint.largeFile` / `userInitiated`）。原文限制：「Pausing is only possible for download GET requests, only if the `Task.allowPause` field is true, and only if the server supports pause/resume.」可用 `taskCanResume` 查伺服器是否支援。來源：`https://github.com/781flyingdutchman/background_downloader/blob/main/doc/lifecycle.md`
- 桌面同樣走 Range + ETag：`download_isolate.dart` 送 `Range: bytes=<start>-`，並在 resume 時驗證 ETag（不同或 weak 就丟 `TaskException('Cannot resume: ETag is not identical, or is weak')`）；伺服器不支援 ranges 就不能 resume。來源：`https://github.com/781flyingdutchman/background_downloader/blob/main/lib/src/desktop/download_isolate.dart`

**自訂 HTTP header 與並行上限**

- `headers`（`Map<String,String>`）、`urlQueryParameters`、`httpRequestMethod`、`post`、`retries`（1–10，指數退避）。來源：`https://github.com/781flyingdutchman/background_downloader/blob/main/doc/parameters.md`
- 並行上限用 holding queue：`await FileDownloader().configure(globalConfig: (Config.holdingQueue, (maxConcurrent, maxConcurrentByHost, maxConcurrentByGroup)))`，傳 `null` 表示該項不限。holding queue 是**原生側**，app 被暫停仍會從佇列拉任務；Dart 側的 `MemoryTaskQueue`（`maxConcurrent` / `maxConcurrentByHost` / `maxConcurrentByGroup`）則會隨 app 暫停而停。來源：`doc/lifecycle.md`
- 桌面 `DesktopDownloader` 的預設值：`maxConcurrent = 10`、`maxConcurrentByHost = unlimited`、`maxConcurrentByGroup = unlimited`。來源：`https://github.com/781flyingdutchman/background_downloader/blob/main/lib/src/desktop/desktop_downloader.dart`（`var maxConcurrent = 10;` 與 `configure` 的 `?? 10`）

**Dart 側進度**

- 拿得到。`FileDownloader().updates` stream（`TaskStatusUpdate` / `TaskProgressUpdate`）、`registerCallbacks`、以及 `Transfer` handle 的 `progressNotifier`（0.0–1.0）、`statusNotifier`、`networkSpeedNotifier`、`timeRemainingNotifier`、`holdReasonNotifier`。來源：`README.md`、`doc/transfers.md`

**Android 下載到 app 私有目錄 vs 自選資料夾**

- `BaseDirectory` 的選項（`.applicationDocuments` / `.temporary` / `.applicationSupport` / `.applicationLibrary`）**全部是 app 私有**。要給使用者看到，得下載完成後 `FileDownloader().moveToSharedStorage(task, SharedStorage.downloads)`。`SharedStorage` 選項：`.downloads`（全平台，iOS 是假的）、`.images` / `.video`（Android+iOS）、`.audio`（Android+iOS，iOS 假）、`.files` / `.external`（僅 Android）。iOS 的「假」是在 app Documents 下開子目錄。來源：`https://github.com/781flyingdutchman/background_downloader/blob/main/doc/storage.md`
- 直接寫入使用者自選資料夾要用 URI API：`downloader.uri.pickDirectory()` + `UriDownloadTask(directoryUri: ...)`；Android 上此路徑**繞過暫存檔直接寫入目的**。**但 URI 下載不能暫停或續傳**（原文：「Note that Uri downloads cannot be paused or resumed.」），且 Android 上目的 URI 有檔案不代表下載成功（可能是半截）。來源：`https://github.com/781flyingdutchman/background_downloader/blob/main/doc/URI.md`
- 桌面沒有內建檔案／目錄 picker；官方建議用 `file_picker` 拿路徑再轉 `Uri.file(path, windows: Platform.isWindows)`。來源：`doc/URI.md`
- `openFile`：Android 上 `BaseDirectory.applicationDocuments` 裡的檔案**不能開**，要改存 `.applicationSupport` 或先搬到 shared storage。來源：`doc/notifications.md`

**Android 執行時間限制**

- WorkManager 標準背景任務上限 **9 分鐘**；要跑更久需 `allowPause: true`（自動跨 9 分鐘循環續傳）或 Android 14+ 的 `priority: 0`（UIDT，免限）。`priority < 5` 視為 expedited，上限 **2 分鐘**。來源：`README.md`、`doc/parameters.md`
- 重定向：桌面與前景請求最多 10 個；行動平台用系統預設（iOS 16、Android 20）。來源：`README.md`（9.6.3 changelog：「Raise HTTP redirect limit to 10 for desktop and foreground requests」）

---

### A2. `flutter_downloader`

- 最新版本 **1.12.1**，發佈 **2026-08-22T08:28:20Z**。來源：`https://pub.dev/api/packages/flutter_downloader`
- pub points **140/160**、likes **1,641**、30 天下載 **156,521**。來源：`https://pub.dev/api/packages/flutter_downloader/score`
- 平台：**只有 Android 與 iOS**。`pubspec.yaml` 的 `flutter.plugin.platforms` 只有 `android` 與 `ios`；README 第一句「A plugin for creating and managing download tasks. Supports iOS and Android.」→ **不支援任何桌面平台**。來源：`https://github.com/fluttercommunity/flutter_downloader/blob/master/pubspec.yaml`、`.../README.md`
- 底層：Android 用 `WorkManager`、iOS 用 `NSURLSessionDownloadTask`。來源：`.../README.md`
- Repo：940 stars、**351 open issues**、最後 push 2026-08-22（與 pub 發佈同日）。來源：`gh api repos/fluttercommunity/flutter_downloader`
- README 有一段維護者開發註記，值得注意：「The changes of external storage APIs in Android 11 cause some problems with the current implementation. I decide to re-design this plugin with new strategy to manage download file location. It is still in triage and discussion in this PR (#550).」來源：`.../README.md`
- 安全：README 明言**舊版本有 SQL injection 漏洞**，建議升級到最新版。來源：`.../README.md`
- iOS 限制（README）：「This plugin only supports save files in `NSDocumentDirectory`」。來源：`.../README.md`

**與 `background_downloader` 的差異（事實層面）**

- 平台：flutter_downloader 只有 Android/iOS；background_downloader 另有 Windows/Linux/macOS（桌面為 Dart isolate、無系統背景）。
- flutter_downloader 的 Android 檔案位置策略正是它自己承認還沒重設計的部分（Android 11 外部儲存 API 變更）；background_downloader 另外提供 `BaseDirectory`（app 私有）與 SAF URI 兩條路，且文件化各自的限制。
- flutter_downloader 是高人氣舊套件（1.64k likes）但 open issues 多（351）、改版慢（1.12.0 → 1.12.1 隔了約 19 個月）。background_downloader 活躍（1 個月內 5 個版本、open issues 0）。
- 來源：上述兩套件的 pub.dev 頁與 README。

---

### A3. 在 `dio` 自己下載

- `dio` 最新版本 **5.11.1**，發佈 **2026-09-04**。points **160/160**、likes **8,352**、30 天下載 **4,577,877**。來源：`https://pub.dev/api/packages/dio`、`https://pub.dev/api/packages/dio/score`

**事實**

- `Dio.download` 的公開簽名（5.11.1）：
  `Future<Response> download(String urlPath, dynamic savePath, {ProgressCallback? onReceiveProgress, Map<String, dynamic>? queryParameters, CancelToken? cancelToken, bool deleteOnError = true, FileAccessMode fileAccessMode = FileAccessMode.write, String lengthHeader = Headers.contentLengthHeader, Object? data, Options? options})`。
  來源：`https://pub.dev/documentation/dio/latest/dio/Dio/download.html`
- `onReceiveProgress(received, total)`：若檔案被壓縮且用預設 content-length header，`total` 會是 **-1**；官方建議設 `accept-encoding: '*'` 讓 `total` 不是 -1。來源：同上
- `deleteOnError` 預設 `true`（失敗時刪掉半截檔）；`FileAccessMode.append` 存在但 **web 不支援**。**公開 API 沒有任何自動續傳／resume 參數** —— 續傳要自己送 `Range` header（`Options(headers: ...)`）並自己決定 append。來源：同上
- 取消：`CancelToken`（一個 token 可共用於多個請求；`CancelToken.isCancel(error)`）。來源：`https://pub.dev/packages/dio`
- dio **不在背景 isolate 執行請求**；唯一的 isolate 用法是 default transformer 對 >50KB 的回應做 `jsonDecode`。下載進度與取消都在 main isolate 的 callback／token 上。來源：`https://pub.dev/packages/dio`

**與上面兩者的取捨（事實）**

- 控制權最大：自訂每一條 header、重試、重定向、續傳策略、寫檔位置、檔案命名（`savePath` 可傳 `FutureOr<String> Function(Headers)`）。代價是全部要自己寫（續傳、進度持久化、失敗重試、並行上限）。
- 沒有 OS 層背景排程：dio 跑在 app 的 Dart 執行環境。Android 要「切到背景／螢幕關掉仍跑完」需自己開 foreground service（社群常用 `flutter_foreground_task`，最新 **11.0.3**、發佈 **2026-09-07**、points 150/160、likes 583、30 天下載 218,915：`https://pub.dev/api/packages/flutter_foreground_task`）；Windows 沒有等價機制（推測：Flutter 生態沒有現成的 Windows service 套件，未查證）。
- 對比 `background_downloader`：後者已在 Android 端用 WorkManager/UIDT 處理 app 被殺後續傳、在 iOS 用 background URLSession、並處理 WorkManager 9 分鐘上限，且提供 Transfer API（進度 notifier、暫停續傳、通知）。自己用 dio 等於把這些重做一遍。
- 對比 `flutter_downloader`：dio 至少能覆蓋桌面。
- 「在 isolate 下載」不改變背景限制：isolate 隨 process 死亡，Android 上 app 程序被殺（非前景服務）就停；桌面 app 關閉就停。

---

## B. 權限

### B1. `permission_handler`

**版本與維護狀態**

- 最新版本 **13.0.2**，發佈 **2026-09-04T09:59:07Z**。來源：`https://pub.dev/api/packages/permission_handler`
- pub points **160/160**、likes **6,014**、30 天下載 **3,432,295**。來源：`https://pub.dev/api/packages/permission_handler/score`
- Repo `baseflow/flutter-permission-handler`：2,174 stars、開放 issue 162、最後 push 2026-09-26、未 archived。來源：`gh api repos/baseflow/flutter-permission-handler`

**平台支援**

- `flutter.plugin.platforms` 只宣告四個 endorsed implementation：`android` → `permission_handler_android`、`ios` → `permission_handler_apple`、`web` → `permission_handler_html`、`windows` → `permission_handler_windows`。**沒有 macOS、沒有 Linux**。來源：`https://pub.dev/api/packages/permission_handler`（pubspec）
- pub.dev 頁面平台標籤同樣是 Android / iOS / web / Windows。來源：`https://pub.dev/packages/permission_handler`
- **Windows 實作是近乎 no-op 的 stub**：`checkPermissionStatus` 永遠回 `GRANTED`；`requestPermissions` 對每個傳入的 permission 都回 `GRANTED`；`shouldShowRequestPermissionRationale` 與 `openAppSettings` 都回 `false`（唯一真正做事的只有 `checkServiceStatus` 的 location / bluetooth / ignoreBatteryOptimizations 分支）。來源：`https://github.com/Baseflow/flutter-permission-handler/blob/main/permission_handler_windows/windows/permission_handler_windows_plugin.cpp`
  - 推測（未實測）：在 Windows 上呼叫 `Permission.x.request()` 一律回 granted，且不會有任何系統 UI；`openAppSettings()` 是 no-op。
- macOS / Linux：無實作 → 推測呼叫時會 `MissingPluginException` 或 `UnimplementedError`（未在文檔中明寫，**查不到**正式說明）。

**`openAppSettings()`**

- 用途：開啟本 app 的系統設定頁，讓使用者手動開啟權限。官方範例註解：「The user opted to never again see the permission request dialog for this app. The only way to change the permission's status now is to let the user manually enable it in the system settings.」來源：`https://github.com/Baseflow/flutter-permission-handler/blob/main/permission_handler/README.md`

**denied vs permanentlyDenied**

- Android：**`status` 永遠不會回 `permanentlyDenied`**（`permission_handler_android` 14.1.0 起的刻意行為）。README：「On Android, only the result of `request()` can be `permanentlyDenied`; `status` reports `denied` instead.」實作 dartdoc 補充：OS 無法區分「從未請求」「使用者在設定裡重設為每次詢問」「永久拒絕」，所以一律回 denied；只有 `request()` 的結果能回 `permanentlyDenied`，而且真為永久拒絕時**不會彈對話框**、直接回傳。來源：`.../permission_handler/README.md`、`https://github.com/Baseflow/flutter-permission-handler/blob/main/permission_handler_android/android/src/main/java/com/baseflow/permissionhandler/PermissionManager.java`
- iOS：README 只對 Android 做了「status 不回 permanentlyDenied」的聲明 → **反推** iOS 的 `status` 可以回 `permanentlyDenied`（未白紙黑字寫出，標「推測」）。iOS 的實務事實：使用者拒絕後再 `request()` 不再彈，只能 `openAppSettings()` 導去設定。
- 不彈對話框的權限（README 原文）：`Notification`、`Bluetooth`。會**直接開對應設定頁**的：`manageExternalStorage`、`systemAlertWindow`、`requestInstallPackages`、`accessNotificationPolicy`。來源：`.../permission_handler/README.md`

**FMP 相關的 permission 對應（Android 實作）**

- `Permission.audio` → `Manifest.permission.READ_MEDIA_AUDIO`。來源：`https://github.com/Baseflow/flutter-permission-handler/blob/main/permission_handler_android/android/src/main/java/com/baseflow/permissionhandler/PermissionUtils.java`
- `Permission.notification` → `Manifest.permission.POST_NOTIFICATIONS`（`checkPermissionStatus` 走 `NotificationManagerCompat.areNotificationsEnabled()`；Android 13+ 實際查 `POST_NOTIFICATIONS`）。來源：`PermissionUtils.java`、`PermissionManager.java`
- `Permission.manageExternalStorage` → `MANAGE_EXTERNAL_STORAGE`；API 30+ 時 `request()` 會開 `Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` 設定頁，狀態查 `Environment.isExternalStorageManager()`；API 30 以下回 `RESTRICTED`。來源：`PermissionManager.java`
- `Permission.storage` → `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE`；README 說明這兩個在 Android 10（API 29）起 deprecated、**Android 13（API 33）起完全移除**，媒體存取要改用 `Permission.photos` / `videos` / `audio`。來源：`.../permission_handler/README.md`

---

### B2. Android 13+ `POST_NOTIFICATIONS`

- Android 13（API 33）新增的 runtime 權限，用於「non-exempt (including Foreground Services (FGS)) notifications」。Manifest：`<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`；執行期用 `ActivityResultContracts.RequestPermission()`。來源：`https://developer.android.com/develop/ui/views/notifications/notification-permission`
- 未取得時**靜默封鎖**：新安裝預設通知關閉；使用者按「不要允許」後「all notification channels are blocked, except for a few specific roles」。若 app target 12L 或更低，使用者按一次「不要允許」就不再被問，直到重裝或 app 升到 target 13+。來源：同上
- 檢查現況用 `NotificationManager.areNotificationsEnabled()`。來源：同上
- **豁免（原文）**：「Notifications related to media sessions are exempt from this behavior change.」→ **media session 的通知不需要 POST_NOTIFICATIONS**。來源：同上（Exemptions 段）
- **Foreground service 通知不豁免**：沒權限時使用者只在 Task Manager 看得到 FGS 通知，通知抽屜看不到。原文：「if the user denies the notification permission, they still see notices related to foreground services in the Task Manager but don't see them in the notification drawer.」來源：同上
- 另一項豁免是自行管理通話的 app（`MANAGE_OWN_CALLS` + `ConnectionService` + `registerPhoneAccount()`）。來源：同上
- 對 FMP 的意義：**播放中的媒體通知**（Media3 / media session）豁免；但**下載進度／完成通知**屬 FGS 或一般通知，Android 13+ 要 `POST_NOTIFICATIONS`。`background_downloader` 也是這樣要求（見 A1）。

---

### B3. Android `READ_MEDIA_AUDIO`（13+）／`READ_EXTERNAL_STORAGE`（舊）

- 讀取**其他 app 建立的**音訊檔，Android 13+ 宣告 `READ_MEDIA_AUDIO`；Android 9（API 28）以下要 `READ_EXTERNAL_STORAGE`（讀）與 `WRITE_EXTERNAL_STORAGE`（寫）。來源：`https://developer.android.com/training/data-storage/shared/media`
- Android 10（API 29）走舊路徑（`File` API 直接路徑）需要 `requestLegacyExternalStorage="true"` + `READ_EXTERNAL_STORAGE`。來源：同上
- Android 11（API 30）：若 app 有 `READ_EXTERNAL_STORAGE`，**可以用裸檔案路徑讀媒體檔**（File API / `fopen()`）。原文：「Running on Android 11 — 1. request the `READ_EXTERNAL_STORAGE` permission. 2. Access the files using direct file paths.」來源：`https://developer.android.com/training/data-storage/use-cases`
- 但 Android 13 起 `READ_EXTERNAL_STORAGE` 被移除／停用（見 B1 的 permission_handler FAQ）。→ 推測：Android 13+ 讀**其他 app 的**音訊檔要靠 `READ_MEDIA_AUDIO`；`READ_MEDIA_AUDIO` 是否同樣允許裸路徑讀取，官方頁面沒有像 Android 11 段落那樣白紙黑字說明（**查不到**明確聲明）。
- 讀寫**自己建立的**媒體檔，Android 10+ 不需任何儲存權限。來源：`https://developer.android.com/training/data-storage/shared/media`
- 寫入 MediaStore：`ContentResolver.insert()` + `MediaStore.Audio.Media`，長寫入用 `IS_PENDING=1`→`0`；建立／更新時**不要**用 `DATA` 欄位，用 `DISPLAY_NAME` 與 `RELATIVE_PATH`。來源：同上
- Android 14 部分授權：`READ_MEDIA_VISUAL_USER_SELECTED` **只管 images / videos**。原文：「Android 14 introduces Selected Photos Access, which allows users to grant apps access to specific images and videos in their library」。整頁**完全沒有提到 audio**，manifest 與 runtime 範例只搭 `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO`。→ **音訊沒有對應的部分授權**，仍是全有全無。來源：`https://developer.android.com/about/versions/14/changes/partial-photo-video-access`
- Permission group 對應：`Permission.audio` → `READ_MEDIA_AUDIO`（見 B1）。

---

### B4. Android 11+ scoped storage 與 `MANAGE_EXTERNAL_STORAGE`

**`MANAGE_EXTERNAL_STORAGE` 授予什麼（原文）**

- 「Read and write access to all files within shared storage.」「Access to the contents of the `MediaStore.Files` table.」「Access to the root directory of both the USB on-the-go (OTG) drive and the SD card.」「Write access to all internal storage directories except `/Android/data/`, `/sdcard/Android`, and most subdirectories of `/sdcard/Android`. **This write access includes direct file path access.**」
- 仍**不能**存取其他 app 的 app-specific 目錄（`Android/data/<other>`）。來源：`https://developer.android.com/training/data-storage/manage-all-files`

**怎麼請求與檢查**

- Manifest：`<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />`。
- 導向設定頁：官方 manage-all-files 頁寫的是 `Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)`（列出所有 app）。
- **per-app 版本**：`Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`，**API level 30 加入**，constant value `android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`，**Intent 的 data URI 必須是 `package:<packageName>`**，原文：「The Intent's data URI MUST specify the application package name whose ability of managing external storage you want to control.」啟動該 activity 需要 `MANAGE_EXTERNAL_STORAGE` 權限。來源：`https://developer.android.com/reference/android/provider/Settings#ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`
- 檢查：`Environment.isExternalStorageManager()`。來源：`https://developer.android.com/training/data-storage/manage-all-files`
- 測試用：`adb shell appops set --uid PACKAGE_NAME MANAGE_EXTERNAL_STORAGE allow`。來源：同上

**Google Play 政策（受限權限）**

- 適用範圍：target Android 11（API 30）+ 且宣告 `MANAGE_EXTERNAL_STORAGE` 的 app（`READ_EXTERNAL_STORAGE` 不受此限）。需在 Play Console 填 Permissions Declaration Form 並**通過審核**才可發佈。
- 許可用途：file management、backup and restore、anti-virus、document management、on-device file search、disk/folder encryption、device migration。
- **不許可**的用途明確包含：「Media files access」（改用 MediaStore API）與「Any File selection activity where the user manually selects individual files」（改用 Storage Access Framework）。
- 強制力原文：「Apps that fail to meet policy requirements or do not submit a Permissions Declaration Form **may be removed from Google Play**.」未申報／欺騙性使用「may result in a suspension of your app and/or termination of your developer account」。來源：`https://support.google.com/googleplay/android-developer/answer/10467955`
- **對 FMP 的實際影響**：FMP 依 ADR 0004 決定不上架任何應用商店（只從 GitHub Releases 散佈），所以這條 Play 政策對它**沒有實際拘束力**；受限權限的「許可用途」清單也就不構成阻礙。政策風險只在「哪天要上架」時才成立。來源：`C:\Users\Roxy\orca\FMP\docs\adr\0004-android-storage-without-mediastore.md`（該 ADR 已引同一政策頁並做了相同判斷）

---

### B5. SAF（Storage Access Framework）

**機制與限制**

- `ACTION_OPEN_DOCUMENT_TREE`（Android 5.0 / API 21 起）讓使用者選一個目錄，授權涵蓋該目錄下所有檔案與子目錄，但**不含**該目錄外的其他 app 檔案。來源：`https://developer.android.com/training/data-storage/shared/documents-files`
- Android 11（API 30）起**不能**要求：內部儲存根目錄、可靠 SD 卡根目錄、`Download` 目錄、`Android/data/` 與 `Android/obb/` 及其子目錄。來源：同上
- 授權時效：一般 URI permission **只到裝置重啟為止**；`contentResolver.takePersistableUriPermission(uri, FLAG_GRANT_READ_URI_PERMISSION or FLAG_GRANT_WRITE_URI_PERMISSION)` 可跨重啟。原文警語：「Even after calling `takePersistableUriPermission()`, your app doesn't retain access to the URI if the associated document is moved or deleted.」來源：同上
- 所有 I/O 走 `ContentResolver`（`openFileDescriptor` / `openInputStream`）與 `DocumentsContract.deleteDocument`。來源：同上
- 官方頁面**沒有**明寫「document URI 不能轉成檔案路徑」這句話（該頁通篇以 URI 操作，未下此結論）—— 這是**查不到的原文**，見下一點的替代證據。

**關鍵問題：SAF 目錄下能不能用 `dart:io` 裸路徑寫檔？**

- 答案：**不能**（在 scoped storage 生效的 Android 10+／11+ 上）。
- 佐證一（官方語意的反面）：「`MANAGE_EXTERNAL_STORAGE` grants … Write access to all internal storage directories … **This write access includes direct file path access.**」（`https://developer.android.com/training/data-storage/manage-all-files`）→ 反面即：**沒有**這個權限就沒有 shared storage 的直接路徑寫入權。
- 佐證二（官方對「讀」的說明只給到 Android 11 的 `READ_EXTERNAL_STORAGE`，且未涵蓋寫入）：`https://developer.android.com/training/data-storage/use-cases`。
- 佐證三（套件作者的第一手陳述）：`saf` 套件 README 首行即以粗體寫「**Scoped storage broke `File('/storage/emulated/0/…')`. `saf` is the fix.**」，並說明 1.x 的 path-based API 已改名 `LegacySaf`、將於 3.0.0 移除，新 API 是 URI-based「store URIs, not paths」。來源：`https://github.com/jvoltci/saf/blob/master/README.md`
- 佐證四（外掛實作證據）：`file_picker` 的 Android 端把 SAF tree URI **用字串組出**路徑（見下），但這條路徑在 Android 11+ 上無寫入權；`shared_storage` 的官方文件直言 `getRealPathFromUri`（content URI → 真路徑）**在 Android 10+（API 29+）已不再支援**。來源：`https://github.com/vicajilau/flutter_file_picker`（`FileUtils.kt`）、`https://alexrintt.github.io/shared-storage/Usage/Storage%20Access%20Framework/`
- 推測（未實測）：拿 SAF 授權後再用 `File(path).writeAsBytes()` 寫該目錄，在 Android 11+ 會失敗（`FileSystemException` / `EACCES`）；要寫入必須走 `ContentResolver` 或 `MANAGE_EXTERNAL_STORAGE`。

**Dart 側相關套件**

- **`saf`** — 最新 **2.1.2**，發佈 **2026-08-25T09:32:29Z**；points **160/160**、likes **71**、30 天下載 **2,961**；**Android only**（Dart ≥3.0、Flutter ≥3.10、minSdk 21）。能力：`pickDirectory()`、`persistedPermissions()`、`walk()`、`readFileBytes` / `writeFileBytes` / `readFileStream` / `writeFileStream`、`copyTo` / `moveTo`、`copyToLocalFile`（把 SAF 檔案複製到 app cache 拿真路徑）、`openFileDescriptor` / `withFileDescriptor`（給 `/proc/self/fd/<fd>`）、`thumbnail()`。Media picking 明言 out of scope。1.x path-based API 為 `LegacySaf`（deprecated，3.0.0 移除）。來源：`https://pub.dev/api/packages/saf`、`https://pub.dev/api/packages/saf/score`、`https://github.com/jvoltci/saf/blob/master/README.md`
- **`shared_storage`** — 最新 **0.8.1**，發佈 **2024-02-16T07:37:20Z**，pub.dev 標示 **discontinued（已停止維護）**；points 160/160、likes **61**、30 天下載 2,556；**Android only**。提供 SAF / MediaStore / Environment API 的封裝。來源：`https://pub.dev/api/packages/shared_storage`、`https://pub.dev/packages/shared_storage`
- **`file_picker`** — 最新 **13.1.0**，發佈 **2026-09-15T11:53:57Z**；points 160/160、likes **4,947**、30 天下載 **4,074,590**；平台 Android / iOS / Linux / macOS / Windows / Web。`getDirectoryPath()` 除 web 外全平台可用；`pickFileAndDirectoryPaths()` **只有 macOS**；`clearTemporaryFiles()` 只有 Android/iOS；並有 `AndroidSAFHandle`（`content://` URI + accessMode + `releaseGrant()`）。來源：`https://pub.dev/api/packages/file_picker`、`https://pub.dev/packages/file_picker`
- **`media_store_plus`** — 最新 **0.1.3**，發佈 **2024-09-22**（約 2 年未更新）；points 160/160、likes 91、30 天下載 24,488；用 MediaStore API 讀寫、可把 content URI 轉真路徑。來源：`https://pub.dev/api/packages/media_store_plus`

**`file_picker.getDirectoryPath()` 在 Android 到底回傳什麼**

- Dart 端送 method `dir`（`file_picker_android.dart`），Android 端在 `FileUtils.kt` 處理：
  - 開 `Intent(ACTION_OPEN_DOCUMENT_TREE)`（`type == "dir"` 分支）。
  - 取得結果後先 `takePersistableUriPermission`（當 SAF options 的 `grant == lifetime` 且 `autoPersist`）。
  - **若沒有傳 `androidOptions`（SAF options）**：用 `DocumentsContract.buildDocumentUriUsingTree` + `getFullPathFromTreeUri()` 把 tree URI **轉成檔案系統路徑字串**回傳。`getFullPathFromTreeUri` 的作法是把 tree document id 用 `:` 切開，`primary` 換成 `Environment.getExternalStorageDirectory()`，其他 volume 換成 `/storage/<volumeId>/<path>`，再接上 document path。
  - 轉不出來時回錯誤 `unknown_path`，Dart 端的訊息是：「Could not resolve directory path. Maybe it's a protected one or unsupported (such as Downloads folder). Make sure that you are on SDK 21 or above.」
  - **若有傳 `androidOptions`**：直接回傳 `content://` URI 字串（`data.data!!.toString()`），不轉路徑。
- 來源：`https://github.com/vicajilau/flutter_file_picker/blob/main/packages/file_picker_android/android/src/main/kotlin/com/mr/flutter/plugin/filepicker/FileUtils.kt`、`.../lib/src/file_picker_android.dart`
- 另：`file_picker_android` README 明言 `initialDirectory` 對 `pickFile` / `pickFiles` / `pickFileAndDirectoryPaths` / `getDirectoryPath` **在 Android 上無效**（原生只開 `ACTION_OPEN_DOCUMENT`、`ACTION_OPEN_DOCUMENT_TREE`、`ACTION_GET_CONTENT`，都不帶起始位置）。來源：`https://github.com/vicajilau/flutter_file_picker/blob/main/packages/file_picker_android/README.md`
- 結論（FMP 視角）：`getDirectoryPath()` 在 Android 拿到的是**組出來的路徑字串**，不是有效授權的裸路徑；Downloads 等目錄直接失敗。

---

## 與 FMP 決策相關的關鍵事實

### 硬限制（平台不支援或政策不允許）

1. **`flutter_downloader` 不支援桌面**（只有 Android/iOS，pubspec 與 README 皆然）→ FMP（Android + Windows）若用它得為 Windows 另寫一套。
2. **`background_downloader` 在桌面沒有真背景**：純 Dart isolate，app 一關下載即停、沒有系統排程、**不產生任何通知**、記錄只到 app lifecycle 為止（`doc/ARCHITECTURE.md`、`doc/notifications.md`）。→ 「Windows 關掉 app 仍下載完」用現成 Flutter 套件做不到。
3. **`background_downloader` 的 SAF/URI 下載不能暫停、不能續傳**（`doc/URI.md`）。→ 「直接下載進使用者自選資料夾」與「可暫停續傳」二選一。
4. **SAF 目錄不能用 `dart:io` 裸路徑寫檔**（scoped storage；`MANAGE_EXTERNAL_STORAGE` 是唯一能拿「direct file path access」的路）。→ 想用裸路徑寫入 shared storage，Android 11+ 只有 `MANAGE_EXTERNAL_STORAGE` 一條路（或改走 MediaStore / SAF 的 URI I/O）。
5. **音訊沒有部分授權**：`READ_MEDIA_VISUAL_USER_SELECTED` 只管 images/videos，Android 14 文檔完全不含 audio。→ 讀使用者音樂庫是全有全無的 `READ_MEDIA_AUDIO`。
6. **`MANAGE_EXTERNAL_STORAGE` 是 Play 受限權限**，「Media files access」與「使用者手動選單一檔案」都列在不許可用途，不符資格未申報者「may be removed from Google Play」。**FMP 不上架任何商店（ADR 0004），此政策對它沒有實際拘束**；但它同時鎖死了「未來上架」這條路。
7. **`POST_NOTIFICATIONS` 不豁免 foreground service 通知**；只有 media session 通知豁免。→ Android 13+ 的下載／FGS 通知必須要這個權限；播放中的媒體通知不用。
8. **`permission_handler` 沒有 macOS / Linux 實作**；**Windows 實作是 no-op**（一律回 granted、`openAppSettings()` 回 false）。→ 在 Windows 上它不解決任何權限問題（不會彈窗、也不會壞）；macOS/Linux 上不能用。
9. **Android WorkManager 9 分鐘上限、expedited 2 分鐘**（`background_downloader`）；要長下載需 `allowPause`（跨週期續傳）或 Android 14+ UIDT（需 `RUN_USER_INITIATED_JOBS` + 通知）。

### 可選取捨（沒有單一硬答案）

- **下載落地位置**：(a) app 私有目錄（`BaseDirectory.*`，零權限、可暫停續傳、但不給使用者看，需事後 `moveToSharedStorage`）；(b) `MANAGE_EXTERNAL_STORAGE` + 裸路徑（可暫停續傳、使用者自選資料夾，但 Play 受限——不上架則可）；(c) SAF URI（`UriDownloadTask` / `saf`，Play 友善，但不能暫停續傳，且寫檔要走 content URI）。
- **引擎**：`background_downloader`（跨平台 API 一致、含進度 notifier／通知／暫停續傳／WorkManager+UIDT／桌面 isolate）vs 自己用 `dio`（控制權最大，但續傳、進度持久化、前景服務、並行上限全要自己寫）。
- **目錄選擇器三條路**：`file_picker.getDirectoryPath()`（Android 上等於先拿 SAF 授權再換算路徑字串，受保護目錄會失敗；桌面回真路徑，可用）／`saf` 的 `pickDirectory()`（拿 URI，Android-only，是最「正確」的 SAF 用法）／`background_downloader.uri.pickDirectory()`（拿 URI，跨平台，但桌面沒有內建 picker，官方建議桌面另用 `file_picker`）。ADR 0004 目前用的是第一條（`FilePicker.getDirectoryPath()`）加上 `MANAGE_EXTERNAL_STORAGE` 讓那條路徑真的可寫。
- **通知策略**：Android 13+ 若要下載進度通知就得請求 `POST_NOTIFICATIONS`（且 `background_downloader` 的 UIDT 任務**強制**要有通知）；不請求就是下載無聲進行。
- **桌面下載的期待管理**：桌面（Windows）本質上只能「app 開著才下載」。要嘛接受，要嘛自己實作 OS 層服務（Flutter 生態無現成套件，**查不到**可用方案）。

### 查不到 / 未確認

- `READ_MEDIA_AUDIO` 是否也允許裸路徑讀取音訊檔（官方頁面只對 Android 11 的 `READ_EXTERNAL_STORAGE` 明說過）。
- `permission_handler` 在 macOS / Linux 無實作時的具體失敗方式（無文檔，推測 `MissingPluginException`）。
- `permission_handler` 的 iOS `status` 是否會回 `permanentlyDenied`（README 只明文講了 Android 的相反行為）。
- 「SAF document URI 不能當檔案路徑」在 Android 官方文檔中的**直接原文**（僅能從 `MANAGE_EXTERNAL_STORAGE` 的 `direct file path access` 反面、以及 `saf` / `shared_storage` 的套件方陳述佐證）。
- Windows 上「app 關閉後續傳下載」的可行做法（未找到 Flutter 套件；未查證）。

---

# 第二部：內嵌標籤、HTTP 續傳、平台下載位置

## A. Dart 內嵌音檔標籤（寫入，非僅讀取）

### A.1 FMP 現況（讀 repo 得到的前提）

- 舊版**只寫 sidecar JSON，不寫內嵌 tag**。sidecar 檔名契約在
  `lib/core/constants/download_filenames.dart`：`cover.jpg` / `avatar.jpg` / `metadata.json`，
  多頁時為 `metadata_P{NN}.json`（`metadataCandidatesForAudio()` 以 `^P(\d+)$` 正則比對音檔名）。
- 舊版**檔名一律寫 `.m4a`**，與實際容器無關：
  `lib/services/download/download_path_maintenance_service.dart` 內
  `_audioExtensions = ['.m4a', '.mp3', '.aac', '.opus']`、`_ownedAudioExtensions = ['.m4a']`，
  註解明寫「`DownloadPathUtils.computeDownloadPath` 只寫 `.m4a`」。
  路徑佈局（`download_path_utils.dart`）：`{baseDir}/{playlistName}/{sourceId}_{parentTitle}/P{n}.m4a`
  或單頁 `/audio.m4a`。
- 來源實際可能拿到的容器與編碼（`lib/data/sources/base_source.dart`，`AudioStreamResult` 的
  `container` ∈ {`mp4`, `webm`, `m4a`}、`codec` ∈ {`aac`, `opus`}；`formatPriority = [opus, aac]`）。
  `youtube_source.dart` 由 mimeType 判 `webm`。`playback_media.dart` 註解提到最後一節路徑可區分
  `.m4s` / `.m3u8` / `.flac` 三種來源。

→ 新設計要「寫內嵌 tag + 副檔名照實際格式（可能 m4a / opus / webm / flac）」，
這正是下面套件選型的約束。

### A.2 Dart 套件盤點（版本與日期取自 pub.dev）

| 套件 | 最新版 | pub.dev 最後發佈 | 平台 | 底層 | 可否寫入 |
|---|---|---|---|---|---|
| `audiotags` | **1.4.5** | **17 個月前**（≈2025-04） | Android / iOS / Linux / macOS / Windows | Rust `lofty`（flutter_rust_bridge） | 可寫 |
| `metadata_god` | **1.1.0** | **13 個月前**（≈2025-08） | Android / iOS / Linux / macOS / Windows | Rust | 可寫（格式少） |
| `flutter_taglib` | **1.5.2** | **52 天前**（≈2026-08） | Android / iOS / Linux / macOS / Windows | TagLib（Dart FFI + Native Assets） | 可寫（格式最廣） |
| `audio_metadata_reader` | **1.8.0** | versions 頁 **18 天前** / 套件頁「5 天前」（≈2026-09） | Android / iOS / Linux / macOS / Windows | **純 Dart** | 可寫（寫入格式受限） |

來源：
<https://pub.dev/packages/audiotags>、<https://pub.dev/packages/audiotags/versions>、
<https://pub.dev/packages/metadata_god>、<https://pub.dev/packages/flutter_taglib>、
<https://pub.dev/packages/audio_metadata_reader>、<https://pub.dev/packages/audio_metadata_reader/versions>

**逐套件細節**

- `audiotags` 1.4.5
  - verified publisher `erikastaroza.com`，MIT，30 likes / 120 pub points，全五平台。
  - 透過 Rust `lofty` 寫入（`AudioTags.write(path, tag)`），**整檔覆寫語意**；`duration` 為唯讀欄位。
  - lofty 官方支援格式表（<https://docs.rs/lofty/latest/lofty/>）：AAC (ADTS)、APE、AIFF、FLAC、
    MP3、MP4、MPC、Opus、Ogg Vorbis、Speex、WAV、WavPack。
    → **不含 Matroska / WebM**。
  - 來源：<https://pub.dev/packages/audiotags>、<https://docs.rs/lofty/latest/lofty/>

- `metadata_god` 1.1.0
  - verified publisher `krtirtho.dev`，MIT，全五平台；需要 `rustup`；Android 需
    `READ/WRITE_EXTERNAL_STORAGE`（新版 Android 需 `MANAGE_EXTERNAL_STORAGE`）。
  - 支援格式僅：mp3 → ID3v2.4、m4a/mp4 → MPEG-4 audio metadata、flac → Vorbis comment。
    → **不支援 opus / webm / aac**。
  - 來源：<https://pub.dev/packages/metadata_god>（context7 的 `resolve-library-id` 對
    `metadata_god` 無命中，回傳的是 Node.js 的 `music-metadata`，故直接取 pub.dev 頁面。）

- `flutter_taglib` 1.5.2
  - **unverified uploader**，只有 2 likes / 150 pub points（小眾）。
  - 包裝 TagLib：wrapper Apache-2.0，TagLib 本身 LGPL / MPL。
  - README 列 MP3 / FLAC / M4A / WAV / OGG「及 TagLib 支援的其他格式」。
  - TagLib 官方（<https://taglib.org/>）宣稱可讀寫 ID3v1/ID3v2、Vorbis comment 等，格式涵蓋
    MP3、MP4、AAC、Ogg、Opus、FLAC、Speex、APE、MPC、WavPack、WAV、AIFF、TrueAudio、
    **Matroska、WebM**、ASF、WMA、DSF、DFF 及 tracker 格式。TagLib **2.3.1 發佈於 2026-07-20**
    （含 Matroska 相關修正）。
  - → **這是目前唯一在文件上涵蓋 WebM / Matroska / Opus 寫入的 Dart 選項**。
  - **推測**：fluter_taglib 實際能不能寫 WebM/Opus，取決於它 bundle 的 TagLib 版本與它自己有沒有
    把對應 API 暴露出來。「bundle 的是哪個 TagLib 版本」**查不到**（repo README 取不到內容），
    故這條只能算推測，動工前必須實際驗證。
  - 來源：<https://pub.dev/packages/flutter_taglib>、<https://taglib.org/>

- `audio_metadata_reader` 1.8.0
  - 純 Dart（無 native 依賴），全五平台。
  - **可寫**：MP3 / MP4 / FLAC / WAV / APE。
  - **唯讀**：OGG / Opus / WebM / Matroska / AIFF / MOV；**AAC 不支援**。
  - 寫入為**原子寫入**（先寫 temp 再 rename）。
  - 來源：<https://pub.dev/packages/audio_metadata_reader>

- `taglib`（純 Dart 套件名）→ **<https://pub.dev/packages/taglib> 回 HTTP 404，不存在**。
  只有 `flutter_taglib`。（這是查證結果，不是障礙。）

### A.3 以 FFmpeg 重新封裝／寫 tag

- **FFmpegKit 已退役**：
  - `ffmpeg_kit_flutter` 最新版 **6.0.3**（另有 `6.0.3-LTS`），FFmpeg 6.0，**僅 Android / iOS / macOS**。
  - Arthenica 於 **2025-01-06** 公告退役，**2025-04-01** 從 Maven Central / CocoaPods / npm
    移除 native binaries；pub.dev 標為 discontinued / unmaintained。
  - 官方 GitHub README（2026-07 仍有更新）明說 FFmpegKit 已正式退役，後續是原作者以
    **source-only** 形式繼續的 `FFmpegKitNext`。
  - 來源：<https://pub.dev/packages/ffmpeg_kit_flutter>、<https://github.com/arthenica/ffmpeg-kit>

- **社群 fork**：`ffmpeg_kit_flutter_new` **4.6.2**，**54 天前**發佈，verified publisher
  `antonkarpenko.com`，203 likes。內含 **FFmpeg 8.1.2**，支援 Android API 24+ / iOS 14.0+ /
  macOS 10.15+ / Windows 10+ x86_64 / Linux x86_64。共八種變體；
  **Full 版為 GPL**，GPL codec（x264 / x265 / xvidcore / vid.stab）只出現在 `-gpl` 變體。
  另有較新的 `ffmpeg_kit_extended_flutter`（FFmpegKit 9.0.1 API、改用 FFI、全五平台）。
  - 來源：<https://pub.dev/packages/ffmpeg_kit_flutter_new>

- → 用 FFmpeg 寫 tag / remux 是「最重但最一致」的路線：能吃所有容器，代價是**套件體積、
  GPL 授權傳染、平台限制**，以及多一層 native 依賴。

### A.4 A 段小結（決策面）

- **B 站 DASH 音訊是 `.m4s`（fragmented MP4 / AAC）** → MP4 writer 可行；
  `audiotags`（lofty）、`metadata_god`、`audio_metadata_reader` 都可寫。
- **NetEase 取 flac**（`netease_source.dart` 以 `encodeType: 'flac'` 請求）→ FLAC writer 可行，
  上述四套件都支援。
- **YouTube 可能拿到 Opus / WebM** → **只有 TagLib 系（`flutter_taglib`）在文件上涵蓋**；
  lofty 明確不支援 Matroska，`audio_metadata_reader` 對 WebM/Opus 標唯讀，`metadata_god` 不支援。
- 可行路線（三選一，皆為設計選項而非事實）：
  1. 一律用 `flutter_taglib`（單一套件通吃），風險是套件小眾（2 likes / 150 points、unverified）
     且 WebM 寫入待實證。
  2. 混合：m4a / flac 用 `audio_metadata_reader`（純 Dart、活躍、原子寫入），WebM/Opus 另尋或
     改用 FFmpeg。
  3. 一律走 FFmpeg remux / 寫 tag（最一致，但最重且有 GPL 與體積成本）。
- 寫 tag 是**改寫既有檔案**，必須原子寫入（temp + rename）以免下載完成的檔案損毀；
  `audio_metadata_reader` 已內建，其他套件需自行確認。

---

## B. HTTP Range / 續傳

### B.1 標準語意（RFC 9110 §14；RFC 9110 已取代 RFC 7233）

- **RFC 9110**（HTTP Semantics, STD 97, 2022-06）**obsolete 了 RFC 7233**。
  Range 在 §14.2、`Accept-Ranges` §14.3、`Content-Range` §14.4、`multipart/byteranges` §14.6，
  `If-Range` 在 §13.1.5。
  來源：<https://www.rfc-editor.org/rfc/rfc9110.html>、<https://www.rfc-editor.org/rfc/rfc7233.html>
- **Range 是選用功能**：server **可以忽略 Range**，直接回 **200** 與完整資源（等同
  `Accept-Ranges: none`）。客戶端不能假設一定拿得到 206。
  來源：<https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Range>
- **206 Partial Content**：接受 Range 時回 206，帶 `Content-Range: bytes start-end/total`。
  注意 206 的 `Content-Length` 是**該段長度**，不是資源總長。
  來源：<https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/206>
- 單一 range → 直接 body + `Content-Range`；**多重 range → `multipart/byteranges`**。
  來源：<https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Range>
- **416 Range Not Satisfiable**：range 越界或不合法時回 416。
  來源：<https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/416>
- **位元組單位是 0-indexed、含頭含尾**（`bytes=0-499` 是前 500 bytes）。
  續傳的標準寫法是 `Range: bytes={已下載位元組數}-`。
  來源：<https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Range>
- **`If-Range`（續傳正確性的關鍵）**：
  - 讓 Range 請求變成**條件式**。validator 相符 → 回 **206** 部分內容；
    **不相符 → 忽略 Range，回 200 完整資源**。
  - validator 只接受**強 ETag**（弱 ETag 的 `W/` 前綴**不可**用於 If-Range）或 HTTP-date。
  - `If-Range` **必須與 `Range` 同時出現**，否則 server 會忽略它。
  - 原文（RFC 7233 §3.2，語意被 RFC 9110 §13.1.5 沿用）：
    "If the validator given in the If-Range header field matches the current validator ...
    the server SHOULD process the Range header field as requested. If the validator does not
    match, the server MUST ignore the Range header field."
  - 來源：<https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/If-Range>、
    <https://www.rfc-editor.org/rfc/rfc9110.html>
- **ETag**：標識資源的**特定版本**；資源內容改變**必須**產生新 ETag。
  強 ETag 才讓 Range 請求可被 cache / 可安全續傳。
  來源：<https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/ETag>
- **`Last-Modified`** 精度較低（秒級），是拿不到 ETag 時的 fallback。
  來源：<https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/ETag>

### B.2 B 站 CDN（`upos-*.bilivideo.com`）公開已知行為

- 播放位址由 playurl API 取得，**DASH 音視分離**，音訊是獨立的 `.m4s` 檔。
- 社群文（<https://www.bilibili.com/read/cv6415114>）明說：
  1. **連結有時效**（`deadline`/簽名參數）；
  2. **不帶 `Referer` 直接訪問該連結會 403**；
  3. 慣用下載器是 **aria2c**（可多連線、可續傳）。
- CDN 有多個 host（`upos-sz-mirroraliov` / `upos-sz-mirrorcos` / `upos-sz-mirrorhw` /
  `upos-sz-estgcos` 等 `.bilivideo.com`）；yt-dlp issue #14498 記錄了「手動換 CDN 網域」
  的做法（**官方無此選項**），並指出預設 CDN 可能被限速。
  來源：<https://github.com/yt-dlp/yt-dlp/issues/14498>
- **推測**：既然 aria2c / IDM / yt-dlp 這類工具能對 B 站多連線與續傳，CDN 應支援
  byte range（206）。**我沒有打 API 實測**，故此條標推測，動工前必須驗證。
- **查不到**：upos 在換 host 後是否回**相同 ETag** 的官方說明；以及它對 `If-Range` 的支援程度。

### B.3 YouTube CDN（`googlevideo.com`）公開已知行為

- YouTube 走 **DASH**；MPEG-DASH **on-demand profile**
  （`urn:mpeg:dash:profile:isoff-on-demand:2011`）用 `SegmentBase@indexRange`，
  **播放與 seek 本身就是用 HTTP byte-range 抓 MP4 segment**（回 206）。
  也就是說 YouTube 的「正規」抓法本來就是 range-based。
  → 由此**推論** googlevideo 支援 Range / 206。**推測**（機制推論，非直接觀測）。
- YouTube 官方 DASH-over-HTTP 文件同時列 **MP4 與 WebM** 容器。
- URL 帶 **expire 簽名參數**，過期後失效（常見 403）。yt-dlp issue #7074 記錄了字幕 URL
  在任務中途過期；社群多起 403 回報（如 mpv issue #16563、r/youtubedl 討論）。
  來源：<https://github.com/yt-dlp/yt-dlp/issues/7074>
- yt-dlp 有 `--continue`（續傳部分下載的檔／fragment，**預設開啟**）與 `--http-chunk-size`
  （分塊 HTTP 下載，**預設關閉**）。→ 顯示「分塊／續傳」在 YouTube 是常見且必要的做法。
  來源：<https://github.com/yt-dlp/yt-dlp>
- **查不到**：googlevideo 明確回 `Accept-Ranges: bytes` 的第一方聲明。故此點只能算推測。

### B.4 「每次續傳都重新解析 URL」的風險，與正規做法

風險（皆為設計推理）：

1. **簽名 URL 過期** → 403，必須重新解析（B 站與 YouTube 皆然）。
2. **重解析可能換到不同 host / CDN edge**。不同 edge 對同一物件**未必給相同 ETag**
   （**推測**）。此時正確的 `If-Range` 會直接回 200 完整檔 = 強制重來；
   但若**不**帶 `If-Range` 而只發 `Range`，就會出現「舊片段 + 新版本片段」**混拼成損壞檔**。
3. **內容可能變動**（重解析可能選到不同畫質 / 編碼 / 位元率）→ 續傳拼檔直接壞掉。
4. 因此「拿到新 URL 就從舊 offset 接著寫」是**不安全**的預設行為。

正規做法（RFC 語意下的安全續傳）：

- 第一次回應時**記錄 ETag / Last-Modified 與已下載位元組數**。
- 續傳請求：`Range: bytes={N}-` **加上** `If-Range: <ETag>`（同一次請求）。
- 收到 **206** → **驗證 `Content-Range` 的起點 == N** 才續寫；不符就視為失敗。
- 收到 **200** → 代表 validator 不符（或 server 不支援 Range）：**丟棄暫存檔，從 0 重寫**。
- **不要跨 CDN host 重用 ETag**（**推測**：不同 host 可能給不同 validator）。
- 若來源本身是 DASH（B 站、YouTube），另一條路是**分段下載**（每個 segment 獨立 URL、
  各自簽名），把「續傳」變成「已完成的 segment 不重抓」，比對單一大檔用 Range 更貼合來源模型。

---

## C. 各平台下載位置與沙盒可見性

### C.1 iOS / macOS 沙盒

- app 容器內可寫位置（官方 File System Programming Guide）：
  - `Documents/` — 使用者產生的資料檔。
  - `Library/` — app 資料；**除 `Library/Caches` 外會被 iTunes / iCloud 備份**。
    - `Library/Application Support/` — app 自己的資料檔（**iOS 上會被備份**）；
      官方建議放在以 **bundle id 命名的子目錄**下。
    - `Library/Caches/` — **不備份**，且系統在空間不足時**可清除**。
  - `tmp/` — **不備份**，且 app 未執行時系統**可清除**。
  - 來源：<https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html>
- **讓檔案在「檔案」App 可見**：`UIFileSharingEnabled = YES` **且**
  `LSSupportsOpeningDocumentsInPlace = YES`，**兩個都要設**，app 的 `Documents/` 才會出現在
  「在我的 iPhone 上」。
  - 來源（Apple 官方兩頁抓不到內文，僅回導覽框架；改用社群明述此條件者）：
    <https://developer.apple.com/documentation/bundleresources/information-property-list/uifilesharingenabled>、
    <https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsopeningdocumentsinplace>、
    <https://nemecek.be/blog/57>、<https://blog.eidinger.info>
- **macOS 沙盒**（10.7 起）：容器在 `NSHomeDirectory()` 內，`Application Support` / `Caches` /
  `tmp` 都在容器裡。容器**外**的檔案需要：
  - 使用者透過 open / save panel 選取 → entitlement
    `com.apple.security.files.user-selected.read-write`（唯讀則 `...read-only`）；
  - 持久存取要 **security-scoped bookmark**：存 bookmark data，下次 resolve 後
    `startAccessingSecurityScopedResource()` / 用完 `stopAccessingSecurityScopedResource()`。
  - 有實務者指出：bookmark 只在**使用者選了 read/write** 時成功，選 read-only 會失敗
    （社群經驗，非官方文件）。
  - 另有開發者稱 `com.apple.security.files.bookmarks.app-scope` entitlement 已非必需
    （引 Jeff Johnson / FB7405463）。→ **文件與實務不一致，標為有爭議**。
  - 來源：<https://developer.apple.com/documentation/security/app_sandbox>、
    <https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()>

**FMP 相關**：Android / Windows 以外的平台若要「使用者看得到下載的音樂」，
iOS 需兩個 Info.plist key + 檔案放 `Documents/`；macOS 需使用者授權或放容器內。

### C.2 Linux（XDG）

- **XDG Base Directory Spec**：
  - `$XDG_DATA_HOME`（預設 `~/.local/share`）— 使用者資料。
  - `$XDG_CONFIG_HOME`（預設 `~/.config`）— 設定。
  - `$XDG_STATE_HOME`（預設 `~/.local/state`）— 狀態 / log。
  - `$XDG_CACHE_HOME`（預設 `~/.cache`）— 快取。
  - 來源：<https://specifications.freedesktop.org/basedir-spec/latest/>
- **使用者音樂目錄**：由 `xdg-user-dirs` 管理，設定檔在 `$XDG_CONFIG_HOME/user-dirs.dirs`，
  變數 `XDG_MUSIC_DIR`（預設 `$HOME/Music`），由 `xdg-user-dirs-update` 寫入；
  查詢用 `xdg-user-dir MUSIC`。
  - 來源：<https://wiki.archlinux.org/title/XDG_user_directories>
- 慣例：使用者可見的音樂 → `XDG_MUSIC_DIR` 下自建子目錄；內部狀態 / DB → `XDG_DATA_HOME/<app>`；
  快取 → `XDG_CACHE_HOME/<app>`。

### C.3 Windows

- **資料夾語意**：
  - `Documents` — 使用者文件（**Known Folder**，可能被 OneDrive 重導向）。
  - `AppData\Roaming` — **會跟隨網域 / 漫遊 profile 同步**，適合小設定。
  - `AppData\Local` — **不漫遊**、機器專屬，適合快取與大檔。
  - `AppData\LocalLow` — 低完整性（low integrity）行程用。
  - 來源：<https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid>、
    Microsoft Q&A / superuser 關於 Roaming vs Local 的官方回覆
- **路徑長度**：Win32 API 歷史上限 **`MAX_PATH` = 260**。Windows 10 1607+ 對**部分**函式
  移除限制，但 **app 必須 opt-in**：同時設 registry `LongPathsEnabled` **且** app manifest
  宣告 `longPathAware`；且只對有 `W` 版的函式有效。
  - 來源：<https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation>
- **FMP 相關**：`{playlistName}/{sourceId}_{parentTitle}/P{n}.m4a` 這種**深層巢狀 + 中文長標題**
  佈局，很容易逼近 260；未 opt-in 時寫入會失敗。需縮短路徑或處理長路徑。

### C.4 Android

- **App 專屬目錄**（internal files/cache 與 external app-specific
  `Android/data/<pkg>/`）：**卸載後一律刪除**；Android 10+ 加密；不需任何儲存權限。
  - 來源：<https://developer.android.com/training/data-storage/app-specific>
- **共用儲存**：音訊走 **MediaStore**（`Music/` ↔ `MediaStore.Audio`）；Android 10+
  scoped storage 為預設。建立 / 更新媒體用 `DISPLAY_NAME` + `RELATIVE_PATH`（**不要**用 `DATA`）；
  下載類可放 `MediaStore.Downloads`（`Download/`）。
  - 來源：<https://developer.android.com/training/data-storage/shared/media>
- **FMP 相關**：要「卸載後仍保留」的音樂**必須**寫共用儲存 `Music/`（要處理權限 / MediaStore）；
  寫進 app 專屬目錄的使用者音樂會隨卸載消失。
- `path_provider` **2.1.6**（verified publisher flutter.dev，約 3 個月前）：
  - Temporary / Application Support / Application Documents / Application Cache → 全五平台。
  - Application Library → **僅 iOS / macOS**。
  - External Storage / External Cache / External Storage Directories → **僅 Android**
    （app 專屬外部目錄，卸載即刪）。
  - Downloads → 全五平台。
  - SDK 下限：Android 24+ / iOS 13.0+ / macOS 10.15+ / Windows 10+。
  - 來源：<https://pub.dev/packages/path_provider>、<https://pub.dev/packages/path_provider/versions>

---

## 與 FMP 決策相關的關鍵事實

### 硬限制（不可繞，只能接受或改需求）

1. **WebM / Opus 容器幾乎沒有純 Dart 寫入方案**。lofty（`audiotags` 底層）格式表**不含**
   Matroska/WebM；`audio_metadata_reader` 對 WebM/Opus 標唯讀；`metadata_god` 不支援。
   文件上涵蓋的只有 TagLib 系（`flutter_taglib`）。（A.2）
2. **`flutter_taglib` 是小眾 + unverified**（2 likes / 150 pub points），且它 bundle 的 TagLib
   版本與實際 WebM 寫入能力**查不到**，必須實證。（A.2）
3. **HTTP Range 是選用功能**：server 可忽略並回 200；416 表不合法；206 的 `Content-Length`
   是段長不是總長。（B.1）
4. **`If-Range` 是續傳唯一安全機制**：validator 不符 → 回 200 完整檔，客戶端**必須**丟棄已下載
   部分。弱 ETag 不可用於 `If-Range`。（B.1、B.4）
5. **B 站與 YouTube 的 URL 都是時效簽名**，過期即 403，**必然**需要重解析；且 B 站連結
   **必須帶 `Referer`**。（B.2、B.3）
6. **Android app 專屬目錄卸載即刪**；要使用者可見保留必須走 MediaStore / 共用儲存。（C.4）
7. **Windows 路徑 260 上限**未 opt-in 時會硬失敗，而 FMP 的巢狀 + 中文標題佈局天然逼近上限。（C.3）
8. **iOS 要讓 `Documents/` 在「檔案」App 可見需兩個 Info.plist key 皆 YES**。（C.1）
9. **FFmpegKit 已退役**，官方 binary 已下架；社群 fork 為 GPL 且有體積成本。（A.3）

### 可選取捨

- **寫 tag 套件**：單一 `flutter_taglib`（廣但小眾）vs 混合（純 Dart 為主 + WebM 另解）
  vs 全走 FFmpeg（一致但最重）。三者是設計選擇，取決於「一定要支援 webm/opus 寫入嗎」。（A.4）
- **副檔名政策**：維持現行「一律 `.m4a`」可避開 WebM 寫入問題，但檔名與實際容器不符；
  改成照實際格式則拉高套件需求。（A.4）
- **續傳策略**：對 DASH 來源（B 站 / YouTube），「以 segment 為單位續傳」比「對單一大檔用
  `Range` + `If-Range`」更貼合來源模型；兩者不互斥，可並存。（B.4）
- **下載落地位置**：app 私有（簡單、卸載即消失、無權限）vs 共用儲存 / `Documents` / `Music`
  （使用者可見、可保留，但要處理各平台權限與沙盒）。（C.1–C.4）

### 查不到 / 待實證

- B 站 `upos` 是否支援 `If-Range`、以及換 host 後 ETag 是否一致 — **查不到**，**推測**支援 Range。
- googlevideo 回 `Accept-Ranges: bytes` 的第一方聲明 — **查不到**，僅由 DASH byte-range 機制**推測**。
- `flutter_taglib` bundle 的 TagLib 版本與 WebM 寫入實效 — **查不到**，需實測。
- `com.apple.security.files.bookmarks.app-scope` 是否仍必需 — **文件與實務不一致**。
