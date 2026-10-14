import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/database_backups.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:path/path.dart' as p;

// 資料庫檔的備份、還原與刪除（M3 PR 14b，ADR 0025 §決定 9、M3 design §12.2）。

void main() {
  // 備份檔以第二個 AppDatabase 開來數筆數，原資料庫是另一個檔案，不會互相干擾。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dataDirectory;
  late Log log;

  setUp(() {
    dataDirectory = Directory.systemTemp.createTempSync('fmp_backups_');
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.warning);
    // 刪得掉也證明資料庫關閉後檔案沒被佔住（Windows 上開著的檔案刪不掉）。
    addTearDown(() => dataDirectory.deleteSync(recursive: true));
  });

  File databaseFile() => File(p.join(dataDirectory.path, databaseFileName));

  Future<AppDatabase> open() => openAppDatabase(dataDirectory);

  Future<void> install(AppDatabase database, String id) =>
      PluginRepository(database).install(
        InstalledPlugin(
          id: id,
          version: '1.0.0',
          manifestJson: '{}',
          script: '',
          installedAt: DateTime.utc(2026),
        ),
      );

  Future<Map<String, int>> counts(AppDatabase database) async => {
    for (final table in database.allTables)
      table.actualTableName: await database
          .customSelect('SELECT COUNT(*) AS n FROM "${table.actualTableName}"')
          .getSingle()
          .then((row) => row.read<int>('n')),
  };

  /// 備份檔本身是一個能直接開的資料庫。
  Future<Map<String, int>> countsOfFile(String path) async {
    final database = AppDatabase(NativeDatabase(File(path)));
    try {
      return await counts(database);
    } finally {
      await database.close();
    }
  }

  DatabaseBackups backupsOf(AppDatabase database) =>
      DatabaseBackups(database, dataDirectory, log);

  group('create', () {
    test('writes a standalone database with the same rows', () async {
      final database = await open();
      addTearDown(database.close);
      await install(database, 'fmp-test');

      final backup = await backupsOf(database).create();

      expect(
        p.dirname(backup.path),
        p.join(dataDirectory.path, backupDirectoryName),
      );
      expect(await countsOfFile(backup.path), await counts(database));
      expect((await countsOfFile(backup.path))['installed_plugins'], 1);
      expect(backup.sizeBytes, File(backup.path).lengthSync());
    });

    test('names the file after the UTC time, without colons', () async {
      final database = await open();
      addTearDown(database.close);

      final backup = await withClock(
        Clock.fixed(DateTime.utc(2026, 10, 14, 9, 8, 7, 6)),
        () => backupsOf(database).create(),
      );

      expect(p.basename(backup.path), 'fmp-20261014T090807006Z.db');
      expect(p.basename(backup.path), isNot(contains(':')));
      expect(backup.createdAt, DateTime.utc(2026, 10, 14, 9, 8, 7, 6));
    });

    test('does not overwrite a backup made in the same millisecond', () async {
      final database = await open();
      addTearDown(database.close);
      final backups = backupsOf(database);
      final fixed = Clock.fixed(DateTime.utc(2026, 10, 14));
      await withClock(fixed, backups.create);

      await expectLater(
        withClock(fixed, backups.create),
        throwsA(isA<FileSystemException>()),
      );
      expect(await backups.list(), hasLength(1));
    });

    test('fails when the backups directory cannot be created', () async {
      final database = await open();
      addTearDown(database.close);
      // `backups` 是一個檔案：建不了目錄。
      File(p.join(dataDirectory.path, backupDirectoryName))
          .writeAsStringSync('not a directory');

      await expectLater(
        backupsOf(database).create(),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('list', () {
    test('is empty without a backups directory', () async {
      final database = await open();
      addTearDown(database.close);

      expect(await backupsOf(database).list(), isEmpty);
    });

    test('lists newest first and skips files that are not backups', () async {
      final database = await open();
      addTearDown(database.close);
      final backups = backupsOf(database);
      final older = await withClock(
        Clock.fixed(DateTime.utc(2026, 10, 13)),
        backups.create,
      );
      final newer = await withClock(
        Clock.fixed(DateTime.utc(2026, 10, 14)),
        backups.create,
      );
      for (final name in ['notes.txt', 'fmp-bad.db']) {
        File(p.join(dataDirectory.path, backupDirectoryName, name))
            .writeAsStringSync('x');
      }

      expect(await backups.list(), [newer, older]);
    });
  });

  group('restore', () {
    test(
      'replaces the database with the backup and keeps the old file',
      () async {
        final database = await open();
        await install(database, 'in-backup');
        final backups = backupsOf(database);
        final backup = await backups.create();
        await install(database, 'after-backup');
        expect((await counts(database))['installed_plugins'], 2);

        await withClock(
          Clock.fixed(DateTime.utc(2026, 10, 14, 1)),
          () => backups.restore(backup),
        );

        final restored = await open();
        addTearDown(restored.close);
        expect(
          (await PluginRepository(restored).list()).map((plugin) => plugin.id),
          ['in-backup'],
        );
        // 原來的資料庫留在旁邊，兩筆都在。
        final aside = File(
          '${databaseFile().path}.before-restore-20261014T010000000Z',
        );
        expect(aside.existsSync(), isTrue);
        expect((await countsOfFile(aside.path))['installed_plugins'], 2);
        // 備份本身沒動，暫存檔不留。
        expect(File(backup.path).existsSync(), isTrue);
        expect(File('${databaseFile().path}.restoring').existsSync(), isFalse);
      },
    );

    test('moves a stale journal aside instead of applying it', () async {
      final database = await open();
      final backups = backupsOf(database);
      final backup = await backups.create();
      // 資料庫關閉後不會留 -journal，這裡放一個假的，模擬當機後的殘留。
      File('${databaseFile().path}-journal').writeAsStringSync('stale');

      await backups.restore(backup);

      expect(File('${databaseFile().path}-journal').existsSync(), isFalse);
      final restored = await open();
      addTearDown(restored.close);
      expect(await restored.customSelect('SELECT 1').get(), hasLength(1));
    });

    test('puts the database back when the swap fails', () async {
      final database = await open();
      await install(database, 'original');
      final backups = backupsOf(database);
      final backup = await backups.create();
      await install(database, 'after-backup');
      const stamp = '20261014T010000000Z';
      // 殘留的 journal 改名的目標被一個資料夾佔住：主檔已經移開之後才失敗。
      File('${databaseFile().path}-journal').writeAsStringSync('stale');
      final blocker = Directory(
        '${databaseFile().path}-journal.before-restore-$stamp',
      )..createSync();
      File(p.join(blocker.path, 'keep')).writeAsStringSync('x');

      await expectLater(
        withClock(
          Clock.fixed(DateTime.utc(2026, 10, 14, 1)),
          () => backups.restore(backup),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(backups.isClosed, isTrue);
      expect(
        File('${databaseFile().path}.before-restore-$stamp').existsSync(),
        isFalse,
      );
      expect(File('${databaseFile().path}.restoring').existsSync(), isFalse);
      File('${databaseFile().path}-journal').deleteSync();
      final reopened = await open();
      addTearDown(reopened.close);
      expect(
        (await PluginRepository(reopened).list()).map((plugin) => plugin.id),
        unorderedEquals(['original', 'after-backup']),
      );
    });

    test('a missing backup throws and leaves the database open', () async {
      final database = await open();
      addTearDown(database.close);
      final backups = backupsOf(database);
      final backup = await backups.create();
      File(backup.path).deleteSync();

      await expectLater(
        backups.restore(backup),
        throwsA(isA<FileSystemException>()),
      );

      // 還能用：失敗發生在關閉之前。
      expect(backups.isClosed, isFalse);
      await install(database, 'still-works');
      expect(databaseFile().existsSync(), isTrue);
    });
  });

  group('erase', () {
    test('deletes the database files and keeps the backups', () async {
      final database = await open();
      await install(database, 'fmp-test');
      final backups = backupsOf(database);
      final backup = await backups.create();
      File('${databaseFile().path}-journal').writeAsStringSync('stale');

      await backups.erase();

      expect(databaseFile().existsSync(), isFalse);
      expect(File('${databaseFile().path}-journal').existsSync(), isFalse);
      expect(File(backup.path).existsSync(), isTrue);
      // 下次啟動重建一個空的。
      final fresh = await open();
      addTearDown(fresh.close);
      expect(await PluginRepository(fresh).list(), isEmpty);
    });
  });
}
