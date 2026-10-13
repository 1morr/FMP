import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/data_reset.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/database_backups.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/platform/app_restart/app_restart.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:path/path.dart' as p;

import '../support/credentials.dart';

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
    databaseBackups: DatabaseBackups(database, dataDirectory, log),
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
    await PluginRepository(database).install(
      InstalledPlugin(
        id: 'fmp-test',
        version: '1.0.0',
        manifestJson: jsonEncode({
          'id': 'fmp-test',
          'name': 'fmp-test',
          'version': '1.0.0',
          'author': 'FMP tests',
          'apiVersion': 1,
          'capabilities': ['search', 'login'],
          'allowedHosts': ['example.test'],
          'login': {
            'methods': ['qr'],
          },
        }),
        script: '',
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
      await DatabaseBackups(fresh, dataDirectory, log).restore(backup);
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
        databaseBackups: DatabaseBackups(database, dataDirectory, log),
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
    test('replaces the data, clears the credentials, then restarts', () async {
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

      await reset.restoreAndRestart(backup);

      final restored = await openAppDatabase(dataDirectory);
      addTearDown(restored.close);
      expect((await PluginRepository(restored).list()).map((e) => e.id), [
        'fmp-test',
      ]);
      // 憑證不在備份裡：先清掉，免得配上備份裡的帳號列；快取不動。
      expect(events, ['secure storage', 'web view', 'restart']);
      expect(storage.values, isEmpty);
      expect(restarter.logAtRestart, contains('Database restored; restarting'));
    });

    test('a missing backup throws without restarting', () async {
      final backup = await reset.backUp();
      File(backup.path).deleteSync();

      await expectLater(
        reset.restoreAndRestart(backup),
        throwsA(isA<StateError>()),
      );

      // 備份不見就什麼都不動：不清憑證、不關資料庫、不重啟。
      expect(events, isEmpty);
      expect(await pluginCount(database), 0);
    });

    test(
      'still restarts when the swap fails after the database closed',
      () async {
        await seed();
        final backup = await reset.backUp();
        // 殘留 journal 的改名目標被資料夾佔住：資料庫關閉、主檔移開之後才失敗，原檔改回來。
        const stamp = '20261014T010000000Z';
        final databasePath = p.join(dataDirectory.path, databaseFileName);
        File('$databasePath-journal').writeAsStringSync('stale');
        final blocker = Directory('$databasePath-journal.before-restore-$stamp')
          ..createSync();
        File(p.join(blocker.path, 'keep')).writeAsStringSync('x');

        await expectLater(
          withClock(
            Clock.fixed(DateTime.utc(2026, 10, 14, 1)),
            () => reset.restoreAndRestart(backup),
          ),
          throwsA(isA<FileSystemException>()),
        );

        // 關閉之後的資料庫不能再用：記下錯誤、照樣重啟，回到原本的資料庫。
        expect(events, ['secure storage', 'web view', 'restart']);
        expect(
          restarter.logAtRestart,
          contains('The restore failed after the database was closed'),
        );
        File('$databasePath-journal').deleteSync();
        final reopened = await openAppDatabase(dataDirectory);
        addTearDown(reopened.close);
        expect(await pluginCount(reopened), 1);
      },
    );
  });
}
