import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/import/import_bundle.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/data/import/legacy_imports_repository.dart';
import 'package:fmp/data/import/staging_import.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'import_fixtures.dart';

// 暫存庫的寫入與驗證（M5 design §6.1、§6.2、§9「暫存庫」「中途失敗」）。一律用真的檔案資料庫：
// 要驗的是檔案本身，以及失敗後檔案不在。

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late File staging;
  late Log log;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('fmp_staging_');
    staging = File(p.join(directory.path, 'legacy-import', 'staging-test.db'));
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.warning);
    // 刪得掉也證明暫存庫關閉後檔案沒被佔住（Windows 上開著的檔案刪不掉）。
    addTearDown(() => directory.deleteSync(recursive: true));
  });

  StagingImport stager({int seed = 1}) =>
      StagingImport(log, random: Random(seed));

  Future<AppDatabase> open() async {
    final database = AppDatabase(NativeDatabase(staging));
    addTearDown(database.close);
    return database;
  }

  /// 用原始 sqlite 改暫存檔（外鍵檢查預設關閉，才寫得進違規的資料）。
  void tamper(void Function(sqlite.Database raw) change) {
    final raw = sqlite.sqlite3.open(staging.path);
    try {
      change(raw);
    } finally {
      raw.close();
    }
  }

  void expectNoStagingFiles() {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      expect(
        File('${staging.path}$suffix').existsSync(),
        isFalse,
        reason: 'staging$suffix',
      );
    }
  }

  Future<void> expectFailure(
    Future<void> Function() action,
    LegacyImportStep step,
  ) async {
    await expectLater(
      action,
      throwsA(
        isA<LegacyImportFailed>()
            .having((e) => e.step, 'step', step)
            .having((e) => e.reason, 'reason', isNotEmpty),
      ),
    );
    expectNoStagingFiles();
  }

  group('write', () {
    test('writes the whole bundle with the original timestamps', () async {
      await stager().write(fullBundle(), staging, importedAt: importedAt);

      final database = await open();
      final bundle = fullBundle();

      // 曲目：顯示資料原樣；updated_at 是匯入時間。
      final tracks = TracksRepository(database);
      final found = await tracks.find([
        for (final t in bundle.tracks) '${t.key}',
      ]);
      expect(found.values, unorderedEquals(bundle.tracks));
      final updated = await database
          .customSelect('SELECT DISTINCT updated_at AS u FROM tracks')
          .get();
      expect(
        [for (final row in updated) row.read<int>('u')],
        [importedAt.millisecondsSinceEpoch],
      );

      // 歌單：順序、sort_order、原始時間、項目順序與 unavailable、遠端欄位。
      final playlists = PlaylistRepository(database);
      final overviews = await playlists.overviews();
      expect(
        [for (final o in overviews) o.playlist.name],
        ['Local list', 'Imported list', 'Mix list'],
      );
      expect([for (final o in overviews) o.playlist.sortOrder], [0, 1, 2]);
      expect(overviews[0].playlist.createdAt, at(1));
      expect(overviews[0].playlist.updatedAt, at(2));
      expect(overviews[1].playlist.kind, PlaylistKind.imported);
      expect(overviews[2].playlist.mixSeedSourceId, 'dQw4w9WgXcQ');

      final local = await playlists.entries(overviews[0].playlist.id);
      expect(
        [for (final e in local) e.track.sourceId],
        ['BV1b', 'BV1a', 'BV1b'],
      );
      expect([for (final e in local) e.position], [0, 1, 2]);
      final imported = await playlists.entries(overviews[1].playlist.id);
      expect([for (final e in imported) e.unavailable], [false, true]);
      expect([for (final e in imported) e.remoteItemId], [null, null]);

      final remote = (await playlists.remote(overviews[1].playlist.id))!;
      expect(remote.pluginId, 'bilibili');
      expect(remote.remoteId, '12345');
      expect(remote.ownerName, 'Owner');
      expect(remote.writable, isTrue);
      expect(remote.artworkOverridden, isTrue);
      expect(remote.nameOverridden, isFalse);
      expect(remote.refreshIntervalHours, 48);
      expect(remote.lastRefreshedAt, at(5));
      expect(remote.lastResult, isNull);
      expect(remote.status, PlaylistRemoteStatus.active);

      // 佇列與播放狀態。
      final queue = QueueRepository(database);
      final stored = await queue.readQueue();
      expect(
        [for (final t in stored.entries) t.sourceId],
        ['dQw4w9WgXcQ', 'BV1a'],
      );
      expect(stored.shuffleRanks, [1, 0]);
      expect(await queue.readPlayerState(), bundle.playerState);

      // 歷史：原始的 played_at，新的在前。
      final history = await PlayHistoryRepository(database).page(limit: 10);
      expect([for (final h in history) h.playedAt], [at(12), at(11), at(10)]);

      // 電台。
      final stations = await RadioRepository(database).list();
      expect([for (final s in stations) s.roomId], ['99', 'live1']);
      expect([for (final s in stations) s.addedAt], [at(20), at(21)]);
      expect(stations[0].liveStatus, isNull);

      // 其他表。
      Future<int> count(String table) async =>
          (await database
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n');
      expect(await count('track_origins'), 1);
      expect(await count('accounts'), 1);
      expect(await count('source_settings'), 2);
      expect(await count('chart_settings'), 0);
      expect(await count('installed_plugins'), 0);
      final settings = await database
          .customSelect(
            'SELECT plugin_id, browse_as_logged_in AS b FROM source_settings '
            'ORDER BY plugin_id',
          )
          .get();
      expect([for (final row in settings) row.read<int>('b')], [1, 0]);
      expect(
        await AppearanceSettingsRepository(database).read(),
        bundle.appearance,
      );
      expect(await NetworkSettingsRepository(database).read(), bundle.network);
      expect(
        await PlaybackSettingsRepository(database).read(),
        bundle.playback,
      );
      expect(await LayoutStateRepository(database).read(), bundle.layout);

      // 資料庫是目前版本的新庫。
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), database.schemaVersion);
    });

    test('writes the import record and the legacy playlist ids', () async {
      await stager().write(fullBundle(), staging, importedAt: importedAt);

      final database = await open();
      final record = (await LegacyImportsRepository(database)
          .latestUnacknowledged())!;
      expect(record.source, LegacyImportSource.database);
      expect(record.importedAt, importedAt);
      expect(record.legacySchemaVersion, 4);
      expect(record.backupVersion, isNull);
      expect(record.summary, fullBundle().record.summary);
      expect(record.acknowledged, isFalse);

      // 舊歌單 id 對到新歌單 id（依名稱找，不靠 id 的數字）。
      final rows = await database
          .customSelect(
            'SELECT m.legacy_import_id AS import_id, m.legacy_playlist_id AS legacy, '
            'p.name AS name FROM legacy_playlist_ids m '
            'JOIN playlists p ON p.id = m.playlist_id ORDER BY m.legacy_playlist_id',
          )
          .get();
      expect(
        [
          for (final row in rows)
            (row.read<int>('legacy'), row.read<String>('name')),
        ],
        [(3, 'Imported list'), (7, 'Local list'), (9, 'Mix list')],
      );
      expect({for (final row in rows) row.read<int>('import_id')}, {record.id});
    });

    test('stored format', () async {
      await stager().write(fullBundle(), staging, importedAt: importedAt);

      final database = await open();
      final row = await database
          .customSelect(
            'SELECT source, imported_at, legacy_schema_version, backup_version, '
            'summary_json, acknowledged FROM legacy_imports',
          )
          .getSingle();
      expect(row.data, {
        'source': 'database',
        'imported_at': 1792744200000,
        'legacy_schema_version': 4,
        'backup_version': null,
        'summary_json':
            '{"collections":{"tracks":{"read":10,"written":8,'
            '"skipped":{"duplicateTrack":1,"unreferenced":1}}},'
            '"unimportedSettings":["themeColor"],"reloginPlatforms":["netease"]}',
        'acknowledged': 0,
      });
    });

    test('an empty bundle writes only the record', () async {
      await stager().write(
        ImportBundle(record: record(source: LegacyImportSource.backup)),
        staging,
        importedAt: importedAt,
      );

      final database = await open();
      final record0 = (await LegacyImportsRepository(database)
          .latestUnacknowledged())!;
      expect(record0.source, LegacyImportSource.backup);
      expect(record0.backupVersion, 5);
      expect(record0.legacySchemaVersion, isNull);
      for (final table in database.allTables) {
        final name = table.actualTableName;
        final n =
            (await database
                    .customSelect('SELECT COUNT(*) AS n FROM $name')
                    .getSingle())
                .read<int>('n');
        expect(n, name == 'legacy_imports' ? 1 : 0, reason: name);
      }
    });

    test('replaces a leftover file at the staging path', () async {
      await staging.parent.create(recursive: true);
      await staging.writeAsString('not a database');
      await File('${staging.path}-wal').writeAsString('leftover');

      await stager().write(fullBundle(), staging, importedAt: importedAt);

      expect(File('${staging.path}-wal').existsSync(), isFalse);
      await stager().verify(fullBundle(), staging);
    });

    test(
      'a reference to a track that is not in the bundle fails the write',
      () async {
        final bundle = fullBundle();
        final broken = ImportBundle(
          record: bundle.record,
          tracks: bundle.tracks,
          playlists: bundle.playlists,
          queue: [
            ...bundle.queue,
            ImportQueueEntry(track: track('missing').key),
          ],
          playerState: bundle.playerState,
        );

        await expectFailure(
          () => stager().write(broken, staging, importedAt: importedAt),
          LegacyImportStep.write,
        );
      },
    );

    test('a duplicate track key fails the write halfway', () async {
      final bundle = fullBundle();
      final broken = ImportBundle(
        record: bundle.record,
        tracks: [...bundle.tracks, bundle.tracks.first],
        playlists: bundle.playlists,
      );

      await expectFailure(
        () => stager().write(broken, staging, importedAt: importedAt),
        LegacyImportStep.write,
      );
    });

    test('a mix playlist without a seed fails the write', () async {
      final broken = ImportBundle(
        record: record(),
        playlists: [
          ImportPlaylist(
            kind: PlaylistKind.mix,
            name: 'Broken mix',
            createdAt: at(1),
            updatedAt: at(1),
          ),
        ],
      );

      await expectFailure(
        () => stager().write(broken, staging, importedAt: importedAt),
        LegacyImportStep.write,
      );
    });

    test('the failure reason carries no user data', () async {
      final bundle = fullBundle();
      final broken = ImportBundle(
        record: bundle.record,
        tracks: [...bundle.tracks, bundle.tracks.first],
      );

      try {
        await stager().write(broken, staging, importedAt: importedAt);
        fail('expected a failure');
      } on LegacyImportFailed catch (error) {
        expect('$error', isNot(contains('Song')));
        expect('$error', isNot(contains('BV1a')));
      }
    });
  });

  group('verify', () {
    Future<void> writeFull() =>
        stager().write(fullBundle(), staging, importedAt: importedAt);

    test('passes on what write produced and keeps the file', () async {
      await writeFull();

      await stager().verify(fullBundle(), staging);

      expect(staging.existsSync(), isTrue);
      // 驗證不改檔案：還能再驗一次。
      await stager().verify(fullBundle(), staging);
    });

    test('rejects a row count that differs from the bundle', () async {
      await writeFull();
      tamper((raw) => raw.execute('DELETE FROM legacy_playlist_ids'));

      await expectFailure(
        () => stager().verify(fullBundle(), staging),
        LegacyImportStep.verify,
      );
    });

    test('rejects rows in a table the bundle does not write', () async {
      await writeFull();
      tamper(
        (raw) => raw.execute(
          "INSERT INTO chart_settings (plugin_id, chart_id) VALUES ('x', 'y')",
        ),
      );

      await expectLater(
        stager().verify(fullBundle(), staging),
        throwsA(
          isA<LegacyImportFailed>().having(
            (e) => e.reason,
            'reason',
            contains('chart_settings'),
          ),
        ),
      );
      expectNoStagingFiles();
    });

    test('rejects a sampled track that was changed', () async {
      await writeFull();
      tamper((raw) => raw.execute("UPDATE tracks SET title = 'Changed'"));

      await expectFailure(
        () => stager().verify(fullBundle(), staging),
        LegacyImportStep.verify,
      );
    });

    test('rejects a playlist entry order that was changed', () async {
      await writeFull();
      tamper(
        (raw) => raw.execute(
          'UPDATE playlist_entries SET position = 5 - position '
          'WHERE playlist_id = (SELECT MIN(id) FROM playlists)',
        ),
      );

      await expectFailure(
        () => stager().verify(fullBundle(), staging),
        LegacyImportStep.verify,
      );
    });

    test('rejects a history time that was changed', () async {
      await writeFull();
      tamper((raw) => raw.execute('UPDATE play_history SET played_at = 1'));

      await expectFailure(
        () => stager().verify(fullBundle(), staging),
        LegacyImportStep.verify,
      );
    });

    test('rejects a radio station that was changed', () async {
      await writeFull();
      tamper((raw) => raw.execute("UPDATE radio_stations SET title = 'x'"));

      await expectFailure(
        () => stager().verify(fullBundle(), staging),
        LegacyImportStep.verify,
      );
    });

    test('rejects a change to the parts compared in full', () async {
      // 佇列、播放狀態、匯入紀錄、遠端欄位與項目旗標：筆數不變，只有內容比對看得到。
      final cases = <String, String>{
        'queue rank':
            'UPDATE queue_entries SET shuffle_rank = 5 '
            'WHERE position = 0',
        'queue order':
            "UPDATE queue_entries SET track_key = (SELECT track_key FROM "
            "tracks WHERE source_id = 'BV1b') WHERE position = 0",
        'player state': 'UPDATE player_state SET volume = 0.25',
        'mix cursor': "UPDATE player_state SET mix_cursor = 'c'",
        'record summary':
            "UPDATE legacy_imports SET summary_json = "
            '\'{"collections":{},"unimportedSettings":[],'
            '"reloginPlatforms":[]}\'',
        'record version': 'UPDATE legacy_imports SET legacy_schema_version = 3',
        'remote owner': "UPDATE playlist_remote SET owner_name = 'x'",
        'remote generation':
            'UPDATE playlist_remote SET refresh_generation = 1',
        'entry unavailable':
            'UPDATE playlist_entries SET unavailable = 1 '
            'WHERE unavailable = 0',
        'mix seed':
            "UPDATE playlists SET mix_seed_source_id = 'other' "
            "WHERE kind = 'mix'",
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        await writeFull();
        tamper((raw) => raw.execute(value));

        await expectLater(
          stager().verify(fullBundle(), staging),
          throwsA(
            isA<LegacyImportFailed>().having(
              (e) => e.step,
              'step',
              LegacyImportStep.verify,
            ),
          ),
          reason: key,
        );
        expectNoStagingFiles();
      }
    });

    test('rejects a foreign key violation nothing else notices', () async {
      await writeFull();
      // legacy_playlist_ids 不在抽樣裡，筆數不變；只有外鍵檢查看得到。
      tamper(
        (raw) =>
            raw.execute('UPDATE legacy_playlist_ids SET playlist_id = 999'),
      );

      await expectLater(
        stager().verify(fullBundle(), staging),
        throwsA(
          isA<LegacyImportFailed>().having(
            (e) => e.reason,
            'reason',
            contains('foreign key'),
          ),
        ),
      );
      expectNoStagingFiles();
    });

    test('rejects an orphan track', () async {
      final bundle = fullBundle();
      final withOrphan = ImportBundle(
        record: bundle.record,
        tracks: [...bundle.tracks, track('nobody-uses-me')],
        playlists: bundle.playlists,
      );
      await stager().write(withOrphan, staging, importedAt: importedAt);

      await expectLater(
        stager().verify(withOrphan, staging),
        throwsA(
          isA<LegacyImportFailed>().having(
            (e) => e.reason,
            'reason',
            contains('orphan'),
          ),
        ),
      );
      expectNoStagingFiles();
    });

    test('rejects a file that is not a database', () async {
      await staging.parent.create(recursive: true);
      await staging.writeAsBytes(List.filled(4096, 7));

      await expectFailure(
        () => stager().verify(fullBundle(), staging),
        LegacyImportStep.verify,
      );
    });

    test('removes the -wal and -shm files along with the database', () async {
      await writeFull();
      tamper((raw) => raw.execute("UPDATE tracks SET title = 'Changed'"));
      await File('${staging.path}-wal').writeAsBytes(const []);
      await File('${staging.path}-shm').writeAsBytes(const []);

      await expectFailure(
        () => stager().verify(fullBundle(), staging),
        LegacyImportStep.verify,
      );
    });

    group('sampling', () {
      // 兩百首曲目與歷史、六十張歌單：超過每種抽的 50 筆。
      ImportBundle large() {
        final tracks = [for (var i = 0; i < 200; i++) track('T$i')];
        return ImportBundle(
          record: record(),
          tracks: tracks,
          playlists: [
            for (var i = 0; i < 60; i++)
              ImportPlaylist(
                kind: PlaylistKind.local,
                name: 'List $i',
                createdAt: at(i),
                updatedAt: at(i),
                entries: [
                  for (var j = 0; j < 4; j++)
                    ImportPlaylistEntry(track: tracks[(i + j) % 200].key),
                ],
              ),
          ],
          history: [
            for (var i = 0; i < 200; i++)
              ImportHistoryEntry(
                track: tracks[i].key,
                // 每三筆共用一個時間，順序要靠 id 分。
                playedAt: at(i ~/ 3),
              ),
          ],
          radioStations: [
            for (var i = 0; i < 60; i++)
              ImportRadioStation(
                pluginId: 'bilibili',
                roomId: 'room$i',
                title: 'Room $i',
                addedAt: at(i),
              ),
          ],
        );
      }

      test('passes on a bundle larger than the sample', () async {
        final bundle = large();
        await stager().write(bundle, staging, importedAt: importedAt);

        await stager().verify(bundle, staging);
      });

      test('catches a change to every row of a large collection', () async {
        // 不論抽到哪幾筆都會碰到被改的列：證明抽樣真的比對了內容。
        final cases = <String, String>{
          'tracks': "UPDATE tracks SET uploader = 'x'",
          'playlists': "UPDATE playlists SET name = name || 'x'",
          'history': 'UPDATE play_history SET played_at = played_at + 1',
          'radio': "UPDATE radio_stations SET title = 'x'",
        };
        for (final MapEntry(:key, :value) in cases.entries) {
          final bundle = large();
          await stager().write(bundle, staging, importedAt: importedAt);
          tamper((raw) => raw.execute(value));

          await expectLater(
            stager().verify(bundle, staging),
            throwsA(isA<LegacyImportFailed>()),
            reason: key,
          );
          expectNoStagingFiles();
        }
      });

      test('samples with the injected random', () async {
        // 兩百個電台只改一個：抽 50 筆約四分之一的機會抽到它。種子固定，所以結果固定；
        // 抽到的種子紅、沒抽到的綠，兩種都出現才證明是隨機數決定抽哪幾筆。
        final bundle = ImportBundle(
          record: record(),
          radioStations: [
            for (var i = 0; i < 200; i++)
              ImportRadioStation(
                pluginId: 'bilibili',
                roomId: 'room$i',
                title: 'Room $i',
                addedAt: at(i),
              ),
          ],
        );
        Future<bool> passes(int seed) async {
          await stager().write(bundle, staging, importedAt: importedAt);
          tamper(
            (raw) => raw.execute(
              "UPDATE radio_stations SET title = 'x' WHERE room_id = 'room17'",
            ),
          );
          try {
            await stager(seed: seed).verify(bundle, staging);
            return true;
          } on LegacyImportFailed {
            return false;
          }
        }

        final outcomes = [
          for (var seed = 1; seed <= 12; seed++) await passes(seed),
        ];
        expect(outcomes, contains(true));
        expect(outcomes, contains(false));
        expect([
          for (var seed = 1; seed <= 12; seed++) await passes(seed),
        ], outcomes);
      });
    });
  });

  test('ten thousand history entries and queue entries', () async {
    // 量一次寫進回報，不斷言時間（機器快慢不同）。
    final tracks = [for (var i = 0; i < 10000; i++) track('BV$i')];
    final bundle = ImportBundle(
      record: record(),
      tracks: tracks,
      queue: [
        for (final (index, t) in tracks.indexed)
          ImportQueueEntry(track: t.key, shuffleRank: index),
      ],
      playerState: const PlayerState(
        currentPosition: 0,
        position: Duration.zero,
        loopMode: LoopMode.off,
        shuffleEnabled: true,
        volume: 1,
        muted: false,
      ),
      history: [
        for (final (index, t) in tracks.indexed)
          ImportHistoryEntry(track: t.key, playedAt: at(index)),
      ],
    );

    final write = Stopwatch()..start();
    await stager().write(bundle, staging, importedAt: importedAt);
    write.stop();
    final verify = Stopwatch()..start();
    await stager().verify(bundle, staging);
    verify.stop();

    // ignore: avoid_print
    print(
      '10k history + 10k queue + 10k tracks: write ${write.elapsedMilliseconds} ms, '
      'verify ${verify.elapsedMilliseconds} ms',
    );
    final database = await open();
    final stored = await PlayHistoryRepository(database).page(limit: 1);
    expect(stored.single.playedAt, at(9999));
  });
}
