# Image / Cache Performance Review

審查範圍：`TrackThumbnail`、`TrackCover`、`ImageLoadingService`、`ThumbnailUrlUtils`、`FileExistsCache`，以及目前等價的圖片與 cache 路徑。只審查與記錄，未修改程式碼。

## 語料與規範分層

### 規範性要求

- `AGENTS.md`：UI 不得直接使用 `Image.network()` / `Image.file()`；UI 圖片載入應走 `TrackThumbnail`、`TrackCover` 或 `ImageLoadingService`。
- `lib/ui/AGENTS.md`：歌曲封面使用 `TrackThumbnail` / `TrackCover`，頭像使用 `ImageLoadingService.loadAvatar()`，其他圖片使用 `ImageLoadingService.loadImage()`；`loadImage()` 應傳 `width` / `height` 或 `targetDisplaySize`。
- `lib/services/AGENTS.md`：`ThumbnailUrlUtils` 應依平台最佳化縮圖 URL：Bilibili width suffix、YouTube 16:9 tier、YouTube avatar `=s{size}`、Netease `?param={size}y{size}`。
- `docs/README.md` 與 `docs/development.md`：目前核心規則以 `AGENTS.md` 為權威，開發文檔只保留摘要；UI 圖片載入摘要同樣要求使用 `TrackThumbnail`、`TrackCover` 或 `ImageLoadingService`。

### 描述性內容，已用代碼驗證

- `.serena/memories/ui_coding_patterns.md`、`.serena/memories/refactoring_lessons.md`、`.serena/memories/download_system.md` 都把圖片載入、`targetDisplaySize`、`FileExistsCache` 的 watch/read 模式列為目前坑點或補充模式。這些 memory 本身不是權威規範；以下 findings 均以當前 `lib/` 與 `test/` 內容驗證。

## 快速結論

- 未在 `lib/` 找到直接 `Image.network()` / `Image.file()` 呼叫；`rg -n "Image\\.(network|file)\\(" lib test` 只命中 `lib/ui/AGENTS.md:10` 的規則文字。
- 目前 `ImageLoadingService.loadImage()` 呼叫點大多有 `width` / `height` 或 `targetDisplaySize`，且已有靜態測試覆蓋部分固定尺寸場景。
- 主要風險不在「完全沒走統一組件」，而在：本地圖片與部分 target-only 網路圖片仍可能以過大尺寸進入 Flutter image cache；另有一個預載路徑繞過統一 cache manager。

## Findings

### 1. Confirmed issue：本地圖片不使用 decode-size hint

**Evidence**

- `lib/core/services/image_loading_service.dart:65` 到 `lib/core/services/image_loading_service.dart:68`：只要 `localPath != null`，直接建立 `FileImage(file)`，沒有把 `width`、`height` 或 `targetDisplaySize` 轉成 decode 尺寸。
- `lib/core/services/image_loading_service.dart:318` 到 `lib/core/services/image_loading_service.dart:323`：本地圖片最後以一般 `Image(image: widget.image, width, height)` 顯示，`width` / `height` 只限制 layout，沒有 `cacheWidth` / `cacheHeight`。
- `lib/ui/pages/library/downloaded_page.dart:307` 到 `lib/ui/pages/library/downloaded_page.dart:312`、`lib/ui/pages/library/downloaded_category_page.dart:338` 到 `lib/ui/pages/library/downloaded_category_page.dart:343`：已下載頁與分類頁即使傳了 `targetDisplaySize`，本地 `cover.jpg` 仍會走上述 `FileImage` 路徑。

**Trigger scenario**

使用者下載或同步大量歌曲後進入已下載頁、已下載分類頁、歌單詳情頁；本地 `cover.jpg` 若是來源原圖或大尺寸圖片，列表/卡片只顯示 120-240dp，但 Flutter 可能解碼完整本地圖片。

**User impact**

外部/native image memory 可能高於預期，快速滾動含本地封面的列表時可能增加 GC、光柵化壓力與 image cache 驅逐。這會抵消 `targetDisplaySize` 在呼叫點上的意圖。

**Suggested measurement or fix**

- 先用 profile 模式測量：在已下載頁快速滾動 100+ 張本地封面，記錄 VM Service `getMemoryUsage.externalUsage`、Flutter image cache current bytes、Timeline jank。
- 修正方向：讓 `ImageLoadingService` 對本地圖片也接受有效 decode 尺寸，例如從 `width` / `height` / `targetDisplaySize` 與 DPR 計算 `cacheWidth` / `cacheHeight`，並使用可套用 resize hint 的 provider/Widget 路徑。

