# current-state — Debug 頁相關現況（補 `docs/audit/devtools.md` 未涵蓋者）

查證日：2026-09-28
查證方式：唯讀原始碼（分支 `docs/audit`，repo 根目錄的現行專案），以 `檔案:行號` 逐條標註。未執行 App、未跑測試、未打任何音樂平台 API。
前置說明：`docs/audit/devtools.md`（審計日 2026-09-26）已完整描述的段落，本檔只**指回**不重抄；本檔只補它沒有的、或需要更精確行號的。
**重要前提**：repo 內**不存在 `app/` 目錄**（`ls app` 無此目錄），ADR 0008–0024 描述的 `app/lib/...` 是尚待建立的新專案；本檔描述的是現行 `lib/`（舊專案）。

---

## 1. 開發者模式

### 1.1 開啟與持久化
已被 `devtools.md` §1.1 完整涵蓋（連點 7 次、`requiredTaps = 7`、不持久化、無關閉入口、路由無條件註冊）。此處只補「開發者模式到底控制了什麼」，因為這決定 Debug 頁的開關語意。

### 1.2 `developerOptionsProvider` 的**全部**消費點（grep `developerOptionsProvider`，共 4 個檔案）

| 消費點 | 用途 | 檔案:行號 |
|---|---|---|
| 定義 | `NotifierProvider<DeveloperOptionsNotifier, DeveloperOptionsState>` | `lib/providers/settings/developer_options_provider.dart:76-79` |
| 設定頁的版本列 | 讀 `isEnabled`/`tapCount`，判斷要不要顯示「再點 n 次」提示 | `lib/ui/pages/settings/widgets/settings_about.dart:7-8`、`:23-32` |
| 設定頁的開發者區塊 | 只在 `isEnabled` 時顯示「開發者選項」那一列；否則 `SizedBox.shrink()` | `lib/ui/pages/settings/widgets/settings_about.dart:91-117`（`_DeveloperOptionsSection`）、掛載點 `lib/ui/pages/settings/settings_page.dart:194` |
| 開發者選項頁的日誌級別列 | 讀 `state.logLevel`、呼叫 `setLogLevel` | `lib/ui/pages/settings/developer_options_page.dart:603`、`:615` |

**事實**：開發者模式控制的只有兩件事——(a) 設定頁是否出現「開發者選項」入口；(b) 執行期 log 級別下拉。它**不**控制任何路由保護（§1.4）、**不**控制 Debug 頁內任何區塊的顯示（頁面內所有區塊無條件顯示）、也**不**影響 Toast（`devtools.md` §5 第 1 點已列；ADR 0023 已定開發者模式要讓錯誤提示附「詳細」）。

### 1.3 `DeveloperOptionsState` 三個欄位
`isEnabled`、`tapCount`、`logLevel`，皆記憶體狀態（`:6-34`）；`build()` 以 `AppLogger.minLevel` 初始化 `logLevel`（`:39-40`）。`reset()`（`:70-72`）在 `lib/` 與 `test/` 都查不到呼叫點（`devtools.md` §1.1 已列）。

### 1.4 路由保護
`devtools.md` §1.1 說三個路由無條件註冊。補充精確位置：路徑常數 `lib/ui/router.dart:54-56`、路由名常數 `:87-89`、註冊在 `lib/ui/router.dart:246-263`（`developer` 底下巢狀 `database` 與 `logs`）。**無 `redirect` 或 `canActivate` 之類的守衛**。

---

## 2. Debug 頁（`DeveloperOptionsPage`）逐區塊

`devtools.md` §1.2 已有逐區塊表；此處只補它沒點到的實作細節。

### 2.1 頁面骨架
三個 `_SettingsSection`：除錯工具（`:37-57`）、資料管理（`:60-63`）、資訊（`:66-79`），區塊間 `Divider()`。

### 2.2 記憶體使用（`_MemoryInfoTile`，`:168-474`）
- 讀的 provider（全為 `ref.read`，非 watch）：`queueProvider`（`:209`）、`rankingCacheServiceProvider`（`:210`）、`lyricsCacheServiceProvider`（`:224`）。
- 磁碟圖片快取走靜態方法 `NetworkImageCacheService.getCacheSizeMB()`（`:197`）與常數 `NetworkImageCacheService.maxCacheSizeMB`（`:198`）。
- 進程 RSS 只在 Android/Windows/Linux 取（`Platform.isAndroid || Platform.isWindows || Platform.isLinux`，`:202`）——這是 UI 層的平台判斷（未來 `fmp_platform_checks` lint 的對象，ADR 0015）。
- 「Native 記憶體」= `RSS − Flutter 圖片快取 bytes`，clamp 到 `[0, RSS]`（`:358-363`），是粗估不是量測。
- **清除按鈕只清 Flutter 記憶體**：`PaintingBinding.instance.imageCache.clear()` + `clearLiveImages()`（`:266-274`），**不動**磁碟快取、不動歌詞快取。
- 摘要行寫死簡中 `'Flutter 图片: '`（`:307`），未走 i18n（`devtools.md` §5 第 13 點已列）。

