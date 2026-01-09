import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/settings_repository.dart';
import '../services/cache/cache_service.dart';
import 'database_provider.dart';

/// SettingsRepository Provider
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return SettingsRepository(isar);
});

/// CacheService Provider
final cacheServiceProvider = Provider<CacheService>((ref) {
  final settingsRepository = ref.watch(settingsRepositoryProvider);
  return CacheService(settingsRepository: settingsRepository);
});

/// 缓存统计信息 Provider
final cacheStatsProvider = FutureProvider<CacheStats>((ref) async {
  final cacheService = ref.watch(cacheServiceProvider);
  return cacheService.getCacheStats();
});

/// 刷新缓存统计
final cacheStatsRefreshProvider = StateProvider<int>((ref) => 0);

/// 可刷新的缓存统计 Provider
final refreshableCacheStatsProvider = FutureProvider<CacheStats>((ref) async {
  // 监听刷新触发器
  ref.watch(cacheStatsRefreshProvider);
  final cacheService = ref.watch(cacheServiceProvider);
  return cacheService.getCacheStats();
});
