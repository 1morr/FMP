# Research: 快取與離線行為 —— 舊代碼庫（lib/）現況基線

- **驗證日期**：2026-09-27
- **方法**：先讀 `docs/audit/{data,playback,sources,perf-baseline,features,platforms,questions}.md` 找線索，
  再逐一開對應的 `lib/` 原始碼重新核對；審計文件的結論一律視為「待驗證假設」，
  本文件只記錄本次親自讀過原始碼後確認的事實。凡未能在原始碼中核對到的項目，
  明確標註「查不到」並說明已嘗試的搜尋方式；純推論未見直接程式碼佐證的，
  標註「推測」。所有結論括號內為 `檔案路徑:行號`（相對 repo 根目錄）。
- **範圍**：只描述 `lib/` 現況，不做設計建議或評論（含 B12 相關的排行榜背景刷新
  行為，只如實記錄現況）。

---

## 1. 圖片快取

**套件與分層**：`cached_network_image: ^4.0.0` + `flutter_cache_manager: ^3.4.2`
(`pubspec.yaml:52-53`)。圖片快取實際上有三層，彼此獨立、由不同機制管理：

1. **Flutter 內建記憶體快取**（`PaintingBinding.instance.imageCache`）：
   App 啟動時依平台寫死大小，Android/iOS 100 張 / 50MB，桌面 200 張 / 80MB
   (`lib/main.dart:156-164`)。**不可由使用者調整**，也不受設定頁「圖片快取
   大小」影響。
2. **`flutter_cache_manager` 磁碟快取**（`NetworkImageCacheService`
   /`_FmpImageCacheManager`，`lib/core/services/network_image_cache_service.dart`）：
   快取目錄為 `getTemporaryDirectory()/fmp_network_image_cache`
   (`network_image_cache_service.dart:282-284`)；固定 `stalePeriod` 7 天
   (`_stalePeriodDays = 7`, `network_image_cache_service.dart:127`)，**不可
   由使用者調整**；`maxNrOfCacheObjects` 由目前大小上限除以 100KB 估算，
   clamp 在 100–3000 個 (`network_image_cache_service.dart:131-132`)。
3. **`ResizeImage` 解碼快取**：主顯示路徑用 `memCacheHeight` 限制解碼後圖片
   佔用的記憶體，磁碟不做二次縮放（`image_loading_service.dart:614-624,
   646-660`，comment 明確說明是刻意避免 flutter_cache_manager 同時存原圖與
   縮放副本造成雙倍磁碟佔用）。

**使用者可調的「圖片快取大小」設定**：`Settings.maxCacheSizeMB`
(`lib/data/models/settings.dart:247`，欄位預設 32)，UI 在
`settings_cache.dart:4-127`，選項為 16/32/48/64 MB
(`settings_cache.dart:62`)，最小值 16MB (`download_settings_provider.dart:102`)。
此設定**只影響第 2 層（flutter_cache_manager 磁碟快取的檔案數估算與手動
trim 上限）**，不影響第 1 層記憶體快取、也不影響第 2 層的 7 天有效期：
- 設定變更會呼叫 `NetworkImageCacheService.setMaxCacheSizeMB(value)`
  （重建 CacheManager）與 `trimCacheIfNeeded(value)`（依修改時間刪最舊檔案
  至符合上限）(`download_settings_provider.dart:100-113`)。
- App 啟動時也會同步一次並做初始 trim + 估算初始化
  (`download_settings_provider.dart:69-77`)。
- 另外還有「載入 30 張圖後檢查一次」與「估算值達 90% 上限時立即清理」的
  背景 trim 機制 (`network_image_cache_service.dart:142-158, 190-219`)。

**平台差異**：
- 磁碟快取預設上限：Android/iOS 16MB，桌面 32MB
  (`network_image_cache_service.dart:135-140`)。
- 全新安裝走 `createBootstrapSettings()`：行動裝置強制設 16MB，桌面沿用
  `Settings()` 預設 32MB (`lib/data/database/database_migration.dart:106-112`)。
