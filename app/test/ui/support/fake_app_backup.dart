import 'package:fmp/app/backup.dart';
import 'package:fmp/data/database/backup_format.dart';

/// 設定頁「備份與還原」的假實作：記下被呼叫的順序；真的匯出與驗證另有
/// `database_backups_test.dart` 與 `backup_test.dart`。
class FakeAppBackup implements AppBackup {
  FakeAppBackup({
    this.exportResult,
    this.exportError,
    this.staged,
    this.stageError,
  });

  /// [export] 回的位置；`null` 是使用者取消。
  final Uri? exportResult;
  final Object? exportError;

  /// [pickAndStage] 回的暫存檔；`null` 是使用者取消。
  final StagedBackup? staged;
  final Object? stageError;
  final calls = <String>[];

  @override
  Future<Uri?> export() async {
    calls.add('export');
    if (exportError case final error?) throw error;
    return exportResult;
  }

  @override
  Future<StagedBackup?> pickAndStage() async {
    calls.add('pickAndStage');
    if (stageError case final error?) throw error;
    return staged;
  }
}
