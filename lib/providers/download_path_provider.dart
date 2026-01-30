import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/download/download_path_manager.dart';
import '../services/download/download_path_sync_service.dart';
import '../data/repositories/track_repository.dart';
import 'repository_providers.dart';
import 'database_provider.dart';

/// DownloadPathManager Provider
final downloadPathManagerProvider = Provider<DownloadPathManager>((ref) {
  return DownloadPathManager(ref.watch(settingsRepositoryProvider));
});

/// 下载路径状态 Provider
final downloadPathProvider = FutureProvider<String?>((ref) async {
  final manager = ref.watch(downloadPathManagerProvider);
  return manager.getCurrentDownloadPath();
});

/// 下载路径同步服务 Provider
final downloadPathSyncServiceProvider = Provider<DownloadPathSyncService>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  final trackRepo = TrackRepository(isar);
  final pathManager = ref.watch(downloadPathManagerProvider);
  return DownloadPathSyncService(trackRepo, pathManager);
});
