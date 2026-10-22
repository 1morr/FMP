# 轉換器：曲目、歌單、佇列、歷史、電台、外部來源

## 目標

M5 PR 3（上層 `implement.md` § 3；design §5.1–§5.7、§9「轉換器」）：`LegacyConverter` 把 PR 1 的 `LegacySnapshot` 轉成 PR 2 的 `ImportBundle`，純 Dart、沒有 I/O。每一筆略過都帶理由並計數，進 `ImportSummary`。帳號與憑證（PR 4）、設定（PR 5）不在這個 PR：`accounts` 空、設定組全空，只有播放歷史上限的換算在這裡做（歷史的截斷要用）。

範圍、做法都已由擁有者核准（2026-10-23，design §11 第 4、12 條）。計畫沒涵蓋、會改變行為、範圍或對外介面的決定，停下回報，不自行拍板。

## 現況（以程式碼為準）

- `lib/legacy_import/legacy_snapshot.dart`（PR 1）：舊 11 個 collection 的純值，Isar 型別預設（`minLong`、NaN、false）照原樣；`LegacySettings` 可變，讀取器已在 `schemaVersion < 4` 時補做舊 migration。**轉換器不改 snapshot**（上層 `implement.md`「留下的後續」PR 1）。
- `lib/data/import/import_bundle.dart`（PR 2）：`ImportBundle`、`ImportPlaylist`（`legacyPlaylistId`、`kind`、Mix 欄位、`remote`、`entries`）、`ImportPlaylistRemote`、`ImportPlaylistEntry`（`TrackKeyParts`、`unavailable`）、`ImportQueueEntry`、`PlayerState`、`ImportHistoryEntry`、`ImportRadioStation`、`ImportTrackOrigin`、`ImportRecord`、`ImportSummary`／`CollectionSummary`。`TrackInfo.duration` 以毫秒比對，轉換器給毫秒精度。
- `StagingImport.verify` 要求：`ImportBundle.tracks` 是唯一放曲目資料的地方，項目、佇列、歷史、`track_origins` 參照的每個鍵都要在 `tracks` 裡；沒被參照的曲目會被當成孤兒（驗證失敗）。
- `lib/domain/track_key.dart`：`TrackKey.format`、`TrackKeyParts`。
- 官方插件在同層的 `fmp-plugins` repo：bilibili 1.10.0、youtube 1.6.0、netease 1.7.0、qqmusic 1.0.0。`playlistFromUrl` 在各插件的 `src/plugin.js`（bilibili :412、netease :300、qqmusic :81）與 youtube `src/playlist.js`；單元測試在各插件的 `test/`。
- lint `fmp_source_id_literal`：官方插件 id 的字面值只能寫在 `lib/legacy_import`。

## 需求

