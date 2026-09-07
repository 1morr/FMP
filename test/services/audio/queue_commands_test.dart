import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/services/audio/queue_commands.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:isar_community/isar.dart';

import '../../support/isar_test_harness.dart';

/// `QueueCommands` 是 Phase 4 步驟 E 從 `AudioController` 抽出來的第一個協作者。
///
/// 這裡測的是它獨自負責的三件事：Mix 模式閘門、佇列已滿的提示、以及把例外
/// 轉成 `QueueMutationStatus.failed` 而不是往上拋。狀態投影不在它身上，所以
/// 這份測試完全不碰 `PlayerState`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueueCommands', () {
    late Directory tempDir;
    late Isar isar;
    late QueueManager queueManager;
    late ToastService toastService;
    late List<ToastMessage> toasts;
    late QueueCommands commands;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('queue_commands_');
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'queue_commands_test',
      );
      queueManager = _buildQueueManager(isar);
      await queueManager.initialize();

      toastService = ToastService();
      toasts = [];
      toastService.messageStream.listen(toasts.add);

      commands = QueueCommands(
        queueManager: queueManager,
        toastService: toastService,
      );
    });

    tearDown(() async {
      toastService.dispose();
      if (isar.isOpen) await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('adding reaches the queue and reports applied', () async {
      final result = await commands.add(_track('a'), isMixMode: false);

      expect(result.status, QueueMutationStatus.applied);
      expect(queueManager.tracks, hasLength(1));
    });

    test('mix mode blocks the three add paths and says so once each', () async {
      final add = await commands.add(_track('a'), isMixMode: true);
      final addAll = await commands.addAll([_track('b')], isMixMode: true);
      final addNext = await commands.addNext(_track('c'), isMixMode: true);

      expect([
        add.status,
        addAll.status,
        addNext.status,
      ], everyElement(QueueMutationStatus.blocked));
      expect(queueManager.tracks, isEmpty);
      await pumpEventQueue();
      expect(toasts, hasLength(3));
      expect(toasts.map((t) => t.type), everyElement(ToastType.info));
    });

    test('mix mode blocks shuffle silently', () async {
      final result = await commands.shuffle(isMixMode: true);

      expect(result.status, QueueMutationStatus.blocked);
      await pumpEventQueue();
      // UI 已經禁用了按鈕，這只是額外保護 —— 再彈一次提示是噪音。
      expect(toasts, isEmpty);
    });

    test('remove, move and clear do not consult mix mode at all', () async {
      await commands.addAll([_track('a'), _track('b')], isMixMode: false);

      expect((await commands.move(0, 1)).status, QueueMutationStatus.applied);
      expect((await commands.removeAt(0)).status, QueueMutationStatus.applied);
      expect((await commands.clear()).status, QueueMutationStatus.applied);
      expect(queueManager.tracks, isEmpty);
    });

    test('a throwing queue becomes failed, not an exception', () async {
      final throwing = QueueCommands(
        queueManager: _ThrowingQueueManager(isar),
        toastService: toastService,
      );

      final result = await throwing.add(_track('a'), isMixMode: false);

      expect(result.status, QueueMutationStatus.failed);
      expect(result.error, isA<StateError>());
      expect(result.isApplied, isFalse);
    });
  });
}

QueueManager _buildQueueManager(Isar isar) {
  final queueRepository = QueueRepository(isar);
  final trackRepository = TrackRepository(isar);
  return QueueManager(
    queueRepository: queueRepository,
    trackRepository: trackRepository,
    queuePersistenceManager: QueuePersistenceManager(
      queueRepository: queueRepository,
      trackRepository: trackRepository,
      settingsRepository: SettingsRepository(isar),
    ),
  );
}

class _ThrowingQueueManager extends QueueManager {
  _ThrowingQueueManager(Isar isar)
    : super(
        queueRepository: QueueRepository(isar),
        trackRepository: TrackRepository(isar),
        queuePersistenceManager: QueuePersistenceManager(
          queueRepository: QueueRepository(isar),
          trackRepository: TrackRepository(isar),
          settingsRepository: SettingsRepository(isar),
        ),
      );

  @override
  Future<bool> add(Track track) async => throw StateError('boom');
}

Track _track(String id) => Track()
  ..sourceId = id
  ..sourceType = SourceIds.bilibili
  ..title = 'Track $id';
