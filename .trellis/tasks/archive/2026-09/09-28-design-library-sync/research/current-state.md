# 舊專案的音樂庫與同步（current state）

- 查證日期：2026-09-28
- 查證方式：讀 `docs/audit/`（`features.md` §3–§4、§13–§15；`data.md` §1–§2；`sources.md` §5；`errors.md` §2、§4）並以 `lib/` 程式碼逐條核對（`sed -n`／`grep -n` 直接讀原始碼，行號以查證當下的檔案為準）。**沒有**執行 App、**沒有**打真實 API、**沒有**跑 `flutter test`。
- 標記約定：沒有標記的敘述是我在程式碼裡直接讀到的事實；「推測」表示程式碼推得但未實跑確認；「查不到」表示在 `lib/`／`test/`／`tool/` grep 不到。

---

## 1. 資料模型

### 1.1 本地歌單與匯入歌單怎麼區分

**同一個 `Playlist` collection，靠 `sourceUrl != null` 區分，不是兩個型別。**

| 事實 | 證據 |
|---|---|
| `isImported` 是 getter：`sourceUrl != null` | `lib/data/models/playlist.dart:70` |
| 匯入歌單多帶 `importSourceType`（音源 id 字串）、`sourceUrl`、`lastRefreshed`、`useAuthForRefresh`、`ownerName`、`ownerUserId` | `lib/data/models/playlist.dart:24,27,33,45,39,42` |
| 本地歌單的 `sourceUrl` 為 null，其餘欄位共用 | 同上；新增本地歌單的建構子在 `lib/services/library/playlist_service.dart:125-130` |
| `refreshIntervalHours` 是「幾小時」而非排程表；null＝不啟用 | `lib/data/models/playlist.dart:30,76-83` |
| `needsRefresh` 是**會被 Isar 持久化的 getter**（沒標 `@ignore`），存下來的值只在 `put` 當下算過 | `docs/audit/data.md:§1.2`；`playlist.dart:76-83` |
| Mix 是第三種：`isMix`，只存元資料（不存 tracks），刷新直接跳過 | `playlist.dart:48-54`；`import_service.dart:418-427` |
| 名稱 `name` 有 **unique 索引**，同名歌單匯入時自動加 ` (2)`、` (3)` 後綴 | `playlist.dart:11-12`；`import_service.dart:249,645-660` |
| 匯入歌單在詳情頁有「已匯入」badge（本地歌單沒有） | `lib/ui/pages/library/playlist_detail_page.dart:748-760` |

### 1.2 曲目與歌單的關係、同一首歌出現在多張歌單

**沒有 IsarLink；`Playlist.trackIds` 是手動維護的整數陣列，反向關係存在 `Track.playlistInfo`。**

| 事實 | 證據 |
|---|---|
| `Playlist.trackIds: List<int>`（有序，指向 `Track.id`） | `lib/data/models/playlist.dart:57` |
| `Track.playlistInfo: List<PlaylistDownloadInfo>`，每筆是一個（playlistId, playlistName, downloadPath） | `lib/data/models/track.dart:10-34,53-55` |
| 同一首歌在多張歌單＝**同一列 `Track`**，`playlistInfo` 多筆、多個 `Playlist.trackIds` 各含它的 id | `playlist_mutation_repository.dart:765-799`（`_ensureSinglePlaylistInfo`）；`:620-659`（`mergeDuplicateTrackMembershipsInTxn`）；`:661-681`（`remapPlaylistTrackReferencesInTxn`） |
| 沒有任何 `IsarLink`／`IsarLinks`／`@Backlink` | `docs/audit/data.md:§1.2`（整份 lib grep 不到） |
| 參照完整性沒有 DB 層保證；`DataIntegrityRepository.scan/repair` 能修，但 `lib/` 裡唯一呼叫點是開發者選項「重設所有資料」 | `docs/audit/data.md:§1.2`；`docs/audit/features.md:§14` |
| 重複曲目以 `uniqueKey` 判定 | `docs/adr/0005` 後果節 |

### 1.3 曲目唯一鍵

