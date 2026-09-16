import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_history.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:isar_community/isar.dart';
import '../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('play history repository snapshot', () {
    setUpAll(() async {
      await initializeIsarForTests();
    });

    test(
      'loadHistorySnapshot applies filters and returns latest records first',
      () async {
        final harness = await _createHarness();
        addTearDown(harness.dispose);

        await harness.seed(
          _history(
            sourceId: 'yt-new',
            sourceType: SourceIds.youtube,
            title: 'Focus Track',
            artist: 'Alpha',
            playedAt: DateTime(2026, 4, 20, 18),
          ),
          _history(
            sourceId: 'yt-old',
            sourceType: SourceIds.youtube,
            title: 'Focus Track Archive',
            artist: 'Alpha',
            playedAt: DateTime(2026, 4, 19, 9),
          ),
          _history(
            sourceId: 'bili-hit',
            sourceType: SourceIds.bilibili,
            title: 'Other Song',
            artist: 'Beta',
            playedAt: DateTime(2026, 4, 20, 12),
          ),
        );

        final records = await harness.repository.loadHistorySnapshot(
          sourceTypes: {SourceIds.youtube},
          startDate: DateTime(2026, 4, 20),
          searchKeyword: 'focus',
        );

        expect(records.map((e) => e.sourceId).toList(), ['yt-new']);
      },
    );

    test(
      'queryHistory applies time order pagination without snapshot cap',
      () async {
        final harness = await _createHarness();
        addTearDown(harness.dispose);

        final records = List.generate(75, (index) {
          return _history(
            sourceId: 'song-$index',
            sourceType: SourceIds.youtube,
            title: 'Song $index',
            playedAt: DateTime(
              2026,
              4,
              20,
              12,
            ).subtract(Duration(minutes: index)),
          );
        });
        await harness.seedMany(records);

        final page = await harness.repository.queryHistory(
          offset: 20,
          limit: 10,
        );

        expect(
          page.map((e) => e.sourceId).toList(),
          List.generate(10, (index) => 'song-${index + 20}'),
        );
      },
    );

    test(
      'getRecentHistoryDistinct scans only enough recent rows for unique tracks',
      () async {
        final harness = await _createHarness();
        addTearDown(harness.dispose);

        await harness.seedMany([
          _history(
            sourceId: 'repeat',
            sourceType: SourceIds.youtube,
            title: 'Repeat Latest',
            playedAt: DateTime(2026, 4, 20, 12),
          ),
          _history(
            sourceId: 'repeat',
            sourceType: SourceIds.youtube,
            title: 'Repeat Older',
            playedAt: DateTime(2026, 4, 20, 11),
          ),
          _history(
            sourceId: 'unique',
            sourceType: SourceIds.youtube,
            title: 'Unique',
            playedAt: DateTime(2026, 4, 20, 10),
          ),
        ]);

        final recent = await harness.repository.getRecentHistoryDistinct(
          limit: 2,
        );

        expect(recent.map((e) => e.sourceId).toList(), ['repeat', 'unique']);
      },
    );

    test(
      'getHistoryStats includes records at today and week boundaries',
      () async {
        final harness = await _createHarness();
        addTearDown(harness.dispose);

        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
        final sameBoundary = todayStart.isAtSameMomentAs(weekStart);

        await harness.seedMany([
          _history(
            sourceId: 'today-start',
            sourceType: SourceIds.youtube,
            title: 'Today Start',
            playedAt: todayStart,
            durationMs: 1000,
          ),
          _history(
            sourceId: 'week-start',
            sourceType: SourceIds.youtube,
            title: 'Week Start',
            playedAt: weekStart,
            durationMs: 2000,
          ),
          _history(
            sourceId: 'before-week',
            sourceType: SourceIds.youtube,
            title: 'Before Week',
            playedAt: weekStart.subtract(const Duration(milliseconds: 1)),
            durationMs: 4000,
          ),
        ]);

        final stats = await harness.repository.getHistoryStats();

        expect(stats.totalCount, 3);
        expect(stats.todayCount, sameBoundary ? 2 : 1);
        expect(stats.weekCount, 2);
        expect(stats.totalDurationMs, 7000);
        expect(stats.todayDurationMs, sameBoundary ? 3000 : 1000);
        expect(stats.weekDurationMs, 3000);
      },
    );

    test('addHistory preserves records beyond the old snapshot cap', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      // 1000 是舊的快照上限。留著這條是為了釘住它已經不是寫入端的上限了 ——
      // `loadHistorySnapshot` 一次只讀 1000 筆，但資料庫裡可以有更多。
      const beyondOldSnapshotCap = 1001;
      for (var i = 0; i < beyondOldSnapshotCap; i++) {
        await harness.repository.addHistory(
          _track(i),
          keepAtMost: kDefaultPlayHistoryLimit,
        );
      }

      final stats = await harness.repository.getHistoryStats();

      expect(stats.totalCount, beyondOldSnapshotCap);
      expect(stats.totalDurationMs, beyondOldSnapshotCap * 1000);
    });

    test('addHistory deletes the oldest rows once past the cap', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      // 既有列的 playedAt 明寫。`PlayHistory.fromTrack` 只會蓋上
      // `DateTime.now()`，而連續幾次寫入的 now 有可能落在同一個刻度上 ——
      // 那樣「哪一筆最舊」就成了平手，斷言會時紅時綠。
      const cap = 5;
      await harness.seedMany([
        for (var i = 0; i < cap; i++)
          _history(
            sourceId: 'seeded-$i',
            sourceType: SourceIds.youtube,
            title: 'Seeded $i',
            playedAt: DateTime(2026, 4, 1 + i),
          ),
      ]);

      await harness.repository.addHistory(_track(0), keepAtMost: cap);

      final remaining = await harness.repository.getAllHistory(limit: 100);

      // 總數停在上限，而被擠掉的正好是最舊的那一筆。
      expect(remaining, hasLength(cap));
      expect(remaining.first.sourceId, 'song-0');
      expect(remaining.map((h) => h.sourceId), isNot(contains('seeded-0')));
      expect(remaining.map((h) => h.sourceId), contains('seeded-4'));
    });

    test('trimToLimit applies a lowered cap to existing rows', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedMany([
        for (var i = 0; i < 10; i++)
          _history(
            sourceId: 'seeded-$i',
            sourceType: SourceIds.youtube,
            title: 'Seeded $i',
            playedAt: DateTime(2026, 4, 1 + i),
          ),
      ]);

      final deleted = await harness.repository.trimToLimit(4);

      expect(deleted, 6);
      final remaining = await harness.repository.getAllHistory(limit: 100);
      expect(remaining.map((h) => h.sourceId).toList(), [
        'seeded-9',
        'seeded-8',
        'seeded-7',
        'seeded-6',
      ]);
    });

    test('a non-positive cap never empties the history', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.repository.addHistory(
        _track(0),
        keepAtMost: kDefaultPlayHistoryLimit,
      );

      // 壞掉的設定值（備份匯入、降級往返）不該把使用者的歷史清空。
      expect(await harness.repository.trimToLimit(0), 0);
      expect(await harness.repository.getHistoryCount(), 1);
    });
  });
}

