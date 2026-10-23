import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/first_launch_import.dart';
import 'package:fmp/app/legacy_import.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/legacy_import/legacy_database_reader.dart';
import 'package:fmp/legacy_import/legacy_importer.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:path/path.dart' as p;

import '../legacy_import/legacy_credential_fixtures.dart';
import '../support/credentials.dart';
import '../support/legacy_database.dart';

// 首次啟動的中途失敗（M5 design §3.1、§9）：每一步失敗時的狀態。rename 之前：沒有 `fmp.db`、
// 沒有暫存檔、舊檔不變；寫憑證失敗：`fmp.db` 在，該平台載入後是未登入，secure storage 沒有殘留。

final class _FakeReader implements LegacyCredentialReader {
  _FakeReader(this.reads);

  final Map<String, LegacyCredentialRead> reads;

  @override
  Future<Map<String, LegacyCredentialRead>> read(List<String> keys) async =>
      reads;
}

/// 在指定的步驟拋 [LegacyImportFailed]、其餘交給真的實作的 [LegacyImport]。
final class _FailingImport implements LegacyImport {
  _FailingImport(this._inner, {this.failAt, this.credentialsThrow = false});

  final LegacyImport _inner;
  final LegacyImportStep? failAt;
  final bool credentialsThrow;

  @override
  Future<LegacySource?> locate() => _inner.locate();

  @override
  Future<LegacyStaged> stage(
    LegacySource source, {
    void Function(LegacyImportStep step)? progress,
  }) {
    final failAt = this.failAt;
    if (failAt != null) {
      progress?.call(failAt);
      throw LegacyImportFailed(failAt, 'injected');
    }
    return _inner.stage(source, progress: progress);
  }

  @override
  Future<Set<String>> writeCredentials(
    LegacyStaged staged, {
    required Set<String> loggedInPluginIds,
  }) {
    if (credentialsThrow) throw StateError('injected');
    return _inner.writeCredentials(
      staged,
      loggedInPluginIds: loggedInPluginIds,
    );
  }
}

