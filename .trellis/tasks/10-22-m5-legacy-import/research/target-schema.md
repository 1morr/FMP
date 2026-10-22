# Research: M5 匯入目標（`app/` 新端）盤點

- **Query**: 盤點 M5 legacy import 要寫入的新端（`app/`）：drift 表、TrackKey 與插件 id、匯入歌單、憑證、設定、資料目錄、啟動流程與 ADR 0034 還原機制、dev 入口、lint、repository 寫入 API。
- **Scope**: internal（另讀了同層 sibling repo `<同層>/fmp-plugins\index.json` 取官方插件 id）
- **Date**: 2026-10-22
- 路徑除特別標明外都相對 `app/`。`AGENTS.md:N` 指 `app/AGENTS.md`。原始碼與 AGENTS.md 衝突時以原始碼為準，下面每條都已對過原始碼。

---

## 1. drift 表（schemaVersion 18）

`lib/data/database/app_database.dart:55` 宣告 `schemaVersion => 18`；22 張表登記在 `app_database.dart:24-49`。快照最新是 `drift_schemas/app_database/drift_schema_v18.json`。所有表名以 `tableName` 寫死（`tables.dart:14`）。外鍵每次開啟在 `beforeOpen` 打開（`app_database.dart:61`，`PRAGMA foreign_keys = ON`），所以寫入順序必須先 `tracks` 再參照它的表。

通用格式（`converters.dart`）：時間 = UTC epoch **毫秒**整數（`EpochMillisecondsConverter`，`converters.dart:245-254`）；列舉 = 寫死字串，讀到不認得的值**拋錯**（各 converter 的 `_ => throw FormatException`）；布林 = SQLite 0/1。

### 1.1 曲目與音樂庫

**`tracks`**（`tables.dart:155-183`）：PK `track_key`。

| 欄位 | 型別 | 可空 | 說明 |
|---|---|---|---|
| `track_key` | text | 否 | `TrackKey.format` 輸出，PK（:161） |
| `source_type_id` | text | 否 | 插件 id 字串，無 FK（:164） |
| `source_id` | text | 否 | 音源內 id（:165） |
| `cid` | integer | 是 | B 站分 P cid（:166） |
| `title` | text | 否 | 分 P 曲目是分 P 標題（:167） |
| `uploader` | text | 是 | （:168） |
| `duration_ms` | integer | 是 | 毫秒（:169） |
| `artwork_json` | text | 是 | `[{url, width?}]`；空陣列時存 NULL（`TracksRepository.encodeArtwork`，`tracks_repository.dart:91`） |
| `updated_at` | integer(epoch ms) | 否 | 每次 upsert 取 `clock.now()`（`tracks_repository.dart:19`），**無法由呼叫端指定** |
| `part_index` | integer | 是 | 分 P 序號（從 1）（:178）；AGENTS 明寫舊 `pageNum` -> `part_index`、舊 `parentTitle` -> `parent_title`（`AGENTS.md:417-418`） |
| `parent_title` | text | 是 | 影片標題（:179） |

**`playlists`**（`tables.dart:420-446`）：PK `id` autoIncrement。

- 欄位：`kind`（text，`local`／`imported`／`mix`，`PlaylistKindConverter` `converters.dart:305-322`）、`name`（NOT NULL）、`description`、`artwork_json`（皆可空）、`sort_order`（int NOT NULL，由小到大）、`created_at`／`updated_at`（epoch ms NOT NULL）、`mix_plugin_id`／`mix_seed_source_id`／`mix_seed_cid`（可空）。
- 表級 CHECK（:440-445）：`kind='mix'` 時 `mix_plugin_id` 與 `mix_seed_source_id` 非 NULL；否則三個 mix 欄全 NULL。

**`playlist_entries`**（`tables.dart:452-477`）：PK `id` autoIncrement。`playlist_id` FK -> `playlists.id` **ON DELETE CASCADE**；`track_key` FK -> `tracks.track_key` **RESTRICT**；`position` int NOT NULL（**不唯一**，順序是 `(position, id)`）；`remote_item_id` text 可空；`unavailable` bool 預設 false；`seen_generation` int 預設 0。索引 `playlist_entries_playlist(playlist_id, position)`、`playlist_entries_track_key(track_key)`（:452-456）。同一首可在同一份歌單出現多次（`AGENTS.md:485`）。

**`playlist_remote`**（`tables.dart:483-525`）：見第 3 節。

**`track_origins`**（`tables.dart:576-591`）：PK `(track_key, origin_plugin_id)`，`origin_id` text NOT NULL；`track_key` FK -> tracks **CASCADE**。外部（Spotify／QQ）匯入選定曲目才寫，舊版沒有對應概念。

**`match_results`**（`tables.dart:550-571`）：PK `(origin_plugin_id, origin_id)`；`title` NOT NULL；`artists`／`duration_ms`／`score`(real) 可空；`selected_track_key` FK -> tracks **RESTRICT**（可空）；`user_selected` bool 預設 false；索引 `match_results_selected`。舊版沒有對應概念。

### 1.2 佇列與歷史

**`queue_entries`**（`tables.dart:189-208`）：PK `position`（int）；`track_key` FK -> tracks **RESTRICT**（索引 `queue_entries_track_key`）；`shuffle_rank` int 可空。**不得加 `position >= 0` 的 CHECK**（位移時暫用負值，:187）。

**`player_state`**（`tables.dart:212-242`）：單列，`id` CHECK `= 1`。`current_position` int 可空；`position_ms` int NOT NULL；`loop_mode` text NOT NULL（`off`／`all`／`one`，`converters.dart:102-119`）；`shuffle_enabled` bool NOT NULL；`volume` real NOT NULL（0–1）；`muted` bool NOT NULL；`mode` text 可空（`queue`／`mix`）；`mix_plugin_id`／`mix_id`／`mix_title`／`mix_cursor` text 可空；`updated_at` epoch ms NOT NULL。讀回時 `mode = mix` 而身分欄缺任一個（`mix_cursor` 除外）就當一般佇列（`AGENTS.md:410-411`）。**速度不持久化**（:211）。

**`play_history`**（`tables.dart:247-261`）：PK `id` autoIncrement；`track_key` FK -> tracks **RESTRICT**；`played_at` epoch ms NOT NULL；索引 `play_history_played_at`、`play_history_track_key`。同一首聽兩次是兩列（`AGENTS.md:422`）。

### 1.3 電台

**`radio_stations`**（`tables.dart:382-415`）：PK `id` autoIncrement；`plugin_id` NOT NULL（無 FK）；`room_id` NOT NULL；`title` NOT NULL；`host_name`、`artwork_json` 可空；`sort_order` int NOT NULL；`added_at` epoch ms NOT NULL；`live_status` text 可空（`live`／`offline`，`converters.dart:226-242`）；`live_title` 可空；`status_checked_at` epoch ms 可空。UNIQUE `(plugin_id, room_id)`（:412-414）。**「查詢失敗」不存**（`AGENTS.md:475`）。

### 1.4 設定組

單列表的 `id` 皆 `CHECK (id = 1)`。欄位為 NULL = 使用者沒設定過，預設只在 Notifier 套用（`AGENTS.md:1920-1921`）。細節見第 5 節。