### 2.3 日誌級別（`_LogLevelTile`，`:597-627`）
`DropdownButton<LogLevel>` 列出 `LogLevel.values`（DEBUG/INFO/WARNING/ERROR），`onChanged` 呼叫 `ref.read(developerOptionsProvider.notifier).setLogLevel(next)`。**它只影響之後產生的 log（含落盤）**，重啟回復 `AppLogger.minLevel`（`devtools.md` §1.2 已列）。

### 2.4 資料庫檢視器（`DatabaseViewerPage`）
- 頁面：`lib/ui/pages/settings/database_viewer_page.dart:14`；collection 選擇器 `_buildCollectionSelector()`（`:50`）為頂部 chip 列；清單 `_DatabaseCollectionListView`（`:115`），`collection.query(isar)`（`:127`）一次 `findAll()`；每筆一張 `_DataCard`（`:192`）。
- 清單來源 `lib/data/database/database_catalog.dart`，共 **11 個 collection**，全部 `findAll()`：Track（`:53`）、Playlist（`:61`）、PlayQueue（`:69`）、PlayHistory（`:77`，`sortByPlayedAtDesc()`）、Settings（`:86`）、SearchHistory（`:95`，`sortByTimestampDesc()`）、DownloadTask（`:103`）、RadioStation（`:111`）、LyricsMatch（`:119`）、LyricsTitleParseCache（`:127`）、Account（`:135`）。
- **唯讀**：`FmpDatabaseCollection` 只宣告 `query`／`title`／`subtitle`／`sections`（`database_catalog.dart:9-29`），沒有任何寫入函式；頁面無搜尋、無分頁、無編輯（`devtools.md` §1.2 已列）。

### 2.5 重設資料（`_ResetDataTile`，`developer_options_page.dart:511-567`）
確認對話框（`showConfirmDestructiveDialog`）→ `DataIntegrityRepository(isar).clearEverything()`（`:551`，即 `_isar.clear()`，`data_integrity_repository.dart:55-57`）→ `runDatabaseMigration(isar)`（`:554`）。範圍限制見 `devtools.md` §1.2／§5 第 3 點。

### 2.6 資訊區塊的「除錯模式」
恆真裝飾列（`:69-77`），`devtools.md` §1.2 已列。

---

## 3. Log 檢視頁（`LogViewerPage`）——補 `devtools.md` §3.4

`devtools.md` §3.4 已列筆數上限與篩選；補精確行為：

| 行為 | 實作 | 檔案:行號 |
|---|---|---|
| 初始載入 | `_logs = List.from(AppLogger.logs)`（複製 500 筆記憶體緩衝） | `log_viewer_page.dart:34` |
| 訂閱即時 | `AppLogger.logStream.listen`，超過 1000 筆 `removeAt(0)` | `:35-46`（上限 `:39`） |
| 顯示篩選 | 級別門檻用 `log.level.index < _filterLevel.index` 過濾，再比對 `message`／`tag` 的小寫子字串 | `:68-80` |
| 篩選選單 | `PopupMenuButton<LogLevel>`，四項 | `:199-219`（其中 `'Info+'` `:209`、`'Warning+'` 寫死英文） |
| 複製全部 | 只複製**已篩選**的 `_filteredLogs` | `:91-95` |
| 匯出落盤檔 | `AppLogger.fileSink.readAll()`（輪替檔由舊到新串接）；Android 選目錄、其餘平台 `FilePicker.saveFile`；檔名 `fmp_log_<ISO8601去冒號>.log` | `:102-148` |
| 清空 | `_logs.clear()` + `AppLogger.clearLogs()`，**不動落盤檔** | `:150-155` |
| 單筆詳情 | 僅對 `hasError` 的列可點（`:291`）；對話框顯示時間/級別/tag/message/error/stackTrace，可複製 | `:345-415` |

- 沒有系統分享（`share_plus` 未在 pubspec）。匯出只有「存檔」。
- 「顯示篩選」與「開發者選項的記錄門檻」是兩個不同的級別設定（`devtools.md` §3.4 已列）。

---

## 4. Log 寫檔（位置／輪替／保留／格式）與 ADR 0011 的差異

