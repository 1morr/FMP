import 'package:drift/drift.dart';

import 'package:fmp/data/database/app_database.steps.dart';
import 'package:fmp/data/database/converters.dart';
import 'package:fmp/data/database/tables.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/developer.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/player_mode.dart';
import 'package:fmp/domain/player_tab.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/radio.dart';
import 'package:fmp/domain/stream_preferences.dart';

part 'app_database.g.dart';

/// App 唯一的資料庫（ADR 0010）。只有 `lib/data/` 使用它（lint
/// `fmp_layer_imports` 擋其他目錄 import drift）；上層透過
/// `lib/data/repositories/` 存取。
///
/// 執行器從建構子注入：App 用 `openAppDatabase` 開資料目錄裡的檔案，測試用
/// `NativeDatabase.memory()`。
@DriftDatabase(
  tables: [
    AppearanceSettingsTable,
    NetworkSettingsTable,
    PlaybackSettingsTable,
    InstalledPluginsTable,
    PluginIndexesTable,
    PluginStorageTable,
    TracksTable,
    QueueEntriesTable,
    PlayerStateTable,
    PlayHistoryTable,
    SearchHistoryTable,
    LayoutStateTable,
    AccountsTable,
    SourceSettingsTable,
    DeveloperSettingsTable,
    SchedulerRunsTable,
    RadioStationsTable,
    PlaylistsTable,
    PlaylistEntriesTable,
    PlaylistRemoteTable,
    ChartSettingsTable,
    MatchResultsTable,
    TrackOriginsTable,
    LegacyImportsTable,
    LegacyPlaylistIdsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// 改了 `tables.dart` 就要加一，並存新快照（drift_schemas/）。
  @override
  int get schemaVersion => 22;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // SQLite 預設不檢查外鍵，而且這個設定只對目前連線有效，每次開啟都要設
    // （ADR 0019 §決定 1）。放在 beforeOpen：migration 跑完之後、第一個查詢之前。
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
    // 失敗要整個回滾（ADR 0010 §決定 3），而 drift 不會自己把 onUpgrade 包進
    // 交易，所以照 `Migrator.runMigrationSteps` 的 dartdoc 改兩處：外鍵檢查與
    // `user_version` 都在交易內。`PRAGMA foreign_keys` 在交易內無效，所以在交易外
    // 關、開。
    onUpgrade: (m, from, to) async {
      await customStatement('PRAGMA foreign_keys = OFF');
      await transaction(() async {
        await m.runMigrationSteps(
          from: from,
          to: to,
          steps: migrationSteps(
            from1To2: (m, schema) async {
              await m.create(schema.networkSettings);
            },
            from2To3: (m, schema) async {
              await m.create(schema.playbackSettings);
            },
            from3To4: (m, schema) async {
              await m.create(schema.tracks);
              await m.create(schema.queueEntries);
              await m.create(schema.queueEntriesTrackKey);
              await m.create(schema.playerState);
            },
            from4To5: (m, schema) async {
              await m.create(schema.playHistory);
              await m.create(schema.playHistoryPlayedAt);
              await m.create(schema.playHistoryTrackKey);
            },
            from5To6: (m, schema) async {
              await m.create(schema.layoutState);
            },
            from6To7: (m, schema) async {
              // 既有的列 `enabled` 是預設的真（ADR 0030 §決定 7）。
              await m.addColumn(
                schema.installedPlugins,
                schema.installedPlugins.enabled,
              );
              await m.addColumn(
                schema.installedPlugins,
                schema.installedPlugins.sourceIndexUrl,
              );
              await m.addColumn(
                schema.installedPlugins,
                schema.installedPlugins.checksJson,
              );
              await m.create(schema.pluginIndexes);
            },
            from7To8: (m, schema) async {
              await m.create(schema.accounts);
              await m.create(schema.sourceSettings);
            },
            from8To9: (m, schema) async {
              await m.create(schema.developerSettings);
            },
            from9To10: (m, schema) async {
              // 既有的列都是使用者裝的：`from_dev_folder` 取預設的假。
              await m.addColumn(
                schema.installedPlugins,
                schema.installedPlugins.fromDevFolder,
              );
            },
            from10To11: (m, schema) async {
              await m.create(schema.schedulerRuns);
            },
            from11To12: (m, schema) async {
              await m.create(schema.radioStations);
              // 既有的列這一欄是空的＝沒設定過，預設只在 Notifier 套用。
              await m.addColumn(
                schema.networkSettings,
                schema.networkSettings.radioStatusIntervalMinutes,
              );
            },
            from12To13: (m, schema) async {
              // 既有的列 `mode` 是空＝一般佇列，M2 的恢復行為不變。
              await m.addColumn(schema.playerState, schema.playerState.mode);
              await m.addColumn(
                schema.playerState,
                schema.playerState.mixPluginId,
              );
              await m.addColumn(schema.playerState, schema.playerState.mixId);
              await m.addColumn(
                schema.playerState,
                schema.playerState.mixTitle,
              );
              await m.addColumn(
                schema.playerState,
                schema.playerState.mixCursor,
              );
            },
            from13To14: (m, schema) async {
              // 既有的曲目都不是分 P：兩欄是空的。
              await m.addColumn(schema.tracks, schema.tracks.partIndex);
              await m.addColumn(schema.tracks, schema.tracks.parentTitle);
            },
            from14To15: (m, schema) async {
              await m.create(schema.playlists);
              await m.create(schema.playlistEntries);
              await m.create(schema.playlistEntriesPlaylist);
              await m.create(schema.playlistEntriesTrackKey);
            },
            from15To16: (m, schema) async {
              await m.create(schema.playlistRemote);
            },
            from16To17: (m, schema) async {
              // 既有的列這一欄是空的＝沒設定過，預設只在 Notifier 套用。
              await m.addColumn(
                schema.networkSettings,
                schema.networkSettings.chartRefreshIntervalMinutes,
              );
              await m.create(schema.chartSettings);
            },
            from17To18: (m, schema) async {
              // 既有的列這兩欄是空的＝沒設定過（依預設是目標、依插件清單排）。
              await m.addColumn(
                schema.sourceSettings,
                schema.sourceSettings.matchTarget,
              );
              await m.addColumn(
                schema.sourceSettings,
                schema.sourceSettings.matchRank,
              );
              await m.create(schema.matchResults);
              await m.create(schema.matchResultsSelected);
              await m.create(schema.trackOrigins);
            },
            from18To19: (m, schema) async {
              // 新表升級後是空的：沒有匯入過舊版資料。
              await m.create(schema.legacyImports);
              await m.create(schema.legacyPlaylistIds);
            },
            from19To20: (m, schema) async {
              // 既有的列這兩欄是空的＝沒設定過，預設只在 resolveAppearance 套用。
              await m.addColumn(
                schema.appearanceSettings,
                schema.appearanceSettings.seedColor,
              );
              await m.addColumn(
                schema.appearanceSettings,
                schema.appearanceSettings.fontFamily,
              );
            },
            from20To21: (m, schema) async {
              // 既有的列這一欄是空的＝沒記過，側欄依預設收合。
              await m.addColumn(
                schema.layoutState,
                schema.layoutState.railExpanded,
              );
            },
            from21To22: (m, schema) async {
              // 新表升級後是空的：舊版 App 沒有存過搜尋歷史。
              await m.create(schema.searchHistory);
              await m.create(schema.searchHistorySearchedAt);
            },
          ),
        );
        final violations = await customSelect('PRAGMA foreign_key_check').get();
        if (violations.isNotEmpty) {
          throw StateError(
            'Foreign key check failed after migrating from $from to $to: '
            '${violations.length} violation(s)',
          );
        }
        await customStatement('PRAGMA user_version = $to');
      });
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
