import 'package:fmp/data/database/app_database.dart';

/// 排程器的上次成功時間（`scheduler_runs`，ADR 0017 §決定 2）。工作 id 到 UTC 時間；
/// 讀回來精度到毫秒。
final class SchedulerRunsRepository {
  SchedulerRunsRepository(this._db);

  final AppDatabase _db;

  /// 全部工作的上次成功時間。
  Future<Map<String, DateTime>> all() async {
    final rows = await _db.select(_db.schedulerRunsTable).get();
    return {for (final row in rows) row.jobId: row.lastSuccessAt};
  }

  /// 記下 [jobId] 在 [at] 成功（覆蓋舊值）。
  Future<void> record(String jobId, DateTime at) => _db
      .into(_db.schedulerRunsTable)
      .insertOnConflictUpdate(
        SchedulerRunsTableCompanion.insert(
          jobId: jobId,
          lastSuccessAt: at.toUtc(),
        ),
      );
}