現況（`devtools.md` §3 已描述一部分，此處補差異）：

| 項目 | 現況（含出處） | ADR 0011 定案 | 差異 |
|---|---|---|---|
| 記憶體歷史 | 500 筆（`lib/core/logger.dart:71-72`），`Queue` + `removeFirst`（`:262-264`） | 最近 1,000 筆 | **不同** |
| 落盤檔案 | 單檔 2MB、保留 3 個（`lib/core/log_file_sink.dart:18-19`、`_rotate()` `:90-105`） | 單檔 2MB、保留 3 個 | 相同 |
| 落盤位置 | `getApplicationDocumentsDirectory()/FMP/logs/fmp.log`（`log_file_sink.dart:24-28`） | ADR 0009 資料目錄的 `logs/` | 概念相同 |
| 落盤啟用 | `main()` 在 binding 初始化後 `attachFileSink`，**所有 build 都掛**（`lib/main.dart:135-138`，`attachFileSink` 在 `:136`；`logger.dart:163-170`） | release 寫 info 以上 | 概念相同（層級決定內容） |
| release 預設級別 | `kDebugMode ? debug : info`（`logger.dart:68`） | release 預設 `info`，開發者模式可調 `debug` | 相同 |
| console 輸出 | **不分 build 一律 `debugPrint`**（`logger.dart:272,283`），debug 另加 `developer.log`（`:283-290` 前） | console 只在 debug build | **不同**（`devtools.md` §5 第 12 點已列） |
| 遮蔽範圍 | 訊息與 error 字串遮蔽（`logger.dart:177-200` 的 `redactSensitive`；`_log` 呼叫點 `:227-238`）；**stackTrace 不遮蔽**（`:256`、`:285-289`） | 遮蔽套用在訊息、error、**stackTrace**、結構化欄位 | **不同**（`devtools.md` §3.3 已列） |
| 保留期限 | **沒有**「保留 N 天」的概念，只有「保留 3 個檔」 | ADR 0011 未寫保留期限；`phase2-plan` 要求「加輪替與保留期限」 | **保留期限是新增要求** |
| 日誌套件 | 自製 `AppLogger` 靜態類別（`logger.dart:67`），**未使用 `talker`**（pubspec 無 talker；`grep talker pubspec.yaml` 無結果） | 採用 `talker` 作資料核心 | **不同**（新專案才引入） |
| 格式 | 每筆 `toFileLine()`：`[LEVEL] [tag] message` + 換行縮排的 `Error:`／`StackTrace:` | 門面參數含結構化欄位 | 結構化欄位是新增 |

其他事實：
- 遮蔽不涵蓋 CDN 簽名 URL（`devtools.md` §3.3 已列）；AI 歌詞比對在 debug 級別會把整個請求 payload 寫進 log（`lib/services/lyrics/ai_title_parser.dart:57`、`ai_lyrics_selector.dart:116`）。
- 落盤 I/O 失敗全部吞掉，`write()` 不等待也不拋（`log_file_sink.dart:6-13,71-74`）。

---

## 5. `DataIntegrityRepository.scan/repair`

`devtools.md` §1.2 註腳只提到「`lib/` 查不到呼叫點，只有測試用」。補它的實際行為：

- 檔案：`lib/data/repositories/data_integrity_repository.dart`。
- `scan()`（`:59-79`）回 `DataIntegrityReport`（`:9-27`），檢查四件事：
  1. 重複的 Track `uniqueKey`（`:66`）；
  2. 重複的 DownloadTask `savePath`（僅非空的，`:67-72`）；
  3. 重複的 Account `platform`（`:73-76`）；
  4. PlayQueue 筆數 > 1（`:77`，`hasIssues` 的判準在 `:22-27`）。
- `repair()`（`:81-162`）在單一 `writeTxn` 內修復：Track 群組保留「完整度分數」最高者（`_preferTrack`／`_trackCompletenessScore`，`:323-342`），合併 metadata（`_mergeTrackMetadata`，`:229-265`），並 remap 其他表的參考（`_remapTrackReferences`，`:164-180`：改寫 DownloadTask `trackId`、PlayQueue `trackIds`／`originalOrder`／`currentIndex`）；DownloadTask 保留狀態分數最高者（`:344-364`）；Account 保留已登入／較新者（`:366-375`）；PlayQueue 只留一個（`:377-387`）。
- **呼叫點**：`clearEverything()` 被 `developer_options_page.dart:551` 呼叫；`scan()`／`repair()` 在 `lib/` **零呼叫點**，只有 `test/data/repositories/data_integrity_repository_test.dart`（`:29,59,66,69,70,119,146,171,188,205,229,247`）使用。grep 佐證：`grep -rn "DataIntegrityRepository|\.scan()|\.repair()" lib/ test/`。

