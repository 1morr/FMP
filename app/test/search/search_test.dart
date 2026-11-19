import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/search/search.dart';
import 'package:fmp/search/search_history.dart';

import '../support/fjs.dart';

/// 跨插件搜尋（`docs/design/search.html`〈錯誤與空結果〉、ADR 0039）：每個
/// 音源各自搜、各自失敗與重試，排序與分頁。插件是寫在這裡的小插件，跑在真
/// 的引擎裡；搜尋紀錄沒有資料庫，只在記憶體。
void main() {
  late Directory logDir;
  late Log log;

  setUpAll(loadFjsForTests);
  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_search_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
  });
  tearDown(() async {
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  String manifest(String id, {List<String>? sorts}) => jsonEncode({
    'id': id,
    'name': id.toUpperCase(),
    'version': '1.0.0',
    'capabilities': ['search'],
    'domains': ['api.example.com'],
    'searchSorts': ?sorts,
  });

  /// 每頁兩首、共 [pages] 頁；曲名寫著查詢、排序與頁碼。
  String paged(int pages) =>
      '''
    export async function search({ query, sort, page = 1 }) {
      return {
        tracks: [1, 2].map((n) => ({
          id: page + '-' + n,
          title: query + ' ' + (sort ?? '-') + ' p' + page + '#' + n,
          author: 'A',
        })),
        isEnd: page >= $pages,
      };
    }
  ''';

  /// 每次呼叫輪流：先失敗（[code]），之後成功。
  String flaky(String code) =>
      '''
    let calls = 0;
    export async function search({ query }) {
      calls += 1;
      if (calls === 1) throw new PluginError('$code');
      return { tracks: [{ id: 'f', title: query + ' again', author: 'B' }] };
    }
  ''';

  Future<ProviderContainer> start(List<PluginBundle> bundles) async {
    final host = PluginHost(bundles: bundles, log: log);
    addTearDown(host.close);
    final container = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(log),
        pluginHostProvider.overrideWith((_) => host),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  List<String> titles(ProviderContainer c) => [
    for (final t in c.read(searchProvider)!.tracks) t.title,
  ];

  test('each source searches on its own; one failing does not hide the '
      'others, and a retry asks only that one again', () async {
    final c = await start([
      PluginBundle(manifest: manifest('songs'), code: paged(1)),
      PluginBundle(manifest: manifest('busy'), code: flaky('rate_limited')),
    ]);
    final search = c.read(searchProvider.notifier);

    await search.search('夜');
    final state = c.read(searchProvider)!;
    expect(titles(c), ['夜 - p1#1', '夜 - p1#2']);
    expect(state.sources.last.error, isA<RateLimited>());
    expect(nothingFoundIn(state.sources), isFalse);

    search.retry('busy');
    await _settle(c);
    expect(c.read(searchProvider)!.sources.last.error, isNull);
    expect(titles(c), contains('夜 again'));
    expect(titles(c).where((t) => t.startsWith('夜 -')), hasLength(2));
  });

  test('loading more appends the next page until the plugin says it is the '
      'last one', () async {
    final c = await start([
      PluginBundle(manifest: manifest('songs'), code: paged(2)),
    ]);
    final search = c.read(searchProvider.notifier);
    await search.search('夜');

    search.loadMore();
    await _settle(c);
    expect(titles(c), ['夜 - p1#1', '夜 - p1#2', '夜 - p2#1', '夜 - p2#2']);
    expect(c.read(searchProvider)!.sources.single.isEnd, isTrue);

    search.loadMore();
    await _settle(c);
    expect(titles(c), hasLength(4));
  });

  test('changing the sort searches again with it; the sort stays for the '
      'next search', () async {
    final c = await start([
      PluginBundle(
        manifest: manifest('songs', sorts: ['relevance', 'viewCount']),
        code: paged(1),
      ),
    ]);
    final search = c.read(searchProvider.notifier);
    await search.search('夜');
    expect(titles(c).first, '夜 - p1#1');

    await search.sortBy(SearchSort.viewCount);
    expect(titles(c).first, '夜 viewCount p1#1');

    await search.search('晴');
    expect(titles(c).first, '晴 viewCount p1#1');
  });

  test('a slow earlier search does not overwrite a newer one', () async {
    final c = await start([
      PluginBundle(
        manifest: manifest('slow'),
        code: '''
          export async function search({ query }) {
            if (query === 'old') await new Promise((r) => setTimeout(r, 300));
            return { tracks: [{ id: query, title: query, author: 'A' }] };
          }
        ''',
      ),
    ]);
    final search = c.read(searchProvider.notifier);
    final old = search.search('old');
    await search.search('new');
    await old;
    expect(titles(c), ['new']);
  });

  test('a search goes into the search history', () async {
    final c = await start([
      PluginBundle(manifest: manifest('songs'), code: paged(1)),
    ]);
    await c.read(searchProvider.notifier).search('  夜 ');
    expect(await c.read(searchHistoryProvider.future), ['夜']);
  });

  test('nothing found only when every source succeeded with no tracks', () {
    final empty = SourceResults(
      manifest: PluginManifest.parse(manifest('a')),
      pages: const [[]],
      isEnd: true,
    );
    final failed = SourceResults(
      manifest: PluginManifest.parse(manifest('b')),
      error: const NetworkError(),
    );
    expect(nothingFoundIn([empty]), isTrue);
    expect(nothingFoundIn([empty, failed]), isFalse);
  });

  test('results go round by round, alternating sources, without repeats', () {
    Track t(String plugin, String id) => Track(
      ref: TrackRef(pluginId: plugin, trackId: id),
      title: id,
      author: '',
    );
    SourceResults source(String id, List<List<Track>> pages) => SourceResults(
      manifest: PluginManifest.parse(manifest(id)),
      pages: pages,
    );
    final merged = interleave([
      source('a', [
        [t('a', '1'), t('a', '2'), t('a', '3')],
        [t('a', '4'), t('a', '1')],
      ]),
      source('b', [
        [t('b', '1')],
      ]),
    ]);
    expect(
      [for (final x in merged) '${x.ref}'],
      ['a/1', 'b/1', 'a/2', 'a/3', 'a/4'],
    );
  });

  test(
    'only the sorts some plugin declares are offered, in the host order',
    () {
      expect(
        sortsOf([
          PluginManifest.parse(manifest('a', sorts: ['date', 'relevance'])),
          PluginManifest.parse(manifest('b')),
        ]),
        [SearchSort.relevance, SearchSort.date],
      );
    },
  );
}

/// 等每個音源都不在載入中（引擎在真的時間裡回答）。
Future<void> _settle(ProviderContainer c) async {
  for (var i = 0; i < 200; i++) {
    if (!c.read(searchProvider)!.sources.any((s) => s.loading)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
