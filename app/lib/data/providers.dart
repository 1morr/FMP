import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';

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

final pluginStorageRepositoryProvider = Provider<PluginStorageRepository>(
  (ref) => PluginStorageRepository(ref.watch(appDatabaseProvider)),
);
