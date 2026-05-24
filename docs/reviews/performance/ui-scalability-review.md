# UI Scalability Review

Scope: 大型列表、歌單詳情、搜索結果、下載列表、播放隊列。本文只審查並記錄，不修改產品程式碼，也不修改其他 agent 的報告。

## 語料分層

規範性要求:

- `AGENTS.md` 要求保留他人變更、UI widgets/pages 做 targeted tests + `flutter analyze`，並以 `lib/ui/AGENTS.md` 作為 UI 規則來源。
- `lib/ui/AGENTS.md:77` 要求避免 `Row` 直接放在 `ListTile.leading`，需要複合 leading 時改用扁平 `InkWell` + `Padding` + `Row`。
- `lib/providers/AGENTS.md:16` 要求 `isLoading` 頁面使用 `isLoading && data.isEmpty` 守衛，`lib/providers/AGENTS.md:17` 要求 `FutureProvider` mutation 後 invalidate。
- `docs/development.md:165` 與 `.serena/memories/refactoring_lessons.md:27` 要求列表/網格重複項使用穩定 key。
- `docs/debugging-with-vm-service.md:260` 定義 jank 閾值，`docs/debugging-with-vm-service.md:349` 提供 `profileWidgetBuilds` 的量測方式。

描述性內容，只作線索並以代碼驗證:

- `.serena/memories/ui_coding_patterns.md:355` 說列表項應使用 `ValueKey`；實作中部分頁面已符合，但仍有缺口，見 findings。
- `.serena/memories/ui_coding_patterns.md:316` 說 `FutureProvider` refresh 會保留舊資料；下載分類頁使用 `FutureProvider`，本次未把該描述直接當成性能證據。
- `docs/reviews/performance/instruction-corpus.md:138` 把 playlist/downloaded/search stable keys 列為待驗證描述；本 review 逐一查了相關呼叫點。

## 已驗證的正向情況

- 歌單詳情初始只載入 100 首，`PlaylistDetailNotifier._pageSize` 在 `lib/providers/playlist_provider.dart:273`，初次與 load more 分頁在 `lib/providers/playlist_provider.dart:280` 和 `lib/providers/playlist_provider.dart:323`。
- 已下載分類與歌單詳情都使用 `CustomScrollView` + `SliverList`，不是把整個清單展開成 `Column`：`lib/ui/pages/library/downloaded_category_page.dart:143`、`lib/ui/pages/library/playlist_detail_page.dart:226`。
- `ListTile.leading` 直接使用 `Row` 的靜態測試存在於 `test/ui/static_rules/list_tile_leading_static_rule_test.dart:6`，本次 `rg` 沒在審查範圍內找到直接 `leading: Row(`。
- 下載進度已走 per-task selector：`downloadTaskProgressProvider` 在 `lib/providers/download/download_providers.dart:169` 以 `select((state) => state[taskId])` 只重建單一 task。

## Findings

### FMP-UI-SCALE-01 - 搜索結果在 build 中反覆重組與排序

Status: Confirmed issue.

Evidence: `SearchState.mixedOnlineTracks` 每次 getter 都重新產生 list；播放量排序還會 sort：`lib/providers/search_provider.dart:96`、`lib/providers/search_provider.dart:105`。同一次 search results build 會多次讀這個 getter：`lib/ui/pages/search/search_page.dart:546`、`lib/ui/pages/search/search_page.dart:552`、`lib/ui/pages/search/search_page.dart:565`、`lib/ui/pages/search/search_page.dart:588`。

Trigger scenario: 使用 All 搜索、持續 load more 到多個音源累積大量 online tracks，或切到播放量排序後再切換 selection/loading 狀態。

User impact: 每次搜索頁 rebuild 都可能做多次 O(n) interleave 或 O(n log n) sort。資料量大時會增加 UI thread build 成本，導致滾動與載入更多時掉幀。

Suggested measurement or fix: 先在 profile mode 開 `profileWidgetBuilds`，對 300/600/1000 online tracks 比較 sort 前後 build time。修正方向是同一次 build 先存 `final mixedOnlineTracks = state.mixedOnlineTracks`，再進一步把 mixed/sorted 結果搬到 notifier state 或 memoized selector，避免 getter 具有昂貴工作。

Instruction docs accuracy notes: stable key 規範本身準確，但沒有覆蓋「getter 不能在 build 熱路徑反覆排序」這類衍生規則；VM Service profiling 文檔可直接用來量測。

### FMP-UI-SCALE-02 - 搜索展開的 online 分 P row 缺少 key

Status: Confirmed issue.

