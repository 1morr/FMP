# Riverpod / Rebuild 審查

日期：2026-05-25
範圍：`lib/providers`、`lib/ui` 中的 Riverpod provider、`ConsumerWidget`/`ConsumerStatefulWidget`、`ref.watch` 使用、列表 row rebuild、`FutureProvider` invalidation。
限制：本次只審查與寫文檔，未修改程式碼或其他 agent 報告。

## 語料分層

### 規範性要求

- `AGENTS.md` 要求以 `rg` 搜索、保留他人變更、使用既有 provider/helper pattern，並在 UI 控制播放時走 `AudioController`。
- `lib/providers/AGENTS.md` 要求：DB 多寫入集合用 Isar `watchAll()` + `StateNotifier`；DB join 用 `StateNotifier` + 樂觀更新；檔案系統掃描用 `FutureProvider` + `invalidate`；`isLoading` 頁面必須守衛 `isLoading && data.isEmpty`；涉及 playlist/detail/cover/download 的連動刷新應走 `libraryInvalidationCoordinatorProvider`；排行榜 UI watch `RankingCacheState`，刷新用 notifier。
- `lib/ui/AGENTS.md` 要求：圖片走 `TrackThumbnail` / `TrackCover` / `ImageLoadingService`；播放狀態預設用 `currentTrackProvider` 比對；下載/本地檔案使用 `FileExistsCache` watch + read 模式；列表 item 使用穩定 key；避免 `ListTile.leading` 放複合 `Row`。
- `docs/README.md` 說明 `AGENTS.md` 是 agent 權威規則，`docs/development.md` 是人類 onboarding 摘要，`.serena/memories/` 只應是窄補充。

### 描述性內容

以下內容只當作審查線索，已回到程式碼和測試驗證：

- `.serena/memories/refactoring_lessons.md` 與 `.serena/memories/ui_coding_patterns.md` 提到：`FutureProvider` 失效後保留舊資料、`StreamProvider`/`FutureProvider` 因使用者切換排序/篩選 reload 時應避免 loading 閃爍、列表/網格要穩定 key、列表 item 可 watch `currentTrackProvider`。
- `docs/development.md` 摘要了 Riverpod 2.x、FutureProvider invalidation、列表 key、AudioController 邊界，但它不是逐條規範來源。
- `docs/reviews/performance/instruction-corpus.md` 已存在且未修改；其審查規則與本報告一致：描述性 claims 必須用 code evidence 驗證。

## Findings

### 1. Confirmed issue：搜尋篩選/排序會清空結果並觸發整頁 loading 閃爍

Evidence:

- `lib/providers/search_provider.dart:516`-`522`：`setSource()` 在有 query 時把 `onlineResults` 設為 `{}` 並 `isLoading: true`。
- `lib/providers/search_provider.dart:536`-`540`：`setSearchOrder()` 在有 query 時同樣清空 `onlineResults` 並進入 loading。
- `lib/providers/search_provider.dart:247`-`253`：`search()` 開始時再次清空 `onlineResults`。
- `lib/ui/pages/search/search_page.dart:436`-`438`：當 `state.isLoading && state.allOnlineTracks.isEmpty` 時整個結果區改成 spinner。

Trigger scenario:

- 使用者已看到「全部音源」搜尋結果後切到 Bilibili / YouTube / Netease chip，或切換排序。
- 多音源搜尋結果多、網路慢或其中一個音源延遲時，結果區會先變空白 loading，再回填。

User impact:

- 明顯閃爍，使用者失去正在閱讀的位置。
- 切換排序/篩選的體感像重新進頁，而不是刷新既有結果。

Suggested measurement or fix:

- 用 VM Service 開 `profileWidgetBuilds`，錄製「搜尋 -> 切換 chip -> 切排序」的 build timeline，確認 spinner 期間與列表 rebuild 數。
- 對篩選：如果舊 `onlineResults` 已包含目標 source，可先保留該 source 的舊結果並顯示 inline refresh indicator。
- 對排序：保留舊排序結果到新結果回來，另用 `isRefreshing` 或 `loadingReason` 控制底部/頂部進度，不用清空列表。

Instruction docs accuracy notes:

- `lib/providers/AGENTS.md` 的 `isLoading && data.isEmpty` 規則在 UI 層有遵守，但 provider 主動清空 data，實際仍造成閃爍。
- `.serena/memories/ui_coding_patterns.md` 對使用者切換排序/篩選時「保留舊資料」的描述與這段搜尋實作不一致。