| 表 | 位置 |
|---|---|
| `appearance_settings` | `tables.dart:18-31` |
| `network_settings` | `tables.dart:34-53` |
| `playback_settings` | `tables.dart:58-84` |
| `developer_settings` | `tables.dart:341-361` |
| `chart_settings`（PK `(plugin_id, chart_id)`） | `tables.dart:531-543` |
| `layout_state`（單列，裝置專屬，備份不收） | `tables.dart:266-287` |

### 1.5 帳號與每音源設定

**`accounts`**（`tables.dart:292-314`）：PK `plugin_id`，**無 FK 到 `installed_plugins`**。`user_id` text NOT NULL；`display_name` text NOT NULL；`avatar_json` text 可空（`Artwork[]` JSON，格式 `[{"url":..,"width"?:..}]`，見 `lib/plugins/accounts/account_service.dart` 的 `login`）；`status` text NOT NULL（`active`／`invalidated`，`converters.dart:160-179`）；`logged_in_at` epoch ms NOT NULL；`last_refresh_at` epoch ms 可空；`last_refresh_result` text 可空（`refreshed`／`unchanged`／`failed`，`converters.dart:182-203`）。不存 VIP（ADR 0029 §6）。

**`source_settings`**（`tables.dart:318-337`）：PK `plugin_id`。`browse_as_logged_in` bool 可空（空 = 用 manifest 預設，沒宣告是開）；`match_target` bool 可空；`match_rank` int 可空。登出時保留。

### 1.6 插件

**`installed_plugins`**（`tables.dart:87-116`）：PK `id`。`version`、`manifest_json`、`script` text NOT NULL；`installed_at` epoch ms NOT NULL；`enabled` bool 預設 true；`source_index_url` text 可空（空 = 從檔案／網址安裝）；`checks_json` 可空；`from_dev_folder` bool 預設 false。

**`plugin_storage`**（`tables.dart:136-151`）：PK `(plugin_id, key)`；`plugin_id` FK -> `installed_plugins.id` **CASCADE**；`value` text NOT NULL。

**`plugin_indexes`**（`tables.dart:120-132`）：PK `url`；`added_at` epoch ms。官方 index 不存這裡（網址在 `lib/core/endpoints.dart:8-9`）。

### 1.7 排程

**`scheduler_runs`**（`tables.dart:365-377`）：PK `job_id`；`last_success_at` epoch ms NOT NULL；無 FK。

### 1.8 converters 存的字串一覽（`lib/data/database/converters.dart`）

| 欄位 | 合法字串 | 行 |
|---|---|---|
| `appearance_settings.theme_mode` | `system`／`light`／`dark` | 17-35 |
| `appearance_settings.locale` | `zh-TW`／`zh-CN`／`en` | 38-56 |
| `playback_settings.audio_quality` | `high`／`medium`／`low` | 59-76 |
| `playback_settings.audio_format_priority` | `opus,aac`／`aac,opus`（註解明寫與舊版字面值相同，「M5 匯入直接對得上」，:78-79） | 80-99 |
| `player_state.loop_mode` | `off`／`all`／`one` | 102-119 |
| `player_state.mode` | `queue`／`mix` | 122-137 |
| `layout_state.player_tab` | `lyrics`／`queue`／`details` | 140-157 |
| `accounts.status` | `active`／`invalidated` | 160-179 |
| `accounts.last_refresh_result` | `refreshed`／`unchanged`／`failed` | 182-203 |
| `developer_settings.log_level` | `debug`／`info` | 206-222 |
| `radio_stations.live_status` | `live`／`offline` | 226-242 |
| `playlist_remote.status` | `active`／`sourceGone`／`authRequired` | 257-278 |
| `playlist_remote.last_result` | `complete`／`partial`／`failed` | 281-302 |
| `playlists.kind` | `local`／`imported`／`mix` | 305-322 |

### 1.9 另一個資料庫：cache DB（`lib/data/cache/`）

- `cache.db` 是第二個 drift 庫（`cache_database.dart`，`@DriftDatabase(tables: [CacheEntriesTable])`，`schemaVersion => 1`），只有一張 `cache_entries`（`cache_tables.dart:50-75`：`id`、`key`、`category`（`image`／`chart`）、`plugin_id`、`relative_path`、`size_bytes`、`last_access`、`valid_until`、`etag`；UNIQUE `(category, plugin_id, key)`）。
- 位置：平台快取目錄下的 `fmp_cache/`（`lib/platform/cache_directory/cache_directory.dart:9`；Android = `getCacheDir()`，Windows = `%LOCALAPPDATA%\<Company>\<ProductName>`，同檔 docstring）。可隨時丟：版本不同就刪表重建（`cache_database.dart` 的 `onUpgrade`）。
- 該檔註解指出 Windows prod 的 ProductName 與舊版相同，**舊版的歌詞快取也在同一個平台快取目錄**，所以多包一層 `fmp_cache`（`cache_directory.dart:5-8`）。
- AGENTS 寫明「舊版的快取設定不匯入（ADR 0016 §決定 3）」（`AGENTS.md:1925-1927`）。匯入不需要碰 cache DB。

### 1.10 備份歸類清單（新表要歸類）

`lib/data/database/backup_format.dart:12-48`：`backupExcludedTables = [layout_state, accounts, plugin_storage, scheduler_runs]`；`backupCarriedTables` 是其餘 18 張。`test/data/database/backup_format_test.dart` 對 `AppDatabase.allTables` 強制每張表歸類。M5 如果新增表要同步（AGENTS 與 ADR 0034 「之後要注意」末條）。

---

## 2. TrackKey 與插件 id

### 2.1 TrackKey 形狀

`lib/domain/track_key.dart:19-20`：

```dart
static String format(String sourceTypeId, String sourceId, {int? cid}) =>
    cid != null ? '$sourceTypeId:$sourceId:$cid' : '$sourceTypeId:$sourceId';
```

- 有 cid = 三段 `bilibili:BV1xx:123456`；無 cid = 兩段 `youtube:dQw4w9WgXcQ`。分組鍵 `formatGroup` 永遠兩段（:23）。`tryParse`（:30-46）可反向拆；超過兩個 `:` 或 cid 非整數回 null。
- 檔頭明寫它是持久化格式，「舊版把同一個字串存在 Isar 的複合索引與備份 JSON 的外鍵裡；M5 靠逐字相同的鍵把歌單、播放歷史接回曲目」（:5-7），輸出由 `test/domain/track_key_test.dart` 釘住。
- 注意：`source_id` 內若含 `:` 會讓 `tryParse` 失效（沒有轉義）；寫入走 `TrackInfo.key` -> `'${track.key}'`（`tracks_repository.dart:22`），key 由三欄現組，不是從字串反解。

### 2.2 tracks 與插件的關係

