import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/scheduler_runs_repository.dart';

import '../../support/memory_database.dart';

void main() {
  test('nothing is stored before a job succeeded', () async {
    final repository = SchedulerRunsRepository(memoryDatabase());

    expect(await repository.all(), isEmpty);
  });

  test('records a success and overwrites the previous one', () async {
    final repository = SchedulerRunsRepository(memoryDatabase());

    await repository.record('a', DateTime.utc(2026, 10, 14, 1));
    await repository.record('b', DateTime.utc(2026, 10, 14, 2));
    await repository.record('a', DateTime.utc(2026, 10, 14, 3));

    expect(await repository.all(), {
      'a': DateTime.utc(2026, 10, 14, 3),
      'b': DateTime.utc(2026, 10, 14, 2),
    });
  });

  // 持久化格式：UTC epoch 毫秒（`app/AGENTS.md` § 資料層）。
  test('stored format', () async {
    final database = memoryDatabase();
    final repository = SchedulerRunsRepository(database);

    // 本地時間也存成同一個 UTC 時刻；亞毫秒的部分不存。
    await repository.record(
      'radio-status:bilibili',
      DateTime.fromMicrosecondsSinceEpoch(1790000000123456),
    );

    final row = await database
        .customSelect('SELECT job_id, last_success_at FROM scheduler_runs')
        .getSingle();
    expect(row.data, {
      'job_id': 'radio-status:bilibili',
      'last_success_at': 1790000000123,
    });
    final read = (await repository.all())['radio-status:bilibili']!;
    expect(read.isUtc, isTrue);
    expect(read.millisecondsSinceEpoch, 1790000000123);
  });
}