| 事實 | 證據 |
|---|---|
| `TrackKey.format(sourceType, sourceId, {cid})` → 有 cid 三段式 `sourceType:sourceId:cid`，否則兩段式 | `lib/data/models/track_key.dart:19-20` |
| `Track.uniqueKey` 用 `format`，`groupKey` 永遠兩段式（同影片所有分 P 共用） | `lib/data/models/track.dart:344,341` |
| `Track.sourcePageKey` 是同一個字串，當 Isar 複合索引（`CompositeIndex('cid')`） | `track.dart:277-278` |
| B 站分 P：**每個分 P 一列 Track**，共用 `sourceId`（bvid），`cid` 不同；`pageNum` 只是顯示序號 | `docs/adr/0005`；`track.dart:260-266` |
| cid 是可空、且會被回填：搜尋／排行榜來的曲目先沒 cid，第一次解析串流時 `track.cid ??= streamResult.cid`，`uniqueKey` 從兩段式變三段式 | `docs/adr/0005`「鍵有兩種形狀」節 |
| 鍵是持久化格式，被 `LyricsMatch.trackUniqueKey`、`PlayHistory.trackKey`、備份 JSON 當外鍵 | `docs/adr/0005` 後果節；`lib/data/models/play_history.dart:47` |
| 其他會持久化的身分欄位：`originalSongId` / `originalSource`（外部平台來源 id） | `track.dart:254-263` |

### 1.4 曲目的其他狀態

| 狀態 | 怎麼存 | 證據 |
|---|---|---|
| 下載標記 | `Track.playlistInfo[].downloadPath`（空字串＝沒下載）＋獨立的 `DownloadTask` collection；**沒有**單一布林欄位 | `track.dart:10-34`；`docs/audit/data.md:§1.2` |
| 播放歷史 | 獨立的 `PlayHistory` collection，**快照當下的標題／歌手／時長／封面**，不參照 `Track.id`，只存 `trackKey` | `lib/data/models/play_history.dart:10-77` |
| 已失效曲目 | `Track.isAvailable` / `unavailableReason`。**目前唯一寫入點是建構時**：網易雲 `st != -200` | `lib/data/sources/netease_source.dart:710` |
| 失效標記的更新路徑 | `TrackRepository.markUnavailable(id, reason)` 存在，但 `lib/`、`test/`、`tool/` grep **零呼叫端**（死代碼） | `lib/data/repositories/track_repository.dart:325-331` |
| 收藏／喜歡曲目 | **查不到**。沒有 track 層的 favorite。唯一 `isFavorite` 在 `RadioStation`（且無 UI 入口） | `lib/data/models/radio_station.dart:50`；`docs/audit/features.md:§14` |
| 孤兒曲目清理 | 啟動 10 秒後刪「`playlistInfo` 所有項目的 playlistId 都 <= 0 且不在佇列」的 Track；**不刪 `LyricsMatch`**（保留使用者手動挑的歌詞與 offset） | `lib/services/audio/queue_manager.dart:219-229`；`lib/data/repositories/track_repository.dart:634-673` |

**代價**：孤兒清理只看 `playlistInfo`，而 `playlistInfo` 是手動維護的。`docs/adr/0010` 背景節記載這造成過資料遺失（下載同步重建關聯時對不上就丟，接著孤兒清理把曲目刪掉）。

---

## 2. 匯入流程

### 2.1 三條入口

| 入口 | 走的路 | 證據 |
|---|---|---|
| URL 匯入 B 站收藏夾／YouTube 播放清單／網易雲歌單 | `import_playlist_dialog` → `SourceManager.playlistParsingSourceForUrl` 認得 → `ImportService.importFromUrl` | `lib/ui/pages/library/widgets/import_playlist_dialog.dart:159-176`；`import_service.dart:156-330` |
| URL 匯入 QQ／Spotify 歌單 | 認不得 → `PlaylistImportService.detectSource` → 逐首搜尋比對 → 匯入預覽頁 | `import_playlist_dialog.dart:171-176`；`lib/services/import/playlist_import_service.dart` |
| 帳號歌單／電台匯入 | 帳號管理頁「管理歌單」，走 `ImportService.importFromUrl` 並帶 `useAuth=true` | `lib/ui/pages/settings/widgets/account_playlists_sheet.dart:277`；`docs/audit/features.md:§4` |

### 2.2 `importFromUrl` 的建立／更新