Track _track(int index) => Track()
  ..sourceId = 'song-$index'
  ..sourceType = SourceIds.youtube
  ..title = 'Song $index'
  ..durationMs = 1000;

class _Harness {
  _Harness({
    required this.repository,
    required this.isar,
    required this.tempDir,
  });

  final PlayHistoryRepository repository;
  final Isar isar;
  final Directory tempDir;

  Future<void> seed(
    PlayHistory first, [
    PlayHistory? second,
    PlayHistory? third,
  ]) async {
    final records = [first, ?second, ?third];
    await seedMany(records);
  }

  Future<void> seedMany(List<PlayHistory> records) async {
    await isar.writeTxn(() async {
      await isar.playHistorys.putAll(records);
    });
  }

  Future<void> dispose() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<_Harness> _createHarness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'play_history_repository_snapshot_test_',
  );
  final isar = await Isar.open(
    [PlayHistorySchema],
    directory: tempDir.path,
    name: 'play_history_repository_snapshot_test',
  );

  return _Harness(
    repository: PlayHistoryRepository(isar),
    isar: isar,
    tempDir: tempDir,
  );
}

PlayHistory _history({
  required String sourceId,
  required String sourceType,
  required String title,
  String? artist,
  required DateTime playedAt,
  int? durationMs,
}) {
  return PlayHistory()
    ..sourceId = sourceId
    ..sourceType = sourceType
    ..title = title
    ..artist = artist
    ..playedAt = playedAt
    ..durationMs = durationMs;
}