Evidence: `_SearchResultTile` 展開 `pages` 時直接 map `_PageTile`，沒有傳 key：`lib/ui/pages/search/search_page.dart:1143`。`_PageTile` constructor 也沒有 `super.key`：`lib/ui/pages/search/search_page.dart:1168`。現有 key 測試涵蓋 online 主 row、本地展開 row、playlist detail row：`test/ui/pages/search/search_page_phase2_test.dart:40`，但沒有要求 `_PageTile` key；`test/ui/static_rules/ui_consistency_static_rule_test.dart:145` 只檢查 `_PageTile` 的 action menu。

Trigger scenario: 展開多 P 在線視頻後，該視頻的 pages 載入/更新、父列表重排，或目前播放分 P 變更造成子 row rebuild。

User impact: Flutter 只能按位置比對 `_PageTile` element。若頁面列表發生插入、順序變化或資料補齊，可能出現 row 狀態/高亮短暫錯位；目前風險偏低，因 pages 通常一次載入後穩定。

Suggested measurement or fix: 給 `_PageTile` 加 `super.key`，呼叫端使用 `ValueKey('${track.sourceType.name}:${track.sourceId}:${page.page}:${page.cid ?? 0}')` 類型的穩定身份。加靜態測試覆蓋 `_PageTile(` keyed call site。

Instruction docs accuracy notes: `docs/development.md:165` 的「列表/網格重複項應使用穩定 key」準確；現有測試只覆蓋部分動態 row。

### FMP-UI-SCALE-03 - 歌單詳情多 P group wrapper 缺少 key

Status: Confirmed issue.

Evidence: 歌單詳情多 P group 回傳頂層 `Column`，但沒有 key：`lib/ui/pages/library/playlist_detail_page.dart:341`。相同模式的 downloaded category 已在 group wrapper 上使用 `ValueKey('downloaded-group-${group.groupKey}')`：`lib/ui/pages/library/downloaded_category_page.dart:445`。歌單詳情測試只要求 `_TrackListTile` keyed call site 至少兩處：`test/ui/pages/search/search_page_phase2_test.dart:68`。

Trigger scenario: 大歌單載入更多、遠端刷新移除歌曲、批量刪除、或 group 前方插入/刪除導致 `SliverList` 子節點位置改變。

User impact: 單曲 row 有 key，但多 P group 的頂層 element 無穩定身份。當 group 位置移動時，Flutter 只能用 index 比對 wrapper，可能造成 context menu、展開子樹或重繪邊界重用不理想。

Suggested measurement or fix: 對 playlist detail 的多 P branch 加 `key: ValueKey('playlist-group-${group.groupKey}')`，並補一條 static rule test 對齊 downloaded category。這是低風險修正，不需要 runtime profiling 才能判定。

Instruction docs accuracy notes: `.serena/memories/ui_coding_patterns.md:355` 和 `docs/development.md:165` 對 stable key 的要求準確；描述性 claim「playlist detail 使用 stable keys」只對 track row 成立，不完整。

### FMP-UI-SCALE-04 - 播放隊列拖拽 hover 以整頁 setState 更新

Status: Needs profiling.

Evidence: 拖拽進入不同 target 時 `_onDragUpdate` 對整個 `QueuePage` `setState`：`lib/ui/pages/queue/queue_page.dart:184`。列表使用 `ScrollablePositionedList.builder` 並開啟 `addAutomaticKeepAlives: true`：`lib/ui/pages/queue/queue_page.dart:406`、`lib/ui/pages/queue/queue_page.dart:411`。每個 row 內有 `DragTarget` + `LongPressDraggable`：`lib/ui/pages/queue/queue_page.dart:610`、`lib/ui/pages/queue/queue_page.dart:630`。row key 包含 index：`lib/ui/pages/queue/queue_page.dart:440`。

Trigger scenario: 500+ 首播放隊列中長按拖拽，跨過多個 row，尤其是在 Windows desktop 或低端 Android 上。

User impact: hover target 每變一次都可能重建頁面與可見 row；keep-alive 會保留更多已建 row。index-based key 在 reorder 後也會讓 moved track 的 element identity 改變。這可能造成拖拽卡頓、記憶體增加或 thumbnail/indicator 重建過多。

Suggested measurement or fix: 用 profile mode + `profileWidgetBuilds` 量測拖拽 100/500/1000 queue items 的 dirty widget 數、UI frame P90/P99。若確認卡頓，把 drag target 狀態下放到 row-level `ValueListenable`/provider selector，或改用框架/套件的 reorderable list。key 需要用 queue entry identity；若允許同一 track 重複入隊，不能只用 `track.id`，應引入穩定 queue item id 或 occurrence token。

Instruction docs accuracy notes: 現有 `test/ui/pages/queue/queue_page_reorder_test.dart:75` 只驗證 shuffle mode 仍有拖拽 affordance，沒有覆蓋拖拽性能、key identity 或 keep-alive 成本。VM Service 調試文檔適合補量測。

