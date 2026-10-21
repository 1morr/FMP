import 'package:fmp/app/data_reset.dart';
import 'package:fmp/data/database/backup_format.dart';
import 'package:fmp/data/database/database_backups.dart';

/// 記下被呼叫的順序；真的清空與重啟另有 `data_reset_test.dart`。
final class FakeDataReset implements DataReset {
  FakeDataReset({
    this.backUpError,
    this.listed = const [],
    this.stageError,
    this.restoreError,
  });

  final Object? backUpError;
  final List<DatabaseBackup> listed;

  /// 非空時 [stageBackup] 拋這個（例如 [BackupRejected]）。
  final Object? stageError;

  /// 非空時 [restoreAndRestart] 拋這個（模擬自動備份失敗）。
  final Object? restoreError;
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

  /// [stageBackup] 回的暫存檔：有兩個插件，其中一個有兩個網域。
  static const staged = StagedBackup(
    path: '/home/tester/data/backups/staged-20261014T010203000Z.db',
    plugins: [
      BackupPlugin(
        id: 'fmp-test',
        name: 'Test Source',
        version: '1.2.3',
        hosts: ['example.test', 'cdn.example.test'],
      ),
      BackupPlugin(
        id: 'other',
        name: 'Other Source',
        version: '0.1.0',
        hosts: ['other.example.test'],
      ),
    ],
    unusablePluginIds: ['broken-plugin'],
    indexUrls: ['https://index.example.test/'],
  );

  @override
  Future<StagedBackup> stageBackup(DatabaseBackup backup) async {
    calls.add('stage ${backup.path}');
    if (stageError case final error?) throw error;
    return staged;
  }

  @override
  Future<void> discardStaged(StagedBackup staged) async => calls.add('discard');

  @override
  Future<void> restoreAndRestart(StagedBackup staged) async {
    calls.add('restore');
    if (restoreError case final error?) throw error;
  }
}