void main() {
  late Directory temp;
  late Directory legacyDirectory;
  late Directory dataDirectory;
  late File target;
  late Log log;
  late InMemorySecureStorage storage;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fmp_first_launch_test');
    addTearDown(() => temp.delete(recursive: true));
    legacyDirectory = Directory(p.join(temp.path, 'legacy'));
    dataDirectory = Directory(p.join(temp.path, 'data'))..createSync();
    target = File(p.join(dataDirectory.path, databaseFileName));
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
    storage = InMemorySecureStorage();
  });

  LegacyImporter realImporter() => LegacyImporter(
    dataDirectory: dataDirectory,
    log: log,
    locator: LegacyDataLocator(
      resolve: (_) async => LegacyLocations(
        databaseDirectories: [legacyDirectory],
        credentialReader: _FakeReader(
          legacyReads(
            bilibili: legacyBilibiliJson(),
            netease: legacyNeteaseJson(),
          ),
        ),
      ),
    ),
    secureStorage: storage,
    importOutputDevice: false,
  );

  Future<LegacySource> source() async =>
      (await realImporter().locate()) ?? (throw StateError('no legacy data'));

  List<String> stagingFiles() {
    final directory = Directory(
      p.join(dataDirectory.path, legacyImportDirectoryName),
    );
    return directory.existsSync()
        ? [for (final e in directory.listSync()) p.basename(e.path)]
        : const [];
  }

  Future<void> expectNothingLeft({
    required File legacy,
    required Object hash,
  }) async {
    expect(target.existsSync(), isFalse);
    expect(stagingFiles(), isEmpty);
    expect(sha256.convert(legacy.readAsBytesSync()), hash);
    expect(storage.values, isEmpty);
  }

  for (final step in [
    LegacyImportStep.read,
    LegacyImportStep.convert,
    LegacyImportStep.write,
    LegacyImportStep.verify,
  ]) {
    test('a failure in the ${step.name} step leaves nothing behind', () async {
      final legacy = await writeSyntheticLegacyDatabase(legacyDirectory);
      final hash = sha256.convert(legacy.readAsBytesSync());
      final failing = _FailingImport(realImporter(), failAt: step);

      await expectLater(
        importOnFirstLaunch(
          legacy: failing,
          source: await source(),
          target: target,
          log: log,
        ),
        throwsA(isA<LegacyImportFailed>().having((e) => e.step, 'step', step)),
      );
      await expectNothingLeft(legacy: legacy, hash: hash);
    });
  }

  test('a legacy file that cannot be read fails the read step', () async {
    legacyDirectory.createSync(recursive: true);
    final legacy = File(p.join(legacyDirectory.path, legacyDatabaseFileName))
      ..writeAsBytesSync(List.filled(64, 7));
    final hash = sha256.convert(legacy.readAsBytesSync());

    await expectLater(
      importOnFirstLaunch(
        legacy: realImporter(),
        source: await source(),
        target: target,
        log: log,
      ),
      throwsA(
        isA<LegacyImportFailed>().having(
          (e) => e.step,
          'step',
          LegacyImportStep.read,
        ),
      ),
    );
    await expectNothingLeft(legacy: legacy, hash: hash);
  });

  // 失敗頁的「重試」在同一個行程裡再跑一次（Isar 的實例名固定，上一次要已經關好）。
  test(
    'retrying after a read failure runs cleanly in the same process',
    () async {
      legacyDirectory.createSync(recursive: true);
      final bad = File(p.join(legacyDirectory.path, legacyDatabaseFileName))
        ..writeAsBytesSync(List.filled(64, 7));
      final importer = realImporter();
      final found = await source();

      await expectLater(
        importOnFirstLaunch(
          legacy: importer,
          source: found,
          target: target,
          log: log,
        ),
        throwsA(isA<LegacyImportFailed>()),
      );
      bad.deleteSync();
      await writeSyntheticLegacyDatabase(legacyDirectory);

      await importOnFirstLaunch(
        legacy: importer,
        source: found,
        target: target,
        log: log,
      );
      expect(target.existsSync(), isTrue);
      expect(stagingFiles(), isEmpty);
    },
  );

  test('a failed rename deletes the staging file and writes nothing', () async {
    final legacy = await writeSyntheticLegacyDatabase(legacyDirectory);
    final hash = sha256.convert(legacy.readAsBytesSync());
    // 目標位置被一個目錄佔住：改名一定失敗。
    Directory(target.path).createSync();
    final steps = <LegacyImportStep>[];

    await expectLater(
      importOnFirstLaunch(
        legacy: realImporter(),
        source: await source(),
        target: target,
        log: log,
        progress: steps.add,
      ),
      throwsA(
        isA<LegacyImportFailed>().having(
          (e) => e.step,
          'step',
          LegacyImportStep.swap,
        ),
      ),
    );
    expect(steps.last, LegacyImportStep.swap);
    expect(FileSystemEntity.isDirectorySync(target.path), isTrue);
    expect(stagingFiles(), isEmpty);
    expect(sha256.convert(legacy.readAsBytesSync()), hash);
    expect(storage.values, isEmpty);
  });

  test('an existing database is never replaced', () async {
    await writeSyntheticLegacyDatabase(legacyDirectory);
    target.writeAsStringSync('existing');

    await expectLater(
      importOnFirstLaunch(
        legacy: realImporter(),
        source: await source(),
        target: target,
        log: log,
      ),
      throwsA(isA<LegacyImportFailed>()),
    );
    expect(target.readAsStringSync(), 'existing');
    expect(stagingFiles(), isEmpty);
    expect(storage.values, isEmpty);
  });

  test('success moves the staging database into place, then writes the '
      'credentials', () async {
    final legacy = await writeSyntheticLegacyDatabase(legacyDirectory);
    final hash = sha256.convert(legacy.readAsBytesSync());
    final steps = <LegacyImportStep>[];
    ImportSummary? summary;

    final imported = await importOnFirstLaunch(
      legacy: realImporter(),
      source: await source(),
      target: target,
      log: log,
      progress: steps.add,
      onStaged: (value) => summary = value,
    );

    expect(steps, [
      LegacyImportStep.read,
      LegacyImportStep.convert,
      LegacyImportStep.write,
      LegacyImportStep.verify,
      LegacyImportStep.swap,
      LegacyImportStep.credentials,
    ]);
    expect(imported.failedCredentials, isEmpty);
    expect(summary, isNotNull);
    expect(target.existsSync(), isTrue);
    expect(stagingFiles(), isEmpty);
    expect(storage.values.keys, {
      'credentials.bilibili',
      'credentials.netease',
    });
    expect(sha256.convert(legacy.readAsBytesSync()), hash);
  });

  for (final throwing in [false, true]) {
    test(
      'a credential write failure (${throwing ? 'thrown' : 'reported'}) keeps '
      'the database and loads as signed out without leftovers',
      () async {
        await writeSyntheticLegacyDatabase(legacyDirectory);
        final real = realImporter();
        final legacy = _FailingImport(real, credentialsThrow: throwing);
        storage.writeError = StateError('keystore locked');

        final imported = await importOnFirstLaunch(
          legacy: legacy,
          source: await source(),
          target: target,
          log: log,
        );

        expect(imported.failedCredentials, {'bilibili', 'netease'});
        expect(target.existsSync(), isTrue);
        expect(storage.values, isEmpty);

        // 載入時沒有憑證的帳號列被刪掉：結果是未登入，沒有孤兒的 cookie。
        storage.writeError = null;
        final database = AppDatabase(NativeDatabase(target));
        addTearDown(database.close);
        final accounts = AccountRepository(database);
        expect(await accounts.byId('bilibili'), isNotNull);
        final store = CredentialStore(
          storage: storage,
          accounts: accounts,
          plugins: PluginRepository(database),
          settings: SourceSettingsRepository(database),
          redactor: Redactor(),
          log: log,
        );
        addTearDown(store.dispose);
        await store.ready;
        for (final id in ['bilibili', 'netease']) {
          expect(await store.state(id), CredentialState.none, reason: id);
          expect(await accounts.byId(id), isNull, reason: id);
        }
        expect(storage.values, isEmpty);
      },
    );
  }

  test('an existing fmp.db (also after starting with empty data) is never '
      'imported over', () async {
    expect(needsFirstLaunchImport(dataDirectory), isTrue);
    // 「以空白資料啟動」就是照常開庫，會建出 fmp.db。
    final database = await openAppDatabase(dataDirectory);
    await database.close();
    expect(target.existsSync(), isTrue);
    expect(needsFirstLaunchImport(dataDirectory), isFalse);
  });
}
