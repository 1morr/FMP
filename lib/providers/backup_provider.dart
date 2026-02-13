import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backup/backup_service.dart';
import 'database_provider.dart';

/// 备份服务 Provider
final backupServiceProvider = Provider<BackupService>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return BackupService(isar);
});
