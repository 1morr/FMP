import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/backup_format.dart';
import 'package:fmp/data/database/database_backups.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../drift/app_database/generated/schema.dart';
import '../../support/backup_readers.dart';

// 資料庫檔的備份、匯出、還原與刪除（M3 PR 14b，ADR 0025 §決定 9；M4 PR 22，ADR 0034）。
// 全部以真的檔案資料庫。表的歸類閘門在 `backup_format_test.dart`。

/// [haystack] 的位元組裡有沒有 [needle]（UTF-8）。
bool containsBytes(Uint8List haystack, String needle) {
  final bytes = utf8.encode(needle);
  for (var i = 0; i + bytes.length <= haystack.length; i++) {
    var matched = true;
    for (var j = 0; j < bytes.length && matched; j++) {
      matched = haystack[i + j] == bytes[j];
    }
    if (matched) return true;
  }
  return false;
}

/// [source] 匯出的備份檔位元組；[change] 可以在匯出的檔上動手腳。
Future<Uint8List> exportBytesOf(
  AppDatabase source,
  Directory directory, {
  void Function(sqlite.Database raw)? change,
}) async {
  final target = File(p.join(directory.path, 'export-source.db'));
  await DatabaseBackups(
    source,
    directory,
    Log(redactor: Redactor(), minimumLevel: LogLevel.warning),
    readPlugin: lenientBackupReader,
  ).export(target);
  if (change != null) {
    final raw = sqlite.sqlite3.open(target.path);
    try {
      change(raw);
    } finally {
      raw.close();
    }
  }
  final bytes = target.readAsBytesSync();
  target.deleteSync();
  return bytes;
}

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

  DatabaseBackups backupsOf(AppDatabase database) => DatabaseBackups(
    database,
    dataDirectory,
    log,
    readPlugin: lenientBackupReader,
  );

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

  group('restoreStaged', () {
    test(
      'replaces the database with the backup and keeps the old file',
      () async {
        final database = await open();
        await install(database, 'in-backup');
        final backups = backupsOf(database);
        final backup = await backups.create();
        await install(database, 'after-backup');
        expect((await counts(database))['installed_plugins'], 2);
        final staged = await backups.stageFile(File(backup.path));

        await withClock(
          Clock.fixed(DateTime.utc(2026, 10, 14, 1)),
          () => backups.restoreStaged(staged),
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
        expect(File(staged.path).existsSync(), isFalse);
        expect(File('${databaseFile().path}.restoring').existsSync(), isFalse);
      },
    );

    test('moves a stale journal aside instead of applying it', () async {
      final database = await open();
      final backups = backupsOf(database);
      final staged = await backups.stageFile(
        File((await backups.create()).path),
      );
      // 資料庫關閉後不會留 -journal，這裡放一個假的，模擬當機後的殘留。
      File('${databaseFile().path}-journal').writeAsStringSync('stale');

      await backups.restoreStaged(staged);

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
      final staged = await backups.stageFile(File(backup.path));
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
          () => backups.restoreStaged(staged),
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

    test('a missing staged file throws and leaves the database open', () async {
      final database = await open();
      addTearDown(database.close);
      final backups = backupsOf(database);
      final staged = await backups.stageFile(
        File((await backups.create()).path),
      );
      File(staged.path).deleteSync();

      await expectLater(
        backups.restoreStaged(staged),
        throwsA(isA<FileSystemException>()),
      );

      // 還能用：失敗發生在關閉之前。
      expect(backups.isClosed, isFalse);
      await install(database, 'still-works');
      expect(databaseFile().existsSync(), isTrue);
    });
  });

  group('export', () {
    const fakeCookie = 'fake-cookie-***-marker';

    /// 這台的資料：每一類「不帶走」的都有一筆，外加會帶走的插件與自訂 index。
    Future<void> seedDevice(AppDatabase database) async {
      await install(database, 'fmp-test');
      await database.customStatement(
        "INSERT INTO installed_plugins (id, version, manifest_json, script, "
        "installed_at, from_dev_folder) VALUES ('dev-marker', '0', '{}', '', "
        '0, 1)',
      );
      await database.customStatement(
        "INSERT INTO plugin_storage (plugin_id, key, value) "
        "VALUES ('fmp-test', 'anonymous', '$fakeCookie')",
      );
      await database.customStatement(
        "INSERT INTO accounts (plugin_id, user_id, display_name, status, "
        "logged_in_at) VALUES ('fmp-test', 'u', 'Someone', 'active', 1)",
      );
      await database.customStatement(
        'INSERT INTO layout_state (id, panel_expanded) VALUES (1, 1)',
      );
      await database.customStatement(
        "INSERT INTO scheduler_runs (job_id, last_success_at) "
        "VALUES ('job', 1)",
      );
      await database.customStatement(
        "INSERT INTO playback_settings (id, output_device_id, "
        "output_device_name, play_history_limit) "
        "VALUES (1, 'dev-id', 'Speakers', 77)",
      );
      await database.customStatement(
        "INSERT INTO developer_settings (id, plugin_dev_folder, "
        "developer_mode) VALUES (1, 'folder-a', 1)",
      );
      await database.customStatement(
        "INSERT INTO plugin_indexes (url, added_at) "
        "VALUES ('https://index.example.test/', 1)",
      );
    }

    test(
      'sets the keyed device columns to NULL and keeps the other columns',
      () async {
        final database = await open();
        addTearDown(database.close);
        await database.customStatement(
          "INSERT INTO source_settings (plugin_id, browse_as_logged_in, "
          "match_target, match_rank) VALUES ('p1', 1, 0, 3), "
          "('p2', 0, NULL, 1)",
        );
        final target = File(p.join(dataDirectory.path, 'keyed.db'));

        await backupsOf(database).export(target);

        final file = AppDatabase(NativeDatabase(target));
        addTearDown(file.close);
        final rows = await file
            .customSelect(
              'SELECT plugin_id, browse_as_logged_in AS b, match_target AS t, '
              'match_rank AS r FROM source_settings ORDER BY plugin_id',
            )
            .get();
        expect(rows.map((row) => row.readNullable<int>('b')), [null, null]);
        expect(rows.map((row) => row.readNullable<int>('t')), [0, null]);
        expect(rows.map((row) => row.readNullable<int>('r')), [3, 1]);
      },
    );

    test('removes the device data and keeps the rest', () async {
      final database = await open();
      addTearDown(database.close);
      await seedDevice(database);
      final before = await counts(database);
      final target = File(p.join(dataDirectory.path, 'out.db'));

      await backupsOf(database).export(target);

      final exported = await countsOfFile(target.path);
      for (final table in backupExcludedTables) {
        expect(exported[table], 0, reason: table);
      }
      for (final table in backupCarriedTables) {
        // 標記列是唯一少掉的。
        final expected = table == 'installed_plugins'
            ? before[table]! - 1
            : before[table];
        expect(exported[table], expected, reason: table);
      }
      final file = AppDatabase(NativeDatabase(target));
      addTearDown(file.close);
      final rows = await file
          .customSelect(
            "SELECT (SELECT COUNT(*) FROM installed_plugins WHERE id = "
            "'dev-marker') AS marker, output_device_id AS d, "
            "output_device_name AS n, play_history_limit AS keep, "
            "(SELECT plugin_dev_folder FROM developer_settings) AS folder, "
            "(SELECT developer_mode FROM developer_settings) AS mode "
            "FROM playback_settings",
          )
          .getSingle();
      expect(rows.read<int>('marker'), 0);
      expect(rows.readNullable<String>('d'), isNull);
      expect(rows.readNullable<String>('n'), isNull);
      expect(rows.read<int>('keep'), 77);
      expect(rows.readNullable<String>('folder'), isNull);
      // 同一列的其他欄位照帶。
      expect(rows.read<int>('mode'), 1);
      expect(target.existsSync(), isTrue);
      expect(File('${target.path}.partial').existsSync(), isFalse);
    });

    test('the file holds no trace of a cookie value', () async {
      final database = await open();
      addTearDown(database.close);
      await seedDevice(database);
      final backups = backupsOf(database);
      final target = File(p.join(dataDirectory.path, 'out.db'));

      // 對照：整份副本裡看得到，所以下面找不到才有意義。
      final full = await backups.create();
      expect(
        containsBytes(File(full.path).readAsBytesSync(), fakeCookie),
        isTrue,
      );
      await backups.export(target);

      expect(containsBytes(target.readAsBytesSync(), fakeCookie), isFalse);
    });

    test('is a database at the current schema version', () async {
      final database = await open();
      addTearDown(database.close);
      final target = File(p.join(dataDirectory.path, 'out.db'));

      await backupsOf(database).export(target);

      final raw = sqlite.sqlite3.open(target.path);
      addTearDown(raw.close);
      expect(
        raw.select('PRAGMA user_version').single.values.first,
        database.schemaVersion,
      );
    });

    test('removes leftovers of an earlier export, sidecars included', () async {
      final database = await open();
      addTearDown(database.close);
      final target = File(p.join(dataDirectory.path, 'out.db'));
      final leftovers = [
        for (final base in ['${target.path}.partial', target.path])
          for (final extra in ['-journal', '-wal', '-shm']) '$base$extra',
        '${target.path}.partial',
      ];
      for (final path in leftovers) {
        File(path).writeAsStringSync('stale');
      }
      final backups = backupsOf(database);

      await backups.export(target);

      for (final path in leftovers) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
      expect(target.existsSync(), isTrue);

      // 交給使用者之後整個刪掉。
      File('${target.path}-wal').writeAsStringSync('stale');
      await backups.deleteExport(target);
      expect(target.existsSync(), isFalse);
      expect(File('${target.path}-wal').existsSync(), isFalse);
    });

    test('a failed export removes the partial file and its sidecars', () async {
      final database = await open();
      addTearDown(database.close);
      final target = File(p.join(dataDirectory.path, 'missing', 'out.db'));

      await expectLater(backupsOf(database).export(target), throwsA(anything));

      expect(File('${target.path}.partial-journal').existsSync(), isFalse);
    });

    test('a failed export leaves no file and the database usable', () async {
      final database = await open();
      addTearDown(database.close);
      await seedDevice(database);
      final target = File(p.join(dataDirectory.path, 'missing', 'out.db'));

      await expectLater(backupsOf(database).export(target), throwsA(anything));

      expect(target.existsSync(), isFalse);
      expect(File('${target.path}.partial').existsSync(), isFalse);
      expect((await counts(database))['plugin_storage'], 1);
    });
  });

  group('stage', () {
    Future<Uint8List> exportedBytes(
      AppDatabase source, {
      void Function(sqlite.Database raw)? change,
    }) => exportBytesOf(source, dataDirectory, change: change);

    Future<void> expectRejected(
      Future<Object?> staging,
      BackupRejection reason,
      AppDatabase database,
      Map<String, int> before,
    ) async {
      await expectLater(
        staging,
        throwsA(
          isA<BackupRejected>().having((e) => e.reason, 'reason', reason),
        ),
      );
      // 暫存檔不留，目前的資料庫完全沒動。
      final leftovers = Directory(
        p.join(dataDirectory.path, backupDirectoryName),
      ).listSync().where((e) => p.basename(e.path).startsWith('staged-'));
      expect(leftovers, isEmpty);
      expect(await counts(database), before);
    }

    late AppDatabase database;
    late Map<String, int> before;

    setUp(() async {
      database = await open();
      addTearDown(database.close);
      await install(database, 'current');
      before = await counts(database);
    });

    test('accepts an exported file and lists its plugins and hosts', () async {
      final other = Directory.systemTemp.createTempSync('fmp_backups_other_');
      addTearDown(() => other.deleteSync(recursive: true));
      final source = await openAppDatabase(other);
      addTearDown(source.close);
      await PluginRepository(source).install(
        InstalledPlugin(
          id: 'fmp-test',
          version: '1.2.3',
          manifestJson: jsonEncode({
            'id': 'fmp-test',
            'name': 'Test Source',
            'allowedHosts': ['example.test', 'cdn.example.test'],
          }),
          script: '',
          installedAt: DateTime.utc(2026),
        ),
      );
      await install(source, 'unreadable');
      final bytes = await exportedBytes(source);
      await source.customStatement(
        "UPDATE installed_plugins SET manifest_json = 'not json' "
        "WHERE id = 'unreadable'",
      );

      final staged = await backupsOf(database).stageBytes(bytes);

      expect(staged.plugins, [
        const BackupPlugin(
          id: 'fmp-test',
          name: 'Test Source',
          version: '1.2.3',
          hosts: ['example.test', 'cdn.example.test'],
        ),
        const BackupPlugin(
          id: 'unreadable',
          name: 'unreadable',
          version: '1.0.0',
          hosts: [],
        ),
      ]);
      expect(File(staged.path).existsSync(), isTrue);
      expect(
        p.dirname(staged.path),
        p.join(dataDirectory.path, backupDirectoryName),
      );
      expect(await counts(database), before);
    });

    test('accepts a full backup file from the backups directory', () async {
      final backups = backupsOf(database);
      final backup = await backups.create();

      final staged = await backups.stageFile(File(backup.path));

      expect(staged.plugins.map((plugin) => plugin.id), ['current']);
      expect(File(backup.path).existsSync(), isTrue);
    });

    test('rejects a newer version', () async {
      final bytes = await exportedBytes(
        database,
        change: (raw) =>
            raw.execute('PRAGMA user_version = ${database.schemaVersion + 1}'),
      );

      await expectRejected(
        backupsOf(database).stageBytes(bytes),
        BackupRejection.newerVersion,
        database,
        before,
      );
    });

    test('rejects user_version 0 as not an FMP backup', () async {
      final bytes = await exportedBytes(
        database,
        change: (raw) => raw.execute('PRAGMA user_version = 0'),
      );

      await expectRejected(
        backupsOf(database).stageBytes(bytes),
        BackupRejection.notFmpBackup,
        database,
        before,
      );
    });

    test('rejects a file that is not SQLite', () async {
      await expectRejected(
        backupsOf(database).stageBytes(
          Uint8List.fromList(utf8.encode('{"version": 5, "playlists": []}')),
        ),
        BackupRejection.notFmpBackup,
        database,
        before,
      );
      await expectRejected(
        backupsOf(database).stageBytes(Uint8List(0)),
        BackupRejection.notFmpBackup,
        database,
        before,
      );
    });

    test('rejects a foreign SQLite file', () async {
      final foreign = File(p.join(dataDirectory.path, 'foreign.db'));
      sqlite.sqlite3.open(foreign.path)
        ..execute('CREATE TABLE notes (id INTEGER)')
        ..execute('PRAGMA user_version = 3')
        ..close();

      await expectRejected(
        backupsOf(database).stageBytes(foreign.readAsBytesSync()),
        BackupRejection.notFmpBackup,
        database,
        before,
      );
    });

    test('rejects a file with a good header and damaged content', () async {
      final bytes = await exportedBytes(database);
      // 標頭（前 100 個位元組）完整，第一頁其餘的內容換成雜訊。
      for (var i = 100; i < 4096 && i < bytes.length; i++) {
        bytes[i] = 0xFF;
      }

      await expectRejected(
        backupsOf(database).stageBytes(bytes),
        BackupRejection.corrupt,
        database,
        before,
      );
    });

    test('rejects a truncated file', () async {
      final bytes = await exportedBytes(database);

      await expectRejected(
        backupsOf(database)
            .stageBytes(Uint8List.sublistView(bytes, 0, bytes.length ~/ 2)),
        BackupRejection.corrupt,
        database,
        before,
      );
    });

    test('rejects a trigger, even one that cannot fire yet', () async {
      final bytes = await exportedBytes(
        database,
        change: (raw) => raw.execute(
          'CREATE TRIGGER sneaky AFTER INSERT ON accounts BEGIN '
          'DELETE FROM tracks; END',
        ),
      );

      await expectRejected(
        backupsOf(database).stageBytes(bytes),
        BackupRejection.notFmpBackup,
        database,
        before,
      );
    });

    test('rejects a view', () async {
      final bytes = await exportedBytes(
        database,
        change: (raw) => raw.execute('CREATE VIEW sneaky AS SELECT 1'),
      );

      await expectRejected(
        backupsOf(database).stageBytes(bytes),
        BackupRejection.notFmpBackup,
        database,
        before,
      );
    });

    test('rejects an unknown table or a missing one', () async {
      final extra = await exportedBytes(
        database,
        change: (raw) => raw.execute('CREATE TABLE sneaky (id INTEGER)'),
      );
      final missing = await exportedBytes(
        database,
        change: (raw) => raw.execute('DROP TABLE plugin_indexes'),
      );

      for (final bytes in [extra, missing]) {
        await expectRejected(
          backupsOf(database).stageBytes(bytes),
          BackupRejection.notFmpBackup,
          database,
          before,
        );
      }
    });

    test('does not change the original bytes of a source file', () async {
      final backups = backupsOf(database);
      final backup = await backups.create();
      final original = File(backup.path).readAsBytesSync();

      await backups.stageFile(File(backup.path));

      expect(File(backup.path).readAsBytesSync(), original);
    });

    test('clears staged files left by an earlier run', () async {
      final backups = backupsOf(database);
      final stale = File(
        p.join(dataDirectory.path, backupDirectoryName, 'staged-old.db'),
      )..createSync(recursive: true);

      await backups.stageBytes(await exportedBytes(database));

      expect(stale.existsSync(), isFalse);
    });

    test('a negative user_version is not an FMP backup', () async {
      final bytes = await exportedBytes(
        database,
        change: (raw) => raw.execute('PRAGMA user_version = -1'),
      );

      await expectRejected(
        backupsOf(database).stageBytes(bytes),
        BackupRejection.notFmpBackup,
        database,
        before,
      );
    });

    test('does not list the rows the plugin development tool added', () async {
      await database.customStatement(
        "INSERT INTO installed_plugins (id, version, manifest_json, script, "
        "installed_at, from_dev_folder) VALUES ('dev-marker', '0', '{}', '', "
        '0, 1)',
      );
      final backups = backupsOf(database);
      final backup = await backups.create();

      final staged = await backups.stageFile(File(backup.path));

      expect(staged.plugins.map((plugin) => plugin.id), ['current']);
    });

    test('lists the custom plugin indexes the backup adds', () async {
      await database.customStatement(
        "INSERT INTO plugin_indexes (url, added_at) VALUES "
        "('https://b.example.test/', 2), ('https://a.example.test/', 1)",
      );

      final staged = await backupsOf(database)
          .stageBytes(await exportedBytes(database));

      expect(staged.indexUrls, [
        'https://a.example.test/',
        'https://b.example.test/',
      ]);
    });

    test('a plugin the reader refuses rejects the whole file', () async {
      final strict = DatabaseBackups(
        database,
        dataDirectory,
        log,
        readPlugin: ({
          required id,
          required version,
          required manifestJson,
          required script,
        }) => throw const BackupRejected(BackupRejection.notFmpBackup),
      );

      await expectRejected(
        strict.stageBytes(await exportedBytes(database)),
        BackupRejection.notFmpBackup,
        database,
        before,
      );
    });

    group('the schema is rebuilt by the app', () {
      /// [staged] 與全新資料庫的 `sqlite_master.sql`（不含 sqlite_ 自己的）是否逐項相同。
      Future<void> expectFreshSchema(StagedBackup staged) async {
        Future<Map<String, String?>> sql(AppDatabase db) async => {
          for (final row
              in await db
                  .customSelect(
                    "SELECT name, sql FROM sqlite_master "
                    "WHERE name NOT LIKE 'sqlite_%'",
                  )
                  .get())
            row.read<String>('name'): row.readNullable<String>('sql'),
        };
        final fresh = AppDatabase(NativeDatabase.memory());
        addTearDown(fresh.close);
        final result = AppDatabase(NativeDatabase(File(staged.path)));
        addTearDown(result.close);
        expect(await sql(result), await sql(fresh));
      }

      test('a table with an extra column and weaker constraints comes out '
          'as the app defines it', () async {
        final source = await exportedBytes(
          database,
          change: (raw) {
            raw.execute('DROP TABLE plugin_indexes');
            raw.execute(
              'CREATE TABLE plugin_indexes (url TEXT PRIMARY KEY, added_at, extra TEXT)',
            );
            raw.execute(
              "INSERT INTO plugin_indexes VALUES "
              "('https://a.example.test/', 1, 'x')",
            );
            raw.execute('ALTER TABLE tracks ADD COLUMN sneaky TEXT');
          },
        );

        final staged = await backupsOf(database).stageBytes(source);

        await expectFreshSchema(staged);
        expect(staged.indexUrls, ['https://a.example.test/']);
        expect((await countsOfFile(staged.path))['plugin_indexes'], 1);
      });

      test('rows that break a constraint of the app schema are refused', () async {
        final bytes = await exportedBytes(
          database,
          change: (raw) {
            raw.execute('DROP TABLE developer_settings');
            raw.execute(
              'CREATE TABLE developer_settings (id INTEGER PRIMARY KEY, '
              'developer_mode INTEGER, log_level TEXT, plugin_dev_folder TEXT, '
              'report_reminder_dismissed INTEGER)',
            );
            raw.execute('INSERT INTO developer_settings (id) VALUES (7)');
          },
        );

        await expectRejected(
          backupsOf(database).stageBytes(bytes),
          BackupRejection.corrupt,
          database,
          before,
        );
      });

      test('a table missing a column is refused', () async {
        final bytes = await exportedBytes(
          database,
          change: (raw) =>
              raw.execute('ALTER TABLE plugin_indexes DROP COLUMN added_at'),
        );

        await expectRejected(
          backupsOf(database).stageBytes(bytes),
          BackupRejection.corrupt,
          database,
          before,
        );
      });

      test('rows that break a foreign key are refused', () async {
        final bytes = await exportedBytes(
          database,
          change: (raw) => raw.execute(
            "INSERT INTO plugin_storage (plugin_id, key, value) "
            "VALUES ('no-such-plugin', 'k', 'v')",
          ),
        );

        await expectRejected(
          backupsOf(database).stageBytes(bytes),
          BackupRejection.corrupt,
          database,
          before,
        );
      });

      test('an ordinary export keeps all its rows', () async {
        final staged = await backupsOf(database)
            .stageBytes(await exportedBytes(database));

        await expectFreshSchema(staged);
        final counted = await countsOfFile(staged.path);
        expect(counted['installed_plugins'], 1);
        expect(File('${staged.path}.rebuilt').existsSync(), isFalse);
      });
    });

    // 舊版的備份靠既有的 migration 還原（ADR 0034 §決定 3）；每個歷史版本都試，
    // 同時證明 migration 之後的 sqlite_master 與全新的資料庫一致。
    for (final version in GeneratedHelper.versions) {
      test('migrates a version $version file', () async {
        final schema = await SchemaVerifier(GeneratedHelper())
            .schemaAt(version);
        schema.rawDatabase.execute(
          "INSERT INTO installed_plugins (id, version, manifest_json, script, "
          "installed_at) VALUES ('old', '0.1.0', "
          '\'{"name":"Old","allowedHosts":["old.example.test"]}\', \'\', 0)',
        );
        final source = File(p.join(dataDirectory.path, 'v$version.db'));
        schema.rawDatabase.execute('VACUUM INTO ?', [source.path]);

        final staged = await backupsOf(database).stageFile(source);

        expect(staged.plugins, const [
          BackupPlugin(
            id: 'old',
            name: 'Old',
            version: '0.1.0',
            hosts: ['old.example.test'],
          ),
        ]);
        // 暫存檔已經在目前的版本。
        final counted = await countsOfFile(staged.path);
        expect(counted.keys, containsAll(backupCarriedTables));
        expect(await counts(database), before);
      });
    }
  });

  group('carryOver', () {
    late Directory otherDirectory;
    late AppDatabase mine;
    late AppDatabase other;

    setUp(() async {
      otherDirectory = Directory.systemTemp.createTempSync('fmp_other_');
      addTearDown(() => otherDirectory.deleteSync(recursive: true));
      mine = await open();
      addTearDown(mine.close);
      other = await openAppDatabase(otherDirectory);
      addTearDown(other.close);
    });

    /// 一台裝置的資料；[tag] 區分兩台。
    Future<void> seed(AppDatabase database, String tag) async {
      await database.customStatement(
        "INSERT INTO accounts (plugin_id, user_id, display_name, status, "
        "logged_in_at) VALUES ('fmp-test', '$tag-user', '$tag', 'active', 1)",
      );
      await database.customStatement(
        'INSERT INTO layout_state (id, panel_width) '
        "VALUES (1, ${tag == 'mine' ? 300 : 500})",
      );
      await database.customStatement(
        "INSERT INTO playback_settings (id, output_device_id, "
        "output_device_name, play_history_limit) VALUES (1, '$tag-device', "
        "'$tag speakers', ${tag == 'mine' ? 10 : 20})",
      );
      await database.customStatement(
        "INSERT INTO developer_settings (id, plugin_dev_folder) "
        "VALUES (1, '$tag-folder')",
      );
    }

    Future<StagedBackup> stageOther() async {
      final backup = await DatabaseBackups(
        other,
        otherDirectory,
        log,
        readPlugin: lenientBackupReader,
      ).create();
      return backupsOf(mine).stageFile(File(backup.path));
    }

    test("replaces the backup's values with this device's", () async {
      await seed(mine, 'mine');
      await seed(other, 'other');
      final backups = backupsOf(mine);
      final staged = await stageOther();

      await backups.carryOver(staged, await backups.readCarriedState());

      final result = AppDatabase(NativeDatabase(File(staged.path)));
      addTearDown(result.close);
      Future<List<String>> column(String sql) async => [
        for (final row in await result.customSelect(sql).get())
          row.read<String>('v'),
      ];
      expect(await column('SELECT user_id AS v FROM accounts'), ['mine-user']);
      expect(
        await column('SELECT CAST(panel_width AS TEXT) AS v FROM layout_state'),
        ['300.0'],
      );
      expect(
        await column('SELECT output_device_id AS v FROM playback_settings'),
        ['mine-device'],
      );
      expect(
        await column('SELECT output_device_name AS v FROM playback_settings'),
        ['mine speakers'],
      );
      expect(
        await column('SELECT plugin_dev_folder AS v FROM developer_settings'),
        ['mine-folder'],
      );
      // 同一列的其他欄位是備份的。
      expect(
        await column(
          'SELECT CAST(play_history_limit AS TEXT) AS v FROM playback_settings',
        ),
        ['20'],
      );
    });

    test('keyed device columns come from this device by plugin id and NULL '
        'when it has no such row', () async {
      await install(other, 'both');
      await install(other, 'only-backup');
      await mine.customStatement(
        "INSERT INTO source_settings (plugin_id, browse_as_logged_in, "
        "match_target, match_rank) VALUES ('both', 1, 1, 9), "
        "('only-mine', 1, NULL, NULL)",
      );
      await other.customStatement(
        "INSERT INTO source_settings (plugin_id, browse_as_logged_in, "
        "match_target, match_rank) VALUES ('both', 0, 0, 2), "
        "('only-backup', 1, NULL, 5)",
      );
      final backups = backupsOf(mine);
      final staged = await stageOther();

      await backups.carryOver(staged, await backups.readCarriedState());

      final result = AppDatabase(NativeDatabase(File(staged.path)));
      addTearDown(result.close);
      final rows = await result
          .customSelect(
            'SELECT plugin_id, browse_as_logged_in AS b, match_target AS t, '
            'match_rank AS r FROM source_settings ORDER BY plugin_id',
          )
          .get();
      expect(rows.map((row) => row.read<String>('plugin_id')), [
        'both',
        'only-backup',
      ]);
      // 登入身分瀏覽：這台的值；這台沒有那一列是空值。其餘欄位照備份。
      expect(rows.map((row) => row.readNullable<int>('b')), [1, null]);
      expect(rows.map((row) => row.readNullable<int>('t')), [0, null]);
      expect(rows.map((row) => row.readNullable<int>('r')), [2, 5]);
    });

    test(
      'a backup file that still carries the value does not keep it',
      () async {
        await other.customStatement(
          "INSERT INTO source_settings (plugin_id, browse_as_logged_in) "
          "VALUES ('p', 1)",
        );
        final backups = backupsOf(mine);
        // 舊的備份檔沒把這欄清掉：直接塞進暫存檔的來源。
        final staged = await backups.stageBytes(
          await exportBytesOf(other, otherDirectory),
        );
        final raw = AppDatabase(NativeDatabase(File(staged.path)));
        addTearDown(raw.close);
        await raw.customStatement(
          'UPDATE source_settings SET browse_as_logged_in = 1',
        );

        await backups.carryOver(staged, await backups.readCarriedState());

        final row = await raw
            .customSelect(
              'SELECT browse_as_logged_in AS b FROM source_settings',
            )
            .getSingle();
        expect(row.readNullable<int>('b'), isNull);
      },
    );

    test('clears the values when this device has none', () async {
      await seed(other, 'other');
      final backups = backupsOf(mine);
      final staged = await stageOther();

      await backups.carryOver(staged, await backups.readCarriedState());

      final result = AppDatabase(NativeDatabase(File(staged.path)));
      addTearDown(result.close);
      final counted = await counts(result);
      expect(counted['accounts'], 0);
      expect(counted['layout_state'], 0);
      final device = await result
          .customSelect('SELECT output_device_id AS v FROM playback_settings')
          .getSingle();
      expect(device.readNullable<String>('v'), isNull);
      final folder = await result
          .customSelect('SELECT plugin_dev_folder AS v FROM developer_settings')
          .getSingle();
      expect(folder.readNullable<String>('v'), isNull);
    });

    test('adds the settings rows when the backup has none', () async {
      await seed(mine, 'mine');
      final backups = backupsOf(mine);
      final staged = await backups.stageBytes(
        await exportBytesOf(other, otherDirectory),
      );

      await backups.carryOver(staged, await backups.readCarriedState());

      final result = AppDatabase(NativeDatabase(File(staged.path)));
      addTearDown(result.close);
      final device = await result
          .customSelect('SELECT output_device_id AS v FROM playback_settings')
          .getSingle();
      expect(device.read<String>('v'), 'mine-device');
    });

    test('keeps this device\'s dev marker rows unless the backup has the '
        'same plugin', () async {
      for (final id in ['marker-only', 'shared']) {
        await mine.customStatement(
          "INSERT INTO installed_plugins (id, version, manifest_json, script, "
          "installed_at, from_dev_folder) VALUES ('$id', '9', '{}', '', 0, 1)",
        );
      }
      await other.customStatement(
        "INSERT INTO installed_plugins (id, version, manifest_json, script, "
        "installed_at) VALUES ('shared', '1', '{}', '', 0)",
      );
      final backups = backupsOf(mine);
      final staged = await stageOther();

      await backups.carryOver(staged, await backups.readCarriedState());

      final result = AppDatabase(NativeDatabase(File(staged.path)));
      addTearDown(result.close);
      final rows = await result
          .customSelect(
            'SELECT id, version, from_dev_folder AS marker '
            'FROM installed_plugins ORDER BY id',
          )
          .get();
      expect(
        [
          for (final row in rows)
            (row.read<String>('id'), row.read<int>('marker')),
        ],
        [('marker-only', 1), ('shared', 0)],
      );
      expect(rows.last.read<String>('version'), '1');
    });

    test('empties the other device-only tables and keeps the rest', () async {
      await seed(mine, 'mine');
      await install(other, 'fmp-test');
      await other.customStatement(
        "INSERT INTO plugin_storage (plugin_id, key, value) "
        "VALUES ('fmp-test', 'k', 'v')",
      );
      await other.customStatement(
        "INSERT INTO scheduler_runs (job_id, last_success_at) "
        "VALUES ('job', 1)",
      );
      await other.customStatement(
        "INSERT INTO plugin_indexes (url, added_at) VALUES ('https://i.test/', 1)",
      );
      final backups = backupsOf(mine);
      final staged = await stageOther();

      await backups.carryOver(staged, await backups.readCarriedState());

      final result = AppDatabase(NativeDatabase(File(staged.path)));
      addTearDown(result.close);
      final counted = await counts(result);
      expect(counted['plugin_storage'], 0);
      expect(counted['scheduler_runs'], 0);
      expect(counted['plugin_indexes'], 1);
      expect(counted['installed_plugins'], 1);
    });

    // 常數裡加一張不帶走的表、一欄裝置欄位，這台的值與還原都要跟著動；漏了就紅。
    test('the carried state and carryOver cover every constant', () async {
      await seed(mine, 'mine');
      await seed(other, 'other');
      final backups = backupsOf(mine);
      final state = await backups.readCarriedState();

      expect(state.tables.keys, unorderedEquals(backupKeptOnDeviceTables));
      expect(
        state.deviceColumns.keys,
        unorderedEquals(backupDeviceColumns.keys),
      );
      for (final MapEntry(key: table, value: columns)
          in backupDeviceColumns.entries) {
        expect(
          state.deviceColumns[table]!.keys,
          unorderedEquals(columns),
          reason: table,
        );
      }
      // 這台每一欄都有值，所以每一欄都能看出有沒有被帶到。
      for (final values in state.deviceColumns.values) {
        expect(values.values, everyElement(isNotNull));
      }
      expect(
        state.keyedDeviceColumns.keys,
        unorderedEquals(backupDeviceKeyedColumns.keys),
      );
      expect(
        backupKeptOnDeviceTables,
        everyElement(isIn(backupExcludedTables)),
      );

      final staged = await stageOther();
      await backups.carryOver(staged, state);
      final result = AppDatabase(NativeDatabase(File(staged.path)));
      addTearDown(result.close);
      for (final MapEntry(key: table, value: columns)
          in backupDeviceColumns.entries) {
        final row = await result
            .customSelect('SELECT ${columns.join(', ')} FROM "$table"')
            .getSingle();
        for (final column in columns) {
          expect(
            row.data[column],
            state.deviceColumns[table]![column],
            reason: '$table.$column',
          );
        }
      }
    });

    // 不帶走的每張表都要有「帶這台的」或「清空」的處理：常數裡新增一張，這個 map 沒跟著加就紅。
    test(
      'every excluded table is either kept from this device or emptied',
      () async {
        const insertOther = {
          'layout_state':
              'INSERT INTO layout_state (id, panel_width) VALUES (1, 500)',
          'accounts':
              "INSERT INTO accounts (plugin_id, user_id, display_name, status, "
              "logged_in_at) VALUES ('p', 'other', 'other', 'active', 1)",
          'plugin_storage':
              "INSERT INTO plugin_storage (plugin_id, key, value) "
              "VALUES ('p', 'k', 'v')",
          'scheduler_runs': "INSERT INTO scheduler_runs (job_id, last_success_at) VALUES ('j', 1)",
        };
        expect(insertOther.keys, unorderedEquals(backupExcludedTables));
        await install(other, 'p');
        for (final sql in insertOther.values) {
          await other.customStatement(sql);
        }
        final backups = backupsOf(mine);
        final staged = await stageOther();

        await backups.carryOver(staged, const CarriedState());

        // 這台什麼都沒有：每張不帶走的表在暫存檔裡都是空的，不論帶不帶這台的。
        final result = AppDatabase(NativeDatabase(File(staged.path)));
        addTearDown(result.close);
        final counted = await counts(result);
        for (final table in backupExcludedTables) {
          expect(counted[table], 0, reason: table);
        }
      },
    );

    test('rolls back completely when a write fails', () async {
      await seed(other, 'other');
      final backups = backupsOf(mine);
      final staged = await stageOther();

      await expectLater(
        backups.carryOver(
          staged,
          const CarriedState(
            tables: {
              'accounts': [
                {'plugin_id': 'fmp-test', 'no_such_column': 1},
              ],
            },
            deviceColumns: {
              'playback_settings': {'output_device_id': 'mine-device'},
            },
          ),
        ),
        throwsA(anything),
      );

      final result = AppDatabase(NativeDatabase(File(staged.path)));
      addTearDown(result.close);
      final counted = await counts(result);
      expect(counted['accounts'], 1);
      final device = await result
          .customSelect('SELECT output_device_id AS v FROM playback_settings')
          .getSingle();
      expect(device.read<String>('v'), 'other-device');
    });
  });

  group('discard', () {
    test('deletes the staged file', () async {
      final database = await open();
      addTearDown(database.close);
      final backups = backupsOf(database);
      final staged = await backups.stageFile(
        File((await backups.create()).path),
      );

      await backups.discard(staged);

      expect(File(staged.path).existsSync(), isFalse);
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
