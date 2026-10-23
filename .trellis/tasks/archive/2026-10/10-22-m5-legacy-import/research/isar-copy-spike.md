# Isar 複本讀取探針（M5 規劃用，一次性）

日期：2026-10-22。目標：用舊 App 的 schema 開「複本」並讀出匿名統計，不動原檔。

## 結論

- **可行**。複本用 11 個舊 schema 一次開起、全部集合讀得出，沒有 schema 不符或 native lib 載入錯誤。
- 原檔 SHA-256 與 mtime 前後一致（雜湊與修改時間只在當次比對，不記錄）。原檔只被 `cp` 讀過，沒被 Isar 開過。
- **鎖檔後綴是 `-lck`**：Isar 在複本目錄新建了 `fmp_database.isar-lck`（開著時 4096 bytes、關閉後 0 bytes）。
  目錄裡只有 `fmp_database.isar` 與 `fmp_database.isar-lck` 兩個檔。原目錄 `<文件>/FMP/` 也是同一組檔名
  （App 當時留有 `-lck`）。
- 複本已刪除，探針套件內無任何 `.isar*` 檔。

## 版本與做法

| 項目 | 版本 |
|------|------|
| Flutter／Dart | 3.47.5／3.13.4 |
| `isar_community`、`isar_community_flutter_libs` | 3.3.2、3.3.2（pub 快取，未下載） |
| Isar core | `IsarCore using libmdbx: v0.13.8-temp-upstream-fix` |

1. 暫存套件 `<暫存目錄>/isar-spike/`（package 名維持 `fmp`，讓 `package:fmp/...` import 原樣有效），
   `flutter test` 執行。
2. 從舊 `lib/data/models/` **逐字複製**：account、download_task、lyrics_match、lyrics_title_parse_cache、
   play_history、play_queue、playlist、radio_station、search_history、settings、track、track_key、
   source_ids、models 與各自的 `.g.dart`（模型與註解零改動，schema id 與舊 App 一致）。
3. 只補 4 個 stub 讓它編得過：`core/constants/app_constants.dart`（`lyricsAiDefaultTimeoutSeconds`）、
   `core/constants/app_layout.dart`（`detailPanelDefault`）、`core/utils/duration_formatter.dart`、
   `i18n/strings.g.dart`（`source_ids.dart` 的 `t`）。`settings.dart` 依賴 `package:flutter/material.dart`，
   所以探針是 Flutter 套件、用 `flutter test` 跑；`dart run` 不行。
4. 載入 native lib：`Isar.initializeIsarCore(libraries: {Abi.windowsX64: '<LOCALAPPDATA>\Pub\Cache\hosted\pub.dev\isar_community_flutter_libs-3.3.2\windows\libisar.dll'})`。
   **key 要用 `dart:ffi` 的 `Abi`**；`IsarAbi` 只是 `isar_core.dart` 內的 typedef，沒從 `isar.dart` 匯出。
5. `Isar.open([TrackSchema, PlaylistSchema, PlayQueueSchema, PlayHistorySchema, SettingsSchema,
   SearchHistorySchema, DownloadTaskSchema, RadioStationSchema, LyricsMatchSchema,
   LyricsTitleParseCacheSchema, AccountSchema], directory: <複本目錄>, name: 'fmp_database',
   maxSizeMiB: 2048)`，未設 compactOnLaunch。
6. 複本在 `isar.close()` 後，原檔 hash／mtime 重驗一致，再整個刪掉 `copy/`。

## 數字（僅聚合）

### 各集合筆數

| 集合 | 筆數 |
|------|-----:|
| Track | 1195 |
| Playlist | 1 |
| PlayQueue | 1 |
| PlayHistory | 443 |
| Settings | 1 |
| SearchHistory | 2 |
| DownloadTask | 1（status 全是 completed） |
| RadioStation | 0 |
| LyricsMatch | 1 |
| LyricsTitleParseCache | 0 |
| Account | 2 |

### Settings

- `schemaVersion` = 4
- `sourceSettings` **不是空的**，3 筆：bilibili `useAuthForPlay=true`、netease `true`、youtube `false`

### Track

- sourceType：bilibili 1195／youtube 0／netease 0／other 0
- bilibili 且 `cid != null`：299；其中 `pageCount == null || pageCount <= 1`：9
- `pageNum != null`：1193
- 重複 TrackKey（sourceType+sourceId+cid）：0 組
- `playlistInfo` 內有非空 `downloadPath` 的 Track：0

### Playlist

- `isMix`：0；`sourceUrl != null`：1；`refreshIntervalHours != null`：0
- `trackIds` 共 1195 筆，指向不存在 Track 的：0

### PlayQueue（1 列）

- `trackIds.length` = 1195（指向不存在 Track：0）
- `isShuffleEnabled` = true；`originalOrder` = **長度 0 的空 list（不是 null）**
- `isMixMode` = false；`loopMode` = all

### PlayHistory

- 443 筆；其 key（`sourceType:sourceId[:cid]`）在 Track 找不到的：**110**

### 其他

- RadioStation：0
- Account：bilibili `isLoggedIn=true, sessionExpired=false`；netease `isLoggedIn=true, sessionExpired=false`
- LyricsMatch 1、SearchHistory 2

## 對 M5 規劃的提示

- 「Track 有 `pageNum` 的 1193 筆，但 `cid != null` 只有 299」：多數 bilibili Track 沒 cid，
  M5 的 TrackKey 映射不能假設 cid 必有。
- PlayHistory 有 110 筆沒對應 Track，匯入要決定略過、保留孤兒或補建 Track。
- `originalOrder` 在 shuffle 開啟時仍為空 list，匯入不能把「空」當成「無 shuffle 資料」以外的訊號。