- 資料完整性修復邏輯 `fix(settings.maxCacheSizeMB < 1, () => ... = 32)`
  **不分平台**、壞值一律修回 32MB (`database_migration.dart:265`)——與
  行動裝置預設 16MB 不一致，是純資料修復用途，非平台感知。
- 記憶體快取（第 1 層）：行動 100 張/50MB、桌面 200 張/80MB
  (`main.dart:156-164`)。

**誰清除、如何清除**：
- 使用者在設定頁「清除圖片快取」只清第 2 層（`ImageLoadingService
  .clearNetworkCache()` → `NetworkImageCacheService.clearCache()`：
  呼叫 `cacheManager.emptyCache()` 後再手動刪目錄檔案、重建 CacheManager
  (`network_image_cache_service.dart:262-279`) )(`settings_cache.dart:103-113`)。
  **不會清除第 1 層記憶體快取**。
- 第 1 層記憶體快取只能在「開發者選項」頁用
  `PaintingBinding.instance.imageCache.clear()` +
  `clearLiveImages()` 清除，一般使用者看不到這個入口
  (`lib/ui/pages/settings/developer_options_page.dart:266-274`)。

**Cache Key**：磁碟快取 key 為 `'fmp_s${cacheExtent}_$url'`
(`image_loading_service.dart:315-317, 378-383`)，`cacheExtent` 依顯示尺寸
與 DPR（量化到 0.5）計算，同一張圖不同顯示尺寸會產生不同快取條目
(`image_loading_service.dart:340-341, 368-373`)。

**請求標頭**：圖片 CDN 請求預設**不帶 User-Agent**（
`SourceHttpPolicy.imageHeadersForUrl` 預設 `includeUserAgent: false`），
只帶對應音源的 Referer/Origin；下載管線與 `imageHeaders()` 預設才帶
`mediaUserAgent` (`image_loading_service.dart:319-331`,
`source_http_policy.dart:96-119`)。

---

## 2. 串流 URL 快取

**Isar 持久化欄位**：`Track.audioUrl` (String?) 與 `Track.audioUrlExpiry`
(DateTime?) (`lib/data/models/track.dart:68,71`)。有效性判斷：
`hasValidAudioUrl` —— `audioUrl` 為 null 則無效；有 `audioUrlExpiry` 時要求
`now` 早於 `expiry - 5 分鐘安全邊界`（`audioUrlRefreshMargin`）
(`track.dart:280-293`)。

**行程內（記憶體）解析快取**：`DefaultStreamResolutionService._resolvedStreams`
是一個 `Map<String, _ResolvedStream>`，key 為
`'${track.uniqueKey}|${track.pageNum ?? ''}'`
(`lib/services/audio/stream_resolution_service.dart:109, 335-341`)，上限 32
筆、超過時以插入順序（近似 LRU）淘汰最舊者
(`stream_resolution_service.dart:111-113, 382-384`)。**這個快取只存在於
當前執行的 process，App 重啟後為空**（註解明確說明：`stream_resolution_
service.dart:103-108`）。

**播放路徑會不會重用 Isar 上已持久化但仍有效的 `audioUrl`？** 不會直接重用。
`resolvePrimary()`（播放用途）呼叫 `_reusableResolution()`，此函式**必須**
在 `_resolvedStreams`（行程內記憶體快取）命中才會回傳非 null
(`stream_resolution_service.dart:348-368`；第 355 行 `_resolvedStreams
.remove(key)` 為 null 就直接放棄，不會退回去看 `track.audioUrl` 是否仍
`hasValidAudioUrl`)。也就是說：**App 重啟後第一次播放同一首歌，即使 Isar
裡的 `audioUrlExpiry` 還沒過期，仍會重新打網路解析**——`Track.audioUrl`/
`audioUrlExpiry` 持久化的實際作用範圍**只在同一個 process 內的短路徑判斷**
（例如 UI 顯示、`hasValidAudioUrl` 供 `prefetchTrack` 判斷是否需要預取，見
下方 bug）。