**Instruction docs accuracy notes**

`lib/ui/AGENTS.md` 要求傳 `width` / `height` 或 `targetDisplaySize` 以便縮圖 URL 最佳化；這對網路 URL 成立，但對本地 `FileImage` 的 decode 尺寸不成立。文檔若要精準，應區分「URL 最佳化 hint」與「本地 decode-size hint」。

### 2. Suspected issue：只有 `targetDisplaySize` 的網路圖片沒有記憶體 decode 上限

**Evidence**

- `lib/core/services/image_loading_service.dart:120` 到 `lib/core/services/image_loading_service.dart:124`：`targetDisplaySize` 會用於 `ThumbnailUrlUtils.getOptimizedUrlCandidates()`。
- `lib/core/services/image_loading_service.dart:413` 到 `lib/core/services/image_loading_service.dart:427`：`memCacheWidth` / `memCacheHeight` 只從 `widget.width` / `widget.height` 計算，沒有使用 `targetDisplaySize`。
- `lib/ui/pages/radio/radio_player_page.dart:155` 到 `lib/ui/pages/radio/radio_player_page.dart:159`、`lib/ui/pages/library/playlist_detail_page.dart:727` 到 `lib/ui/pages/library/playlist_detail_page.dart:733`：多個大封面/背景場景只傳 `targetDisplaySize`，沒有傳 `width` / `height`。

**Trigger scenario**

播放頁、歌單詳情背景、電台詳情封面載入網路圖片。對 Bilibili / Netease / YouTube，URL 通常會被降到較合理尺寸；但未知 domain 或來源未按參數返回預期尺寸時，`CachedNetworkImage` 的 memory decode 仍沒有明確上限。

**User impact**

單張大圖可能以原始下載尺寸進入 image cache。高解析封面或背景圖切換時，可能造成短暫 memory spike、image cache 驅逐，或低階 Android 裝置卡頓。

**Suggested measurement or fix**

- 測量 `invertOversizedImages`、VM Service memory、Timeline；特別測未知來源封面與 YouTube `maxresdefault`。
- 修正方向：將 `targetDisplaySize` 一併傳入 `_CachedNetworkImage`，在 `width` / `height` 缺省時以 `targetDisplaySize * devicePixelRatio` 作為 `memCacheWidth` / `memCacheHeight` 的 fallback。

**Instruction docs accuracy notes**

現有文件說 `targetDisplaySize` 可讓縮圖 URL 選可靠尺寸；代碼確實用於 URL 候選。但文件沒有說明 `targetDisplaySize` 目前不會限制 `CachedNetworkImage.memCacheWidth` / `memCacheHeight`，容易讓呼叫者誤以為它同時控制網路解碼尺寸。

### 3. Confirmed issue：電台可點封面預載繞過統一 cache manager 與候選 URL 流程

**Evidence**

- `lib/ui/widgets/track_detail_panel.dart:2066` 到 `lib/ui/widgets/track_detail_panel.dart:2071`：`_RadioClickableCover._preloadImage()` 直接建立 `CachedNetworkImageProvider(optimizedUrl, headers: ...)`，沒有傳 `NetworkImageCacheService.defaultCacheManager`。
- `lib/core/services/image_loading_service.dart:416` 到 `lib/core/services/image_loading_service.dart:427`：主要圖片路徑使用 `CachedNetworkImage` 並明確傳 `NetworkImageCacheService.defaultCacheManager`、`memCacheWidth`、`memCacheHeight`。
- `lib/ui/widgets/track_detail_panel.dart:2102` 到 `lib/ui/widgets/track_detail_panel.dart:2106`：實際顯示同一張電台封面時又走 `ImageLoadingService.loadImage()`，形成預載與顯示兩套 cache 行為。

**Trigger scenario**

打開電台詳情面板或播放中的 Bilibili live station，`_preloadImage()` 先解析預載，畫面本體再用 `ImageLoadingService` 載入。

**User impact**

同一張封面可能在不同 cache manager / cache key 管線中重複下載、重複記帳或無法被 FMP 的網路圖片磁碟 cache 設定清理。預載也不使用 `getOptimizedUrlCandidates()` 的 fallback 序列，失敗後只靠畫面本體重新載入。

