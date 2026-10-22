import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/legacy_import/legacy_database_reader.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';
import 'package:path/path.dart' as p;

import '../support/legacy_database.dart';

void main() {
  late Directory temp;
  late Directory source;
  late Directory workRoot;
  late List<(String, Map<String, Object?>)> logs;
  late LegacyDatabaseReader reader;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fmp_legacy_reader_test');
    addTearDown(() => temp.delete(recursive: true));
    source = Directory(p.join(temp.path, 'source'));
    workRoot = Directory(p.join(temp.path, 'legacy-import'));
    logs = [];
    reader = LegacyDatabaseReader(
      log: (message, fields) => logs.add((message, fields)),
    );
  });

  Future<LegacySnapshot> readSynthetic({int? schemaVersion = 4}) async {
    final file = await writeSyntheticLegacyDatabase(
      source,
      schemaVersion: schemaVersion,
    );
    return reader.read(file, workRoot);
  }

  List<String> entries(Directory directory) => directory.existsSync()
      ? [
          for (final entity in directory.listSync(recursive: true))
            p.relative(entity.path, from: directory.path),
        ]
      : [];

  test(
    'the source file and directory are untouched; the work directory is gone',
    () async {
      final file = await writeSyntheticLegacyDatabase(source);
      final hashBefore = sha256.convert(file.readAsBytesSync());
      final modifiedBefore = file.lastModifiedSync();
      final listingBefore = entries(source)..sort();

      await reader.read(file, workRoot);

      expect(sha256.convert(file.readAsBytesSync()), hashBefore);
      expect(file.lastModifiedSync(), modifiedBefore);
      // 沒有新增 lock 檔或任何其他檔案。
      expect(entries(source)..sort(), listingBefore);
      expect(entries(workRoot), isEmpty);
    },
  );

  test('a database that cannot be opened fails at the open step and leaves no work directory', () async {
    // 太小的檔（約一頁以下）libmdbx 會當成新庫，所以用一個夠大的壞檔。
    await source.create(recursive: true);
    final broken = File(p.join(source.path, legacyDatabaseFileName))
      ..writeAsBytesSync(List.filled(100000, 7));

    await expectLater(
      reader.read(broken, workRoot),
      throwsA(
        isA<LegacyReadException>()
            .having((e) => e.step, 'step', LegacyReadStep.open)
            // 訊息只有步驟與原因型別，沒有路徑。
            .having(
              (e) => e.toString(),
              'message',
              allOf(contains('open'), isNot(contains(temp.path))),
            ),
      ),
    );
    expect(entries(workRoot), isEmpty);
    expect(broken.readAsBytesSync(), List.filled(100000, 7));
  });

  group('a copy without a settings row fails at the read step', () {
    // libmdbx 把太小的檔（實測 100、4096 位元組）當成新庫開，不報錯；舊 App 每次
    // 啟動都寫設定列，所以沒有設定列就不是可用的舊庫（app/AGENTS.md § 舊資料匯入）。
    for (final size in [100, 4096]) {
      test('a $size-byte file', () async {
        await source.create(recursive: true);
        final tiny = File(p.join(source.path, legacyDatabaseFileName))
          ..writeAsBytesSync(List.filled(size, 7));
        final listingBefore = entries(temp)..sort();

        await expectLater(
          reader.read(tiny, workRoot),
          throwsA(
            isA<LegacyReadException>().having(
              (e) => e.step,
              'step',
              LegacyReadStep.read,
            ),
          ),
        );
        expect(entries(workRoot), isEmpty);
        expect(tiny.readAsBytesSync(), List.filled(size, 7));
        // 開庫只寫工作目錄：工作目錄（已刪）以外沒有多出任何檔案。
        expect(
          entries(temp)..sort(),
          [...listingBefore, 'legacy-import']..sort(),
        );
      });
    }

    test('a real database with no settings row', () async {
      final file = await writeSyntheticLegacyDatabase(
        source,
        withSettings: false,
      );

      await expectLater(
        reader.read(file, workRoot),
        throwsA(
          isA<LegacyReadException>().having(
            (e) => e.step,
            'step',
            LegacyReadStep.read,
          ),
        ),
      );
      expect(entries(workRoot), isEmpty);
    });
  });

  test('a missing file fails at the copy step', () async {
    await expectLater(
      reader.read(File(p.join(source.path, 'missing.isar')), workRoot),
      throwsA(
        isA<LegacyReadException>().having(
          (e) => e.step,
          'step',
          LegacyReadStep.copy,
        ),
      ),
    );
    expect(entries(workRoot), isEmpty);
  });

  test('logs only the steps and the collection counts', () async {
    final snapshot = await readSynthetic();

    final counts = {
      for (final (message, fields) in logs)
        if (message == 'Legacy collection read')
          fields['collection']: fields['count'],
    };
    expect(counts, snapshot.counts);
    for (final (_, fields) in logs) {
      expect(
        fields.keys,
        anyOf(
          unorderedEquals(['step']),
          unorderedEquals(['collection', 'count']),
          isEmpty,
        ),
      );
      for (final value in fields.values) {
        expect('$value', isNot(contains(temp.path)));
        expect('$value', isNot(contains('Synthetic')));
      }
    }
  });

  group('reads every collection', () {
    late LegacySnapshot snapshot;
    setUp(() async => snapshot = await readSynthetic());

    test('counts', () {
      expect(snapshot.counts, {
        'Track': SyntheticLegacy.trackCount,
        'Playlist': SyntheticLegacy.playlistCount,
        'PlayQueue': 1,
        'PlayHistory': SyntheticLegacy.playHistoryCount,
        'Settings': 1,
        'SearchHistory': SyntheticLegacy.searchHistoryCount,
        'DownloadTask': SyntheticLegacy.downloadTaskCount,
        'RadioStation': SyntheticLegacy.radioStationCount,
        'LyricsMatch': SyntheticLegacy.lyricsMatchCount,
        'LyricsTitleParseCache': SyntheticLegacy.lyricsTitleParseCacheCount,
        'Account': SyntheticLegacy.accountCount,
      });
    });

    LegacyTrack track(int id) => snapshot.tracks.firstWhere((t) => t.id == id);

    test('tracks: Bilibili parts, single parts and duplicate keys', () {
      final p1 = track(SyntheticLegacy.multiPartOne);
      expect(p1.sourceType, 'bilibili');
      expect(p1.sourceId, 'BV1synthetic0001');
      expect(p1.cid, 1001);
      expect(p1.pageNum, 1);
      expect(p1.pageCount, 2);
      expect(p1.parentTitle, 'Synthetic Multi Part Video');
      expect(p1.ownerId, 1001);
      expect(p1.bilibiliAid, 777);
      expect(p1.durationMs, 180000);
      expect(p1.createdAt.toUtc(), SyntheticLegacy.baseTime);
      expect(p1.playlistInfo.single.playlistId, 1);
      expect(p1.playlistInfo.single.playlistName, 'Synthetic Local');
      expect(p1.playlistInfo.single.downloadPath, '');

      final noCid = track(SyntheticLegacy.singleNoCid);
      expect(noCid.cid, isNull);
      expect(noCid.pageCount, 1);
      expect(noCid.isAvailable, isFalse);
      expect(noCid.unavailableReason, 'synthetic reason');

      expect(track(SyntheticLegacy.singleWithCid).cid, 4004);
      expect(track(SyntheticLegacy.singleWithCid).isVip, isTrue);

      final netease = track(SyntheticLegacy.netease);
      expect(netease.originalSongId, '10001');
      expect(netease.playlistInfo.map((i) => i.playlistId), [1, 0]);
      expect(netease.playlistInfo.map((i) => i.downloadPath), [
        '/synthetic/music/Synthetic Local/10001_x/audio.m4a',
        '/synthetic/music/scanned/audio.m4a',
      ]);

      // 同一個曲目鍵在 DB 裡有兩列，讀取器不去重。
      final youtubeRows = snapshot.tracks
          .where(
            (t) => t.sourceType == 'youtube' && t.sourceId == 'ytsynthetic01',
          )
          .map((t) => t.id);
      expect(youtubeRows, [
        SyntheticLegacy.youtube,
        SyntheticLegacy.youtubeDuplicate,
      ]);
    });

    test('playlists keep their order and dangling ids', () {
      final local = snapshot.playlists.firstWhere((l) => l.id == 1);
      expect(local.trackIds, [
        SyntheticLegacy.multiPartOne,
        SyntheticLegacy.multiPartTwo,
        SyntheticLegacy.singleNoCid,
        SyntheticLegacy.youtube,
        SyntheticLegacy.danglingTrackId,
        SyntheticLegacy.netease,
      ]);
      expect(local.hasCustomCover, isTrue);
      expect(local.sortOrder, 2);

      final imported = snapshot.playlists.firstWhere((l) => l.id == 2);
      expect(imported.importSourceType, 'bilibili');
      expect(imported.sourceUrl, 'https://example.invalid/favlist?fid=1');
      expect(imported.refreshIntervalHours, 24);
      expect(imported.useAuthForRefresh, isTrue);
      expect(imported.notifyOnUpdate, isFalse);
      expect(imported.lastRefreshed!.toUtc(), SyntheticLegacy.baseTime);

      final mix = snapshot.playlists.firstWhere((l) => l.id == 3);
      expect(mix.isMix, isTrue);
      expect(mix.mixPlaylistId, 'RDsynthetic');
      expect(mix.trackIds, isEmpty);
    });

    test('play queue', () {
      final queue = snapshot.playQueues.single;
      expect(queue.trackIds.last, SyntheticLegacy.danglingTrackId);
      expect(queue.currentIndex, 1);
      expect(queue.lastPositionMs, 42000);
      expect(queue.isShuffleEnabled, isTrue);
      expect(queue.loopMode, LegacyLoopMode.all);
      // 空 list 不是 null。
      expect(queue.originalOrder, isEmpty);
      expect(queue.originalOrder, isNotNull);
      expect(queue.lastVolume, 0.5);
      expect(queue.isMixMode, isTrue);
      expect(queue.mixTitle, 'Synthetic Mix');
    });

    test('play history: two- and three-segment keys, one without a track', () {
      expect(snapshot.playHistory.map((h) => h.cid), [1001, null, 9009, null]);
      expect(snapshot.playHistory.map((h) => h.sourceId), [
        'BV1synthetic0001',
        'BV1synthetic0001',
        'BV9gone000009',
        'ytsynthetic01',
      ]);
      expect(
        snapshot.playHistory.first.playedAt.toUtc(),
        SyntheticLegacy.baseTime,
      );
    });

    test('settings at v4 are read as stored, type defaults included', () {
      final settings = snapshot.settings.single;
      expect(snapshot.storedSchemaVersion, 4);
      expect(settings.schemaVersion, 4);
      expect(settings.themeModeIndex, 2);
      expect(settings.primaryColor, 0xFF336699);
      expect(settings.customDownloadDir, '/synthetic/downloads');
      expect(settings.locale, 'zh_TW');
      expect(settings.restartRewindSeconds, 5);
      // v4 的庫已經是舊 App 修好的值；缺欄的型別預設照原樣，不在這裡清理。
      expect(settings.playHistoryLimit, legacyNullLong);
      expect(settings.detailPanelWidth, isNaN);
      expect(settings.sourceSettings.map((e) => e.sourceId), [
        'bilibili',
        'youtube',
        'netease',
      ]);
      expect(settings.sourceSettings.map((e) => e.useAuthForPlay), [
        true,
        false,
        true,
      ]);
      expect(settings.lyricsAiEndpoint, 'https://example.invalid/v1');
      expect(settings.lyricsWindowOutlineEnabled, isTrue);
      expect(settings.lyricsWindowShadowBlurRadius, 3.5);
      expect(settings.lyricsWindowTextColor, isNull);
    });

    test('the remaining collections', () {
      expect(snapshot.searchHistory.map((s) => s.query), [
        'synthetic query one',
        'synthetic query two',
      ]);

      final done = snapshot.downloadTasks.first;
      expect(done.trackId, SyntheticLegacy.netease);
      expect(done.status, LegacyDownloadStatus.completed);
      expect(done.progress, 1.0);
      expect(done.totalBytes, 1024);
      expect(done.completedAt, isNotNull);
      final failed = snapshot.downloadTasks.last;
      expect(failed.status, LegacyDownloadStatus.failed);
      expect(failed.playlistId, isNull);
      expect(failed.priority, 3);

      expect(snapshot.radioStations.map((r) => r.sourceType), [
        'bilibili',
        'youtube',
      ]);
      expect(snapshot.radioStations.first.isFavorite, isTrue);
      expect(snapshot.radioStations.first.hostUid, 321);

      expect(snapshot.lyricsMatches.map((m) => m.trackUniqueKey), [
        'bilibili:BV1synthetic0001:1001',
        'bilibili:BV3synthetic0003',
      ]);
      expect(snapshot.lyricsMatches.first.offsetMs, -250);

      expect(snapshot.accounts.map((a) => a.platform), ['bilibili', 'netease']);
      expect(snapshot.accounts.first.isLoggedIn, isTrue);
      expect(snapshot.accounts.last.sessionExpired, isTrue);
      expect(snapshot.accounts.last.userId, isNull);
    });
  });

  test('a settings row below v4 gets the old migrations replayed', () async {
    final snapshot = await readSynthetic(schemaVersion: null);

    expect(snapshot.storedSchemaVersion, 0);
    final settings = snapshot.settings.single;
    expect(settings.schemaVersion, 4);
    // 補做之後，缺欄的型別預設變回舊版的預設。
    expect(settings.playHistoryLimit, 10000);
    expect(settings.detailPanelWidth, 380);
    expect(settings.sourceSettings.map((e) => e.sourceId).toSet(), {
      'bilibili',
      'youtube',
      'netease',
    });
    // 使用者設過的值不被動。
    expect(settings.themeModeIndex, 2);
    expect(settings.customDownloadDir, '/synthetic/downloads');
  });
}
