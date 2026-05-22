# Library / Playlist UI Review

## Findings

1. 類型：bug；嚴重度：高
   `lib/ui/pages/library/downloaded_category_page.dart:910`
   已下載分類頁刪除單首下載時，`_deleteDownload()` 直接用掃描出來的 `track.id` 呼叫 `trackRepo.clearDownloadPath(track.id)`，但掃描 DTO 在 `lib/providers/download/download_scanner.dart:90` 建出的 `Track` 沒有持久化 id，通常會是預設 id。結果是檔案被刪除，但 persisted `Track.playlistInfo[].downloadPath` 可能沒有被清掉；同時 `downloadStateChanged(fileExistsChanged: false)` 在 `lib/ui/pages/library/downloaded_category_page.dart:921` 明確不刷新 `FileExistsCache`。

2. 類型：UX 問題；嚴重度：中
   `lib/ui/pages/library/playlist_detail_page.dart:1214`、`lib/ui/pages/library/playlist_detail_page.dart:1516`
   playlist detail 的下載完成標記只看 `track.isDownloadedForPlaylist(...)`，也就是 DB 中的 downloadPath 是否非空，沒有用 `FileExistsCache.exists()` 驗證實際檔案仍存在。頁面雖在 `lib/ui/pages/library/playlist_detail_page.dart:124` 預載封面路徑 cache，但沒有對音訊下載路徑做相同的 existence gate。

3. 類型：代碼風格問題；嚴重度：低
   `lib/ui/pages/library/downloaded_category_page.dart:489`、`lib/ui/pages/library/downloaded_category_page.dart:513`
   downloaded category 的單曲與展開分 P 列表建立 `_DownloadedTrackTile` 時沒有傳 `ValueKey`；多 P group 外層 `Column` 也沒有 stable key。這和 data 層「List/grid items should use stable identity keys」的規則不一致，且同頁資料來自檔案掃描、排序與分組結果，穩定 key 應以 `sourceType/sourceId/pageNum/cid/downloadPath` 組成。

4. 類型：重構機會；嚴重度：低
   `lib/ui/pages/library/playlist_detail_page.dart:1254`
   playlist detail 的 group header menu 手寫了「加入其他歌單」與「加入遠端收藏」等 common track action 項目，並在 `lib/ui/pages/library/playlist_detail_page.dart:1304`、`lib/ui/pages/library/playlist_detail_page.dart:1392` 自行 dispatch。單曲 tile 與多選 menu 已使用 `buildCommonTrackActionMenuItems()` / `TrackActionCoordinator`，group menu 可改成共用 helper 後再注入 `play_first`、`download_all`、`remove_all` 這些 group-specific action。

## Evidence

- 搜尋範圍：`rg -n "isLoading|RefreshIndicator|invalidate|ValueKey|TrackActionCoordinator|buildCommonTrackActionMenuItems|buildTrackActionPopupMenuEntries|FileExistsCache|fileExistsCacheProvider|Image\\.network|Image\\.file"` 覆蓋 `lib/ui/pages/library`、`lib/ui/pages/history` 與 playlist card actions。
- Loading empty guard：`lib/ui/pages/library/library_page.dart:116` 使用 `state.isLoading && displayPlaylists.isEmpty`；`lib/ui/pages/library/playlist_detail_page.dart:168` 只在 playlist 還沒載入時顯示整頁 spinner，`lib/ui/pages/library/playlist_detail_page.dart:195` 對 tracks 初載另有 guard。未在 library/playlist detail 發現單純 `if (state.isLoading)` 導致已有資料被 spinner 取代的問題。
- Optimistic update rollback：`lib/providers/playlist_provider.dart:417`、`:443`、`:471`、`:503` 先更新 state，catch 後在 `:436`、`:464`、`:496`、`:524` 呼叫 `loadPlaylist()` rollback。library reorder 也有測試 `test/ui/pages/library/library_page_reorder_test.dart:25`。
- ValueKey 正面證據：library grid 使用 `ValueKey(playlist.id)` 於 `lib/ui/pages/library/library_page.dart:190`、`:217`；playlist detail track tile 使用 `ValueKey('${track.groupKey}:${track.pageNum ?? 1}')` 於 `lib/ui/pages/library/playlist_detail_page.dart:356`、`:405`；history rows 使用 `ValueKey('history-date-...')` / `ValueKey('history-track-...')` 於 `lib/ui/pages/history/play_history_page.dart:419`；import preview alternative rows 使用 source/page/cid key 於 `lib/ui/pages/library/import_preview_page.dart:767`、`:922`。
- Refresh / invalidation：downloaded category 有明確刷新按鈕，`lib/ui/pages/library/downloaded_category_page.dart:144` invalidate `downloadedCategoryTracksProvider`；downloaded page sync 和 delete 走 `libraryInvalidationCoordinatorProvider.downloadStateChanged()`，見 `lib/ui/pages/library/downloaded_page.dart:44`、`:459`。依 `lib/ui/AGENTS.md`，downloaded/library flows 可用 explicit invalidation/buttons，不一定要 `RefreshIndicator`。
- `libraryInvalidationCoordinatorProvider`：playlist list/detail mutation 走 coordinator，見 `lib/providers/playlist_provider.dart:105`、`:139`、`:157`、`:430`、`:458`、`:490`；download completion 也由 provider wiring 走 coordinator，見 `lib/providers/download/download_providers.dart:59`、`:65`。
- Common track actions：history 單選/多選使用 menu helper 與 coordinator，見 `lib/ui/pages/history/play_history_page.dart:119`、`:838`、`:910`；downloaded category 單曲 menu 使用 helper/coordinator，見 `lib/ui/pages/library/downloaded_category_page.dart:852`、`:902`；playlist detail 單曲與多選使用 helper/coordinator，見 `lib/ui/pages/library/playlist_detail_page.dart:486`、`:539`、`:1573`、`:1674`。例外是 finding 4 的 group header。
- Image / local file loading：沒有在審查範圍找到直接 `Image.network()` / `Image.file()`。downloaded grid 與 downloaded category 使用 `ImageLoadingService.loadImage(... targetDisplaySize: ...)`，見 `lib/ui/pages/library/downloaded_page.dart:307`、`lib/ui/pages/library/downloaded_category_page.dart:396`、`:419`；相關 static test 在 `test/ui/static_rules/ui_consistency_static_rule_test.dart:50`。