**Suggested measurement or fix**

- 測量 HTTP profile / cache 目錄：進入電台詳情前後比對是否有重複請求與不同 cache 目錄寫入。
- 修正方向：預載改走與 `ImageLoadingService` 相同的 cache manager、headers、候選 URL 與 decode hint；或者移除手寫預載，改由現有 image widget 的載入狀態驅動 overlay。

**Instruction docs accuracy notes**

`lib/ui/AGENTS.md` 對「其他圖片 -> `ImageLoadingService.loadImage()`」是準確的方向；此預載不是直接 `Image.network()` / `Image.file()`，但仍繞過了統一服務的一部分。文件可補一句：預載也應復用 `ImageLoadingService` / `NetworkImageCacheService` 的 cache policy。

### 4. Needs profiling：`FileExistsCache` 在大量初次 miss 時仍可能造成 IO burst

**Evidence**

- `lib/ui/widgets/track_thumbnail.dart:59` 到 `lib/ui/widgets/track_thumbnail.dart:70`、`lib/ui/widgets/track_thumbnail.dart:182` 到 `lib/ui/widgets/track_thumbnail.dart:192`：`TrackThumbnail` / `TrackCover` 用 `.select(...)` 只 watch 相關 local cover path，但在 build 中遇到未命中的 `coverPaths` 會呼叫 `getFirstExisting()` 安排檢查。
- `lib/providers/download/file_exists_cache.dart:201` 到 `lib/providers/download/file_exists_cache.dart:223`：`_scheduleRefreshPaths()` 去重 pending 後，在 microtask 中對 pending path 逐一 `File(path).exists()`。
- `test/providers/download/file_exists_cache_phase4_test.dart:309` 到 `test/providers/download/file_exists_cache_phase4_test.dart:318`：測試確認 missing path cache 可避免重複 refresh scheduling；`test/providers/download/file_exists_cache_phase4_test.dart:337` 到 `test/providers/download/file_exists_cache_phase4_test.dart:346` 確認 missing cache 有 5000 條上限。

**Trigger scenario**

首次打開含大量已下載 track 的頁面，且頁面尚未或無法預先 `preloadPaths()`；每個 visible item 都會在 build 後排入非同步存在性檢查。快速滾動到大量新項目時，可能連續觸發多批文件存在性 IO。

**User impact**

目前沒有同步 IO 直接卡 build，且 pending/missing cache 已降低重複工作；但在慢速磁碟、網路磁碟、自訂 Android 下載目錄或超大庫時，microtask IO burst 仍可能影響 frame pacing。

**Suggested measurement or fix**

- 用 VM Service Timeline 與 `profileWidgetBuilds` 測量：清空 `FileExistsCache` 後進入大型已下載歌單，記錄 `Animator::BeginFrame`、`GPURasterizer::Draw`、Dart heap / external memory。
- 若 profiling 顯示卡頓，優先在頁面進入時批次 `preloadPaths()`，或把 `getFirstExisting()` 的檢查做節流/批次化，避免每個新 item 都各自排入 microtask。

**Instruction docs accuracy notes**

`FileExistsCache` 的 watch/read 模式與 `.select(...)` 描述準確；memory 補充中「避免 UI build 同步 IO」也與代碼一致。不過文檔沒有要求所有大型列表都必須預載封面存在性，這部分仍需用 profiling 決定是否升級為規範。

## 測試與覆蓋觀察

- `test/core/utils/thumbnail_url_utils_test.dart:79` 到 `test/core/utils/thumbnail_url_utils_test.dart:107` 覆蓋 YouTube `mqdefault` 不升級與候選 URL 去重。
- `test/ui/static_rules/ui_consistency_static_rule_test.dart:50` 到 `test/ui/static_rules/ui_consistency_static_rule_test.dart:71` 靜態檢查部分固定尺寸圖片有 `targetDisplaySize`，但不是全域掃描所有 `loadImage()` 呼叫，也沒有驗證 `targetDisplaySize` 是否影響 decode size。
- `test/ui/widgets/track_thumbnail_test.dart:19` 到 `test/ui/widgets/track_thumbnail_test.dart:29` 覆蓋 `TrackThumbnail` layout size；目前未覆蓋 `ImageLoadingService` 對本地/網路圖片的 `cacheWidth`、`memCacheWidth` 行為。