**已確認的行為/落差（非推測，有程式碼與呼叫鏈佐證）——預取（prefetch）
可能因為 Isar 殘留的「有效」`audioUrl` 而失效**：
1. `PlaybackRequestSession._prefetchNextIfRequested` 在每次成功開始播放後，
   對佇列下一首呼叫 `_audioStreamManager.prefetchTrack(nextTrack)`
   (`lib/services/audio/playback_request_session.dart:813-826`)。
2. `prefetchTrack()` 開頭檢查：若 `track.hasValidAudioUrl` 為 true 就直接
   return，不做任何解析 (`stream_resolution_service.dart:299-304`)。
3. 若下一首曲目是從 Isar 讀出、帶著上一個 process 留下的、尚未過期的
   `audioUrl`/`audioUrlExpiry`（例如佇列裡排在後面、幾分鐘前才被
   `_applyStreamResult` 寫入資料庫的曲目 (`stream_resolution_service.dart:
   420-480`)），這次 `hasValidAudioUrl` 會是 true，於是 `prefetchTrack`
   直接跳過，**不會**把結果寫進 `_resolvedStreams`。
4. 真正要切到這首歌時，`_armNextMedia` 呼叫
   `_audioStreamManager.selectPlayback(nextTrack, persist: false)`
   (`lib/services/audio/audio_provider.dart:1663-1677`)，其註解明確寫
   「命中預取留下的行程內快取時不會再打網路」(`audio_provider.dart:
   1671-1673`)——但因為第 3 步 `prefetchTrack` 提早退出，`_resolvedStreams`
   裡根本沒有這個 key，`_reusableResolution` 會 cache miss，於是仍然要在
   `_armNextMedia` 當下同步打一次網路解析。
   **淨效果**：預取機制原本要提前把下一首解析好、讓切歌時零延遲，但只要
   佇列裡的下一首曲目在 Isar 中殘留一個「還沒過期」的 `audioUrl`，這次
   prefetch 就會被跳過，切歌當下退化成同步網路解析（不是播放失敗，是
   多了一次原本該提前做完的等待）。

**每個音源的過期時間來源與寫死值**：
- **Bilibili**：優先從 URL 的 `deadline`（unix 秒）query 參數反推實際過期時間
  (`lib/data/sources/bilibili_source.dart:428-438`，註解量到約 7178 秒
  ≈ 1.99 小時，非常接近寫死的 2 小時)；已過期則回傳 `Duration.zero`
  強制立即視為需要重新解析；拿不到 `deadline` 才退回常數
  `AppConstants.bilibiliAudioUrlExpiryHours = 2` 小時
  (`lib/core/constants/app_constants.dart:26`,
  `bilibili_source.dart:373-379, 417-423`)。
- **YouTube**：**固定寫死** 1 小時 (`_audioUrlExpiry = Duration(hours:
  AppConstants.youtubeAudioUrlExpiryHours)`，`youtubeAudioUrlExpiryHours = 1`
  於 `app_constants.dart:29`；套用處見 `lib/data/sources/youtube_source.dart:
  52-54` 及多處 `expiry: _audioUrlExpiry`，如行 470/518/567/738/784/831/
  1970/2005/2020)。**不會**依實際簽名 URL 內容反推真實到期時間。
- **NetEase**：優先用 API 回報的 `expi`（秒）；`expi` 為 null 或 ≤0 時退回
  常數 `_fallbackAudioUrlExpiry = Duration(minutes: 16)`
  (`lib/data/sources/netease_source.dart:41, 152-163`)。

