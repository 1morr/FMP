# 下載子系統 prior art 調查

- **查證日期**：2026-09-28
- **查證方式**：以 `gh api repos/OWNER/REPO/commits/HEAD --jq .sha` 取得各 repo 當下 HEAD 的 commit SHA，再 `git clone --depth 1` 把該 SHA 的樹抓到本機，**直接讀原始碼與 README**。所有引用都附固定 SHA 的 permalink（`https://github.com/OWNER/REPO/blob/<SHA>/<path>`）。**未執行任何 app、未打任何真實 API**。
- **引用格式**：`[代號]` 對應下方各產品的 repo 與 SHA。標「**README 宣稱**」的是文件說法，標「**程式碼**」的是我在原始碼看到的事實，兩者分開。查不到的一律寫「查不到」，我的推論一律標「推測」。

## 受查產品與固定 SHA

| 產品 | repo | SHA | 技術棧 |
|---|---|---|---|
| Finamp `[F]` | finamp-app/finamp | `0aae9d5ed530ffdf3d62ab12dab4f475a67687dc` | Flutter + Jellyfin client + `background_downloader` |
| Namida `[N]` | namidaco/namida | `e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5` | Flutter + 自寫 Range/分塊下載器 |
| Spotube `[S]` | KRTirtho/spotube | `69a310c78f5ceaf4eab7dfee98f187d38211c9ba` | Flutter + Dio 分塊下載 |
| NewPipe `[P]` | TeamNewPipe/NewPipe | `7e5df38aad4b2c035332b3f71aee3064d4fdaae4` | Android 原生 Kotlin（giga 下載引擎） |
| Musify `[M]` | gokadzev/Musify | `5b98d3a3cddd3fdb16ea6cc14d59d667e82cccd2` | Flutter + `youtube_explode_dart` |
| MusicFree `[X]` | maotoumao/MusicFree | `d118b18b3d0c904400f7eea7bf99c0ceec6c1aee` | React Native + JS 插件架構 |

避開的歧義：`[N]` 的 repo 是 **`namidaco/namida`**，不是任務描述裡寫的「author namida-app」。

---

## 總覽表

| 產品 | 佇列 / 併發 | 背景下載機制 | 續傳 | 儲存位置 | 內嵌 tag | 權限流程 |
|---|---|---|---|---|---|---|
| Finamp `[F]` | 任務佇列在 host（`IsarTaskQueue`），併發上限 `maxConcurrentDownloads`（預設 5），可設定 | `background_downloader` 的 `FileDownloader`，Android 走 WorkManager（該套件自身機制）；app 另外呼叫 `resumeFromBackground()` | **套件支援、app 刻意不用**：`storeResumeData` 有實作，但 `pauseAll`/`resumeAll` 是空函式，註釋寫明「We do not currently pause or resume the downloads」 | app-private（`applicationSupport`）為平台預設；另有 internal/external/custom。external/custom 用 `file_picker` 取字串路徑，**沒有持續化 SAF 授權** → 官方文件自承 practically broken | **不寫 tag** | `permission_handler` 唯一一處被**註解掉**；目錄選擇靠 `FilePicker.getDirectoryPath()`，UI 對 iOS/Android 顯示紅色 `customLocationsBuggy` 警告 |
| Namida `[N]` | 兩層：**檔案數** `downloadParallelCount`（預設 4）+ **單檔執行緒數** `downloadThreadsCount`（預設 3），都可設定 | **沒有** WorkManager；下載跑在共用 isolate（`FilesDownloadManager with PortsProvider<SendPort>`）；靠 `audio_service` 的前景服務與 battery-optimization 例外維持。**查不到**任何下載專用的 foreground service | **自寫且完整**：以「磁碟上檔案大小」為續傳位移；`Content-Range` 驗證；伺服器不理 Range 時從 0 重來；多執行緒用 `<index>.part` 且「只以整塊成長，所以永遠是合法前綴」；5 次重試、30s 停滯逾時、指數退避 | 使用者可見的 `Namida/Downloads`（`AppDirs.YOUTUBE_DOWNLOADS`，預設 `INTERNAL_STORAGE/Downloads`），可用內建瀏覽器改路徑。**不用 SAF**，改用 `MANAGE_EXTERNAL_STORAGE` | **寫入**（`ffmpeg_controller.dart`）：`-metadata k=v` + `-id3v2_version 3 -write_id3v2 1 -c copy`；opus/ogg/flac 先 `-map_metadata -1` 再整套寫回 | Android 11+ 要求 `Permission.manageExternalStorage`（`requestManageStoragePermission`）；拒絕 → snackbar 報錯並 `return false`；永久拒絕另外走 `openAppSettings()`；另有 `requestIgnoreBatteryOptimizations()` |
| Spotube `[S]` | **硬編碼 1**：`_startDownloading()` 看到任何 `downloading` 就 return；佇列只存在記憶體（`build()` 回 `[]`），重啟即消失 | **無**（只有播放用的 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`；`BIND_JOB_SERVICE` 屬於 `home_widget` 不是下載） | **無續傳**：分塊下載的暫存目錄在**每次開始前先整個刪掉**、失敗也刪 → 跨嘗試無法接續。Range 只是用來分塊加速，不是續傳 | Android **硬編碼** `/storage/emulated/0/Download/Spotube`；macOS 放 `Caches`；其餘 `getDownloadsDirectory()/Spotube`。路徑存 drift `PreferencesTable.downloadLocation`。用 `file_picker` 取字串路徑，同樣**沒有 SAF 授權** | **寫入**（`metadata_god`）：`MetadataGod.writeMetadata`，含 title/artist/album/albumArtist/year/durationMs/fileSize 與封面 `Picture` | `use_get_storage_perms.dart` 請求 `Permission.storage` 或 Android 13+ 的 `Permission.audio`；manifest 有 `requestLegacyExternalStorage="true"` |
| NewPipe `[P]` | **預設 1**：`mPrefQueueLimit` 預設 `true`，開啟時 `getRunningMissionsCount() < 1` 才啟動下一個任務；可在設定關掉。單檔另有 `threadCount`（預設 3）分塊 | **有**：`DownloadManagerService` 是 foreground service（manifest `android:foregroundServiceType="dataSync"`），`updateForegroundState(true)` → `startForeground(...)`，同時 `mLock.acquireWifiAndCpu()` 取 WifiLock + WakeLock | **完整且有量身設計**：`blocks[]` 陣列記每個 block 的位移（-1 = 已完成），每個 mission 一個 metadata 檔（檔名 = timestamp）存在 `pending_downloads/`；`DownloadMissionRecover` + `MissionRecoveryInfo` 處理來源 URL 失效後重新協商；伺服器不允許 Range 時退回單執行緒 | **SAF 為主**：`StoredDirectoryHelper`（`DocumentFile` / tree URI），音訊與視訊各自一個 handle；`NewPipeSettings.useStorageAccessFramework()` 在 API 29+ **強制 true**，只在舊版可由偏好設定控制；非 SAF 模式才是 `Environment.getExternalStorageDirectory()/Music` 之類 | **不寫 tag**：`postprocessing/` 只做容器處理（`M4aNoDash`、`Mp4FromDashMuxer`、`OggFromWebmDemuxer`、`WebMMuxer`、`TtmlConverter`），全樹只有一個 `ffmpeg` 檔名命中（`Mp4FromDashWriter.java`），沒有任何 `-metadata` 寫入 | `PermissionHelper.checkStoragePermissions()`：**若走 SAF 就直接回 true（不需權限）**；否則請求 `READ_EXTERNAL_STORAGE` + `WRITE_EXTERNAL_STORAGE`。另有 `checkPostNotificationsPermission()`（TIRAMISU 起、只問一次） |
| Musify `[M]` | 播放清單下載：**硬編碼 3** 個 worker 的 queue；單曲 `makeSongOffline` 沒有全域佇列或限流 | **無下載專用機制**：manifest 只有 `INTERNET` / `WAKE_LOCK` / `FOREGROUND_SERVICE(MEDIA_PLAYBACK)`（屬 `audio_service` 播放用），沒有下載 foreground service。下載中切到背景是否會繼續 → **查不到保證**（推測只在播放維持前景服務時才存活） | **無續傳**：`streamsClient.get(audioManifest)` 直接 `pipe` 進 `openWrite()`，中斷就 `.delete()` 重來，無 Range | **app-private**：`applicationDirPath = (await getApplicationDocumentsDirectory()).path`，子目錄 `tracks/`、`artworks/`、`stream_buffer/`。**不需任何儲存權限**（manifest 裡沒有），也不給使用者選目錄 | **不寫 tag**：pubspec 無 `metadata_god`/taglib；封面存成 sidecar `artworks/<ytid>.<ext>`；唯一讀 tag 的東西是 `youtube_explode_dart`（讀取端） | **完全沒有權限流程**（app-private 目錄不需要）。manifest 無任何 storage permission |
| MusicFree `[X]` | **可設定 1..10，預設 3**：`maxDownloadCount = clamp(config basic.maxDownload \|\| 3, 1, 10)`；任務佇列在記憶體（jotai atom） | 用 `react-native-fs` 的 `downloadFile({ background: true })`，交給 RNFS 的原生背景下載（iOS/Android 各有實作） | **無續傳**：暫存檔名用 `nanoid()`，重試等於全新下載 | `basePath` = Android `RNFS.ExternalDirectoryPath` / iOS `Documents`；下載到 `<basePath>/download/music/`，暫存在 `<basePath>/cache/download/`。路徑可由 `config basic.downloadPath` 覆寫。**不用 SAF** | **下載器不寫 tag**。`native/mp3Util` 雖有 `setMediaTag`，但下載流程沒呼叫它；下載後只把 `localPath` 記進 DB。`mp3Util` 只用於**讀**本地檔案 meta | **`downloadFile` 失敗 → 試著建目標目錄，建不起來就報 `DownloadFailReason.NoWritePermission`**（沒有主動請求權限的流程，靠系統授權結果） |

---

## Finamp `[F]` — finamp-app/finamp @ `0aae9d5e`

### 1. 佇列與併發

**程式碼**：`class IsarTaskQueue implements TaskQueue` 在
[`lib/services/downloads_service_backend.dart#L230`](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/downloads_service_backend.dart#L230)
實作 `background_downloader` 的 `TaskQueue` 介面。`_advanceQueue()` 的 dartdoc 直接寫「will enqueue finampSettings.maxConcurrentDownloads at once」（同檔 L307），實際守門條件在 L329：

```dart
while (_activeDownloads.length >= FinampSettingsHelper.finampSettings.maxConcurrentDownloads ||
    _finampUserHelper.currentUser == null) {
  await Future.delayed(const Duration(milliseconds: 500));
}
```

即 **`maxConcurrentDownloads` 是使用者可設定的併發上限**；輪詢間隔 500ms。另外每筆任務間刻意延遲 20ms，註釋說是為了「prevent choking the method channel」（註釋提到 `MemoryTaskQueue`，那是 `background_downloader` 自己的 in-memory 佇列類比）。任務優先序用 `Priority.animation + 50`。

**排序**：查詢時 `limit(20)`，一次取一批；排序依據我沒追到明確的欄位（**查不到**），但佇列是先進先出的 `_advanceQueue()` 補位。

`DownloadTask` 的組裝把 Isar 記錄翻譯成套件任務，並把 Jellyfin 的授權標頭塞進去（同檔約 L330–350）：`taskId: task.isarId.toString()`、`headers: {"Authorization": _finampUserHelper.authorizationHeader}`、`baseDirectory`/`directory`/`filename` 由 `task.path` 拆解。

### 2. 背景下載

**程式碼**：`background_downloader` 本身在 Android 用 WorkManager（套件層事實，不在本 repo 內，我只在 `lib/main.dart` 的 `_setupDownloadsHelper()` 看到
[`fileDownloader.configure(globalConfig: (Config.checkAvailableSpace, 1024))`](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/main.dart)
與 `await fileDownloader.resumeFromBackground()`、`await downloadsService.startQueues()`）。Finamp 自己**沒有** foreground service。

### 3. 續傳

這是最值得注意的一點：**套件能力被接上，但 app 主動放棄使用**。