- 解析 URL → 取 `PlaylistParseResult`（title／description／coverUrl／tracks／totalCount／ownerName／ownerUserId）→ 若是多 P 音源先展開分 P → 建或更新 `Playlist` → `addTracks` → 更新封面 → 寫 `lastRefreshed`。`import_service.dart:156-330`。
- **更新既有歌單時刻意不覆寫 `name`、`description`**：更新分支只設 `importSourceType`、`ownerName`、`ownerUserId`、`useAuthForRefresh`、`refreshIntervalHours`、`notifyOnUpdate`、`updatedAt`（`import_service.dart:244-256`）。所以本地改過的名稱與描述在**重新匯入**時存活。
- 但 `useAuthForRefresh` 與 `refreshIntervalHours` 會被這次呼叫的參數覆寫 —— 這正是 `questions.md` M12 說的「『使用登入狀態重新整理』會被重新匯入覆寫」。
- 封面：`_updatePlaylistCover` 開頭 `if (playlist.hasCustomCover) return;`，沒自訂封面就用平台封面、否則退回第一首歌的縮圖、歌單空則清成 null（`import_service.dart:629-646`）。`hasCustomCover` 由 `updatePlaylist` 依「這次有沒有傳非空 coverUrl」設定（`playlist_service.dart:197-206`）。
- B 站收藏夾的解析是**逐頁抓**（`ps=pageSize`、算 `totalPages`、每頁之間 `networkRetryDelay` 延遲），只有第一頁帶 `media_count` 當 `totalCount`（`lib/data/sources/bilibili_source.dart:535-645`）。網易雲是 `playlist/detail` 取 trackIds 後**分批抓詳情**（`netease_source.dart:258-326`、`:493-496`）。

### 2.3 刷新流程（`refreshPlaylist`）

入口有兩個：手動（歌單卡「刷新」，`playlist_card_actions.dart:253-255`）與自動（`AutoRefreshService`）。兩者都走 `RefreshManagerNotifier.refreshPlaylist` → `ImportService.refreshPlaylist(playlistId)`（`lib/providers/library/refresh_provider.dart:124-266`；`import_service.dart:406-556`）。

差異計算是**整批集合運算，不是逐項 diff**，全部在一個 Isar 交易裡：

`PlaylistMutationRepository.replaceTracksFromRemoteRefresh(playlistId, refreshedTracks, policy)`（`lib/data/repositories/playlist_mutation_repository.dart:427-605`）：

1. 先依 `uniqueKey` 去掉遠端回傳清單裡的重複（`:432`、`_dedupeTracksByUniqueKey`）。
2. `_isar.writeTxn(...)` 包住整段（`:434`）。
3. 以 `TrackSourceIdentity` 查既有曲目（`:456`、`_findTracksByIdentity` → `track_repository.getBySourceIdentities`）。
4. 逐首：
   - **新增**：既有清單查不到 → `tracks.putAll` 新增，記 `addedTrackIds`（`:483-486,537-538`）。
   - **元資料更新**：`_mergeTrackMetadataIfNeeded`（`:725-763`）只補**缺少的**欄位 —— `audioUrl`（既有 URL 失效才覆寫）、`thumbnailUrl`、`durationMs`、`artist`、`originalSongId`、`originalSource`。**`title` 不在其中**：遠端改標題不會同步下來。記 `updatedTrackIds`。
   - **成員修復**：`_ensureSinglePlaylistInfo` 修正這首歌在這個歌單的 `playlistInfo` 項（`:469-473`、`:765-799`）。
   - **不變**：記 `skippedTrackIds`。
5. **順序**：遠端清單的順序直接覆寫 `playlist.trackIds`（`:593`）—— 這是唯一的順序來源，沒有本地排序概念。
6. **刪除**：只有在 `canPruneRemovedTracks = policy.sourceDataComplete && errors.isEmpty` 時才真的刪（`:531-532`）。刪除會 `removeFromPlaylist`；`playlistInfo` 空了就 `tracks.deleteAll` 刪掉那一列 Track，否則只更新（`:560-591`）。
7. **資料不完整時不刪**：`sourceDataComplete=false` 時走 `_mergePreservingExistingTrackOrder`（`:841-873`）—— 既有曲目一首不刪、順序不動，遠端新曲目插在「遠端順序裡排在它後面的第一首既有曲目」之前。回傳 `pruningSkipped=true`。
8. 封面：`_updateRefreshCover`（`:820-840`）優先用平台封面，沒有才退回第一首歌縮圖；`hasCustomCover` 為真就完全不動。

`sourceDataComplete` 的判定在 `import_service.dart:469-471`：分 P 展開完整（`expansion.isComplete`）**且**（`totalCount <= 0` 或 抓到的首數 >= totalCount）。也就是說**中途任何一頁抓失敗都會讓這次刷新變成「只增不刪」**。

