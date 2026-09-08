import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/services/backup/backup_service.dart';
import 'package:fmp/data/database/database_provider.dart';

/// 备份服务 Provider
final backupServiceProvider = Provider<BackupService>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return BackupService(isar);
});