## User impact

- Finding 1 會讓使用者在「已下載分類」刪掉單首歌後，playlist detail 或其他依賴 persisted downloadPath 的 UI 仍可能顯示已下載；如果 `FileExistsCache` 之前已記住該路徑存在，狀態還會更難即時修正。音樂播放器使用上會造成「明明刪了檔案，歌單還顯示可離線」的錯誤判斷。
- Finding 2 會在外部移動/刪除下載檔、同步尚未執行或單首刪除清理失敗時，顯示過期的下載 badge。這會影響使用者快速掃描哪些歌曲可離線播放。
- Finding 3 目前多數 row 是 stateless，短期風險較低；但在檔案掃描結果、分組展開或未來加入 row-local state 時，缺 key 會增加錯位重用與動畫/選中狀態錯亂風險。
- Finding 4 不一定造成現有功能錯誤，但 common action 流程分叉會讓後續新增遠端 action、toast 行為、partial success 處理或登入過濾時容易漏掉 group menu。

## Suggested direction

- 單首已下載刪除不要用掃描 Track 的 id 當 persisted id。復用 `DownloadPathMaintenanceService.deleteDownloadedTracks([track])`，或新增以 `sourceType/sourceId/cid/downloadPath` 匹配 persisted track 並清理 matching downloadPath 的 service method；完成後透過 `libraryInvalidationCoordinatorProvider.downloadStateChanged()` 傳回 `affectedPlaylistIds`，且檔案刪除成功時不要設 `fileExistsChanged: false`。
- playlist detail 的下載 badge 應在 DB downloadPath 非空後再經 `FileExistsCache` 判斷實際路徑存在。可在 page build 中 watch `fileExistsCacheProvider` 或細分 selector，預載 `track.allDownloadPaths`，然後以 `cache.exists(path)` gate `isDownloadedForPlaylist` 類顯示。
- downloaded category row key 建議使用 `ValueKey('${track.sourceType.name}:${track.sourceId}:${track.pageNum ?? track.cid ?? 0}:${track.allDownloadPaths.firstOrNull ?? ''}')`；group 外層用 `ValueKey('downloaded-group-${group.groupKey}')`。
- group header 的 common actions 可透過 `buildCommonTrackActionMenuItems(scope: TrackActionMenuScope.multi, ...)` 產生，再把 group-specific 的播放首 P、全部下載、從歌單移除附加到 menu；dispatch common action 時優先走 `TrackActionCoordinator.handleMulti()`。

## Instruction docs accuracy notes

- `AGENTS.md`、`lib/ui/AGENTS.md`、`lib/providers/AGENTS.md` 與目前程式碼大體一致：StateNotifier loading guard、playlist/detail invalidation coordinator、common track action helper、downloaded FutureProvider invalidate 都有實作證據。
- `.serena/memories/ui_coding_patterns.md` 對 AppBar spacing 與 UI constants 的說法比 `lib/ui/AGENTS.md` 更絕對；目前應以 `lib/ui/AGENTS.md` 為準，因為它允許 `PopupMenuButton` 結尾 spacer 視需求使用，也允許小型一次性 layout literal。
- `.serena/memories/download_system.md` 的 FileExistsCache 規則仍是有效補充；本次 finding 1/2 正是目前 UI 與該補充規則、`lib/ui/AGENTS.md` file existence cache pattern 之間的落差。