---

## 6. 現有的網路請求記錄機制

**查不到任何 App 內請求記錄機制。** 逐條：

- `lib/` 內無 `LogInterceptor`、無 `PrettyDioLogger`、無請求歷史／環形緩衝（grep `LogInterceptor`、`requestLog|networkLog|httpHistory|requestHistory` 皆 0 命中）。
- dio 實例統一由 `HttpClientFactory.create`（`lib/core/utils/http_client_factory.dart:32`）建立，只設 headers / timeouts / content type，**沒有攔截器**。
- 既有攔截器只有三個帳號認證用：`BilibiliAuthInterceptor`（`lib/services/account/bilibili_auth_interceptor.dart:17`）、`NeteaseAuthInterceptor`（`netease_auth_interceptor.dart:12`）、`YouTubeAuthInterceptor`（`youtube_auth_interceptor.dart:11`）；它們只做 cookie 注入與認證錯誤重試（例如 bilibili 的 `-101/-111`，見該檔 dartdoc `:9-14`），**不是記錄器**。
- 唯一能看到實際 HTTP 流量的是 **VM Service**：`ext.dart.io.httpEnableTimelineLogging` + `getHttpProfile`（`docs/development.md` §執行期除錯）。該節並註明「FMP 的 Dio 沒有自訂 `httpClientAdapter`，走的是 `dart:io HttpClient`，三個音源與圖片 CDN 都攔得到」。
- ADR 0011 已定新專案要「自己的 dio 攔截器，每請求一筆摘要（方法、主機、路徑、遮過的 query、狀態、耗時、大小、音源、錯誤類型），經門面寫入；不記 body」。**這是新功能，現況沒有。**

---

## 7. 播放狀態觀察工具

**沒有專用除錯 UI。** 事實：

- 唯一狀態源：`audioControllerProvider = NotifierProvider<AudioController, PlayerState>`（`lib/providers/audio/audio_controller_provider.dart:91`）。
- `PlayerState`（`lib/services/audio/player_state.dart:12-60`）欄位：`isPlaying`、`isBuffering`、`isLoading`、`processingState`、`position`、`duration`、`bufferedPosition`、`speed`、`volume`、`playingTrack`、`error`（String）、`retryAttempt`、`isNetworkError`、`isRetrying`、`nextRetryAt`、`currentBitrate`、`currentContainer`、`currentCodec`、`currentStreamType`、`audioDevices`、`currentAudioDevice`。
- selector 位於 `lib/providers/audio/audio_player_selectors.dart`：`playbackSpeedProvider`（`:119`）、`desktopAudioDeviceStateProvider`（`:123`）、`currentStreamMetadataProvider`（`:136`）、`currentTrackProvider`（`:169`）、`queueProvider`（`:174`）、`upcomingTracksProvider`（`:179`）、`queueControlStateProvider`（`:184`）。
- 這些 selector 的消費者是 **播放 UI**，不是除錯頁：`lib/ui/pages/player/player_page.dart:171,819`、`lib/ui/widgets/panels/track_detail_panel.dart:753`、`lib/ui/widgets/player/mini_player_desktop_controls.dart:28`、`lib/ui/pages/radio/radio_player_page.dart:41`。
- 「佇列即時狀態」目前只在 Debug 頁的記憶體磚顯示「佇列曲數」（`developer_options_page.dart:384-389`），沒有更多。
- 執行期讀活物件只有 VM Service 的 `getClassList → getInstances → getObject`（`docs/development.md` §執行期除錯，含 `evaluate` 不通的地雷）。
- ADR 0018 已定新專案的狀態是 sealed（`Idle`/`Loading`/`Playing`/`Paused`/`Buffering`/`Retrying`/`Failed(AppError)`）+ 高頻位置走獨立 stream。**與現況的單一 `PlayerState` 不同。**

---

## 8. 快取清除入口

現況**沒有單一「清除所有快取」入口**，散在三處（皆各自為政）：

