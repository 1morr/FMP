import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/matching/matching.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/match_results_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/library/external_import.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

import '../playback/fake_source_plugin.dart';
import '../support/pump_until.dart';
import 'fake_import_plugin.dart';
import 'library_harness.dart';

// 外部匯入（M4 design §8.4、ADR 0019 §決定 5，上層 implement.md § 19 的測試）：來源是假的
// `importPlaylist` 插件（`spotify`，沒有 `resolveStream`），目標是能搜能播的假插件。

/// 一首外部歌曲：[id] 是外部 id，標題、歌手、時長照給的。
typedef Song = (String id, String title, String artist, int seconds);

RemotePlaylistItem _item(Song song, {String sourceTypeId = 'spotify'}) =>
    RemotePlaylistItem(
      track: TrackSummary(
        sourceTypeId: sourceTypeId,
        sourceId: song.$1,
        title: song.$2,
        uploader: song.$3,
        duration: Duration(seconds: song.$4),
      ),
    );

PlaylistPage _page(
  List<Song> songs, {
  String? cursor,
  bool truncated = false,
  String sourceTypeId = 'spotify',
}) => PlaylistPage(
  playlist: const RemotePlaylist(title: 'Road trip'),
  items: [for (final song in songs) _item(song, sourceTypeId: sourceTypeId)],
  cursor: cursor,
  truncated: truncated,
);

/// 搜尋結果的一首（[plugin] 的曲目）。
TrackSummary _hit(
  String plugin,
  String id,
  String title,
  String uploader,
  int seconds,
) => TrackSummary(
  sourceTypeId: plugin,
  sourceId: id,
  title: title,
  uploader: uploader,
  duration: Duration(seconds: seconds),
);

const _one = ('s1', 'Blue Sky', 'Alice / Bob', 200);
const _two = ('s2', 'Green Field', 'Carol', 180);
const _three = ('s3', 'Red Moon', 'Dave', 240);

/// 能搜能播的目標：[results] 依關鍵字回第一頁。
FakeSourcePlugin _target(
  String id,
  FutureOr<List<TrackSummary>> Function(String keyword) results,
) => FakeSourcePlugin(
  (_) => const [],
  id: id,
  name: 'Target $id',
  onSearch: (query) async =>
      SearchPage(items: await results(query.keyword), hasMore: false),
);

/// 對每個關鍵字都回「同名同歌手同時長」的那一首（[_one]、[_two]、[_three] 都匹配得到）。
List<TrackSummary> _exact(String plugin, String keyword) => [
  for (final song in [_one, _two, _three])
    if (keyword.startsWith(song.$2))
      _hit(
        plugin,
        '$plugin-${song.$1}',
        song.$2,
        firstArtist(song.$3)!,
        song.$4,
      ),
];

