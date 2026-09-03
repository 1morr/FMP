import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_history.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:isar_community/isar.dart';

import '../../support/isar_test_harness.dart';

/// `PlayHistory.trackKey` 是被索引的 getter，這幾條查詢從「載入全表再用 Dart
/// 過濾」改成索引查詢。行為必須完全一樣。
void main() {
  late Isar isar;
  late Directory tempDir;
  late PlayHistoryRepository repository;

  setUpAll(initializeIsarForTests);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('play_history_key_test_');
    isar = await Isar.open([PlayHistorySchema],
        directory: tempDir.path, name: 'play_history_key_test');
    repository = PlayHistoryRepository(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  PlayHistory entry(String sourceId, {int? cid, String? type}) =>
      PlayHistory()
        ..sourceId = sourceId
        ..sourceType = type ?? SourceIds.bilibili
        ..cid = cid
        ..title = 'T'
        ..playedAt = DateTime(2026, 1, 1);

  Future<void> seed() async {
    await isar.writeTxn(() async {
      await isar.playHistorys.putAll([
        entry('BV1'),
        entry('BV1'),
        entry('BV1', cid: 7),
        entry('BV2'),
        entry('BV1', type: SourceIds.youtube),
      ]);
    });
  }

  test('getPlayCount counts only the exact key', () async {
    await seed();

    expect(await repository.getPlayCount('BV1', SourceIds.bilibili), 2);
    expect(await repository.getPlayCount('BV1', SourceIds.bilibili, cid: 7), 1);
    expect(await repository.getPlayCount('BV2', SourceIds.bilibili), 1);
    expect(await repository.getPlayCount('BV1', SourceIds.youtube), 1);
    expect(await repository.getPlayCount('nope', SourceIds.bilibili), 0);
  });

  test('getPlayCountByKey agrees with getPlayCount', () async {
    await seed();

    expect(await repository.getPlayCountByKey('bilibili:BV1'), 2);
    expect(await repository.getPlayCountByKey('bilibili:BV1:7'), 1);
    expect(await repository.getPlayCountByKey('youtube:BV1'), 1);
  });

  test('deleteAllForTrack removes exactly that key', () async {
    await seed();

    expect(await repository.deleteAllForTrack('bilibili:BV1'), 2);

    expect(await isar.playHistorys.count(), 3);
    expect(await repository.getPlayCountByKey('bilibili:BV1'), 0);
    expect(await repository.getPlayCountByKey('bilibili:BV1:7'), 1,
        reason: 'a different cid is a different track');
    expect(await repository.getPlayCountByKey('youtube:BV1'), 1,
        reason: 'a different source is a different track');
  });
}
