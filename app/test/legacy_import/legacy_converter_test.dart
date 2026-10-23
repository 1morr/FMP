import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/import/import_bundle.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/mix_identity.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/legacy_import/legacy_converter.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';
import 'package:fmp/legacy_import/legacy_track_catalog.dart';
import 'package:fmp/legacy_import/skip_reason.dart';

import 'legacy_snapshot_builders.dart';

// 轉換器（M5 design §5、§9「轉換器」）：純 Dart，手寫的 snapshot 進、匯入包出。全是編造資料。

TrackKeyParts key(String type, String id, [int? cid]) =>
    TrackKeyParts(sourceTypeId: type, sourceId: id, cid: cid);

ImportBundle convert(
  LegacySnapshot snapshot, {
  LegacyImportSource source = LegacyImportSource.database,
  int? backupVersion,
}) => const LegacyConverter().convert(
  snapshot,
  source: source,
  backupVersion: backupVersion,
  now: DateTime.utc(2026, 10, 23),
);

CollectionSummary summaryOf(ImportBundle bundle, String collection) =>
    bundle.record.summary.collections[collection]!;

/// 每個 collection：讀到的 = 寫出的 + 略過的筆數（註記在 `notes`，不算）；`skipped` 裡只有
/// 真正的略過、`notes` 裡只有註記。
void expectBalanced(ImportBundle bundle) {
  for (final MapEntry(:key, :value)
      in bundle.record.summary.collections.entries) {
    final skipped = value.skipped.values.fold<int>(0, (sum, n) => sum + n);
    expect(value.read, value.written + skipped, reason: key);
    for (final reason in value.skipped.keys) {
      expect(SkipReason.values.byName(reason).isSkip, isTrue, reason: reason);
    }
    for (final reason in value.notes.keys) {
      expect(SkipReason.values.byName(reason).isSkip, isFalse, reason: reason);
    }
  }
}