**清除/失效機制**：沒有「清除串流 URL 快取」的使用者入口；唯一的主動失效點
是 `invalidateStream(track)`——從 `_resolvedStreams` 移除該 key，供播放失敗
時呼叫，避免同一個壞 URL 被無限次重複交還
(`stream_resolution_service.dart:328-333`)。`Track.audioUrl` 欄位本身不會被
主動清空，只會在下一次成功解析時被新值覆蓋
(`stream_resolution_service.dart:427-428, 462-474`)。

**下載請求刻意不重用快取**：`purpose == StreamResolutionPurpose.download`
時強制 `reusable = null`，一定重新打一次解析，理由是下載耗時可能超過 5
分鐘安全邊界，寧可多付一次解析成本也不要让整個檔案因 URL 中途失效而報廢
(`stream_resolution_service.dart:147-152`)。

---

## 3. 歌詞快取

**實作**：`LyricsCacheService` (`lib/services/lyrics/lyrics_cache_service.dart`)。
- 儲存位置：`getApplicationCacheDirectory()/lyrics/`
  (`lyrics_cache_service.dart:63-64`)，每首歌一個 JSON 檔，檔名為
  `base64Url(trackUniqueKey) + '.json'` (`lyrics_cache_service.dart:268-271`)。
- 另有 `_metadata.json` 記錄每個 key 的最後存取時間，用於 LRU 淘汰，寫入採
  2 秒防抖 (`lyrics_cache_service.dart:33-39, 311-320`)。
- 雙重上限：檔案數（使用者可調，見下）與**固定** 5MB 總大小上限
  (`maxCacheSizeBytes = 5 * 1024 * 1024`，`lyrics_cache_service.dart:19`，
  此值**不可由使用者調整**)。任何一項超過就以 LRU 逐一淘汰最舊檔案，直到
  兩項都在限制內 (`lyrics_cache_service.dart:203-239`)。

**使用者可調的「歌詞快取」設定**：`Settings.maxLyricsCacheFiles`
(`lib/data/models/settings.dart:350`，預設 50 =
`LyricsCacheService.defaultMaxCacheFiles`)，UI 選項 10/30/50/100/200
(`settings_cache.dart:171`)，最小值 10
(`download_settings_provider.dart:118`)。變更會呼叫
`LyricsCacheService.setMaxCacheFiles(value)`，若目前快取超過新上限會立即
觸發清理 (`lyrics_cache_service.dart:25-31`, `download_settings_provider.dart:
115-126`)。此設定**只控制檔案數上限**，不影響固定的 5MB 大小上限，也
不影響 LRU 的存取時間判斷邏輯本身。

**清除**：設定頁「清除歌詞快取」直接呼叫 `LyricsCacheService.clear()`——
整個刪除 `lyrics/` 目錄再重建，`_accessTimes` 清空
(`lyrics_cache_service.dart:141-158`, `settings_cache.dart:215-226`)。

**平台差異**：查不到——`LyricsCacheService` 沒有任何 `Platform.isX` 分支，
`getApplicationCacheDirectory()` 由 `path_provider` 依平台解析實際路徑，
但快取邏輯（上限、LRU、清除）本身對 Android/Windows 一致。

---

## 4. 排行/首頁快取（Ranking / Home)

**實作**：`RankingCacheService` (`lib/services/cache/ranking_cache_service.dart`)，
是純記憶體狀態（`Map<String, List<Track>>`），**不持久化到 Isar 或磁碟**
(`ranking_cache_service.dart:24-108`；App 重啟後榜單資料需要重新抓取，
本文件未找到任何寫入 Isar/檔案的程式碼路徑，搜尋方式：在
`ranking_cache_service.dart` 全文與 `grep -r "RankingCacheService"` 均未見
持久化呼叫)。

**刷新策略**：
- App 啟動時立即抓一次，有 5 秒初始逾時保護
  (`_defaultInitialLoadTimeout`, `ranking_cache_service.dart:117, 178-199`)。
- 定時背景刷新，預設間隔 1 小時，可由使用者在設定頁調整為
  30/60/120/240 分鐘 (`Settings.rankingRefreshIntervalMinutes` 預設 60，
  `lib/data/models/settings.dart:434`；UI `settings_cache.dart:245-306`)。
