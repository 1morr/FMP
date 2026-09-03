import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:isar_community/isar.dart';

import '../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueueRepository', () {
    late Directory tempDir;
    late Isar isar;
    late QueueRepository queues;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('queue_repo_test_');
      isar = await Isar.open(
        [PlayQueueSchema],
        directory: tempDir.path,
        name: 'queue_repo_test',
      );
      queues = QueueRepository(isar);
    });

    tearDown(() async {
      if (isar.isOpen) await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('persists the queue while the database is open', () async {
      await queues.addTracks([1, 2, 3]);

      final saved = await queues.getOrCreate();
      expect(saved.trackIds, [1, 2, 3]);
    });

    test('writes are a no-op once the database is closed', () async {
      await queues.addTracks([1, 2, 3]);
      await isar.close();

      // 关闭之后仍然有在途的写入 —— 以前这里会抛
      // `IsarError: Isar instance has already been closed`。
      await expectLater(queues.addTracks([4, 5]), completes);
      await expectLater(queues.updatePosition(1234), completes);
      await expectLater(queues.clear(), completes);
    });

    test('getOrCreate hands back an empty queue once closed', () async {
      await queues.addTracks([1, 2, 3]);
      await isar.close();

      final queue = await queues.getOrCreate();
      expect(queue.trackIds, isEmpty);
      expect(queue.currentIndex, 0);
    });
  });
}
