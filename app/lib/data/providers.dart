import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/data/repositories/database_inspector.dart';
import 'package:fmp/data/repositories/developer_settings_repository.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/data/repositories/scheduler_runs_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';

/// App 唯一的資料庫。`main()` 在 `runApp` 之前開啟（`openAppDatabase`），
/// 再以 override 注入；其他地方不自己開庫（ADR 0010 §決定 3）。
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(
    'appDatabaseProvider is overridden by main() with the opened database',
  ),
);

final appearanceSettingsRepositoryProvider =
    Provider<AppearanceSettingsRepository>(
      (ref) => AppearanceSettingsRepository(ref.watch(appDatabaseProvider)),
    );

final networkSettingsRepositoryProvider = Provider<NetworkSettingsRepository>(
  (ref) => NetworkSettingsRepository(ref.watch(appDatabaseProvider)),
);

final pluginRepositoryProvider = Provider<PluginRepository>(
  (ref) => PluginRepository(ref.watch(appDatabaseProvider)),
);

final pluginIndexRepositoryProvider = Provider<PluginIndexRepository>(
  (ref) => PluginIndexRepository(ref.watch(appDatabaseProvider)),
);

final pluginStorageRepositoryProvider = Provider<PluginStorageRepository>(
  (ref) => PluginStorageRepository(ref.watch(appDatabaseProvider)),
);

final playbackSettingsRepositoryProvider = Provider<PlaybackSettingsRepository>(
  (ref) => PlaybackSettingsRepository(ref.watch(appDatabaseProvider)),
);

final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => QueueRepository(ref.watch(appDatabaseProvider)),
);

final tracksRepositoryProvider = Provider<TracksRepository>(
  (ref) => TracksRepository(ref.watch(appDatabaseProvider)),
);

final playHistoryRepositoryProvider = Provider<PlayHistoryRepository>(
  (ref) => PlayHistoryRepository(ref.watch(appDatabaseProvider)),
);

final layoutStateRepositoryProvider = Provider<LayoutStateRepository>(
  (ref) => LayoutStateRepository(ref.watch(appDatabaseProvider)),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(appDatabaseProvider)),
);

final sourceSettingsRepositoryProvider = Provider<SourceSettingsRepository>(
  (ref) => SourceSettingsRepository(ref.watch(appDatabaseProvider)),
);

final schedulerRunsRepositoryProvider = Provider<SchedulerRunsRepository>(
  (ref) => SchedulerRunsRepository(ref.watch(appDatabaseProvider)),
);

final developerSettingsRepositoryProvider =
    Provider<DeveloperSettingsRepository>(
      (ref) => DeveloperSettingsRepository(ref.watch(appDatabaseProvider)),
    );

final databaseInspectorProvider = Provider<DatabaseInspector>(
  (ref) => DatabaseInspector(
    ref.watch(appDatabaseProvider),
    ref.watch(redactorProvider),
  ),
);

final radioRepositoryProvider = Provider<RadioRepository>(
  (ref) => RadioRepository(ref.watch(appDatabaseProvider)),
);

final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => PlaylistRepository(ref.watch(appDatabaseProvider)),
);
