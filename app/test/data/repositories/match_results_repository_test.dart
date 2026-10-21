import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/match_results_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';

import '../../support/memory_database.dart';

// 外部匯入的匹配結果（ADR 0033 §決定 1、M4 design §3.1、§8.4）：確認時一個 transaction 寫歌單、
// 曲目、match_results 與 track_origins；再匯入時以（來源插件, 外部 id）讀回。

TrackInfo _track(String id) => TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  title: 'Song $id',
  uploader: 'Uploader $id',
  duration: const Duration(seconds: 200),
);

MatchResult _match(
  String originId, {
  TrackInfo? selected,
  double? score,
  bool userSelected = false,
}) => MatchResult(
  originPluginId: 'spotify',
  originId: originId,
  title: 'Original $originId',
  artists: 'Artist A / Artist B',
  duration: const Duration(seconds: 201),
  selected: selected,
  score: score,
  userSelected: userSelected,
);

void main() {
  late AppDatabase database;
  late PlaylistRepository playlists;
  late MatchResultsRepository results;

  setUp(() {
    database = memoryDatabase();
    playlists = PlaylistRepository(database);
    results = MatchResultsRepository(database);
  });

  test('confirming writes a local playlist, its songs in order, every match '
      'and the origins of the selected songs', () async {
    final id = await playlists.createFromMatches(
      name: 'Remote title',
      tracks: [_track('b'), _track('a')],
      matches: [
        _match('s1', selected: _track('b'), score: 0.9),
        _match('s2'),
        _match('s3', userSelected: true),
        _match('s4', selected: _track('a'), score: 0.4, userSelected: true),
      ],
    );

    final playlist = (await playlists.find(id))!;
    expect(playlist.kind, PlaylistKind.local);
    expect(playlist.name, 'Remote title');
    expect(await playlists.remote(id), isNull, reason: 'never refreshed');
    expect(
      [for (final e in await playlists.entries(id)) e.track.sourceId],
      ['b', 'a'],
    );
    expect(await results.find('spotify', ['s1', 's2', 's3', 's4', 'missing']), {
      's1': _match('s1', selected: _track('b'), score: 0.9),
      's2': _match('s2'),
      's3': _match('s3', userSelected: true),
      's4': _match('s4', selected: _track('a'), score: 0.4, userSelected: true),
    });
    expect(await results.find('qqmusic', ['s1']), isEmpty);
  });

  test('stored format', () async {
    await playlists.createFromMatches(
      name: 'x',
      tracks: [_track('b')],
      matches: [
        _match('s1', selected: _track('b'), score: 0.75),
        _match('s2'),
      ],
    );

    final rows = await database
        .customSelect(
          'SELECT origin_plugin_id, origin_id, title, artists, duration_ms, '
          'selected_track_key, score, user_selected FROM match_results '
          'ORDER BY origin_id',
        )
        .get();
    expect(
      [for (final row in rows) row.data],
      [
        {
          'origin_plugin_id': 'spotify',
          'origin_id': 's1',
          'title': 'Original s1',
          'artists': 'Artist A / Artist B',
          'duration_ms': 201000,
          'selected_track_key': 'fmp-test:b',
          'score': 0.75,
          'user_selected': 0,
        },
        {
          'origin_plugin_id': 'spotify',
          'origin_id': 's2',
          'title': 'Original s2',
          'artists': 'Artist A / Artist B',
          'duration_ms': 201000,
          'selected_track_key': null,
          'score': null,
          'user_selected': 0,
        },
      ],
    );
    final origins = await database
        .customSelect(
          'SELECT track_key, origin_plugin_id, origin_id FROM track_origins',
        )
        .get();
    expect(
      [for (final row in origins) row.data],
      [
        {
          'track_key': 'fmp-test:b',
          'origin_plugin_id': 'spotify',
          'origin_id': 's1',
        },
      ],
    );
  });

  test(
    'a second import overwrites the stored match of the same song',
    () async {
      await playlists.createFromMatches(
        name: 'first',
        tracks: [_track('a')],
        matches: [_match('s1', selected: _track('a'), score: 0.8)],
      );

      await playlists.createFromMatches(
        name: 'second',
        tracks: [_track('b')],
        matches: [_match('s1', selected: _track('b'), userSelected: true)],
      );

      expect(await results.find('spotify', ['s1']), {
        's1': _match('s1', selected: _track('b'), userSelected: true),
      });
      // 兩張歌單各自留著。
      expect(await playlists.watchAll().first, hasLength(2));
    },
  );

  test('a failing write leaves nothing behind', () async {
    // 選定的曲目不在 tracks 裡：match_results 的外鍵讓整個 transaction 失敗。
    await expectLater(
      playlists.createFromMatches(
        name: 'x',
        tracks: [_track('a')],
        matches: [_match('s1', selected: _track('missing'))],
      ),
      throwsA(anything),
    );

    expect(await playlists.watchAll().first, isEmpty);
    expect(await results.find('spotify', ['s1']), isEmpty);
    final tracks = await database
        .customSelect('SELECT COUNT(*) AS n FROM tracks')
        .getSingle();
    expect(tracks.data['n'], 0);
  });

  test('more ids than one query takes are read in chunks', () async {
    final ids = [for (var i = 0; i < 1200; i++) 's$i'];
    await playlists.createFromMatches(
      name: 'big',
      tracks: const [],
      matches: [for (final id in ids) _match(id)],
    );

    expect((await results.find('spotify', ids)).keys.toSet(), ids.toSet());
  });
}