- 單一音源刷新失敗時走退避重試（5s/30s/2min/10min），非等到下一次整點刷新
  (`ranking_cache_service.dart:117-129, 297-311`)。
- 監聽 `ConnectivityNotifier.onNetworkRecovered`，網路恢復時立即重新整個
  刷新一輪 (`ranking_cache_service.dart:149, 217-230`)。

**是否會抓「已停用顯示」的音源（現況，對應 B12 的現況描述，不含任何設計
評論）**：`RankingCacheService.bindSources()` 用
`manager.registeredSourceTypes`（`SourceManager` 註冊過的所有音源）建立要
刷新的榜單清單 (`ranking_cache_service.dart:158-172`)，**與**首頁顯示用的
`homeRankingSettingsProvider.disabledSources`（使用者在「首頁熱門來源」設定
頁勾掉的音源，`lib/providers/settings/home_ranking_settings_provider.dart:
11-38, 107-170`）**完全是兩條互不相干的資料**：`registeredSourceTypes`
只反映音源是否被 `SourceManager` 註冊（見 `lib/data/sources/source_provider.
dart:20`），不受「首頁熱門來源」開關影響。因此目前程式碼行為是：使用者在
首頁設定頁停用某音源的排行顯示後，`RankingCacheService` 仍會照
`rankingRefreshIntervalMinutes` 的間隔在背景持續抓該音源的榜單資料，只是
首頁 UI 不顯示（UI 端用 `enabledHomeRankingSourceOrderProvider` 過濾，
`home_ranking_settings_provider.dart:193-195`，本次未展開讀取 UI 消費端，
以 `docs/audit/features.md` 對此點的描述與本次核對的 `bindSources` 邏輯
互相印證，判定一致）。

---

## 5. 電台快取

**沒有獨立的「電台快取」機制/檔案**。搜尋方式：
1. 全域搜尋 `RadioCacheService` 類別與 `radio.*cache`/`radio.*Cache` 樣式的
   檔名或類別名，均無結果。
2. 讀了唯一相關服務 `RadioRefreshService`
   (`lib/services/radio/radio_refresh_service.dart`)，其角色是**直播狀態
   輪詢**，不是內容快取：
   - `_liveStatus`（`Map<int, bool>`）只存在記憶體，記錄各電台目前是否在
     直播 (`radio_refresh_service.dart:66, 79-80`)，**不持久化**。
   - 電台的封面/標題/主播名若有變化，會回寫進 Isar 的 `RadioStation` 實體
     本身（`repository.save(station)`，`radio_refresh_service.dart:195-215`），
     這是電台元資料的**目前值**，不是另一份「快取」副本。
   - 刷新間隔可調（0=關閉、1/3/5/10 分鐘，`RadioRefreshService.offMinutes`
     常數與 UI 選項，`settings_cache.dart:308-370`），預設 5 分鐘
     (`radio_refresh_service.dart:34`)。
   - 有風控退避（連續被限流時間隔倍增，上限 30 分鐘，
     `radio_refresh_service.dart:239-250`）與 App 進背景暫停輪詢
     (`radio_refresh_service.dart:133-146`)，這兩者是流量控制，非快取策略。
   - 電台音訊串流本身走一般播放路徑，沒有另外的電台專屬串流快取層——本次
     搜尋 `lib/services/radio/` 目錄下與 `cache` 相關的字串未再找到其他
     結果。

---

## 6. 搜尋歷史

**儲存**：Isar `SearchHistory` collection (`lib/data/models/search_history.dart`)，
欄位為 `query`（`@Index()`）與 `timestamp`（`@Index()`）。透過
`SearchHistoryRepository` 存取 (`lib/data/repositories/search_history_repository.dart`)。

**上限**：`AppConstants.maxSearchHistoryCount = 100`
(`lib/core/constants/app_constants.dart:32`)，**不可由使用者調整**、沒有
對應設定頁項目。