| 入口 | 位置 | 實際清除什麼 |
|---|---|---|
| 設定頁「圖片快取」對話框的「清除」 | `lib/ui/pages/settings/widgets/settings_cache.dart`（`_ImageCacheSizeListTile` 的 `_showImageCacheDialog`） | `ImageLoadingService.clearNetworkCache()` → `NetworkImageCacheService.clearCache()`（`lib/core/services/image_loading_service.dart:41-47`、`network_image_cache_service.dart:262`）。**不清** Flutter 記憶體 `ImageCache` |
| 設定頁「歌詞快取」對話框的「清除」 | 同檔（`_LyricsCacheSizeListTile`） | `lyricsCacheServiceProvider` 的 `cache.clear()` |
| 開發者選項頁記憶體磚的「清除圖片記憶體快取」 | `developer_options_page.dart:410-417`、`:266-274` | 只清 `PaintingBinding.instance.imageCache`（記憶體） |
| 設定頁「下載管理」的「清除已完成／清除佇列」 | `lib/ui/pages/settings/download_manager_page.dart:37-49` | `downloadService.clearCompleted()` / `clearQueue()`，與快取無關 |

- 設定頁的「快取」區塊在 `lib/ui/pages/settings/settings_page.dart:118-127`，同一區塊還有排行榜／電台刷新間隔。
- **串流網址快取**：舊版把串流網址存進 Isar（`docs/audit`／ADR 0016 背景已述），因此**沒有**「清除串流快取」的入口。
- ADR 0016 已定新專案要「一個統一快取庫、一個總上限、設定頁顯示各類用量與一個清除快取（含 Flutter 記憶體 `ImageCache`）」。**現況與此差距大。**

---

## 9. 診斷包

**查不到任何診斷包實作。** `grep -rni "diagnostic|診斷包|診斷" lib/` 只命中 `lib/core/errors/user_message.dart` 的「診斷（diagnostic）」字樣（`:11-13,25,42-43,78,116-120`），那是錯誤訊息措辭，不是診斷包。ADR 0011 §6 已定新專案的診斷包欄位（參考 NewPipe）。

---

## 10. VM Service 除錯做法（`docs/development.md` §執行期除錯）

摘要（細節見該節原文）：
- 只在 debug / profile build 可用；Isar 的 `ext.isar.*` 只在 debug（`Isar.open` 的 `inspector` 在 profile / release 被 tree shake）。
- 取 BASE：`flutter run` 印出的 VM Service URL 去掉結尾 `/`；**token 是本機除錯憑證，不貼進 issue／PR／log／報告**；`getVM` 取 isolate id。
- HTTP：先 `httpEnableTimelineLogging` 再產生流量（只記開啟之後的請求；啟動那幾秒量不到），再 `getHttpProfile` / `getHttpProfileRequest` / `clearHttpProfile`。回應含簽名串流 URL 與 Cookie，不可外流。
- 讀活物件：`evaluate` 不通（`No compilation service available`），改用 `getClassList → getInstances → getObject`。
- Isar：參數全包在 `args` JSON 字串；`editProperty` 路徑用 `.` 分段（清單索引寫數字段）；`Settings.youtubeStreamPriority` 是 `@Deprecated` v1 欄位；寫入會與 App 自己的寫入者搶（`QueueManager` 每 10 秒存回整份 `PlayQueue`）。
- 其他 RPC：`listInstances`、`getSchema`、`exportJson`、`importJson`；記憶體／timeline／widget tree dump 見 Dart VM Service Protocol。

---

## 11. 其他與 Debug 頁相關的既有事實

- **Toast**：全 app 單一 `ToastService`（靜態 + Stream 兩套入口），`devtools.md` §2 已詳列；ADR 0023 已定要換成單一 `Toaster`，並讓 Debug 頁的錯誤歷史共用錯誤詳細頁。
- **錯誤歷史**：現況沒有「錯誤歷史」概念，只有 log 篩選；ADR 0011 §5 說錯誤歷史 = Debug 頁的 log 篩選。
- **遮蔽函式**：現況是 `AppLogger.redactSensitive`（單一處，`logger.dart:177`），但只涵蓋訊息與 error 字串；ADR 0011 §3 要求單一遮蔽函式涵蓋 stackTrace、CDN 簽名 URL、已知憑證值。
- **音源健康檢查**：`grep -rni "healthCheck|health_check|健康檢查|sourceHealth" lib/` **0 命中**——現況沒有。ADR 0015 §4 已定「檢查案例一份四用」，健康檢查是真實連線、App 內、手動執行。
- **插件開發工具**：現況沒有插件系統（ADR 0014 的 script source plugins 是新專案設計）；`grep -rni "plugin" lib/ --include=*.dart` 只有 3 命中（`core/secure_key_value_store.dart:65-66` 的 `MissingPluginException`、`services/audio/audio_service.dart:10` 的註釋），都與 debug 頁無關。
- **i18n**：`devtools.md` §5 第 13 點已列三處寫死字串（`developer_options_page.dart:307`、`log_viewer_page.dart:208-212`）。
