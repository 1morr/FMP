import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/storage.dart';
import 'package:fmp/app/storage_notice.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';

/// 啟動時開資料庫、讀回佇列（`main` 用 [openStorage]）。正常與讀不回來時
/// 另存一份的路在 `test/playback/queue_persistence_test.dart`。
void main() {
  late Directory dir;
  late Log log;
  final now = DateTime.utc(2026, 11, 18, 9, 30, 15);

  File databaseFile() => File('${dir.path}/fmp.sqlite');
  String logText() =>
      File('${dir.path}/logs/${Log.fileName}').readAsStringSync();

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fmp_storage_');
    log = await Log.open(
      Directory('${dir.path}/logs'),
      minimumLevel: LogLevel.debug,
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a new database file opens with nothing saved and no notice', () async {
    final storage = await openStorage(databaseFile(), log, now: () => now);
    addTearDown(storage.database!.close);
    await log.close();

    expect(storage.saved, isNull);
    expect(storage.notice, isNull);
  });

  test('a database that cannot be opened saves nothing and gives the '
      'database notice', () async {
    Directory(databaseFile().path).createSync();

    final storage = await openStorage(databaseFile(), log, now: () => now);
    await log.close();

    expect(storage.database, isNull);
    expect(storage.notice, StorageNotice.databaseUnavailable);
    expect(logText(), contains('ERROR Opening the database failed'));
  });

  test('when the unreadable queue cannot be copied, nothing is saved this '
      'time and the unreadable data stays where it was', () async {
    final first = AppDatabase.open(databaseFile());
    await first.customStatement(
      'INSERT INTO queue_states VALUES (0, 9, 1, 0, \'off\', 0)',
    );
    await first.close();
    // 另存的檔名已被佔住，VACUUM INTO 不覆寫。
    File('${databaseFile().path}.unreadable-20261118T093015Z')
        .writeAsStringSync('taken');

    final storage = await openStorage(databaseFile(), log, now: () => now);
    await log.close();

    expect(storage.database, isNull);
    expect(storage.notice, StorageNotice.databaseUnavailable);
    expect(logText(), contains('ERROR Keeping a copy of the unreadable queue'));
    final reopened = AppDatabase.open(databaseFile());
    addTearDown(reopened.close);
    expect(await reopened.select(reopened.queueStates).get(), hasLength(1));
  });
}