- `IsarPersistentStorage`（同檔 L34）**有**實作 `storeResumeData` / `retrieveResumeData` / `removeResumeData` / `storePausedTask` / `retrievePausedTask`。
- 但 `pauseAll` / `resumeAll` 是**空覆寫**（[`#L432`](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/downloads_service_backend.dart#L432)），旁邊的註釋明寫「We do not currently pause or resume the downloads」。

**啟動時的對帳**（`initializeQueue()`）反而比續傳更重要：對每個 item 檢查 `item.file?.existsSync()`，存在就標 complete 並 log「Marking download ${item.name} as complete on startup.」；狀態是 `downloading` 但不在 `allTasks(includeTasksWaitingToRetry: true)` 裡的，重新入列並 log「Re-enqueueing download ${item.name} on startup.」。**這是「重啟後靠檔案本身 + 狀態欄位對帳」的樣板**，不是靠 HTTP 續傳。

### 4. 儲存位置

**程式碼**：`class DownloadLocation`（[`lib/models/finamp_models.dart#L1017`](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/models/finamp_models.dart#L1017)）持有 `id` / `relativePath` / `baseDirectory`。`enum DownloadLocationType`（[`#L2605`](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/models/finamp_models.dart#L2605)）列出全部選項：

```
internalDocuments  → BaseDirectory.applicationDocuments
internalSupport    → BaseDirectory.applicationSupport
external           → BaseDirectory.root
custom             → BaseDirectory.root
migrated / cache / none
platformDefaultDirectory = (iOS || Android) ? internalSupport : cache
```

`DownloadItem.file` 是 `currentPath` 與**相對路徑** `path` 的 join；`updateCurrentPath()` 分別用 `getApplicationDocumentsDirectory()` / `getApplicationSupportDirectory()` / `getApplicationCacheDirectory()` 求解。相對路徑是刻意的設計 —— `DOWNLOADS_PLAN.md` 寫「Relative path handling by default - this will solve the absolute path issue I mentioned earlier」。

**外部目錄是壞的，而且官方文件自己承認**：`custom_download_location_form.dart` 用 `FilePicker.getDirectoryPath()` 取回一個**字串路徑**，沒有把 SAF 的 tree URI 權限持續化。`DOWNLOADS_PLAN.md` 的原話是「**Scoped storage support - Finamp's support for external directories is currently practically broken.**」。UI 上對 iOS/Android 直接顯示紅色 `customLocationsBuggy` 警告（`lib/screens/downloads_settings_screen.dart`）。

`android/app/src/main/AndroidManifest.xml` 有 `READ/WRITE_EXTERNAL_STORAGE` 與 `android:requestLegacyExternalStorage="true"`，`targetSdkVersion flutter.targetSdkVersion`。

### 5. 檔名與目錄結構

`_getTrackDownloadPath(DownloadItem)`（同檔 `downloads_service_backend.dart`）：

- **human-readable 模式**：`fileName = _filesystemSafe("${originalFilename ?? "$indexNumber$artist${item.name}"}_${item.id.raw.substring(0, 8)}")`，其中 `indexNumber = "[${item.indexNumber}] "`、`artist = "${item.artists?.first} - "`；路徑段 `pathSegments = [_filesystemSafe(item.albumArtist), _filesystemSafe(item.album)]`，最前面再補一層 `"Finamp"`（除非該 location 最後一段已經是 `finamp`）。
- **非 human-readable 模式**：`fileName = item.id.raw`，子目錄固定 `FINAMP_BASE_DOWNLOAD_DIRECTORY`（[`#L30`](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/downloads_service_backend.dart#L30) = `"songs"`）。
- 淨化：`_filesystemSafe` 只做 `unsafe?.replaceAll(RegExp(r'[/?<>:*|.\\"]'), "_")`。
- 副檔名來自 `downloadItem.syncTranscodingProfile?.codec.container ?? mediaSources?.firstOrNull?.container`。

**metadata 會進路徑**（artist / albumArtist / album / track index），但**會加 8 碼 id 後綴**避重名 —— 這是可以直接借的折衷。

圖片下載另走一條：`fileName = "${Uuid().v4()}.image"`、子目錄 `FINAMP_BASE_IMAGES_DIRECTORY`，完成後才依 `event.mimeType` 把副檔名改成 `.jpg`/`.bmp`/`.png`/`.gif`。

### 6. 內嵌 tag

**程式碼**：**沒有**。全 repo 的 tag 寫入相關符號（`metadata_god`、`taglib`、`writeMetadata`、`-metadata`）我沒找到任何下載路徑上的使用。

### 7. 下載 ↔ 音樂庫關聯（最值得學的一段）

`DownloadItem` 是 Isar model（[`finamp_models.dart#L1613`](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/models/finamp_models.dart#L1613)），帶真正的**關係鏈**：

```
IsarLinks<DownloadItem> requires;      // 這筆下載需要誰先完成
IsarLinks<DownloadItem> requiredBy;    // 誰需要我
IsarLinks<DownloadItem> info;          // 我附帶的資訊節點（歌詞等）
IsarLinks<DownloadItem> infoFor;
String path;                           // 相對路徑
@Name("viewId")  int? isarViewId;
DownloadLocation? fileDownloadLocation / syncDownloadLocation   // computed
```

節點型別是階層：**anchor → collection → album/playlist → track → image**，用一個 anchor 節點把整棵樹串起來。`DOWNLOADS_PLAN.md` 說明動機：「it will allow me to actually model relations in the database to make adding and removing downloads more reliable」，並說明舊系統散在五個 Hive DB（`DownloadedItems`、`DownloadedParents`、`DownloadIds`、`DownloadedImages`、`DownloadedImageIds`）。`DownloadIds` 的存在理由文件也寫得很清楚：「a copy of the data stored in `DownloadedItems`, but indexed by the `flutter_downloader` download ID so that we can track the download ID back to the actual song.」—— 這正是舊套件逼出來的冗餘表，換到 `background_downloader` 後被關係模型取代。

狀態機 `enum DownloadItemState`（[`#L1798`](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/models/finamp_models.dart#L1798)）：
`notDownloaded, downloading, failed, complete, enqueued, syncFailed, needsRedownload, needsRedownloadComplete`，附 `isFinal` / `isComplete` 便利 getter，以及 `static DownloadItemState fromTaskStatus(TaskStatus status)` 把套件狀態映射回自家狀態。

### 8. 刪除

`deleteDownload(DownloadItem)`（[`#L634`](https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/services/downloads_service_backend.dart#L634)）：

1. 取消已入列的套件任務；
2. 刪檔；
3. **只在 `useHumanReadableNames` 為真、且父目錄已空時**才刪父目錄（非 human-readable 模式共用 `songs/`，所以不能刪）；
4. `updateItemState(transactionItem, DownloadItemState.notDownloaded)` —— **保留記錄**，只改狀態；
5. 若是 track，順帶刪掉 `DownloadedLyrics`。

也就是「**記錄留下、狀態改掉**」而不是「刪 row」。

### 9. 權限流程

**程式碼**：`permission_handler` 全 repo 唯一一處使用是**被註解掉的**（`lib/services/downloads_service.dart` 約 L441），註釋引 issue #134 說「suggesting this does not make a request and always returns failure」。實務上的「權限」步驟就是 `FilePicker.getDirectoryPath()`；失敗或路徑不可寫的處理**查不到**結構化流程。**結論：Finamp 沒有可用的權限退化（fallback）設計，這點是反例。**

### README / 文件宣稱（與程式碼分開）

- **README 宣稱**（`DOWNLOADS_PLAN.md`，屬 repo 內設計文件）：換掉 `flutter_downloader` 改用 `background_downloader` 的四個理由 ——「Better looking API」（說 `flutter_downloader` 在 iOS 有下載無法標記完成的 bug）、「Scoped storage support」（自承外部目錄 practically broken）、「Relative path handling by default」、「Better stability」。同時說明 Hive → Isar 的動機是「actually model relations」。
- 我**驗證過為真**的部分：相對路徑（`DownloadItem.file` 用 `currentPath + path`）、Isar 關係（`IsarLinks`）、`background_downloader` 取代 `flutter_downloader`（pubspec 只有前者）。
- 我**未能驗證**的部分：`flutter_downloader` 的 iOS bug、`background_downloader` 的穩定性比較 —— 這些是作者的判斷，不是我能從程式碼核實的事實。

---

## Namida `[N]` — namidaco/namida @ `e8363dbf`

這是六個產品裡**下載引擎做得最完整**的一個，也是最接近「host 自己管下載」的樣板。

### 1. 佇列與併發

**兩層獨立的併發控制**：

**檔案層**：`class YoutubeParallelDownloadsHandler`（[`lib/youtube/controller/parallel_downloads_controller.dart#L10`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/controller/parallel_downloads_controller.dart#L10)）持有 `_tasks`（以 `DownloadTaskFilename` 為 key）、`_queue: Queue<_ParallelDownloadTask>`、`_runningCount`。設定入口是

```dart
void setMaxParallelDownloads(int count) {
  settings.youtube.save(downloadParallelCount: count.withMinimum(1));
  _startQueued();
}
```

（同檔 L19–22）。`_startQueued()` 用 `while (_runningCount < maxCount && _queue.isNotEmpty)`，並且在真正啟動前才檢查 `shouldSkip(task.config)`；`_run` 完成後 `_finish` 再 `_startQueued()` 補位。

**單檔執行緒層**：`settings.youtube.downloadThreadsCount`（[`lib/controller/settings.youtube.dart#L56`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/settings.youtube.dart#L56)），`downloadParallelCount = RxnF<int>(fallback: 4)`、下一行 `downloadThreadsCount = RxnF<int>(fallback: 3)`。

**預設值：4 個檔案併發 × 每檔 3 執行緒。**

### 2. 背景下載

**程式碼**：**沒有 WorkManager**（pubspec 沒有 `workmanager`），**沒有下載專用 foreground service**（AndroidManifest 只有 `audio_service` 的 `AudioService` + `MediaButtonReceiver`）。下載跑在一個**共用 isolate**：

```dart
class FilesDownloadManager with PortsProvider<SendPort> {
  static final inst = ...;   // 註釋：「Resumable downloads running in a shared isolate.」
```

（`lib/controller/files_download_manager.dart`）。progress 以 100ms 批次回報，註釋寫「progress is batched, sending each chunk floods the main isolate, especially with parallel downloads」（`_kProgressReportIntervalMs = 100`）。

維持存活的手段是**要求電池優化例外**：`requestIgnoreBatteryOptimizations()` 先跳一個帶「dont ask again」按鈕的常駐 snackbar 才發請求（`lib/controller/platform/permission_manager/permission_manager.dart`），manifest 有 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`。README 也把這條列在權限說明：「`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (requested when needed): improve downloads.」

**這是弱點**：相比 NewPipe 的 foreground service，靠 battery-optimization 例外在現代 Android 上不可靠。**推測**這也是為何它需要 `_kStallTimeout = Duration(seconds: 30)` 與 5 次重試。

### 3. 續傳（本節是全文最有價值的部分）

`abstract class DownloadWrapper`（`lib/class/download_wrapper.dart`）的常數與策略：

- `_kMaxRetries = 5`、`_kStallTimeout = Duration(seconds: 30)`、`_retryBackoff` 註釋寫「1s, 2s, 4s, 8s, then 10s」。
- `_isRetryable` 涵蓋 5xx / 408 / 429 / Timeout / Socket / Handshake / Http / Rhttp*。

**Range 的用法**：`_downloadRange(...)` 裡

```dart
final rangeHeader = end == null ? 'bytes=$start-' : 'bytes=$start-${end - 1}';
```

**續傳位移 = 磁碟上既有檔案大小**（不是 ETag、不是 If-Range）：

```dart
start = targetBaseOffset + targetSize;      // targetSize = _sizeSync(target)
FileMode.writeOnlyAppend
```

**三個關鍵的防護**：

1. 伺服器回非 206 且 `targetSize > 0` → `onWritten(-targetSize, 0); targetSize = 0; writeMode = FileMode.writeOnly;`，註釋：「server didnt honor our range request, restarting from scratch to not corrupt the file」。
2. `_contentRangeMatches` 驗證 `Content-Range` 的 start 與 total 是否與 `totalBytes` 一致。
3. 收到 **416** 時，用 `_contentRangeTotal(contentRange) == start` 判斷是否其實已經下載完成。

**多執行緒的續傳設計**（`class MultiThreadedDownloadWrapper`）：`_kPartExtension = '.part'`，parts 放在 `'$filePath.parts'`，檔名 `<index>.part`，每個 part 存的是從 `index * chunkSize` 開始的位元組。設計註釋是我看過最精煉的一句：

> file only grows by whole chunks so it always holds a valid prefix, and each `<index>.part` holds the bytes from `index * chunkSize`, so everything resumes from file sizes alone

搭配 `partsSizeSync` / `deleteParts` / `_parsePartIndex` / `_chunkLength`。`_kCopyBufferSize = 1 << 20`。

是否啟用多執行緒的條件（`files_download_manager.dart` L25/L39）：

```dart
static const _kChunkSize = 8 * 1024 * 1024;
...
if (_kMultiThreaded && threads > 1 && totalBytes > _kChunkSize) { ... }
```

**`ETag` / `If-Range` 完全沒有出現** —— 值得注意，因為對「URL 會過期、內容可能變動」的串流來源，用檔案大小當續傳依據本身有正確性風險（**推測**：作者接受這個風險，因為目標是 YouTube 上不會變的媒體串流）。

### 4. 儲存位置

**`AppDirs`**（`lib/core/constants.dart`）：

```dart
AppDirs.YOUTUBE_DOWNLOADS_DEFAULT = _join(INTERNAL_STORAGE, 'Downloads')
static String get YOUTUBE_DOWNLOADS => settings.youtube.ytDownloadLocation.value
AppDirs.INTERNAL_STORAGE = FileParts.joinPath(isWindowsPortable ? AppDirs.ROOT_DIR : paths[0], 'Namida')
```

（`AppDirs.INTERNAL_STORAGE` 的組裝在 `lib/main.dart` L204）。也就是 **`Namida/Downloads`，使用者可見，可用內建檔案瀏覽器改**：`NamidaFileBrowser.getDirectory(note: lang.defaultDownloadLocation)` → `settings.youtube.save(ytDownloadLocation: path)`。

**不用 SAF**，改用 `MANAGE_EXTERNAL_STORAGE`（見 §9）。這是刻意的取捨：全樹可寫，代價是要一顆被 Google Play 限縮的權限。

分組目錄：`_getGroupDirectoryPath(groupName) => FileParts.joinPath(AppDirs.YOUTUBE_DOWNLOADS, groupName.groupName)`；快取模式 `_getTempDirectoryPath(...) => config.cacheOnly ? AppDirs.VIDEOS_CACHE_TEMP : _getGroupDirectoryPath(groupName)`。

### 5. 檔名與目錄結構（yt-dlp 風格，最值得借）

`lib/youtube/controller/yt_filename_rebuilder.dart` 的 `_YtFilenameRebuilder`：

- 模板語法用 yt-dlp 的 `%(param)s`：`paramRegex = RegExp(r'%\((\w+)\)s')`。
- 使用者模板裡**必須**存在的參數：`encodedParamsThatShouldExistInFilename = const ['video_id','id','video_url','url','video_title','title','playlist_index','playlist_autonumber']` —— 這是**唯一性閘門**：強制使用者模板至少含一個能保證不撞名的參數。
- 找不到的值填 `fallback = 'NA'`。
- `_keywordToInfo` 是一個大 switch，處理 title/artist 解析（含從 description 抽、`keepFeatKeywordsOnly`、`_removeTopicKeyword` 去掉 YouTube 自動加的 "- Topic" 後綴）。
- 淨化：`DownloadTaskFilename.cleanupFilenameRegex = RegExp(r'[*#\$|/\\!^:"\?%<>⼸⁄⧸]', caseSensitive: false)`。
- **長度上限分平台**：`_fullPathLimit` = Windows 258 / macOS 1024 / 其他 4096，單一組件上限 255。
- 撞名處理：`withNumberSuffix` → `name (n).ext`。

README 的對應宣稱：「Downloads output filename builder (similar to yt-dlp)」、「Tags config for downloads」、「Optional Auto title/artist/album extraction for downloads and scrobbling」。

### 6. 內嵌 tag

**程式碼**：**有寫**，用**內附的 ffmpeg**（`lib/controller/ffmpeg_controller.dart`）。

`NamidaFFMPEG.ffmpegEditMetadata({required String path, MIFormatTags? oldTags, required Map<String, String?> tagsMap, bool keepFileStats = true})` 的做法是寫到 `.temp_${path.hashCode}.$ext` 再搬回原路徑（避免半成品）。

**opus 家族的坑寫得很明確**：

```dart
const opusEtcFormats = {'opus','ogg','oga','ogx','flac','alac'};
// 註釋：overwriting tags for opus is not supported, we need to remove all first
//       (-map_metadata -1) and write all combined
```

所以那類格式會加 `-map_metadata -1 -disposition:v attached_pic`。參數組裝：

```dart
params.add('-metadata'); params.add('${e.key}=$valueCleaned');
... '-id3v2_version','3','-write_id3v2','1','-c','copy','-y'
```

**這是「用 ffmpeg 統一寫 tag」路線的完整實作參考**，含格式差異的處理。讀取端另外用了 `flutter_taglib` 的 fork（**這是我的紀錄，本次未重新核對 pubspec**）。

### 7. 下載 ↔ 音樂庫關聯

**程式碼**：任務狀態存在**每個 group 一個 sqlite DB**（透過 `namico_db_wrapper` 的 `DBWrapperMainSync(params.tasksDatabasesPath)`）：

```dart
downloadTasksGroupDB.put(config.filename.key, config.toJson());
```

另有舊 `.json` 任務檔的 migration。影片記錄的 model 是 `NamidaVideo { path, ytID, nameInCache, height, width, sizeInBytes, frameratePrecise, creationTimeMS, durationMS, bitrate }` —— **`path` 與 `ytID` 都在記錄裡**，且 `nameInCache` 與最終檔名分開存（下載中用 cache 名，完成後才 move 到 `moveTo` / `moveToRequiredBytes` 的最終路徑）。

沒有像 Finamp 那樣的關係圖；是扁平的「一筆任務 = 一列」。

### 8. 刪除

`FilesDownloadManager.deleteDownloadFiles(File)` —— **同時刪掉 `.parts` 目錄**（否則會留下孤兒分塊）。UI 入口我沒逐一追（**查不到**確切入口點，但 `DownloadTaskFilename` 為 key 讓刪除能精準對到目標）。

### 9. 權限流程

`lib/controller/platform/permission_manager/permission_manager.dart`：

```dart
_shouldRequestManageAllFilesPermission = NamidaFeaturesAvailablity.android11and_plus.resolve();

Future<bool> requestManageStoragePermission({bool request = true, bool showError = true, required String? directoryToCreate}) async {
  await Permission.manageExternalStorage.request();
  // 失敗 → snackyy(title: lang.storagePermissionDenied, message: lang.storagePermissionDeniedSubtitle, isError: true); return false;
  // 成功 → 建立 directoryToCreate
}
```

（同檔 L87 起）。舊 Android 走 `Permission.storage` 或 `Permission.audio/videos/photos`（`requestStoragePermission`），**永久拒絕時呼叫 `openAppSettings()`**。

manifest 權限清單很長，關鍵幾條：`MANAGE_EXTERNAL_STORAGE`、`READ_EXTERNAL_STORAGE android:maxSdkVersion="32"`、`WRITE_EXTERNAL_STORAGE`、`READ_MEDIA_AUDIO/VIDEO/IMAGES`、`POST_NOTIFICATIONS`、`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`、`WRITE_SETTINGS`、`QUERY_ALL_PACKAGES`、`android:requestLegacyExternalStorage="true"`。

### 反例 / 要避開的

- **`MANAGE_EXTERNAL_STORAGE` + 自建檔案瀏覽器**換來全樹可寫，但代價是無法上 Google Play（除非符合豁免）。FMP 若要上架，這條走不通。
- `parallel_downloads_controller.dart` 的第一行註釋是 `// rewrite by claude` —— 提醒：這個檔案有一次 AI 重寫的歷史，引用其設計時要留意它與其他檔案的風格差異。
- 靠 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 而非 foreground service 維持背景下載，是這份調查裡最不可靠的一條路。

---

## Spotube `[S]` — KRTirtho/spotube @ `69a310c7`

**這是全文最該當反面教材的實作**：功能看起來齊（佇列、分塊、tag、封面），但每一項都在關鍵處少一塊。

### 1. 佇列與併發

**程式碼**：`lib/provider/download_manager_provider.dart`。

```dart
enum DownloadStatus { queued, downloading, completed, failed, canceled }
class DownloadTask { track, status, cancelToken, totalSizeBytes, downloadedBytesStream }
```

併發**硬編碼 1**（[`#L265`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/download_manager_provider.dart#L265)）：

```dart
Future<void> _startDownloading() async {
  for (final task in state) {
    if (task.status == DownloadStatus.downloading) return;   // 有一個在跑就整個 return
    if (task.status == DownloadStatus.queued) {
      try { await _downloadTrack(task); } finally { await _startDownloading(); }
    }
  }
}
```

**佇列只存在記憶體**：`build()` 回 `[]`，所以**重啟後佇列消失、沒有任何持久化**（對照 Finamp 的 Isar `DownloadItem`、Namida 的 sqlite 任務表、NewPipe 的 metadata 檔）。

`addToQueue` 會避重並註明「No await should be invoked to avoid stuck UI」（L102/L116/L123 都出現同一句）。

### 2. 背景下載

**程式碼**：**沒有下載用的背景機制**。`android/app/src/main/AndroidManifest.xml` 的 `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 屬 `audio_service` 播放；`BIND_JOB_SERVICE` 屬於 `home_widget`（佈景小工具），不是下載。**結論：切到背景後下載是否繼續沒有保證。**

### 3. 續傳

**沒有續傳，而且是刻意的**：`lib/extensions/dio.dart` 的 `chunkDownload` 在**開始前**先把暫存目錄整個刪掉：

```dart
if (await tempSaveDir.exists()) await tempSaveDir.delete(recursive: true);
```

錯誤路徑上也刪。暫存路徑是 `tempRootDir/Spotube/.chunk_dl_<filename>`，分塊存成 `part_$i` 再串接成目標檔。

Range 只用來**加速**，不是續傳：先 HEAD 帶 `'Range': 'bytes=0-0'` 讀 content-length，再判斷

```dart
supportsRange = headResp?.statusCode == 206 ||
                headResp?.headers.value(HttpHeaders.acceptRangesHeader) == 'bytes';
```

（[`#L58`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/extensions/dio.dart#L58)）。不支援 Range 或 `connections <= 1` 就退回套件本身的 `download()`。分塊：`chunkSize = (totalLength / connections).ceil()`、`connections = 4`。

**缺 `Content-Range` 驗證**（對照 Namida 的 `_contentRangeMatches`）—— 任一分塊回錯內容都會被無聲串進成品。

### 4. 儲存位置

`_getDefaultDownloadDirectory()`：

- Android **硬編碼** `"/storage/emulated/0/Download/Spotube"`
- macOS `join((await paths.getLibraryDirectory()).path, "Caches")`
- 其餘 `getDownloadsDirectory()/Spotube`

路徑用 drift 持久化：`setData(PreferencesTableCompanion(downloadLocation: Value(downloadDir)))`，設定頁在 `lib/pages/settings/sections/downloads.dart`。

**與 Finamp 同一個病**：挑目錄用 `FilePicker.platform.getDirectoryPath`（行動/macOS）或 `file_selector` 的 `getDirectoryPath`（桌面），**只拿到字串路徑、沒有 SAF 授權**。Android 硬編碼路徑 + `requestLegacyExternalStorage="true"` 在 Android 11+ 直接不可寫（**推測**這就是為什麼需要 `requestLegacyExternalStorage` —— 一個已經在 API 33 失效的旗標）。

### 5. 檔名與目錄結構

```dart
savePath = join(downloadLocation,
  ServiceUtils.sanitizeFilename("${track.query.name} - ${track.query.artists.map((e) => e.name).join(", ")}.${container.getFileExtension()}"));
```

**完全扁平**（沒有 album/artist 子目錄），檔名是 `曲名 - 藝人1, 藝人2.ext`。淨化：`sanitizeFilename` 取代 `[\/\?<>\\:\*\|"]` 與控制字元 `[\x00-\x1f\x80-\x9f]`。撞名時跳 `_shouldReplaceFileOnExist` 對話框（`ReplaceDownloadedDialog`，用 `replaceDownloadedFileState` memo 化）。

### 6. 內嵌 tag

**有**，用 `metadata_god: ^1.1.0`（[`#L250`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/download_manager_provider.dart#L250)）：

```dart
await MetadataGod.writeMetadata(file: savePath, metadata: task.track.toMetadata(...));
```

`toMetadata`（[`lib/models/metadata/track.dart#L92`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/models/metadata/track.dart#L92)）設 title、artist（join `", "`）、album、albumArtist、year（`album.releaseDate`，fallback 1970）、durationMs、`fileSize: BigInt.from(fileLength)`，封面用 `Picture(data: imageBytes, mimeType: lookupMimeType(...) ?? "image/jpeg")`，圖從 `ServiceUtils.downloadImage(...index: 1)` 取得。

**一個可愛的細節**：`if (container.getFileExtension() == "weba") return;` —— WebM audio 直接跳過寫 tag。這是對「有些容器寫不了 tag」的務實處理，可借。

### 7. 下載 ↔ 音樂庫關聯

**程式碼**：**幾乎沒有**。`lib/pages/library/user_downloads.dart` 只顯示**記憶體裡的當前佇列**（`context.l10n.currently_downloading(downloadQueue.length)` + 「全部取消」），**沒有已下載清單**。重啟後 app 不知道哪些歌下載過。

**唯一的痕跡是檔案系統**：`_downloadTrack` 開頭就是「同路徑檔案已存在 → 問要不要取代」，也就是用檔名碰撞當作「下載過」的判斷。**這是最脆弱的關聯方式**（改個 naming 就全失效）。

### 8. 刪除

`DownloadManager` 只有 cancel（`cancelToken`）。**已下載檔案沒有 app 內刪除入口**（查不到）；只能靠系統檔案管理器。

### 9. 權限流程

`lib/hooks/configurators/use_get_storage_perms.dart` 請求 `Permission.storage` 或 Android 13+ 的 `Permission.audio`，檢查 `isGranted` / `isLimited`。**拒絕後的處理查不到結構化流程**（沒有 `openAppSettings` 的痕跡）。manifest：`INTERNET`、`WAKE_LOCK`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`WRITE/READ_EXTERNAL_STORAGE`、`READ_MEDIA_AUDIO`、`android:requestLegacyExternalStorage="true"`。

---

## NewPipe `[P]` — TeamNewPipe/NewPipe @ `7e5df38a`

Android 原生，giga 下載引擎（`us.shandian.giga`）。**這是六個產品裡唯一有正規 foreground service + SAF + 完整災難恢復的實作**，也是這份調查裡「Android 下載」最正確的參考。

### 1. 佇列與併發

**程式碼**：`DownloadManager`（[`app/src/main/java/us/shandian/giga/service/DownloadManager.java#L30`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/us/shandian/giga/service/DownloadManager.java#L30)）。

併發由一個**布林**控制，不是數字：

```java
boolean start = !mPrefQueueLimit || getRunningMissionsCount() < 1;
if (canDownloadInCurrentNetwork() && start) { mission.start(); }
```

（[`#L265`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/us/shandian/giga/service/DownloadManager.java#L265)）。`getRunningMissionsCount()`（L398）只數「running 且未完成、非後處理失敗」的任務。

- **`mPrefQueueLimit` 預設 `true`**（[`app/src/main/res/xml/download_settings.xml#L76`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/res/xml/download_settings.xml#L76) 的 `android:defaultValue="true"`，偏好讀取在 `DownloadManagerService.java#L326`）→ **預設一次只跑 1 個下載**。
- 設定標籤是「enable queue limit」（`downloads_queue_limit`），使用者可關掉 → 變成全部一起跑（**不是有限的 N**，是無上限，這點值得注意）。

**單檔執行緒數**：`mission.threadCount`（`DownloadMission.java#L128` 的 dartdoc「Maximum of download threads running, chosen by the user」，預設值在 L131 `public int threadCount = 3;`），由 `DownloadManagerService.startMission(...)` 的 `threads` 參數傳入（`EXTRA_THREADS`），靜態工廠 `startMission` 在 `DownloadManagerService.java#L355` 附近。

**重試**：`mPrefMaxRetry`（`DownloadManagerService.java#L318` 從偏好讀），mission 建立時 `this.maxRetry = 3`（`DownloadMission.java`）。

**排序**：`mMissionsPending` 是 `ArrayList`，搭配 `enqueued` 旗標與 `mPrefQueueLimit` 掃描；`DownloadManager.java#L459`/`L520` 附近的迴圈在 queue limit 模式下 `break`。

**README / 設定頁宣稱**：`max_retry_msg` = "Maximum retries"、"Maximum number of attempts before canceling the download"（`strings.xml#L666`）。

### 2. 背景下載（本產品最重要的參考）

**程式碼**：`DownloadManagerService` **是 foreground service**。

- manifest：[`app/src/main/AndroidManifest.xml#L138`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/AndroidManifest.xml#L138)
  `<service android:name="us.shandian.giga.service.DownloadManagerService" android:foregroundServiceType="dataSync" />`
  —— 型別是 **`dataSync`**（API 34 起要在 manifest 聲明，這是正確的型別）。
- 進入前景：`public void updateForegroundState(boolean state)` → `startForeground(FOREGROUND_NOTIFICATION_ID, mNotification)`（[`DownloadManagerService.java#L338`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/us/shandian/giga/service/DownloadManagerService.java#L338)），離開用 `ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)`。
- **同時加鎖**：同一個函式末尾 `manageLock(state)`，而 `manageLock`（L493）呼叫 `mLock.acquireWifiAndCpu()` / `releaseWifiAndCpu()` —— 即 **WifiLock + WakeLock 一起拿**。
- 通知帶 `PendingIntent` 指向 `DownloadActivity`（L146–162），另有獨立的「下載完成」通知（`notifyFinishedDownload`，在 `downloadDoneNotification` 上 `setDeleteIntent(null)` 並加註「prevent NewPipe running when is killed, cleared from recent, etc」）。
- 通知權限：`checkPostNotificationsPermission`（TIRAMISU 起），且用 `App.getInstance().getNotificationsRequested()` **只問一次**。

**這是本份調查裡唯一真正可靠的背景下載實作**，其他五個都沒有。

### 3. 續傳（設計最精細）

**程式碼**：核心是 `int[] blocks` —— dartdoc 寫得很清楚（`DownloadMission.java` 約 L115）：

> Download blocks, the size is multiple of `BLOCK_SIZE`. Every entry (block) in this array holds an offset, used to resume the download. An block offset can be **-1 if the block was downloaded successfully**.

區塊大小 `BLOCK_SIZE`；`DownloadInitializer.java` 算數量：

```java
int count = (int) (mMission.length / DownloadMission.BLOCK_SIZE);
if ((count * DownloadMission.BLOCK_SIZE) < mMission.length) count++;
mMission.blocks = new int[count];
// if one thread is required don't calculate blocks, is useless
```

（[`DownloadInitializer.java#L123`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/us/shandian/giga/get/DownloadInitializer.java#L123)）。**`blocks == null && current == 0` 是「首次下載」的判斷**（L51）。

**多執行緒**：`threads = new Thread[Math.min(threadCount, remainingBlocks)]`，每個執行緒跑一個 `DownloadRunnable(this, i)` 並以 `acquireBlock()`（synchronized）搶下一個未完成的 block（`DownloadMission.java#L475`、`acquireBlock` 在 L167 附近）。單執行緒退回 `DownloadRunnableFallback`（L465），並用 `fallbackResumeOffset`。

**Range 的組裝**：`HttpURLConnection openConnection(boolean headRequest, long rangeStart, long rangeEnd)`（[`#L217`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/us/shandian/giga/get/DownloadMission.java#L217)）：

```java
String req = "bytes=" + rangeStart + "-";
if (rangeEnd > 0) req += rangeEnd;
conn.setRequestProperty("Range", req);
```

並在 L253/L256 log 出 `Range=` 與 `Content-Range=`（可觀測性做得比別人好）。

**伺服器不支援 Range 時**：L509 `Log.w(TAG, "pausing a download that can not be resumed (range requests not allowed by the server).")` —— 明確放棄續傳並把任務標成無法續傳。

**災難恢復（最獨特的一段）**：因為 NewPipe 下載的是 YouTube 的**時效性 URL**，續傳時 URL 常常已經失效。所以有：

- `DownloadMissionRecover`（`threads[0] instanceof DownloadMissionRecover` 用來判斷是否在恢復中，`DownloadMission.java#L684`）
- `MissionRecoveryInfo`（含 `DownloadMissionRecover.java`、`MissionRecoveryInfo.kt`）
- `recoveryInfo` 陣列存在 mission 上，並經 `EXTRA_RECOVERY_INFO` 傳遞（`DownloadManagerService.java` 的 `startMission` 參數說明寫「array of MissionRecoveryInfo, in case is required recover the download」）
- 錯誤碼 `ERROR_RESOURCE_GONE`、`ERROR_PROGRESS_LOST`、`ERROR_POSTPROCESSING_STOPPED` 等

**啟動時的對帳**（`DownloadManager.loadPendingMissions`，L150 起）非常值得逐條讀：

1. 掃 `pending_downloads/` 目錄（`getPendingDir`：先試 `context.getExternalFilesDir("pending_downloads")`，失敗退 `context.getFilesDir()`，都失敗就 `throw new RuntimeException`）。
2. `Utility.readFromFile(sub)` 讀不回來的就刪檔。
3. `mis.isFinished()` → 移到 finished 清單（`setFinished`）並刪 metadata 檔，註釋「DON'T delete missions that are truly finished - let them be moved to finished list」。
4. `mis.hasInvalidStorage() && errCode != ERROR_PROGRESS_LOST` → 只在 `mis.storage == null` 時才真刪，註釋「Only delete if it's truly unrecoverable (not just progress lost)」。**「進度丟失不等於任務不可回收」是這裡的核心洞見。**
5. `StoredFileHelper.deserialize(mis.storage, ctx)` 還原儲存 handle，`exists = !mis.storage.isInvalid() && mis.storage.existsAsFile()`。
6. 後處理中斷（`mis.isPsRunning()`）：若演算法是 `worksOnSameFile`，認為結果已損壞而刪檔，標 `ERROR_POSTPROCESSING_STOPPED`。

Metadata 檔的命名是 **timestamp**（`mission.metadata = new File(mPendingMissionsDir, String.valueOf(mission.timestamp))`，`DownloadManager.java` startMission 內），撞名就換一個 timestamp 重試。

**注意：完全沒有 ETag / If-Range**。NewPipe 用「block 位移 + 檔案存在」＋（換 URL 的）mission recovery 取代。跟 Namida 同樣的取捨。

### 4. 儲存位置（SAF 做得最正確）

**程式碼**：`org.schabi.newpipe.streams.io.StoredFileHelper`（實作 `Serializable`，因為要寫進 metadata）與 `StoredDirectoryHelper`。

`StoredFileHelper` 有兩條路徑：

```java
public StoredFileHelper(final Context context, final Uri uri, final String mime) {
    if (FilePickerActivityHelper.isOwnFileUri(context, uri)) {
        final File ioFile = Utils.getFileForUri(uri);
        ioPath = ioFile.toPath();  source = Uri.fromFile(ioFile).toString();   // 純檔案路徑
    } else {
        docFile = DocumentFile.fromSingleUri(context, uri);  source = uri.toString();  // SAF single URI
    }
}
```

內部欄位同時保有 `docFile` / `docTree`（SAF）與 `ioPath`（java.nio），並用 `FileStream` / `FileStreamSAF` 兩個實作把兩種後端統一成同一個 stream 介面。**`deserialize` / `isInvalid` / `existsAsFile` / `create` / `createFile` / `createUniqueFile` 這一整套是 SAF 生命週期管理的實作參考** —— 尤其 `isInvalid()` 這個概念（SAF 授權可能在重裝/清資料後失效，必須能偵測並重建）。

**SAF 的強制程度**（`NewPipeSettings.java#L105`）：

```java
public static boolean useStorageAccessFramework(final Context context) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        return true;                      // API 29+ 一律 SAF，無商量
    } else if (DeviceUtils.isFireTv()) {
        return false;                     // FireOS 的 SAF 對話框無法用遙控器確認 (#6455)
    }
    final String key = context.getString(R.string.storage_use_saf);
    return prefs.getBoolean(key, true);   // 舊版預設仍是 true
}
```

設定字串也說明得很誠實（`strings.xml#L678-680`）：`downloads_storage_use_saf_title` = "Use system folder picker (SAF)"、`downloads_storage_use_saf_summary` = "The 'Storage Access Framework' allows downloads to an external SD card"、`downloads_storage_use_saf_summary_api_29` = "**Starting from Android 10 only 'Storage Access Framework' is supported**"。

**音訊與視訊分開的兩個 handle**：`DownloadManager` 的建構子 `DownloadManager(Context, Handler, StoredDirectoryHelper storageVideo, StoredDirectoryHelper storageAudio)`（`DownloadManager.java#L67`），tag 常數 `public static final String TAG_AUDIO = "audio"` / `TAG_VIDEO = "video"`。預設目錄（非 SAF 模式）：`saveDefaultVideoDownloadDirectory` → `Environment.DIRECTORY_MOVIES`、`saveDefaultAudioDownloadDirectory` → `Environment.DIRECTORY_MUSIC`，都再包一層 `NewPipe`（`getNewPipeChildFolderPathForDir` → `new File(dir, "NewPipe").toURI().toString()`）。

**這個「音訊/視訊各自一個 SAF tree + 一個 tag 字串」的設計直接對應 FMP 的需求**（多來源、可能多型別），很值得照抄。

### 5. 檔名與目錄結構

`DownloadDialog`（`app/src/main/java/org/schabi/newpipe/download/DownloadDialog.java`）：`filenameTmp = getNameEditText().concat(".")`（L761），再依格式附副檔名，例如 L771 `filenameTmp += "opus"`、L774/L783/L797 `filenameTmp += format.getSuffix()`、L795 `MediaFormat.SRT.getSuffix()`。也就是**使用者可在下載對話框直接改檔名**，副檔名由串流格式決定。

淨化在 `FilenameUtils.kt`（[`app/src/main/java/org/schabi/newpipe/util/FilenameUtils.kt`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/util/FilenameUtils.kt)）：

- `CHARSET_MOST_SPECIAL = "[\\n\\r|?*<\":\\\\>/']+"`、`CHARSET_ONLY_LETTERS_AND_DIGITS = "[^\\w\\d]+"`
- **取代字元也是使用者設定**：`settings_file_replacement_character_key`，預設 `"_"`；字元集也可選（`settings_file_charset_key`）或自填正則
- 註釋引 issue 編號：「#143 #44 #42 #22: make sure that the filename does not contain illegal chars.」
- 註解提到 `title`：「@param title the title to create a filename from」

**結構完全扁平**（單層目錄 + 檔名），沒有 album/artist 子目錄。**撞名處理很完整**：`checkSelectedDownload(mainStorage, mainStorage.findFile(filenameTmp), filenameTmp, mimeTmp)`（L542/L860），後續在 L880–L1006 之間用 `mainStorage.createFile` ／ `createUniqueFile` 嘗試；註釋提到要避開「the filename is not used in a pending/finished download」（L926）—— **撞名檢查有把「未完成的下載」算進去**，這點很多實作會漏。

### 6. 內嵌 tag

**程式碼**：**不寫 tag**。`us.shandian.giga.postprocessing` 只有五個檔：`M4aNoDash.java`、`Mp4FromDashMuxer.java`、`OggFromWebmDemuxer.java`、`Postprocessing.java`、`TtmlConverter.java`、`WebMMuxer.java` —— 全是**容器層**處理（DASH 的 audio/video 合併、WebM→Ogg 解封裝、字幕轉換），沒有任何 `-metadata` / tag 寫入。全 `org/schabi/newpipe/` 只有一個檔案名命中 `ffmpeg`（`streams/Mp4FromDashWriter.java`，而那是自寫的 MP4 寫入器，不是 ffmpeg binary）。

**串流資訊改存在 app 自己的 DB**（見 §7）—— 這是一個合理替代方案：既然寫 tag 要嘛加 ffmpeg 依賴、要嘛加 native 庫，NewPipe 選擇「檔案是純媒體、metadata 在 app 裡」。

### 7. 下載 ↔ 音樂庫關聯

**程式碼**：`us.shandian.giga.get.sqlite.FinishedMissionStore`（SQLite，`SQLiteOpenHelper`）：

```java
private static final String DATABASE_NAME = "downloads.db";
private static final int DATABASE_VERSION = 4;
MISSIONS_CREATE_TABLE =
  "CREATE TABLE " + FINISHED_TABLE_NAME + " (" +
    KEY_PATH       + " TEXT NOT NULL, " +     // "path"
    KEY_SOURCE     + " TEXT NOT NULL, " +     // "url"
    KEY_DONE       + " INTEGER NOT NULL, " +  // "bytes_downloaded"
    KEY_TIMESTAMP  + " INTEGER NOT NULL, " +
    KEY_KIND       + " TEXT NOT NULL, " +     // "kind"：a / v / s
    " UNIQUE(" + KEY_TIMESTAMP + ", " + KEY_PATH + "));";
```

（[`app/src/main/java/us/shandian/giga/get/sqlite/FinishedMissionStore.java`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/us/shandian/giga/get/sqlite/FinishedMissionStore.java)）。另有舊表 `MISSIONS_TABLE_NAME_v2 = "download_missions"` 的 migration 痕跡，`DATABASE_VERSION = 4`。

**重啟後如何知道**：`loadFinishedMissions()`（`DownloadManager.java#L110` 起）在載入時**逐筆檢查檔案是否還在**：

```java
// check if the files exists, otherwise, forget the download
for (int i = finishedMissions.size() - 1; i >= 0; i--) { ... }
```

**「DB 記錄 + 啟動時跟檔案系統對帳」** 是這份調查裡第二種可靠模式（第一種是 Finamp 的「檔案存在 + 狀態欄位對帳」）。`path` 是完整字串（SAF URI 或檔案路徑），`kind` 區分音/視/字幕。

### 8. 刪除

`DownloadManager.deleteMission(Mission mission, boolean alsoDeleteFile)`（[`#L287`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/us/shandian/giga/service/DownloadManager.java#L287)）：

```java
if (mission instanceof DownloadMission)      mMissionsPending.remove(mission);
else if (mission instanceof FinishedMission) { mMissionsFinished.remove(mission); mFinishedMissionStore.deleteMission(mission); }
if (alsoDeleteFile) mission.delete();
```

**「移除記錄」與「刪檔案」是兩個獨立選項**（`alsoDeleteFile`）—— 這是很好的 API 設計，讓 UI 能分別提供「只從清單移除」與「連檔案一起刪」。

另有一個 `forgetMission(StoredFileHelper storage)`（L305）：`mission.storage = null; mission.delete();` —— **刻意忘掉儲存 handle（例如 SAF 授權已失效）**，用在 `tryRecover` 失敗時。

**UI 入口**：`us.shandian.giga.ui.adapter.MissionAdapter` 搭配 `us.shandian.giga.ui.common.Deleter`：

```java
mDeleter = new Deleter(root, mContext, this, mDownloadManager, mIterator, mHandler);
...
mDownloadManager.deleteMission(mission, true);   // 單筆，連檔刪
mDeleter.append(h.item.mission, true);           // 加入多重刪除佇列，連檔刪
mDeleter.append(h.item.mission, false);          // 只移除記錄
```

（`MissionAdapter.java` L137/L624/L675/L680/L688）。`Deleter` 另有 `pause()` / `resume()` / `dispose()`（L796–L805），即**多重刪除是可暫停的批次作業**。

### 9. 權限流程（最正確的一版）

`PermissionHelper`（[`app/src/main/java/org/schabi/newpipe/util/PermissionHelper.java`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/util/PermissionHelper.java)）：

```java
public static boolean checkStoragePermissions(final Activity activity, final int requestCode) {
    if (NewPipeSettings.useStorageAccessFramework(activity)) {
        return true; // Storage permissions are not needed for SAF
    }
    if (!checkReadStoragePermissions(activity, requestCode)) return false;
    return checkWriteStoragePermissions(activity, requestCode);
}
```

**核心洞見：走 SAF 就不需要任何儲存權限。** 這是把 §4 與 §9 綁在一起的關鍵 —— SAF 不是「比較好的儲存方式」，它是「**唯一不需要權限的儲存方式**」。對照 Namida 用 `MANAGE_EXTERNAL_STORAGE` 換全樹可寫、Finamp/Spotube 用 legacy 權限 + 字串路徑，NewPipe 的做法是唯一在 API 29+ 上不需要特殊權限且真正可寫外部儲存的路。

請求碼有三個獨立常數：`POST_NOTIFICATIONS_REQUEST_CODE = 779`、`DOWNLOAD_DIALOG_REQUEST_CODE = 778`、`DOWNLOADS_REQUEST_CODE = 777`。

`checkWriteStoragePermissions` 裡原本的 `shouldShowRequestPermissionRationale` 分支被**整段註解掉**（含它自己的 `/* ... */`），留下的註釋是「No explanation needed, we can request the permission.」—— 即**不做 rationale 說明**，直接請求。這算簡化，不算最佳實務（**推測**：這條路徑在 API 29+ 已經走不到，所以沒人維護）。

`checkSystemAlertWindowPermission` 處理 `SYSTEM_ALERT_WINDOW`（下載浮動視窗用），在 Android R+ 因為 `ACTION_MANAGE_OVERLAY_PERMISSION` 只會開到列表頁，改成**先跳一個說明對話框**再跳設定（含把 app 名與權限名用 `<i>` 斜體的 HTML 格式化訊息）。這是「跳系統設定前先解釋」的實作樣板。

---

## Musify `[M]` — gokadzev/Musify @ `5b98d3a3`

最**簡**的一個：用 `youtube_explode_dart` 的高階 API 直接把串流 pipe 進檔案，其餘全部靠 app-private 目錄省掉權限問題。

### 1. 佇列與併發

**程式碼**：

- **播放清單下載**：`OfflinePlaylistService.downloadPlaylist`（`lib/services/playlist_download_service.dart`）建一個 `Queue<dynamic>` 與 **3 個 worker**：

  ```dart
  const maxConcurrent = 3;
  final workerCount = songsList.length < maxConcurrent ? songsList.length : maxConcurrent;
  await Future.wait([for (var i = 0; i < workerCount; i++) _processDownloadQueue(songQueue, progressNotifier)])
    .timeout(Duration(minutes: songsList.length * 2), onTimeout: () { ... });
  ```

  （[`#L137`](https://github.com/gokadzev/Musify/blob/5b98d3a3cddd3fdb16ea6cc14d59d667e82cccd2/lib/services/playlist_download_service.dart#L137)）。**硬編碼 3，不可設定**。整批有 `songsList.length * 2` 分鐘的總逾時。
- **單曲下載**：`makeSongOffline`（[`lib/services/common_services.dart#L832`](https://github.com/gokadzev/Musify/blob/5b98d3a3cddd3fdb16ea6cc14d59d667e82cccd2/lib/services/common_services.dart#L832)）**沒有全域佇列或限流**，直接 `await`。同時下載多首單曲 → 沒有上限（**推測**這是刻意的，因為單首下載是使用者明確動作）。
- 狀態用 `ValueNotifier<List>` 與 `activeDownloads` 字串清單（`List<String> activeDownloads`），**沒有持久化**（重啟後 `activeDownloads` 清空、`downloadProgressNotifiers` 清空）。

### 2. 背景下載

**程式碼**：**沒有下載專用的背景機制**。`android/app/src/main/AndroidManifest.xml` 只有：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
...
<service android:name="com.ryanheise.audioservice.AudioService" android:foregroundServiceType="mediaPlayback" />
```

全部是 `audio_service`（播放）用的。**下載中切到背景是否會繼續 → 查不到任何保證**（`WAKE_LOCK` 存在但沒有對應的下載服務；**推測**只在播放維持前景服務期間僥倖存活）。對照 NewPipe 的 `dataSync` foreground service，這是明顯缺口。

### 3. 續傳

**沒有**。`makeSongOffline` 的核心是：

```dart
final audioManifest = await fetchBestAudioStream(ytid);
final stream = ytClient.videos.streamsClient.get(audioManifest);
fileStream = audioFile.openWrite();
await stream.pipe(fileStream);
```

失敗路徑 `if (await audioFile.exists()) await audioFile.delete();` —— **中斷就刪、重來**，完全沒有 Range。

### 4. 儲存位置（最省事的一條路）

**程式碼**：`lib/main.dart#L335`：`applicationDirPath = (await getApplicationDocumentsDirectory()).path;`

`lib/services/io_service.dart` 的 `class FilePaths`：

```dart
static const String tracksDir = 'tracks';
static const String artworksDir = 'artworks';
static const String streamBufferDir = 'stream_buffer';

static String getAudioPath(String songId) => '$applicationDirPath/$tracksDir/$songId$audioExtension';
static String getArtworkPath(String songId) => '$applicationDirPath/$artworksDir/$songId$artworkExtension';
static String getStreamBufferDirPath() => '$applicationDirPath/$streamBufferDir';
```

`ensureDirectoriesExist()` 建這三個目錄。

**關鍵洞見：選 app-private 目錄 → 完全不需要任何儲存權限**（manifest 裡一條 storage permission 都沒有），也不需要 SAF、不需要選目錄 UI。代價是檔案使用者看不到、其他播放器讀不到、換手機帶不走。**對「以 app 為中心的下載」這是最省事的正解**；FMP 若要兩者兼得就得兩條路都做。

### 5. 檔名與目錄結構

**最極簡的路徑之一**：檔名就是 **`<ytid><ext>`**（`getAudioPath`），**完全沒有 metadata 進路徑**，也沒有可讀的曲名。

`audioExtension` 與 `artworkExtension` 是全域常數（`io_service.dart`）；實際副檔名由 `fetchBestAudioStream` 拿到的 manifest 決定（`audioManifest.audioCodec` / `audioManifest.bitrate.kiloBitsPerSecond`）。

**這種「id 當檔名」的做法唯一好處是零碰撞、零淨化問題、id 一查就到**；壞處是使用者完全無法辨識（除非讀 app DB）。**這是上一份 playlist 調查裡也要注意的反例**。

### 6. 內嵌 tag

**程式碼**：**不寫 tag**。

- pubspec 沒有 `metadata_god`、沒有 taglib、沒有 ffmpeg 相關套件（`youtube_explode_dart` 與 `youtube_music_explode_dart` 是 path 依賴的本機 fork）。
- 封面存成 **sidecar 檔案**：`_downloadAndSaveArtworkFile(offlineSong['highResImage'], artworkPath)`，然後 `offlineSong['artworkPath'] = artworkPath`。
- `grep 'metadata_god\|taglib\|ID3\|writeMetadata'` 在 `lib/` 與 `pubspec.yaml` **零命中**。

**「封面當 sidecar 檔案 + DB 記路徑」是完整可行的替代方案**（很多播放器都這樣做），比寫 tag 少了格式相容性的坑。

### 7. 下載 ↔ 音樂庫關聯（第二好的樣板）

**程式碼**：**Hive box `userNoBackup`**（`lib/services/common_services.dart`）：

```dart
ValueNotifier<List> userOfflineSongs = ValueNotifier<List>(...);
```

`makeSongOffline` 成功後寫入的欄位（同檔約 L912–L918）：

```dart
offlineSong['audioPath'] = audioFile.path;
offlineSong['audioBitrateKbps'] = audioBitrateKbps;
offlineSong['audioCodec'] = audioCodec;
offlineSong['dateAdded'] = DateTime.now().millisecondsSinceEpoch;
```

用 `ytid` 當 key 做 upsert，再 `addOrUpdateData<List>('userNoBackup', 'offlineSongs', userOfflineSongs.value)` 持久化。

**最有意思的設計**：**路徑同時「存」也「可重算」**。

- 存：`audioPath` 在記錄裡。
- 可重算：`FilePaths.getAudioPath(ytid)` 純函式，只要 `applicationDirPath` 對，路徑永遠能推回來。

`isSongAlreadyOffline(ytid)`（L532）先查 `userOfflineSongs` 的 id 集合，找到之後**還要再檢查 `File(audioPath).exists()`**：

```dart
if (isSongAlreadyOffline(ytid)) {
  final existingPath = FilePaths.getAudioPath(ytid);
  if (await File(existingPath).exists()) { ... return true; }
}
```

（L841–L846）—— **「記錄說有 + 檔案真的在」雙重確認**，這是這份調查裡第三次出現同一個模式（Finamp、NewPipe、Musify 都做，Spotube 只有半個）。**這三家的共識比任何單一實作都更有說服力：下載狀態不可以只信 DB。**

還有 `_cachedOfflineSongIds = _createSongIdCache(userOfflineSongs)`（L82）—— 為了避開每次都掃整個 list，維護一份 id 快取。

**播放清單層**：`OfflinePlaylistService.offlinePlaylists` 存另一份清單，`checkAndAutoMarkOffline(playlist)` 在所有歌都離線時自動把整個 playlist 標成 offline（含 `downloadedAt`）。也就是**下載狀態有兩層：單曲 + 歌單**，而且歌單層是**推導出來**的（不是使用者明確下載才會有）。

### 8. 刪除

`removeSongFromOffline(dynamic songId)`（[`#L954`](https://github.com/gokadevz/Musify/blob/5b98d3a3cddd3fdb16ea6cc14d59d667e82cccd2/lib/services/common_services.dart#L954)）：

1. 刪 `FilePaths.getAudioPath(songId)`；
2. 刪 `FilePaths.getArtworkPath(songId)`；
3. `userOfflineSongs.value = ... removeWhere((song) => song['ytid'] == songId)`，再寫回 Hive。

**每一步都包在自己的 try/catch 裡**（刪檔失敗不會擋住清記錄），而且**檔案與記錄都刪**（不像 Finamp 留記錄）。

UI 入口：`lib/widgets/song_bar.dart` 的 toggle（`removeOfflineText` / `makeOfflineText`，L157），另有 `OfflinePlaylistService.removeSongFromOfflineAndResync`（`playlist_download_service.dart#L392`）處理「刪單曲後同步歌單離線狀態」。

### 9. 權限流程

**程式碼**：**完全沒有**。`grep 'Permission'` 在 `lib/` 零命中，manifest 也沒有任何 storage permission。

**結論：Musify 用「選 app-private 目錄」把權限問題整個消掉了。** 這是六個產品裡唯一一個完全不需要處理權限的 —— 也是最誠實的取捨：它放棄了「使用者可見的下載檔案」這個功能，換來零權限、零 SAF、零相容性問題。

### README 宣稱

- **README 宣稱**：「Offline listening support」（README 第 29 行）。**我驗證過為真**（`makeSongOffline` / `userOfflineSongs` / `OfflinePlaylistService`）。

---

## MusicFree `[X]` — maotoumao/MusicFree @ `d118b18b`

React Native，**插件架構的旁證**（任務指定可簡短）。這是六個產品裡唯一一個與 FMP 新架構同型（來源 = 外部 JS 插件、host 負責下載）的實作，所以插件契約那段值得細看。

### 插件契約（對 FMP 的 `resolveStream` 最直接可比）

`src/types/plugin.d.ts`（[permalink](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/types/plugin.d.ts)）：

```ts
export interface IMediaSourceResult {
    headers?: Record<string, string>;
    /** 兜底播放 */
    url?: string;
    /** UA */
    userAgent?: string;
    /** 音质 */
    quality?: IMusic.IQualityKey;
}
...
/** 获取根据音乐信息获取url */
getMediaSource?: (
    musicItem: IMusic.IMusicItemBase,
    quality: IMusic.IQualityKey,
) => Promise<IMediaSourceResult | null>;
```

**三個可以直接對到 FMP 設計的點**：

1. **插件回傳的是「一個 URL + headers + UA」，不是位元組**。host 負責所有 HTTP。這正是任務描述的「用 plugin `resolveStream` 取得候選串流清單」的形狀。
2. **`quality` 是「一次一個音質」而不是「回一整份清單」**。要候選清單的話是**由 host 逐個音質去問**（見下）。
3. `headers` 與 `userAgent` 分開回傳；`url` 的註釋寫「**兜底播放**」（fallback playback）—— 即這個 url 也可能來自 `musicItem.url` 而不是插件現算。

`IPluginDefine` 的其他欄位也值得一看：`platform`（來源名）、`primaryKey?: string[]`（「主鍵，會被存儲到 mediameta 中」）、`supportedSearchType?: ICommon.SupportMediaType[]`、`cacheControl?: "cache" | "no-cache" | "no-store"`、`userVariables?: IUserVariable[]`、`hints?: Record<string, string[]>`。**`primaryKey` 的概念對 FMP 很有用**：跨來源辨識同一首歌時，插件自己宣告哪些欄位構成主鍵。

### 下載（host 端）

`src/core/downloader.ts`（[permalink](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/downloader.ts)）：

**狀態機**：`DownloadStatus { Pending, Preparing, Downloading, Completed, Error }`。
**失敗原因列舉**（`DownloadFailReason`）：`NetworkOffline` / `NotAllowToDownloadInCellular` / `FailToFetchSource` / `NoWritePermission` / `Unknown`。**把失敗原因做成明確的列舉而不是自由字串**，這點值得借。

**併發：可設定 1..10，預設 3**（[`#L183`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/downloader.ts#L183)）：

```ts
const maxDownloadCount = Math.max(1, Math.min(+(this.configService.getConfig("basic.maxDownload") || 3), 10));
```

搭配 `downloadNextPendingTask()` 的遞迴排程：先檢查 `downloadingCount >= maxDownloadCount`，再找第一個 `Pending` 任務，標成 started，**在真正 download 之前先遞迴呼叫 `downloadNextPendingTask()`**（L270 的註釋是「预处理完成，可以开始处理下一个任务」）—— 即「連結解析」與「位元組傳輸」兩階段重疊，避免解析慢的任務卡住整條佇列。**這是個聰明的排程細節。**

**候選串流清單的取得（host 逐個音質去問插件）**（L215–L240）：先由 `getQualityOrder(目標音質, config basic.downloadQualityOrder ?? "asc")` 產生一個**音質順序陣列**，再逐一 `await plugin.methods.getMediaSource(musicItem, quality, 1, true)`，取第一個有 `data.url` 的：

```ts
for (let quality of qualityOrder) {
  try {
    data = await plugin.methods.getMediaSource(musicItem, quality, 1, true);
    if (!data?.url) { continue; }
    break;
  } catch { }
}
url = data?.url ?? url;      // 插件全失敗 → 退回 musicItem.url（兜底）
headers = data?.headers;
```

**這是「候選清單」在插件架構下的實際形狀**：不是插件一次回一個陣列，而是 host 依偏好順序**逐一協商**，失敗就降級到下一個音質，全失敗才用兜底 URL。`try { } catch { }` 空 catch 說明**插件拋錯被視為該音質不可用**，而不是任務失敗。

**下載本體**：`react-native-fs` 的 `downloadFile({ fromUrl, toFile, headers, background: true, begin, progress })`（[`#L302`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/downloader.ts#L302)）。

- **`background: true`** 交給 RNFS 的原生背景下載機制（**這是六個產品裡第二個有意識處理背景下載的**）。
- **先下到暫存路徑再搬**：`cacheDownloadPath`（`nanoid().<ext>`，在 `<basePath>/cache/download/`）→ 成功後 `await copyFile(cacheDownloadPath, targetDownloadPath)` → 最後 `await unlink(cacheDownloadPath)` 清理。**因為暫存檔名是 `nanoid()`，所以沒有節點──重試等於全新下載，沒有續傳。**
- 副檔名從 URL 猜：`getExtensionName(url)` 用正則抓，fallback `"mp3"`；再對 `supportLocalMediaType` 白名單，不在名單內一律改成 `mp3`。**這是「不能信任 URL 尾綴」的正確態度。**

**寫入權限的偵測方式很務實**（L290–L296）：不主動請求權限，而是**試著建目標資料夾，失敗就報 `DownloadFailReason.NoWritePermission`**：

```ts
const folder = path.dirname(targetDownloadPath);
const folderExists = await exists(folder);
if (!folderExists) { await mkdirR(folder); }
// catch → this.emit(DownloaderEvent.DownloadTaskError, DownloadFailReason.NoWritePermission, ...)
```

**`NoWritePermission` 是「權限不足」的具體 symptom，不是抽象概念** —— 這比抽象地問「有沒有權限」更可靠，因為 SAF/Android 的權限狀態本來就難以窮舉。

### 儲存位置

`src/constants/pathConst.ts`：

```ts
export const basePath = Platform.OS === "android"
    ? RNFS.ExternalDirectoryPath      // Android: app 專屬外部目錄（不需權限）
    : RNFS.DocumentDirectoryPath;     // iOS: Documents

export default {
    basePath,
    pluginPath: `${basePath}/plugins/`,
    localLrcPath: `${basePath}/local_lrc/`,
    downloadCachePath: `${basePath}/cache/download/`,
    downloadPath: `${basePath}/download/`,
    downloadMusicPath: `${basePath}/download/music/`,
    ...
};
```

下載路徑由 `getDownloadPath(fileName)` 決定：`configService.getConfig("basic.downloadPath") ?? pathConst.downloadMusicPath`（可設定，預設 `<basePath>/download/music/`）。

**`RNFS.ExternalDirectoryPath` 是關鍵**：它是 `/sdcard/Android/data/<pkg>/files/`，**使用者可見（透過檔案管理器）但不需要任何權限**。這是介於「app-private」與「SAF」之間的第三條路 —— **FMP 若不想碰 SAF 又想要使用者能看到檔案，這是值得評估的選項**（代價：Android 11+ 的使用者透過檔案管理器存取 `Android/data` 受限，且解除安裝時被清掉，跟 app-private 一樣）。

### 檔名

```ts
private static generateFilename(musicItem: IMusic.IMusicItem) {
  return `${escapeCharacter(musicItem.platform)}@${escapeCharacter(musicItem.id)}@${escapeCharacter(musicItem.title)}@${escapeCharacter(musicItem.artist)}`.slice(0, 200);
}
```

格式：**`平台@id@標題@藝人`**，`escapeCharacter` 淨化，**整體截斷到 200 字元**。

**`平台@id@標題@藝人` 這個組合很聰明**：`平台@id` 保證唯一（可解析回來源）、`標題@藝人` 保證人類可讀。**「結構化分隔符 + 前段保證唯一 + 後段保證可讀 + 總長截斷」** —— 比起 Finamp 的「可讀名稱 + 8 碼 id 後綴」更明確（因為分隔符讓程式可以反解）。值得借。

`getExtensionName` 的正則（L152–L160）也值得一提：

```ts
url.match(/^https?\:\/\/.+\.([^\?\.]+?$)|(?:([^\.]+?)\?.+$)/)
```

先試 `.ext` 結尾，再試 `?` 前的 `.ext`，都不中就 `"mp3"`。

### 內嵌 tag

**程式碼**：下載流程**不寫 tag**。`src/native/mp3Util/index.ts` 的介面裡**有** `setMediaTag: (filePath, meta: IWritableMeta) => Promise<void>` 與 `IWritableMeta { lyric?, comment?, ... }`，但 `grep` 顯示下載流程（`downloader.ts`）**沒有呼叫它**。

`mp3Util` 的實際用途全在**讀**本地檔案時：`localMusicSheet.ts#L170` 的 `mp3Util.getMediaMeta(...)`、`pluginManager/plugin.ts#L1041` 的 `Mp3Util.getMediaCoverImg(localPath)`、`#L1054` 的 `Mp3Util.getLyric(localPath)`、`#L1082` 的 `Mp3Util.getBasicMeta(urlLike)`。

**下載後只把路徑記進 DB**：

```ts
LocalMusicSheet.addMusic({ ...musicItem, [internalSerializeKey]: { localPath: targetDownloadPath } });
patchMediaExtra(musicItem, { downloaded: true, localPath: targetDownloadPath });
```

（`downloader.ts` L330–L340）。即 **metadata 完全靠 app 自己的 DB，檔案本體是裸的**。

**這是一個重要的架構選擇**：MusicFree 的插件**本來就提供完整的 `IMusicItem`**（title/artist/album/封面 URL），所以不需要從檔案裡讀 metadata —— 寫 tag 的唯一理由是「給其他播放器看」。**FMP 的插件架構有同樣的性質**：既然 `resolveStream` 的來源已經知道曲名藝人，寫 tag 與否就是「要不要讓外部播放器受益」的產品決策，不是技術必需品。

### 下載 ↔ 音樂庫關聯

**兩層**：

1. `LocalMusicSheet.addMusic({...musicItem, localPath})` —— 進「本地音樂」清單。
2. `patchMediaExtra(musicItem, { downloaded: true, localPath })` —— 在媒體的 extra 屬性上打 `downloaded` 旗標 + 路徑。

`removeMusic(musicItem, alsoDeleteFile)`（`src/core/localMusicSheet.ts#L77`）：

```ts
export async function removeMusic(musicItem, alsoDeleteFile) {
    ...
    await unlink(localPath);     // L91
}
```

**刪除入口**：`src/components/panels/types/musicItemOptions.tsx` L146–L166，兩個獨立選項：

```tsx
await LocalMusicSheet.removeMusic(musicItem);             // 只從清單移除
...
title: t("panel.musicItemOptions.deleteLocalDownload"),
content: t("panel.musicItemOptions.deleteLocalDownloadConfirm"),
...
await LocalMusicSheet.removeMusic(musicItem, true);       // 連檔案刪（有確認對話框）
```

**「移除」與「刪檔」兩個選單項、刪檔有確認對話框、i18n key 分開** —— 跟 NewPipe 的 `alsoDeleteFile` 同一個思路，而且多了「確認」這一步。**這是 UI 層最完整的參考。**

`remove(musicItem)`（downloader 上的另一個方法）只處理**尚未下載的任務**：只有 `Pending` / `Error` 狀態可以取消，`Preparing` / `Downloading` 回 `false`（**即已開始的任務無法取消** —— 這是個缺口，`AbortController` 之類的機制查不到）。

### 其他值得注意的

- **下載前檢查網路狀態**：`network.isOffline` → 報 `NetworkOffline`；`network.isCellular && !config basic.useCelluarNetworkDownload` → 報 `NotAllowToDownloadInCellular`（`download()` 開頭）。**「行動網路下不下載」是設定項**，這點 FMP 也該考慮（大檔案在行動網路下載是很實際的痛點）。
- **事件匯流排**：`Downloader extends EventEmitter<IEvents>`，四個事件 `DownloadError` / `DownloadTaskUpdate` / `DownloadTaskError` / `DownloadQueueCompleted`，UI 用 `useDownloadTask(musicItem)` hook 訂閱（`downloader.on(...)` + cleanup `off`）。**下載器與 UI 完全解耦**。
- **去重**：`download()` 用 `filter` 同時擋「已在 downloadTasks 裡」與 `LocalMusicSheet.isLocalMusic(m)`，並在 filter 裡順手建立任務（副作用寫在 filter 裡，可讀性差，但有效）。

---

## 對 FMP 新下載子系統的可借鏡點與反例

前提：FMP 新架構是「所有來源都是 JS script plugin，下載由 host 處理，用 plugin 的 `resolveStream` 取得候選串流清單」。以下按主題分。

### A. 可借鏡的設計（依價值排序）

**A1. 「候選串流清單」在插件架構下的實際形狀 = host 逐個協商，不是插件回陣列。**
MusicFree 的做法值得直接照搬形狀：host 先由使用者偏好產生一個**音質順序**（`getQualityOrder(目標, "asc"/"desc")`），逐一 `getMediaSource(item, quality)`，**取第一個有 `url` 的**，全部失敗才退回 `musicItem.url` 兜底（`downloader.ts#L215-240`）。
可借的三個細節：
- **插件拋錯 = 該候選不可用**（`try {} catch {}` 空 catch），而不是整筆下載失敗；
- **兜底 URL 與插件算出的 URL 是同一條路徑**（`url = data?.url ?? url`），所以插件完全失效時下載仍可能成功；
- 插件回傳 `{ url, headers, userAgent }` 三元組（`plugin.d.ts` 的 `IMediaSourceResult`），**headers 與 UA 分開** —— FMP 的 `resolveStream` 契約應該照這個形狀設計，因為串流來源幾乎都需要自訂 header。
另外 MusicFree 的 `IPluginDefine.primaryKey?: string[]`（插件自己宣告哪些欄位構成主鍵）**對 FMP 的跨來源歌曲辨識很有用**，值得納入插件契約。

**A2. 「DB 記錄 + 啟動時與檔案系統對帳」是三家共識，不是任一家偏好。**
Finamp（`item.file?.existsSync()` → 標 complete／重新入列）、NewPipe（`loadFinishedMissions()` 逐筆檢查檔案還在不在，「check if the files exists, otherwise, forget the download」）、Musify（`isSongAlreadyOffline(ytid)` 之後**還要** `File(audioPath).exists()`）**全都做同一件事**。Spotube 沒做，而 Spotube 正是唯一「重啟後完全不知道下載過什麼」的產品。
**這條應該當硬性要求**：下載狀態不可只信 DB，也不可只信檔案系統，必須兩者對帳。Musify 的雙重確認寫法（先查 id 集合再驗檔案）成本最低。

**A3. 相對路徑 / 可重算路徑，勝過存絕對路徑。**
- Finamp 用 `DownloadLocation.currentPath + item.path`（相對），文件說明動機是「this will solve the absolute path issue」—— iOS 的 app 容器路徑每次更新都會變。
- Musify 更徹底：**路徑是純函式 `FilePaths.getAudioPath(ytid)`**，記錄裡的 `audioPath` 只是快取。
**對 FMP**：若下載目錄可能跨平台或跨版本變動（Windows 可攜版、Android 換外部儲存），**存「相對路徑」或「可從 id 重算」是唯一穩健的做法**。Finamp 的雙軌（下載位置存 `baseDirectory` 列舉 + `relativePath`）比 Musify 的純函式更靈活，但兩者都比絕對路徑好。

**A4. 續傳的依據用「磁碟上檔案大小」，並配三個防護。**
Namida 的實作（`download_wrapper.dart`）是目前看過最實務的：
1. `start = targetBaseOffset + targetSize`（`targetSize = _sizeSync(target)`，即既有檔案大小）；
2. 伺服器**回非 206 且 targetSize > 0 → 整個重來**（註釋：「server didnt honor our range request, restarting from scratch to not corrupt the file」）；
3. `_contentRangeMatches` **驗證 `Content-Range` 的 start 與 total**；
4. **416 → 用 `_contentRangeTotal(contentRange) == start` 判斷是否其實已下載完**。
NewPipe 的 `blocks[]`（每塊位移、-1 = 完成）是另一個更精細的變體，但對「單檔 + 少量並行」的 FMP 而言 Namida 的檔案大小法更簡單且已足夠。
**注意：六個產品（含 NewPipe）沒有任何一個用 ETag / If-Range。** 對 FMP 的 plugin 串流（URL 有時效性、內容理論上可能變動），用檔案大小當續傳依據**有正確性風險**。NewPipe 的答案是 `DownloadMissionRecover` / `MissionRecoveryInfo`：**URL 失效時不是放棄，而是重新協商一組新 URL 並接續**。FMP 若要支援續傳，必須回答「URL 過期了怎麼辦」，這是 NewPipe 唯一提供了完整答案的地方。

**A5. 多執行緒的暫存設計：「整塊成長，所以永遠是合法前綴」。**
Namida 的 `MultiThreadedDownloadWrapper`：parts 放 `'$filePath.parts'`，`<index>.part` 存從 `index * chunkSize` 起算的位元組，設計註釋是最好的一句總結：
> file only grows by whole chunks so it always holds a valid prefix, and each `<index>.part` holds the bytes from `index * chunkSize`, so everything resumes from file sizes alone
**這讓「目標檔案」本身就是進度表**，不需要額外的分塊狀態 DB，且任何中斷點都能只用檔案大小恢復。搭配 `_kChunkSize = 8 * 1024 * 1024` 與「只有當 `threads > 1 && totalBytes > chunkSize` 才多執行緒」的守門。**FMP 若要分塊下載，這是可直接實作（而非借概念）的設計。**
反例是 Spotube：分塊暫存在**開始前先整個刪掉**、**零 `Content-Range` 驗證**、**串接成目標檔時不看每塊對不對** —— 分塊只帶來速度，帶來三個新的失敗模式。

**A6. 檔案命名：結構化分隔符 + 前段保證唯一 + 後段保證可讀 + 總長截斷。**
MusicFree 的 `` `${platform}@${id}@${title}@${artist}`.slice(0, 200) `` 是形狀最好的（分隔符讓程式能反解來源與 id，title/artist 給人看，200 字元上限防爆路徑）。
Namida 的 yt-dlp 風格模板最強但最複雜，可借其中**兩條規則**：
- **強制模板必含唯一性參數**：`encodedParamsThatShouldExistInFilename = ['video_id','id','video_url','url','video_title','title','playlist_index','playlist_autonumber']` —— 使用者可以自由改模板，但模板若不含任何一個保證不撞名的參數就拒絕。**這是「可設定」與「不會壞」之間的關鍵閘門。**
- **長度上限分平台**：`_fullPathLimit` = Windows 258 / macOS 1024 / 其他 4096，單一組件 255。Windows 的 258 是 FMP 有 Windows build 時會踩到的坑。
Finamp 的折衷也好用：可讀名稱 + **id 前 8 碼後綴**（`"$indexNumber$artist${item.name}_${item.id.raw.substring(0,8)}"`）。
**反面**：Musify 的檔名就是 `<ytid><ext>`（人類完全不可讀）、Spotube 是完全扁平的 `曲名 - 藝人.ext`（無子目錄、無唯一性保證，靠檔名碰撞當「下載過」的判斷）。
**要避免的淨化陷阱**：Finamp 的 `_filesystemSafe` 只取代 `[/?<>:*|.\\"]` —— **沒有處理控制字元、沒有長度限制、沒有 Windows 保留名（CON/PRN/NUL）**。Namida 的 `cleanupFilenameRegex` 與 Spotube 的 `sanitizeFilename`（含 `[\x00-\x1f\x80-\x9f]`）都更完整。NewPipe 的 `FilenameUtils` 最好用（字元集可選、取代字元可設定），但**把正則交給使用者填**是過度的自由度。

**A7. SAF 是「唯一不需要權限的可寫外部儲存」，NewPipe 的實作是完整參考。**
- `NewPipeSettings.useStorageAccessFramework()`：**API 29+ 一律 true，不給選**；只為 FireTV 的遙控器 bug (#6455) 例外。
- `PermissionHelper.checkStoragePermissions()`：**走 SAF 直接 `return true; // Storage permissions are not needed for SAF`**。
- `StoredFileHelper`：SAF（`DocumentFile` + tree URI）與 java.nio（`ioPath`）雙後端，用 `FileStream` / `FileStreamSAF` 統一成同一介面，**`Serializable` 且能 `deserialize` / `isInvalid()` / `create()`** —— 因為 SAF 授權會在重裝或清資料後失效，**可偵測 + 可重建是必要能力**。
- **音訊與視訊各自一個 `StoredDirectoryHelper` + 一個 tag 字串**（`TAG_AUDIO`/`TAG_VIDEO`），建構子明列這兩個參數。**FMP 多來源、可能多型別，這個「每個目的地一個 handle + 一個 tag」的形狀可以直接用。**
**反例（兩個成功產品都在這裡壞掉）**：Finamp 與 Spotube 都用 `file_picker` 的 `getDirectoryPath()` 拿到**字串路徑**，沒有持續化 SAF 授權 —— Finamp 自家文件寫「practically broken」並在 UI 掛紅字警告，Spotube 只能退回硬編碼 `/storage/emulated/0/Download/Spotube` + 已失效的 `requestLegacyExternalStorage="true"`。
**結論：要嘛完整的 SAF（NewPipe 路線），要嘛完全不碰（Musify 路線）。用 file_picker 拿字串路徑假裝支援使用者選目錄，是三者中最差的選項。**

**A8. 背景下載只有一條可靠的路：Android foreground service with `dataSync`。**
- NewPipe 是唯一做對的：manifest `android:foregroundServiceType="dataSync"`，`startForeground(...)` 配 `ServiceCompat.stopForeground(STOP_FOREGROUND_REMOVE)`，**同時 `acquireWifiAndCpu()`（WifiLock + WakeLock 一起）**，通知帶 `PendingIntent` 回下載頁，完成另有通知（且 `setDeleteIntent(null)` 並註記「prevent NewPipe running when is killed, cleared from recent, etc」），通知權限只問一次（`App.getInstance().setNotificationsRequested()`）。
- MusicFree 用 `react-native-fs` 的 `background: true`（把問題交給 RNFS 的原生實作）。
- Namida 靠 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` + **常駐 snackbar 反覆要求** —— 在現代 Android 上不可靠，**這是它需要 `_kStallTimeout = 30s` 與 5 次重試的真正原因**（推測）。
- Finamp 交給 `background_downloader`（該套件在 Android 用 WorkManager）。
- Spotube / Musify：**完全沒有**。
**FMP 若在 Android 上要「鎖屏也繼續下載」，除了 foreground service 沒有第二條路**；`foregroundServiceType` 要選 `dataSync`，且必須同時拿 WakeLock（否則 CPU 睡了傳輸會停）。另外要注意 Android 13+ 的 `POST_NOTIFICATIONS` 是 foreground service 通知能否顯示的前提。

**A9. 使用者可設定的是「檔案併發」與「單檔執行緒」兩個獨立旋鈕，且預設值不宜大。**
- Namida：`downloadParallelCount`（預設 **4**）× `downloadThreadsCount`（預設 **3**）。
- MusicFree：`maxDownloadCount` clamp 到 **1..10，預設 3**（`Math.max(1, Math.min(x || 3, 10))` —— **上界與下界都硬夾**）。
- NewPipe：queueLimit 布林（預設 true = 一次 1 個）+ 單檔 `threadCount` 預設 3。
- Finamp：`maxConcurrentDownloads`（註釋說一次 enqueue 這麼多）。
- Spotube：**硬編碼 1**；Musify：**硬編碼 3**。
**可借**：MusicFree 的 clamp 寫法最穩健（不會被 config 檔裡的值搞壞）；Namida 的「兩層分開設」對應兩個真正獨立的資源（網路連線數 vs 單檔並行）。**要避免**：NewPipe 的 `queueLimit` 是布林 —— 關掉它變成**無上限**，不是「可設定的 N」。

**A10. 刪除要有「移除記錄」與「刪檔案」兩個獨立選項，且刪檔要有確認。**
- NewPipe：`deleteMission(mission, alsoDeleteFile)`，UI 三處呼叫分別傳 `true`/`false`（`MissionAdapter` L624/L675/L680），另有可 `pause()`/`resume()` 的批次 `Deleter`。
- MusicFree：選單兩個獨立項（`deleteLocalDownload` 有確認對話框），i18n key 分開。
- Finamp：`deleteDownload` 留記錄、只改狀態成 `notDownloaded`（並順手刪歌詞）—— **也是合法選項**（保留「這首歌使用者曾想下載」的資訊）。
**FMP 需要明確回答一個問題**：刪檔之後，那首歌在 library 裡是「還在但沒下載」還是「消失」？Finamp 選前者、Musify 選後者（`removeWhere` 真的把記錄拿掉），NewPipe 兩者都給。
**順手的細節**：Namida 的 `deleteDownloadFiles(File)` **同時刪 `.parts` 目錄** —— 分塊下載一定要記得清孤兒分塊。Spotube 的暫存目錄也只是「下次開始時刪掉上一次的」，沒有主動清理。

**A11. 失敗原因做成明確的列舉。**
MusicFree：`DownloadFailReason { NetworkOffline, NotAllowToDownloadInCellular, FailToFetchSource, NoWritePermission, Unknown }`（`downloader.ts`）。NewPipe 的錯誤碼也是列舉（`ERROR_NOTHING` / `ERROR_HTTP_FORBIDDEN` / `ERROR_RESOURCE_GONE` / `ERROR_PROGRESS_LOST` / `ERROR_POSTPROCESSING_STOPPED` …）。
**這直接決定 UI 能不能給出有用的訊息**：「無網路」、「不允許行動網路下載」、「插件拿不到串流」、「沒有寫入權限」對使用者是四件不同的事、四種不同的處置，全部壓成「下載失敗」等於不給資訊。

**A12. 「行動網路下是否下載」是設定項。**
MusicFree：`network.isCellular && !config basic.useCelluarNetworkDownload` → 拒絕並報 `NotAllowToDownloadInCellular`。NewPipe：`mPrefMeteredDownloads`（`downloads_cross_network`，預設 false）+ `canDownloadInCurrentNetwork()` / `handleConnectivityState` / `NetworkState { Unavailable, Operating, MeteredOperating }`（`DownloadManager.java#L33`）—— **NewPipe 有一整套網路狀態機，並且在網路不可用時不啟動任務、等狀態變化再啟動**。這比「下載失敗後重試」正確得多。

**A13. 寫 tag 是可選的產品決策，不是技術必須；封面當 sidecar 檔案是完全可行的替代。**
- **寫 tag**：Namida（ffmpeg）、Spotube（`metadata_god`）。
- **不寫 tag**：Finamp、NewPipe、Musify、MusicFree（四家）。
而 MusicFree 的理由最清楚：**插件本來就提供完整 `IMusicItem`（title/artist/album/封面 URL），metadata 完全在 app DB 裡，寫 tag 的唯一理由是「給外部播放器看」**。FMP 的插件架構有同樣性質 —— 既然 `resolveStream` 的來源已經知道曲名藝人，**寫不寫 tag 是「要不要讓檔案離開 app 還能用」的決策**。
若決定要寫，Spotube 的務實處理值得抄：
```dart
if (container.getFileExtension() == "weba") return;   // 寫不了 tag 的容器直接跳過
```
以及 Namida 對格式差異的處理（`opus/ogg/oga/ogx/flac/alac` 要先 `-map_metadata -1` 再整套寫回，因為「overwriting tags for opus is not supported」），以及 finamp 那種「寫到 `.temp_<hash>.<ext>` 再搬回」的原子性做法。
Musify 的 sidecar 封面（`artworks/<ytid>.<ext>` + `offlineSong['artworkPath']`）證明**不寫 tag 也能有完整的使用者體驗**。

**A14. 儲存位置是「權限 vs 可見性」的四選一，三條可行路都已有人走完。**
- **app-private**（`getApplicationDocumentsDirectory`）：Musify。零權限、零 SAF、零相容性問題；使用者看不到、其他 app 讀不到、解除安裝即消失。
- **app 專屬外部目錄**（`RNFS.ExternalDirectoryPath` = `/sdcard/Android/data/<pkg>/files/`）：MusicFree。**零權限但仍可被檔案管理器看到**；與 app-private 同樣在解除安裝時被清掉，且 Android 11+ 使用者存取受限。
- **完整 SAF**（`ACTION_OPEN_DOCUMENT_TREE` + 持續化授權）：NewPipe。唯一能寫任意使用者目錄（含 SD 卡）且不需特殊權限的路；成本是要做完整的授權生命週期管理（`isInvalid` / `deserialize` / `create`）。
- **`MANAGE_EXTERNAL_STORAGE` + 自建瀏覽器**：Namida。全樹可寫、體驗最好；**代價是無法上 Google Play（除非符合豁免）**。
**FMP 是 Android + Windows 雙平台**，Windows 沒有 SAF 問題（`getDownloadsDirectory()` 直接可用），所以這個決策**只需要為 Android 做**。任務的「使用者自選資料夾」需求若必須滿足，只有 SAF 一條路；若可接受 app 目錄，Musify/MusicFree 的路線能把整個 §9 的權限章節刪掉。

**A15. 下載器與 UI 解耦（事件匯流排）。**
MusicFree：`Downloader extends EventEmitter<IEvents>`，四事件 `DownloadError` / `DownloadTaskUpdate` / `DownloadTaskError` / `DownloadQueueCompleted`，UI 用 `useDownloadTask(musicItem)` hook 訂閱並在 cleanup 時 `off`（`downloader.ts` 末段）。
Finamp 的對應是 `DownloadItemState` 的狀態機 + `fromTaskStatus(TaskStatus)` 映射 —— **把套件狀態明確映射回自家狀態**，避免套件的狀態列舉洩漏到 UI。
Namida 的 progress 批次回報（`_kProgressReportIntervalMs = 100`，註釋「sending each chunk floods the main isolate, especially with parallel downloads」）是跨 isolate 時的必備細節。

### B. 反例（FMP 應主動避開）

**B1. 不要把「檔名碰撞」當作「這首歌下載過」的判斷。**
Spotube 的 `_shouldReplaceFileOnExist`（同路徑檔案存在 → 問要不要取代）是它唯一的「下載過」判斷。**改一次 naming 規則，整個下載庫的辨識就全失效。**

**B2. 不要用 `file_picker` 的 `getDirectoryPath()` 假裝支援使用者選目錄。**
Finamp 與 Spotube 都這樣做，兩家的結果都是「功能宣稱存在、實際不可用」（Finamp 自承 practically broken 並掛紅字；Spotube 退回硬編碼路徑 + 已失效的 `requestLegacyExternalStorage`）。**這是這份調查裡最具體的一次失敗示範 —— 同一個 bug 在兩個獨立專案裡重現。**

**B3. 不要有「佇列只在記憶體」。**
Spotube 的 `build()` 回 `[]`，重啟後佇列與下載歷史全部消失。對照：Finamp（Isar）、Namida（per-group sqlite）、NewPipe（metadata 檔 + `downloads.db`）、MusicFree（DB 記 `localPath` + `downloaded` 旗標）、Musify（Hive）。**只有 Spotube 沒做，也只有 Spotube 有這個缺口。**

**B4. 續傳不可用時要明確放棄，不要靜默地從頭下載。**
NewPipe 有一行明確的 log：`Log.w(TAG, "pausing a download that can not be resumed (range requests not allowed by the server).")`（`DownloadMission.java#L509`），並把任務標成無法續傳。
Namida 的處理也好：伺服器不理 Range 時 `onWritten(-targetSize, 0)` **把已回報的進度扣回去**，讓 UI 的進度條不會顯示錯誤的百分比（註釋：「restarting from scratch to not corrupt the file」）。**「重來」要讓使用者看見進度歸零，而不是假裝還在繼續。**

**B5. 不要相信 URL 尾綴。**
MusicFree 是唯一有意識處理的：`getExtensionName` 抓不到就 `"mp3"`，抓到之後**還要對 `supportLocalMediaType` 白名單**，不在名單內一律改 `"mp3"`。
Spotube 的 `container.getFileExtension()` 來的容器格式是可信的（來自 API 而非 URL），但它的分塊流程**不做 `Content-Range` 驗證**，這比尾綴問題更嚴重。

**B6. 不要讓「已開始的下載」無法取消。**
MusicFree 的 `remove(musicItem)` 只接受 `Pending` / `Error` 狀態，`Preparing` / `Downloading` 回 `false` —— **已開始的任務使用者取消不掉**（`AbortController` / `CancelToken` 之類的機制查不到）。對照 Spotube 有 `cancelToken`、NewPipe 有 `pauseMission` / `deleteMission`、Namida 有 `stopDownload` / `stopDownloads`。**取消是基本能力，不該漏。**

**B7. 靠 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 維持背景下載不可靠。**
Namida 用**常駐 snackbar 反覆要求**（`requestIgnoreBatteryOptimizations()` 先跳一個帶「dont ask again」的提示才發請求），README 也把它列在權限說明。**在現代 Android（尤其各家 OEM 的省電策略下）這不是保證。** foreground service 才是。

**B8. 不要用 `MANAGE_EXTERNAL_STORAGE`，除非確定不需要上架。**
Namida 用它換來全樹可寫 + 自建檔案瀏覽器（體驗確實最好），但這顆權限在 Google Play 受到嚴格限縮。**這是一個產品決策而非技術決策，FMP 若計畫上架 Google Play 就必須排除這條路。**

### C. 查不到的部分（誠實列出）

1. **Finamp 的任務排序依據**：`_advanceQueue()` 一次 `limit(20)`，但排序欄位我沒追到。任務優先序有 `Priority.animation + 50`，但完整的排序規則查不到。
2. **Finamp 的權限失敗處理**：`permission_handler` 唯一一處被註解掉，`FilePicker` 回傳不可寫路徑時的後續流程我沒找到結構化的處理。
3. **Spotube 的權限拒絕處理**：`use_get_storage_perms.dart` 檢查 `isGranted`/`isLimited`，但拒絕後沒有 `openAppSettings` 之類的痕跡，後續流程查不到。
4. **NewPipe 的 `blockAcquired` / `writingToFileNext` / `writingToFile` 三個變數的完整協作**：看得出是「多執行緒寫同一檔案時的排序與互斥」，但我沒有讀完整段（`DownloadMission.java` 的 L800–L850 附近有 `for (Thread thread : threads)` 的收尾邏輯），**細節未核實**。
5. **Musify 的 `audioExtension` / `artworkExtension` 具體值**：`io_service.dart` 裡是常數，我沒讀到定義處。
6. **Namida 的下載刪除 UI 入口**：`deleteDownloadFiles` 存在，但從哪個畫面觸發我沒追。
7. **MusicFree 下載中任務的取消機制**：`remove` 只涵蓋 Pending/Error，`Preparing`/`Downloading` 的取消方式查不到。
8. **Spotube 已下載檔案是否有 app 內刪除入口**：`UserDownloadsPage` 只顯示記憶體佇列，沒找到已下載清單或刪除入口。
9. **Finamp / Namida 的 `flutter_taglib` fork 這條線索**：我先前紀錄裡提到 Namida 用了 `flutter_taglib` 的 fork 來**讀** tag，**本次未重新核對 pubspec**，僅供參考。
10. **各產品的 README 對「背景下載」的宣稱**：我沒有逐個核對 README 是否宣稱支援背景下載（Finamp / Namida / Musify / MusicFree 的 README 我只 grep 了 `download` 關鍵字）。**若 FMP 要引用某家的「背景下載」說法，需要另外回查該家 README，且必須以程式碼為準** —— 這份文件裡所有背景下載的結論都來自程式碼（manifest + service + 套件呼叫），不是 README。
