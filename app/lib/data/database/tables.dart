import 'package:drift/drift.dart';

import 'package:fmp/data/database/converters.dart';

// Schema v15（M1 的 v1，M2 加 network_settings（v2）、playback_settings（v3）、tracks、
// queue_entries、player_state（v4）、play_history（v5）與 layout_state（v6），M3 加
// installed_plugins 的三欄與 plugin_indexes（v7）、accounts 與 source_settings（v8）、
// developer_settings（v9）、scheduler_runs（v11）、radio_stations 與
// network_settings 的電台間隔（v12）、player_state 的 Mix 五欄（v13）、tracks 的分 P 兩欄（v14）），M4 加
// playlists 與 playlist_entries（v15）。
// 改這個檔案就是改 schema：bump `AppDatabase.schemaVersion`、
// 存新快照、寫 migration 與升級測試（.trellis/spec/app/data/index.md）。
// SQL 表名以 `tableName` 寫死，Dart 類別改名不會改到資料庫。

/// 外觀設定，單列（ADR 0011 §決定 7）。欄位為空＝使用者沒設定過。
@DataClassName('AppearanceSettingsRow')
class AppearanceSettingsTable extends Table {
  @override
  String get tableName => 'appearance_settings';

  /// 固定為 1；CHECK 讓第二列插不進去。
  late final IntColumn id = integer().check(id.equals(1))();
  late final themeMode = text().nullable().map(
    const ThemeModeSettingConverter(),
  )();
  late final locale = text().nullable().map(const LocaleSettingConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 「網路」設定，單列（ADR 0011 §決定 7）。欄位為空＝使用者沒設定過。
@DataClassName('NetworkSettingsRow')
class NetworkSettingsTable extends Table {
  @override
  String get tableName => 'network_settings';

  /// 固定為 1；CHECK 讓第二列插不進去。
  late final IntColumn id = integer().check(id.equals(1))();

  /// 快取上限（MiB）；空＝平台宣告的預設（ADR 0016 §決定 3）。
  late final cacheLimitMb = integer().nullable()();

  /// 電台狀態刷新間隔（分）；`0`＝關閉，空＝預設（ADR 0017 §決定 6、M3 design §3.3）。
  late final radioStatusIntervalMinutes = integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 「播放」設定，單列（ADR 0011 §決定 7、design §3.3）。欄位為空＝使用者沒設定過，
/// 預設只在 Notifier 套用。整組欄位在 M2 PR 10 一次建好，各欄位的 setter 跟著
/// 用到它的 PR 加。
@DataClassName('PlaybackSettingsRow')
class PlaybackSettingsTable extends Table {
  @override
  String get tableName => 'playback_settings';

  /// 固定為 1；CHECK 讓第二列插不進去。
  late final IntColumn id = integer().check(id.equals(1))();
  late final audioQuality = text().nullable().map(
    const AudioQualityConverter(),
  )();
  late final audioFormatPriority = text().nullable().map(
    const AudioFormatPriorityConverter(),
  )();
  late final rememberPosition = boolean().nullable()();
  late final tempPlayRewindSeconds = integer().nullable()();
  late final skipPreviewClips = boolean().nullable()();

  /// 偏好的輸出裝置（只有 Windows）：mpv 的裝置名與顯示用的描述。
  late final outputDeviceId = text().nullable()();
  late final outputDeviceName = text().nullable()();
  late final restartRewindSeconds = integer().nullable()();
  late final playHistoryLimit = integer().nullable()();
  late final autoScrollToCurrent = boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 從檔案安裝的插件（ADR 0014）。
@DataClassName('InstalledPluginRow')
class InstalledPluginsTable extends Table {
  @override
  String get tableName => 'installed_plugins';

  /// 音源 id，例如 B 站插件的 id。
  late final id = text()();
  late final version = text()();
  late final manifestJson = text()();
  late final script = text()();

  /// UTC epoch 毫秒。
  late final installedAt = integer().map(const EpochMillisecondsConverter())();

  /// 啟用與否（ADR 0030 §決定 7）；停用的插件不載入。升級前裝好的列為真。
  late final enabled = boolean().withDefault(const Constant(true))();

  /// 來自哪個 index 網址；空＝從檔案或網址安裝（ADR 0030 §決定 6）。
  late final sourceIndexUrl = text().nullable()();

  /// 從 index 安裝時一併存的 `checks.json` 原文，給健康檢查用；沒有就是空。
  late final checksJson = text().nullable()();

  /// 真＝這一列是插件開發工具為了 `plugin_storage` 的外鍵補的，不是使用者裝的
  /// （M3 PR 16b）；每次套用開發資料夾時對齊，不屬於資料夾的標記列會被刪掉。
  late final fromDevFolder = boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 使用者加的自訂插件 index（ADR 0030 §決定 6）。官方 index 不存在這裡，網址在
/// `endpoints.dart`。
@DataClassName('PluginIndexRow')
class PluginIndexesTable extends Table {
  @override
  String get tableName => 'plugin_indexes';

  late final url = text()();

  /// UTC epoch 毫秒。
  late final addedAt = integer().map(const EpochMillisecondsConverter())();

  @override
  Set<Column<Object>> get primaryKey => {url};
}

/// 每個插件自己的 key／value（ADR 0014 §決定 5）。移除插件時由外鍵的
/// `ON DELETE CASCADE` 一起清掉（ADR 0014 §決定 8）。
@DataClassName('PluginStorageRow')
class PluginStorageTable extends Table {
  @override
  String get tableName => 'plugin_storage';

  late final pluginId = text().references(
    InstalledPluginsTable,
    #id,
    onDelete: KeyAction.cascade,
  )();
  late final key = text()();
  late final value = text()();

  @override
  Set<Column<Object>> get primaryKey => {pluginId, key};
}

/// 曲目的顯示資料（design §3.1）：佇列與（之後的）播放歷史以外鍵參照它，音源是
/// 權威，曲目進入佇列時以新值覆蓋。只放 M2 用得到、而且是音源給的事實。
@DataClassName('TrackRow')
class TracksTable extends Table {
  @override
  String get tableName => 'tracks';

  /// `TrackKey.format` 的輸出（ADR 0005）。
  late final trackKey = text()();

  /// 曲目鍵的三段，查詢與 M5 對照用。
  late final sourceTypeId = text()();
  late final sourceId = text()();
  late final cid = integer().nullable()();
  late final title = text()();
  late final uploader = text().nullable()();
  late final durationMs = integer().nullable()();

  /// `[{url, width?}]`，ADR 0016 §決定 4 的 DTO 原樣。
  late final artworkJson = text().nullable()();

  /// 最後一次 upsert。
  late final updatedAt = integer().map(const EpochMillisecondsConverter())();

  /// 分 P 曲目才有：分 P 的序號（從 1 起）與影片標題（M3 design §3.1、§11.1）。
  late final partIndex = integer().nullable()();
  late final parentTitle = text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {trackKey};
}

/// 佇列的每個位置（design §3.2）。`RESTRICT`：被佇列參照的曲目刪不掉，孤兒清理
/// 只刪沒人參照的。主鍵是位置，位移時先改成負值再改回，避開主鍵衝突，所以不能
/// 加 `position >= 0` 的檢查。`track_key` 有索引：刪曲目時 `RESTRICT` 的檢查靠它，沒有的話
/// 每刪一列都要掃一次佇列（孤兒清理）。
@TableIndex(name: 'queue_entries_track_key', columns: {#trackKey})
@DataClassName('QueueEntryRow')
class QueueEntriesTable extends Table {
  @override
  String get tableName => 'queue_entries';

  late final position = integer()();
  late final trackKey = text().references(
    TracksTable,
    #trackKey,
    onDelete: KeyAction.restrict,
  )();

  /// 隨機開啟時，這個位置在本輪排列裡的名次（ADR 0018 §決定 5：隨機順序以位置為
  /// 單位，所以跟著位置走，不跟著歌）；沒開隨機時為空。
  late final shuffleRank = integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {position};
}

/// 播放狀態，單列（design §3.2、ADR 0018 §決定 10）。不是設定：音量與靜音隨佇列
/// 存在這裡。速度不持久化。
@DataClassName('PlayerStateRow')
class PlayerStateTable extends Table {
  @override
  String get tableName => 'player_state';

  /// 固定為 1；CHECK 讓第二列插不進去。
  late final IntColumn id = integer().check(id.equals(1))();

  /// 佇列目前這首的位置；佇列是空的時為空。
  late final currentPosition = integer().nullable()();
  late final positionMs = integer()();
  late final loopMode = text().map(const LoopModeConverter())();
  late final shuffleEnabled = boolean()();

  /// 0–1；靜音時是取消靜音後回到的值。
  late final volume = real()();
  late final muted = boolean()();

  /// 空（舊版的列）或 `queue`＝一般佇列；`mix`＝Mix，身分在下面四欄（M3 PR 19）。
  late final mode = text().nullable().map(const PlayerModeConverter())();
  late final mixPluginId = text().nullable()();
  late final mixId = text().nullable()();
  late final mixTitle = text().nullable()();

  /// 插件的不透明字串；空＝這個 Mix 沒有更多。
  late final mixCursor = text().nullable()();
  late final updatedAt = integer().map(const EpochMillisecondsConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 播放歷史（design §3.2、§7.8）：一次播放一列。`RESTRICT`：被歷史參照的曲目刪不掉，
/// 孤兒清理只刪沒人參照的。`played_at` 的索引給倒序分頁，`track_key` 的索引給刪曲目時
/// `RESTRICT` 的檢查（沒有的話孤兒清理每刪一列掃一次整張表）。
@TableIndex(name: 'play_history_played_at', columns: {#playedAt})
@TableIndex(name: 'play_history_track_key', columns: {#trackKey})
@DataClassName('PlayHistoryRow')
class PlayHistoryTable extends Table {
  @override
  String get tableName => 'play_history';

  late final id = integer().autoIncrement()();
  late final trackKey = text().references(
    TracksTable,
    #trackKey,
    onDelete: KeyAction.restrict,
  )();
  late final playedAt = integer().map(const EpochMillisecondsConverter())();
}

/// 依裝置記住的版面狀態，單列（design §3.4）。不屬於任何設定組：設定包含在備份裡，
/// 還原到另一台裝置時不該帶來這台的面板寬度，所以 M4 的備份不收它。欄位為空＝沒記過。
/// 面板的兩欄在播放頁這一版就建好（右側面板在 M2 PR 19 接上），免得再升 schema。
@DataClassName('LayoutStateRow')
class LayoutStateTable extends Table {
  @override
  String get tableName => 'layout_state';

  /// 固定為 1；CHECK 讓第二列插不進去。
  late final IntColumn id = integer().check(id.equals(1))();

  /// 播放頁右欄上次選的分頁。
  late final playerTab = text().nullable().map(const PlayerTabConverter())();

  /// 右側「正在播放」面板展開與否。
  late final panelExpanded = boolean().nullable()();

  /// 右側面板的寬度（dp）。資料庫只擋明顯的壞值，實際範圍在讀取時依視窗夾取。
  late final RealColumn panelWidth = real().nullable().check(
    panelWidth.isSmallerOrEqualValue(1600),
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 登入過的插件的帳號顯示資訊（ADR 0029 §決定 6）。一列＝一個插件。憑證本身在
/// secure storage，是否登入只看 `CredentialStore`；啟動時列與憑證不一致就刪掉多的
/// 那一邊。沒有外鍵到 `installed_plugins`：插件 id 只是字串（design §3.1）。
@DataClassName('AccountRow')
class AccountsTable extends Table {
  @override
  String get tableName => 'accounts';

  late final pluginId = text()();
  late final userId = text()();
  late final displayName = text()();

  /// `Artwork[]` 的 JSON；沒有頭像為空。
  late final avatarJson = text().nullable()();
  late final status = text().map(const AccountStatusConverter())();
  late final loggedInAt = integer().map(const EpochMillisecondsConverter())();
  late final lastRefreshAt = integer().nullable().map(
    const EpochMillisecondsConverter(),
  )();
  late final lastRefreshResult = text().nullable().map(
    const RefreshResultConverter(),
  )();

  @override
  Set<Column<Object>> get primaryKey => {pluginId};
}

/// 每音源設定（ADR 0011 §決定 7）。不是設定「組」：以插件 id 讀寫。欄位為空＝
/// 沒設定過，用 manifest 宣告的預設。登出時保留。
@DataClassName('SourceSettingsRow')
class SourceSettingsTable extends Table {
  @override
  String get tableName => 'source_settings';

  late final pluginId = text()();

  /// 「以登入身分瀏覽與播放」（ADR 0012 §決定 6）。
  late final browseAsLoggedIn = boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {pluginId};
}

/// 「開發者」設定，單列（ADR 0025 §決定 1、M3 design §3.3）。欄位為空＝使用者沒設定過，
/// 預設只在 Notifier 套用。四個欄位在 M3 PR 11 一次建好，setter 跟著用到它的 PR 加。
@DataClassName('DeveloperSettingsRow')
class DeveloperSettingsTable extends Table {
  @override
  String get tableName => 'developer_settings';

  /// 固定為 1；CHECK 讓第二列插不進去。
  late final IntColumn id = integer().check(id.equals(1))();
  late final developerMode = boolean().nullable()();
  late final logLevel = text().nullable().map(
    const LogLevelSettingConverter(),
  )();

  /// 插件開發資料夾的路徑（ADR 0025 §決定 7，M3 PR 16）。
  late final pluginDevFolder = text().nullable()();

  /// 「送出前請檢查」不再提醒（ADR 0023 §決定 4、ADR 0025 §決定 10，M3 PR 13）。
  late final reportReminderDismissed = boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 排程器的上次成功時間（ADR 0017 §決定 2、M3 design §3.1）：每個工作 id 一列，重啟後
/// 照它算下一次到期。沒有外鍵到 `installed_plugins`，工作 id 只是字串。
@DataClassName('SchedulerRunRow')
class SchedulerRunsTable extends Table {
  @override
  String get tableName => 'scheduler_runs';

  late final jobId = text()();
  late final lastSuccessAt = integer().map(
    const EpochMillisecondsConverter(),
  )();

  @override
  Set<Column<Object>> get primaryKey => {jobId};
}

/// 電台清單（ADR 0031 §決定 1、M3 design §3.1）：使用者存的直播間。最後一次查到的直播狀態也
/// 存在這裡，啟動時先顯示（ADR 0017 §決定 3）；「查詢失敗」只在記憶體，不存。沒有外鍵到
/// `installed_plugins`：插件移除或停用時電台保留，重新安裝後恢復。
@DataClassName('RadioStationRow')
class RadioStationsTable extends Table {
  @override
  String get tableName => 'radio_stations';

  late final id = integer().autoIncrement()();
  late final pluginId = text()();

  /// 音源內的直播間 id（`liveStatus` 回傳的那個，不一定是網址裡的）。
  late final roomId = text()();
  late final title = text()();
  late final hostName = text().nullable()();

  /// `[{url, width?}]` 的 JSON，同 `tracks.artwork_json`；沒有封面為空。
  late final artworkJson = text().nullable()();

  /// 清單順序，由小到大；拖曳後整批重寫。
  late final sortOrder = integer()();
  late final addedAt = integer().map(const EpochMillisecondsConverter())();

  /// 最後一次查到的狀態；還沒查過為空。
  late final liveStatus = text().nullable().map(
    const RadioLiveStatusConverter(),
  )();
  late final liveTitle = text().nullable()();
  late final statusCheckedAt = integer().nullable().map(
    const EpochMillisecondsConverter(),
  )();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {pluginId, roomId},
  ];
}

/// 歌單（ADR 0033 §決定 1、M4 design §3.1）：`local` 使用者自建、`imported` 從網址匯入、
/// `mix` 是 Mix 歌單。Mix 三欄只有 `mix` 用，CHECK 讓兩種形狀不會混：`mix` 時
/// 插件 id 與種子的音源 id 非空，否則三欄都空。`sort_order` 由小到大，拖曳後整批重寫。
@DataClassName('PlaylistRow')
class PlaylistsTable extends Table {
  @override
  String get tableName => 'playlists';

  late final id = integer().autoIncrement()();
  late final kind = text().map(const PlaylistKindConverter())();
  late final name = text()();
  late final description = text().nullable()();

  /// `[{url, width?}]` 的 JSON，同 `tracks.artwork_json`；沒有封面為空。
  late final artworkJson = text().nullable()();
  late final sortOrder = integer()();
  late final createdAt = integer().map(const EpochMillisecondsConverter())();
  late final updatedAt = integer().map(const EpochMillisecondsConverter())();
  late final mixPluginId = text().nullable()();
  late final mixSeedSourceId = text().nullable()();
  late final mixSeedCid = integer().nullable()();

  @override
  List<String> get customConstraints => [
    "CHECK ((kind = 'mix' AND mix_plugin_id IS NOT NULL "
        'AND mix_seed_source_id IS NOT NULL) '
        "OR (kind <> 'mix' AND mix_plugin_id IS NULL "
        'AND mix_seed_source_id IS NULL AND mix_seed_cid IS NULL))',
  ];
}

/// 歌單裡的每一首（M4 design §3.1）。`playlist_id` 連帶刪除；`track_key` 是 `RESTRICT`：
/// 被歌單參照的曲目刪不掉，孤兒清理只刪沒人參照的，所以 `track_key` 有索引（理由同
/// `queue_entries`）。`position` 不唯一，順序是（`position`, `id`），搬動時整批重寫。
/// 後三欄只有匯入歌單用（M4 design §5.2）。
@TableIndex(
  name: 'playlist_entries_playlist',
  columns: {#playlistId, #position},
)
@TableIndex(name: 'playlist_entries_track_key', columns: {#trackKey})
@DataClassName('PlaylistEntryRow')
class PlaylistEntriesTable extends Table {
  @override
  String get tableName => 'playlist_entries';

  late final id = integer().autoIncrement()();
  late final playlistId = integer().references(
    PlaylistsTable,
    #id,
    onDelete: KeyAction.cascade,
  )();
  late final position = integer()();
  late final trackKey = text().references(
    TracksTable,
    #trackKey,
    onDelete: KeyAction.restrict,
  )();
  late final remoteItemId = text().nullable()();
  late final unavailable = boolean().withDefault(const Constant(false))();
  late final seenGeneration = integer().withDefault(const Constant(0))();
}
