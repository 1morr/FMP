import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/backup.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/backup_format.dart';
import 'package:fmp/data/database/database_backups.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/repository/plugin_updates.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../ui/support/plugin_page_harness.dart' show pluginScript;

// 設定頁的匯出與選檔驗證流程（M4 PR 22，ADR 0034 §決定 1、4）；備份檔本身的內容規則在
// `test/data/database/database_backups_test.dart`。

class _Dialogs implements FileDialogs {
  PickedFile? picked;
  Uri? saveResult = Uri.file('/fake/saved.db');
  Object? saveError;
  final extensions = <String>[];
  final maxBytes = <int?>[];
  final saves = <({String name, Uint8List bytes, String mimeType})>[];

  @override
  Future<PickedFile?> pickFile({
    required String extension,
    int? maxBytes,
  }) async {
    this.maxBytes.add(maxBytes);
    extensions.add(extension);
    return picked;
  }

  @override
  Future<Uri?> saveFile({
    required String name,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    saves.add((name: name, bytes: bytes, mimeType: mimeType));
    if (saveError case final error?) throw error;
    return saveResult;
  }

  @override
  Future<String?> pickDirectory() async => null;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const fakeCookie = 'fake-cookie-***-marker';

  late Directory dataDirectory;
  late Log log;
  late AppDatabase database;
  late _Dialogs dialogs;
  late FileAppBackup backup;

  setUp(() async {
    dataDirectory = Directory.systemTemp.createTempSync('fmp_backup_flow_');
    addTearDown(() => dataDirectory.deleteSync(recursive: true));
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.info);
    database = await openAppDatabase(dataDirectory);
    addTearDown(database.close);
    dialogs = _Dialogs();
    backup = FileAppBackup(
      databaseBackups: DatabaseBackups(
        database,
        dataDirectory,
        log,
        readPlugin: readBackupPlugin,
      ),
      dataDirectory: dataDirectory,
      fileDialogs: dialogs,
      log: log,
    );
    final script = pluginScript('fmp-test');
    await database.customStatement(
      'INSERT INTO installed_plugins (id, version, manifest_json, script, '
      'installed_at) VALUES (?, ?, ?, ?, 0)',
      ['fmp-test', '1.0.0', PluginFile.parse(script).manifestJson, script],
    );
    await database.customStatement(
      "INSERT INTO plugin_storage (plugin_id, key, value) "
      "VALUES ('fmp-test', 'k', '$fakeCookie')",
    );
  });

  /// 匯出現在的資料庫、把檔案交給選檔對話框，再選檔驗證。
  Future<StagedBackup?> exportAndPick() async {
    await backup.export();
    dialogs.picked = PickedFile(name: 'b.db', bytes: dialogs.saves.last.bytes);
    return backup.pickAndStage();
  }

  File tempFile() => File(p.join(dataDirectory.path, backupExportTempName));

  group('export', () {
    test('hands the cleaned file to the save dialog and removes the temp '
        'file', () async {
      final saved = await withClock(
        Clock.fixed(DateTime.utc(2026, 10, 21, 1, 2, 3, 4)),
        backup.export,
      );

      expect(saved, Uri.file('/fake/saved.db'));
      final save = dialogs.saves.single;
      expect(save.name, 'fmp-backup-20261021T010203004Z.db');
      expect(save.mimeType, 'application/vnd.sqlite3');
      expect(
        utf8.decode(save.bytes.sublist(0, 15), allowMalformed: true),
        'SQLite format 3',
      );
      expect(
        utf8.decode(save.bytes, allowMalformed: true),
        isNot(contains(fakeCookie)),
      );
      expect(tempFile().existsSync(), isFalse);
      expect(File('${tempFile().path}.partial').existsSync(), isFalse);
      expect(
        log.history.any((record) => record.message == 'Backup exported'),
        isTrue,
      );
    });

    test('the file it hands over can be restored', () async {
      await backup.export();

      final staged = await DatabaseBackups(
        database,
        dataDirectory,
        log,
        readPlugin: readBackupPlugin,
      ).stageBytes(dialogs.saves.single.bytes);

      expect(staged.plugins.map((plugin) => plugin.id), ['fmp-test']);
    });

    test(
      'cancelling returns null, logs nothing and leaves no temp file',
      () async {
        dialogs.saveResult = null;

        expect(await backup.export(), isNull);

        expect(tempFile().existsSync(), isFalse);
        expect(
          log.history.any((record) => record.message == 'Backup exported'),
          isFalse,
        );
      },
    );

    test('a failed save is logged, rethrown and leaves no temp file', () async {
      dialogs.saveError = const FileSystemException('disk full');

      await expectLater(backup.export(), throwsA(isA<FileSystemException>()));

      expect(tempFile().existsSync(), isFalse);
      expect(
        log.history.where((record) => record.level == LogLevel.error),
        hasLength(1),
      );
    });

    test('a platform without file dialogs cannot export', () async {
      final without = FileAppBackup(
        databaseBackups: DatabaseBackups(
          database,
          dataDirectory,
          log,
          readPlugin: readBackupPlugin,
        ),
        dataDirectory: dataDirectory,
        fileDialogs: null,
        log: log,
      );

      await expectLater(without.export(), throwsUnsupportedError);
    });
  });

