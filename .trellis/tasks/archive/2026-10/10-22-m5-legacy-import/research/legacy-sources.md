# Research: 舊版（legacy）資料來源清冊，供 M5 規劃

- **Query**: 列出舊專案 Isar schema、關聯與鍵格式、檔案位置、JSON 備份格式、Settings 與 migration、secure storage 憑證、PlayQueue、下載與歌詞紀錄、Isar codegen 與開啟行為。
- **Scope**: internal（含 pub cache 內已有的套件原始碼）
- **Date**: 2026-10-22
- **基準**: 本 repo `main`（`cb311bcd`）根目錄 `lib/`（凍結的舊專案）。`docs/audit/data.md` 已逐項對照原始碼；有出入處在文內標「與 audit 不同」。
- **路徑慣例**: 使用者名稱一律寫 `<使用者>`；沒有讀取任何真實資料檔。

---

## 0. 最影響決策的事實與意外

1. **舊 secure storage 沒有傳任何選項**：`const FlutterSecureStorage()`（`lib/core/secure_key_value_store.dart:42-43`），全專案只有這一個建構點（grep `FlutterSecureStorage(` 於 `lib/`，其餘三個帳號服務與歌詞 AI 設定都走 `FlutterSecureKeyValueStore()`：`bilibili_account_service.dart:82`、`netease_account_service.dart:45`、`youtube_account_service.dart:44`、`lyrics_ai_config_service.dart:34`）。所以吃的是 10.3.1 的全部預設值，其中 Android `AndroidOptions.resetOnError` 在 Dart 端預設 `true`（`flutter_secure_storage-10.3.1/lib/options/android_options.dart` 建構子），並且每次都以 `'resetOnError': 'true'` 送進原生層；原生層在 key 不吻合或遷移失敗時 `deleteOnFailure` 會清空全部資料（`FlutterSecureStorage.java:939-961`）。**讀舊憑證若沿用預設選項，讀取失敗會把舊憑證刪掉**（ADR 0029 §決定 5 與 `app/lib/platform/secure_storage/flutter_secure_storage_adapter.dart:42-46` 已注意到同一個預設值）。
2. **Windows 舊憑證是檔案，不在 Credential Manager 的值裡**：`%APPDATA%\com.personal\fmp\<前綴><key>.secure`（AES-GCM），16 byte 金鑰放 Credential Manager（見 §6.3）。ADR 0010 與 `secure_key_value_store.dart:7-9` 的註釋寫「DPAPI」，原始碼裡不是 DPAPI API（`flutter_secure_storage_windows-4.1.0/windows/flutter_secure_storage_windows_plugin.cpp:314-361,543-556`）。
3. **`app/pubspec.yaml` 已是 `flutter_secure_storage: ^11.2.0`（`app/pubspec.yaml:87`），ADR 0010 卻寫 legacy_import 依賴 10.x（`docs/adr/0010-...md:53`）**。同一個 package 名稱在同一個 pubspec 只能解析一個版本；`app/packages/` 內只有 `flutter_inappwebview_*_stub` 與 `fmp_lints`，沒有 10.x 的副本。11.x 把 9.x 密文遷移來源拿掉（`flutter_secure_storage-11.2.0/CHANGELOG.md:48-54`），舊專案 pubspec 註解（`pubspec.yaml:67-73`）說明了同一件事。這是 M5 設計要先解的衝突，不是已有答案。
4. **舊 `*.g.dart` 被 `.gitignore` 排除（`.gitignore:29`），但本工作樹的 `lib/data/models/*.g.dart` 都在**（`git ls-files 'lib/**/*.g.dart'` 為空、`git check-ignore` 命中 `.gitignore:29`）。它們是本機 `dart run build_runner build` 的產物，PropertySchema 與目前 `.dart` 原始碼逐項吻合（§1）。
5. **Isar 沒有唯讀開啟模式**（`isar_community-3.3.2/lib` 內 grep `readOnly|read_only` 零命中；`Isar.open` 參數只有 `schemas/directory/name/maxSizeMiB/relaxedDurability/compactOnLaunch/inspector`，`lib/src/isar.dart:88-96`）。每次開啟都經過原生 `isar_instance_create` 並把完整 schema JSON 交給核心（`lib/src/native/open.dart:139-151`）。核心是閉源二進位，開啟時是否寫檔（建立 lock 檔、依 schema 差異建立/移除 collection 與索引）在 pub cache 內查不到原始碼，見 §9.3。
6. **實際存在的 PlayHistory.trackKey、Track.sourcePageKey 等推導值都被持久化**（§1.12），且 `Track` 在 DB 層沒有「sourceType+sourceId+cid」唯一索引（§2.3）。同一個 TrackKey 在舊 DB 裡可能有多列。
7. **舊備份的 `DateTime` 是本機時間無時區字串**：`toIso8601String()` 對 local `DateTime` 不帶 `Z`/offset（`backup_data.dart:109,259,366` 等）；Isar 讀出的 `DateTime` 已 `.toLocal()`（`isar_reader_impl.dart:196-208`）。匯入端 `DateTime.parse` 會把無 offset 字串當成匯入裝置的本機時間（`backup_data.dart:60,231,338`）。
8. **舊 Windows 預設路徑落在使用者「文件」資料夾**：DB、log、（未自選時的）下載都在 `<文件>\FMP\`（§3）。`<文件>` 是 `SHGetKnownFolderPath(Documents)`（`path_provider_windows-2.3.0/lib/src/path_provider_windows_real.dart:123-124,137-`），可能被 OneDrive 重新導向。

---

## 1. Isar collection 與 embedded（共 11 個 collection、2 個 embedded）

`fmpDatabaseSchemas` 清單：Track、Playlist、PlayQueue、PlayHistory、Settings、SearchHistory、DownloadTask、RadioStation、LyricsMatch、LyricsTitleParseCache、Account（`lib/data/database/database_catalog.dart:50-144`、`:142-144`）。**沒有任何 `IsarLink`/`IsarLinks`/`@Backlink`**（各 `*.g.dart` 都是 `links: {}`，例：`track.g.dart:222`）。

### 1.0 讀 PropertySchema 的結論與通則

- 下列欄位表的「型別」欄取自 `*.g.dart` 的 `PropertySchema`，行號範圍：Account `account.g.dart:19-59`、DownloadTask `download_task.g.dart:19-80`、LyricsMatch `lyrics_match.g.dart:19-43`、LyricsTitleParseCache `lyrics_title_parse_cache.g.dart:20-64`、PlayHistory `play_history.g.dart:19-55`、PlayQueue `play_queue.g.dart:19-101`、Playlist `playlist.g.dart:19-124`、RadioStation `radio_station.g.dart:19-75`、SearchHistory `search_history.g.dart:19-28`、Settings `settings.g.dart:19-310`、Track `track.g.dart:19-145`；embedded：`PlaylistDownloadInfoSchema` `track.g.dart:5356-`、`SourceSettingsEntrySchema` `settings.g.dart:7702-`。
- Isar 型別對應：`long`＝int64、`double`、`bool`、`string`、`dateTime`、`longList`、`objectList`。`dateTime` 磁碟上是 UTC 微秒，讀出為 `DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true).toLocal()`（`isar_reader_impl.dart:196-208`）。
- **舊列缺欄位時讀到的是 Isar 型別預設，不是 Dart 初值**：非空 int → `Isar.minLong`、非空 double → NaN、bool → false、非空 String → `''`、`String?` → null、List → `[]`（`lib/data/database/database_migration.dart:24-29`、`:159-165`）。直接讀 DB 的匯入端看到的就是這種原始值（舊 App 靠 `runDatabaseMigration` 與 `repairSettingsInvariants` 修，匯入端不跑它們，見 §5）。
- **推導值（無 `@ignore` 的 getter）被存下來**；下文標「推導」者，值在 `put` 當下計算，讀出物件時 Dart 端不使用磁碟上的值（`track.dart:338-339` 註釋）。這些不該匯入。

### 1.1 Track（`lib/data/models/track.dart:37-348`）

| 欄位 | 型別 | 可空 | 說明 / 索引 | 證據 |
|---|---|---|---|---|
| `id` | Id(int64) autoIncrement | 否 | 主鍵；被 Playlist/PlayQueue/DownloadTask 以整數引用 | `track.dart:39` |
| `sourceId` | String | 否 | `@Index()` hash，非 unique | `track.dart:42-43`、`track.g.dart:151-163` |
| `sourceType` | String | 否 | `@Index()` hash；值 `bilibili`/`youtube`/`netease`（§2.2） | `track.dart:46-47`、`track.g.dart:164-176` |
| `title` | String | 否 | | `track.dart:50` |
| `artist` | String | 是 | | `track.dart:53` |
| `ownerId` | int | 是 | Bilibili UP 主 id | `track.dart:56` |
| `channelId` | String | 是 | YouTube 頻道 id | `track.dart:59` |
| `durationMs` | int | 是 | | `track.dart:62` |
| `thumbnailUrl` | String | 是 | | `track.dart:65` |
| `audioUrl` | String | 是 | **過期的簽名串流 URL，不應匯入** | `track.dart:68`、`track.g.dart:21-25` |
| `audioUrlExpiry` | DateTime | 是 | **不應匯入** | `track.dart:71`、`track.g.dart:26-30` |
| `isAvailable` | bool | 否 | 預設 true | `track.dart:74` |
| `isVip` | bool | 否 | 預設 false | `track.dart:77` |
| `unavailableReason` | String | 是 | | `track.dart:80` |
| `playlistInfo` | List\<PlaylistDownloadInfo\> (objectList) | 否（預設 `[]`） | 歌單歸屬 + 下載路徑（§1.2） | `track.dart:85`、`track.g.dart:100-106` |
| `pageCount` | int | 是 | **沒標 @ignore，是真欄位**（分 P 總數） | `track.dart:243`、`track.g.dart:89-93` |
| `cid` | int | 是 | `@Index()` value；Bilibili 分 P 識別 | `track.dart:248-249`、`track.g.dart:177-189` |
| `pageNum` | int | 是 | 分 P 序號 | `track.dart:252` |
| `parentTitle` | String | 是 | 多 P 的父標題（也用於下載資料夾名） | `track.dart:255` |
| `bilibiliAid` | int | 是 | | `track.dart:258` |
| `originalSongId` | String | 是 | 匯入來源平台歌曲 id（netease/qqmusic/spotify） | `track.dart:264` |
| `originalSource` | String | 是 | `"netease"`/`"qqmusic"`/`"spotify"` | `track.dart:267` |
| `createdAt` | DateTime | 否 | 預設 `DateTime.now()` | `track.dart:270` |
| `updatedAt` | DateTime | 是 | `@Index()` value | `track.dart:273-274`、`track.g.dart:190-202` |
| `viewCount` | — | — | `@ignore`，**不持久化**（`track.dart:239-240`），不在 PropertySchema |  |

**推導但被持久化（不應匯入）**：`formattedDuration`、`groupKey`、`hasValidAudioUrl`（時間相關，磁碟值必然過時）、`isPartOfMultiPage`、`sourcePageKey`、`uniqueKey`（`track.g.dart:52-66,72-76,112-116,133-137`；getter 定義 `track.dart:278,288-293,328,331,334,340`）。`sourcePageKey` 另有複合索引 `sourcePageKey_cid`（hash + value，`track.dart:277-278`、`track.g.dart:203-220`）。

### 1.2 PlaylistDownloadInfo（embedded，`track.dart:10-34`）

| 欄位 | 型別 | 說明 | 證據 |
|---|---|---|---|
| `playlistId` | int | 指向 `Playlist.id`；`0` 代表掃描器發現的本地檔案（沒有歌單） | `track.dart:13`；`track_repository.dart:640-646,650-653` 註釋 |
| `playlistName` | String | 預設 `''`，下載路徑比對用 | `track.dart:16` |
| `downloadPath` | String | 空字串＝未下載；非空是**絕對路徑** | `track.dart:19`、`track.dart:29` |
| `isDownloaded`（推導，被持久化） | bool | 不應匯入 | `track.g.dart:5366-5370` |

### 1.3 Playlist（`lib/data/models/playlist.dart:6-88`）

| 欄位 | 型別 | 可空 | 說明 | 證據 |
|---|---|---|---|---|
| `id` | Id | 否 | | `playlist.dart:8` |
| `name` | String | 否 | `@Index(unique: true)`（無 replace） | `playlist.dart:11-12`、`playlist.g.dart:129-142` |
| `description`、`coverUrl` | String | 是 | | `:15,18` |
| `hasCustomCover` | bool | 否 | 預設 false | `:21` |
| `sourceUrl`、`importSourceType` | String | 是 | 匯入來源 URL / 類型 | `:24,27` |
| `refreshIntervalHours` | int | 是 | | `:30` |
| `lastRefreshed` | DateTime | 是 | | `:33` |
| `notifyOnUpdate` | bool | 否 | 預設 true | `:36` |
| `ownerName`、`ownerUserId` | String | 是 | | `:39,42` |
| `useAuthForRefresh` | bool | 否 | 預設 false | `:45` |
| `isMix` | bool | 否 | YouTube Mix（動態生成、不存 tracks） | `:48` |
| `mixPlaylistId`、`mixSeedVideoId` | String | 是 | | `:51,54` |
| `trackIds` | List\<int\> (longList) | 否 | **有序**的 `Track.id` 清單；歌單成員順序的唯一來源 | `:57`、`playlist.g.dart:108-112` |
| `createdAt` | DateTime | 否 | | `:60` |
| `updatedAt` | DateTime | 是 | | `:63` |
| `sortOrder` | int | 否 | `@Index()` value，越小越前 | `:66-67`、`playlist.g.dart:143-157` |

**推導但被持久化（不應匯入）**：`isImported`、`needsRefresh`（時間相關）、`trackCount`（`playlist.g.dart:46-50,67-71,103-107`；getter `playlist.dart:70,73,76-83`）。

### 1.4 PlayQueue（`lib/data/models/play_queue.dart:18-85`）

欄位見 §7；**推導但被持久化**：`length`、`isEmpty`、`isNotEmpty`、`hasNext`、`hasPrevious`、`currentTrackId`（`play_queue.g.dart` props id 1、2、3、4、6、11；getter `play_queue.dart:62-80`）。

### 1.5 PlayHistory（`lib/data/models/play_history.dart:10-77`）

| 欄位 | 型別 | 可空 | 說明 | 證據 |
|---|---|---|---|---|
| `id` | Id | 否 | | `:12` |
| `sourceId` | String | 否 | `@Index()` | `:15-16` |
| `sourceType` | String | 否 | `@Index()` | `:19-20` |
| `cid` | int | 是 | | `:23` |
| `title` | String | 否 | | `:26` |
| `artist` | String | 是 | | `:29` |
| `durationMs` | int | 是 | | `:32` |
| `thumbnailUrl` | String | 是 | | `:35` |
| `playedAt` | DateTime | 否 | `@Index()` | `:38-39` |
| `trackKey`（推導，被持久化並**有索引**） | String | 否 | `TrackKey.format(sourceType, sourceId, cid: cid)`；不應匯入，由 sourceType/sourceId/cid 重算 | `:46-47`、`play_history.g.dart:101-114` |

**無** Track 外鍵：歷史列自帶顯示欄位，獨立於 Track（`play_history.dart:8-9`）。

### 1.6 SearchHistory（`search_history.dart:6-20`）

`id`、`query`(String, `@Index()`)、`timestamp`(DateTime, `@Index()`)（`:8-16`；`search_history.g.dart:19-28`）。

### 1.7 RadioStation（`radio_station.dart:7-58`）

| 欄位 | 型別 | 可空 | 說明 | 證據 |
|---|---|---|---|---|
| `url` | String | 否 | `@Index(unique: true)` | `:12-13` |
| `title` | String | 否 | | `:16` |
| `thumbnailUrl`、`hostName`、`hostAvatarUrl` | String | 是 | | `:19,22,25` |
| `hostUid` | int | 是 | | `:28` |
| `sourceType` | String | 否 | `@Index()`；註釋寫 bilibili/youtube | `:30-32` |
| `sourceId` | String | 否 | `@Index()`；Bilibili 房間 id / YouTube videoId | `:34-36` |
| `sortOrder` | int | 否 | `@Index()` | `:39-40` |
| `createdAt` | DateTime | 否 | | `:43` |
| `lastPlayedAt` | DateTime | 是 | | `:46` |
| `isFavorite` | bool | 否 | `@Index()` | `:49-50` |
| `uniqueKey`（推導，被持久化） | String | 否 | `TrackKey.formatGroup(sourceType, sourceId)`；不應匯入 | `:53`、`radio_station.g.dart` props id 11 |

### 1.8 Account（`account.dart:9-48`）

| 欄位 | 型別 | 可空 | 說明 | 證據 |
|---|---|---|---|---|
| `id` | Id | 否 | | `:11` |
| `platform` | String | 否 | `bilibili`/`youtube`/`netease`（`account_service` 的 `platform` getter 回傳 `SourceIds.*`：`bilibili_account_service.dart:87`、`netease_account_service.dart:53`、`youtube_account_service.dart:51`）；**無索引** | `:14` |
| `userId`、`userName`、`avatarUrl` | String | 是 | 非敏感資訊 | `:17,20,23` |
| `isLoggedIn` | bool | 否 | 預設 false | `:26` |
| `lastRefreshed` | DateTime | 是 | 每次 upsert 都被設成 now（`account_repository.dart:60`） | `:29` |
| `loginAt` | DateTime | 是 | | `:32` |
| `isVip` | bool | 否 | 僅網易雲使用 | `:35` |
| `sessionExpired` | bool | 否 | 憑證被拒後：憑證清掉、`isLoggedIn=false`、此列保留且 `sessionExpired=true`；登出走刪列 | `:42`（註釋 `:37-41`） |

無推導欄位。

### 1.9 DownloadTask（`download_task.dart:24-107`）

| 欄位 | 型別 | 可空 | 說明 | 證據 |
|---|---|---|---|---|
| `id` | Id | 否 | | `:26` |
| `trackId` | int | 否（`late`） | `Track.id`；`@Index()` | `:29-30` |
| `playlistId` | int | 是 | `Playlist.id` | `:33` |
| `playlistName` | String | 是 | null＝未分類 | `:36` |
| `savePath` | String | 是 | 計畫保存路徑；`@Index()` | `:39-40` |
| `status` | enum `DownloadStatus` **以 name 存**成 string | 否 | `pending/downloading/paused/completed/failed`；`@Index()` | `:43-45`、`download_task.g.dart:271-277` |
| `progress` | double | 否 | | `:48` |
| `downloadedBytes` | int | 否 | | `:51` |
| `totalBytes` | int | 是 | | `:54` |
| `errorMessage` | String | 是 | | `:57` |
| `tempFilePath` | String | 是 | `.downloading` 續傳暫存 | `:60` |
| `priority` | int | 否 | `@Index()` | `:63-64` |
| `createdAt` | DateTime | 否 | | `:67` |
| `completedAt` | DateTime | 是 | | `:70` |

所有 getter 都標 `@ignore`（`:72-102`），無推導欄位被持久化。

### 1.10 LyricsMatch（`lyrics_match.dart:9-28`）

`trackUniqueKey`(String, **unique + replace** 索引)、`lyricsSource`(String：`lrclib`/`netease`/`qqmusic`)、`externalId`(String)、`offsetMs`(int，預設 0)、`matchedAt`(DateTime)（`:14-27`；`lyrics_match.g.dart:48-63`）。`trackUniqueKey` 是 `TrackKey.format()` 字串。

### 1.11 LyricsTitleParseCache（`lyrics_title_parse_cache.dart:5-20`）

`trackUniqueKey`(unique+replace)、`sourceType`、`parsedTrackName`、`parsedArtistName?`、`confidence`(double)、`provider`、`model`、`createdAt`、`updatedAt`。**每次啟動都被清空**（`database_migration.dart:65-66`），不屬於耐久資料，不應匯入。

### 1.12 Settings 與 SourceSettingsEntry

見 §5。

### 1.13 enum 儲存方式總表

| 位置 | enum | 儲存 | 磁碟值 | 證據 |
|---|---|---|---|---|
| `PlayQueue.loopMode` | `LoopMode` | `@Enumerated(EnumType.name)` → string | `'none'`/`'all'`/`'one'` | `play_queue.dart:35-36`、`play_queue.g.dart:252-256` |
| `DownloadTask.status` | `DownloadStatus` | name → string | `'pending'`/`'downloading'`/`'paused'`/`'completed'`/`'failed'` | `download_task.dart:43-45`、`download_task.g.dart:271-277` |
| `sourceType`（Track/PlayHistory/RadioStation/Account.platform/LyricsTitleParseCache.sourceType） | 曾是 `SourceType` enum（name 存），現為 String | string（磁碟格式不變） | `'bilibili'`/`'youtube'`/`'netease'` | `source_ids.dart:3-18`；commit `0b93e61d` 訊息「The disk format is unchanged: @Enumerated(EnumType.name) already wrote IsarType.string」；舊 enum 定義 `git show 0b93e61d^:lib/data/models/track.dart:9-12` |
| Settings 內的 `themeModeIndex` 等 | 無 enum 欄位，全是 **index 整數**（§5） | int | | `settings.dart:224,284,309,353,364` |

所有沒有 index 儲存的 enum 都是 name。`Settings` 的各 `*Index` 才是整數。

---

## 2. 關聯與鍵格式

### 2.1 關聯一覽（全是手動維護的值，DB 不保證完整性）

| 來源 | 目標 | 型式 | 證據 |
|---|---|---|---|
| `Playlist.trackIds` | `Track.id` | 有序 int64 清單 | `playlist.dart:57` |
| `PlayQueue.trackIds`、`PlayQueue.originalOrder` | `Track.id` | 有序 int64 清單（`originalOrder` 可空） | `play_queue.dart:23,39` |
| `DownloadTask.trackId` | `Track.id` | int | `download_task.dart:30` |
| `DownloadTask.playlistId` | `Playlist.id` | int? | `download_task.dart:33` |
| `Track.playlistInfo[].playlistId` | `Playlist.id` | int（`0`＝掃描器發現的無歌單檔案） | `track.dart:13` |
| `LyricsMatch.trackUniqueKey`、`LyricsTitleParseCache.trackUniqueKey` | Track | TrackKey 字串 | `lyrics_match.dart:13-15` |
| `PlayHistory.trackKey`（推導） | Track | TrackKey 字串，但歷史列自帶欄位 | `play_history.dart:46-47` |
| `RadioStation.uniqueKey`（推導） | — | `sourceType:sourceId` | `radio_station.dart:53` |

**同一個歌單成員有兩份記錄**：`Playlist.trackIds`（順序）與 `Track.playlistInfo[].playlistId`（歸屬 + 下載路徑）。備份只用前者（`backup_service.dart:109-116`）；孤兒判定只用後者（`track_repository.dart:631-662`）。兩者是否一致沒有 DB 層保證（audit：`data_integrity_repository` scan/repair 只在開發者「重設所有資料」被呼叫，`docs/audit/data.md:56`，**本次未重新驗證該呼叫點**）。

**Track 的存活依據**：`isReferenced` 看 `Playlist.trackIds` 與 `PlayQueue.trackIds`（`track_repository.dart:517-535`）；`deleteOrphanTracks` 看「不在目前佇列」且「`playlistInfo` 內沒有 `playlistId > 0`」（`:635-668`）。所以舊 DB 內存在**不屬任何歌單、只被佇列或下載路徑（`playlistId=0`）引用**的 Track 列，也可能有只被 `PlayHistory` 以字串重建的歌。

### 2.2 `TrackKey.format()` 精確輸出

`lib/data/models/track_key.dart:19-20`：

```dart
static String format(String sourceTypeId, String sourceId, {int? cid}) =>
    cid != null ? '$sourceTypeId:$sourceId:$cid' : '$sourceTypeId:$sourceId';
