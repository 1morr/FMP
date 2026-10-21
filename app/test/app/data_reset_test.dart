import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/backup.dart';
import 'package:fmp/app/data_reset.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:drift/native.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/backup_format.dart';
import 'package:fmp/data/database/database_backups.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/platform/app_restart/app_restart.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:path/path.dart' as p;

import '../support/credentials.dart';
import '../ui/support/plugin_page_harness.dart' show pluginScript;

// 重設資料與從備份還原（M3 PR 14b，ADR 0025 §決定 9、ADR 0012 §如何確認）。

/// 把每一步記進共用的 [events]，順序就是閘門。
final class _RecordingStorage implements SecureStorage {
  _RecordingStorage(this.events);

  final List<String> events;
  final values = <String, String>{};

  @override
  Future<void> deleteAll() async {
    events.add('secure storage');
    values.clear();
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

final class _RecordingWebView implements LoginWebView {
  _RecordingWebView(this.events);

  final List<String> events;

  @override
  Future<void> clearAll() async => events.add('web view');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by the reset');
}

/// 重啟時記下 log 檔當下的內容：重啟會結束行程，log 要在那之前寫完。
final class _RecordingRestarter implements AppRestarter {
  _RecordingRestarter(this.events, this.logDirectory);

  final List<String> events;
  final Directory logDirectory;
  String logAtRestart = '';

  @override
  Future<void> restart() async {
    events.add('restart');
    logAtRestart = [
      for (final file in logDirectory.listSync().whereType<File>())
        file.readAsStringSync(),
    ].join();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dataDirectory;
  late Directory logDirectory;
  late List<String> events;
  late _RecordingStorage storage;
  late _RecordingWebView webView;
  late _RecordingRestarter restarter;
  late Log log;
  late AppDatabase database;
  late AppDataReset reset;

  /// [clearCache] 預設只記一筆事件。
  AppDataReset buildReset(
    AppDatabase database, {
    Future<void> Function()? clearCache,
  }) => AppDataReset(
    databaseBackups: DatabaseBackups(
      database,
      dataDirectory,
      log,
      readPlugin: readBackupPlugin,
    ),
    secureStorage: storage,
    loginWebView: webView,
    clearCache: clearCache ?? () async => events.add('cache'),
    log: log,
    restarter: restarter,
  );

  setUp(() async {
    dataDirectory = Directory.systemTemp.createTempSync('fmp_reset_');
    addTearDown(() => dataDirectory.deleteSync(recursive: true));
    logDirectory = Directory(p.join(dataDirectory.path, 'logs'));
    events = [];
    storage = _RecordingStorage(events);
    webView = _RecordingWebView(events);
    restarter = _RecordingRestarter(events, logDirectory);
    log = Log(
      redactor: Redactor(),
      minimumLevel: LogLevel.info,
      file: LogFile(logDirectory),
    );
    // log 檔是背景寫的：刪目錄之前等它寫完（Windows 上開著的檔案刪不掉）。
    addTearDown(() => log.file!.flush());
    database = await openAppDatabase(dataDirectory);
    addTearDown(database.close);
    reset = buildReset(database);
  });

  Future<void> seed() async {
    final script = pluginScript(
      'fmp-test',
      name: 'fmp-test',
      login: {
        'methods': ['qr'],
      },
    );
    await PluginRepository(database).install(
      InstalledPlugin(
        id: 'fmp-test',
        version: '1.0.0',
        manifestJson: PluginFile.parse(script).manifestJson,
        script: script,
        installedAt: DateTime.utc(2026),
      ),
    );
    await AccountRepository(database).upsert(
      Account(
        pluginId: 'fmp-test',
        userId: 'u',
        displayName: 'Someone',
        status: AccountStatus.active,
        loggedInAt: DateTime.utc(2026, 10, 9),
      ),
    );
    storage.values['credentials.fmp-test'] = jsonEncode({
      'cookies': {'FAKE_SESSION': 'FAKE_COOKIE_VALUE_12345'},
    });
  }

  Future<int> pluginCount(AppDatabase database) async =>
      (await PluginRepository(database).list()).length;

  group('backing up', () {
    test('a failed backup is reported and logged', () async {
      File(p.join(dataDirectory.path, backupDirectoryName))
          .writeAsStringSync('blocks the directory');

      await expectLater(reset.backUp(), throwsA(isA<FileSystemException>()));

      expect(
        log.history.where((record) => record.level == LogLevel.error),
        hasLength(1),
      );
      // 備份只是備份，其他東西都沒動。
      expect(events, isEmpty);
    });
  });

  group('resetting', () {
    test('clears in order, flushes the log, then restarts', () async {
      await seed();
      final backup = await reset.backUp();

      await reset.resetAndRestart(backup);

      expect(events, ['secure storage', 'web view', 'cache', 'restart']);
      // 重啟那一刻，「要重啟」這筆 log 已經寫進檔案。
      expect(restarter.logAtRestart, contains('Data reset; restarting'));
    });

    test('leaves an empty database, no credentials, and keeps logs '
        'and backups', () async {
      await seed();
      final backup = await reset.backUp();

      await reset.resetAndRestart(backup);

      expect(storage.values, isEmpty);
      expect(logDirectory.listSync(), isNotEmpty);
      expect(File(backup.path).existsSync(), isTrue);
      expect(
        File(p.join(dataDirectory.path, databaseFileName)).existsSync(),
        isFalse,
      );
      // 下次啟動：空的資料庫。
      final fresh = await openAppDatabase(dataDirectory);
      addTearDown(fresh.close);
      expect(await pluginCount(fresh), 0);
      expect(await AccountRepository(fresh).list(), isEmpty);
      // 憑證存放是空的，之後的請求不會帶憑證（ADR 0012 §如何確認）。
      final credentials = credentialStoreFor(
        fresh,
        redactor: Redactor(),
        log: log,
        storage: storage,
      );
      addTearDown(credentials.dispose);
      expect(await credentials.state('fmp-test'), CredentialState.none);
      expect(await credentials.credentialMaterial('fmp-test'), isNull);
    });

    test('the backup holds the data that was cleared', () async {
      await seed();
      final backup = await reset.backUp();
      await reset.resetAndRestart(backup);

      final fresh = await openAppDatabase(dataDirectory);
      addTearDown(fresh.close);
      expect(await pluginCount(fresh), 0);
      final backups = DatabaseBackups(
        fresh,
        dataDirectory,
        log,
        readPlugin: readBackupPlugin,
      );
      await backups.restoreStaged(await backups.stageFile(File(backup.path)));
      final restored = await openAppDatabase(dataDirectory);
      addTearDown(restored.close);
      expect(await pluginCount(restored), 1);
    });

    test('a missing backup clears nothing', () async {
      await seed();
      final backup = await reset.backUp();
      File(backup.path).deleteSync();

      await expectLater(reset.resetAndRestart(backup), throwsStateError);

      expect(events, isEmpty);
      expect(storage.values, isNotEmpty);
      expect(await pluginCount(database), 1);
    });

    test('a platform without a login web view skips that step', () async {
      await seed();
      final backup = await reset.backUp();

      await AppDataReset(
        databaseBackups: DatabaseBackups(
          database,
          dataDirectory,
          log,
          readPlugin: readBackupPlugin,
        ),
        secureStorage: storage,
        loginWebView: null,
        clearCache: () async => events.add('cache'),
        log: log,
        restarter: restarter,
      ).resetAndRestart(backup);

      expect(events, ['secure storage', 'cache', 'restart']);
    });

    test('a failing step stops the reset there', () async {
      await seed();
      final backup = await reset.backUp();
      final failing = buildReset(
        database,
        clearCache: () async => throw const FileSystemException('cache'),
      );

      await expectLater(
        failing.resetAndRestart(backup),
        throwsA(isA<FileSystemException>()),
      );

      // 資料庫與重啟都沒發生。
      expect(events, ['secure storage', 'web view']);
      expect(await pluginCount(database), 1);
      expect(
        File(p.join(dataDirectory.path, databaseFileName)).existsSync(),
        isTrue,
      );
    });
  });

  group('restoring', () {
    Future<StagedBackup> stage(DatabaseBackup backup) =>
        reset.stageBackup(backup);

    test('replaces the data, keeps the login, then restarts', () async {
      await seed();
      final backup = await reset.backUp();
      await PluginRepository(database).install(
        InstalledPlugin(
          id: 'later',
          version: '1.0.0',
          manifestJson: '{}',
          script: '',
          installedAt: DateTime.utc(2026),
        ),
      );
      // 這台之後換了帳號；備份裡是舊的。
      await AccountRepository(database).upsert(
        Account(
          pluginId: 'fmp-test',
          userId: 'this-device',
          displayName: 'This device',
          status: AccountStatus.active,
          loggedInAt: DateTime.utc(2026, 10, 12),
        ),
      );
      final staged = await stage(backup);

      await reset.restoreAndRestart(staged);

      final restored = await openAppDatabase(dataDirectory);
      addTearDown(restored.close);
      expect((await PluginRepository(restored).list()).map((e) => e.id), [
        'fmp-test',
      ]);
      // 帳號列是這台目前的，不是備份裡的。
      expect((await AccountRepository(restored).list()).map((e) => e.userId), [
        'this-device',
      ]);
      // 憑證與登入 WebView 都沒動（ADR 0034 §決定 4）；快取也不動。
      expect(events, ['restart']);
      expect(storage.values.keys, ['credentials.fmp-test']);
      final credentials = credentialStoreFor(
        restored,
        redactor: Redactor(),
        log: log,
        storage: storage,
      );
      addTearDown(credentials.dispose);
      expect(await credentials.state('fmp-test'), CredentialState.active);
      expect(restarter.logAtRestart, contains('Backup restored; restarting'));
    });

    test('backs up the current database before replacing it', () async {
      await seed();
      final backup = await reset.backUp();
      await PluginRepository(database).install(
        InstalledPlugin(
          id: 'later',
          version: '1.0.0',
          manifestJson: '{}',
          script: '',
          installedAt: DateTime.utc(2026),
        ),
      );
      final staged = await stage(backup);

      await withClock(
        Clock.fixed(DateTime.utc(2026, 10, 14, 1)),
        () => reset.restoreAndRestart(staged),
      );

      // 自動備份是還原前的資料庫（兩個插件）。
      final auto = File(
        p.join(
          dataDirectory.path,
          backupDirectoryName,
          'fmp-20261014T010000000Z.db',
        ),
      );
      expect(auto.existsSync(), isTrue);
      final copy = AppDatabase(NativeDatabase(auto));
      addTearDown(copy.close);
      expect(await PluginRepository(copy).list(), hasLength(2));
    });

    test('empties plugin_storage and scheduler_runs, whatever the file '
        'holds', () async {
      await seed();
      await database.customStatement(
        "INSERT INTO plugin_storage (plugin_id, key, value) "
        "VALUES ('fmp-test', 'anonymous', 'fake-cookie-from-the-file')",
      );
      await database.customStatement(
        "INSERT INTO scheduler_runs (job_id, last_success_at) "
        "VALUES ('job', 1)",
      );
      // 整份副本（Debug 頁的備份）連這兩張表都帶著。
      final backup = await reset.backUp();
      final staged = await stage(backup);

      await reset.restoreAndRestart(staged);

      final restored = await openAppDatabase(dataDirectory);
      addTearDown(restored.close);
      for (final table in ['plugin_storage', 'scheduler_runs']) {
        final row = await restored
            .customSelect('SELECT COUNT(*) AS n FROM "$table"')
            .getSingle();
        expect(row.read<int>('n'), 0, reason: table);
      }
    });

    test('a failed automatic backup replaces nothing', () async {
      await seed();
      final backup = await reset.backUp();
      final staged = await stage(backup);
      final fixed = Clock.fixed(DateTime.utc(2026, 10, 14, 1));
      // 同一毫秒已經有同名的備份：自動備份會失敗。
      await withClock(fixed, reset.backUp);

      await expectLater(
        withClock(fixed, () => reset.restoreAndRestart(staged)),
        throwsA(isA<FileSystemException>()),
      );

      expect(events, isEmpty);
      expect(await pluginCount(database), 1);
      // 暫存檔還在，由呼叫端決定要不要刪。
      expect(File(staged.path).existsSync(), isTrue);
      await reset.discardStaged(staged);
      expect(File(staged.path).existsSync(), isFalse);
    });

    test('a rejected backup stages nothing', () async {
      final backup = await reset.backUp();
      File(backup.path).writeAsStringSync('not a database');

      await expectLater(
        reset.stageBackup(backup),
        throwsA(
          isA<BackupRejected>().having(
            (e) => e.reason,
            'reason',
            BackupRejection.notFmpBackup,
          ),
        ),
      );

      expect(events, isEmpty);
      expect(await pluginCount(database), 0);
    });

    test(
      'still restarts when the swap fails after the database closed',
      () async {
        await seed();
        final backup = await reset.backUp();
        final staged = await stage(backup);
        // 原檔改名的目標被資料夾佔住：資料庫關閉之後才失敗，原檔還在原處。
        const stamp = '20261014T010000000Z';
        final databasePath = p.join(dataDirectory.path, databaseFileName);
        final blocker = Directory('$databasePath.before-restore-$stamp')
          ..createSync();
        File(p.join(blocker.path, 'keep')).writeAsStringSync('x');

        await expectLater(
          withClock(
            Clock.fixed(DateTime.utc(2026, 10, 14, 1)),
            () => reset.restoreAndRestart(staged),
          ),
          throwsA(isA<FileSystemException>()),
        );

        // 關閉之後的資料庫不能再用：記下錯誤、照樣重啟，回到原本的資料庫。
        expect(events, ['restart']);
        expect(
          restarter.logAtRestart,
          contains('The restore failed after the database was closed'),
        );
        final reopened = await openAppDatabase(dataDirectory);
        addTearDown(reopened.close);
        expect(await pluginCount(reopened), 1);
      },
    );
  });
}