- `tracks.source_type_id` 就是**插件 id 字串**；沒有任何 FK 指向 `installed_plugins`（`tables.dart:164`、`AGENTS.md:398-408`）。
- 舊版音源 id 常數：`lib/data/models/source_ids.dart` -> `bilibili`／`youtube`／`netease`（舊專案根目錄 `lib/data/models/source_ids.dart:15-17`），**與新端官方插件 id 字面相同**。
- 官方插件 id：lint 清單 `packages/fmp_lints/lib/src/rules/source_id_literal.dart:11-23` 列 `bilibili`、`youtube`、`netease`、`spotify`、`qqmusic`。sibling repo `<同層>/fmp-plugins\index.json`（branch `main`）實際列出同樣五個 id，版本 bilibili 1.10.0、netease 1.7.0、qqmusic 1.0.0、spotify 1.0.0、youtube 1.6.0。App 側的 `fmp-test` 等是測試插件，只在 dev 打包。
- 官方 index 網址：`lib/core/endpoints.dart:8-9` = `https://raw.githubusercontent.com/1morr/fmp-plugins/main/index.json`。
- **只有 `lib/legacy_import/` 與 `test/` 可以寫官方插件 id 字面值**（`source_id_literal.dart:26`，lint `fmp_source_id_literal`）。

### 2.3 引用了未安裝插件時的行為

- 全新安裝**沒有任何插件**：`installed_plugins` 空。`main.dart` 不預裝；唯一的來源是使用者經 UI 安裝（ADR 0030 §12：搜尋頁與首頁在「沒有任何已啟用、具 `search` 能力的插件」時顯示引導，官方清單預設全勾、依序安裝；`lib/ui/plugins/plugin_onboarding.dart:75-83` `showOnboarding`，狀態只活在這次執行，`:26-27`）。需要網路讀官方 index。dev flavor 已有測試插件時不出現（ADR 0030 §12）。
- ADR 0030「之後要注意」第一條：「M5 的 legacy import 偵測舊音源並提示一鍵安裝，用同一個安裝流程」（`docs/adr/0030-...md` 後果段）。目前沒有程式碼做這件事（`lib/legacy_import/` 不存在，見第 9 節）。
- 資料保留：曲目、電台、`playlist_remote`、`accounts`、`source_settings`、`chart_settings`、`match_results` 都不綁 `installed_plugins`，插件停用或移除後資料保留（`tables.dart` 各表註解；ADR 0030 §10「曲目與電台保留，顯示『音源未安裝』」）。
- 播放：佇列裡該插件的曲目照「音源未安裝」跳過（`AGENTS.md:1116`、`1520-1525`）；UI 名稱由 `pluginNameProvider`／`sourceUnavailableProvider` 顯示（`AGENTS.md:1129-1133`）。
- 匯入歌單自動刷新：`dueForRefresh(pluginIds, now)` 只選「在插件清單且宣告 `importPlaylist`」的插件（`playlist_repository.dart:449-478`；`AGENTS.md:1305-1307` 自動刷新段）；插件沒裝就不被刷新。
- 帳號/憑證：`CredentialStore._load` 只讀「manifest 宣告 `login` 的**已安裝**插件」加上「有帳號列的」（`credential_store.dart:112-135`；`AGENTS.md:881`）。所以匯入寫了 `accounts` 列但插件沒裝時，該 id 仍會被讀（`ids` 含 `accounts.keys`，`credential_store.dart:117-121`）。

---

## 3. 匯入（remote）歌單

### 3.1 `playlist_remote` 欄位（`tables.dart:483-525`）

| 欄位 | 型別 | 可空 | 預設 | 說明 |
|---|---|---|---|---|
| `playlist_id` | int | 否 | | PK；FK -> playlists **CASCADE** |
| `plugin_id` | text | 否 | | 無 FK |
| `remote_id` | text | 否 | | 音源內歌單 id；UNIQUE `(plugin_id, remote_id)` |
| `owner_name` | text | 是 | | |
| `writable` | bool | 否 | false | 能否寫回遠端（`libraryWrite`） |
| `name_overridden`／`description_overridden`／`artwork_overridden` | bool | 否 | false | true = 下次刷新不蓋掉該欄 |
| `refresh_interval_hours` | int | 是 | | **空 = 不啟用自動刷新**；新匯入預設 24 |
| `last_refreshed_at` | epoch ms | 是 | | 只在 `complete`／`partial` 時寫；空 = 還沒刷新完過 |
| `last_result` | text | 是 | | `complete`／`partial`／`failed` |
| `status` | text | 否 | `'active'` | `active`／`sourceGone`／`authRequired` |
| `refresh_generation` | int | 否 | 0 | 每次刷新開始 +1 |

`playlist_entries` 的後三欄（`remote_item_id`、`unavailable`、`seen_generation`）只有匯入歌單用（`tables.dart:451`）。

### 3.2 刷新工作如何找到它們

- `PlaylistRepository.dueForRefresh`（`playlist_repository.dart:449-478`）：`status = active` 且 `refresh_interval_hours IS NOT NULL` 且 `plugin_id` 在清單內，且 `last_refreshed_at` 為空或距今已滿間隔；排序 `last_refreshed_at` 由舊到新（空最先）、同時間依 id。
- `PlaylistRefreshJob`：登記單一 `playlist-refresh` 工作、間隔 30 分鐘，每張自己的間隔在欄位（`AGENTS.md:1304-1311`）。
- 刷新是否帶登入：**沒有逐歌單的旗標**。請求一律 `userPreference`，讀私人歌單被拒且這次沒帶憑證而使用者已登入時，插件以 `required` 重送一次（ADR 0012 §2 補充、`AGENTS.md:1027-1029`）。「帶不帶」由 `source_settings.browse_as_logged_in`（每插件）決定。

### 3.3 刷新對舊匯入項目的處理（影響匯入時怎麼填 entries）

`AGENTS.md:1297-1303`：刷新開始 `refresh_generation` +1 得 g；比對鍵有 `remote_item_id` 用它，否則用（曲目鍵, 第 k 次出現）；完整刷新才刪 `seen_generation < g`、重寫 `position`。所以匯入進來的 entries 若 `remote_item_id = NULL`、`seen_generation = 0`，下一次完整刷新會以（曲目鍵, 第 k 次出現）比對。（此為既有行為描述，不含建議。）

### 3.4 寫入入口

- `PlaylistRepository.createImported({pluginId, remoteId, info: RemotePlaylistInfo, refreshIntervalHours = 24})`（`playlist_repository.dart:323-361`）：兩張表一個 transaction；若 `(pluginId, remoteId)` 已存在回 `null`。`RemotePlaylistInfo` 欄位 `name, description?, artwork[], ownerName?, writable?`（`lib/domain/playlist.dart:49-56`）。**它不接受** `lastRefreshedAt`、`lastResult`、`status`、三個 overridden 旗標、`createdAt`／`updatedAt`（`createdAt`／`updatedAt` 一律 `clock.now()`，:333-341），也**不寫 entries**。
- entries 用 `addTracks(playlistId, List<TrackInfo>)`（:654-679）：同 transaction upsert 曲目、接在歌單尾端；不接受 `remote_item_id`／`unavailable`／`seen_generation`（`PlaylistEntriesTableCompanion.insert` 只給 `playlistId, position, trackKey`），並呼叫 `_touch` 更新 `updated_at`。
- 逐欄細寫（`remote_item_id` 等）目前只有刷新 session 的 `writePage`（`playlist_repository.dart:817`）做。
- 其他寫入（驗證 `playlist_remote` 預設值/旗標）：`setWritable`（:500）、`setRefreshInterval`（:506）。

### 3.5 舊匯入歌單對應