  group('pickAndStage', () {
    test('asks for a .db file and stages the chosen one', () async {
      await backup.export();
      dialogs.picked = PickedFile(
        name: 'fmp-backup.db',
        bytes: dialogs.saves.single.bytes,
      );

      final staged = await backup.pickAndStage();

      expect(dialogs.extensions, ['db']);
      expect(staged, isNotNull);
      expect(File(staged!.path).existsSync(), isTrue);
    });

    test('cancelling returns null', () async {
      expect(await backup.pickAndStage(), isNull);
    });

    test('a file that is not a backup is rejected and logged', () async {
      dialogs.picked = PickedFile(
        name: 'notes.db',
        bytes: Uint8List.fromList(utf8.encode('hello')),
      );

      await expectLater(
        backup.pickAndStage(),
        throwsA(
          isA<BackupRejected>().having(
            (e) => e.reason,
            'reason',
            BackupRejection.notFmpBackup,
          ),
        ),
      );

      expect(
        log.history.any(
          (record) => record.message == 'A backup file was rejected',
        ),
        isTrue,
      );
    });
  });

  group('plugins in the file', () {
    /// 把 [script] 以覆蓋的欄位裝進資料庫，匯出，再選檔驗證。
    Future<StagedBackup?> stageWith({
      required String script,
      String? id,
      String? version,
      String? manifestJson,
    }) async {
      final file = PluginFile.parse(script);
      await database.customStatement(
        'INSERT INTO installed_plugins (id, version, manifest_json, script, '
        'installed_at) VALUES (?, ?, ?, ?, 0)',
        [
          id ?? file.manifest.id,
          version ?? file.manifest.version,
          manifestJson ?? file.manifestJson,
          script,
        ],
      );
      return exportAndPick();
    }

    Future<void> expectMismatch(Future<StagedBackup?> staging) async {
      await expectLater(
        staging,
        throwsA(
          isA<BackupRejected>().having(
            (e) => e.reason,
            'reason',
            BackupRejection.notFmpBackup,
          ),
        ),
      );
      final leftovers = Directory(p.join(dataDirectory.path, 'backups'))
          .listSync()
          .where((e) => p.basename(e.path).startsWith('staged-'));
      expect(leftovers, isEmpty);
    }

    setUp(() async {
      // 外層 setUp 裝了一個空腳本的 fmp-test；這一組自己決定要什麼。
      await database.customStatement('DELETE FROM plugin_storage');
      await database.customStatement('DELETE FROM installed_plugins');
    });

    test('lists name, version and hosts from the script header', () async {
      final script = pluginScript(
        'fmp-test',
        name: 'Test Source',
        version: '1.2.3',
        hosts: ['example.test', 'cdn.example.test'],
      );

      final staged = await stageWith(script: script);

      expect(staged!.plugins, const [
        BackupPlugin(
          id: 'fmp-test',
          name: 'Test Source',
          version: '1.2.3',
          hosts: ['example.test', 'cdn.example.test'],
        ),
      ]);
    });

    test('refuses a row whose manifest_json names other hosts than the '
        'script header', () async {
      final script = pluginScript('fmp-test', hosts: ['evil.example']);
      final safe = PluginFile.parse(
        pluginScript('fmp-test', hosts: ['safe.example']),
      ).manifestJson;

      await expectMismatch(stageWith(script: script, manifestJson: safe));
    });

    test('refuses a row whose id differs from the script header', () async {
      await expectMismatch(
        stageWith(script: pluginScript('fmp-test'), id: 'other-id'),
      );
    });

    test(
      'refuses a row whose version differs from the script header',
      () async {
        await expectMismatch(
          stageWith(script: pluginScript('fmp-test'), version: '9.9.9'),
        );
      },
    );

    /// 備份裡 [id] 這一列之後有沒有留在暫存檔。
    Future<int> stagedRows(StagedBackup staged) async {
      final copy = AppDatabase(NativeDatabase(File(staged.path)));
      addTearDown(copy.close);
      return (await copy
              .customSelect('SELECT COUNT(*) AS n FROM installed_plugins')
              .getSingle())
          .read<int>('n');
    }

    test('drops a plugin whose apiVersion this app does not support', () async {
      final unsupported = pluginScript(
        'evil',
        hosts: ['evil.example'],
      ).replaceFirst('"apiVersion":1', '"apiVersion":2');
      expect(unsupported, contains('"apiVersion":2'));
      final good = pluginScript('good');
      for (final (id, script) in [('evil', unsupported), ('good', good)]) {
        await database.customStatement(
          'INSERT INTO installed_plugins (id, version, manifest_json, script, '
          "installed_at) VALUES (?, '1.0.0', '{}', ?, 0)",
          [id, script],
        );
      }
      // 'good' 的列和標頭不一致會被拒絕：先把它改成一致。
      final header = PluginFile.parse(good);
      await database.customStatement(
        'UPDATE installed_plugins SET manifest_json = ?, version = ? '
        "WHERE id = 'good'",
        [header.manifestJson, header.manifest.version],
      );
      await database.customStatement(
        "INSERT INTO plugin_storage (plugin_id, key, value) "
        "VALUES ('evil', 'k', 'v')",
      );
      await database.customStatement(
        "INSERT INTO source_settings (plugin_id, browse_as_logged_in) "
        "VALUES ('evil', 1), ('good', 1)",
      );
      await database.customStatement(
        "INSERT INTO chart_settings (plugin_id, chart_id, enabled) "
        "VALUES ('evil', 'hot', 1), ('good', 'hot', 1)",
      );
      final backups = DatabaseBackups(
        database,
        dataDirectory,
        log,
        readPlugin: readBackupPlugin,
      );
      // 整份副本連 plugin_storage 都帶著，才看得到 cascade。
      final full = await backups.create();

      final staged = await backups.stageFile(File(full.path));

      expect(staged.unusablePluginIds, ['evil']);
      expect(staged.plugins.map((plugin) => plugin.id), ['good']);
      expect(await stagedRows(staged), 1);
      final copy = AppDatabase(NativeDatabase(File(staged.path)));
      addTearDown(copy.close);
      final storage = await copy
          .customSelect('SELECT COUNT(*) AS n FROM plugin_storage')
          .getSingle();
      expect(storage.read<int>('n'), 0);
      // 比照移除插件：被丟掉的插件，每音源設定與榜單設定也一起刪。
      for (final table in ['source_settings', 'chart_settings']) {
        final ids = await copy
            .customSelect('SELECT plugin_id FROM $table')
            .map((row) => row.read<String>('plugin_id'))
            .get();
        expect(ids, ['good'], reason: table);
      }
    });

    test('drops a plugin whose header is broken, and lists it', () async {
      await database.customStatement(
        "INSERT INTO installed_plugins (id, version, manifest_json, script, "
        "installed_at) VALUES ('fmp-test', '1.0.0', '{}', 'broken', 0)",
      );

      final staged = await exportAndPick();

      expect(staged!.plugins, isEmpty);
      expect(staged.unusablePluginIds, ['fmp-test']);
      expect(await stagedRows(staged), 0);
    });

    // 備份檔自己的欄位型別不可信：把 `from_dev_folder` 的型別拿掉、值寫成文字 '0'，
    // 重建之後它是 INTEGER 0，過濾與一致性檢查都看得到這一列。
    test('a column whose type was removed does not hide a row from the '
        'check', () async {
      final script = pluginScript('fmp-test', hosts: ['evil.example']);
      final safe = PluginFile.parse(
        pluginScript('fmp-test', hosts: ['safe.example']),
      ).manifestJson;
      await database.customStatement(
        'INSERT INTO installed_plugins (id, version, manifest_json, script, '
        'installed_at) VALUES (?, ?, ?, ?, 0)',
        ['fmp-test', '1.0.0', safe, script],
      );
      await backup.export();
      final tampered = p.join(dataDirectory.path, 'tampered.db');
      File(tampered).writeAsBytesSync(dialogs.saves.last.bytes);
      final raw = sqlite.sqlite3.open(tampered);
      raw.execute('PRAGMA writable_schema = ON');
      raw.execute(
        'UPDATE sqlite_master SET sql = replace(replace(sql, '
        "'\"from_dev_folder\" INTEGER', '\"from_dev_folder\"'), "
        "' CHECK (\"from_dev_folder\" IN (0, 1))', '') "
        "WHERE name = 'installed_plugins'",
      );
      raw.execute('PRAGMA writable_schema = OFF');
      raw.close();
      // 重開連線才會讀到改過的 schema；同一個連線仍照舊的型別轉換。
      final edited = sqlite.sqlite3.open(tampered);
      expect(
        edited
            .select(
              "SELECT sql FROM sqlite_master WHERE name = 'installed_plugins'",
            )
            .single['sql'],
        isNot(contains('CHECK ("from_dev_folder"')),
      );
      edited.execute("UPDATE installed_plugins SET from_dev_folder = '0'");
      edited.close();
      // 竄改要真的生效，否則這個測試驗不到讀取順序。
      final check = sqlite.sqlite3.open(tampered);
      expect(
        check
            .select(
              'SELECT typeof(from_dev_folder) AS t FROM installed_plugins',
            )
            .single['t'],
        'text',
      );
      check.close();
      dialogs.picked = PickedFile(
        name: 'b.db',
        bytes: File(tampered).readAsBytesSync(),
      );

      // 被拒絕的原因是「列與標頭不一致」，不是更早的別的檢查。
      await expectLater(
        backup.pickAndStage(),
        throwsA(
          isA<BackupRejected>().having(
            (e) => e.detail,
            'detail',
            contains('does not match its script header'),
          ),
        ),
      );
    });

    test('ignores a development marker row, whatever it holds', () async {
      await database.customStatement(
        "INSERT INTO installed_plugins (id, version, manifest_json, script, "
        "installed_at, from_dev_folder) VALUES ('dev', '0', '{}', 'junk', 0, 1)",
      );

      final staged = await stageWith(script: pluginScript('fmp-test'));

      expect(staged!.plugins.map((plugin) => plugin.id), ['fmp-test']);
    });
  });