1. **`LegacyConverter`**（`lib/legacy_import/legacy_converter.dart`）：`convert(LegacySnapshot, {required LegacyImportSource source, int? backupVersion, required DateTime now})` → `ImportBundle`。內部按 design §5 分段（曲目鍵正規化、曲目、歌單、佇列、歷史、電台、外部來源），PR 4、PR 5 之後在同一個轉換器加帳號與設定的段落，結構要讓它們只加不改。
2. **通則**（§5.1）：音源 id 字面相同不轉換，其他值略過（`unknownSource`）；時間轉 UTC；封面單一網址 → `[TrackArtwork(url)]`，空或非 `http(s)` 略過。
3. **B 站單 P 去 cid**（§5.1、§11 第 12 條）：`pageCount` ≤ 1，或 `pageCount` 空且 `pageNum` 空或 1 且 `parentTitle` 空時視為單 P，鍵去掉 cid；兩段與三段的同一支影片合併成一列。建一張「舊鍵 → 新鍵」與「舊 `Track.id` → 新鍵」的對照，歌單、佇列、歷史都經它。歷史裡出現、`Track` 裡沒有的 B 站鍵照原樣（記 `unverifiedPart`，不算略過）。**先以 bilibili 1.10.0 的搜尋、收藏夾、分 P 程式碼（`itemsOfMedia` 等）對一次規則**，對不上就停下回報。
4. **曲目**（§5.2）：只寫被參照的（未被參照的計 `unreferenced`）；欄位對照；`part_index`、`parent_title` 只給正規化後還帶 cid 的；同鍵多列取 `updatedAt ?? createdAt` 最新的一列，其餘計 `duplicateTrack`；歷史快照補的曲目只在鍵還沒有時加。
5. **歌單**（§5.3）：排序、時間、Mix、`imported`＋`playlist_remote`、認不出或重複的轉 `local`（`remoteNotRecognized`／`duplicateRemote`）、`writable` 比對舊 `Account.userId`、項目順序與 `unavailable`、懸空 id（`danglingTrackId`）、`legacyPlaylistId` 帶舊 `Playlist.id`（只在資料庫來源）。
6. **網址辨識**（`lib/legacy_import/remote_playlist_url.dart`，§5.3 的表）：只認不需要連網的形式。每個插件一組表格測試，期望值逐條取自該插件的單元測試或原始碼，**測試檔註明插件版本與來源檔**。
7. **佇列與播放狀態**（§5.4）：自然順序、`current_position`（同一首出現多次取第 k 次）、shuffle、loop、`position_ms`、`volume`（夾 0–1，NaN 或整列是型別預設時 1.0）、Mix 模式；`shuffleRank` 留空（`QueueStore` 會重新產生）。
8. **播放歷史**（§5.5）：依 `playedAt` 由新到舊，截到換算後的上限（`overHistoryLimit`）。上限換算：`playHistoryLimit` 取「不小於舊值的最小選項」，選項與上限照新版的設定定義（50000）；不合法或等於舊預設時用新版預設。這個換算函式 PR 5 會沿用，放在之後設定轉換也能 import 的地方。
9. **電台**（§5.6）、**外部來源**（§5.7）：`originalSource ∈ {qqmusic, netease}` 且 id 格式與新插件的 `sourceId` 相同才寫；`spotify` 與格式不符的略過（`originIdFormat`）。對照 qqmusic 1.0.0、netease 1.7.0 的 `sourceId` 格式，寫進測試。
10. **快取上限不匯入**（ADR 0016 §決定 3）：`network.cacheLimitMebibytes` 留空，測試斷言。
11. **`ImportSummary`**：每個 collection 的 read／written／skipped{理由: 筆數}；略過理由是一個列舉，序列化成英文字串。
12. **測試**（§9「轉換器」）：純 Dart，§5 每一列對照、每個略過理由各一例、B 站單 P 去 cid 與合併（含歌單、佇列、歷史經對照後接上）、分 P 欄位只給分 P、網址辨識表、歷史上限換算。另外一個整合測試：PR 1 的合成舊庫 → 讀取器 → 轉換器 → PR 2 的 `StagingImport.write`＋`verify` 通過（證明轉換結果滿足驗證的不變式）。
13. **文件**：`app/AGENTS.md` § 舊資料匯入加轉換器的契約（B 站單 P 的鍵、網址辨識與插件的依賴、略過理由）；只寫查不到的，每條寫閘門。

## 不做

帳號與憑證（PR 4）、設定（PR 5，歷史上限除外）、找舊資料、啟動流程、UI、JSON 備份讀取器（PR 6、7）。`fmp-plugins` README 的「宿主的依賴」由主對話另開 PR。

## 驗收

- 測試全綠；`dart format --output=none --set-exit-if-changed lib test tool`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 通過。
- 回報：改了哪些檔、B 站單 P 規則與插件程式碼的對照結果（檔名與行號）、三個插件網址辨識的來源、外部來源的 id 格式、計畫沒涵蓋而做了判斷的地方。