void main() {
  group('B 站單 P 去 cid', () {
    test('rule: pageCount <= 1, or no pageCount with no part signs', () {
      bool single({int? pageCount, int? pageNum, String? parentTitle}) =>
          isBilibiliSinglePart(
            legacyTrack(
              id: 1,
              pageCount: pageCount,
              pageNum: pageNum,
              parentTitle: parentTitle,
            ),
          );
      expect(single(pageCount: 1), isTrue);
      expect(single(pageCount: 0), isTrue);
      // pageCount 在，以它為準，不看 pageNum／parentTitle。
      expect(single(pageCount: 1, pageNum: 3, parentTitle: 'x'), isTrue);
      expect(single(pageCount: 2), isFalse);
      expect(single(pageCount: 2, pageNum: 1), isFalse);
      // pageCount 空：pageNum 空或 1，而且沒有 parentTitle。
      expect(single(), isTrue);
      expect(single(pageNum: 1), isTrue);
      expect(single(pageNum: 1, parentTitle: ''), isTrue);
      expect(single(pageNum: 2), isFalse);
      expect(single(pageNum: 1, parentTitle: 'Parent'), isFalse);
    });

    test('a single-part track loses the cid the old app backfilled', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [
            legacyTrack(
              id: 1,
              sourceId: 'BVs',
              pageCount: 1,
              cid: 77,
              pageNum: 1,
            ),
          ],
          playlists: [
            legacyPlaylist(id: 1, trackIds: [1]),
          ],
        ),
      );
      expect(bundle.tracks.single.key, key('bilibili', 'BVs'));
      expect(
        bundle.playlists.single.entries.single.track,
        key('bilibili', 'BVs'),
      );
    });

    test(
      'two-segment and three-segment keys of one video merge into one row',
      () {
        final bundle = convert(
          legacySnapshot(
            tracks: [
              legacyTrack(
                id: 1,
                sourceId: 'BVs',
                title: 'older, two segments',
                pageCount: 1,
                updatedAt: baseTime,
              ),
              legacyTrack(
                id: 2,
                sourceId: 'BVs',
                title: 'newer, backfilled cid',
                pageCount: 1,
                cid: 77,
                updatedAt: baseTime.add(const Duration(days: 1)),
              ),
            ],
            // 歌單、佇列、歷史都經對照接上同一個鍵，包含指到被併掉那一列的 id。
            playlists: [
              legacyPlaylist(id: 1, trackIds: [1, 2]),
            ],
            queue: legacyQueue(trackIds: [1]),
            history: [
              legacyHistory(id: 1, sourceId: 'BVs', playedAt: baseTime),
              legacyHistory(
                id: 2,
                sourceId: 'BVs',
                cid: 77,
                playedAt: baseTime,
              ),
            ],
          ),
        );
        final merged = key('bilibili', 'BVs');
        expect(bundle.tracks, hasLength(1));
        expect(bundle.tracks.single.title, 'newer, backfilled cid');
        expect(bundle.tracks.single.key, merged);
        expect(bundle.playlists.single.entries.map((e) => e.track), [
          merged,
          merged,
        ]);
        expect(bundle.queue.map((e) => e.track), [merged]);
        expect(bundle.history.map((e) => e.track), [merged, merged]);
        expect(summaryOf(bundle, 'tracks').skipped, {'duplicateTrack': 1});
        // 兩段與三段的歷史鍵都在 Track 裡，沒有未驗證的分 P。
        expect(summaryOf(bundle, 'history').skipped, isEmpty);
        expectBalanced(bundle);
      },
    );

    test(
      'a history cid key of a video that Track knows as single-part merges',
      () {
        final bundle = convert(
          legacySnapshot(
            tracks: [legacyTrack(id: 1, sourceId: 'BVs', pageCount: 1)],
            playlists: [
              legacyPlaylist(id: 1, trackIds: [1]),
            ],
            history: [
              legacyHistory(
                id: 1,
                sourceId: 'BVs',
                cid: 55,
                title: 'cid the Track row never had',
                playedAt: baseTime,
              ),
            ],
          ),
        );
        expect(bundle.history.single.track, key('bilibili', 'BVs'));
        expect(bundle.tracks, hasLength(1));
        expect(
          bundle.tracks.single.title,
          isNot('cid the Track row never had'),
        );
        expect(summaryOf(bundle, 'history').notes, isEmpty);
        expect(summaryOf(bundle, 'tracks').read, 1);
        expectBalanced(bundle);
      },
    );

    test('a history cid key of a known multi-part video stays, no note', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [
            legacyTrack(
              id: 1,
              sourceId: 'BVm',
              pageCount: 2,
              cid: 1,
              pageNum: 1,
              parentTitle: 'P',
            ),
          ],
          playlists: [
            legacyPlaylist(id: 1, trackIds: [1]),
          ],
          history: [
            legacyHistory(id: 1, sourceId: 'BVm', cid: 2, playedAt: baseTime),
          ],
        ),
      );
      expect(bundle.history.single.track, key('bilibili', 'BVm', 2));
      expect(summaryOf(bundle, 'history').notes, isEmpty);
    });

    test('a multi-part track keeps its cid, part index and parent title', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [
            legacyTrack(
              id: 1,
              sourceId: 'BVm',
              title: 'Part Two',
              pageCount: 2,
              cid: 202,
              pageNum: 2,
              parentTitle: 'The Video',
            ),
          ],
          playlists: [
            legacyPlaylist(id: 1, trackIds: [1]),
          ],
        ),
      );
      final track = bundle.tracks.single;
      expect(track.key, key('bilibili', 'BVm', 202));
      expect(track.partIndex, 2);
      expect(track.parentTitle, 'The Video');
    });

    test('a single-part track gets no part index or parent title', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [
            legacyTrack(
              id: 1,
              pageCount: 1,
              cid: 5,
              pageNum: 1,
              parentTitle: 'Same As Title',
            ),
          ],
          playlists: [
            legacyPlaylist(id: 1, trackIds: [1]),
          ],
        ),
      );
      expect(bundle.tracks.single.partIndex, isNull);
      expect(bundle.tracks.single.parentTitle, isNull);
    });

    test('non-bilibili tracks keep whatever cid they have', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [
            legacyTrack(
              id: 1,
              sourceType: 'youtube',
              sourceId: 'yt',
              pageCount: 1,
              cid: 9,
            ),
          ],
          playlists: [
            legacyPlaylist(id: 1, trackIds: [1]),
          ],
        ),
      );
      expect(bundle.tracks.single.key, key('youtube', 'yt', 9));
    });

    test(
      'a bilibili history key without a Track stays as it is and is noted',
      () {
        final bundle = convert(
          legacySnapshot(
            history: [
              legacyHistory(
                id: 1,
                sourceId: 'BVgone',
                cid: 9009,
                title: 'Gone Track',
                artist: 'Someone',
                durationMs: 61000,
                thumbnailUrl: 'https://example.invalid/c.jpg',
                playedAt: baseTime,
              ),
              legacyHistory(id: 2, sourceId: 'BVtwo', playedAt: baseTime),
            ],
          ),
        );
        expect(bundle.history.map((e) => e.track), [
          key('bilibili', 'BVgone', 9009),
          key('bilibili', 'BVtwo'),
        ]);
        // 歷史快照補出曲目：欄位來自歷史列。
        final gone = bundle.tracks.firstWhere((t) => t.sourceId == 'BVgone');
        expect(gone.title, 'Gone Track');
        expect(gone.uploader, 'Someone');
        expect(gone.duration, const Duration(milliseconds: 61000));
        expect(
          gone.artwork.single.url,
          Uri.parse('https://example.invalid/c.jpg'),
        );
        expect(gone.cid, 9009);
        // 只有帶 cid 的才無從判斷；註記不算略過。
        expect(summaryOf(bundle, 'history').notes, {'unverifiedPart': 1});
        expect(summaryOf(bundle, 'history').skipped, isEmpty);
        expect(summaryOf(bundle, 'history').written, 2);
        expectBalanced(bundle);
      },
    );
  });

  group('tracks', () {
    test('only referenced tracks are written; the rest are unreferenced', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [
            legacyTrack(id: 1, sourceId: 'BVa'),
            legacyTrack(id: 2, sourceId: 'BVb'),
          ],
          playlists: [
            legacyPlaylist(id: 1, trackIds: [1]),
          ],
        ),
      );
      expect(bundle.tracks.map((t) => t.sourceId), ['BVa']);
      expect(summaryOf(bundle, 'tracks').skipped, {'unreferenced': 1});
      expectBalanced(bundle);
    });

    test('field mapping', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [
            legacyTrack(
              id: 1,
              sourceType: 'netease',
              sourceId: '123',
              title: 'A Song',
              artist: 'An Artist',
              durationMs: 215500,
              thumbnailUrl: 'https://example.invalid/a.jpg',
            ),
          ],
          playlists: [
            legacyPlaylist(id: 1, trackIds: [1]),
          ],
        ),
      );
      final track = bundle.tracks.single;
      expect(track.sourceTypeId, 'netease');
      expect(track.sourceId, '123');
      expect(track.title, 'A Song');
      expect(track.uploader, 'An Artist');
      expect(track.duration, const Duration(milliseconds: 215500));
      expect(track.artwork, [
        TrackArtwork(url: Uri.parse('https://example.invalid/a.jpg')),
      ]);
    });

    test('artwork: empty and non-http urls are dropped', () {
      for (final (index, url) in [
        '',
        '   ',
        'ftp://example.invalid/a.jpg',
        '/local/file.jpg',
        'file:///x.jpg',
        null,
      ].indexed) {
        final bundle = convert(
          legacySnapshot(
            tracks: [
              legacyTrack(id: 1, sourceId: 'BV$index', thumbnailUrl: url),
            ],
            playlists: [
              legacyPlaylist(id: 1, trackIds: [1]),
            ],
          ),
        );
        expect(bundle.tracks.single.artwork, isEmpty, reason: '$url');
      }
    });

    test(
      'the latest row wins (updatedAt ?? createdAt); ties go to the later row',
      () {
        final bundle = convert(
          legacySnapshot(
            tracks: [
              legacyTrack(
                id: 1,
                sourceType: 'youtube',
                sourceId: 'yt',
                title: 'created later than the other updatedAt',
                createdAt: baseTime.add(const Duration(days: 5)),
              ),
              legacyTrack(
                id: 2,
                sourceType: 'youtube',
                sourceId: 'yt',
                title: 'updated most recently',
                createdAt: baseTime,
                updatedAt: baseTime.add(const Duration(days: 9)),
              ),
              legacyTrack(
                id: 3,
                sourceType: 'youtube',
                sourceId: 'yt',
                title: 'oldest',
                createdAt: baseTime,
              ),
            ],
            playlists: [
              legacyPlaylist(id: 1, trackIds: [1, 3]),
            ],
          ),
        );
        expect(bundle.tracks.single.title, 'updated most recently');
        // 參照到被併掉那一列的 id 仍然接得上。
        expect(bundle.playlists.single.entries, hasLength(2));
        expect(summaryOf(bundle, 'tracks').skipped, {'duplicateTrack': 2});

        final tie = convert(
          legacySnapshot(
            tracks: [
              legacyTrack(
                id: 1,
                sourceType: 'youtube',
                sourceId: 'yt',
                title: 'first',
              ),
              legacyTrack(
                id: 2,
                sourceType: 'youtube',
                sourceId: 'yt',
                title: 'second',
              ),
            ],
            playlists: [
              legacyPlaylist(id: 1, trackIds: [1]),
            ],
          ),
        );
        expect(tie.tracks.single.title, 'second');
      },
    );

    test('a history snapshot never replaces a Track row', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [
            legacyTrack(
              id: 1,
              sourceType: 'youtube',
              sourceId: 'yt',
              title: 'from the Track table',
            ),
          ],
          history: [
            legacyHistory(
              id: 1,
              sourceType: 'youtube',
              sourceId: 'yt',
              title: 'from history',
              playedAt: baseTime,
            ),
          ],
        ),
      );
      expect(bundle.tracks.single.title, 'from the Track table');
    });

    test('unknown sources are skipped, with the rows that point at them', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [
            legacyTrack(id: 1, sourceType: 'spotify', sourceId: 'sp'),
            legacyTrack(id: 2, sourceId: 'BVok'),
          ],
          playlists: [
            legacyPlaylist(id: 1, trackIds: [1, 2]),
          ],
          queue: legacyQueue(trackIds: [1]),
          history: [
            legacyHistory(
              id: 1,
              sourceType: 'spotify',
              sourceId: 'sp',
              playedAt: baseTime,
            ),
          ],
          radio: [legacyRadio(id: 1, sourceType: 'spotify', sourceId: 'room')],
        ),
      );
      expect(bundle.tracks.map((t) => t.sourceId), ['BVok']);
      expect(summaryOf(bundle, 'tracks').skipped, {'unknownSource': 1});
      expect(summaryOf(bundle, 'playlistEntries').skipped, {
        'unknownSource': 1,
      });
      expect(summaryOf(bundle, 'queue').skipped, {'unknownSource': 1});
      expect(summaryOf(bundle, 'history').skipped, {'unknownSource': 1});
      expect(summaryOf(bundle, 'radioStations').skipped, {'unknownSource': 1});
      expectBalanced(bundle);
    });
  });

  group('playlists', () {
    test('sort order is rewritten by (sortOrder, id); times are UTC', () {
      final bundle = convert(
        legacySnapshot(
          playlists: [
            legacyPlaylist(id: 3, name: 'C', sortOrder: 1),
            legacyPlaylist(id: 2, name: 'B', sortOrder: 0),
            legacyPlaylist(id: 1, name: 'A', sortOrder: 1),
          ],
        ),
      );
      expect(bundle.playlists.map((p) => p.name), ['B', 'A', 'C']);
      expect(bundle.playlists.map((p) => p.legacyPlaylistId), [2, 1, 3]);
    });

    test('createdAt and updatedAt keep the old values; updatedAt falls back to createdAt', () {
      final updated = baseTime.add(const Duration(days: 2));
      final bundle = convert(
        legacySnapshot(
          playlists: [
            legacyPlaylist(id: 1, updatedAt: updated),
            legacyPlaylist(id: 2),
          ],
        ),
      );
      final (a, b) = (bundle.playlists[0], bundle.playlists[1]);
      expect(a.createdAt, baseTime.toUtc());
      expect(a.createdAt.isUtc, isTrue);
      expect(a.updatedAt, updated.toUtc());
      expect(b.updatedAt, baseTime.toUtc());
    });

    test('a plain playlist: name, description, cover, entries in order', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [
            legacyTrack(id: 1, sourceId: 'BVa'),
            legacyTrack(id: 2, sourceType: 'youtube', sourceId: 'yt'),
          ],
          playlists: [
            legacyPlaylist(
              id: 7,
              name: 'Mine',
              description: 'desc',
              coverUrl: 'https://example.invalid/cover.jpg',
              trackIds: [2, 1, 2],
            ),
          ],
        ),
      );
      final playlist = bundle.playlists.single;
      expect(playlist.kind, PlaylistKind.local);
      expect(playlist.name, 'Mine');
      expect(playlist.description, 'desc');
      expect(
        playlist.artwork.single.url,
        Uri.parse('https://example.invalid/cover.jpg'),
      );
      expect(playlist.legacyPlaylistId, 7);
      expect(playlist.remote, isNull);
      // 同一首可以在歌單裡出現多次。
      expect(playlist.entries.map((e) => e.track), [
        key('youtube', 'yt'),
        key('bilibili', 'BVa'),
        key('youtube', 'yt'),
      ]);
      expect(playlist.entries.every((e) => !e.unavailable), isTrue);
    });

    test('the backup source has no legacy playlist ids', () {
      final bundle = convert(
        legacySnapshot(playlists: [legacyPlaylist(id: 4)]),
        source: LegacyImportSource.backup,
        backupVersion: 5,
      );
      expect(bundle.playlists.single.legacyPlaylistId, isNull);
      expect(bundle.record.source, LegacyImportSource.backup);
      expect(bundle.record.backupVersion, 5);
      expect(bundle.record.legacySchemaVersion, isNull);
    });

    test('dangling track ids are skipped and counted', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [legacyTrack(id: 1)],
          playlists: [
            legacyPlaylist(id: 1, trackIds: [1, 404, 1]),
          ],
        ),
      );
      expect(bundle.playlists.single.entries, hasLength(2));
      final entries = summaryOf(bundle, 'playlistEntries');
      expect((entries.read, entries.written), (3, 2));
      expect(entries.skipped, {'danglingTrackId': 1});
      expectBalanced(bundle);
    });

    group('Mix', () {
      test('becomes a mix playlist on youtube with the seed and no tracks', () {
        final bundle = convert(
          legacySnapshot(
            tracks: [legacyTrack(id: 1)],
            playlists: [
              legacyPlaylist(
                id: 1,
                isMix: true,
                mixSeedVideoId: 'seedVideo',
                trackIds: [1],
                coverUrl: 'https://example.invalid/mix.jpg',
              ),
            ],
          ),
        );
        final mix = bundle.playlists.single;
        expect(mix.kind, PlaylistKind.mix);
        expect(mix.mixPluginId, 'youtube');
        expect(mix.mixSeedSourceId, 'seedVideo');
        expect(mix.mixSeedCid, isNull);
        expect(mix.entries, isEmpty);
        expect(mix.remote, isNull);
        // 沒有曲目被參照：Track 是孤兒。
        expect(bundle.tracks, isEmpty);
      });

      test('without a seed it is skipped', () {
        for (final seed in [null, '', '  ']) {
          final bundle = convert(
            legacySnapshot(
              playlists: [
                legacyPlaylist(id: 1, isMix: true, mixSeedVideoId: seed),
              ],
            ),
          );
          expect(bundle.playlists, isEmpty, reason: '"$seed"');
          expect(summaryOf(bundle, 'playlists').skipped, {'mixWithoutSeed': 1});
          expectBalanced(bundle);
        }
      });
    });

    group('imported playlists', () {
      LegacySnapshot imported({
        String? url = 'https://space.bilibili.com/1/favlist?fid=4026748432',
        String? type = 'bilibili',
        String? ownerUserId = '555',
        List<LegacyAccount> accounts = const [],
        bool secondWithSameUrl = false,
        bool trackAvailable = true,
      }) => legacySnapshot(
        tracks: [
          legacyTrack(id: 1, sourceId: 'BVa', isAvailable: trackAvailable),
        ],
        accounts: accounts,
        playlists: [
          legacyPlaylist(
            id: 1,
            sourceUrl: url,
            importSourceType: type,
            refreshIntervalHours: 24,
            lastRefreshed: baseTime,
            ownerName: 'Owner',
            ownerUserId: ownerUserId,
            hasCustomCover: true,
            trackIds: [1],
          ),
          if (secondWithSameUrl)
            legacyPlaylist(
              id: 2,
              sourceUrl: url,
              importSourceType: type,
              trackIds: [1],
              sortOrder: 1,
            ),
        ],
      );

      test('a recognized url makes an imported playlist with its remote', () {
        final bundle = convert(imported());
        final playlist = bundle.playlists.single;
        expect(playlist.kind, PlaylistKind.imported);
        final remote = playlist.remote!;
        expect(remote.pluginId, 'bilibili');
        expect(remote.remoteId, '4026748432');
        expect(remote.ownerName, 'Owner');
        expect(remote.artworkOverridden, isTrue);
        expect(remote.refreshIntervalHours, 24);
        expect(remote.lastRefreshedAt, baseTime.toUtc());
        expect(remote.writable, isFalse);
        expect(summaryOf(bundle, 'playlists').skipped, isEmpty);
      });

      test('an empty refresh interval stays empty (no automatic refresh)', () {
        final snapshot = legacySnapshot(
          playlists: [
            legacyPlaylist(
              id: 1,
              sourceUrl: 'https://music.163.com/playlist?id=19723756',
            ),
          ],
        );
        final remote = convert(snapshot).playlists.single.remote!;
        expect(remote.pluginId, 'netease');
        expect(remote.remoteId, '19723756');
        expect(remote.refreshIntervalHours, isNull);
        expect(remote.lastRefreshedAt, isNull);
      });

      test('writable follows the old account of that platform', () {
        final same = convert(
          imported(
            accounts: [legacyAccount(platform: 'bilibili', userId: '555')],
          ),
        );
        expect(same.playlists.single.remote!.writable, isTrue);
        final other = convert(
          imported(
            accounts: [legacyAccount(platform: 'bilibili', userId: '999')],
          ),
        );
        expect(other.playlists.single.remote!.writable, isFalse);
        final wrongPlatform = convert(
          imported(
            accounts: [legacyAccount(platform: 'netease', userId: '555')],
          ),
        );
        expect(wrongPlatform.playlists.single.remote!.writable, isFalse);
        final noOwner = convert(
          imported(
            ownerUserId: null,
            accounts: [legacyAccount(platform: 'bilibili', userId: '555')],
          ),
        );
        expect(noOwner.playlists.single.remote!.writable, isFalse);
      });

      test(
        'the plugin comes from the url; a different importSourceType is noted',
        () {
          final bundle = convert(imported(type: 'netease'));
          expect(bundle.playlists.single.remote!.pluginId, 'bilibili');
          expect(summaryOf(bundle, 'playlists').notes, {
            'importSourceMismatch': 1,
          });
          expect(summaryOf(bundle, 'playlists').skipped, isEmpty);
          expect(summaryOf(bundle, 'playlists').written, 1);
        },
      );

      test(
        'a url nobody recognizes makes a local playlist and keeps the tracks',
        () {
          for (final url in [
            'https://163cn.tv/AbCdEf',
            'https://example.invalid/whatever',
            'not a url',
          ]) {
            final bundle = convert(imported(url: url));
            final playlist = bundle.playlists.single;
            expect(playlist.kind, PlaylistKind.local, reason: url);
            expect(playlist.remote, isNull);
            expect(playlist.entries, hasLength(1));
            expect(summaryOf(bundle, 'playlists').notes, {
              'remoteNotRecognized': 1,
            });
            expect(summaryOf(bundle, 'playlists').skipped, isEmpty);
            expectBalanced(bundle);
          }
        },
      );

      test('an empty url is a plain local playlist, without a note', () {
        for (final url in [null, '', '  ']) {
          final bundle = convert(imported(url: url, type: null));
          expect(bundle.playlists.single.kind, PlaylistKind.local);
          expect(summaryOf(bundle, 'playlists').skipped, isEmpty);
        }
      });

      test('a second playlist of the same remote becomes local', () {
        final bundle = convert(imported(secondWithSameUrl: true));
        expect(bundle.playlists.map((p) => p.kind), [
          PlaylistKind.imported,
          PlaylistKind.local,
        ]);
        expect(bundle.playlists[1].remote, isNull);
        expect(bundle.playlists[1].entries, hasLength(1));
        expect(summaryOf(bundle, 'playlists').notes, {'duplicateRemote': 1});
        expect(summaryOf(bundle, 'playlists').skipped, isEmpty);
        expect(summaryOf(bundle, 'playlists').written, 2);
      });

      test('unavailable tracks are marked only in imported playlists', () {
        final importedBundle = convert(imported(trackAvailable: false));
        expect(
          importedBundle.playlists.single.entries.single.unavailable,
          isTrue,
        );

        final local = convert(
          imported(url: null, type: null, trackAvailable: false),
        );
        expect(local.playlists.single.entries.single.unavailable, isFalse);
      });
    });
  });

  group('queue and player state', () {
    List<LegacyTrack> tracks(int count) => [
      for (var i = 1; i <= count; i++) legacyTrack(id: i, sourceId: 'BV$i'),
    ];

    test('natural order, loop, position, volume, shuffle flag', () {
      final bundle = convert(
        legacySnapshot(
          tracks: tracks(3),
          queue: legacyQueue(
            trackIds: [1, 2, 3],
            currentIndex: 2,
            lastPositionMs: 42000,
            loopMode: LegacyLoopMode.all,
            lastVolume: 0.25,
          ),
        ),
      );
      expect(bundle.queue.map((e) => e.track.sourceId), ['BV1', 'BV2', 'BV3']);
      expect(bundle.queue.every((e) => e.shuffleRank == null), isTrue);
      final state = bundle.playerState!;
      expect(state.currentPosition, 2);
      expect(state.position, const Duration(milliseconds: 42000));
      expect(state.loopMode, LoopMode.all);
      expect(state.shuffleEnabled, isFalse);
      expect(state.volume, 0.25);
      expect(state.muted, isFalse);
      expect(state.mix, isNull);
      expect(bundle.tracks, hasLength(3));
    });

    test('loop modes map none/all/one to off/all/one', () {
      for (final (legacy, expected) in [
        (LegacyLoopMode.none, LoopMode.off),
        (LegacyLoopMode.all, LoopMode.all),
        (LegacyLoopMode.one, LoopMode.one),
      ]) {
        final bundle = convert(
          legacySnapshot(
            tracks: tracks(1),
            queue: legacyQueue(trackIds: [1], loopMode: legacy),
          ),
        );
        expect(bundle.playerState!.loopMode, expected);
      }
    });

    test('shuffle on: the entries use originalOrder, current stays on the same track', () {
      // 洗過的順序 [3, 1, 2]，目前是第 0 個（track 3）；自然順序 [1, 2, 3]。
      final bundle = convert(
        legacySnapshot(
          tracks: tracks(3),
          queue: legacyQueue(
            trackIds: [3, 1, 2],
            originalOrder: [1, 2, 3],
            currentIndex: 0,
            isShuffleEnabled: true,
          ),
        ),
      );
      expect(bundle.queue.map((e) => e.track.sourceId), ['BV1', 'BV2', 'BV3']);
      expect(bundle.playerState!.currentPosition, 2);
      expect(bundle.playerState!.shuffleEnabled, isTrue);
      // 名次不匯入，QueueStore 會重新產生。
      expect(bundle.queue.every((e) => e.shuffleRank == null), isTrue);
    });

    test('shuffle on with an empty originalOrder falls back to trackIds', () {
      final bundle = convert(
        legacySnapshot(
          tracks: tracks(2),
          queue: legacyQueue(
            trackIds: [2, 1],
            originalOrder: [],
            isShuffleEnabled: true,
          ),
        ),
      );
      expect(bundle.queue.map((e) => e.track.sourceId), ['BV2', 'BV1']);
    });

    test('shuffle off ignores originalOrder', () {
      final bundle = convert(
        legacySnapshot(
          tracks: tracks(2),
          queue: legacyQueue(trackIds: [2, 1], originalOrder: [1, 2]),
        ),
      );
      expect(bundle.queue.map((e) => e.track.sourceId), ['BV2', 'BV1']);
    });

    test(
      'the same track twice: the k-th occurrence maps to the k-th occurrence',
      () {
        // 洗過 [2, 1, 2, 3]，目前在第 2 個（第二次出現的 track 2）；自然 [1, 2, 3, 2]。
        final bundle = convert(
          legacySnapshot(
            tracks: tracks(3),
            queue: legacyQueue(
              trackIds: [2, 1, 2, 3],
              originalOrder: [1, 2, 3, 2],
              currentIndex: 2,
              isShuffleEnabled: true,
            ),
          ),
        );
        expect(bundle.playerState!.currentPosition, 3);

        final first = convert(
          legacySnapshot(
            tracks: tracks(3),
            queue: legacyQueue(
              trackIds: [2, 1, 2, 3],
              originalOrder: [1, 2, 3, 2],
              currentIndex: 0,
              isShuffleEnabled: true,
            ),
          ),
        );
        expect(first.playerState!.currentPosition, 1);
      },
    );

    test('skipped entries shift the positions; a skipped current is empty', () {
      final bundle = convert(
        legacySnapshot(
          tracks: tracks(2),
          queue: legacyQueue(trackIds: [404, 1, 2], currentIndex: 2),
        ),
      );
      expect(bundle.queue, hasLength(2));
      expect(bundle.playerState!.currentPosition, 1);
      expect(summaryOf(bundle, 'queue').skipped, {'danglingTrackId': 1});

      final skippedCurrent = convert(
        legacySnapshot(
          tracks: tracks(2),
          queue: legacyQueue(trackIds: [404, 1, 2], currentIndex: 0),
        ),
      );
      expect(skippedCurrent.playerState!.currentPosition, isNull);
    });

    test('an out-of-range current index is empty', () {
      for (final index in [-1, 3, 99, -9223372036854775808]) {
        final bundle = convert(
          legacySnapshot(
            tracks: tracks(2),
            queue: legacyQueue(trackIds: [1, 2], currentIndex: index),
          ),
        );
        expect(bundle.playerState!.currentPosition, isNull, reason: '$index');
      }
    });

    test('position: negative or the type default is 0', () {
      for (final ms in [-1, -9223372036854775808]) {
        final bundle = convert(
          legacySnapshot(
            tracks: tracks(1),
            queue: legacyQueue(trackIds: [1], lastPositionMs: ms),
          ),
        );
        expect(bundle.playerState!.position, Duration.zero, reason: '$ms');
      }
    });

    test(
      'volume: clamped to 0..1; NaN (the whole row at type defaults) is 1.0',
      () {
        final cases = <double, double>{
          0.5: 0.5,
          0: 0,
          -0.5: 0,
          1.7: 1,
          double.nan: 1,
          double.infinity: 1,
          double.negativeInfinity: 0,
        };
        for (final MapEntry(key: input, value: expected) in cases.entries) {
          final bundle = convert(
            legacySnapshot(
              tracks: tracks(1),
              queue: legacyQueue(trackIds: [1], lastVolume: input),
            ),
          );
          expect(bundle.playerState!.volume, expected, reason: '$input');
        }
      },
    );

    test('Mix mode needs both the mix id and the title', () {
      MixIdentity? mixOf({String? id, String? title, bool mode = true}) =>
          convert(
            legacySnapshot(
              tracks: tracks(1),
              queue: legacyQueue(
                trackIds: [1],
                isMixMode: mode,
                mixPlaylistId: id,
                mixTitle: title,
              ),
            ),
          ).playerState!.mix;

      final mix = mixOf(id: 'RDabc', title: 'My Mix')!;
      expect(
        (mix.pluginId, mix.mixId, mix.title, mix.cursor),
        ('youtube', 'RDabc', 'My Mix', null),
      );
      expect(mixOf(id: 'RDabc'), isNull);
      expect(mixOf(title: 'My Mix'), isNull);
      expect(mixOf(id: '', title: 'My Mix'), isNull);
      expect(mixOf(id: 'RDabc', title: 'My Mix', mode: false), isNull);
    });

    test('an empty or fully skipped queue still writes the player state', () {
      final empty = convert(
        legacySnapshot(
          queue: legacyQueue(
            loopMode: LegacyLoopMode.one,
            lastVolume: 0.3,
            currentIndex: 0,
          ),
        ),
      );
      expect(empty.queue, isEmpty);
      final state = empty.playerState!;
      expect(state.currentPosition, isNull);
      expect(state.loopMode, LoopMode.one);
      expect(state.volume, 0.3);
      expect(state.mix, isNull);

      final allDangling = convert(
        legacySnapshot(queue: legacyQueue(trackIds: [404], lastVolume: 0.7)),
      );
      expect(allDangling.queue, isEmpty);
      expect(allDangling.playerState!.volume, 0.7);
      expect(allDangling.playerState!.currentPosition, isNull);
      expectBalanced(allDangling);

      // Mix 身分照 §5.4：兩個欄位都有才寫。
      final mix = convert(
        legacySnapshot(
          queue: legacyQueue(
            lastVolume: 0.3,
            isMixMode: true,
            mixPlaylistId: 'RDx',
            mixTitle: 'T',
          ),
        ),
      );
      expect(mix.playerState!.mix!.mixId, 'RDx');
    });

    test('no queue row, or a row of pure type defaults, writes no state', () {
      expect(convert(legacySnapshot()).playerState, isNull);
      const nullLong = -9223372036854775808;
      final defaults = convert(
        legacySnapshot(
          queue: legacyQueue(
            currentIndex: nullLong,
            lastPositionMs: nullLong,
            lastVolume: double.nan,
          ),
        ),
      );
      expect(defaults.playerState, isNull);
      expect(defaults.queue, isEmpty);
    });
  });

  group('play history', () {
    List<LegacyPlayHistory> rows(int count) => [
      for (var i = 1; i <= count; i++)
        legacyHistory(
          id: i,
          sourceType: 'youtube',
          sourceId: 'yt$i',
          // id 越大越新。
          playedAt: baseTime.add(Duration(minutes: i)),
        ),
    ];

    test('written oldest first, times in UTC', () {
      final bundle = convert(
        legacySnapshot(history: rows(3).reversed.toList()),
      );
      expect(bundle.history.map((e) => e.track.sourceId), [
        'yt1',
        'yt2',
        'yt3',
      ]);
      expect(
        bundle.history.first.playedAt,
        baseTime.add(const Duration(minutes: 1)).toUtc(),
      );
      expect(bundle.history.first.playedAt.isUtc, isTrue);
    });

    test('equal times keep the legacy id order (later id is newer)', () {
      final bundle = convert(
        legacySnapshot(
          history: [
            legacyHistory(
              id: 2,
              sourceType: 'youtube',
              sourceId: 'b',
              playedAt: baseTime,
            ),
            legacyHistory(
              id: 1,
              sourceType: 'youtube',
              sourceId: 'a',
              playedAt: baseTime,
            ),
          ],
        ),
      );
      expect(bundle.history.map((e) => e.track.sourceId), ['a', 'b']);
    });

    test('truncated to the converted limit, newest kept', () {
      // 舊上限 1000 是選項內的值，原樣生效。
      final bundle = convert(
        legacySnapshot(
          history: rows(1003),
          settings: LegacySettings(playHistoryLimit: 1000),
        ),
      );
      expect(bundle.history, hasLength(1000));
      expect(bundle.history.last.track.sourceId, 'yt1003');
      expect(bundle.history.first.track.sourceId, 'yt4');
      expect(summaryOf(bundle, 'history').skipped, {'overHistoryLimit': 3});
      expectBalanced(bundle);
      // 沒被留下的歷史不會多出曲目。
      expect(bundle.tracks, hasLength(1000));
    });

    test('an unlisted legacy limit is rounded up to the next option', () {
      final bundle = convert(
        legacySnapshot(
          history: rows(1500),
          settings: LegacySettings(playHistoryLimit: 1200),
        ),
      );
      // 1200 -> 5000：全部留下。
      expect(bundle.history, hasLength(1500));
    });

    test('an invalid limit (type default) uses the new default', () {
      final bundle = convert(
        legacySnapshot(
          history: rows(3),
          settings: LegacySettings(playHistoryLimit: -9223372036854775808),
        ),
      );
      expect(bundle.history, hasLength(3));
    });

    test('unknown sources are skipped before the limit applies', () {
      final bundle = convert(
        legacySnapshot(
          history: [
            ...rows(2),
            legacyHistory(
              id: 9,
              sourceType: 'spotify',
              sourceId: 'x',
              playedAt: baseTime,
            ),
          ],
          settings: LegacySettings(playHistoryLimit: 1000),
        ),
      );
      expect(bundle.history, hasLength(2));
      expect(summaryOf(bundle, 'history').skipped, {'unknownSource': 1});
    });

    test('the same track played twice is two entries and one track', () {
      final bundle = convert(
        legacySnapshot(
          history: [
            legacyHistory(
              id: 1,
              sourceType: 'youtube',
              sourceId: 'a',
              title: 'older',
              playedAt: baseTime,
            ),
            legacyHistory(
              id: 2,
              sourceType: 'youtube',
              sourceId: 'a',
              title: 'newer',
              playedAt: baseTime.add(const Duration(hours: 1)),
            ),
          ],
        ),
      );
      expect(bundle.history, hasLength(2));
      expect(
        bundle.tracks.single.title,
        'newer',
        reason: 'the newest snapshot supplies it',
      );
    });
  });

  group('radio stations', () {
    test('mapping, order by (sortOrder, id)', () {
      final bundle = convert(
        legacySnapshot(
          radio: [
            legacyRadio(
              id: 2,
              sourceId: 'roomB',
              title: 'B',
              sortOrder: 1,
              hostName: 'Host',
              thumbnailUrl: 'https://example.invalid/r.jpg',
              createdAt: DateTime(2024, 1, 2),
            ),
            legacyRadio(
              id: 1,
              sourceType: 'youtube',
              sourceId: 'roomA',
              title: 'A',
              sortOrder: 0,
            ),
          ],
        ),
      );
      expect(bundle.radioStations.map((s) => s.title), ['A', 'B']);
      final b = bundle.radioStations[1];
      expect(b.pluginId, 'bilibili');
      expect(b.roomId, 'roomB');
      expect(b.hostName, 'Host');
      expect(b.artwork.single.url, Uri.parse('https://example.invalid/r.jpg'));
      expect(b.addedAt, DateTime(2024, 1, 2).toUtc());
      expect(bundle.radioStations[0].hostName, isNull);
      expect(bundle.radioStations[0].artwork, isEmpty);
    });

    test('a duplicate (plugin, room) is skipped, the first one stays', () {
      final bundle = convert(
        legacySnapshot(
          radio: [
            legacyRadio(id: 1, sourceId: 'room', title: 'first'),
            legacyRadio(id: 2, sourceId: 'room', title: 'second', sortOrder: 1),
            legacyRadio(
              id: 3,
              sourceType: 'youtube',
              sourceId: 'room',
              sortOrder: 2,
            ),
          ],
        ),
      );
      expect(bundle.radioStations.map((s) => s.title), [
        'first',
        'Synthetic Room',
      ]);
      expect(summaryOf(bundle, 'radioStations').skipped, {
        'duplicateStation': 1,
      });
      expectBalanced(bundle);
    });
  });

  group('external origins', () {
    ImportBundle convertOrigin(
      String? source,
      String? id, {
      String type = 'netease',
    }) => convert(
      legacySnapshot(
        tracks: [
          legacyTrack(
            id: 1,
            sourceType: type,
            sourceId: 'src',
            originalSource: source,
            originalSongId: id,
          ),
        ],
        playlists: [
          legacyPlaylist(id: 1, trackIds: [1]),
        ],
      ),
    );

    test('netease: an all-digit id is written for the track', () {
      final bundle = convertOrigin('netease', '1234567');
      final origin = bundle.trackOrigins.single;
      expect(origin.track, key('netease', 'src'));
      expect(origin.originPluginId, 'netease');
      expect(origin.originId, '1234567');
      expect(summaryOf(bundle, 'trackOrigins').written, 1);
    });

    test('qqmusic: a mid without colon or surrounding blanks is written', () {
      final bundle = convertOrigin('qqmusic', '002abcDEF123', type: 'youtube');
      expect(bundle.trackOrigins.single.originPluginId, 'qqmusic');
      expect(bundle.trackOrigins.single.originId, '002abcDEF123');
    });

    test('formats that differ from the plugin sourceId are skipped', () {
      // netease 1.7.0：/^\d+$/ 且為安全整數；qqmusic 1.0.0：trim 後非空、不含 ':'。
      final cases = <(String, String)>[
        ('netease', 'abc'),
        ('netease', '12a'),
        ('netease', ''),
        ('netease', ' 123'),
        ('netease', '-5'),
        ('netease', '9007199254740992'),
        ('netease', '99999999999999999999'),
        ('qqmusic', ''),
        ('qqmusic', ' 002abc'),
        ('qqmusic', '002abc '),
        ('qqmusic', 'a:b'),
        ('spotify', '4uLU6hMCjMI75M1A2tKUQC'),
        ('lrclib', '123'),
      ];
      for (final (source, id) in cases) {
        final bundle = convertOrigin(source, id);
        expect(bundle.trackOrigins, isEmpty, reason: '$source "$id"');
        expect(summaryOf(bundle, 'trackOrigins').skipped, {
          'originIdFormat': 1,
        });
        expectBalanced(bundle);
      }
    });

    test('the largest safe integer is accepted', () {
      expect(
        convertOrigin('netease', '9007199254740991').trackOrigins,
        hasLength(1),
      );
    });

    test('tracks without an origin do not count', () {
      final bundle = convertOrigin(null, null);
      expect(bundle.trackOrigins, isEmpty);
      expect(summaryOf(bundle, 'trackOrigins').read, 0);
    });

    test('an unreferenced track writes no origin', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [
            legacyTrack(
              id: 1,
              sourceType: 'netease',
              sourceId: '1',
              originalSource: 'netease',
              originalSongId: '1',
            ),
          ],
        ),
      );
      expect(bundle.trackOrigins, isEmpty);
      expect(bundle.tracks, isEmpty);
    });
  });

  group('record and summary', () {
    test('the database source records the stored schema version', () {
      final bundle = convert(legacySnapshot(storedSchemaVersion: 3));
      expect(bundle.record.source, LegacyImportSource.database);
      expect(bundle.record.legacySchemaVersion, 3);
      expect(bundle.record.backupVersion, isNull);
    });

    test('every reason serializes to its English name and round-trips, notes included', () {
      final summary = ImportSummary(
        collections: {
          'x': CollectionSummary(
            read: 12,
            written: 0,
            skipped: {
              for (final r in SkipReason.values.where((r) => r.isSkip))
                r.name: 1,
            },
            notes: {
              for (final r in SkipReason.values.where((r) => !r.isSkip))
                r.name: 1,
            },
          ),
        },
      );
      expect(ImportSummary.decode(summary.encode()), summary);
      expect(SkipReason.values.map((r) => r.name), [
        'unknownSource',
        'unreferenced',
        'duplicateTrack',
        'danglingTrackId',
        'mixWithoutSeed',
        'overHistoryLimit',
        'duplicateStation',
        'originIdFormat',
        'remoteNotRecognized',
        'duplicateRemote',
        'importSourceMismatch',
        'unverifiedPart',
      ]);
    });

    test('the summary has no user data (no titles, names or urls)', () {
      final bundle = convert(
        legacySnapshot(
          tracks: [legacyTrack(id: 1, title: 'SECRET-TITLE')],
          playlists: [
            legacyPlaylist(
              id: 1,
              name: 'SECRET-NAME',
              sourceUrl: 'https://example.invalid/SECRET-URL',
              trackIds: [1],
            ),
          ],
        ),
      );
      final json = bundle.record.summary.encode();
      expect(json, isNot(contains('SECRET')));
    });
  });

  group('settings and accounts are left to later steps', () {
    test('accounts and settings groups are empty; the cache limit is never imported', () {
      final settings = LegacySettings(
        maxCacheSizeMB: 512,
        themeModeIndex: 2,
        locale: 'zh_TW',
        playHistoryLimit: 5000,
      );
      final bundle = convert(
        legacySnapshot(
          settings: settings,
          accounts: [legacyAccount(platform: 'bilibili', userId: '1')],
        ),
      );
      expect(bundle.accounts, isEmpty);
      expect(bundle.network.cacheLimitMebibytes, isNull);
      expect(bundle.network, NetworkSettings.empty);
      expect(bundle.appearance.themeMode, isNull);
      expect(bundle.appearance.locale, isNull);
      expect(bundle.playback.playHistoryLimit, isNull);
      expect(bundle.browseAsLoggedIn, isEmpty);
      expect(bundle.record.summary.unimportedSettings, isEmpty);
      expect(bundle.record.summary.reloginPlatforms, isEmpty);
    });
  });

  test('the snapshot is not modified', () {
    final settings = LegacySettings(playHistoryLimit: 3000);
    final tracks = [legacyTrack(id: 1), legacyTrack(id: 2, sourceId: 'BV1')];
    final playlistIds = [2, 1];
    final snapshot = legacySnapshot(
      tracks: tracks,
      settings: settings,
      playlists: [legacyPlaylist(id: 1, trackIds: playlistIds)],
      history: [legacyHistory(id: 1, sourceId: 'BV1', playedAt: baseTime)],
    );
    convert(snapshot);
    expect(settings.playHistoryLimit, 3000);
    expect(playlistIds, [2, 1]);
    expect(snapshot.tracks.map((t) => t.id), [1, 2]);
  });

  test('an empty snapshot converts to an empty bundle', () {
    final bundle = convert(legacySnapshot());
    expect(bundle.tracks, isEmpty);
    expect(bundle.playlists, isEmpty);
    expect(bundle.history, isEmpty);
    expectBalanced(bundle);
  });
}