```

- 有 cid → `sourceType:sourceId:cid`（三段）；沒有 → `sourceType:sourceId`（兩段）。
- `formatGroup` 恆為兩段 `sourceType:sourceId`（`:23-24`）；`RadioStation.uniqueKey` 用它（`radio_station.dart:53`）。
- `tryParse` 用 `split(':')`，只接受 2 或 3 段；3 段的第三段必須是整數，否則回 null（`:30-46`）。**sourceId 若自己含 `:` 就解不回來**（沒有逸出）；實務上 BV 號、YouTube id、網易數字 id 不含 `:`，但這是格式沒保護的點。
- 註解宣告此字串是**持久化格式的一部分**，由 `test/data/models/track_key_test.dart` 用寫死字面值釘住（`track_key.dart:3-10`）。
- `sourceType` 的值：`bilibili`、`youtube`、`netease`（`source_ids.dart:16-18`，`SourceIds.values` 順序即此，`:24`）。範例：`bilibili:BV1xx...:123456`、`youtube:dQw4w9WgXcQ`、`netease:1234567`（範例為格式示意，非取自實際資料）。
- Bilibili 的舊列可能是兩段（還沒回填 cid）：`backfillCid` 在播放當下才補 cid，並同交易改 LyricsMatch 鍵（`track_repository.dart:155-174`）；啟動時 `_relinkLyricsMatchesToCidKeys` 再接住漏掉的（`database_migration.dart:84-103`）。因此舊 DB 內同一支 Bilibili 影片的 Track、PlayHistory、LyricsMatch 可能同時有兩段與三段鍵。
- 鍵字串的改版歷史：commit `adeef972`（2026-09-03）把 16 份複製收斂成一份，訊息稱「Generated Isar schemas are byte-identical」，即格式沒變；`sourceType.name` 與現在的 String 值相同。

### 2.3 唯一性（DB 層）

- 有 unique 索引：`Playlist.name`、`RadioStation.url`、`LyricsMatch.trackUniqueKey`（replace）、`LyricsTitleParseCache.trackUniqueKey`（replace）。
- **沒有** unique：Track（`sourceId`/`sourceType`/`cid`/`sourcePageKey_cid` 全 `unique: false`，`track.g.dart:151-220`）、PlayHistory、SearchHistory、Account.platform。Track 去重靠應用層 `getOrCreate`/`getOrCreateAll`（`track_repository.dart:369-510`）；備份匯入也靠 `uniqueKey` 略過重複（`backup_service.dart:419-422`）。

---

## 3. 舊版檔案位置

### 3.1 資料庫

- 常數：`fmpDatabaseName='fmp_database'`、目錄名 `AppConstants.appName`＝`'FMP'`、檔名 `fmp_database.isar`、lock 名常數寫 `fmp_database.isar.lock`（`database_provider.dart:14-17`；`app_constants.dart:8`）。
- 位置：`getApplicationDocumentsDirectory()/FMP/`（`database_provider.dart:23-25,50-53`）。
  - Windows：`C:\Users\<使用者>\Documents\FMP\fmp_database.isar`（`<文件>` 為 Known Folder Documents）。
  - Android：`getApplicationDocumentsPath()` → `PathUtils.getDataDirectory(context)`（`path_provider_android-2.2.22/.../PathProviderPlugin.java:56-59`），即 app 私有目錄下 `app_flutter/`（Flutter embedding 的 `getDataDirectory`，**該實作不在 repo/pub cache，是依 Flutter embedding 既有知識**）。應用 id `com.personal.fmp`（`android/app/build.gradle*`：`namespace`/`applicationId` 皆 `com.personal.fmp`）。實際：`/data/user/0/com.personal.fmp/app_flutter/FMP/fmp_database.isar`。
- **舊位置搬移邏輯**：`_ensureFmpDatabaseDirectory` 建立 `FMP/` 後呼叫 `_moveLegacyFmpDatabaseFiles`，把 documents **根目錄**下的 `fmp_database.isar` 與 `fmp_database.isar.lock` 搬進 `FMP/`；目標已存在就跳過；先 `rename`，`FileSystemException` 時 copy+delete（`database_provider.dart:32-43,55-83`）。這條邏輯在每次 `openFmpDatabase()` 前都跑（`:50-53,91`）。意味著極舊版本的 DB 可能還在 documents 根目錄；新 App 偵測舊資料時，這兩個位置都要看。
- 開啟參數：`maxSizeMiB: 2048`、`compactOnLaunch: CompactCondition(minFileSize: 8 MiB, minRatio: 2.0)`（`database_provider.dart:92-106`）。Isar 預設 `defaultMaxSizeMiB=1024`（`isar.dart:33`）。
- lock 檔實際名稱：CHANGELOG 寫 `dir/name.isar` 與 `dir/name.isar.lock`（`isar_community-3.3.2/CHANGELOG.md:214`，屬 3.0 前後的記載）；3.3.2 的核心是 libmdbx 0.13.8（`CHANGELOG.md:44`、M1 紀錄），`libisar.dll` 內字串搜尋有 `-lck`（libmdbx 在 NOSUBDIR 模式的慣用 lock 檔尾碼）而無 `.isar.lock` 這串。**實際檔名無法在不看真實目錄的前提下確認**（`test/providers/database_path_test.dart:36,56` 只測舊程式碼的搬移邏輯，用的是 `.isar.lock` 字面值）。

### 3.2 Log

`getApplicationDocumentsDirectory()/FMP/logs/fmp.log`，輪替 `fmp.1.log`…，單檔 2 MiB、保留 3 檔（`lib/core/log_file_sink.dart:15-28`）。Windows＝`<文件>\FMP\logs\`，Android＝`app_flutter/FMP/logs/`。

### 3.3 歌詞快取（可丟棄的快取）

`getApplicationCacheDirectory()/lyrics/<safeKey>.json` 加 `_metadata.json`（存取時間表）（`lyrics_cache_service.dart:63-64,271,276,327`）。
- Windows：`%LOCALAPPDATA%\com.personal\fmp\lyrics\`（`getApplicationCachePath` → `_createApplicationSubdirectory(LocalAppData)`，`path_provider_windows_real.dart:126-128`；子目錄＝`CompanyName\ProductName`，`:217`；舊版 `Runner.rc:92,98` 為 `com.personal`、`fmp`）。
- Android：`context.getCacheDir()/lyrics/`（`PathProviderPlugin.java:62-64`）。
- 內容是從網路取回的歌詞，`LyricsMatch` 才是耐久紀錄（`lyrics_match.dart:5-8`）。

其他快取（網路圖片）在 `getTemporaryDirectory()/fmp_network_image_cache`（`docs/audit/data.md:221`；`network_image_cache_service.dart:283`），更新 APK 在 `getTemporaryDirectory()`（`update_service.dart:228`），皆可丟棄。

### 3.4 Windows `%APPDATA%\com.personal\fmp\`

- 該目錄＝`%APPDATA%\<CompanyName>\<ProductName>`＝`C:\Users\<使用者>\AppData\Roaming\com.personal\fmp\`（`path_provider_windows_real.dart:119-120,217`；舊版 `windows/runner/Runner.rc:92,98`）。
- **舊 `lib/` 本身沒有任何呼叫 `getApplicationSupportDirectory`**（grep 全 `lib/` 只有 documents/temp/cache/external 四種）。這個目錄的已知內容：`flutter_secure_storage_windows` 的 `*.secure` 檔（§6.3）。其他 plugin 是否也寫入此處（例如 `window_manager`、`hotkey_manager`、`flutter_inappwebview_windows`）**未逐一追查**；WebView2 的 user data folder 在 `flutter_inappwebview_windows-0.6.0` 只在呼叫端指定時才有值（`webview_environment.cpp:61`），舊專案沒指定（grep `userDataFolder|WebViewEnvironment` 於 `lib/` 零命中），走 WebView2 預設。
- 新 App prod 的 `CompanyName`/`BINARY_NAME`/`ProductName` 與舊版相同（`app/windows/CMakeLists.txt:7`、`app/windows/runner/Runner.rc:92,98`、`app/windows/runner/app_identity.cmake:19`：prod `fmp`、dev `fmp-dev`），所以 prod 會**共用同一個 `%APPDATA%\com.personal\fmp\` 與同一個 secure storage 前綴**。新 App 的鍵加了 `fmp.` 前綴（`flutter_secure_storage_adapter.dart:45-57`），不會與舊鍵名衝突。

### 3.5 下載檔（M6 範圍，只列位置）

預設根目錄優先序：`Settings.customDownloadDir` → Android `.../Music/FMP`（`getExternalStorageDirectory()` 往上四層，退路 `app_flutter/FMP`）→ Windows `<文件>\FMP`（`download_path_utils.dart:187-216`）。目錄結構：`{base}/{歌單名或 "未分类"}/{sourceId}_{parentTitle|title}/audio.m4a` 或 `P01.m4a`…，旁有 `metadata.json`／`metadata_P{N}.json`、`cover.jpg`、`avatar.jpg`（`download_path_utils.dart:23-57`；`download_filenames.dart:14-33`）。副檔名一律 `.m4a`（`:40-46`，audit 同）。

### 3.6 Android 備份設定

舊 `AndroidManifest.xml` `allowBackup="false"`，註解說明原因是自動備份還原 shared prefs 後 Keystore 金鑰對不上（`android/app/src/main/AndroidManifest.xml:26-41`）。

---

## 4. 舊 JSON 備份格式

### 4.1 檔案與版本

- 檔名 `fmp_backup_<ISO 時間，冒號換 - 、去掉小數秒>.json`；`JsonEncoder.withIndent('  ')`；UTF-8 文字；無壓縮、無加密（`backup_service.dart:53-54,79-85`）。存放位置由使用者選（Android 選目錄、其他平台 saveFile，`:58-71`）。
- `kBackupVersion = 5`（`backup_service.dart:35`）。**匯入只擋比目前版本新的**（`:314-321`），沒有最低版本限制；`version` 缺少時當 1（`backup_data.dart:59`）。
- 驗證另要求至少有一類可匯入資料，否則 `emptyBackup`（`backup_service.dart:322-332`）。

### 4.2 版本史（`kBackupVersion` 變遷）

| 版本 | 日期 / commit | 變更 | 證據 |
|---|---|---|---|
| v1 | 2026-02-13 `6a61150c` | 初版。頂層 `version/exportedAt/appVersion/playlists/tracks/playHistory/searchHistory/radioStations/settings`；v1 當時 Playlist 沒有 `lastRefreshed/ownerName/ownerUserId/useAuthForRefresh/updatedAt`，Track 沒有 `isAvailable/isVip/unavailableReason/bilibiliAid/updatedAt`，RadioStation 沒有 `lastPlayedAt` | `git show 6a61150c:lib/services/backup/backup_data.dart`（`toJson` 部分） |
| （仍 v1） | 2026-02-16 `2311c480` | 新增頂層 `lyricsMatches` **未升版本** | `git log -S"'lyricsMatches'"` |
| v2 | 2026-06-21 `1885a3f0` | 加上上述 Playlist 五欄、Track 五欄、RadioStation `lastPlayedAt`，以及版本驗證 | `git show 1885a3f0 -- backup_data.dart` |
| （仍 v2） | 2026-04-21～05-24 | 這些設定鍵在 v2 版號前後陸續加入而**未升版**：`radioRefreshIntervalMinutes`（`8a4e5e1a`）、`lyricsAi*`（`43fbac84`，2026-05-01）、`lyricsWindow*`（`ad92e25d`，2026-05-21）、`homeRankingSourcePriority`/`disabledHomeRankingSources`（`be2b5111`，2026-05-24） | `git log -S` 各欄位名稱 |
| v3 | 2026-09-03 `6de4dfca` | 移除 5 個無讀者的自訂色欄位（`secondaryColor/backgroundColor/surfaceColor/textColor/cardColor`）與 `RadioStation.note` | commit diff；`backup_service.dart:26` |
| v4 | 2026-09-03 `8ffa7d4f` | 6 個每源具名設定鍵收成 `sourceSettings` 陣列；補 `railExpanded/detailPanelExpanded/detailPanelWidth` | `backup_service.dart:27-28` |
| v5 | 2026-09-16 `5ab060be` | 補 `playHistoryLimit` 與 `autoCheckUpdates`；後者隨自動檢查更新移除：匯出不寫、匯入忽略，沒再升版 | `backup_service.dart:29-31` |

**版本號與欄位出現的對應不精確**：同一個 `version` 值的檔案，欄位集合因當時 build 而異（例如 v1 檔可能有也可能沒有 `lyricsMatches`）。匯入端必須逐鍵容錯，這也是舊程式的做法（`fromJson` 對缺鍵一律走預設，`backup_service.dart:32-34`）。

### 4.3 頂層鍵

`version`(int)、`exportedAt`(ISO 字串，local 無 offset)、`appVersion`(String，預設 `'unknown'`)、`playlists`、`tracks`、`playHistory`、`searchHistory`、`radioStations`、`settings`(僅非 null 時寫)、`lyricsMatches`(僅非空時寫)（`backup_data.dart:106-120`；讀取容錯 `:57-104`）。

### 4.4 各實體序列化欄位（`toJson` 鍵名；`if` 表示 null 時省略）

- **playlists**（`backup_data.dart:239-262`）：`name`、`description?`、`coverUrl?`、`hasCustomCover`、`sourceUrl?`、`importSourceType?`、`refreshIntervalHours?`、`lastRefreshed?`、`notifyOnUpdate`、`ownerName?`、`ownerUserId?`、`useAuthForRefresh`、`isMix`、`mixPlaylistId?`、`mixSeedVideoId?`、`trackKeys`(List\<String\>，**有序**)、`createdAt`、`updatedAt?`、`sortOrder`。
  - 缺鍵預設：`hasCustomCover=false`、`notifyOnUpdate=true`、`useAuthForRefresh=false`、`isMix=false`、`trackKeys=[]`、`sortOrder=0`（`:207-236`）。`name`、`createdAt` 必填。
  - **曲目以 `uniqueKey` 字串引用**；匯出時 `trackMap[trackId]` 找不到的成員（懸空 id）直接略過（`backup_service.dart:109-116`）。
- **tracks**（`:345-369`）：`sourceId`、`sourceType`、`title`、`artist?`、`ownerId?`、`channelId?`、`durationMs?`、`thumbnailUrl?`、`viewCount?`、`pageCount?`、`cid?`、`pageNum?`、`parentTitle?`、`isAvailable`、`isVip`、`unavailableReason?`、`bilibiliAid?`、`originalSongId?`、`originalSource?`、`createdAt`、`updatedAt?`。
  - `viewCount` 在匯出時來自記憶體中的 `@ignore` 欄位，從 DB 讀出的 Track 其值為 null，實務上不會出現（`backup_service.dart:155` 讀 `t.viewCount`；欄位定義 `track.dart:239-240`）。
  - **匯出的是整張 Track 表**（`_repository.allTracks()`，`:98`），含不在任何歌單的 Track；不含 `audioUrl`、`audioUrlExpiry`、`playlistInfo`（下載路徑）。
  - `sourceId`、`sourceType`、`title`、`createdAt` 必填。
- **playHistory**（`:410-421`）：`sourceId`、`sourceType`、`cid?`、`title`、`artist?`、`durationMs?`、`thumbnailUrl?`、`playedAt`。**無 trackKey 欄位**，`trackKey` 由三個欄位重算（`:395`）。
- **searchHistory**（`:438-440`）：`query`、`timestamp`。
- **radioStations**（`:492-507`）：`url`、`title`、`thumbnailUrl?`、`hostName?`、`hostAvatarUrl?`、`hostUid?`、`sourceType`、`sourceId`、`sortOrder`、`createdAt`、`lastPlayedAt?`、`isFavorite`。
- **lyricsMatches**（`:883-891`）：`trackUniqueKey`、`lyricsSource`、`externalId`、`offsetMs`（為 0 時省略）、`matchedAt`。
- **settings**（`SettingsBackup.toJson`，`:791-853`）：`themeModeIndex`、`primaryColor?`、`maxCacheSizeMB`、`autoScrollToCurrentTrack`、`rememberPlaybackPosition`、`restartRewindSeconds`、`tempPlayRewindSeconds`、`playHistoryLimit`、`maxConcurrentDownloads`、`downloadImageOptionIndex`、`minimizeToTrayOnClose`、`enableGlobalHotkeys`、`launchAtStartup`、`launchMinimized`、`railExpanded`、`detailPanelExpanded`、`detailPanelWidth`、`fontFamily?`、`locale?`、`audioQualityLevelIndex`、`audioFormatPriority`、`sourceSettings`(陣列，元素 `{sourceId, streamPriority, useAuthForPlay}`，`:554-558`)、`hotkeyConfig?`(String，內含 JSON)、`autoMatchLyrics`、`maxLyricsCacheFiles`、`lyricsDisplayModeIndex`、`lyricsSourcePriority`、`disabledLyricsSources`、`lyricsAiTitleParsingModeIndex`、`allowPlainLyricsAutoMatch`、`lyricsAiEndpoint`、`lyricsAiModel`、`lyricsAiTimeoutSeconds`、`lyricsWindow*`×11(各自 null 時省略)、`rankingRefreshIntervalMinutes`、`homeRankingSourcePriority`、`disabledHomeRankingSources`、`radioRefreshIntervalMinutes`。
  - 備份**不含**：`schemaVersion`、`customDownloadDir`、`preferredAudioDeviceId/Name`、六個 `@Deprecated` 欄位。
  - 設定值的數字編碼同 Isar：各 `*Index` 是整數（§5）。

### 4.5 每源設定折疊（v3 以前）

`_readSourceSettings`（`backup_data.dart:565-590`）：JSON 有 `sourceSettings` 陣列就逐筆讀（非 Map 的元素略過）；否則用六個舊鍵折疊——`bilibiliStreamPriority/useBilibiliAuthForPlay`、`youtubeStreamPriority/useYoutubeAuthForPlay`、`neteaseStreamPriority/useNeteaseAuthForPlay`（`:574-578`）。缺鍵時串流優先序取 `kDefaultStreamPriorityBySource`（B `audioOnly,muxed`、Y `audioOnly,muxed,hls`、N `audioOnly`，`settings.dart:59-63`），`useAuthForPlay` 取 `defaultUseAuthForPlayFor`（B、N 為 true，Y false，`settings.dart:76-79,91-92`）。`SourceSettingsBackup.fromJson` 缺 `useAuthForPlay` 時同樣取該音源預設（`:544-552`）。**注意**：舊備份（v3 以前）裡 Bilibili 的 `useBilibiliAuthForPlay` 若存的是舊預設 false，會被原樣折進去；DB 內則是被 v3→v4 migration 強制改 true 的（§5.2）。兩條路徑對同一使用者可能給出不同的 Bilibili `useAuthForPlay`。

### 4.6 備份「不含」什麼

Account 列、secure storage 的憑證、歌詞 AI API key、PlayQueue、DownloadTask、LyricsTitleParseCache、下載檔與其路徑（`Track.playlistInfo`）、歌詞快取、`schemaVersion`、`customDownloadDir`、`preferredAudioDevice*`、`audioUrl`（`backup_service.dart:91-310`；`docs/audit/data.md:293-302`）。

### 4.7 匯入語意（舊程式）

解析階段完全不動 DB，最後 `writeImport` 單一交易（`backup_service.dart:395-397,764-777`）。曲目以 `uniqueKey` 略過重複、歌單以 `name` 略過同名、播放歷史以 `trackKey:playedAt毫秒` 去重、搜尋歷史以 `query` 去重、電台以 `url`、歌詞匹配以 `trackUniqueKey`（`:418-422,467-471,515-527,561-565,589-593,627-631`）。**歌曲只在 `importPlaylists` 為 true 時才匯入**（`:409`）。設定匯入時 Windows 專屬欄位在非 Windows 保留現值、`hotkeyConfig` 經 `_sanitizeHotkeyConfig` 處理（`:692-709,797-808`）。

### 4.8 hotkeyConfig 內嵌 JSON

`{"bindings":[{"action":<HotkeyAction.name>,"keyId":<int?>,"modifiers":[<字串>...]}]}`（`hotkey_config.dart:110-114,323-325`）。`HotkeyAction`：`playPause/next/previous/stop/volumeUp/volumeDown/mute/toggleWindow`（`:7-17`）。`keyId` 是 Flutter `LogicalKeyboardKey.keyId`。僅 Windows 使用。

---

## 5. Settings（單例 `id=0`）與舊 migration

### 5.1 欄位與預設（`settings.dart:213-443`）

主鍵 `Id id = 0`（`:214`）。**預設值是 Dart 初值；Isar 讀舊列缺欄時給的是型別預設**（§1.0）。

| 欄位 | 型別 | 預設 | 備註 | 行 |
|---|---|---|---|---|
| `schemaVersion` | int | 0 | `<0` 視為 0（`database_migration.dart:164-165`） | 221 |
| `themeModeIndex` | int | 0 | 0 system / 1 light / 2 dark | 224 |
| `primaryColor` | int? | null | ARGB | 227 |
| `railExpanded` | bool | false | | 231 |
| `detailPanelExpanded` | bool | false | | 240 |
| `detailPanelWidth` | double | 412.0（`AppLayout.detailPanelDefault`，`app_layout.dart:21`） | 舊列給 NaN；合法範圍夾在 320–1600（`app_layout.dart:18,35`） | 244 |
| `maxCacheSizeMB` | int | 32（Android 新安裝 16，`database_migration.dart:106-112`） | | 247 |
| `customDownloadDir` | String? | null | 裝置相關 | 250 |
| `hotkeyConfig` | String? | null | §4.8 | 253 |
| `autoScrollToCurrentTrack` | bool | false | | 256 |
| `rememberPlaybackPosition` | bool | true | | 259 |
| `restartRewindSeconds` | int | 0 | | 262 |
| `tempPlayRewindSeconds` | int | 10 | | 265 |
| `playHistoryLimit` | int | 10000（`kDefaultPlayHistoryLimit`，`:209`） | | 276 |
| `maxConcurrentDownloads` | int | 3 | 合法 1–5 | 281 |
| `downloadImageOptionIndex` | int | 1 | 0 none / 1 coverOnly / 2 coverAndAvatar | 284 |
| `minimizeToTrayOnClose` | bool | false | 僅 Windows | 289 |
| `enableGlobalHotkeys` | bool | false | 僅 Windows | 292 |
| `launchAtStartup` | bool | false | 僅 Windows；另寫系統自啟設定 | 295 |
| `launchMinimized` | bool | false | 僅 Windows | 298 |
| `fontFamily` | String? | null | | 301 |
| `locale` | String? | null | `zh_CN`/`zh_TW`/`en`/null | 304 |
| `audioQualityLevelIndex` | int | 0 | 0 high / 1 medium / 2 low | 309 |
| `audioFormatPriority` | String | `opus,aac` | | 313 |
| `sourceSettings` | List\<SourceSettingsEntry\> | `[]` | 每源一筆 `{sourceId, streamPriority, useAuthForPlay}`（`:128-149`） | 318 |
| `youtubeStreamPriority` / `bilibiliStreamPriority` / `neteaseStreamPriority` | String | `audioOnly,muxed,hls` / `audioOnly,muxed` / `audioOnly` | **`@Deprecated`，保留原值給降級用；v2 之後無人寫** | 324/330/336 |
| `preferredAudioDeviceId` / `Name` | String? | null | 裝置相關 | 339/342 |
| `autoMatchLyrics` | bool | false | | 347 |
| `maxLyricsCacheFiles` | int | 50 | | 350 |
| `lyricsDisplayModeIndex` | int | 0 | 0 original / 1 preferTranslated / 2 preferRomaji | 353 |
| `lyricsSourcePriority` | String | `netease,qqmusic,lrclib` | | 357 |
| `disabledLyricsSources` | String | `lrclib` | | 361 |
| `lyricsAiTitleParsingModeIndex` | int | 0 | 合法 0/2/3，1 非法 | 364 |
| `allowPlainLyricsAutoMatch` | bool | false | | 367 |
| `lyricsAiEndpoint` / `lyricsAiModel` | String | `''` | 歌曲標題會送到此端點 | 370/373 |
| `lyricsAiTimeoutSeconds` | int | 20（`app_constants.dart:185`） | | 376 |
| `lyricsWindowTextColor`、`…SecondaryTextColor`、`…InactiveTextOpacity`、`…OutlineEnabled/Color/Width`、`…ShadowEnabled/Color/BlurRadius/OffsetX/OffsetY` | int?/double?/bool? | 全 null＝預設樣式 | 11 欄 | 379-409 |
| `useBilibiliAuthForPlay` / `useYoutubeAuthForPlay` / `useNeteaseAuthForPlay` | bool | false / false / true | **`@Deprecated`** | 417/423/429 |
| `rankingRefreshIntervalMinutes` | int | 60 | | 434 |
| `homeRankingSourcePriority` | String | `bilibili,youtube,netease` | | 437 |
| `disabledHomeRankingSources` | String | `''` | 不得全部停用 | 440 |
| `radioRefreshIntervalMinutes` | int | 5 | 0＝關閉 | 443 |

與 audit §7 對照：欄位集合與預設一致（`docs/audit/data.md:314-357`）；audit 把 `detailPanelExpanded` 預設寫 false 與原始碼 `:240` 吻合；`detailPanelWidth` 預設 `AppLayout.detailPanelDefault`＝412（audit 未寫數值）。

### 5.2 舊 migration（`lib/data/database/database_migration.dart`）

`kFmpSchemaVersion = 4`（`:33`）。進入點 `runDatabaseMigration`，全部在**一個** `isar.writeTxn` 內（`:38-68`）：

| 步驟 | 內容 | 位置 |
|---|---|---|
| 無 Settings 列（全新安裝） | 寫 bootstrap Settings 並直接蓋 v4 | `:42-46,105-112` |
| 0→1「infer pre-versioning defaults」 | 若同時符合「`neteaseStreamPriority` 空 ∧ `!useNeteaseAuthForPlay` ∧ `!rememberPlaybackPosition` ∧ `tempPlayRewindSeconds==0` ∧ `disabledLyricsSources` 空」→ 補 `rememberPlaybackPosition=true`、`tempPlayRewindSeconds=10`、`disabledLyricsSources='lrclib'`（`:240-246`）；`neteaseStreamPriority` 空 → `useNeteaseAuthForPlay=true`、`neteaseStreamPriority='audioOnly'`；**無條件**`railExpanded=false`、`detailPanelExpanded=true`、`detailPanelWidth=380` | `:171-194` |
| 1→2「fold per-source settings」 | 把六個具名欄位折成 `sourceSettings` 三筆（順序 bilibili、youtube、netease）；**只搬不刪** | `:207-222` |
| 2→3 | 已退役，空函式 | `:229` |
| 3→4 | Bilibili `useAuthForPlay` **一律設 true**（含使用者自己關掉的，註釋承認） | `:236-238` |
| 每次啟動（已有 Settings 列時）`repairSettingsInvariants` | 見下 | `:58,252-375` |
| 每次啟動 `_ensureHealthyPlayQueue` | 沒有佇列就建一個；整列都是型別預設值（`lastVolume==0` 等）時 `lastVolume=1.0` | `:62,70-82,382-395` |
| 每次啟動 `_relinkLyricsMatchesToCidKeys` | 把 Bilibili 的兩段式 LyricsMatch 鍵升成三段（已有 cid 的 Track） | `:63,84-103` |
| 每次啟動 | `LyricsTitleParseCache.clear()` | `:66` |

`repairSettingsInvariants` 夾取清單（`:261-372`）：`maxConcurrentDownloads∉[1,5]→3`；`maxCacheSizeMB<1→32`；`audioQualityLevelIndex∉[0,2]→0`；`downloadImageOptionIndex∉[0,2]→1`；`lyricsDisplayModeIndex∉[0,2]→0`；`maxLyricsCacheFiles<1→50`；`playHistoryLimit<1→10000`；`lyricsAiTimeoutSeconds<1→20`；`lyricsAiTitleParsingModeIndex∈{1,<0,>3}→0`；`audioFormatPriority` 空→`opus,aac`；每個內建音源都要有 `sourceSettings` 項且 `streamPriority` 非空；`lyricsSourcePriority` 空→預設；`rankingRefreshIntervalMinutes<1→60`；`homeRankingSourcePriority` 空→預設並正規化；`disabledHomeRankingSources` 正規化；`radioRefreshIntervalMinutes<0→5`；`detailPanelWidth` 非有限→412，越界夾到 [320,1600]。

**對匯入的含意（事實，非建議）**：ADR 0010 規定舊版被 migration 強制改過的設定「照現值匯入」（`docs/adr/0010-...md:58`）。若舊 DB 的 `schemaVersion` 小於 4（使用者從舊版直接升級到新 App，跳過了 v1.10+ 的開啟），Isar 讀出的欄位會是型別預設（`minLong`/NaN/false），新 App 看到的「現值」並不是舊 App 若啟動一次後會得到的值。`effectiveSchemaVersion` 負數視為 0（`:164-165`）。

### 5.3 `PlayQueue` 之外的設定相關檔案

歌詞 AI API key 不在 Settings 而在 secure storage（§6.1）。

---

## 6. 憑證（secure storage）與 Account

### 6.1 鍵名與 JSON 形狀（全部是 `String` 值）

| Key | 值 | 證據 |
|---|---|---|
| `account_bilibili_credentials` | JSON：`sessdata`、`biliJct`、`dedeUserId`、`dedeUserIdCkMd5`、`refreshToken`（皆 String，缺值 `''`）、`savedAt`（ISO8601 字串，local，無 offset；缺值用 now） | `bilibili_account_service.dart:73`；`bilibili_credentials.dart:19-39` |
| `account_youtube_credentials` | JSON：`sid`、`hsid`、`ssid`、`apisid`、`sapisid`、`secure1Psid`、`secure3Psid`、`secure1Papisid`、`secure3Papisid`、`loginInfo`（皆 String，缺值 `''`）、`datasyncId`（String?，null 時仍寫出 `null`）、`savedAt` | `youtube_account_service.dart:27`；`youtube_credentials.dart:38-70` |
| `account_netease_credentials` | JSON：`musicU`（缺值或空會 `throw FormatException`）、`csrf`（缺值 `''`）、`userId`（String?）、`savedAt` | `netease_account_service.dart:30`；`netease_credentials.dart:15-37` |
| `lyrics_ai_api_key` | **純字串**（不是 JSON）；存空字串時 `delete` | `lyrics_ai_config_service.dart:32,70-82` |

- `toCookieString()` 的語意（Bilibili `SESSDATA=…; bili_jct=…; DedeUserID=…; DedeUserID__ckMd5=…`；Netease 還加 `os=pc`、`deviceId=fmp`；YouTube 有 SAPISIDHASH 產生）是**執行期推導**，不存（`bilibili_credentials.dart:41-44`、`netease_credentials.dart:39-52`、`youtube_credentials.dart:73-101`）。YouTube 的 `isValid` 要求 `sapisid/secure1Psid/secure3Psid` 非空（`:105-106`）。
- 讀不出來的處理（舊版）：讀取丟 `PlatformException`/`MissingPluginException` 一律包成 `SecureStorageUnavailable(operation, code)`（`secure_key_value_store.dart:13-27,60-68`）。JSON 壞掉時三個服務會**刪除該鍵**（`bilibili_account_service.dart:578-584`、`youtube_account_service.dart:565`、`netease_account_service.dart:434`；audit `docs/audit/data.md:199-201`）。
- 「重設所有資料」只清 Isar，不清憑證（audit §3.1，`docs/audit/data.md:204`；`data_integrity_repository.dart:55-56`，**本次未再逐行驗證**）。因此 `Account` 列與 secure storage 內容可能不一致：Account 為 `isLoggedIn=false` 但憑證仍在。

### 6.2 `FlutterSecureStorage(...)` 選項

只有 `const FlutterSecureStorage()`（`secure_key_value_store.dart:42-43`），沒有 `aOptions`/`wOptions`/`iOptions`。使用版本：`flutter_secure_storage 10.3.1`、`flutter_secure_storage_windows 4.1.0`、`flutter_secure_storage_platform_interface 2.0.3`（`pubspec.lock:486-493,510-517,526-533`）。實際預設：

- **Android**（`AndroidOptions()`，`flutter_secure_storage-10.3.1/lib/options/android_options.dart`）：`encryptedSharedPreferences=false`、`resetOnError=true`、`migrateOnAlgorithmChange=true`、`migrateWithBackup=false`、`enforceBiometrics=false`、`keyCipherAlgorithm=RSA_ECB_OAEPwithSHA_256andMGF1Padding`、`storageCipherAlgorithm=AES_GCM_NoPadding`、`sharedPreferencesName`/`preferencesKeyPrefix`/`storageNamespace` 皆 null（`toMap()` 送空字串）。原生層預設：SharedPreferences 名 `FlutterSecureStorage`、金鑰前綴 `VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg`（`FlutterSecureStorageConfig.java:15-16`）。也就是舊憑證在 `shared_prefs/FlutterSecureStorage.xml`，鍵形如 `VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_<key>`（前綴加底線的拼接由原生碼完成，**拼接細節未逐行驗證**）。
- **Windows**（`WindowsOptions()`，`windows_options.dart`）：`useBackwardCompatibility=false`（此選項在 10.3.1 的 windows 原生碼 4.1.0 中沒有被使用，`flutter_secure_storage_windows_plugin.cpp` 內無 `useBackward` 字樣）。
- 版本史：`flutter_secure_storage` 在 commit `5efd6cde`（2026-09-08）由 9.2.4 升 10.3.1（`git log -G"flutter_secure_storage: \^" -- pubspec.yaml`）；tag `v1.10.0`（2026-09-09）起含 10.3.1，`v1.9.1` 及更早含 9.2.4。**tag 名與 pubspec `version:` 對不上**（`v2.0.1` 的 pubspec 仍是 `1.11.0+1011000`），別拿 tag 名推版本。10.x 在第一次讀取時把 Android 密文遷移成新 cipher（`pubspec.yaml:67-73` 註解、`flutter_secure_storage-11.2.0/CHANGELOG.md:48-54`）；沒有跑過 10.x 的安裝，11.x 讀不出（會被 `SecureKeyValueStore` 的防護降級成重新登入）。

### 6.3 Windows 儲存機制（與 ADR/註解的「DPAPI」不同）

`flutter_secure_storage_windows-4.1.0/windows/flutter_secure_storage_windows_plugin.cpp`：

- 目錄：`%APPDATA%\<CompanyName>\<ProductName>`，Company/Product 取自 exe 的 version resource，非法字元換 `_`（`:203-262`）。
- 檔案：`<目錄>\<SECURE_STORAGE_KEY_PREFIX><key>.secure`（`:549,615`）；`SECURE_STORAGE_KEY_PREFIX = "${BINARY_NAME}_VGhpcyBpcyB0aGUgcHJlZml4IGZv_"`（`CMakeLists.txt:26-28`；舊版 `BINARY_NAME=fmp`，`windows/CMakeLists.txt:7`）。因此例如 `fmp_VGhpcyBpcyB0aGUgcHJlZml4IGZv_account_bilibili_credentials.secure`。
- 檔案內容：`[IV 12 bytes][AES-GCM tag][ciphertext]`（`:543-556`；明文含結尾 `\0`，`:528,540` 的 `val.length() + 1`）；AES-GCM、16 byte 金鑰（`:315-363,483-541`）。
- 金鑰：Windows Credential Manager 的 generic credential，target `key_<前綴>`、`CRED_PERSIST_LOCAL_MACHINE`（`:314-361`）。不在 Credential Manager 時才會產新金鑰（`NewKey:`）；**若金鑰遺失，既有 `.secure` 檔就無法解密**。
- 新版 `flutter_secure_storage_windows 4.2.2`（新 App 用）的目錄/前綴/檔名/Credential Manager 邏輯與 4.1.0 相同（比對 `…-4.2.2/windows/flutter_secure_storage_windows_plugin.cpp:255-300,494,560` 與 4.1.0）；新 App 把 `useBackwardCompatibility` 納入（`flutter_secure_storage-11.2.0/lib/options/windows_options.dart:5-33`），4.2.2 原生碼內無該字樣（grep 無結果）。**11.x 與 10.x 在 Windows 上的檔案相容性只做了原始碼層級比對，沒有實測。**

### 6.4 Android 儲存

見 §6.2；`allowBackup=false`（`AndroidManifest.xml:26-41`）。Android Keystore 金鑰屬於 applicationId 與簽名；新 App prod 沿用 `com.personal.fmp`（ADR 0008）。簽名是否相同在這個任務範圍外，未查。

### 6.5 Account 列

見 §1.8。`platform` 無索引、可能有多列同 platform（`upsert` 以 `getByPlatform` 避免，但 DB 不保證，`account_repository.dart:49-52`）。

---

## 7. PlayQueue（單例，`id` autoIncrement，實務上一列）

欄位（`play_queue.dart:18-59`；PropertySchema `play_queue.g.dart:19-101`）：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `trackIds` | List\<int\> | 有序 `Track.id`（隨機播放時已是打亂後順序） |
| `currentIndex` | int | 預設 0；對 `trackIds` 的索引 |
| `lastPositionMs` | int | 上次播放位置 |
| `isShuffleEnabled` | bool | |
| `loopMode` | enum name string | `none`/`all`/`one`，預設 `none` |
| `originalOrder` | List\<int\>? | 隨機前的順序；取消隨機時還原（`queue_repository.dart:200-246`） |
| `lastVolume` | double | 預設 1.0；0 且其他欄位全是預設＝「從未寫過」，由 `_ensureHealthyPlayQueue` 修成 1.0（`database_migration.dart:70-82,382-395`） |
| `lastUpdated` | DateTime? | 每次 `save` 設為 now（`queue_repository.dart:47`） |
| `isMixMode` | bool | YouTube Mix 播放模式 |
| `mixPlaylistId`、`mixSeedVideoId`、`mixTitle` | String? | Mix 狀態（`queue_persistence_manager.dart:114-128`：關閉 Mix 時三者設 null） |

- 還原行為：`QueuePersistenceManager.restoreState` 用 `trackIds` 取 Track、位置只在 `rememberPlaybackPosition` 為 true 時採用、音量取 `lastVolume`（`queue_persistence_manager.dart:56-76`）。
- `trackIds` 內的 id 不保證都還有對應 Track（無 FK）。
- 推導欄位被存的清單見 §1.4。
- 播放中的「臨時播放」等執行期狀態是否另有持久化：本次只讀了佇列持久化兩個檔案，**未驗證**其他執行期狀態是否落盤。

---

## 8. 下載紀錄與 LyricsMatch（M6/M7 才匯入，這裡只列 M5 要保留的事）

### 8.1 下載相關資料在舊 DB 的位置

- **`Track.playlistInfo[].downloadPath`**（絕對路徑）是「某歌單下某曲目已下載」的主要持久事實（`track.dart:19,89-147`）；`DownloadTask` 是下載工作佇列，啟動時就清掉 `completed/failed`、把 `downloading` 改回 `paused`（`download_service.dart:204-217`）。所以匯入當下的 `DownloadTask` 主要是未完成任務。
- 啟動時磁碟→DB 同步（REPLACE 模式）會以本地檔案為準替換 DB 路徑，純本地檔案記成 `playlistId=0`（`docs/audit/data.md:282`，含核查更正；**本次未重讀 `startup_download_sync_provider.dart`**）。
- 路徑可能指向：自訂目錄、Android `.../Music/FMP`、Windows `<文件>\FMP`（§3.5）。

### 8.2 LyricsMatch

以 `trackUniqueKey`（TrackKey 字串）連 Track，不用整數 id（`lyrics_match.dart:13-15`）；內容只有外部 id 與 `offsetMs`（`:17-24`）。Track 被刪（孤兒清理）時刻意不連帶刪 LyricsMatch（`track_repository.dart:630-633` 註釋）。因此**歌詞匹配可能對應到已不存在的 Track**，鍵可能是兩段或三段（§2.2）。

### 8.3 對「匯入紀錄」的事實需求

- 只有 **Track.id** 與 **Playlist.id** 是被其他 collection 以整數引用的鍵：`Playlist.trackIds`、`PlayQueue.trackIds/originalOrder`、`DownloadTask.trackId`、`DownloadTask.playlistId`、`Track.playlistInfo[].playlistId`（§2.1）。其餘（LyricsMatch、PlayHistory）用 TrackKey 字串。
- 因此 M6 若要從舊 DB 匯入 `DownloadTask` 或把 `playlistInfo.downloadPath` 歸到新資料表，需要「舊 Track.id → 新 track key」與「舊 Playlist.id → 新 playlist id」兩張對照；M7 的 `LyricsMatch` 只需 TrackKey，不需舊 id。是否在 M5 的匯入紀錄裡存這兩張對照、或 M6 重新開舊 DB 現算，屬設計決定，不在本清冊範圍。
- 舊 DB 在 M5 之後必須仍在原處（ADR 0010 §決定 4：永不自動刪舊檔），M6/M7 才能再讀。

---

## 9. Isar codegen 與開啟舊檔的行為

### 9.1 M1 的作法（`.trellis/tasks/archive/2026-10/09-28-m1-skeleton-tracer/research/isar-sqlite3-coexistence.md`）

- `isar_community_generator` 3.3.2（pub.dev 最新）要求 `analyzer >=8.0.0 <11.0.0`；`app/` workspace 因 `fmp_lints` 釘 `analyzer 13.3.0`（ADR 0015）無法加入（`:150-161`，`dart pub add --dry-run` 的錯誤訊息）。
- 探針改在 **workspace 外的獨立暫存 package** 執行 `dart run build_runner build`（analyzer 10.2.0、`build_runner 2.15.1`、`source_gen 4.2.4`，會警告 SDK language version 比 analyzer 新，但仍成功），把產出的 `.g.dart` 複製進 `app/lib/probe/`，執行期正常（`:32,159-161`）。探針的 `@collection` 只有 `ProbeItem{Id id; late String name;}`（`:39-40`）。
- 該紀錄提出兩條路給 M5：workspace 外產生舊 schema 的 `.g.dart` 後提交進 `app/lib/legacy_import/`（舊 schema 已凍結、產一次即可；探針證實可行），或等 generator 放寬 analyzer 上界（`:162-169`）。`app/.gitignore:50-52` 已放行 `app/` 內的 `*.g.dart`。
- 共存結果：`isar_community 3.3.2` 與 `sqlite3 3.6.0` 在 Android（debug/release、16KB 頁模擬器）與 Windows release 都能同行程共存，`libisar.so`/`libsqlite3.so` 符號不重疊、LOAD 段對齊 ≥0x4000（`:11-17,77-78,113-125`）。
- **現成的產物**：根目錄 `lib/data/models/*.g.dart`（`.gitignore` 排除、不在版控，但本工作樹有）就是 3.3.2 generator 對**凍結 schema**的輸出，檔內 `version: '3.3.2'`（`track.g.dart:228`）；舊 `pubspec.yaml` 的 `isar_community_generator ^3.3.2`（`pubspec.yaml:95`）與 `pubspec.lock:704-711` 解析到 3.3.2。這些檔案是否與「使用者實際安裝版本」所寫 DB 的 schema id 一致，以 Isar 的 collection/property id 為準（`TrackSchema.id=6244076704169336260`，`track.g.dart:18`）；schema id 由名稱雜湊而來，**未獨立重算驗證**。

### 9.2 Isar 能不能唯讀或從副本目錄開

- **沒有唯讀選項**（見 §0.5）。能指定的只有目錄與實例名。`Isar.open` 的檔案位置規則：`<directory>/<name>.isar`（CHANGELOG `:214`）；legacy 實例名是 `fmp_database`（`database_provider.dart:14,92-95`），**開副本時 `name` 必須與副本的檔案主檔名一致**，否則會開出一個新空庫（依 `<name>.isar` 規則推論，**未實測**）。
- `Isar.open` 可從任意可讀寫目錄開；沒有要求在原 app 目錄。`isar_community_flutter_libs` 提供原生庫（`libisar.dll`、Android `libisar.so`）。
- 相同 `name` 的實例在同一行程只能開一次（`_checkOpen`：`Instance has already been opened.`，`isar.dart:57-66`）；`schemas` 不可空、不可重名（`:64-72`）。
- `isar.copyToFile(targetPath)` 存在：「複製一份壓縮過的資料庫」（`isar.dart:237`、CHANGELOG `:222`）。這個 API 本身需要先開啟來源 DB。

### 9.3 開啟是否寫入舊檔（**含推論，未實測**）

可以從 pub cache 證實的：

- 開啟必經 `isar_instance_create(…, schemaStrPtr, maxSizeMiB, relaxedDurability, compactMinFileSize, compactMinBytes, compactMinRatio)`（`open.dart:139-151`），schema 是全部 `CollectionSchema` 序列化的 JSON（`:132-137`）。
- `compactOnLaunch` 只有呼叫端有傳才有效（`open.dart:116-118,128-130`）；舊 App 傳了 `minFileSize 8 MiB ∧ minRatio 2.0`（`database_provider.dart:102-105`）。舊 App 每次啟動可能壓縮 DB（改寫檔案）。
- `relaxedDurability` 預設 true（`isar.dart:93`）。
- `libisar.dll` 內有字串 `-lck`、`mdbx_drop`、`migrate_v`（`grep -a` 於 pub cache 的 `isar_community_flutter_libs-3.3.2/windows/libisar.dll`）。這只證明核心有 libmdbx lock 檔慣例與某種 schema 遷移程式碼，不證明細節。

**不能從 pub cache 證實、需實測的**（核心為閉源二進位，pub cache 內沒有 Rust 原始碼）：

1. 開啟一定會建立/觸碰 lock 檔，且以讀寫模式 mmap 資料檔（libmdbx 的一般行為；Isar 未暴露 `MDBX_RDONLY`）。
2. Isar v3 核心在開啟時依傳入的 schema 與庫內 schema 的差異做遷移（新增缺少的 collection/索引；依 Isar v3 的設計，庫裡有而傳入 schema 沒有的 collection 與索引會被移除）。若這成立，**只傳部分 collection 去開舊檔會刪掉其餘 collection 的資料**，而傳入的 schema 與庫內不同（欄位增減、索引增減）會改寫檔案。這是依 Isar v3 設計的既有知識，不是本次在原始碼確認的事實。
3. 打開非自己寫入的舊檔時若遇 `maxSizeMiB` 小於現有檔案的處理方式。

這三點決定「對原檔唯讀」是否可行，都需要在**舊 DB 的副本**上實驗；本次任務不得讀取真實資料，所以沒有做。事實層面可說的是：Isar API 沒有任何能保證不寫入的旋鈕。

---

## 10. 查不到／未驗證清單

- 舊 DB 在 Windows/Android 實際目錄內的檔案清單、lock 檔真實檔名（§3.1）：需看真實目錄，本任務禁止。
- `%APPDATA%\com.personal\fmp\` 除 `*.secure` 外的內容（§3.4）。
- Android `app_flutter` 的 Flutter embedding 實作（§3.1）：依既有知識，非 repo/pub cache 內可驗。
- Isar 核心開啟時的寫入行為（§9.3）。
- 11.x 讀 10.x 寫的 Windows `.secure` 檔、Android 密文的相容性：僅原始碼比對，未實測。
- `DataIntegrityRepository` 的呼叫點、`startup_download_sync_provider` 的內容：沿用 audit 的說法，未重讀。
- 舊版（`isar` 3.1.0+1 時期，tag `v1.9.1` 及更早）寫出的 DB 是否與 `isar_community 3.3.2` 的 schema id 全部相容：commit `0b93e61d`/ADR 0007 說磁碟格式不變，本次未驗證。`v1.9.1` 的 pubspec 沒有 `isar_community:`（`git show v1.9.1:pubspec.yaml`）。
- 備份 v1 之前可能存在的其他格式：`git log` 顯示 `kBackupVersion` 從 `6a61150c` 才存在，無更早版本。

## Related Specs

- `docs/adr/0010-drift-data-layer-and-legacy-import.md` — 匯入規則與已知限制
- `docs/adr/0029-login-credentials-accounts.md:43` — 新 secure storage 的 11.2.0 與 `resetOnError` 預設
- `docs/audit/data.md` — 前次審計（本檔已逐項對照）
- `.trellis/tasks/archive/2026-10/09-28-m1-skeleton-tracer/research/isar-sqlite3-coexistence.md` — Isar/sqlite3 共存與 codegen