刷新成敗的呈現：成功 toast 顯示「新增 N 首／移除 N 首／N 首未變」「${name} 刷新完成！」（`lib/i18n/en/refreshProvider.i18n.json`；`refresh_provider.dart:204-218`）。失敗 toast「${name} 刷新失敗：${error}」（`refresh_provider.dart:243-247`）。

### 2.4 遠端歌單被刪或變私人

- **沒有任何「遠端歌單已消失」的處理。** 刷新時 `parsePlaylist` 直接拋：B 站 `_checkResponse` 把 -101/-111/-403/-607/11010/11201 映射成字串（11010 = `t.remote.error.contentNotFound`「內容不存在」），其餘「操作失敗 (code)」（`lib/services/account/bilibili_favorites_service.dart:247-279`）。YouTube 用伺服器原文（`youtube_playlist_service.dart:716-721`）。網易雲用 `data['message']`（`netease_playlist_service.dart:297-308`）。
- 結果是 `refreshPlaylist` 拋出 → `RefreshManagerNotifier` 顯示 error toast → **本地歌單原封不動留著舊曲目**，`playlist` 沒有任何「已失效／遠端已刪」欄位，`needsRefresh` 仍為真，下次排程再試一次。
- 認不出 URL 也會拋（`import_service.dart:438-440`、`:481-483`）。
- **注意**：`ImportException` 的訊息已經是翻譯好的字串，但 `user_messageFor` 不認這個型別，會被壓成通用「發生錯誤」（`docs/audit/errors.md:§4.3` 第 1 點）。內部匯入顯示 `ImportException` 自己的文案，刷新路徑則經 `failureMessage`（`refresh_provider.dart:229-234`）。**推測**：實際 toast 文案會是通用錯誤句而非「內容不存在」。

### 2.5 自動刷新

| 事實 | 證據 |
|---|---|
| 每 30 分鐘檢查一次（類別註解誤寫「每小時」） | `lib/services/library/auto_refresh_service.dart:40-44`；`app_constants.dart:151` |
| 服務 provider 一被建立就 `start()`，且**立刻檢查一次** | `auto_refresh_service.dart:143-158` |
| 一次只刷一個歌單，刷完固定等 5 秒再下一個 | `auto_refresh_service.dart:86-116` |
| 候選排序：`needsRefresh` 為真者，`lastRefreshed` 最舊優先（null 最優先） | `auto_refresh_service.dart:69-81` |
| 不看前景／背景，app 開著就跑（唯一例外是電台輪詢會因生命週期暫停） | `docs/audit/features.md:§13.2` |
| 個別歌單間隔：`create_playlist_dialog.dart:61` 顯示新建預設；`Playlist.needsRefresh` 用 `refreshIntervalHours` | `playlist.dart:76-83` |

**ADR 0017 的變更點（重寫版）**：舊版是 30 分鐘的固定輪詢 + 每張歌單各自的「到期」判斷；新版是單一排程器、只在可見且在線時跑、到期補跑，間隔改為 1／6／12／24／48／72／168 小時或不啟用。

---

## 3. 遠端操作（B1「從遠程播放列表移除」、B2「加入遠端歌單」）

### 3.1 三個 adapter 與分派

`RemotePlaylistEditController` 以 `sourceType` 為鍵查 adapter；**查不到就回報整批失敗，刻意不 fallback**（避免把歌加到／刪掉另一個平台的歌單）。`lib/services/library/remote_playlist_edit_controller.dart:23-38,96-99,176-200`。三個 adapter 在 `lib/providers/library/remote_playlist_sync_provider.dart:39-77` 組裝。

- **B 站**：`getVideoAid` → `updateVideoFavorites(addFolderIds/removeFolderIds)`（`remote_playlist_edit_controller.dart:225-301`）。
- **YouTube**：加入用 `addToPlaylist(playlistId, videoId)`；移除要先 `getSetVideoId` 拿 **setVideoId**，拿不到就記為 skipped（`:310-360`）。
- **網易雲**：批次加入／移除 `trackIds`（`:367-428`）。

### 3.2 B1：從遠程播放列表移除

