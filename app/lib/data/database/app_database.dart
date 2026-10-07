import 'package:drift/drift.dart';

import 'package:fmp/data/database/app_database.steps.dart';
import 'package:fmp/data/database/converters.dart';
import 'package:fmp/data/database/tables.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/loop_mode.dart';
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
    PluginStorageTable,
    TracksTable,
    QueueEntriesTable,
    PlayerStateTable,
    PlayHistoryTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// 改了 `tables.dart` 就要加一，並存新快照（drift_schemas/）。
  @override
  int get schemaVersion => 5;

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