### 2. Confirmed issue：搜尋多選狀態 watch 範圍過大

Evidence:

- `lib/ui/pages/search/search_page.dart:76`-`83`：`SearchPage.build()` watch 整個 `searchProvider` 和整個 `searchSelectionProvider`，並每次 build 重建 `allTracks`。
- `lib/providers/selection_provider.dart:33`-`46`：`SelectionState` 包含 `isSelectionMode`、`selectedKeys`、`selectedTracks`。
- `lib/ui/pages/search/search_page.dart:491`-`535`：本地結果 section 又 watch `searchSelectionProvider`，並在 builder 中計算 group 選取狀態。
- `lib/ui/pages/search/search_page.dart:559`-`586`：線上結果 section 同樣 watch selection，並對每列呼叫 `selectionState.isSelected(track)`。

Trigger scenario:

- 搜尋結果很多時進入多選模式，連續點選/取消多個 track。

User impact:

- 每次選取都會讓整個 `Scaffold`、AppBar、source filter、結果 section 參與 rebuild，而不是只更新受影響 row 和 selection app bar。
- 多音源搜尋結果混排時，還會重跑本地去重/分組與線上列表 build。

Suggested measurement or fix:

- 量測選取 20 個結果時 dirty widget 數量與 frame time。
- 頂層只 watch `searchSelectionProvider.select((s) => s.isSelectionMode)`；`SelectionModeAppBar` 已可直接 consume provider。
- Row 層改為 watch `selectedKeys` 的 per-track boolean selector，或建立 `selectionContainsProvider((provider, key))`，讓未受影響 row 不 rebuild。

Instruction docs accuracy notes:

- 現有文件要求列表 item 穩定 key，搜尋頁已有 key；但文件沒有明確要求 selection state 只 watch row 所需欄位。
- 可在 `lib/ui/AGENTS.md` 補一句：長列表多選狀態應使用 `.select` 或 per-row boolean provider，避免頁面頂層 watch 整個 `SelectionState`。

### 3. Needs profiling：多音源搜尋的 `mixedOnlineTracks` 是 build-time 衍生熱點

Evidence:

- `lib/providers/search_provider.dart:96`-`111`：`mixedOnlineTracks` getter 依排序每次產生新的 List。
- `lib/providers/search_provider.dart:114`-`142`：`_interleaveResults()` 逐 source 交錯建立結果。
- `lib/ui/pages/search/search_page.dart:80`-`83`：頂層 build 讀 `searchState.mixedOnlineTracks` 建 `allTracks`。
- `lib/ui/pages/search/search_page.dart:546`-`589`：線上結果 section 再讀 `state.mixedOnlineTracks` 來建立 `SliverList`。
- `lib/providers/search_provider.dart:428` 與 `489`-`493`：`loadMoreAll()` 先把 `isLoading` 設 true，完成後再合併三個 source 結果並設 false。

Trigger scenario:

- 「全部音源」搜尋後滾到底，`loadMoreAll()` 同時載入 Bilibili + YouTube + Netease 下一頁。
- 每次 loading toggle 與結果合併都會觸發頁面 rebuild，getter 也會重算混排。

User impact:

- 結果數多時，build 階段可能出現不必要配置與排序成本；如果同時有選取狀態或播放狀態變更，成本疊加。

Suggested measurement or fix:

- 在 profile 模式錄製 300/600/1000 筆搜尋結果的 `loadMoreAll()`，比較 `SearchPage.build`、`SliverChildBuilderDelegate`、GC new-space 次數。
- 將混排結果在 `SearchNotifier` 更新 state 時一次算好，或用 memoized selector 以 `onlineResults` identity + `searchOrder` 為 key。
- 頂層 `allTracks` 可延後到進入 selection app bar 時再算，避免一般瀏覽每次 build 都合併。

Instruction docs accuracy notes:

- 文件要求「all 查三音源、source chip 查單音源」與實作相符。
- 文件沒有覆蓋「昂貴衍生 list 不應在 widget build getter 中反覆建立」；這是可新增的 performance guidance。

### 4. Confirmed issue：Explore 排行榜頁 watch inactive sources 與完整 `RankingCacheState`

Evidence:

- `lib/ui/pages/explore/explore_page.dart:59`-`69`：`ExplorePage.build()` 同時 watch Bilibili、YouTube、Netease 三個 ranking provider，只為目前 tab 的全選清單。
- `lib/ui/pages/explore/explore_page.dart:128`-`160`：三個 tab builder 都 watch `rankingCacheServiceProvider` 完整 state，再取各自 error/loading。
- `lib/providers/popular_provider.dart:252`-`269`：三個 cached ranking provider 已有 source-specific `.select`。
- `test/ui/pages/ranking_ui_state_consumption_test.dart:100`-`113`：測試只保護 Home rankings 使用 `rankingCacheServiceProvider.select((state) => state.isInitialLoading)`，未覆蓋 Explore。

Trigger scenario:

- 使用者停在 Bilibili tab 時，背景刷新 YouTube 或 Netease，或某 source error 欄位變動。

User impact:

- inactive tab 資料變動仍可讓 Explore 頂層與當前 tab rebuild。
- 排行榜列表通常含圖與播放狀態，額外 rebuild 會放大 image/layout 成本。

Suggested measurement or fix:

- 對三 source 分別觸發 refresh，量測停留在不同 tab 時 dirty widgets。
- 頂層只 watch active tab 的 tracks；全選時可由 active tab provider 提供清單。
- tab content watch per-source tuple，例如 `rankingCacheServiceProvider.select((s) => (isInitialLoading: s.isInitialLoading, error: s.bilibiliError))`，避免完整 state 變更波及。

Instruction docs accuracy notes:

- `lib/providers/AGENTS.md` 要求 RankingCache UI watch immutable state，實作符合「不可讀 mutable singleton」。
- 但 Home 已有更細 selector 測試，Explore 仍使用完整 state；文件若要更準確，應寫成「UI watch `RankingCacheState` 時應 select 所需欄位」。

### 5. Suspected issue：PlaylistDetail 頂層 watch 全域 file cache epoch，可能讓整頁被下載/檔案快取更新牽動

Evidence:

- `lib/ui/pages/library/playlist_detail_page.dart:164`-`167`：詳情頁頂層 watch `playlistDetailProvider`、`playlistDetailSelectionProvider`、`fileExistsCacheEpochProvider`。
- `lib/ui/pages/library/playlist_detail_page.dart:132`-`149`：build 中呼叫 `_checkAndPreloadCache()`，並在 post-frame 對整批下載路徑 `preloadPaths()`。
- `lib/providers/download/file_exists_cache.dart:250`-`257`：`fileExistsCacheEpochProvider` 是全域 epoch，`FileExistsCache` 任一 epoch 變化都會更新它。
- `lib/ui/pages/library/playlist_detail_page.dart:1103`-`1109`：單列下載狀態其實已用 `filePathExistsProvider(path)` 做 per-path watch。
- `test/providers/download/file_exists_cache_phase4_test.dart:250`-`263`：測試目前明確要求 playlist detail page watch reactive cache epoch provider。

Trigger scenario:

- 下載完成、刪除下載、或其他頁面大量預載/清理 file cache。
- 正開著大歌單詳情頁時，全域 epoch 變更會使整頁 build，進而重跑 path set 比對與 sliver 建立。

User impact:

- 大歌單中下載狀態更新可能造成整頁級 rebuild，而 row 級 per-path provider 已足以更新圖示/狀態。
- 因測試目前保護此 pattern，修改時需要先釐清原本要避免的 stale cache bug。

Suggested measurement or fix:

- 在 1000 首歌單頁執行單首下載完成，開 `trackRebuildDirtyWidgets` 比較整頁 dirty 數。
- 若只是為了預載 path，可改成 `ref.listen(playlistDetailProvider.select((s) => s.tracks))` 或在 notifier 完成 tracks 載入後觸發，不要在 widget 頂層 watch 全域 epoch。
- 保留 row 級 `filePathExistsProvider(path)`，讓只有受影響的下載狀態 row rebuild。

Instruction docs accuracy notes:

- `lib/ui/AGENTS.md` 說 shared thumbnail widgets 可用 `.select` watch relevant local path state；這與 row 級 provider 相符。
- `.serena/memories/refactoring_lessons.md` 的「FileExistsCache 要 watch + read」是廣義規則；在長列表頁面應補充「優先 watch per-path/select，不要用全域 epoch 驅動整頁」。

### 6. Confirmed issue：PlaylistDetail 多選 watch 讓整頁與 sliver app bar 跟著每次選取 rebuild

Evidence:

- `lib/ui/pages/library/playlist_detail_page.dart:164`-`166`：詳情頁頂層 watch 整個 `playlistDetailSelectionProvider`。
- `lib/ui/pages/library/playlist_detail_page.dart:307`-`315`：每個 group item build 又 watch selection provider。
- `lib/ui/pages/library/playlist_detail_page.dart:650`-`672`：`_buildSliverAppBar()` 再 watch selection provider 取得 selected count/all selected。
- `lib/ui/pages/library/playlist_detail_page.dart:319`-`335` 與 `368`-`385`：row props 包含 `isSelectionMode`、`isSelected`，任一選取變更會重新建 visible row。