| 舊欄位（任務描述） | 新端對應 | 備註 |
|---|---|---|
| `importSourceType` | `playlists.kind = 'imported'`；`playlist_remote.plugin_id` | 字串與插件 id 相同（`bilibili`／`youtube`／`netease`，舊 `SourceIds`） |
| `sourceUrl` | `playlist_remote.remote_id` | 新端存的是**插件解析後的歌單 id**（`PlaylistRef.playlistId`），不是網址。把網址轉成 id 的是插件匯出 `playlistFromUrl`（`AGENTS.md:1023-1024`、`1296`），需要插件已安裝；host 端沒有內建的網址解析器（`AGENTS.md:1292-1295` 描述的 `PlaylistImporter.recognize` 是問插件） |
| `refreshIntervalHours` | `playlist_remote.refresh_interval_hours` | 兩邊都是小時；新端 NULL = 不啟用；設定頁選項 1／6／12／24／48／72／168 或不啟用（`AGENTS.md:1311-1312`）；欄位本身沒有 CHECK |
| `useAuthForRefresh` | **沒有對應欄位** | 見 3.2：只有每插件的 `source_settings.browse_as_logged_in` |
| 上次刷新時間 | `last_refreshed_at` + `last_result` | `createImported` 不收；需直接寫表或另造入口 |

### 3.6 Mix 歌單

- `kind='mix'` 的列只有 `playlists` 一列：`mix_plugin_id`、`mix_seed_source_id`（種子曲目的 sourceId）、`mix_seed_cid`（可空），沒有曲目、沒有 `playlist_remote`（`AGENTS.md:1294-1295`；`playlist_repository.dart:402-425`）。入口 `createMix({name, pluginId, seedSourceId, seedCid})`。
- Mix 播放中的狀態在 `player_state.mix_*` 五欄（見 1.2），與 Mix 歌單無關。

### 3.7 外部（pairing）歌單

`PlaylistRepository.createFromMatches`（`playlist_repository.dart:363-400`）建的是 `local` 歌單 + `match_results` + `track_origins`，不寫 `playlist_remote`。舊版沒有對應資料。

---

## 4. 憑證

### 4.1 儲存位置與形狀

- `CredentialStore`（`lib/plugins/accounts/credential_store.dart`）是唯一來源。secure storage 鍵 `credentials.<插件 id>`（:103 `_key`），值 = `jsonEncode(LoginCredentials.toJson())`（:223-225）。
- `LoginCredentials`（`login_credentials.dart:10-35`）JSON：`{"cookies": {name: value,...}, "extra": {...}?}`；**只准這兩個鍵**，其他鍵 `FormatException`（:16-19）；兩個 map 的值都必須是字串（:60-69）；`extra` 空時不寫（:32-35）。
- 實際鍵：平台 adapter 加前綴 `fmp.`（prod）／`fmp-dev.`（dev）（`lib/platform/secure_storage/flutter_secure_storage_adapter.dart:46-50` `_prefixOf`、:52-61 `_full`），也就是 prod 實存鍵 = `fmp.credentials.bilibili`。Android 另設 `storageNamespace: 'fmp'`／`'fmp-dev'`，`resetOnError: false`（:39-43）。鍵只准小寫英數與 `.`、`-`（:11-12）。
- 套件：`pubspec.yaml:87` `flutter_secure_storage: ^11.2.0`（11.x）。ADR 0010／0012 要求 legacy import 以 10.x 讀舊憑證；pubspec 目前沒有 10.x，也沒有 `isar_community`（`grep` pubspec 無 isar／legacy 命中）。

### 4.2 各官方插件的憑證內容（取自 sibling `fmp-plugins` 的原始碼，非本 repo）

| 插件 | cookies 鍵 | extra | 來源 |
|---|---|---|---|
| `bilibili` | `SESSDATA`（必須）、`bili_jct`、`DedeUserID`（必要集合 `REQUIRED_COOKIES`），另 `DedeUserID__ckMd5` | `refresh_token`（刷新用，可無） | `fmp-plugins/bilibili/src/plugin.js:1274-1275`、`1323-1334`、`1364-1372`、`1431-1441` |
| `netease` | `MUSIC_U`（必須）、`__csrf`（有就放） | 無 | `fmp-plugins/netease/src/login.js:65-87` |
| `youtube` | 必要 `SAPISID`、`__Secure-1PSID`、`__Secure-3PSID`（`doneCookies`）；實際存的是 `cookieHosts` 讀到的全部 cookie | 無 | `fmp-plugins/youtube/src/login.js:12`；manifest `login.webView.doneCookies` |

登入方式：bilibili `qr`（`refresh: onStartup`）、netease `qr`、youtube `webView`＋`cookie`（`fmp-plugins/*/` 的 manifest；ADR 0029 §8）。

### 4.3 `accounts` 的顯示資訊

見 1.5。登入時的值來自 `loginVerify` 回傳 `{userId, displayName, avatar?}`（`account_service.dart:109-127`）；`avatar_json` 為 `[{"url": "...", "width"?: n}]`（:117-122）。

### 4.4 憑證與帳號列必須成對（匯入時的限制）

`CredentialStore._read`（`credential_store.dart:154-201`）在載入時：
- 有帳號列但**沒憑證** -> 刪帳號列（:176-185）；
- 有憑證但**沒帳號列** -> 刪憑證（:187-195）；
- 憑證 JSON 壞掉／secure storage 讀失敗 -> `unreadable`，不刪，30 秒重讀（:158-171、:204-214）。

所以匯入若只寫 secure storage 而不寫 `accounts` 列（或反之），下次啟動會被對齊刪掉。`accounts.user_id`、`display_name` 是 NOT NULL；舊版 `Account.userId`／`userName` 是 nullable（舊專案 `lib/data/models/account.dart:15-21`），另外舊版的 `sessionExpired` 概念對應 `status = invalidated`（`credential_store.dart:240-255` 的 `invalidate`；已失效的憑證保留不帶，`AGENTS.md:887-888`）。

### 4.5 登入後寫憑證的程式碼

- 單一寫入點：`CredentialStore.save(Account, LoginCredentials)`（`credential_store.dart:223-233` 區段，順序：`_storage.write` -> `_accounts.upsert` -> `_set`（記憶體與遮蔽登記））。
- 其呼叫者：`AccountService.login(plugin, credentials)`（`account_service.dart:109-132`），先 `plugin.loginVerify(credentials)`，通過才 `save`；三種登入方式（QR、webView、貼 cookie）共用。
- 刷新換憑證：`CredentialStore.replace`（寫 secure storage 後更新帳號列的 `last_refresh_*`）。
- 登出：`AccountService.logout`（`account_service.dart:146-150`）：憑證 -> WebView cookie -> accounts 列 -> 記憶體 cookie jar。

### 4.6 「以登入身分瀏覽與播放」

`source_settings.browse_as_logged_in`（可空）。`SourceSettingsRepository.setBrowseAsLoggedIn(pluginId, value:)`（`account_repository.dart:177-186`）。ADR 0012 §6：「legacy import 以舊開關值作為使用者設定；舊版開關範圍較窄，切換版本的發行說明寫明」。

### 4.7 secure storage 與資料庫換檔不是同一個交易

憑證寫在 `SecureStorage` 介面（`lib/platform/secure_storage/secure_storage.dart`），不在 `fmp.db`。備份／還原的設計（ADR 0034）刻意「憑證都不動」（`data_reset.dart:46-48`）。Windows 的 secure storage 檔寫在 application support 目錄（adapter docstring `flutter_secure_storage_adapter.dart:14-18`），詳見第 6 節。