| 事實 | 證據 |
|---|---|
| 入口只在**匯入歌單**詳情頁：單曲紅色「從遠程播放列表移除」、多選同名項 | `lib/ui/pages/library/playlist_detail_page.dart:1502-1507,209-210` |
| 匯入歌單**沒有**本地「從歌單移除」；`remove_all` 也只有非匯入歌單有 | `playlist_detail_page.dart:1509-1514,1287-1294` |
| 確認框：標題「確定要從遠程播放列表中移除嗎？」、內容「同時會從本地歌單中移除。」，用 destructive 樣式 | `lib/i18n/zh-TW/remote.i18n.json`；`playlist_detail_page.dart:565-573`（批次）、`:1566-1582`（單曲） |
| 失敗處理三分支：遠端成功但本地同步失敗 → warning「已從遠程播放列表移除，但本地歌單同步失敗」；純失敗 → 第一筆誤的錯誤訊息；無變更 → 「沒有變更」 | `playlist_detail_page.dart:586-614`；`lib/services/library/remote_playlist_edit_controller.dart:101-128` |
| 成功後：先寫遠端 → 用 `confirmedRemovedTrackIds` 刪本地 → 再呼叫 `refreshMatchingImportedPlaylists`（背景刷新對應的本機匯入歌單，fire-and-forget，失敗只 log） | `remote_playlist_edit_controller.dart:101-143` |
| 「哪張本機歌單對應這個遠端 id」＝用 `RemotePlaylistIdParser.parse(sourceType, sourceUrl)` 比對 | `lib/services/library/remote_playlist_sync_service.dart:30-50` |

### 3.3 B2：加入遠端歌單

| 事實 | 證據 |
|---|---|
| 入口：曲目選單「加入遠端」、播放頁「加入歌單→遠端」、多選 | `lib/ui/handlers/track_action_handler.dart:218-235,298-311` |
| 未登入的來源被**過濾掉**（不是擋整批），並 toast「已跳過未登錄的 $platforms」 | `track_action_handler.dart:218-235`；`lib/services/library/remote_playlist_edit_planner.dart:55-64` |
| **沒有確認框**：勾選要加入的歌單／收藏夾 → 送出。按鈕文字只在「僅有新增、沒有移除」時顯示「添加到 N 個」，其餘顯示「確認」 | `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:195-256`；`lib/ui/widgets/dialogs/remote_playlist_dialog_widgets.dart:408-420` |
| 對話框可新建歌單／收藏夾（B 站 `folder/add`、YouTube `playlist/create`、網易雲 `playlist/create`） | `docs/audit/features.md:§3`、§15.1 |
| 送出前先比對「該遠端歌單已有哪些 `sourceId`」，已在的不重複加 | `remote_playlist_edit_planner.dart:30-40`；`remote_playlist_edit_controller.dart:244-257,430-438` |
| 結果呈現：部分成功 → warning「部分完成 N/M」；全成功 → 「已更新收藏」；全失敗 → 第一筆錯誤；無變更 → 「沒有變更」 | `remote_playlist_dialog_widgets.dart:373-406` |
| 成功後同樣觸發對應本機匯入歌單的背景刷新 | `remote_playlist_edit_controller.dart:129-143` |

### 3.4 與本地歌單的互斥

- 「加入歌單（本地）」對話框**只列非匯入歌單**（`lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:96-101,252-256`）。
- 匯入歌單在詳情頁不能加曲目、不能刪曲目、不能重排；只能改名稱／描述／封面與自動刷新設定（`lib/ui/pages/library/widgets/create_playlist_dialog.dart:118-130,448-465`）。

---

## 4. Spotify／QQ 匯入的匹配流程

### 4.1 演算法（自動）

`PlaylistImportService.importAndMatch`（`lib/services/import/playlist_import_service.dart`）：

| 步驟 | 事實 | 證據 |
|---|---|---|
| 取歌單 | 第一個 `canHandle(url)` 的 `PlaylistImportSource.fetchPlaylist`；實作只有 `QQMusicPlaylistSource`、`SpotifyPlaylistSource` | `:137`；`lib/data/sources/playlist_import/playlist_import_source.dart:95-125` |
| 逐首搜尋 | **序列**執行，每首之間固定延遲：`all` 1000ms、單源 800ms | `:277-285`；`app_constants.dart:83-88` |
| 查詢字串 | `"$title ${artists.join(' ')}"` | `playlist_import_source.dart:28` |
| 取幾筆 | `maxResults × 8`，預設 `5 × 8 = 40` | `:153,312` |
| 搜尋來源 | `all`：並行搜 YouTube 與 Bilibili，單源失敗只 log；**網易雲不在內**。`bilibiliOnly`／`youtubeOnly`：單源，失敗直接拋、該首記 noResult | `:314-351,264-272` |
| 評分 | `_calculateRelevanceScore`：時長先過濾（`< -50` 直接回 -100）；基礎分＝標題相似度 ×0.35 ＋ 歌手相似度 ×0.25 ＋ 播放量 ×0.15 ＋ 組合分 ×0.15；再加精確匹配／頻道與歌手／官方頻道／標題關鍵字／時長／版本／括號內歌名等加分 | `:443-535` |
| 相似度 | N-gram 與 Jaccard 取高者 | `:1044-1075` |
| 排序 | 過濾分數 < 0，取前 5，第一名自動選為 `selectedTrack`，狀態 `matched` | `:354-372,250-258` |
| 候選保留 | `MatchedTrack.searchResults` 保留最多 5 筆候選 | `playlist_import_source.dart:60-66` |
| 原平台 id | 建歌單時寫進 `Track.originalSongId` / `originalSource`（`'netease'\|'qqmusic'\|'spotify'`），供歌詞直取 | `:65-79,119-126` |

