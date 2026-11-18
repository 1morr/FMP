import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/storage.dart';
import 'package:fmp/app/storage_notice.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/data/queue_store.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';

/// 啟動時開資料庫、讀回佇列（`main` 用 [openStorage]）。正常與讀不回來時
/// 另存一份的路在 `test/playback/queue_persistence_test.dart`。
void main() {
  late Directory dir;
  late Log log;
  final now = DateTime.utc(2026, 11, 18, 9, 30, 15);

  File databaseFile() => File('${dir.path}/fmp.sqlite');
  Track track(String id) => Track(
    ref: TrackRef(pluginId: 'p', trackId: id),
    title: id,
    author: 'A',
  );
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

  test('a database that cannot be opened for another reason (here a folder '
      'in its place) is left alone, saves nothing and gives the database '
      'notice', () async {
    Directory(databaseFile().path).createSync();

    final storage = await openStorage(databaseFile(), log, now: () => now);
    await log.close();

    expect(storage.database, isNull);
    expect(storage.notice, StorageNotice.databaseUnavailable);
    expect(logText(), contains('ERROR Opening the database failed'));
    expect(Directory(databaseFile().path).existsSync(), isTrue);
    expect(
      dir.listSync().map((e) => e.path),
      isNot(contains(contains('unreadable'))),
    );
  });

  test('a corrupt database file is moved aside, a new database opens and '
      'saves, and the notice says a copy was kept', () async {
    // SQLite 放棄非 SQLite 的檔時會自己刪掉它用不了的 -wal、-shm（實測），
    // 這裡只驗主檔。
    databaseFile().writeAsStringSync('not a database ' * 100);

    final storage = await openStorage(databaseFile(), log, now: () => now);
    final database = storage.database!;
    addTearDown(database.close);

    expect(storage.notice, StorageNotice.queueUnreadable);
    expect(storage.saved, isNull);
    const backup = 'fmp.sqlite.unreadable-20261118T093015Z';
    expect(
      File('${dir.path}/$backup').readAsStringSync(),
      startsWith('not a database'),
    );
    final store = QueueStore(database);
    await store.save(Queue.empty.add([track('a')]), Duration.zero);
    expect((await store.load())!.queue.current?.track, track('a'));
    await log.close();
    expect(logText(), contains('ERROR The database file is corrupt'));
  });

  test('a second copy in the same second gets a name of its own', () async {
    final first = File('${databaseFile().path}.unreadable-20261118T093015Z')
      ..writeAsStringSync('earlier copy');
    databaseFile().writeAsStringSync('not a database ' * 100);

    final storage = await openStorage(databaseFile(), log, now: () => now);
    addTearDown(storage.database!.close);
    await log.close();

    expect(storage.notice, StorageNotice.queueUnreadable);
    expect(first.readAsStringSync(), 'earlier copy');
    expect(
      File('${first.path}-2').readAsStringSync(),
      startsWith('not a database'),
    );
  });

  test('when the unreadable queue cannot be copied, nothing is saved this '
      'time and the unreadable data stays where it was', () async {
    final first = AppDatabase.open(databaseFile());
    await first.customStatement(
      'INSERT INTO queue_states VALUES (0, 9, 1, 0, \'off\', 0)',
    );
    await first.close();
    // 資料夾唯讀：讀得了，另存的檔建不起來（SQLITE_CANTOPEN，不是壞檔）。
    await Process.run('chmod', ['555', dir.path]);
    addTearDown(() => Process.run('chmod', ['755', dir.path]));

    final storage = await openStorage(databaseFile(), log, now: () => now);
    await log.close();

    expect(storage.database, isNull);
    expect(storage.notice, StorageNotice.databaseUnavailable);
    expect(logText(), contains('ERROR Keeping a copy of the unreadable queue'));
    await Process.run('chmod', ['755', dir.path]);
    final reopened = AppDatabase.open(databaseFile());
    addTearDown(reopened.close);
    expect(await reopened.select(reopened.queueStates).get(), hasLength(1));
  });
}