void main() {
  late LibraryEnv env;
  late FakeImportPlugin source;

  Future<void> start(
    List<SourcePlugin> targets, {
    FutureOr<PlaylistPage> Function(PlaylistPageQuery query)? onPage,
    FakeImportPlugin? from,
  }) async {
    source =
        from ??
        FakeImportPlugin(
          id: 'spotify',
          resolveStream: false,
          onPage: onPage ?? (_) => _page([_one, _two, _three]),
        );
    env = await LibraryEnv.open(plugins: [source, ...targets]);
  }

  Future<ExternalImport> open([String playlistId = 'remote-1']) async {
    final job = await env.container
        .read(externalImportsProvider)
        .open(source.manifest.id, playlistId);
    addTearDown(job.dispose);
    return job;
  }

  /// 讀完、開始、等到每一首都有結果。
  Future<ExternalImport> matched() async {
    final job = await open();
    await job.read();
    job.start();
    await _settled(job);
    return job;
  }

  Future<Map<String, MatchResult>> stored([
    List<String> ids = const ['s1', 's2', 's3'],
  ]) => env.container.read(matchResultsRepositoryProvider).find('spotify', ids);

  test(
    'reads every page and shows the progress, then waits to start',
    () async {
      final a = _target('a', (k) => _exact('a', k));
      await start(
        [a],
        onPage: (query) => switch (query.cursor) {
          null => _page([_one], cursor: '1'),
          '1' => _page([_two], cursor: '2'),
          _ => _page([_three]),
        },
      );
      final job = await open();
      final counts = <int>[];
      job.addListener(() => counts.add(job.readCount));

      await job.read();

      expect(source.pageQueries.map((q) => q.cursor), [null, '1', '2']);
      expect(counts, containsAllInOrder([1, 2, 3]));
      expect(job.phase, ExternalImportPhase.ready);
      expect(job.title, 'Road trip');
      expect(
        [for (final row in job.rows) row.title],
        ['Blue Sky', 'Green Field', 'Red Moon'],
      );
      expect(job.searchCount, 3);
      expect(a.searches, isEmpty, reason: 'nothing is searched before start');
    },
  );

  test('the keyword is the original title and the first artist', () async {
    final a = _target('a', (k) => _exact('a', k));
    await start([a]);

    await matched();

    expect(a.searches.map((q) => q.keyword), [
      'Blue Sky Alice',
      'Green Field Carol',
      'Red Moon Dave',
    ]);
    expect(a.searches.map((q) => q.page), everyElement(1));
  });

  test('a stored match is used without searching, with the choices and '
      'exclusions made before', () async {
    final a = _target('a', (k) => _exact('a', k));
    await start([a]);
    final picked = TrackInfo(
      sourceTypeId: 'a',
      sourceId: 'picked',
      title: 'Picked by hand',
    );
    await env.repository.createFromMatches(
      name: 'Earlier',
      tracks: [picked],
      matches: [
        MatchResult(
          originPluginId: 'spotify',
          originId: 's1',
          title: 'Blue Sky',
          selected: picked,
          userSelected: true,
        ),
        const MatchResult(
          originPluginId: 'spotify',
          originId: 's2',
          title: 'Green Field',
          userSelected: true,
        ),
      ],
    );

    final job = await open();
    await job.read();
    expect(job.reusedCount, 2);
    expect(job.searchCount, 1);
    job.start();
    await _settled(job);

    expect(a.searches.map((q) => q.keyword), ['Red Moon Dave']);
    final [one, two, three] = job.rows;
    expect(one.match, isA<MatchReused>());
    expect(one.chosen, picked);
    expect(two.excluded, isTrue);
    expect(two.chosen, isNull);
    expect(three.chosen?.sourceId, 'a-s3');
  });

  test('candidates of every target are merged and the best 5 kept; the first '
      'is selected only past the threshold', () async {
    final a = _target(
      'a',
      (k) => [
        _hit('a', 'a1', 'Blue Sky', 'Alice', 200),
        _hit('a', 'a2', 'Blue Sky (Live)', 'Alice', 205),
        _hit('a', 'a3', 'Something else', 'Zed', 200),
        _hit('a', 'a4', 'Blue', 'Nobody', 200),
      ],
    );
    final b = _target(
      'b',
      (k) => [
        _hit('b', 'b1', 'Blue Sky', 'Alice Official', 201),
        _hit('b', 'b2', 'Blue Skies', 'Alice', 200),
        _hit('b', 'b3', 'Unrelated', 'Who', 200),
      ],
    );
    await start([
      a,
      b,
    ], onPage: (_) => _page([_one, ('s9', 'Nothing alike', 'Nobody', 200)]));

    final job = await matched();

    const query = MatchQuery(
      title: 'Blue Sky',
      artist: 'Alice / Bob',
      duration: Duration(seconds: 200),
    );
    final hits = [
      ...(await a.onSearch!(SearchQuery(keyword: 'x'))).items,
      ...(await b.onSearch!(SearchQuery(keyword: 'x'))).items,
    ];
    final all =
        [
          for (final (index, hit) in hits.indexed)
            (
              hit.sourceId,
              index,
              score(
                query,
                MatchCandidate(
                  title: hit.title,
                  uploader: hit.uploader,
                  duration: hit.duration,
                ),
              ).total,
            ),
        ]..sort((x, y) {
          final byScore = y.$3.compareTo(x.$3);
          return byScore != 0 ? byScore : x.$2.compareTo(y.$2);
        });
    final found = job.rows.first.match as MatchFound;
    expect(found.candidates, hasLength(5));
    expect(
      [for (final c in found.candidates) c.track.sourceId],
      [for (final entry in all.take(5)) entry.$1],
      reason: 'one list over both targets, not five per target',
    );
    expect(
      {for (final c in found.candidates) c.track.sourceTypeId},
      {'a', 'b'},
    );
    expect(found.selected, same(found.candidates.first));
    expect(found.selected!.score.total, greaterThanOrEqualTo(0.6));

    // 第二首每個候選都沒過門檻：有候選、沒有選定（匹配失敗）。
    final unmatched = job.rows.last.match as MatchFound;
    expect(unmatched.candidates, isNotEmpty);
    expect(unmatched.candidates.first.score.total, lessThan(0.6));
    expect(unmatched.selected, isNull);
    expect(job.rows.last.chosen, isNull);
  });

  test('equal scores keep the order of the targets', () async {
    TrackSummary same(String plugin) =>
        _hit(plugin, '$plugin-1', 'Blue Sky', 'Alice', 200);
    final a = _target('a', (_) => [same('a')]);
    final b = _target('b', (_) => [same('b')]);
    await start([a, b], onPage: (_) => _page([_one]));
    await env.container.read(sourceSettingsRepositoryProvider).setMatchRanks([
      'b',
      'a',
    ]);

    final job = await matched();

    expect(job.targets, ['b', 'a']);
    final found = job.rows.single.match as MatchFound;
    expect(
      [for (final c in found.candidates) c.track.sourceTypeId],
      ['b', 'a'],
    );
  });

  test('a failed search marks that song and the batch goes on', () async {
    final a = _target(
      'a',
      (k) => k.startsWith('Green')
          ? throw RateLimited(pluginId: 'a')
          : _exact('a', k),
    );
    await start([a]);

    final job = await matched();

    final [one, two, three] = job.rows;
    expect(one.chosen?.sourceId, 'a-s1');
    expect(two.match, isA<MatchSearchFailed>());
    expect((two.match as MatchSearchFailed).error, isA<RateLimited>());
    expect(three.chosen?.sourceId, 'a-s3');
    expect(job.phase, ExternalImportPhase.done);

    // 可以重搜。
    a.searches.clear();
    await job.research(two);
    expect(a.searches.single.keyword, 'Green Field Carol');
    expect(two.match, isA<MatchSearchFailed>(), reason: 'still failing');
  });

  test('one target failing still uses the others', () async {
    final a = _target('a', (_) => throw NetworkError(pluginId: 'a'));
    final b = _target('b', (k) => _exact('b', k));
    await start([a, b], onPage: (_) => _page([_one]));

    final job = await matched();

    expect(job.rows.single.chosen?.sourceId, 'b-s1');
  });

  test('a page that fails stops before matching; retry reads again', () async {
    final a = _target('a', (k) => _exact('a', k));
    var fail = true;
    await start(
      [a],
      onPage: (query) => switch (query.cursor) {
        null => _page([_one], cursor: '1'),
        _ when fail => throw NetworkError(pluginId: 'spotify'),
        _ => _page([_two]),
      },
    );
    final job = await open();

    await job.read();

    expect(job.phase, ExternalImportPhase.readFailed);
    expect(job.readError, isA<NetworkError>());
    expect(job.rows, isEmpty);
    expect(() => job.start(), throwsStateError);
    expect(a.searches, isEmpty);

    fail = false;
    await job.read();
    expect(job.phase, ExternalImportPhase.ready);
    expect(job.rows, hasLength(2));
  });

  test('a cursor that repeats is a failed read, not an endless one', () async {
    await start([
      _target('a', (k) => _exact('a', k)),
    ], onPage: (_) => _page([_one], cursor: 'again'));
    final job = await open();

    await job.read();

    expect(job.phase, ExternalImportPhase.readFailed);
    expect(source.pageQueries, hasLength(2));
  });

  test('a truncated last page is matched as usual and remembered', () async {
    final a = _target('a', (k) => _exact('a', k));
    await start(
      [a],
      onPage: (query) => query.cursor == null
          ? _page([_one], cursor: '1')
          : _page([_two], truncated: true),
    );

    final job = await matched();

    expect(job.truncated, isTrue);
    expect(job.phase, ExternalImportPhase.done);
    expect(
      [for (final row in job.rows) row.chosen?.sourceId],
      ['a-s1', 'a-s2'],
    );
  });

  test('closing the preview drops the searches in flight and writes '
      'nothing', () async {
    final hold = Completer<List<TrackSummary>>();
    final a = _target('a', (k) => k.startsWith('Green') ? hold.future : []);
    await start([a]);
    final job = await open();
    await job.read();
    job.start();
    await pumpUntil(() => a.searches.length == 2);

    job.dispose();
    hold.complete(_exact('a', 'Green Field'));
    await settle();

    expect(a.searches, hasLength(2), reason: 'no song after the close');
    expect(await env.repository.watchAll().first, isEmpty);
    expect(await stored(), isEmpty);
  });

  test('confirming writes the playlist, the matches and the origins in one '
      'go; unmatched and excluded songs stay out', () async {
    final a = _target(
      'a',
      (k) => switch (k) {
        'Green Field Carol' => throw RateLimited(pluginId: 'a'),
        'Red Moon Dave' => [_hit('a', 'x', 'Nothing alike', 'Nobody', 240)],
        _ => _exact('a', k),
      },
    );
    await start(
      [a],
      onPage: (_) =>
          _page([_one, _two, _three, ('s4', 'Blue Sky', 'Alice', 200), _one]),
    );
    final job = await matched();
    final s4 = job.rows[3];
    job.setExcluded(s4, excluded: true);
    expect(job.chosenCount, 2, reason: 's1 twice');
    expect(job.canCreate, isTrue);

    final id = await job.confirm();

    final playlist = (await env.repository.find(id))!;
    expect(playlist.kind, PlaylistKind.local);
    expect(playlist.name, 'Road trip');
    expect(await env.repository.remote(id), isNull);
    expect(
      [for (final e in await env.repository.entries(id)) e.track.key],
      [
        for (final _ in [1, 2])
          TrackInfo(sourceTypeId: 'a', sourceId: 'a-s1', title: '').key,
      ],
    );
    final results = await stored(['s1', 's2', 's3', 's4']);
    expect(
      results.keys,
      unorderedEquals(['s1', 's3', 's4']),
      reason: 'the failed search is searched again next time',
    );
    expect(results['s1']!.selected?.sourceId, 'a-s1');
    expect(results['s1']!.score, greaterThan(0.6));
    expect(results['s1']!.userSelected, isFalse);
    expect(results['s1']!.artists, 'Alice / Bob');
    expect(results['s3']!.selected, isNull);
    expect(results['s3']!.userSelected, isFalse, reason: 'unmatched');
    expect(results['s4']!.selected, isNull);
    expect(results['s4']!.userSelected, isTrue, reason: 'excluded');
    final origins = await env.database
        .customSelect(
          'SELECT track_key, origin_plugin_id, origin_id FROM track_origins',
        )
        .get();
    expect(
      [for (final row in origins) row.data],
      [
        {
          'track_key': 'a:a-s1',
          'origin_plugin_id': 'spotify',
          'origin_id': 's1',
        },
      ],
    );
  });

  test('a picked candidate is stored as the user\'s choice and kept when the '
      'targets change', () async {
    final a = _target(
      'a',
      (k) => [
        ..._exact('a', k),
        _hit('a', 'alt', 'Blue Sky (Cover)', 'Someone', 200),
      ],
    );
    final b = _target('b', (k) => _exact('b', k));
    await start([a, b], onPage: (_) => _page([_one, _two]));
    final job = await matched();
    final one = job.rows.first;
    final found = one.match as MatchFound;
    final alt = found.candidates.firstWhere((c) => c.track.sourceId == 'alt');

    job.select(one, alt);
    expect(one.chosen?.sourceId, 'alt');
    a.searches.clear();
    b.searches.clear();
    job.setTargets(['b']);
    await _settled(job);

    expect(one.chosen?.sourceId, 'alt', reason: 'picked by hand');
    expect(job.rows.last.chosen?.sourceId, 'b-s2', reason: 'searched again');
    expect(a.searches, isEmpty);
    expect(b.searches.map((q) => q.keyword), ['Green Field Carol']);

    await job.confirm();
    final results = await stored(['s1']);
    expect(results['s1']!.userSelected, isTrue);
    expect(results['s1']!.selected?.sourceId, 'alt');
  });

  test('a search with your own keyword uses the same scoring and is not '
      'redone when the targets change', () async {
    final a = _target(
      'a',
      (k) => k == 'my words' ? _exact('a', 'Blue Sky') : [],
    );
    final b = _target('b', (_) => []);
    await start([a, b], onPage: (_) => _page([_one]));
    final job = await matched();
    final one = job.rows.single;
    expect(one.chosen, isNull);

    await job.research(one, keyword: '  my words ');

    expect(a.searches.last.keyword, 'my words');
    final found = one.match as MatchFound;
    expect(found.selected?.track.sourceId, 'a-s1');
    expect(
      found.selected!.score.total,
      score(
        const MatchQuery(
          title: 'Blue Sky',
          artist: 'Alice / Bob',
          duration: Duration(seconds: 200),
        ),
        const MatchCandidate(
          title: 'Blue Sky',
          uploader: 'Alice',
          duration: Duration(seconds: 200),
        ),
      ).total,
      reason: 'same score as an automatic match',
    );
    a.searches.clear();
    job.setTargets(['a']);
    await _settled(job);
    expect(a.searches, isEmpty);
  });

  test('changing the targets for this import does not write the '
      'settings', () async {
    final a = _target('a', (k) => _exact('a', k));
    final b = _target('b', (k) => _exact('b', k));
    await start([a, b]);
    final job = await matched();

    job.setTargets(['b']);
    await _settled(job);

    expect(job.targets, ['b']);
    expect(
      await env.container
          .read(sourceSettingsRepositoryProvider)
          .watchMatchTargets()
          .first,
      isEmpty,
    );
    expect(() => job.setTargets(const []), throwsArgumentError);
  });

  group('the default targets', () {
    test('every enabled plugin that searches and plays, by match_rank, then '
        'the plugin list; unchecked ones are left out', () async {
      final a = _target('a', (k) => []);
      final b = _target('b', (k) => []);
      final c = _target('c', (k) => []);
      final searchOnly = FakeImportPlugin(id: 'meta', resolveStream: false);
      await start([a, b, c, searchOnly]);
      final settings = env.container.read(sourceSettingsRepositoryProvider);
      await settings.setMatchRanks(['c']);
      await settings.setMatchTarget('b', target: false);

      final job = await open();

      expect([for (final p in job.available) p.manifest.id], ['c', 'a', 'b']);
      expect(job.targets, ['c', 'a']);
      expect(job.pairing, isFalse);
    });

    test('pairing a playable source leaves the source out by default and '
        'never writes playlist_remote', () async {
      final b = _target('b', (k) => _exact('b', k));
      final playable = FakeImportPlugin(
        id: 'video',
        onPage: (_) => _page([_one], sourceTypeId: 'video'),
        onSearch: (query) =>
            SearchPage(items: _exact('video', query.keyword), hasMore: false),
      );
      await start([b], from: playable);

      final job = await open();

      expect(job.pairing, isTrue);
      expect([for (final p in job.available) p.manifest.id], ['video', 'b']);
      expect(job.targets, ['b']);
      await job.read();
      job.start();
      await _settled(job);
      expect(playable.searches, isEmpty);
      final id = await job.confirm();
      expect(await env.repository.remote(id), isNull);
      expect((await env.repository.find(id))!.kind, PlaylistKind.local);
      final results = await env.container
          .read(matchResultsRepositoryProvider)
          .find('video', ['s1']);
      expect(results['s1']!.selected?.sourceId, 'b-s1');
    });

    test('a source that is not a plugin with importPlaylist is '
        'unsupported', () async {
      await start([_target('a', (k) => [])]);

      await expectLater(
        env.container.read(externalImportsProvider).open('a', 'x'),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  test('part songs of one video are told apart by cid', () async {
    TrackSummary part(int cid) => TrackSummary(
      sourceTypeId: 'video',
      sourceId: 'BV1',
      cid: cid,
      title: 'Part $cid',
      partIndex: cid,
      parentTitle: 'Video',
    );
    await start(
      [_target('a', (k) => [])],
      onPage: (_) => PlaylistPage(
        playlist: const RemotePlaylist(title: 'Parts'),
        items: [
          RemotePlaylistItem(track: part(1)),
          RemotePlaylistItem(track: part(2)),
        ],
      ),
    );
    final job = await open();
    await job.read();

    expect([for (final song in job.songs) song.originId], ['BV1:1', 'BV1:2']);
  });

  // 一千首（三個目標）以假插件量一次匹配的耗時：只量宿主這邊（讀頁、評分、記憶體狀態），
  // 真的音源受網路與每插件限流控制（implement.md 的風險）。
  test('matching a playlist of 1,000 songs', () async {
    final songs = [
      for (var i = 0; i < 1000; i++)
        ('t$i', 'Song number $i', 'Artist $i / Guest', 180 + i % 60),
    ];
    List<TrackSummary> hits(String plugin, String keyword) => [
      for (var n = 0; n < 20; n++)
        _hit(
          plugin,
          '$plugin-$keyword-$n',
          '$keyword take $n',
          'Channel $n',
          200,
        ),
    ];
    final targets = [
      for (final id in ['a', 'b', 'c']) _target(id, (k) => hits(id, k)),
    ];
    await start(
      targets,
      onPage: (query) {
        final start = int.parse(query.cursor ?? '0');
        final end = start + 100;
        return _page(
          songs.sublist(start, end),
          cursor: end < songs.length ? '$end' : null,
        );
      },
    );
    final job = await open();
    final watch = Stopwatch()..start();
    await job.read();
    final read = watch.elapsedMilliseconds;
    job.start();
    await _settled(job, maxRounds: 100000);
    final matching = watch.elapsedMilliseconds - read;
    await job.confirm();
    final total = watch.elapsedMilliseconds;

    // 量測結果印在測試輸出（同 queue_repository_test 的一萬首），記在 PR 描述。
    // ignore: avoid_print
    print(
      '1,000 songs x 3 targets (20 hits each): read $read ms, '
      'match $matching ms, confirm ${total - read - matching} ms',
    );
    expect(job.rows, hasLength(1000));
    expect(targets.every((t) => t.searches.length == 1000), isTrue);
  });

  // 審查與實機的修正（M4 PR 19）。
  group('after review', () {
    Future<void> storeEarlier(
      List<MatchResult> matches,
      List<TrackInfo> tracks,
    ) => env.repository.createFromMatches(
      name: 'Earlier',
      tracks: tracks,
      matches: matches,
    );

    test('a stored exclusion that is included again is no longer stored as '
        'excluded', () async {
      final a = _target('a', (k) => _exact('a', k));
      await start([a], onPage: (_) => _page([_one, _two]));
      final earlier = TrackInfo(
        sourceTypeId: 'a',
        sourceId: 'a-s1',
        title: 'Blue Sky',
      );
      await storeEarlier(
        [
          MatchResult(
            originPluginId: 'spotify',
            originId: 's1',
            title: 'Blue Sky',
            selected: earlier,
          ),
          const MatchResult(
            originPluginId: 'spotify',
            originId: 's2',
            title: 'Green Field',
            userSelected: true,
          ),
        ],
        [earlier],
      );
      final job = await open();
      await job.read();
      final two = job.rows.last;
      expect(two.excluded, isTrue);
      expect(two.picked, isFalse, reason: 'excluded is not a pick');

      job.setExcluded(two, excluded: false);
      await job.confirm();

      final results = await stored(['s2']);
      expect(results['s2']!.selected, isNull);
      expect(
        results['s2']!.userSelected,
        isFalse,
        reason: 'back to a plain failed match, not an exclusion',
      );
    });

    test('a search with your own words in flight is not replaced by a target '
        'change', () async {
      final hold = Completer<List<TrackSummary>>();
      final a = _target(
        'a',
        (k) => k == 'my words' ? hold.future : _exact('a', k),
      );
      final b = _target('b', (k) => _exact('b', k));
      await start([a, b], onPage: (_) => _page([_one]));
      final job = await matched();
      final one = job.rows.single;

      final research = job.research(one, keyword: 'my words');
      await pumpUntil(() => a.searches.last.keyword == 'my words');
      b.searches.clear();
      job.setTargets(['a']);
      hold.complete([_hit('a', 'mine', 'Blue Sky', 'Alice', 200)]);
      await research;
      await _settled(job);

      expect(one.chosen?.sourceId, 'mine');
      expect(
        a.searches.where((q) => q.keyword == 'Blue Sky Alice'),
        hasLength(1),
        reason: 'only the first, automatic search',
      );
    });

    test('a created import cannot be created again; a failed one can be '
        'retried', () async {
      final a = _target('a', (k) => _exact('a', k));
      await start([a], onPage: (_) => _page([_one]));
      final job = await matched();
      // 第一次寫入失敗（觸發器擋住 playlists 的插入）。
      await env.database.customStatement(
        'CREATE TRIGGER fail_playlists BEFORE INSERT ON playlists '
        "BEGIN SELECT RAISE(ABORT, 'test'); END",
      );

      await expectLater(job.confirm(), throwsA(isA<AppError>()));
      expect(job.canCreate, isTrue, reason: 'can retry');
      await env.database.customStatement('DROP TRIGGER fail_playlists');

      await job.confirm();
      expect(job.created, isTrue);
      expect(job.canCreate, isFalse);
      await expectLater(job.confirm(), throwsStateError);
      expect(await env.repository.watchAll().first, hasLength(1));
    });

    test('an error that is not the plugin marks that song as failed and the '
        'batch goes on', () async {
      final a = _target('a', (k) => _exact('a', k));
      // 標題只有空白、沒有歌手：預設關鍵字是空的，`SearchQuery` 丟 ArgumentError。
      await start(
        [a],
        onPage: (_) => PlaylistPage(
          playlist: const RemotePlaylist(title: 'Road trip'),
          items: [
            const RemotePlaylistItem(
              track: TrackSummary(
                sourceTypeId: 'spotify',
                sourceId: 'blank',
                title: '   ',
              ),
            ),
            _item(_two),
          ],
        ),
      );

      final job = await matched();

      expect(job.rows.first.match, isA<MatchSearchFailed>());
      expect(job.rows.last.chosen?.sourceId, 'a-s2');
      expect(job.phase, ExternalImportPhase.done);
    });

    test('when every song uses an earlier match it is done without '
        'starting, and nothing has been touched', () async {
      final a = _target('a', (k) => _exact('a', k));
      await start([a], onPage: (_) => _page([_one, _one]));
      final earlier = TrackInfo(
        sourceTypeId: 'a',
        sourceId: 'a-s1',
        title: 'Blue Sky',
      );
      await storeEarlier(
        [
          MatchResult(
            originPluginId: 'spotify',
            originId: 's1',
            title: 'Blue Sky',
            selected: earlier,
            score: 0.9,
          ),
        ],
        [earlier],
      );

      final job = await open();
      await job.read();

      expect(job.phase, ExternalImportPhase.done);
      expect(job.touched, isFalse);
      expect(job.canCreate, isTrue);
      expect(a.searches, isEmpty);
      expect(() => job.start(), throwsStateError);

      // 臨時改目標照樣重搜沿用的自動結果（決定 6）。
      final b = _target('b', (k) => _exact('b', k));
      await env.setPlugins([source, a, b]);
      final again = await open();
      await again.read();
      expect(again.phase, ExternalImportPhase.done);
      again.setTargets(['b']);
      await _settled(again);
      expect(again.rows.first.chosen?.sourceId, 'b-s1');
      expect(again.touched, isTrue);
    });

    test('starting, picking, excluding and searching again touch it; reading '
        'does not', () async {
      final a = _target('a', (k) => _exact('a', k));
      await start([a]);
      final job = await open();
      await job.read();
      expect(job.touched, isFalse);
      job.setTargets(const []);
      expect(job.touched, isFalse, reason: 'targets before starting');
      job.setTargets(['a']);
      job.start();
      expect(job.touched, isTrue);
    });
  });
}

/// 等到 [job] 的每一首都有結果（插件與資料庫的非同步）。
Future<void> _settled(ExternalImport job, {int maxRounds = 200}) => pumpUntil(
  () => job.phase == ExternalImportPhase.done,
  maxRounds: maxRounds,
  reason: 'every song has a result',
);