---

## 5. 設定（每組欄位與語意）

### 5.1 `appearance_settings`（`tables.dart:18-31`）

只有兩欄：`theme_mode`（`system`／`light`／`dark`）、`locale`（`zh-TW`／`zh-CN`／`en`）。`NULL` = 跟隨系統（「跟隨系統」是把欄位清成 NULL，不存 `system` 當未設定，`AGENTS.md:1968-1972`）。寫入：`AppearanceSettingsRepository.write({themeMode, locale})`（`appearance_settings_repository.dart:55`）。
- **沒有主色／字型欄位**：seed color 是編譯期常數 `appSeedColor = Color(0xFF6750A4)`（`lib/ui/theme/app_theme.dart:8`）；字型 fallback 由平台層依語言決定（`AGENTS.md:1993`）。舊版主色、字型等設定在新端無處可去。

### 5.2 `network_settings`（`tables.dart:34-53`）

`cache_limit_mb`（空 = 平台預設；選項 128／256／512／1024）、`radio_status_interval_minutes`（空 = 5；`0` = 關閉；選項 0／1／3／5／10）、`chart_refresh_interval_minutes`（空 = 60；`0` = 關閉；選項 0／30／60／120／240）。`write` 的 `null` = 沒給、不動（`network_settings_repository.dart:70-90`）。setter 對選項以外的值丟 `ArgumentError`（`AGENTS.md:1923-1930`）。舊版快取設定不匯入。

### 5.3 `playback_settings`（`tables.dart:58-84`；預設見 `AGENTS.md:1931-1957`）

| 欄位 | 型別 | 預設（Notifier） | 選項／備註 |
|---|---|---|---|
| `audio_quality` | text | high | high／medium／low |
| `audio_format_priority` | text | `opus,aac` | `opus,aac`／`aac,opus`（與舊版字面相同） |
| `remember_position` | bool | true | |
| `temp_play_rewind_seconds` | int | 10 | 0／3／5／10／15／30 |
| `skip_preview_clips` | bool | true | |
| `output_device_id`／`output_device_name` | text | 無（系統預設） | 只有 Windows，裝置專屬（備份不帶） |
| `restart_rewind_seconds` | int | 0 | 選項同臨時倒退 |
| `play_history_limit` | int | 10000 | 1000／5000／10000／50000；`setPlayHistoryLimit` 寫完立即 `trimTo` |
| `auto_scroll_to_current` | bool | false | |

`PlaybackSettingsRepository.write` 涵蓋全部十欄（`playback_settings_repository.dart:116-146`，null = 不動）。

### 5.4 `source_settings`（每音源）

`browse_as_logged_in`、`match_target`、`match_rank`（見 1.5）。這是舊「use-auth-for-play」類設定的家。**沒有每音源的串流格式／音質優先**（`audio_quality`、`audio_format_priority` 是全域；請求以 `StreamRequest.quality` 送給插件，`AGENTS.md:1166-1169`）。

### 5.5 `chart_settings`／`network_settings.chart_refresh_interval_minutes`

`chart_settings(plugin_id, chart_id, enabled?, sort_order?)`。`enabled` 空 = 啟用。舊版排行榜設定若要對應，需插件實際 `chartList` 的 `chartId`（`AGENTS.md:976-979`）。

### 5.6 `developer_settings`、`layout_state`

`developer_settings(developer_mode?, log_level?, plugin_dev_folder?, report_reminder_dismissed?)`（`tables.dart:341-361`）。`layout_state(player_tab?, panel_expanded?, panel_width?≤1600)`：依裝置，備份不收（`tables.dart:263-265`）。

### 5.7 目前**沒有**落腳處的舊概念（後續里程碑）

| 舊概念 | 新端現況 |
|---|---|
| 下載（紀錄、路徑、並行數、下載資料夾） | M6（`milestones.md:151-157`）；`AGENTS.md:401` 提到「下載紀錄（M6）各自在加表的 PR 加進孤兒查詢」；目前無表 |
| 歌詞（匹配、來源設定、AI key） | M7；無表。ADR 0034 後果：M7 歌詞匹配結果將在資料庫（`milestones.md:159-165`：「舊歌詞配對以 `manual` 匯入」） |
| 桌面整合（托盤、全域快捷鍵、開機自啟、關閉縮到托盤） | M8（`milestones.md` M8 段）；`hotkey_manager`／`tray_manager` 已列在 lint 的 `platformPackages`（`layer_imports.dart:45-64`），但無設定表 |
| 主色／字型 | 無（5.1） |
| 搜尋歷史 | 本次盤點未在新端 `tables.dart` 找到對應表（未知是否有後續計畫；`grep` 僅查 tables.dart，未讀 design 文件） |
| 每音源串流優先 | 無（5.4） |
| 舊的 `useAuthForRefresh` | 無（3.5） |
| 舊快取設定 | 明確不匯入（ADR 0016 §3，`AGENTS.md:1925-1927`） |
| 電台（舊 RadioStation） | 有：`radio_stations`（`RadioRepository.add`） |
| 舊的 Mix／佇列／播放狀態 | 有：`queue_entries`＋`player_state` |

---

## 6. 資料目錄（平台與 flavor）

程式：`lib/platform/app_data_directory/`。`main()` 在 `runApp` 之前解析（`lib/main.dart:43`）。

### 6.1 Android（`app_data_directory_android.dart:72-93`）

- 目錄 = path_provider 的 application support = `Context.getFilesDir()` = `/data/user/<u>/<applicationId>/files`。
- prod applicationId `com.personal.fmp`（與舊版相同，`AGENTS.md:92-93`、`android/app/build.gradle.kts:39`）；dev `com.personal.fmp.dev`（`applicationIdSuffix = ".dev"`，:78）。
- **新端資料庫 = `/data/user/0/com.personal.fmp/files/fmp.db`**；舊版資料庫在同一個沙盒的 `app_flutter/FMP/`（註解 :66-70，舊專案 `lib/data/database/database_provider.dart:15,51`）。兩者**不同子目錄、同一個沙盒**，不重疊。dev flavor 的 `files/` 在 `com.personal.fmp.dev` 沙盒，讀不到舊沙盒。
- dev 若解析到 `com.personal.fmp` 沙盒下會拋 `LegacyDataLocationException`（:88-91）。

### 6.2 Windows（`app_data_directory_windows.dart:121-161`）

