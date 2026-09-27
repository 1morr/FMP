# Prior art：成熟產品怎麼處理「匯入的外部歌單」

- 查證日期：2026-09-28
- 查證方式：`gh` CLI（`gh api repos/<owner>/<repo>`、`/commits/<branch>`、`/git/trees/<sha>?recursive=1`、`/contents/<path>?ref=<sha>`）讀取公開 repo 的程式碼與 git 物件；部分檔案以 base64 解碼後在本機 grep 行號。沒有使用 WebSearch、tavily-extract 或 WebFetch（所有事實都能在原始碼中找到，且原始碼比文件精確）。所有程式碼連結都固定到查證當下的 commit SHA。
- 查證範圍：Spotube、Namida、MusicFree、Finamp（legacy 與 redesign 兩條分支）、LX Music（desktop）。共 5 個產品。

## 摘要對照表

| 產品 | 匯入歌單是唯讀鏡像或可編輯副本 | 差異比對方式 | 遠端刪除的處理 | 另存本機歌單 | 寫回前確認 | 匹配 UX |
|---|---|---|---|---|---|---|
| Spotube | 兩者皆非：**無本地副本**，純遠端視圖（drift schema 沒有歌單表） | 不適用（每次進頁面即時抓） | 不適用（無副本可刪） | 查不到 | 有加入曲目的 dialog；移除是否確認查不到 | 只在播放來源層做逐曲 id 快取（`source_match_table`），不暴露信心分數 |
| Namida | 帳號歌單＝遠端即時視圖；App 內建的 YT 歌單與本地歌單才是本地物件 | 本地歌單靠 `PlaylistAddDuplicateAction` 處理重複；遠端歌單無本地鏡像故無差異比對 | 查不到（帳號歌單 live 抓取，遠端刪除自然消失） | 無「轉成本地歌單」；但加入曲目時 local / youtube 兩 tab 分流 | **有**：從遠端歌單移除前跳「確定移除？」 | 不跨平台匹配（整條路都在 YouTube 內） |
| MusicFree | **可編輯的本地副本**：匯入即複製成一份普通本地歌單 | 無（匯入後與來源完全脫鉤） | 不適用（無連結） | 匯入本身就是另存本地 | **有**：匯入前「找到 N 首，要匯入嗎？」 | 由外掛負責，App 只收一份曲目陣列；失敗＝空陣列 →「無效連結」；無信心分數、無人工修正 UI |
| Finamp（legacy） | **唯讀鏡像**（下載副本），伺服器為準 | **id 集合差集**：`toAdd` / `toRemove` / `toUpdate`，先刪後載 | **自動刪除本地檔案，無確認**（同一首歌被別的 parent 需要時不刪） | 查不到 | 同步不是寫回；移除是寫回的一種，也無確認 | 不適用（Jellyfin item id 直接對應） |
| LX Music（desktop） | 不適用：無平台帳號，歌單一律本地 | 裝置對裝置同步自建歌單（list）與不喜歡清單（dislike），非外部平台匯入 | 不適用 | 不適用 | 不適用 | 不適用 |

---

## Spotube

- repo：`team-spotube/spotube`（原 `KRTirtho/spotube`，已改名；`gh api repos/KRTirtho/spotube` 會 redirect）
- 查證 commit：`69a310c78f5ceaf4eab7dfee98f187d38211c9ba`（`master`，committer date 2026-06-05）

### 匯入歌單的模型

**沒有本地副本。** 我讀了 drift schema 的 v10 完整實體清單
（[`drift_schemas/app_db/drift_schema_v10.json`](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/drift_schemas/app_db/drift_schema_v10.json)），
全部 10 張表是：

```
authentication_table, blacklist_table, preferences_table, scrobbler_table,
skip_segment_table, source_match_table, audio_player_state_table,
history_table, lyrics_table, plugins_table
```

沒有 playlist 表、沒有 playlist↔track 關聯表。歌單內容一律透過 metadata plugin
（Spotify / YouTube Music 的 Hetu script 外掛）向平台要，因此「匯入的歌單」與
「平台上建立的原生歌單」在資料層是同一個東西，沒有本地鏡像可言：