### 4.2 失敗與手動改選

| 事實 | 證據 |
|---|---|
| 狀態機：`pending / searching / matched / noResult / userSelected / excluded` | `playlist_import_source.dart:45-53` |
| 未匹配的曲目集中顯示在預覽頁的 `_UnmatchedSection`，可逐首重搜 | `lib/ui/pages/library/import_preview_page.dart:330-466` |
| 已匹配的可展開看候選（`_AlternativeTrackTile`）並改選；改選後狀態 `userSelected`、可勾選是否納入 | `import_preview_page.dart:811-960,960-1090`；`lib/providers/library/playlist_import_provider.dart:299-310` |
| 結果持久化＝寫成一般的 `Track`（帶 `originalSongId`），**沒有獨立的匹配紀錄表**，所以不會重算 | `playlist_import_service.dart:65-79` |

### 4.3 與歌詞匹配是不是兩套評分

**是兩套，各自獨立的評分與門檻。**

| 面向 | 歌單匯入 | 歌詞自動匹配 |
|---|---|---|
| 演算法位置 | `playlist_import_service.dart:443-535` | `lib/services/lyrics/lyrics_auto_match_service.dart:819-895` |
| 標題比對 | N-gram／Jaccard 取高 | Levenshtein |
| 權重 | 標題 0.35 / 歌手 0.25 / 播放量 0.15 / 組合 0.15 ＋多項加分 | 標題 0.4 / 歌手 0.3 / 時長 0.2 / 有同步歌詞 0.1 |
| 時長 | 差值評分表（≤10 秒 +20；>200% -100） | 差值分級（≤3 秒 1.0、≤10 秒 0.8、≤20 秒 0.5） |
| 門檻 | 過濾 < 0、取前 5、第一名自動選 | 最高分 ≥ 0.6 才採用 |
| 手動重搜 | `searchForTrack`：搜**全部已註冊音源（含網易雲）**、**只依播放量排序、不打分** | 手動搜尋走 `LyricsProvider`，與自動匹配不同的路徑 |

手動重搜與自動匹配不一致：`playlist_import_service.dart:1156-1201`。

---

## 5. 重寫時值得注意的落差（事實，不是建議）

1. **「遠端是權威」在舊版已經成立**（匯入歌單不能本地增刪、刷新以遠端覆寫順序），但**只在遠端資料完整時才刪除**（`sourceDataComplete`），其餘情況靜默變成「只增不刪」並回報 `pruningSkipped`。UI **不顯示** `pruningSkipped`（`refresh_provider.dart` 的 toast 只組 added／removed／skipped）。
2. **`title` 不會被刷新更新**（`_mergeTrackMetadataIfNeeded` 不含 title），**`description` 只在首次匯入寫入**，之後遠端改描述不會同步下來。
3. **遠端歌單消失／變私人沒有任何狀態**：只有一次 error toast，本地副本照舊、排程繼續重試。
4. **沒有「已失效」的維護路徑**：`TrackRepository.markUnavailable` 零呼叫端；`isAvailable` 只在網易雲建構時判定一次。
5. **沒有 track 層的收藏／喜歡**，舊版的「音樂庫」只有：本機歌單、匯入歌單、下載、播放歷史、佇列。
6. **匹配結果沒有獨立持久層**：舊版的「不再重算」是靠寫成普通 `Track` 達成，代價是沒有「這首是匹配來的、原始平台 id 是什麼」以外的資訊（`originalSongId` / `originalSource` 有存）。
7. **匯入歌單的遠端寫入沒有確認框（加入）／有確認框（移除）**：與擁有者「保留 App 內明確標示的遠端操作」一致，但加入方向目前沒有二次確認。
