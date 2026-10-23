import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/data/import/legacy_imports_repository.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/legacy_import/legacy_database_reader.dart';
import 'package:fmp/legacy_import/legacy_importer.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';
import 'package:path/path.dart' as p;

import '../support/credentials.dart';
import '../support/legacy_database.dart';
import '../support/memory_database.dart';
import 'legacy_credential_fixtures.dart';

// `LegacyImporter`（M5 design §3.1）：以合成的舊庫走一遍 stage，核對步驟順序、暫存檔、
// 舊檔不變，與每一步失敗時的狀態。全是假值。

final class _FakeReader implements LegacyCredentialReader {
  _FakeReader(this.reads);

  final Map<String, LegacyCredentialRead> reads;

  @override
  Future<Map<String, LegacyCredentialRead>> read(List<String> keys) async =>
      reads;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory temp;
  late Directory legacyDirectory;
  late Directory dataDirectory;
  late Log log;
  late InMemorySecureStorage storage;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fmp_legacy_importer_test');
    addTearDown(() => temp.delete(recursive: true));
    legacyDirectory = Directory(p.join(temp.path, 'legacy'));
    dataDirectory = Directory(p.join(temp.path, 'data'))..createSync();
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
    storage = InMemorySecureStorage();
  });

  LegacyImporter importer({Map<String, LegacyCredentialRead>? reads}) =>
      LegacyImporter(
        dataDirectory: dataDirectory,
        log: log,
        locator: LegacyDataLocator(
          resolve: (_) async => LegacyLocations(
            databaseDirectories: [legacyDirectory],
            credentialReader: _FakeReader(
              reads ??
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

  List<String> leftovers() => dataDirectory.existsSync()
      ? [
          for (final entity in Directory(
            p.join(dataDirectory.path, legacyImportDirectoryName),
          ).listSync(recursive: true))
            p.basename(entity.path),
        ]
      : const [];

  test('locate finds the legacy database file and nothing otherwise', () async {
    expect(await importer().locate(), isNull);
    await writeSyntheticLegacyDatabase(legacyDirectory);
    final source = await importer().locate();
    expect(
      source?.database.path,
      p.join(legacyDirectory.path, legacyDatabaseFileName),
    );
  });

  test('the locator and the reader agree on the file name', () {
    expect(legacyDatabaseFile, legacyDatabaseFileName);
  });

  test('stage reports each step, leaves one verified staging file and does not '
      'touch the legacy file', () async {
    final database = await writeSyntheticLegacyDatabase(legacyDirectory);
    final before = sha256.convert(database.readAsBytesSync());
    final modified = database.statSync().modified;
    final steps = <LegacyImportStep>[];

    final staged = await importer().stage(
      (await importer().locate())!,
      progress: steps.add,
    );

    expect(steps, [
      LegacyImportStep.read,
      LegacyImportStep.convert,
      LegacyImportStep.write,
      LegacyImportStep.verify,
    ]);
    expect(staged.file.existsSync(), isTrue);
    expect(p.dirname(staged.file.path), endsWith(legacyImportDirectoryName));
    // 讀取器的工作目錄已刪，只剩暫存庫。
    expect(leftovers(), [p.basename(staged.file.path)]);
    expect(staged.credentials.keys, containsAll(['bilibili', 'netease']));
    expect(staged.summary.collections, isNotEmpty);
    expect(sha256.convert(database.readAsBytesSync()), before);
    expect(database.statSync().modified, modified);

    // 暫存庫是完整的 App 資料庫，帶著一列沒看過的匯入紀錄。
    final staging = AppDatabase(NativeDatabase(staged.file));
    addTearDown(staging.close);
    final record = await LegacyImportsRepository(staging)
        .latestUnacknowledged();
    expect(record, isNotNull);
    expect(record!.summary, staged.summary);
  });

  test('a legacy file that cannot be read fails the read step', () async {
    legacyDirectory.createSync(recursive: true);
    File(p.join(legacyDirectory.path, legacyDatabaseFileName))
        .writeAsBytesSync(List.filled(64, 7));
    final instance = importer();

    await expectLater(
      instance.stage((await instance.locate())!),
      throwsA(
        isA<LegacyImportFailed>().having(
          (e) => e.step,
          'step',
          LegacyImportStep.read,
        ),
      ),
    );
    expect(leftovers(), isEmpty);
  });

  test('writeCredentials writes the platforms that are not signed in and '
      'reports the ones that fail', () async {
    await writeSyntheticLegacyDatabase(legacyDirectory);
    final instance = importer();
    final staged = await instance.stage((await instance.locate())!);

    // 這台已登入的平台不覆寫。
    expect(
      await instance.writeCredentials(staged, loggedInPluginIds: {'netease'}),
      isEmpty,
    );
    expect(storage.values.keys, {'credentials.bilibili'});

    // 寫入失敗：回報插件 id，log 沒有憑證的值。
    storage.writeError = StateError('FAKE_SESSDATA_123 keystore locked');
    expect(
      await instance.writeCredentials(staged, loggedInPluginIds: const {}),
      {'bilibili', 'netease'},
    );
    for (final record in log.history) {
      expect(record.toString(), isNot(contains('FAKE_')));
      expect(record.message, isNot(contains('FAKE_')));
    }
  });

  group('settings page (replacing the current database)', () {
    Uint8List backupBytes() => Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': 5,
          'exportedAt': '2026-09-20T00:00:00.000',
          'playlists': [
            {
              'name': 'From backup',
              'trackKeys': ['youtube:ytA', 'youtube:gone'],
              'createdAt': '2026-01-01T00:00:00.000',
            },
          ],
          'tracks': [
            {
              'sourceId': 'ytA',
              'sourceType': 'youtube',
              'title': 'Video A',
              'createdAt': '2026-01-01T00:00:00.000',
            },
          ],
          'settings': {'themeModeIndex': 2},
        }),
      ),
    );

    test('stageBackup stages a fresh database from a JSON backup', () async {
      final steps = <LegacyImportStep>[];
      final staged = await importer().stageBackup(
        backupBytes(),
        progress: steps.add,
      );

      expect(steps, [
        LegacyImportStep.read,
        LegacyImportStep.convert,
        LegacyImportStep.write,
        LegacyImportStep.verify,
      ]);
      expect(staged.credentials, isEmpty);
      expect(staged.keptAccountPluginIds, isEmpty);
      final entries = staged.summary.collections['playlistEntries']!;
      expect((entries.read, entries.written), (2, 1));
      expect(entries.skipped, {'danglingTrackId': 1});

      final staging = AppDatabase(NativeDatabase(staged.file));
      addTearDown(staging.close);
      final record = (await LegacyImportsRepository(staging)
          .latestUnacknowledged())!;
      expect(record.source, LegacyImportSource.backup);
      expect(record.backupVersion, 5);
      // 備份沒有佇列。
      final queue = await staging
          .customSelect('SELECT COUNT(*) AS n FROM queue_entries')
          .getSingle();
      expect(queue.read<int>('n'), 0);
    });

    test('a backup that cannot be imported is rejected as it is', () async {
      await expectLater(
        importer().stageBackup(Uint8List.fromList(utf8.encode('{}'))),
        throwsA(isA<LegacyBackupRejected>()),
      );
      await expectLater(
        importer().stageBackup(
          Uint8List.fromList(
            utf8.encode('{"version": 9, "exportedAt": "2030-01-01T00:00:00"}'),
          ),
        ),
        throwsA(
          isA<LegacyBackupRejected>().having(
            (e) => e.reason,
            'reason',
            LegacyBackupRejection.newerVersion,
          ),
        ),
      );
      // 被拒絕的備份沒有留下暫存檔。
      expect(
        Directory(p.join(dataDirectory.path, legacyImportDirectoryName))
            .existsSync(),
        isFalse,
      );
    });

    test('stage with replacing replaces an invalidated account and writes '
        'its credentials', () async {
      await writeSyntheticLegacyDatabase(legacyDirectory);
      final current = memoryDatabase();
      await AccountRepository(current).upsert(
        Account(
          pluginId: 'bilibili',
          userId: 'mine',
          displayName: 'This device',
          status: AccountStatus.invalidated,
          loggedInAt: DateTime.utc(2026),
        ),
      );
      final instance = importer();

      final staged = await instance.stage(
        (await instance.locate())!,
        replacing: current,
      );

      expect(staged.keptAccountPluginIds, isEmpty);
      final staging = AppDatabase(NativeDatabase(staged.file));
      addTearDown(staging.close);
      final accounts = {
        for (final a in await AccountRepository(staging).list()) a.pluginId: a,
      };
      expect(accounts['bilibili']!.userId, isNot('mine'));
      expect(accounts['bilibili']!.status, AccountStatus.active);

      await instance.writeCredentials(
        staged,
        loggedInPluginIds: staged.keptAccountPluginIds,
      );
      expect(storage.values.keys, {
        'credentials.bilibili',
        'credentials.netease',
      });
    });

    test('stage with replacing keeps this device\'s account and its '
        'credential is not written', () async {
      await writeSyntheticLegacyDatabase(legacyDirectory);
      final current = memoryDatabase();
      await AccountRepository(current).upsert(
        Account(
          pluginId: 'bilibili',
          userId: 'mine',
          displayName: 'This device',
          status: AccountStatus.active,
          loggedInAt: DateTime.utc(2026),
        ),
      );
      await PlaylistRepository(current).create(name: 'Old list');
      final instance = importer();

      final staged = await instance.stage(
        (await instance.locate())!,
        replacing: current,
      );

      expect(staged.keptAccountPluginIds, {'bilibili'});
      expect(staged.summary.reloginPlatforms, isNot(contains('bilibili')));
      final staging = AppDatabase(NativeDatabase(staged.file));
      addTearDown(staging.close);
      final accounts = await AccountRepository(staging).list();
      expect(
        {for (final a in accounts) a.pluginId: a.userId}['bilibili'],
        'mine',
      );
      final names = [
        for (final o in await PlaylistRepository(staging).overviews())
          o.playlist.name,
      ];
      expect(names, isNot(contains('Old list')));

      await instance.writeCredentials(
        staged,
        loggedInPluginIds: staged.keptAccountPluginIds,
      );
      expect(storage.values.keys, {'credentials.netease'});
      // 目前的資料庫沒被動過。
      expect(
        [
          for (final o in await PlaylistRepository(current).overviews())
            o.playlist.name,
        ],
        ['Old list'],
      );
    });
  });

  test('cleanLegacyImportLeftovers removes work directories and staging '
      'files', () async {
    final root = Directory(
      p.join(dataDirectory.path, legacyImportDirectoryName),
    )..createSync();
    Directory(p.join(root.path, 'work-1')).createSync();
    File(p.join(root.path, 'work-1', 'fmp_database.isar'))
        .writeAsStringSync('');
    File(p.join(root.path, 'staging-1.db')).writeAsStringSync('');

    expect(await cleanLegacyImportLeftovers(dataDirectory, log), 2);
    expect(root.listSync(), isEmpty);
    // 沒有目錄時什麼都不做。
    root.deleteSync();
    expect(await cleanLegacyImportLeftovers(dataDirectory, log), 0);
  });
}
