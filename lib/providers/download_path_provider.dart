import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/download/download_path_manager.dart';
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
