import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/download/download_path_maintenance_service.dart';
import '../services/download/download_path_manager.dart';
import '../services/download/download_path_sync_service.dart';
import 'download/download_providers.dart' show downloadRepositoryProvider;
import 'repository_providers.dart';

/// DownloadPathManager Provider
final downloadPathManagerProvider = Provider<DownloadPathManager>((ref) {
  return DownloadPathManager(ref.watch(settingsRepositoryProvider));
});

/// 下载路径状态 Provider
final downloadPathProvider = FutureProvider<String?>((ref) async {
  final manager = ref.watch(downloadPathManagerProvider);
  return manager.getCurrentDownloadPath();
});

/// 下载路径维护服务 Provider
final downloadPathMaintenanceServiceProvider =
    Provider<DownloadPathMaintenanceService>((ref) {
  final trackRepo = ref.watch(trackRepositoryProvider);
  final pathManager = ref.watch(downloadPathManagerProvider);
  final downloadRepository = ref.watch(downloadRepositoryProvider);
  return DownloadPathMaintenanceService(
    trackRepository: trackRepo,
    pathManager: pathManager,
    clearCompletedAndErrorTasks:
        downloadRepository.clearCompletedAndErrorTasks,
  );
});

/// 下载路径同步服务 Provider
final downloadPathSyncServiceProvider =
    Provider<DownloadPathSyncService>((ref) {
  final trackRepo = ref.watch(trackRepositoryProvider);
  final pathManager = ref.watch(downloadPathManagerProvider);
  return DownloadPathSyncService(trackRepo, pathManager);
});
