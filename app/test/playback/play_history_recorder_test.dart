import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/play_history_recorder.dart';
import 'package:fmp/playback/playback_controller.dart';

import '../support/memory_database.dart';
import '../support/pump_until.dart';

TrackInfo track(String id) =>
    TrackInfo(sourceTypeId: 'fmp-test', sourceId: id, title: 'Song $id');

/// 記錄者在控制器之外的行為：寫入的順序、保留筆數，以及寫失敗不影響播放（design
/// §7.8）。控制器何時報一次播放在 `playback_controller_test.dart`。
void main() {
  late AppDatabase database;
  late PlayHistoryRepository repository;
  late StreamController<CountedPlay> plays;
  late Log log;
  var limit = 10000;

  setUp(() {
    database = memoryDatabase();
    repository = PlayHistoryRepository(database);
    plays = StreamController<CountedPlay>();
    addTearDown(plays.close);
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
    limit = 10000;
    PlayHistoryRecorder(
      repository: repository,
      limit: () async => limit,
      log: log,
    ).listen(plays.stream);
  });

  void play(String id, int minute) =>
      plays.add((track: track(id), at: DateTime.utc(2026, 10, 7, 12, minute)));

  Future<List<String>> history() async => [
    for (final entry in await repository.page(limit: 100)) entry.track.sourceId,
  ];

  /// 等歷史等於 [expected]（資料庫在 drift 的 isolate，要讓事件佇列跑）。
  Future<void> historyBecomes(List<String> expected) async {
    var ids = <String>[];
    for (var round = 0; round < 50; round++) {
      ids = await history();
      if (ids.join(',') == expected.join(',')) return;
      await settle();
    }
    expect(ids, expected);
  }

  test('writes each counted play, newest first', () async {
    play('a', 1);
    play('b', 2);

    await historyBecomes(['b', 'a']);
  });

  test('trims to the limit read at write time', () async {
    limit = 2;
    play('a', 1);
    play('b', 2);
    play('c', 3);

    await historyBecomes(['c', 'b']);
  });

  test('nothing is written or reported after dispose', () async {
    final limitRead = Completer<int>();
    final ownPlays = StreamController<CountedPlay>();
    addTearDown(ownPlays.close);
    final recorder = PlayHistoryRecorder(
      repository: repository,
      limit: () => limitRead.future,
      log: log,
    )..listen(ownPlays.stream);

    // 一筆已經在等保留筆數（組裝點等資料庫的設定）時記錄者被 dispose：組裝點的
    // ref 已經不能用，資料庫可能也要關了。
    ownPlays.add((track: track('a'), at: DateTime.utc(2026, 10, 7, 12)));
    await settle();
    recorder.dispose();
    limitRead.complete(10000);
    for (var round = 0; round < 10; round++) {
      await settle();
    }

    expect(await history(), isEmpty);
    expect(
      log.history.where((r) => r.message == 'Failed to record play history'),
      isEmpty,
    );
  });

  test('a failed write is reported, shows nothing and does not stop '
      'the next one', () async {
    await database.customStatement('DROP TABLE play_history');
    play('a', 1);
    for (var round = 0; round < 50; round++) {
      if (log.history.any(
        (r) => r.message == 'Failed to record play history',
      )) {
        break;
      }
      await settle();
    }

    final reported = [
      for (final record in log.history)
        if (record.message == 'Failed to record play history') record,
    ];
    expect(reported, hasLength(1));
    expect(reported.single.level, LogLevel.error);

    await database.customStatement(
      'CREATE TABLE play_history (id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'track_key TEXT NOT NULL REFERENCES tracks (track_key) ON DELETE RESTRICT, '
      'played_at INTEGER NOT NULL)',
    );
    play('b', 2);
    await historyBecomes(['b']);
  });
}