**去重與寫入規則**：`saveQuery()` 先刪除同字串（`queryEqualTo`，精確比對）
的舊紀錄，再寫入新紀錄，最後只保留依時間排序後最新的 100 筆，多的整批刪除
(`search_history_repository.dart:38-69`)。**沒有基於時間的過期機制**，
純粹是「筆數上限 + 精確字串去重」。

**清除規則**：`clear()` 直接清空整個 collection
(`search_history_repository.dart:32-34`)；`deleteById()` 支援單筆刪除
(`search_history_repository.dart:27-29`)。UI 呼叫點未在本次範圍內展開讀取
（不影響儲存層行為的判定）。

**前綴建議查詢**：`searchByPrefix()`——查詢字串為空回最近 5 筆；非空時做
case-insensitive contains 比對，取最近 10 筆 (`search_history_repository.dart:
72-88`)，屬讀取路徑，非快取。

---

## 7. 音訊本身（播放中的暫存/快取）與下載管線的邊界

**播放時的串流緩衝——兩個後端策略完全不同，且都不是「磁碟快取」**：

- **Windows（media_kit / libmpv）**：`MediaKitAudioService._configureForAudioOnly()`
  明確設定 `cache=yes`、`cache-secs=7200`（2 小時）、`demuxer-max-bytes=24MB`、
  `demuxer-max-back-bytes=8MB`、`demuxer-readahead-secs=7200`
  (`lib/services/audio/media_kit_audio_service.dart:26-28, 189-240`)。
  註解說明目的是讓 libmpv 一次性連續下載整首歌曲，避免分段請求間 TCP
  連線閒置被 CDN（尤其 YouTube）以 `WSAECONNRESET` 切斷
  (`media_kit_audio_service.dart:195-196, 214-216`)。**這是 libmpv 內部的
  串流層記憶體緩衝**（沒有出現 `cache-dir` 或任何指向磁碟路徑的 mpv
  屬性設定，本次搜尋 `media_kit_audio_service.dart` 全文未見磁碟快取路徑
  設定），只服務「目前這首歌從頭到尾播放一次」，並非可被下一次播放或其他
  曲目重用的持久快取，App 重啟、切歌都不會保留。
- **Android（just_audio / ExoPlayer）**：`lib/services/audio/
  just_audio_service.dart` 全文搜尋 `cache`/`Cache` 字串**無結果**——沒有
  設定任何 ExoPlayer `CacheDataSource` 或自訂快取層，代表 Android 端用的是
  ExoPlayer 預設的記憶體內播放緩衝（多大、策略為何屬於 ExoPlayer 內部預設
  值，**推測**：FMP 未覆寫，故沿用套件預設，未在 FMP 程式碼中找到任何相關
  設定值可引用）。

**與下載管線（`lib/services/download/`）的邊界**：本次檢查未發現任何共用
儲存路徑或程式碼路徑上的模糊地帶：
- 下載檔案落地在使用者可設定的下載目錄（`DownloadPathUtils.getDefaultBaseDir()`，
  `lib/services/download/download_service.dart:240-243`），與圖片磁碟快取
  (`getTemporaryDirectory()`)、歌詞快取 (`getApplicationCacheDirectory()`)
  用的是不同的系統目錄類別，彼此不共用檔案或索引。
- 播放路徑對「已下載」與「串流」是硬性二選一、非快取關係：
  `resolvePrimary()` 一開始就呼叫 `_inspectLocalFiles(track)` 檢查
  `track.allDownloadPaths` 是否有實體檔案存在，若有就直接回傳
  `LocalStreamResolution`，完全跳過網路解析與上面提到的串流 URL 快取邏輯
  (`stream_resolution_service.dart:123-145, 483-`)；只有下載
  (`StreamResolutionPurpose.download`) 才會反向強制不重用任何解析快取
  (`stream_resolution_service.dart:147-152`，見第 2 節)。
