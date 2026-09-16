import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_history.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/services/audio/play_history_recorder.dart';
import 'package:isar_community/isar.dart';

import '../../support/isar_test_harness.dart';
import '../../support/pump_until.dart';

/// `PlayHistoryRecorder` 是三個播放副作用協作者之一。
///
/// 在此之前，「播放時會不會寫進播放歷史」在 `AudioController` 這一層**完全沒有
/// 測試**：repository 與 provider 各有自己的單元測試，中間那條轉接沒有人守。
/// 這裡補的就是那條轉接，以及它的兩個保證 —— 不阻塞播放、失敗不外逃。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayHistoryRecorder', () {
    late Directory tempDir;
    late Isar isar;
    late PlayHistoryRepository repository;
    late SettingsRepository settingsRepository;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('play_history_recorder_');
      isar = await Isar.open(
        [PlayHistorySchema, SettingsSchema],
        directory: tempDir.path,
        name: 'play_history_recorder_test',
      );
      repository = PlayHistoryRepository(isar);
      settingsRepository = SettingsRepository(isar);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('records a play into the repository', () async {
      final recorder = PlayHistoryRecorder(
        repository: repository,
        settingsRepository: settingsRepository,
      );

      recorder.record(_track('a', 'Song A'));
      await _settle(isar, 1);

      final stored = await isar.playHistorys.where().findAll();
      expect(stored, hasLength(1));
      expect(stored.single.title, 'Song A');
    });

    test('records every play so play counts can be derived', () async {
      final recorder = PlayHistoryRecorder(
        repository: repository,
        settingsRepository: settingsRepository,
      );
      final track = _track('a', 'Song A');

      recorder.record(track);
      recorder.record(track);
      await _settle(isar, 2);

      // 同一首播兩次要留兩筆 —— 播放次數統計是靠對 trackKey 數列數算出來的。
      expect(await isar.playHistorys.where().count(), 2);
    });

    test('does nothing when the database is not available', () async {
      // provider 在資料庫還沒初始化時就是傳 null 進來的。
      final recorder = PlayHistoryRecorder();

      recorder.record(_track('a', 'Song A'));
      await drainEventQueue(
        reason: 'without a database nothing should be written',
      );

      expect(await isar.playHistorys.where().count(), 0);
    });

    test('caps the history at the limit stored in settings', () async {
      await settingsRepository.update((s) => s.playHistoryLimit = 3);
      final recorder = PlayHistoryRecorder(
        repository: repository,
        settingsRepository: settingsRepository,
      );

      for (var i = 0; i < 5; i++) {
        recorder.record(_track('song-$i', 'Song $i'));
        // 一次一筆地等，而且等的是「這一筆到了」而不是總數 —— 過了上限之後
        // 總數不再成長，用總數當同步點會在第四筆就直接通過。
        await _settleFor(isar, 'song-$i');
      }

      final remaining = await isar.playHistorys
          .where()
          .sortByPlayedAtDesc()
          .findAll();
      expect(remaining, hasLength(3));
      expect(remaining.map((h) => h.sourceId), isNot(contains('song-0')));
      expect(remaining.map((h) => h.sourceId), contains('song-4'));
    });

    test('does nothing without a settings repository', () async {
      // 資料庫還沒開的時候兩個倉庫都是 null；只有一個也一樣算沒開。
      final recorder = PlayHistoryRecorder(repository: repository);

      recorder.record(_track('a', 'Song A'));
      await drainEventQueue(
        reason: 'without settings there is no limit to record against',
      );

      expect(await isar.playHistorys.where().count(), 0);
    });

    test('a failing repository never escapes onto the playback path', () async {
      final recorder = PlayHistoryRecorder(
        repository: _ThrowingRepository(isar),
        settingsRepository: settingsRepository,
      );

      // 沒有 await、沒有 try —— 就像 `_updatePlayingTrack` 呼叫它的樣子。
      recorder.record(_track('a', 'Song A'));

      // 例外若逃出 microtask，這一輪 pump 會讓測試失敗。
      await drainEventQueue(
        reason: 'a repository failure must not escape the microtask',
      );
      expect(await isar.playHistorys.where().count(), 0);
    });
  });
}

/// 等到寫入真的落地。
///
/// `record()` 是 fire-and-forget，而 Isar 的 `writeTxn` 是真的非同步 I/O 且彼此
/// 序列化，所以單次 `pumpEventQueue()` 只等得到第一筆 —— 這正是這個協作者不阻塞
/// 播放的證據，但也意味著測試不能用固定次數的 pump 當同步點。
Future<void> _settle(Isar isar, int expected) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (await isar.playHistorys.where().count() >= expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// 等到 [sourceId] 那一筆真的落地。
Future<void> _settleFor(Isar isar, String sourceId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final found = await isar.playHistorys
        .where()
        .filter()
        .sourceIdEqualTo(sourceId)
        .count();
    if (found > 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _ThrowingRepository extends PlayHistoryRepository {
  _ThrowingRepository(super.isar);

  @override
  Future<void> addHistory(Track track, {required int keepAtMost}) async {
    throw StateError('database is gone');
  }
}

Track _track(String sourceId, String title) => Track()
  ..sourceId = sourceId
  ..sourceType = SourceIds.youtube
  ..title = title;
