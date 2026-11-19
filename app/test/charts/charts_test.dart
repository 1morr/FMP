import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/charts/charts.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/plugins/plugins.dart';

import '../support/fake_http.dart';
import '../support/fjs.dart';

/// 排行榜與它的快取（ARCHITECTURE〈快取〉、`docs/design/home.html`）：先顯示
/// 快取、超過 1 小時在背景重抓、下拉強制重抓、失敗時留著上次的榜。插件是寫在
/// 這裡的小插件，跑在真的引擎裡，網路換成 [FakeHttp]；資料庫是記憶體裡的
/// drift，同一個資料庫開新的 container 就是重開 App；時鐘是假的。
void main() {
  late Directory logDir;
  late Log log;
  late AppDatabase database;
  late DateTime now;

  /// 每個音源的回應；預設回一份三首的榜，曲名帶著第幾次抓。
  late Map<String, FakeResponse Function()> respond;
  late Map<String, int> fetches;

  setUpAll(loadFjsForTests);
  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_charts_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    database = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 11, 20, 9);
    fetches = {};
    respond = {};
  });
  tearDown(() async {
    await database.close();
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  String manifest(String id, {bool charts = true}) => jsonEncode({
    'id': id,
    'name': id.toUpperCase(),
    'version': '1.0.0',
    'capabilities': [if (charts) 'charts' else 'search'],
    'domains': ['api.example.com'],
    if (charts) 'chartTitle': {'en': '$id chart'},
  });

  /// 向 `https://api.example.com/<id>` 要榜；503 是連不上，429 是限流。
  String plugin(String id) =>
      '''
    export async function charts({ limit }) {
      const res = await host.http.request({ url: 'https://api.example.com/$id' });
      if (res.status === 503) throw new PluginError('network', 'offline');
      if (res.status === 429) throw new PluginError('rate_limited', 'busy');
      return JSON.parse(res.body);
    }
  ''';

  FakeResponse chartOf(String id) {
    final n = fetches[id]!;
    return FakeResponse.json({
      'tracks': [
        for (var i = 1; i <= 3; i++)
          {'id': '$id-$i', 'title': '$id #$i (fetch $n)', 'author': 'A'},
      ],
    });
  }

  FakeResponse handle(RequestOptions request) {
    final id = request.uri.pathSegments.single;
    fetches[id] = (fetches[id] ?? 0) + 1;
    return (respond[id] ?? () => chartOf(id))();
  }

  /// 開 App：每次都是新的宿主與 container，資料庫沿用。
  ProviderContainer open(
    List<String> ids, {
    AppDatabase? db,
    bool withDatabase = true,
    List<String> without = const [],
  }) {
    final host = PluginHost(
      bundles: [
        for (final id in ids)
          PluginBundle(manifest: manifest(id), code: plugin(id)),
        for (final id in without)
          PluginBundle(manifest: manifest(id, charts: false), code: ''),
      ],
      log: log,
      httpAdapter: FakeHttp(handle),
    );
    addTearDown(host.close);
    final container = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(log),
        pluginHostProvider.overrideWith((_) => host),
        if (withDatabase) appDatabaseProvider.overrideWithValue(db ?? database),
        chartsClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 讀 [chartsProvider]（首頁打開），等抓榜與存檔都做完。
  Future<ChartsState> show(ProviderContainer c) async {
    c.listen(chartsProvider, (_, _) {});
    await c.read(chartsProvider.notifier).refreshStale();
    return c.read(chartsProvider);
  }

  List<String>? titles(ChartsState state, [int source = 0]) => [
    for (final t in state.sources[source].chart?.tracks ?? const []) t.title,
  ];

  test('the first time fetches the top 10 of every source that declares '
      'charts, in plugin order, and saves them', () async {
    final state = await show(open(['one', 'two'], without: ['plain']));

    expect(state.sources.map((s) => s.manifest.id), ['one', 'two']);
    expect(titles(state, 0), [
      'one #1 (fetch 1)',
      'one #2 (fetch 1)',
      'one #3 (fetch 1)',
    ]);
    expect(state.sources[0].chart!.fetchedAt, now);
    expect(state.sources[1].error, isNull);
    expect(fetches, {'one': 1, 'two': 1});
  });

  test(
    'reopening within an hour shows the saved chart without fetching',
    () async {
      await show(open(['one']));
      now = now.add(const Duration(minutes: 59));

      final state = await show(open(['one']));

      expect(titles(state), contains('one #1 (fetch 1)'));
      expect(fetches['one'], 1);
    },
  );

  test('reopening after more than an hour shows the saved chart first, then '
      'fetches it again in the background', () async {
    await show(open(['one']));
    now = now.add(const Duration(minutes: 61));
    final c = open(['one']);
    c.listen(chartsProvider, (_, _) {});

    final refreshed = c.read(chartsProvider.notifier).refreshStale();
    // 抓的途中畫面已經有上次的榜。
    await Future.doWhile(() async {
      await Future<void>.delayed(Duration.zero);
      return c.read(chartsProvider).sources.single.chart == null;
    });
    final during = c.read(chartsProvider).sources.single;
    expect(during.chart!.tracks.first.title, 'one #1 (fetch 1)');
    expect(during.loading, isTrue);

    await refreshed;
    final after = c.read(chartsProvider).sources.single;
    expect(after.chart!.tracks.first.title, 'one #1 (fetch 2)');
    expect(after.chart!.fetchedAt, now);
    expect(after.loading, isFalse);
  });

  test('staying on the home page past the hour fetches again the next time '
      'it shows', () async {
    final c = open(['one']);
    await show(c);
    now = now.add(const Duration(minutes: 30));
    await c.read(chartsProvider.notifier).refreshStale();
    expect(fetches['one'], 1);

    now = now.add(const Duration(minutes: 31));
    await c.read(chartsProvider.notifier).refreshStale();
    expect(fetches['one'], 2);
  });

  test('pulling to refresh fetches every source even when the chart is '
      'fresh', () async {
    final c = open(['one', 'two']);
    await show(c);

    await c.read(chartsProvider.notifier).refresh();

    expect(fetches, {'one': 2, 'two': 2});
    expect(titles(c.read(chartsProvider)), contains('one #1 (fetch 2)'));
  });

  test('offline with a saved chart keeps showing it and says when it was '
      'fetched', () async {
    await show(open(['one']));
    final fetchedAt = now;
    now = now.add(const Duration(hours: 3));
    respond['one'] = () => const FakeResponse(503);

    final source = (await show(open(['one']))).sources.single;

    expect(source.chart!.tracks.first.title, 'one #1 (fetch 1)');
    expect(source.chart!.fetchedAt, fetchedAt);
    expect(source.error, isA<NetworkError>());
    expect(source.loading, isFalse);
  });

  test('a failure without a saved chart has no chart; retrying asks only '
      'that source again', () async {
    respond['busy'] = () => const FakeResponse(429);
    final c = open(['one', 'busy']);
    final state = await show(c);
    expect(state.sources[1].chart, isNull);
    expect(state.sources[1].error, isA<RateLimited>());
    expect(state.neverLoadedOffline, isFalse);

    respond.remove('busy');
    await c.read(chartsProvider.notifier).refresh(only: 'busy');

    final retried = c.read(chartsProvider).sources[1];
    expect(retried.error, isNull);
    expect(retried.chart!.tracks, hasLength(3));
    expect(fetches, {'one': 1, 'busy': 2});
  });

  test('never loaded and offline everywhere is one combined failure', () async {
    respond['one'] = () => const FakeResponse(503);
    respond['two'] = () => const FakeResponse(503);

    final state = await show(open(['one', 'two']));

    expect(state.neverLoadedOffline, isTrue);
  });

  test('asked while the plugins are still loading, it fetches once they '
      'load', () async {
    final loaded = Completer<PluginHost>();
    final c = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(log),
        pluginHostProvider.overrideWith((_) => loaded.future),
        appDatabaseProvider.overrideWithValue(database),
        chartsClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    c.listen(chartsProvider, (_, _) {});
    await c.read(chartsProvider.notifier).refreshStale();
    expect(c.read(chartsProvider).starting, isTrue);

    final host = PluginHost(
      bundles: [PluginBundle(manifest: manifest('one'), code: plugin('one'))],
      log: log,
      httpAdapter: FakeHttp(handle),
    );
    addTearDown(host.close);
    loaded.complete(host);
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return c.read(chartsProvider).sources.firstOrNull?.chart == null;
    }).timeout(const Duration(seconds: 5));

    expect(fetches['one'], 1);
  });

  test('without a database the chart lives only in memory', () async {
    final c = open(['one'], withDatabase: false);
    final state = await show(c);
    expect(state.sources.single.chart!.tracks, hasLength(3));

    await show(open(['one']));
    expect(fetches['one'], 2);
  });
}