- 結論：**播放緩衝（mpv 的記憶體串流快取／ExoPlayer 預設緩衝）與下載檔案
  是兩個完全獨立的機制**，找不到共用儲存、共用清理邏輯或行為交疊的證據。

---

## 8. 離線行為

**偵測機制**：`ConnectivityNotifier`
(`lib/services/network/connectivity_service.dart`)：
- **不是**用系統網路介面狀態，而是每隔固定間隔對三個公共 DNS 主機做
  `InternetAddress.lookup`：`dns.google`（Google）、`one.one.one.one`
  （Cloudflare）、`dns.alidns.com`（阿里，對中國大陸友善），任一成功即判定
  有網路 (`connectivity_service.dart:51-56, 99-116`)。
- 輪詢間隔：`AppConstants.connectivityPollingInterval = Duration(seconds:
  15)` (`lib/core/constants/app_constants.dart:154`)，套用於
  `Timer.periodic` (`connectivity_service.dart:72-76`)。**確認任務描述中
  「每 15 秒 DNS 探測」的說法屬實**。
- 單次 DNS 查詢逾時：`AppConstants.dnsTimeout = Duration(seconds: 5)`
  (`app_constants.dart:157`，套用於 `connectivity_service.dart:105-107`)。
- 狀態變化（斷網→有網）會透過 `onNetworkRecovered` 廣播事件，目前有兩個
  訂閱者：`RankingCacheService`（立即重新整輪刷新排行榜，
  `ranking_cache_service.dart:149, 217-230`）與 `audio_provider.dart:272`
  （播放側網路恢復重試邏輯，本次未展開細節）。

**各頁面離線行為**：全域搜尋 `connectivityProvider` 的消費點，全 repo 只有
4 處 (`ranking_cache_service.dart:149`、`network_status_banner.dart:25,79`、
`audio_provider.dart:272`)，**沒有找到任何頁面層級（首頁/搜尋/下載/電台）
針對離線狀態的專屬分支邏輯**。實際離線體驗目前完全由一個全域元件負責：

- **全域頂部 Banner**：`NetworkStatusBanner`
  (`lib/ui/widgets/feedback/network_status_banner.dart`)，掛在
  `AppContentWrapper`（`lib/app.dart:180-214`），對 Windows 與
  Android 都會在每一頁上方顯示，不分頁面。`resolveNetworkStatusBannerKind()`
  只有兩種非空狀態：`noNetwork`（`!isConnected`，文案 `t.networkStatus.
  noNetwork`，`network_status_banner.dart:11-20, 99-104`）與
  `playbackNetworkError`（播放中偵測到網路錯誤，額外顯示手動重試按鈕，
  `network_status_banner.dart:96-98, 143-157`）。
- **首頁 / 排行榜**：離線時不主動顯示「離線」提示，行為是「維持顯示上一次
  成功抓到的快取資料」——`RankingCacheService` 刷新失敗時
  `state.updateSource(sourceType, error: ...)` 但**不清空** `tracksBySource`
  （`ranking_cache_service.dart:259-295`，錯誤只記在 `_errorsBySource`，
  舊的 `tracks` 欄位維持不變），配合頂部全域 Banner 提示無網路。首頁本身
  是否讀取 `errorFor()` 顯示額外文案——查不到，本次未展開讀取首頁 UI
  組件（超出核心 8 類快取/離線範圍，且不影響上述 service 層行為的判定）。
- **搜尋頁**：沒有本地搜尋結果快取（見第 6 節，`SearchHistory` 只存查詢字
  串本身，不存結果），離線時搜尋請求會直接透過一般網路例外處理路徑失敗；
  未找到搜尋頁專屬的離線分支（`grep connectivityProvider` 未命中
  `search_page.dart` 或 `search_provider.dart`）。