### FMP-UI-SCALE-05 - 下載管理列表缺少 row key 且每次重建多次掃描 task

Status: Suspected issue.

Evidence: 外層 `ListView.builder` 回傳 section/task，但 `_SectionHeader`、`_FixedHeightDownloadingSection`、`_DownloadTaskTile` 呼叫點沒有 key：`lib/ui/pages/settings/download_manager_page.dart:121`、`lib/ui/pages/settings/download_manager_page.dart:127`、`lib/ui/pages/settings/download_manager_page.dart:132`、`lib/ui/pages/settings/download_manager_page.dart:137`。`_DownloadTaskTile` constructor 沒有 `super.key`：`lib/ui/pages/settings/download_manager_page.dart:321`。`_buildRows` 對同一份 tasks 分別 `where` 五次：`lib/ui/pages/settings/download_manager_page.dart:195`。正在下載區還包一層固定高度、不可滾動的 nested `ListView.builder`：`lib/ui/pages/settings/download_manager_page.dart:261`。

Trigger scenario: 大量 completed/failed/pending tasks 並存，任務狀態頻繁在 pending/downloading/completed 間移動，或使用者快速滾動下載管理頁。

User impact: row 沒 key 時，section 變動可能造成 task tile element 按位置重用。五次掃描在數千 task 時增加 build 成本。nested fixed list 目前 maxSlots 通常很小，但它仍是 nested scroll/layout 熱點。

Suggested measurement or fix: 先用 1000/5000 fake tasks 做 widget benchmark，記錄 `_buildRows` 時間與 frame time。修正可單次分類 tasks，為 header 用 `ValueKey('downloads-section-$status')`、task 用 `ValueKey('download-task-${task.id}')`，並讓 `_DownloadTaskTile` 接收 `super.key`。固定下載區若只顯示 maxConcurrent slots，可考慮不用 nested `ListView.builder`，直接 builder delegate/for loop 生成固定 slots。

Instruction docs accuracy notes: 下載進度「記憶體優先、per-task selector」的描述與 `lib/providers/download/download_providers.dart:141`、`lib/providers/download/download_providers.dart:169` 一致。`test/ui/pages/settings/download_manager_page_phase4_test.dart:37` 只驗證扁平 builder rows，未覆蓋 key 或分類成本。

### FMP-UI-SCALE-06 - 歌單詳情下載狀態以多個 per-path watch 聚合

Status: Needs profiling.

Evidence: `_isDownloadedForPlaylistWithExistingFile` 對單一路徑 watch `filePathExistsProvider(path)`：`lib/ui/pages/library/playlist_detail_page.dart:1093`、`lib/ui/pages/library/playlist_detail_page.dart:1104`。多 P header 會對 `group.tracks.every(...)` 逐首檢查下載狀態：`lib/ui/pages/library/playlist_detail_page.dart:1254`。一般 track tile 也在 build 中查下載狀態：`lib/ui/pages/library/playlist_detail_page.dart:1468`。頁面會在 tracks/cache epoch 變化後 post-frame preload paths：`lib/ui/pages/library/playlist_detail_page.dart:144`。

Trigger scenario: 大型歌單中多個多 P group 已下載，下載完成或本地檔案 cache epoch 更新時，使用者停留在歌單詳情並滾動。

User impact: `filePathExistsProvider` 使用 `select`，所以單一路徑重建粒度合理；但多 P header 會註冊 group 內每個 track 的 dependency。若一個 group 很大，或可見 group 多，下載狀態變化可能造成 header build 成本偏高。

Suggested measurement or fix: 用 profile mode 在含大量多 P tracks 的歌單上觸發下載完成/cache invalidation，量測 `_GroupHeader` build 次數與耗時。若熱點成立，可把 group downloaded status 預先用已 preload 的 path set 做一次性計算，或新增 aggregate provider/cache，讓 header watch 一個 group key 而不是 N 個 path。

Instruction docs accuracy notes: `FileExistsCache` 的 watch/read 模式與 `filePathExistsProvider.select` 是準確且合理的；這不是規範錯誤，而是大 group 聚合時需要 profile 的熱點。

## Coverage Gaps

- `test/performance/list_scrolling_benchmark_test.dart:5` 是通用 benchmark，沒有掛到 FMP 的實際 `SearchPage`、`PlaylistDetailPage`、`DownloadManagerPage` 或 `QueuePage` widget。
- 沒有執行 runtime profile；所有 `needs profiling` 項目都需要用 `docs/debugging-with-vm-service.md` 的 profile/timeline 流程補證。
- 本 review 沒有修改程式碼；建議修正前先分別建立小型 widget/static tests，避免 key/layout 回歸。