- 安裝版（程式目錄有 `unins000.exe`）：`%APPDATA%\<Company>\<ProductName>`；prod = `%APPDATA%\com.personal\fmp`，dev = `%APPDATA%\com.personal\fmp-dev`（ProductName 見 `windows/runner/app_identity.cmake:22-35`；Company `com.personal`，`AGENTS.md:134-136`）。
- 免安裝版：執行檔旁 `userdata\`（prod）／`userdata-dev\`（dev）（:146-151）。`flutter run` 出來的是免安裝版，dev 資料在 `build/windows/x64/dev/runner/<模式>/userdata-dev/`（`AGENTS.md:363-365`）。
- 資料庫檔名 `fmp.db`（`lib/data/database/open_app_database.dart:10`）；同目錄還有 `logs/`（`log_file.dart:12`）、`backups/`（`database_backups.dart:17`）。
- **與舊版目錄的重疊**：
  - 舊 `Documents\FMP\fmp_database.isar`：新端任何模式都不使用 `Documents\FMP`，不重疊。
  - 舊 `%APPDATA%\com.personal\fmp\`（舊版 secure storage 檔，`app_data_directory_windows.dart:117-120`）：**等於新端 Windows 安裝版 prod 的資料目錄**（`%APPDATA%\com.personal\fmp`）。新端 `fmp.db`、`logs\`、`backups\` 會落在舊 secure storage 檔的同一個資料夾。免安裝版 prod（`userdata\`）則不在那裡，但 secure storage 檔（flutter_secure_storage 11）仍在 application support（adapter docstring `flutter_secure_storage_adapter.dart:14-18`）= 同一個 `%APPDATA%\com.personal\fmp`。
- dev 解析結果等於或位於 `Documents\FMP` 或 `%APPDATA%\com.personal\fmp` 時，`main()` 在 `runApp` 前拋 `LegacyDataLocationException`（`app_data_directory.dart:25-51`；`AGENTS.md:366-368`）。`ensureOutsideLegacyData` 的 docstring：「只給開發版用：正式版之後要從這些位置匯入舊資料」（:44）。`main()` 沒有 catch 這個例外（`main.dart:43` 在 try 之外），所以 Windows 視窗開了但內容空白。

### 6.3 快取目錄

見 1.9。與資料目錄分開（`%LOCALAPPDATA%` / `getCacheDir()`）。

---

## 7. 啟動流程與 ADR 0034 還原機制

### 7.1 `main()`（`lib/main.dart:37-148`）

1. `AppPlatform.current(flavor)`（:41）；`directory = await platform.dataDirectory?.resolve()`（:43，沒有資料目錄的平台直接 `UnsupportedPlatformApp`，:73-76）。
2. 建 `Redactor`、`Log`（`LogFile` 在資料目錄的 `logs/`，:46-55）；寫 `App started` log（含 `dataDirectory` 欄位，:59-71）。
3. 設圖片快取上限（:78-82）。
4. `database = await openAppDatabase(directory)`，失敗 -> log + `runApp(DatabaseErrorApp(...))` 然後 `return`（:84-104）。
5. 讀 appInfo、初始化系統媒體控制（:106-116）。
6. `runApp(appProviderScope(overrides: [appDatabaseProvider.overrideWithValue(database), ... secureStorageProvider, cacheDirectoryProvider, devPluginPathProvider ...], child: FmpApp))`（:118-147）。`appRestarterProvider` 也在此注入（:133）。

`openAppDatabase(Directory)`（`open_app_database.dart:20-33`）：把檔名寫死為 `fmp.db`、以 `NativeDatabase.createInBackground(File)` 建 `AppDatabase`，跑 `SELECT 1` 強制開檔／建表／migration，失敗則 close 並 rethrow。`openInMemoryDatabase()`（:36-38）給隔離環境。

`DatabaseErrorApp`（`lib/app/database_error_app.dart:14-56`）：只顯示標題字串與 `SelectableText('$error')`；語言與主題跟隨系統（讀不到設定）；**沒有按鈕**。docstring 說「重試、匯出診斷等選項隨舊資料匯入（M5）與 log（ADR 0025）再加」（:10-12）。`AGENTS.md:377-380` 說 `main()` 這個分支沒有測試。

### 7.2 `DatabaseBackups`（`lib/data/database/database_backups.dart`）

類別住在 `lib/data/`（可用 drift/sqlite3）。建構子 `(AppDatabase, Directory dataDirectory, Log, {readPlugin})`（:56-61）。各方法的職責（描述事實）：

| 成員 | 行 | 做什麼 |
|---|---|---|
| `create()` | 86-115 | `VACUUM INTO backups/fmp-<UTC>.db`（還原／重設前的自動備份）；失敗清半成品 |
| `list()`／`exists()` | 118-142 | 列 `backups/`，最新在前 |
| `export(File)` | 149-163 | `VACUUM INTO` 暫存 -> `_scrubExport`（清不帶走的表／欄）-> `VACUUM` -> rename |
| `stageBytes(Uint8List)`／`stageFile(File)` | 172-177 | 寫 `backups/staged-<UTC>.db` 並 `_stage` 驗證 |
| `_stage` | 187-211 | 依序：`_inspect`（SQLite 標頭、`user_version` 0／過新、`integrity_check`、基礎三表、無 trigger/view）-> `_migrateAndCheck`（用 **`AppDatabase` 自己開檔跑 migration 到 18**，並比對 `sqlite_master` 的 (type,name) 與全新記憶體庫相同）-> `_rebuild`（建全新 schema，`ATTACH` 後逐表 `INSERT … SELECT`，`foreign_key_check`）-> `_readRebuilt`（讀插件清單，壞腳本的列刪掉）。任何失敗刪暫存並拋 `BackupRejected` |
| `readCarriedState()`／`carryOver(staged, state)` | 391-438 | 把這台的 `accounts`、`layout_state`、輸出裝置、`plugin_dev_folder`、`browse_as_logged_in`、dev 標記列寫進暫存檔（單一交易，背景 isolate 用 `sqlite3` 直接開檔，:662-708） |
| `restoreStaged(staged)` | 447-486 | 暫存檔 rename 為 `fmp.db.restoring`；`_database.close()`；舊 `fmp.db`（含 `-wal/-shm/-journal`）rename 為 `fmp.db.before-restore-<UTC>`；`.restoring` rename 為 `fmp.db`；失敗則把舊檔改回；設 `_closed = true` |
| `erase()` | 526-532 | 關閉並刪檔 |
| `discard(staged)` | 441-442 | 刪暫存 |

與 M5 的耦合點（事實）：
- `_stage`／`_inspect` 的前提是「來源檔已經是 FMP 的 SQLite，`user_version` ≥ 1」（`_inspect` :628，`_baseTables` :567-571）。legacy Isar 檔不是 SQLite，進不了這條路；但**寫出的 staging `.db`** 若是以 `AppDatabase` 建的，`user_version` 會是 18、schema 與全新庫一致，可以通過 `_inspect`／`_migrateAndCheck`／`_rebuild`（`_rebuild` 的複製欄位清單是 `fresh.allTables`，:337-346）。
- `restoreStaged` 需要 `StagedBackup`（`backup_format.dart:158-175`，`path`、`plugins`、`unusablePluginIds`、`indexUrls`）與 `DatabaseBackups` 實例（綁在開著的 `_database`，因為要 `close()` 它）。換檔語意（rename 原檔留作 `.before-restore-<stamp>`）可直接用於「staging -> 正式」，但 `restoreStaged` 假設有一個已開啟的 `_database`；`main()` 在 DB 開啟之前（匯入時）沒有這個實例。
- `DataReset.restoreAndRestart`（`lib/app/data_reset.dart:118-131`）：`backUp()`（失敗就停）-> `carryOver(staged, readCarriedState())` -> `_closeDatabaseAndRestart(work: restoreStaged)` -> `_restart`（`log.file?.flush()` 後 `restarter.restart()`）。這是依賴 Riverpod（`dataResetProvider`，:160-178）且依賴 `appDatabaseProvider` 已覆寫的組裝。
- 重啟：`AppRestarter`（`lib/platform/app_restart/app_restart.dart`）。Windows 自己起來（`platform.dart:168` `restartsItself: true`）；Android **不會**（`platform.dart:105` `restartsItself: false`，`app_restart_android.dart` 結束行程，由使用者再開）。
- `Log`（`lib/core/logging/log.dart`）在 `main()` 開 DB 前已建好（`main.dart:48-56`），可在匯入階段使用。

### 7.3 設定頁／Debug 頁入口接線

- 設定頁 `lib/ui/settings/settings_page.dart:238` 放 `BackupControls`（`lib/ui/settings/backup_controls.dart:27`）：`appBackupProvider.pickAndStage()`（:75）-> `lib/ui/backup/restore_flow.dart`（`RestoreConfirmDialog` :90；`work: () => reset.restoreAndRestart(staged)` :73）。
- Debug 頁 `lib/ui/debug/debug_data_actions.dart` 也用 `dataResetProvider`。
- `AppBackup`（`lib/app/backup.dart:157-165`）：`export()`、`pickAndStage()`；`FileAppBackup.pickAndStage` 以 `fileDialogs.pickFile(extension: 'db', maxBytes: 1 GiB)` 讀入記憶體再 `stageBytes`（:213-246）。副檔名過濾寫死 `db`；舊 JSON 備份（`fmp_backup_<時間>.json`）不會被選到。
- ADR 0034「之後要注意」：「M5：舊 JSON 備份由 `legacy_import` 轉換（ADR 0010 §決定 4），是否共用『從備份檔還原』的入口由 M5 定」（`docs/adr/0034-...md:61`）。
- 新端 `.db` 備份的 `user_version` 是 FMP schema 版本；舊 JSON 備份是 `kBackupVersion = 5` 的 JSON（ADR 0034 背景 :16）。

---

## 8. 開發入口（dev entry）

- `lib/plugins/install/dev_plugin_entry.dart:19-41`：`--fmp-dev-plugin=<路徑>`（參數優先）與環境變數 `FMP_DEV_PLUGIN`；`devPluginPath(flavor, arguments, environment)` 在非 dev 回 `null`（:32）。
- 接線：`main(List<String> arguments)`（`main.dart:37`）-> `devPluginPathProvider.overrideWithValue(devPluginPath(flavor, arguments, Platform.environment))`（`main.dart:141-143`）；消費端 `devPluginInstallProvider`（`dev_plugin_entry.dart:48-71`）。除此之外 `main.dart` **沒有其他命令列參數**。
- 為何 dev only：這條路徑跳過 ADR 0014 §6 的安裝前確認，而命令列／intent extra／環境變數都能由別的程式帶入（`dev_plugin_entry.dart:11-17`）。閘門：`plugin_installer_test.dart` 的 `development entry`（含 `prod reads neither…`，`AGENTS.md:1136-1140`）。
- 帶法（`.claude/skills/verify-on-device/references/runtime-state.md:54-73`）：Windows 直接給絕對路徑、環境變數用 `$env:FMP_DEV_PLUGIN=...; Start-Process`；Android `adb shell am start -n com.personal.fmp.dev/com.personal.fmp.MainActivity --esal dart_entrypoint_args --fmp-dev-plugin=<App 讀得到的路徑>`，檔案須先複製進 App 私有目錄。
- 與 legacy 的相關事實：dev 的資料目錄被禁止落在舊位置（6.2），dev 讀舊資料只能讀別的路徑（例如副本）；`LegacyDataLocationException` 只管「資料目錄」，不管「從哪裡讀 legacy」。目前沒有任何參數或環境變數指向 legacy 資料。

---

## 9. Lint：`fmp_layer_imports` 與 `lib/legacy_import/`

規則檔：`packages/fmp_lints/lib/src/rules/layer_imports.dart`。`lib/legacy_import/` 目前**不存在**（`ls lib` 無此目錄）。

與 `legacy_import` 有關的條目：
- `externalPackageOwners`（:12-42）：`'isar_community': 'lib/legacy_import'`（:14）；`drift`、`sqlite3` -> `lib/data`（:15-16）；`flutter_secure_storage`、`path_provider`、`file_picker` 等 -> `lib/platform`（`platformPackages` :45-64，`flutter_secure_storage` 在 :61）。
- `sealedDirectories = ['lib/legacy_import']`（:118）；`_internalViolation`（:244-250）：目標在 sealed 目錄、來源**不在其內**就報 `lib/legacy_import/ is only imported from inside itself`。檢查對象是 `lib/` 內所有檔案，沒有任何例外清單，所以 `lib/main.dart`、`lib/app/`、`lib/data/` 都**不能** import `lib/legacy_import/`。測試：`layer_imports_test.dart:212-215`（`lib/data/database.dart` 被報）、:491-496（`lib/legacy_import/reader.dart` 可 import `isar_community` 與自己目錄）、:719-722（`test/` 不受限）。
- `forbiddenLayerImports`（:67-103）沒有以 `lib/legacy_import` 為「來源」的條目 -> legacy_import 可以 import `lib/core`、`lib/domain`、`lib/data`、`lib/plugins`、`lib/settings`、`lib/platform`……任何目錄（沒有被禁）。但**外部套件**限制仍適用於它：不能 import `drift`／`sqlite3`（只准 `lib/data`）、不能 import `flutter_secure_storage`／`path_provider`（只准 `lib/platform`）。所以 legacy_import 對 DB 的寫入只能透過 `lib/data/` 公開的型別（repository、`AppDatabase`）。（`AppDatabase` 本身是 `lib/data/database/app_database.dart` 的類別，其建構子參數型別是 drift 的 `QueryExecutor`，但 import 它不需要 import `package:drift`。）
- `fmp_source_id_literal`（`source_id_literal.dart:26`）：`sourceIdAllowedDirectories = ['lib/legacy_import', 'test']` 才能寫 `'bilibili'` 之類字面值。
- ADR 0010 §4 說 legacy import 是「唯一依賴 `isar_community` 與 `flutter_secure_storage` 10.x 的地方」，但 lint 表中 `flutter_secure_storage` 的擁有者是 `lib/platform`（`layer_imports.dart:61`），`lib/legacy_import` 沒有例外；pubspec 目前只有 `flutter_secure_storage ^11.2.0`（`pubspec.yaml:87`）。
- ADR 0010 後果段 :75：`isar_community_generator` 3.3.2 要求 `analyzer <11`，與 workspace 的 analyzer 13 衝突，M5 在 workspace 外產生 `*.g.dart` 後提交。
- 沒有以 `lib/legacy_import` 為對象的 sentinel 項：`tool/lint_sentinel.dart` 的覆蓋範圍我沒逐條讀（lint 表見 `AGENTS.md:2765-2806`，未列 legacy_import 專屬閘門以外的條目）。

---

## 10. Repository 寫入 API（是否可作用於任意 `AppDatabase` 實例）

**共通事實**：所有 repository 都是 `Repository(AppDatabase)` 建構子注入（`lib/data/providers.dart:30-120` 的每個 provider 都是 `XRepository(ref.watch(appDatabaseProvider))`）。因此對任何 `AppDatabase` 實例（包含以另一個檔案的 executor 建的 staging 實例）都能直接 `XRepository(stagingDb)`，不需經 Riverpod。`AppDatabase(super.executor)`（`app_database.dart:51`）執行器由呼叫端注入，`open_app_database.dart` 的 `openAppDatabase` 只認 `fmp.db` 檔名。

寫入時外鍵為 ON（`app_database.dart:61`）。

| 目標 | API | 簽名／行為（行） | 備註 |
|---|---|---|---|
| tracks | `TracksRepository.upsert(Iterable<TrackInfo>)` | `tracks_repository.dart:18-42`，`batch.insertAllOnConflictUpdate`；`updated_at` = `clock.now()` | `TrackInfo(sourceTypeId, sourceId, cid?, title, uploader?, duration?, artwork[], partIndex?, parentTitle?)`（`lib/domain/track_info.dart`）；artwork 是 `TrackArtwork(url: Uri, width?)` |
| local 歌單 | `PlaylistRepository.create({name, description?, artwork})` | `playlist_repository.dart:299-317`；`created_at`/`updated_at` = now；`sort_order` = max+1 | 無法指定 created/updated；回傳新 id |
| 歌單曲目 | `addTracks(playlistId, List<TrackInfo>)` | :654-679；同交易 upsert tracks；接在尾端；觸發 `_touch`（更新 `updated_at`） | 可重複同曲目 |
| imported 歌單 | `createImported(...)` | :323-361（見 3.4） | 重複回 null |
| mix 歌單 | `createMix(...)` | :402-425 | |
| 歌單排序 | `reorder(List<int> ids)` | :619 | 整批重寫 `sort_order` |
| 播放歷史 | `PlayHistoryRepository.record(TrackInfo, {playedAt, limit})` | `play_history_repository.dart:47-62`；每筆一個交易：upsert 曲目 + insert + `_trim(limit)` | `playedAt` 可由呼叫端指定；`limit` 必給；逐筆 trim；無批次 API；另有 `trimTo`（:107） |
| 電台 | `RadioRepository.add({pluginId, roomId, title, hostName?, artwork, addedAt, liveStatus?, liveTitle?, statusCheckedAt?})` | `radio_repository.dart:98-138`；查重、接在 max(sort_order)+1；回 bool | `addedAt` 可指定；順序由呼叫次序決定；`reorder(ids)` :145 |
| 佇列＋播放狀態 | `QueueRepository.write({edit?, shuffleRanks, player})` | `queue_repository.dart:163-190`；`edit = QueueRangeEdit(from, removed, inserted: List<TrackInfo>)`（:85-95）；`player = PlayerState(currentPosition, position, loopMode, shuffleEnabled, volume, muted, mix?)`（:15-40） | `updated_at` = now；`reset()` :192 |
| 外觀 | `AppearanceSettingsRepository.write({themeMode?, locale?})` | `appearance_settings_repository.dart:55` | null = 不動 |
| 網路 | `NetworkSettingsRepository.write({cacheLimitMebibytes?, radioStatusIntervalMinutes?, chartRefreshIntervalMinutes?})` | `network_settings_repository.dart:71-90` | |
| 播放 | `PlaybackSettingsRepository.write({...十欄})` | `playback_settings_repository.dart:116-146` | |
| 開發者 | `DeveloperSettingsRepository.write(...)` | `developer_settings_repository.dart:75` | |
| 圖表 | `ChartSettingsRepository.setEnabled/setOrder` | `chart_settings_repository.dart:53,69` | |
| 版面 | `LayoutStateRepository.write(...)` | `layout_state_repository.dart:59` | 裝置專屬 |
| 帳號 | `AccountRepository.upsert(Account)` | `account_repository.dart:88-100` | 不含憑證 |
| 每音源 | `SourceSettingsRepository.setBrowseAsLoggedIn(pluginId, value:)` | :177-186 | 每插件一列 |
| 插件 | `PluginRepository.install(InstalledPlugin)` | `plugin_repository.dart:87-100`；`insertOnConflictUpdate` | 需要 manifest、script 全文；一般安裝走 `PluginInstaller`（下載 + SHA 驗證） |
| 自訂 index | `PluginIndexRepository.add(url, addedAt)` | :240 | |
| 匹配 | `PlaylistRepository.createFromMatches` | :363 | 舊版無對應資料 |
| 孤兒清理 | `TracksRepository.deleteOrphans()` | :46 | 啟動維護 `orphan-tracks`（`lib/app/startup_maintenance.dart:54`）會刪沒被佇列／歷史／歌單／match 參照的曲目 |

repository **沒有**的：批次寫歷史、指定 `created_at`／`updated_at` 的歌單、寫 `playlist_entries.remote_item_id`／`unavailable`／`seen_generation` 的入口（只有刷新 session）、直接寫 `playlist_remote.last_refreshed_at`／`last_result`／`status`（`createImported` 不收；只有 `PlaylistRefreshSession` 的 `_write`／`markPartial`／`markFailed`／`markStatus`，`playlist_repository.dart:953-972`）。需要這些時，`lib/data/` 內可直接用 `AppDatabase` 的 `*Table`（drift API 只能在 `lib/data/` 使用）。

驗證用既有工具：`DatabaseInspector`（`lib/data/repositories/database_inspector.dart`）提供 `tables()`（各表筆數，:68）與 `check()`（`integrity_check`、`foreign_key_check`、孤兒曲目數，:141）；以 `AppDatabase` 建構，所以可對 staging 實例用。

---

## Related Specs

- `.trellis/spec/app/data/index.md`（加表、改 schema、migration）；`.trellis/spec/app/settings/index.md`；`.trellis/spec/app/plugins/index.md`；`.trellis/spec/app/lints/index.md`（本次未逐檔讀，僅依 AGENTS.md 指引列出）。
- ADR：`docs/adr/0010`（匯入）、`0008`（身分沿用）、`0009`（資料目錄）、`0012`／`0029`（憑證）、`0030`（插件生命週期與首次引導）、`0033`（音樂庫）、`0034`（備份與還原）。
- `.trellis/tasks/09-26-fmp-rewrite/milestones.md:145-153`（M5 範圍與驗收）。

## Caveats / Not Found

- 官方插件 id 與憑證 cookie 名稱的證據來自 sibling repo `<同層>/fmp-plugins`（不在本 repo；branch `main`），且是該 repo 當下的工作樹；`<同層>/fmp-plugins-yt`（branch `feat/youtube`）的 index 較舊，不採用。
- 我沒有讀舊（根目錄 `lib/`）資料模型的完整欄位，只在需要對照時引用（`SourceIds`、`Account`、secure storage 類別）。舊 Isar collection 的欄位清單（Track、Playlist、PlayHistory、RadioStation、Settings 等）要另外盤點。
- 「搜尋歷史」在新端是否有承接表：`tables.dart` 沒有，其他文件我沒查。
- `tool/lint_sentinel.dart` 對 `lib/legacy_import` 的覆蓋沒有逐行讀。
- 「`main.dart` 不能 import `lib/legacy_import`」是依 `_internalViolation` 的程式邏輯推得（:244-250）；測試只用 `lib/data/...` 當來源（`layer_imports_test.dart:212-215`），沒有專門以 `lib/main.dart` 為來源的案例。
- 全部為讀碼，未執行任何程式、未碰使用者真實資料夾。