- **播放器**：`hasPlaybackNetworkError` 只在播放過程中偵測到網路類錯誤時
  由 `audioControllerProvider` 曝光 (`network_status_banner.dart:26-28,
  73-75`)，離線時若嘗試播放**串流**曲目會經一般的串流解析失敗路徑處理
  （非本文件範圍展開的錯誤呈現細節）。
- **已下載內容離線播放**：**確認可行**。`resolvePrimary()` 對本地檔案的
  檢查發生在建構網路請求之前、且不受 `purpose` 以外任何連線狀態檢查阻擋
  (`stream_resolution_service.dart:123-145`)——只要 `track.allDownloadPaths`
  裡有檔案通過 `File(path).existsSync()`，就直接回傳 `LocalStreamResolution`
  播放本地檔案，全程不觸碰 `ConnectivityNotifier` 或任何網路呼叫。
- **下載頁**：離線時發起新下載會在下載請求本身的網路層失敗（一般
  Dio/HTTP 例外），未找到下載頁專屬的「離線」提示分支（`grep
  connectivityProvider` 未命中 `lib/services/download/` 或下載相關 UI 頁）。
- **電台頁**：`RadioRefreshService.tick()` 不檢查全域連線狀態，遇到請求失敗
  時走 `_markOffline()` 把該電台標記為未直播，屬於「請求失敗」的一般錯誤
  處理路徑，不是「偵測到離線後跳過請求」的專屬邏輯
  (`radio_refresh_service.dart:216-227, 252-257`)。

**小結（查不到的部分）**：除了上述 5 個消費點與全域 Banner，本次在
`lib/ui/pages/{home,search,download,radio}` 目錄範圍內搜尋
`connectivityProvider`／`ConnectivityNotifier`／`isConnected` 均無命中，
判定「離線時每頁的行為」目前**沒有專屬設計**，一律退化為各自原本的網路
請求失敗處理（多半是通用錯誤 Toast/重試，不是「離線」語意的空狀態），
加上全域頂部 Banner 提示。若需要更細的「失敗時實際顯示什麼 UI 文案」，
需要另外逐頁讀取（未在本次範圍內完成，屬於離線行為的呈現細節而非快取/
偵測機制本身）。

---

## 附錄：本次驗證涉及的檔案清單

- `lib/core/services/image_loading_service.dart`
- `lib/core/services/network_image_cache_service.dart`
- `lib/main.dart`（記憶體圖片快取設定）
- `lib/ui/widgets/images/{track_thumbnail,recent_play_cover_image,
  radio_cover_image,avatar_image,playlist_cover_image}.dart`
- `lib/ui/pages/settings/widgets/settings_cache.dart`
- `lib/ui/pages/settings/developer_options_page.dart`
- `lib/providers/download/download_settings_provider.dart`
- `lib/data/models/settings.dart`
- `lib/data/database/database_migration.dart`
- `lib/data/models/track.dart`
- `lib/services/audio/stream_resolution_service.dart`
- `lib/services/audio/playback_request_session.dart`
- `lib/services/audio/audio_provider.dart`（局部）
- `lib/data/sources/{bilibili_source,youtube_source,netease_source,
  source_http_policy}.dart`
- `lib/services/lyrics/lyrics_cache_service.dart`
- `lib/providers/lyrics/lyrics_provider.dart`
- `lib/services/cache/ranking_cache_service.dart`
- `lib/providers/settings/{refresh_settings_provider,
  home_ranking_settings_provider}.dart`
- `lib/services/radio/radio_refresh_service.dart`
- `lib/data/repositories/search_history_repository.dart`
- `lib/data/models/search_history.dart`
- `lib/services/network/connectivity_service.dart`
- `lib/ui/widgets/feedback/network_status_banner.dart`
- `lib/app.dart`（局部）
- `lib/services/audio/{just_audio_service,media_kit_audio_service}.dart`
- `lib/services/download/download_service.dart`（局部）
- `lib/core/constants/app_constants.dart`
- `lib/i18n/zh-TW/settings.i18n.json`（局部）
- `pubspec.yaml`
