import 'package:drift/drift.dart';

import 'package:fmp/data/database/converters.dart';

// Schema v4（M1 的 v1，M2 加 network_settings（v2）、playback_settings（v3）與 tracks、
// queue_entries、player_state（v4））。改這個檔案就是改 schema：bump `AppDatabase.schemaVersion`、
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

  @override
  Set<Column<Object>> get primaryKey => {id};
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
