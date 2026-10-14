import 'package:fmp/app/data_reset.dart';
import 'package:fmp/data/database/database_backups.dart';

/// 記下被呼叫的順序；真的清空與重啟另有 `data_reset_test.dart`。
final class FakeDataReset implements DataReset {
  FakeDataReset({this.backUpError, this.listed = const []});

  final Object? backUpError;
  final List<DatabaseBackup> listed;
  final calls = <String>[];

  static final made = DatabaseBackup(
    path: '/home/tester/data/backups/fmp-20261014T010203000Z.db',
    createdAt: DateTime.utc(2026, 10, 14, 1, 2, 3),
    sizeBytes: 2048,
  );

  @override
  Future<DatabaseBackup> backUp() async {
    calls.add('backUp');
    if (backUpError case final error?) throw error;
    return made;
  }

  @override
  Future<List<DatabaseBackup>> backups() async {
    calls.add('backups');
    return listed;
  }

  @override
  Future<void> resetAndRestart(DatabaseBackup backup) async =>
      calls.add('reset ${backup.path}');

  @override
  Future<void> restoreAndRestart(DatabaseBackup backup) async =>
      calls.add('restore ${backup.path}');
}