- 讀取走 [`MetadataPluginPlaylistEndpoint.getPlaylist` / `tracks`](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/metadata/endpoints/playlist.dart#L13-L33)
- 編輯走 [`addTracks` / `removeTracks`](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/metadata/endpoints/playlist.dart#L87-L113)
- `create` / `update` / `save` / `unsave` / `deletePlaylist` 是同一組遠端操作
  （[`playlist.dart#L43-L131`](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/metadata/endpoints/playlist.dart#L43-L131)）

呼叫端是 Riverpod 的 `MetadataPluginPlaylistNotifier`，`create` / `modify` /
`addTracks` / `removeTracks` 全部直接呼叫 plugin 後 `ref.invalidateSelf()`
（[`lib/provider/metadata_plugin/playlist/playlist.dart#L60-L140`](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/metadata_plugin/playlist/playlist.dart#L60-L140)）。

### 刷新與差異比對

不適用：沒有本地副本，就沒有差異比對；每次進歌單頁重新向平台抓。

本地唯一的逐曲持久化是 **播放來源匹配快取**，不是歌單同步：
`source_match_table`（欄位 `track_id, source_info, source_type`）。這是
Spotube「Spotify 曲目 → 可用播放來源」的比對結果快取，見
[`lib/models/database/tables/source_match.dart`](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/models/database/tables/source_match.dart)
與 [`lib/provider/server/active_track_sources.dart`](https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/server/active_track_sources.dart)。

### 刪除、本地修改的保留

不適用（沒有本地副本可被遠端刪除影響）。

### 寫回平台

寫回就是唯一的編輯途徑（`addTracks` / `removeTracks` / `update`），沒有本地暫存後再推送的流程。

### 匹配 UX

Spotube 解決的是「Spotify 曲目 → 可播放來源」而不是「歌單轉換」，逐曲快取在本地，
但**沒有**信心分數、候選清單或人工修正的介面暴露給使用者（依 `source_match.dart`
的欄位形狀判斷；未逐行驗證 UI 層是否另有候選選擇器 → **推測**）。

### 來源清單

- https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/drift_schemas/app_db/drift_schema_v10.json
- https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/services/metadata/endpoints/playlist.dart#L13-L131
- https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/metadata_plugin/playlist/playlist.dart#L60-L140
- https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/models/database/tables/source_match.dart

---

## Namida

- repo：`namidaco/namida`
- 查證 commit：`e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5`（`main`，committer date 2026-09-26）

### 匯入歌單的模型

Namida 有兩類歌單，語意不同：

1. **App 內建立的歌單**（含以 YouTube 曲目為成員的「YT 歌單」）：本地物件，
   由 `PlaylistManager` 管理。
   [`YoutubePlaylistController extends PlaylistManager<YoutubeID, String, YTSortType>`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/controller/youtube_playlist_controller.dart#L27-L36)，
   `identifyBy(item) => item.id`（用 YouTube video id 當身分鍵）。
2. **YouTube 帳號上的歌單**：**遠端即時視圖**，不落地。
   `youtube_user_playlists_page.dart` 走
   [`youtube_main_page_fetcher_acc_base`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/pages/youtube_user_playlists_page.dart#L18-L20)
   從帳號抓，編輯則透過 `YtUtilsPlaylist.promptCreatePlaylist` /
   `promptEditPlaylist` 直接對 YouTube 下 API；`promptEditPlaylist` 的註解寫明
   「we prefer always loading live info for better cross-device sync」
   （[`lib/youtube/functions/yt_playlist_utils.dart`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/functions/yt_playlist_utils.dart#L52-L62)）。

**關鍵：我沒有在程式碼裡找到「把遠端 YouTube 歌單匯入成 Namida 本地歌單」這個動作。**
有的是「下載歌單」（`lib/youtube/pages/yt_playlist_download_subpage.dart`，把曲目抓成本地檔案）
與「把曲目加入歌單」時 local / remote 兩個 tab。→ 這一項標「查不到」。

### 刷新與差異比對

- 本地歌單：靠 `PlaylistAddDuplicateAction` 處理重複，寫入後跳 undo snackbar
  （[`youtube_playlist_controller.dart#L65-L96`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/controller/youtube_playlist_controller.dart#L65-L96)）。
- 遠端帳號歌單：無本地鏡像，因此**沒有差異比對**；每次進頁面重新抓。

### 刪除、本地修改的保留

查不到。遠端帳號歌單因為是 live 抓取，遠端刪除後自然不再出現；本地歌單不受影響
（**推測**，未逐行驗證是否有 tombstone 或快取）。

### 另存成本地歌單

沒有「把遠端歌單一鍵轉成本地歌單」的功能。最接近的是加入曲目時的分流 UI：
同一個 bottom sheet 有 `lang.local` / `lang.youtube` 兩個 tab
（[`lib/youtube/functions/add_to_playlist_sheet.dart#L97`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/functions/add_to_playlist_sheet.dart#L97)），
使用者直接選擇寫到本地或寫到遠端。

### 寫回平台

UI 是 `add_to_playlist_sheet.dart`；實際寫入呼叫
`YoutiPie.playlistAction.addRemoveVideosInPlaylist(...)`
（[`#L247-L284`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/functions/add_to_playlist_sheet.dart#L247-L284)）。

**寫回前確認**：

- **移除**遠端歌單曲目 → `_confirmRemoveVideos()` 跳「確定移除？」對話框
  （[`#L224-L245`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/functions/add_to_playlist_sheet.dart#L224-L245)）。
- **加入**遠端歌單 → 沒有二次確認，只有重複曲目的處理選項
  （`showDuplicatedDialogAction`）。

寫入回傳值是 `bool done`，失敗處理我沒讀到完整的錯誤路徑 → 查不到細節。

### 匹配 UX

不適用：Namida 的歌單轉換不跨平台，整條路都在 YouTube 內。

### 來源清單

- https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/controller/youtube_playlist_controller.dart#L27-L96
- https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/functions/add_to_playlist_sheet.dart#L97-L336
- https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/functions/yt_playlist_utils.dart#L52-L62
- https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/youtube/pages/youtube_user_playlists_page.dart

---

## MusicFree

- repo：`maotoumao/MusicFree`
- 查證 commit：`d118b18b3d0c904400f7eea7bf99c0ceec6c1aee`（`master`，committer date 2026-06-20）

### 匯入歌單的模型

**可編輯的本地副本，而且是「匯入即複製」的一次性動作。**

歌單（MusicSheet）一律是本地物件，核心在
[`src/core/musicSheet/index.ts`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/musicSheet/index.ts)，
以 MMKV 持久化（同目錄 `storage.ts`、`sortedMusicList.ts`）。
預設歌單是 `{ id: "favorite", platform: localPluginPlatform, title: "我喜欢" }`。

匯入外部歌單靠外掛宣告的 `importMusicSheet` 能力：

```ts
const validPlugins = PluginManager.getSortedPluginsWithAbility("importMusicSheet");
```

[`importMusicSheet.tsx#L19`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/components/panels/types/importMusicSheet.tsx#L19)

流程：貼上連結 → `plugin.methods.importMusicSheet(text)` 回傳
`IMusic.IMusicItem[]` → **這份陣列就是本地歌單的內容**，之後與來源平台再無關聯。

### 刷新與差異比對

**沒有。** 匯入後就是一份普通本地歌單，跟「我喜歡」同等；沒有 re-sync、
沒有刷新按鈕、沒有 TTL。程式碼裡看不到任何「來源歌單 id ↔ 本地歌單」的連結欄位
（`IMusic.IMusicSheetItemBase` 只有 `id / platform / coverImg / title / worksNum`）。

### 刪除、本地修改的保留

不適用：無連結，本地增刪改完全自由。

### 另存成本地歌單

匯入流程本身就是「另存成本地歌單」：

```ts
showDialog("SimpleDialog", {
  title: t("panel.importMusicSheet.prepareImport"),
  content: t("panel.importMusicSheet.foundSongs", { count: result.length }),
  onOk() { showPanel("AddToMusicSheet", { musicItem: result }); },
})
```

[`importMusicSheet.tsx#L58-L80`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/components/panels/types/importMusicSheet.tsx#L58-L80)

`AddToMusicSheet` 面板再讓使用者選「加到既有歌單」或「新建歌單」
（[`addToMusicSheet.tsx`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/components/panels/types/addToMusicSheet.tsx)）。

### 寫回平台

不存在。本地歌單沒有遠端對應物件。

### 匹配 UX

匹配完全由外掛負責，App 只收一份已經定案的曲目陣列。
**失敗的呈現**：`result.length === 0` → `Toast.warn(t("panel.importMusicSheet.invalidLink"))`
（[`#L72-L77`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/components/panels/types/importMusicSheet.tsx#L72-L77)）。
沒有信心分數、沒有候選清單、App 層沒有逐曲人工修正。

### 自動刷新間隔 / 離線行為

不適用（無連結、無刷新）。

### 來源清單

- https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/components/panels/types/importMusicSheet.tsx#L19-L87
- https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/components/panels/types/addToMusicSheet.tsx
- https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/musicSheet/index.ts

---

## Finamp

- repo：`finamp-app/finamp`（Jellyfin 音樂客戶端）
- 查證 commit：
  - `legacy` 分支 `f49ba47f491fbaf3aeeb67540e8cc788ad2cd307`（committer date 2026-08-10）— 有完整下載／同步實作
  - `redesign` 分支 `0aae9d5ed530ffdf3d62ab12dab4f475a67687dc`（committer date 2026-09-26）— 重寫版
- 注意：`jellyfin/Finamp` 已 404，現址是 `finamp-app/finamp`。

### 匯入歌單的模型

**唯讀鏡像。** Finamp 的「匯入」就是「下載歌單」：把 Jellyfin 伺服器上某個
playlist 的曲目下載到本地，本地集合是伺服器集合的鏡像，**伺服器為準**。
`DOWNLOADS_PLAN.md` 也把 playlist 歸類為 download parent（與 album 同級）：

> `DownloadedParents` - stores data about parents (albums, playlists), with links to children.

[`DOWNLOADS_PLAN.md`](https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/DOWNLOADS_PLAN.md)

### 刷新與差異比對

**依 Jellyfin item id 做 id 集合的差集**，這是整份研究裡最明確的差異比對實作。
`_getSyncState` 建兩個集合——「歌單現在的曲目 id」與「本地已下載且
`requiredBy` 含這個 parent 的曲目 id」——然後回傳三組：

```dart
Set<String> playlistIds = playlistItems.map((e) => e.id).toSet();
Set<String> downloadedIds =
    downloadedSongsCache.map((e) => e.mediaSourceInfo.id!).toSet();
return SyncState(
    playlistIds.difference(downloadedIds),      // toAdd
    downloadedIds.difference(playlistIds),      // toRemove
    playlistIds.intersection(downloadedIds),    // toUpdate
    playlistItems);
```

[`lib/services/sync_helper.dart#L108-L143`](https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/lib/services/sync_helper.dart#L108-L143)

`sync()` 的順序是**先刪後載**：

```dart
await _removeDownloadedItems(parentObject.id, syncState.toRemove);
await _downloadItems(context, parentObject, syncState);
```

[`#L35-L49`](https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/lib/services/sync_helper.dart#L35-L49)；
`toAdd` 與 `toUpdate` 都會進下載佇列，註解寫明理由是
`// we include update items in case any items have been orphaned`
（[`#L52-L80`](https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/lib/services/sync_helper.dart#L52-L80)）。

**保留本地修改的機制**：沒有。本地沒有可修改的欄位，鏡像的唯一狀態就是「有沒有下載」。

### 遠端刪掉的曲目在本地怎麼處理

**自動刪除本地檔案，沒有確認、沒有痕跡。** `toRemove` 直接丟進
`deleteDownloadChildren(jellyfinItemIds: ..., deletedFor: playlistParentId)`，
之後若該 parent 已無子項就一併 `deleteDownloadParent`
（[`#L91-L107`](https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/lib/services/sync_helper.dart#L91-L107)）。

`deletedFor` 這個參數配上 `DownloadedSong.requiredBy` 是 list，暗示
「同一首歌還被別的 album/playlist 需要時不該被刪」；我沒有逐行驗證
`deleteDownloadChildren` 的實作 → **推測**。

### 另存成本地歌單

查不到。Finamp 的本地單位是 download parent（album / playlist 的下載副本），
不是使用者可自由編輯的歌單。

### 寫回平台

**同步不是寫回，它只下載**；寫回 Jellyfin 的編輯在 redesign 分支的
`lib/screens/playlist_edit_screen.dart`、`lib/menus/components/menuEntries/remove_from_current_playlist_menu_entry.dart`、
`lib/components/AlbumScreen/playlist_edit_button.dart`
（檔案清單見 [`redesign` tree](https://github.com/finamp-app/finamp/tree/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib)。
那些編輯是否直接寫伺服器、有無確認，未逐行驗證 → **推測**）。

同步的 UI 入口有兩個粒度，都是 icon button、都沒有確認對話框：

- 全部：Downloads 頁的 sync 按鈕，iterate 所有 downloaded parent
  （[`lib/components/DownloadsScreen/sync_downloaded_playlists.dart#L19-L42`](https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/lib/components/DownloadsScreen/sync_downloaded_playlists.dart#L19-L42)）
- 單一：專輯／歌單頁的 sync/download 按鈕
  （[`lib/components/AlbumScreen/sync_album_or_playlist_button.dart#L29-L50`](https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/lib/components/AlbumScreen/sync_album_or_playlist_button.dart#L29-L50)）

同步過程中唯一的對話框是「選下載位置」，而且只在有多個 download location 時才跳：

```dart
final selectedDownloadLocation = FinampSettingsHelper.finampSettings.downloadLocationsMap.values.length > 1
    ? await showDialog<DownloadLocation>(... DownloadDialog ...)
    : FinampSettingsHelper.finampSettings.downloadLocationsMap.values.first;
```

（[`sync_helper.dart#L68-L80`](https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/lib/services/sync_helper.dart#L68-L80)）

### 匹配 UX

不適用。Jellyfin 客戶端，伺服器 item id 直接對應，沒有跨平台匹配。

### 自動刷新間隔 / 離線

**沒有排程、沒有可設定的間隔**：同步一律由使用者按 sync 按鈕觸發（原始碼裡看不到
timer / scheduled sync）。離線時播本地已下載的檔案，這是下載系統存在的理由。

`DOWNLOADS_PLAN.md` 另外記載一個和 FMP 高度相關的教訓：舊下載系統用**五個各別維護的
key-value DB**（`DownloadedItems` / `DownloadedParents` / `DownloadIds` /
`DownloadedImages` / `DownloadedImageIds`）「all need to be kept in sync」，
作者自評是「very finnicky, and frequently breaks between updates」；1.0 改用
Isar 建立真正的關聯，並以 `background_downloader` 取代 `flutter_downloader`。

### 來源清單

- https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/lib/services/sync_helper.dart#L35-L143
- https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/lib/components/DownloadsScreen/sync_downloaded_playlists.dart#L19-L42
- https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/lib/components/AlbumScreen/sync_album_or_playlist_button.dart#L29-L50
- https://github.com/finamp-app/finamp/blob/f49ba47f491fbaf3aeeb67540e8cc788ad2cd307/DOWNLOADS_PLAN.md

---

## LX Music（desktop）— 相關性低，僅作對照

- repo：`lyswhut/lx-music-desktop`
- 查證 commit：`ad95d5091c9ed689fa72b5e5c849df65f5a679ce`（`master`，pushed_at 2026-09-19）

LX Music 沒有平台帳號，它的「遠端」是使用者自己架的同步伺服器。同步模組只有兩個
種類：自建歌單與不喜歡清單。

```
src/main/modules/sync/client/modules/list
src/main/modules/sync/client/modules/dislike
src/main/modules/sync/server/modules/list
src/main/modules/sync/server/modules/dislike
```

（由 [`git/trees/<sha>?recursive=1`](https://github.com/lyswhut/lx-music-desktop/tree/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/sync) 過濾 `sync/(client|server)/modules/` 得到）

**結論：LX Music 不處理「匯入外部平台歌單」，沒有可對照的唯讀鏡像／差異比對／
寫回確認設計。** 它的 list 同步是裝置對裝置，權威方向推測與 Finamp 同向
（伺服器 snapshot → 本地）→ **推測**，未逐行驗證。

### 來源清單

- https://github.com/lyswhut/lx-music-desktop/tree/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/sync

---

## 對 FMP 的啟示（10 條）

1. **Spotube 證明了「無本地副本」可行，但不適用於 FMP。** 它的 drift schema
   裡一張歌單表都沒有，代價是離線完全沒有歌單內容、也無處放自訂名稱／封面。
   FMP 已定案「名稱、描述、封面可本地改」，所以必須有本地表。（Spotube）
2. **差集式同步是這批產品裡唯一成形的差異比對實作，值得照抄形狀。**
   Finamp 用 id 集合的 `A-B` / `B-A` / `A∩B` 三組決定刪、載、更新，配一個
   `requiredBy` 清單讓一首歌被多個 parent 需要時不誤刪。FMP 的比對鍵要能同時容納
   「遠端曲目 id」與「本地匹配結果」，這個形狀可以直接對應。（Finamp）
3. **不要讓「遠端刪除」直接刪本地資料。** Finamp 是靜默刪檔；FMP 的比對鍵來自匹配，
   一次解析失敗不該被誤判成「遠端刪了」。遠端刪除應該是本地的一種狀態（例如標記
   「已從遠端移除」），而非刪除。（Finamp + 推論）
4. **匯入即複製（MusicFree）與持續鏡像（Finamp）是兩個極端。** FMP 已定案站鏡像這一端，
   但應該保留 MusicFree 的匯入前 UX：「先告訴我抓到幾首，再讓我確認」。（MusicFree）
5. **寫回前的確認在 Namida 有先例，而且分得剛好。** 從遠端歌單**移除**要確認
   （`_confirmRemoveVideos`），**加入**不確認（只處理重複）。FMP 的
   「從遠程播放列表移除」應該比照加確認。（Namida）
6. **「本地 vs 遠端」用同一個 sheet 的兩個 tab 分流**（Namida 的
   `lang.local` / `lang.youtube`）。FMP 的「加入遠端歌單」可以直接沿用這個形狀，
   讓使用者一眼看出自己正在寫哪裡。（Namida）
7. **寫回失敗要有明確回報。** Namida 的寫回只回傳 bool、失敗只 toast；FMP 的
   「改完再同步下來」流程裡，使用者期待遠端操作成功後本地會更新，失敗必須看得見。
   （Namida）
8. **沒有產品提供逐曲匹配的信心分數或人工修正 UI。** Spotube 的匹配快取只在播放
   來源層，不對使用者揭露；MusicFree 把匹配整包交給外掛。FMP 若要設計匹配修正，
   這裡沒有現成慣例可抄，最接近的既有模式是「匯入後列出結果讓你確認」。（Spotube / MusicFree）
9. **1–168 小時的自動刷新間隔在這些產品裡沒有先例。** Finamp 是手動 sync 按鈕
   （兩種粒度：全部／單一），Spotube 是進頁面即時抓，MusicFree 無連結，LX Music 無此概念。
   FMP 這條屬於自訂設計，無外部驗證可依賴。（全部）
10. **跨 store 一致性是這類功能的頭號失敗模式。** 舊 Finamp 的 `DOWNLOADS_PLAN.md`
    自述五個 key-value DB「all need to be kept in sync」是下載系統一直壞的主因，
    最後改用關聯式模型重寫。FMP 的「本地歌單 ↔ 遠端歌單 ↔ 本地檔案 ↔ 匹配結果」
    同樣橫跨多個 store，這條要當警訊。（Finamp）