  group('file size', () {
    test('a file over the limit is refused as not a backup', () async {
      final tooLarge = FileAppBackup(
        databaseBackups: DatabaseBackups(
          database,
          dataDirectory,
          log,
          readPlugin: readBackupPlugin,
        ),
        dataDirectory: dataDirectory,
        fileDialogs: _TooLarge(),
        log: log,
      );

      await expectLater(
        tooLarge.pickAndStage(),
        throwsA(
          isA<BackupRejected>().having(
            (e) => e.reason,
            'reason',
            BackupRejection.notFmpBackup,
          ),
        ),
      );
    });

    test('asks the dialog to apply the limit', () async {
      await backup.pickAndStage();

      expect(dialogs.maxBytes, [backupMaxBytes]);
    });
  });

  group('reviewRestore', () {
    InstalledPlugin installed(
      String id,
      String version,
      List<String> hosts, {
      bool dev = false,
    }) {
      final script = pluginScript(id, version: version, hosts: hosts);
      return InstalledPlugin(
        id: id,
        version: version,
        manifestJson: PluginFile.parse(script).manifestJson,
        script: script,
        installedAt: DateTime.utc(2026),
        fromDevFolder: dev,
      );
    }

    const staged = StagedBackup(
      path: '/s.db',
      plugins: [
        BackupPlugin(
          id: 'same',
          name: 'Same',
          version: '1.0.0',
          hosts: ['a.test', 'new.test'],
        ),
        BackupPlugin(
          id: 'older',
          name: 'Older',
          version: '1.0.0',
          hosts: ['a.test'],
        ),
        BackupPlugin(
          id: 'newer',
          name: 'Newer',
          version: '3.0.0',
          hosts: ['a.test'],
        ),
        BackupPlugin(
          id: 'absent',
          name: 'Absent',
          version: '1.0.0',
          hosts: ['x.test'],
        ),
      ],
      indexUrls: ['https://i.test/'],
    );

    test('marks older versions and the hosts this device lacks', () {
      final review = reviewRestore(staged, [
        installed('same', '1.0.0', ['a.test']),
        installed('older', '2.0.0', ['a.test']),
        installed('newer', '2.0.0', ['a.test']),
      ]);

      final byId = {for (final r in review.plugins) r.plugin.id: r};
      expect(byId['same']!.older, isFalse);
      expect(byId['same']!.addedHosts, ['new.test']);
      expect(byId['older']!.older, isTrue);
      expect(byId['older']!.installedVersion, '2.0.0');
      expect(byId['newer']!.older, isFalse);
      expect(byId['absent']!.installedVersion, isNull);
      // 這台沒裝的插件，網域全部算新增。
      expect(byId['absent']!.addedHosts, ['x.test']);
      expect(review.indexUrls, ['https://i.test/']);
    });

    test('a development marker row is not an installed plugin', () {
      final review = reviewRestore(staged, [
        installed('same', '9.0.0', ['a.test', 'new.test'], dev: true),
      ]);

      expect(review.plugins.first.installedVersion, isNull);
      expect(review.plugins.first.older, isFalse);
    });

    test('a version that is not semver is never "older"', () {
      expect(isOlderVersion('abc', '1.0.0'), isFalse);
      expect(isOlderVersion('1.0.0', 'abc'), isFalse);
      expect(isOlderVersion('1.0.0', '1.0.1'), isTrue);
      expect(isOlderVersion('1.0.1', '1.0.0'), isFalse);
    });
  });
}

final class _TooLarge extends _Dialogs {
  @override
  Future<PickedFile?> pickFile({required String extension, int? maxBytes}) =>
      throw const PickedFileTooLarge(
        name: 'huge.db',
        size: 2000000000,
        maxBytes: 1,
      );
}
