# 0005 — 曲目識別鍵包含 Bilibili 的 cid

- 狀態：已採納
- 日期：2026-09-24
- 影響範圍：`lib/data/models/track_key.dart`、`lib/data/models/track.dart`、所有以識別鍵當外鍵的 collection 與備份格式

## 背景

一支 Bilibili 影片可以有多個分 P，它們共用同一個 bvid（FMP 的 `sourceId`），
各自有自己的 `cid`。`b2c69fc7`（2026-01-10）加入分 P 支援時決定**每個分 P 存成
一筆獨立的 `Track`**，同時在 `Track` 上加了 `cid`、`pageNum`、`parentTitle`，並
讓識別鍵帶上 cid：

- `uniqueKey`：有 cid 是 `sourceType:sourceId:cid`，沒有就是 `sourceType:sourceId`。
- `sourcePageKey`：同一個字串，是 Isar 複合索引（`CompositeIndex('cid')`）。
- `groupKey`：永遠兩段式，同一支影片的所有分 P 共用，用來分組顯示。

`uniqueKey` 就是在這個 commit 誕生的，從來沒有不含 cid 的版本。`b2c69fc7` 沒有
附任何資料遷移：cid 是 nullable 欄位，沒有 cid 的列照舊產生兩段式鍵。

`adeef972`（2026-09-03）把散在十六處的公式收成 `TrackKey.format` /
`TrackKey.formatGroup`，commit message 記錄生成的 Isar schema 逐位元相同。

## 決策

**cid 是曲目身分的一部分。** 分 P 之間唯一穩定的區別是 cid，所以它進鍵。
`TrackKey` 的 dartdoc 明寫：以 cid 區分分 P，不是 `pageNum`。

**這個字串是持久化格式，不是內部識別碼。** 它的字面輸出由
`test/data/models/track_key_test.dart` 用寫死的字串釘住，並斷言每個產生者
（`Track`、`PlayHistory`、`TrackSourceIdentity`、備份 DTO）一致。

## 被否決的替代方案

### 只用 `sourceType:sourceId`

同一支影片的分 P 會撞鍵。這不是推論：`StreamResolutionService._resolutionKey`
的註解記錄了 cid 還沒解析出來、分 P 只剩兩段式鍵時的後果 —— 「會把 P1 的 URL
餵給 P2」，所以那個行程內快取在鍵後面另外接 `pageNum`。

### 用 `pageNum` 區分分 P

`pageNum` 是顯示用的序號。`play_history_page.dart` 判斷「是否正在播放」時的
註解寫明比 cid 不比 pageNum，理由是 cid 才是穩定的唯一標識。`d90b2fac` 也把 cid
定為不可覆寫：「it identifies which page of a multi-page video the track is,
not a cached value」。需要 pageNum 的地方自己接在後面，不進身分。

## 後果

### 鍵被存在別的 collection 與備份檔裡

| 位置 | 用法 |
|---|---|
| `LyricsMatch.trackUniqueKey` | unique index，歌詞匹配的外鍵 |
| `LyricsTitleParseCache.trackUniqueKey` | unique index |
| `PlayHistory.trackKey` | 索引過的 getter |
| `Track.sourcePageKey` | 複合索引 |
| 備份 JSON：`TrackBackup.uniqueKey`、`PlayHistoryBackup.trackKey`、`LyricsMatchBackup.trackUniqueKey` | 匯入時把歷史與匹配接回曲目 |

改字面輸出要同時處理兩件事：Isar 只在 `put` 時重算 getter 索引（`PlayHistory`
的 dartdoc 記錄 v0 → v1 遷移為此重寫了所有既有列），以及既有備份檔要能匯回來。

### 鍵有兩種形狀，而且同一首歌會從一種變成另一種

cid 可以是 null。從搜尋與排行榜來的 Bilibili 曲目一開始沒有 cid；`d90b2fac`
（2026-09-02）起第一次解析串流時 `track.cid ??= streamResult.cid` 會回填，這首歌
的 `uniqueKey` 就從兩段式變成三段式。歌單匯入則在 `import_service.dart` 當下就
填 cid。

寫 `trackUniqueKey` 的地方（`lyrics_auto_match_service.dart`、`lyrics_provider.dart`、
`lyrics_title_parse_cache_repository.dart`、`backup_service.dart`）都用寫入當下的
`uniqueKey`。2026-09-25 查證過，這確實會讓歌詞匹配失聯：v1.9.1 以前，搜尋來的
曲目存下的匹配都是兩段式鍵；升到 v1.10.x 後第一次播放回填 cid，歌詞欄與自動匹配
就都讀不到它了，手動選的歌詞與 offset 跟著不見。

現在的處理：

- **回填當下**：`TrackRepository.backfillCid` 在同一筆交易裡把匹配改到三段式鍵。
  不持久化的解析（臨時播放、預取）也會把 cid 補進資料庫裡已經有的那一列：歌單頁
  點歌走的就是臨時播放，以前 cid 只寫在副本上，資料庫那一列一直停在兩段式鍵。
- **每次啟動**：`database_migration.dart` 補救更早回填過的列，以及備份匯入帶回來
  的舊鍵。

兩處共用 `relinkLyricsMatchToCidKeyInTxn`，只在以下條件都成立時改：

- 同一支影片的列都已經有 cid，而且只有一個 cid；
- 三段式鍵還沒有匹配。

分 P 影片分不出舊匹配屬於哪一 P，所以不改。`LyricsTitleParseCache` 每次啟動都會
清空，不需要處理。

同理，`DataIntegrityRepository` 以 `uniqueKey` 找重複曲目，同一支影片一筆有
cid、一筆沒有，不會被當成重複。

### 不靠 `uniqueKey` 的配對

下載掃描的配對不直接比 `uniqueKey`：`download_path_sync_service.dart` 先用
`TrackSourceIdentity`（同一個三段式公式）直接命中，掃到的檔案沒有 cid 時，退回
`TrackKey.formatGroup` 分組再比 `pageNum`。`download_path_maintenance_service.dart`
也是有 cid 比 cid、沒有才比 `pageNum`。