Trigger scenario:

- 在 500+ 首歌單進入多選，逐首選取或全選 group。

User impact:

- 每次選取都會牽動頁面頂層、SliverAppBar、group list build，而不是只更新勾選列與 AppBar selection count。
- 和 finding 5 的 file cache epoch 疊加時，歌單詳情是 rebuild 熱點。

Suggested measurement or fix:

- 用 profile 模式在大歌單連續選 20 首，記錄 dirty widget、build ms、GC。
- 頂層只 watch `isSelectionMode`；AppBar 用小型 Consumer/select watch `selectedCount`、`selectedKeys.length`。
- Row 層使用 per-track selected boolean selector，避免整個 list 因 `selectedTracks` list identity 變更而 rebuild。

Instruction docs accuracy notes:

- 文件有「列表/網格重複項使用穩定 key」要求，playlist detail 已符合。
- 文件缺少 selection provider watch 範圍的規範；建議和搜尋頁一起補。

### 7. Needs profiling：列表 item 直接 watch `currentTrackProvider` 是播放切歌時的跨頁熱點

Evidence:

- `lib/services/audio/audio_provider.dart:3305`-`3307`：`currentTrackProvider` select `audioControllerProvider.currentTrack`。
- 搜尋頁 row：`lib/ui/pages/search/search_page.dart:996`、`1178`、`1280`、`1488`。
- 歌單詳情 row/group：`lib/ui/pages/library/playlist_detail_page.dart:1253`、`1468`。
- 已下載詳情 row/group：`lib/ui/pages/library/downloaded_category_page.dart:518`、`716`。
- Explore/Home ranking row：`lib/ui/pages/explore/explore_page.dart:244`、`lib/ui/pages/home/home_page.dart:913`。

Trigger scenario:

- 播放下一首、臨時播放搜尋結果、或快速切歌。
- 當搜尋、排行榜、歌單詳情、已下載詳情有大量 visible/cacheExtent row 時，所有 watch `currentTrackProvider` 的 visible item 都會 rebuild 來判斷自己是否播放中。

User impact:

- 對短列表合理；對長列表、桌面大視窗或高 `cacheExtent` 場景可能形成每次切歌的 rebuild burst。

Suggested measurement or fix:

- 先量測「大歌單切歌」與「搜尋結果切歌」的 dirty widget 數；若只是 visible row 數量可接受，保留現況。
- 若超標，建立 row 級 boolean selector，例如 `isTrackCurrentProvider(trackIdentity)` 或直接 `audioControllerProvider.select((s) => matches(s.currentTrack, trackIdentity))`，讓 Riverpod 只通知 false->true / true->false 的 rows。
- 對 group header 可 select `currentTrack.sourceId/pageNum` 後以 group identity 比對，避免整個 `Track` object 變更造成不必要 row rebuild。

Instruction docs accuracy notes:

- `lib/ui/AGENTS.md` 目前明確示範 item watch `currentTrackProvider`，所以這不是違規。
- 建議將文件改成兩層：一般 item 可 watch `currentTrackProvider`；長列表/排行榜/搜尋結果應優先用 per-row boolean `.select`。

### 8. Confirmed issue：Radio UI 直接 watch 完整 `audioControllerProvider`

Evidence:

- `lib/ui/widgets/radio/radio_mini_player.dart:34`-`38`：radio mini player watch `radioControllerProvider` 後直接 `ref.watch(audioControllerProvider)`。
- `lib/ui/pages/radio/radio_player_page.dart:29`-`32`：radio player page 同樣直接 watch 完整 `audioControllerProvider`。
- `lib/ui/pages/radio/radio_player_page.dart:46`-`52`：實際使用 audio state 的地方是桌面音訊設備與音量控制。
- 對照：`lib/ui/pages/player/player_page.dart:89`-`108`、`lib/ui/widgets/player/mini_player.dart:322`-`329`、`417`-`419` 已改用 selectors。
- `test/ui/pages/player/player_page_phase4_test.dart:36`-`49` 與 `test/ui/widgets/mini_player_test.dart:17`-`29` 只保護 player/mini player，未保護 radio UI。

Trigger scenario:

- radio mini player 顯示時，音樂 AudioController 的 progress/position/buffering/loading/queue 變動。
- Radio player page 開著時，任何 `PlayerState` 欄位變更都會 rebuild 整頁。

User impact:

- Radio UI 只需要共用 backend 的音量/音訊設備，卻會被完整 music player state 牽動。
- 在桌面端尤其容易和 progress tick 疊加，造成不必要 rebuild。

Suggested measurement or fix:

- 用 `profileWidgetBuilds` 觀察 radio mini player 在一般音樂播放進度 tick 時是否 rebuild。
- 改用 `desktopAudioDeviceStateProvider` 與 `audioControllerProvider.select((s) => s.volume)`；需要其他欄位再建立小 tuple selector。
- 補一個 static test，類似 PlayerPage：radio UI 不應包含 `ref.watch(audioControllerProvider)`。

Instruction docs accuracy notes:

- 現有測試已表明 player UI 方向是「shared selectors instead of broad controller watch」，但此規範尚未延伸到 radio UI。
- `lib/providers/AGENTS.md` 可補充：共享 `AudioController` state 的 UI 應 select 所需欄位，避免 watch 完整 `PlayerState`。

### 9. Needs profiling：Downloaded `FutureProvider` invalidation 路徑大致正確，但需用 runtime 驗證是否無刷新閃爍

Evidence:

- `lib/providers/download/download_providers.dart:235`-`245`：`downloadedCategoriesProvider` 是檔案掃描 `FutureProvider`。
- `lib/providers/download/download_providers.dart:248`-`254`：`downloadedCategoryTracksProvider(folderPath)` 是 folder 掃描 `FutureProvider.family`。
- `lib/providers/library_invalidation_coordinator.dart:89`-`110`：download mutation 經 coordinator invalidate categories 與 category tracks。
- `lib/ui/pages/library/downloaded_page.dart:93`-`117` 與 `lib/ui/pages/library/downloaded_category_page.dart:109`-`171`：UI 使用 `.when(loading: ...)`，未顯式設定 `skipLoadingOnRefresh`。
- `lib/ui/pages/library/downloaded_category_page.dart:85`-`89`：手動刷新 invalidate family provider 後 await future。
- `test/providers/startup_download_sync_provider_test.dart:52`-`65`、`222`-`236`：測試保護 startup sync 走 coordinator，而不是直接 invalidate。

Trigger scenario:

- 已下載頁正在顯示資料時，下載完成、刪除下載分類、同步本地檔案或手動 refresh。

User impact:

- 依 Riverpod 預設，`invalidate()` refresh 通常保留舊資料，不應閃爍；但實際 UX 仍需用 runtime 確認，尤其是 dependency reload 或 provider family 參數切換時。

Suggested measurement or fix:

- 用 VM Service 或 widget test 驗證：在已有資料狀態下 invalidate `downloadedCategoriesProvider` / `downloadedCategoryTracksProvider`，畫面是否保持舊 list 而非全頁 spinner。
- 若發現閃爍，明確使用 `when(skipLoadingOnRefresh: true, skipLoadingOnReload: true)` 或在頁面保留 last good data。
- 保留 coordinator 路徑；目前未發現下載 mutation 漏 invalidate 的 confirmed issue。

Instruction docs accuracy notes:

- `lib/providers/AGENTS.md` 的「FutureProvider data must be invalidated after mutations」與目前 coordinator 實作相符。
- `.serena/memories/ui_coding_patterns.md` 說 FutureProvider invalidate 會保留舊資料；這是 Riverpod 行為 claim，建議用 targeted widget/runtime test 固化，避免未來 Riverpod 或程式碼改動造成回歸。

## 優先建議

1. 先修 confirmed broad watch：Radio UI 完整 `audioControllerProvider`、Explore 完整 ranking state、搜尋/歌單 selection 頂層 watch。
2. 再量測長列表播放切歌：若 dirty rows 超過可接受範圍，再導入 per-row boolean selector。
3. 搜尋頁應優先處理篩選/排序清空結果造成的 flicker，這是使用者最容易感知的 rebuild/loading 問題。
4. PlaylistDetail 的 file cache epoch 有測試保護，修改前先重現原 stale-cache 場景，再以更窄的 listener 或 per-path watch 替代。

## 建議驗證命令

本報告未修改程式碼。若後續要改 code，建議最小驗證：

```bash
flutter test test/ui/pages/ranking_ui_state_consumption_test.dart test/ui/pages/search/search_page_phase2_test.dart test/providers/download/file_exists_cache_phase4_test.dart
flutter analyze
```
