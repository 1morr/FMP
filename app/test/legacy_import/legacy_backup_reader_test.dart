import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/legacy_import/legacy_backup_reader.dart';
import 'package:fmp/legacy_import/legacy_converter.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';

// 舊 JSON 備份的讀取（M5 design §4.2、§9「JSON 備份」）。檔案是手寫的合成資料，形狀照舊專案凍結的
// `lib/services/backup/backup_data.dart`（`BackupData.fromJson`、`SettingsBackup.fromJson`、
// `_readSourceSettings`）；版本史見 `research/legacy-sources.md` §4.2。

Uint8List bytes(Object json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

const _reader = LegacyBackupReader();

LegacySnapshot read(Object json) => _reader.read(bytes(json)).snapshot;

LegacySourceSettings source(LegacySnapshot snapshot, String id) => snapshot
    .settings
    .single
    .sourceSettings
    .singleWhere((entry) => entry.sourceId == id);

void main() {
  /// v1：初版。沒有 `sourceSettings`（六個具名鍵）、播放歷史上限、版面欄位；`lyricsMatches` 是
  /// 之後沒升版就加的鍵；曲目沒有 `isAvailable` 等欄位，歌單沒有 `updatedAt`。
  final v1 = {
    'version': 1,
    'exportedAt': '2025-01-02T03:04:05.678',
    'appVersion': '1.2.0',
    'playlists': [
      {
        'name': 'Favorites',
        'trackKeys': ['bilibili:BV1aaa:111', 'youtube:ytA', 'bilibili:BV1gone'],
        'createdAt': '2024-05-06T07:08:09.000',
      },
    ],
    'tracks': [
      {
        'sourceId': 'BV1aaa',
        'sourceType': 'bilibili',
        'title': 'Part one',
        'cid': 111,
        'pageNum': 1,
        'pageCount': 2,
        'createdAt': '2024-05-06T07:08:09.000',
      },
      {
        'sourceId': 'ytA',
        'sourceType': 'youtube',
        'title': 'Video A',
        'artist': 'Channel A',
        'channelId': 'UCa',
        'durationMs': 123000,
        'thumbnailUrl': 'https://example.test/a.jpg',
        'createdAt': '2024-05-06T07:08:09.000',
      },
    ],
    'playHistory': [
      {
        'sourceId': 'ytA',
        'sourceType': 'youtube',
        'title': 'Video A',
        'playedAt': '2025-01-01T10:00:00.000',
      },
    ],
    'searchHistory': [
      {'query': 'lofi', 'timestamp': '2025-01-01T09:00:00.000'},
    ],
    'radioStations': [
      {
        'url': 'https://live.example.test/1',
        'title': 'Radio 1',
        'sourceType': 'bilibili',
        'sourceId': '1',
        'createdAt': '2024-05-06T07:08:09.000',
      },
    ],
    'settings': {
      'themeModeIndex': 2,
      'youtubeStreamPriority': 'audioOnly',
      'useYoutubeAuthForPlay': true,
      'useBilibiliAuthForPlay': false,
    },
    'lyricsMatches': [
      {
        'trackUniqueKey': 'youtube:ytA',
        'lyricsSource': 'lrclib',
        'externalId': '9',
        'matchedAt': '2025-01-01T11:00:00.000',
      },
    ],
  };

  group('v1', () {
    final snapshot = read(v1);

    test('reads every collection; numbers the rows by position', () {
      expect(_reader.read(bytes(v1)).version, 1);
      expect(snapshot.tracks.map((t) => (t.id, t.sourceId)), [
        (1, 'BV1aaa'),
        (2, 'ytA'),
      ]);
      expect(snapshot.playHistory.single.title, 'Video A');
      expect(snapshot.searchHistory.single.query, 'lofi');
      expect(snapshot.radioStations.single.sortOrder, 0);
      expect(snapshot.radioStations.single.isFavorite, isFalse);
      expect(snapshot.lyricsMatches.single.externalId, '9');
      // 備份沒有的東西是空的。
      expect(snapshot.playQueues, isEmpty);
      expect(snapshot.accounts, isEmpty);
      expect(snapshot.downloadTasks, isEmpty);
      expect(snapshot.storedSchemaVersion, isNull);
    });

    test('missing keys take the legacy defaults', () {
      final track = snapshot.tracks.first;
      expect(track.isAvailable, isTrue);
      expect(track.isVip, isFalse);
      expect(track.artist, isNull);
      expect(snapshot.playlists.single.notifyOnUpdate, isTrue);
      expect(snapshot.playlists.single.hasCustomCover, isFalse);
      expect(snapshot.playlists.single.updatedAt, isNull);
      expect(snapshot.playlists.single.sortOrder, 0);
    });

    test('playlist items refer to tracks by key; an unknown key dangles', () {
      // 兩個找得到、一個找不到（帶一個不存在的 id，轉換器計成 danglingTrackId）。
      final ids = snapshot.playlists.single.trackIds;
      expect(ids.sublist(0, 2), [1, 2]);
      expect(snapshot.tracks.map((t) => t.id), isNot(contains(ids[2])));
    });

    test('times without a zone are read as local time', () {
      final created = snapshot.tracks.first.createdAt;
      expect(created.isUtc, isFalse);
      expect(created, DateTime(2024, 5, 6, 7, 8, 9));
      expect(snapshot.playHistory.single.playedAt, DateTime(2025, 1, 1, 10));
    });

    test('the six per-source keys fold into three entries', () {
      expect(source(snapshot, 'youtube').streamPriority, 'audioOnly');
      expect(source(snapshot, 'youtube').useAuthForPlay, isTrue);
      // 缺的鍵用該音源的舊預設。
      expect(source(snapshot, 'bilibili').streamPriority, 'audioOnly,muxed');
      expect(source(snapshot, 'bilibili').useAuthForPlay, isFalse);
      expect(source(snapshot, 'netease').streamPriority, 'audioOnly');
      expect(source(snapshot, 'netease').useAuthForPlay, isTrue);
      expect(snapshot.settings.single.themeModeIndex, 2);
    });

    test('the settings are not run through the legacy migrations', () {
      // 備份有自己的版本語意：缺鍵的布林是舊版 fromJson 的預設，不是「使用者關掉」。
      final settings = snapshot.settings.single;
      expect(settings.schemaVersion, 4);
      expect(settings.rememberPlaybackPosition, isTrue);
      expect(settings.tempPlayRewindSeconds, 10);
      expect(settings.playHistoryLimit, 10000);
    });

    test('through the converter: browse as logged in follows the old keys', () {
      final bundle = const LegacyConverter()
          .convert(
            snapshot,
            source: LegacyImportSource.backup,
            backupVersion: 1,
            now: DateTime.utc(2026, 10, 23),
          )
          .bundle;
      expect(bundle.browseAsLoggedIn, {
        'bilibili': false,
        'youtube': true,
        'netease': true,
      });
      expect(bundle.record.source, LegacyImportSource.backup);
      expect(bundle.record.backupVersion, 1);
      expect(bundle.queue, isEmpty);
      expect(bundle.playerState, isNull);
      expect(bundle.accounts, isEmpty);
      // 懸空的曲目鍵被計成略過。
      final entries = bundle.record.summary.collections['playlistEntries']!;
      expect(entries.read, 3);
      expect(entries.written, 2);
      expect(entries.skipped, {'danglingTrackId': 1});
    });
  });

  group('v2', () {
    // v2：加了歌單與曲目的欄位；`radioRefreshIntervalMinutes`、`lyricsAi*`、
    // `homeRankingSourcePriority` 是之後沒升版就加的鍵。
    final v2 = {
      'version': 2,
      'exportedAt': '2025-06-01T00:00:00.000',
      'playlists': [
        {
          'name': 'Imported',
          'sourceUrl': 'https://space.bilibili.com/1/favlist?fid=2',
          'importSourceType': 'bilibili',
          'refreshIntervalHours': 12,
          'lastRefreshed': '2025-05-30T12:00:00.000',
          'ownerName': 'Owner',
          'ownerUserId': '99',
          'useAuthForRefresh': true,
          'trackKeys': ['bilibili:BV1x'],
          'createdAt': '2025-01-01T00:00:00.000',
          'updatedAt': '2025-05-30T12:00:00.000',
          'sortOrder': 3,
        },
      ],
      'tracks': [
        {
          'sourceId': 'BV1x',
          'sourceType': 'bilibili',
          'title': 'X',
          'isAvailable': false,
          'isVip': true,
          'unavailableReason': 'gone',
          'bilibiliAid': 5,
          'originalSongId': '77',
          'originalSource': 'netease',
          'createdAt': '2025-01-01T00:00:00.000',
          'updatedAt': '2025-02-01T00:00:00.000',
        },
      ],
      'settings': {
        'radioRefreshIntervalMinutes': 15,
        'lyricsAiEndpoint': 'https://ai.example.test',
        'homeRankingSourcePriority': 'netease,bilibili,youtube',
        'autoCheckUpdates': true,
      },
    };

    test('reads the added fields and the keys added without a bump', () {
      final snapshot = read(v2);
      final playlist = snapshot.playlists.single;
      expect(playlist.sourceUrl, contains('bilibili.com'));
      expect(playlist.importSourceType, 'bilibili');
      expect(playlist.refreshIntervalHours, 12);
      expect(playlist.useAuthForRefresh, isTrue);
      expect(playlist.sortOrder, 3);
      expect(playlist.updatedAt, DateTime(2025, 5, 30, 12));
      final track = snapshot.tracks.single;
      expect(track.isAvailable, isFalse);
      expect(track.isVip, isTrue);
      expect(track.originalSource, 'netease');
      final settings = snapshot.settings.single;
      expect(settings.radioRefreshIntervalMinutes, 15);
      expect(settings.lyricsAiEndpoint, 'https://ai.example.test');
      expect(settings.homeRankingSourcePriority, 'netease,bilibili,youtube');
      // 沒有的鍵走預設；被移除的 `autoCheckUpdates` 忽略。
      expect(settings.rankingRefreshIntervalMinutes, 60);
      expect(settings.playHistoryLimit, 10000);
    });
  });

  group('v4', () {
    final v4 = {
      'version': 4,
      'exportedAt': '2026-02-03T04:05:06.000',
      'appVersion': '1.9.0',
      'settings': {
        'themeModeIndex': 1,
        'railExpanded': true,
        'detailPanelExpanded': true,
        'detailPanelWidth': 500,
        'sourceSettings': [
          {
            'sourceId': 'youtube',
            'streamPriority': 'muxed,audioOnly',
            'useAuthForPlay': true,
          },
          // 缺 `useAuthForPlay` 走該音源的預設；缺 `streamPriority` 是空字串。
          {'sourceId': 'bilibili'},
          {'sourceId': 'netease', 'useAuthForPlay': false},
        ],
        // v4 之後六個具名鍵不再讀。
        'useYoutubeAuthForPlay': false,
      },
    };

    test('reads the sourceSettings array and the layout keys', () {
      final snapshot = read(v4);
      final settings = snapshot.settings.single;
      expect(settings.railExpanded, isTrue);
      expect(settings.detailPanelExpanded, isTrue);
      expect(settings.detailPanelWidth, 500.0);
      expect(source(snapshot, 'youtube').streamPriority, 'muxed,audioOnly');
      expect(source(snapshot, 'youtube').useAuthForPlay, isTrue);
      expect(source(snapshot, 'bilibili').streamPriority, '');
      expect(source(snapshot, 'bilibili').useAuthForPlay, isTrue);
      expect(source(snapshot, 'netease').useAuthForPlay, isFalse);
      expect(snapshot.settings, hasLength(1));
      expect(snapshot.tracks, isEmpty);
    });
  });

  group('v5', () {
    final v5 = {
      'version': 5,
      'exportedAt': '2026-09-20T00:00:00.000Z',
      'settings': {
        'playHistoryLimit': 5000,
        'autoCheckUpdates': false,
        'sourceSettings': <Object>[],
      },
      'playHistory': [
        {
          'sourceId': 'BV1h',
          'sourceType': 'bilibili',
          'cid': 9,
          'title': 'H',
          'artist': 'U',
          'durationMs': 1000,
          'playedAt': '2026-09-19T08:00:00.000Z',
        },
      ],
    };

    test('reads the play history limit; a time with a zone stays exact', () {
      final snapshot = read(v5);
      expect(_reader.read(bytes(v5)).version, 5);
      expect(snapshot.settings.single.playHistoryLimit, 5000);
      expect(snapshot.settings.single.sourceSettings, isEmpty);
      final entry = snapshot.playHistory.single;
      expect(entry.cid, 9);
      expect(entry.playedAt, DateTime.utc(2026, 9, 19, 8));
    });

    test('a UTF-8 byte order mark is ignored', () {
      final withBom = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(jsonEncode(v5)),
      ]);
      expect(_reader.read(withBom).snapshot.playHistory, hasLength(1));
    });
  });

  group('rejections', () {
    void expectRejected(Uint8List input, LegacyBackupRejection reason) {
      expect(
        () => _reader.read(input),
        throwsA(
          isA<LegacyBackupRejected>().having((e) => e.reason, 'reason', reason),
        ),
      );
    }

    test('a backup newer than version 5', () {
      expectRejected(
        bytes({
          'version': 6,
          'exportedAt': '2027-01-01T00:00:00.000',
          'tracks': [
            {
              'sourceId': 'a',
              'sourceType': 'youtube',
              'title': 't',
              'createdAt': '2027-01-01T00:00:00.000',
            },
          ],
        }),
        LegacyBackupRejection.newerVersion,
      );
    });

    test('something that is not a backup', () {
      expectRejected(
        Uint8List.fromList(utf8.encode('not json')),
        LegacyBackupRejection.notBackup,
      );
      expectRejected(bytes([1, 2]), LegacyBackupRejection.notBackup);
      expectRejected(
        bytes({'hello': 'world'}),
        LegacyBackupRejection.notBackup,
      );
      expectRejected(
        Uint8List.fromList([0xFF, 0xFE, 0x00]),
        LegacyBackupRejection.notBackup,
      );
    });

    test('a backup with nothing to import', () {
      expectRejected(
        bytes({'version': 5, 'exportedAt': '2026-01-01T00:00:00.000'}),
        LegacyBackupRejection.empty,
      );
    });

    test('a required field that is missing or has the wrong type', () {
      expectRejected(
        bytes({
          'version': 5,
          'tracks': [
            {'sourceType': 'youtube', 'title': 't'},
          ],
        }),
        LegacyBackupRejection.corrupt,
      );
      expectRejected(
        bytes({
          'version': 5,
          'playlists': ['not an object'],
        }),
        LegacyBackupRejection.corrupt,
      );
    });

    test('an optional field with the wrong type is treated as missing', () {
      final snapshot = read({
        'version': 5,
        'tracks': [
          {
            'sourceId': 'a',
            'sourceType': 'youtube',
            'title': 't',
            'durationMs': 'long',
            'createdAt': '2026-01-01T00:00:00.000',
          },
        ],
      });
      expect(snapshot.tracks.single.durationMs, isNull);
    });

    test('a file with settings only is a backup', () {
      final snapshot = read({
        'version': 5,
        'settings': {'themeModeIndex': 1},
      });
      expect(snapshot.settings, hasLength(1));
    });
  });
}
