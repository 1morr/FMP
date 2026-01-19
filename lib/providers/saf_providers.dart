import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/saf/saf_service.dart';
import '../../services/saf/file_exists_service.dart';

/// SAF 服务 Provider
final safServiceProvider = Provider<SafService>((ref) {
  return SafService();
});

/// 统一文件存在检测服务 Provider
final fileExistsServiceProvider = Provider<FileExistsService>((ref) {
  final safService = ref.watch(safServiceProvider);
  return FileExistsService(safService);
});
