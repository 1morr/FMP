import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/charts/chart_cache.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/scheduler/background_scheduler.dart';
import 'package:fmp/ui/format/byte_size.dart';
import 'package:fmp/ui/settings/network_controls.dart';
import 'package:material_ui/material_ui.dart';

import '../../charts/fake_chart_plugin.dart';
import '../../data/cache/cache_harness.dart';
import '../support/shell_harness.dart';

void main() {
  /// 選中的快取上限（MiB）：第一組選項（第二組是電台狀態刷新間隔，第三組是排行刷新間隔）。
  int? selectedLimit(WidgetTester tester) => tester
      .widget<RadioGroup<int>>(find.byType(RadioGroup<int>).first)
      .groupValue;

  /// 選中的電台狀態刷新間隔（分，0 是關閉）。
  int? selectedInterval(WidgetTester tester) => tester
      .widget<RadioGroup<int>>(find.byType(RadioGroup<int>).at(1))
      .groupValue;

  /// 選中的排行刷新間隔（分，0 是關閉）。
  int? selectedChartInterval(WidgetTester tester) => tester
      .widget<RadioGroup<int>>(find.byType(RadioGroup<int>).last)
      .groupValue;

  /// 第 [group] 組選項裡文字是 [text] 的那一項（兩組間隔都有「關閉」）。
  Finder optionIn(int group, String text) => find.descendant(
    of: find.byType(RadioGroup<int>).at(group),
    matching: find.text(text),
  );

  /// 以真的（暫存目錄上的）快取庫開設定頁的「網路」組。
  Future<(ShellHarness, CacheHarness, CacheStore)> openNetwork(
    WidgetTester tester, {
    int artworkBytes = 0,
  }) async {
    final cache = CacheHarness();
    final store = (await tester.runAsync(
      () => cache.open(limitBytes: 1 << 30),
    ))!;
    if (artworkBytes > 0) {
      await tester.runAsync(
        () => put(
          cache.manager(store),
          'https://example.test/a.jpg',
          artworkBytes,
        ),
      );
    }
    final h = ShellHarness(cacheStore: store);
    // 設定頁裡這一組在捲動的欄裡（電台間隔在快取之後，矮的視窗放不下）。
    await h.pumpApp(
      tester,
      const SingleChildScrollView(child: NetworkControls()),
    );
    await h.loadSettings(tester);
    return (h, cache, store);
  }

  /// 等畫面出現 [text]：快取庫在真的事件迴圈上跑（資料庫與檔案）。
  Future<void> waitForText(WidgetTester tester, String text) async {
    for (var i = 0; i < 100 && find.text(text).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('an unset limit shows the platform default and says so', (
    tester,
  ) async {
    await openNetwork(tester);

    expect(find.text('128 MB (default)'), findsOneWidget);
    for (final other in ['256 MB', '512 MB', '1024 MB']) {
      expect(find.text(other), findsOneWidget);
    }
    expect(selectedLimit(tester), 128);
  });

  testWidgets('picking a limit writes it and no longer calls it the default', (
    tester,
  ) async {
    final (h, _, _) = await openNetwork(tester);

    await tester.tap(find.text('512 MB'));
    await h.loadSettings(tester);

    final stored = await tester.runAsync(
      () => h.container(tester).read(networkSettingsRepositoryProvider).read(),
    );
    expect(stored, const NetworkSettings(cacheLimitMebibytes: 512));
    expect(find.text('128 MB'), findsOneWidget);
    expect(find.textContaining('MB (default)'), findsNothing);
    expect(selectedLimit(tester), 512);
  });

  // 電台狀態刷新間隔（ADR 0017 §決定 6、ADR 0031 §決定 6）：關閉／1／3／5／10 分，沒設定過是 5 分。
  testWidgets('an unset radio interval is 5 minutes and says so', (
    tester,
  ) async {
    await openNetwork(tester);

    expect(find.text('Radio status refresh'), findsOneWidget);
    expect(find.text('5 min (default)'), findsOneWidget);
    for (final other in ['Off', '1 min', '3 min', '10 min']) {
      expect(optionIn(1, other), findsOneWidget);
    }
    expect(selectedInterval(tester), 5);
  });

  testWidgets('picking a radio interval writes only that field', (
    tester,
  ) async {
    final (h, _, _) = await openNetwork(tester);

    await tester.ensureVisible(optionIn(1, 'Off'));
    await tester.tap(optionIn(1, 'Off'));
    await h.loadSettings(tester);
    Future<NetworkSettings?> stored() => tester.runAsync(
      () => h.container(tester).read(networkSettingsRepositoryProvider).read(),
    );
    expect(
      await stored(),
      const NetworkSettings(radioStatusIntervalMinutes: 0),
    );
    expect(selectedInterval(tester), 0);
    expect(find.text('5 min'), findsOneWidget, reason: 'no longer the default');

    await tester.ensureVisible(find.text('10 min'));
    await tester.tap(find.text('10 min'));
    await h.loadSettings(tester);
    expect(
      await stored(),
      const NetworkSettings(radioStatusIntervalMinutes: 10),
    );
    expect(selectedInterval(tester), 10);
    // 快取上限沒有被寫入。
    expect(selectedLimit(tester), 128);
  });

  // 排行刷新間隔（ADR 0017 §決定 6）：關閉／30／60／120／240 分，沒設定過是 60 分，在電台間隔之後。
  testWidgets('an unset chart interval is 60 minutes and says so', (
    tester,
  ) async {
    await openNetwork(tester);

    expect(find.text('Charts refresh'), findsOneWidget);
    expect(find.text('60 min (default)'), findsOneWidget);
    for (final other in ['Off', '30 min', '120 min', '240 min']) {
      expect(optionIn(2, other), findsOneWidget);
    }
    expect(selectedChartInterval(tester), 60);
    expect(
      tester.getTopLeft(find.text('Charts refresh')).dy,
      greaterThan(tester.getTopLeft(find.text('Radio status refresh')).dy),
      reason: 'after the radio interval',
    );
  });

  testWidgets('picking a chart interval writes only that field', (
    tester,
  ) async {
    final (h, _, _) = await openNetwork(tester);
    Future<NetworkSettings?> stored() => tester.runAsync(
      () => h.container(tester).read(networkSettingsRepositoryProvider).read(),
    );

    await tester.ensureVisible(optionIn(2, 'Off'));
    await tester.tap(optionIn(2, 'Off'));
    await h.loadSettings(tester);
    expect(
      await stored(),
      const NetworkSettings(chartRefreshIntervalMinutes: 0),
    );
    expect(selectedChartInterval(tester), 0);
    expect(
      find.text('60 min'),
      findsOneWidget,
      reason: 'no longer the default',
    );

    await tester.ensureVisible(optionIn(2, '240 min'));
    await tester.tap(optionIn(2, '240 min'));
    await h.loadSettings(tester);
    expect(
      await stored(),
      const NetworkSettings(chartRefreshIntervalMinutes: 240),
    );
    expect(selectedChartInterval(tester), 240);
    // 另外兩組沒有被寫入。
    expect(selectedLimit(tester), 128);
    expect(selectedInterval(tester), 5);
  });

  /// 用量那一列 [title] 右邊的文字。
  String usageOf(WidgetTester tester, String title) =>
      (tester.widget<ListTile>(find.widgetWithText(ListTile, title)).trailing!
              as Text)
          .data!;

  testWidgets('shows the charts usage', (tester) async {
    final (_, _, store) = await openNetwork(tester, artworkBytes: 2048);
    await tester.runAsync(
      () => ChartCache(store).write(
        (pluginId: 'fmp-test', chartId: 'hot'),
        ChartCacheEntry(
          fetchedAt: DateTime.utc(2026, 10, 21),
          tracks: [
            for (var n = 0; n < 50; n++)
              TrackInfo(
                sourceTypeId: 'fmp-test',
                sourceId: 'track-$n',
                title: 'A chart track with a long enough title $n',
              ),
          ],
        ),
      ),
    );
    final usage = (await tester.runAsync(() => store.watchUsage().first))!;
    final bytes = usage[CacheCategory.chart]!;
    expect(bytes, greaterThan(1024));
    await waitForText(tester, formatByteSize(bytes));

    expect(usageOf(tester, 'Charts'), formatByteSize(bytes));
    expect(usageOf(tester, 'Artwork'), '2 KB');
  });

  testWidgets('shows the artwork usage', (tester) async {
    await openNetwork(tester, artworkBytes: 3 * 1024 * 1024);

    expect(find.text('Artwork'), findsOneWidget);
    expect(find.text('3.0 MB'), findsOneWidget);
  });

  // 封面在別處下載、或改了上限而淘汰：用量跟著變，不必離開再進來。
  testWidgets('the usage follows the cache while the page is open', (
    tester,
  ) async {
    final (_, cache, store) = await openNetwork(tester, artworkBytes: 2048);
    expect(find.text('2 KB'), findsOneWidget);

    await tester.runAsync(
      () => put(cache.manager(store), 'https://example.test/b.jpg', 2048),
    );
    await waitForText(tester, '4 KB');
    expect(find.text('4 KB'), findsOneWidget);

    await tester.runAsync(() => store.setLimit(2048));
    await waitForText(tester, '2 KB');
    expect(find.text('2 KB'), findsOneWidget);
  });

  testWidgets('clearing asks first; cancelling keeps everything', (
    tester,
  ) async {
    final (_, cache, store) = await openNetwork(tester, artworkBytes: 2048);

    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();
    expect(find.text('Clear the cache?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Clear the cache?'), findsNothing);
    expect(await tester.runAsync(() => store.watchUsage().first), {
      CacheCategory.image: 2048,
      CacheCategory.chart: 0,
    });
    expect(cache.fileNames(), hasLength(1));
  });

  testWidgets('clearing empties the store, the usage and the ImageCache', (
    tester,
  ) async {
    final (_, cache, store) = await openNetwork(tester, artworkBytes: 2048);
    expect(find.text('2 KB'), findsOneWidget);
    final imageCache = PaintingBinding.instance.imageCache;
    // 記憶體裡有兩張圖：一張沒人在用（`clear` 清得掉），一張畫面上正在用（有
    // listener，是 live image：`clear` 不清，要 `clearLiveImages`）。還在解碼的
    // 也算：`containsKey` 兩種都看。
    imageCache.putIfAbsent(
      'decoded',
      () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
    );
    final inUse = imageCache.putIfAbsent(
      'in use',
      () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
    )!;
    final listener = ImageStreamListener((_, _) {});
    inUse.addListener(listener);
    addTearDown(() => inUse.removeListener(listener));
    expect(imageCache.containsKey('decoded'), isTrue);
    expect(imageCache.liveImageCount, 2);

    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear cache'));
    await tester.pump();
    // 清除在真的事件迴圈上跑（索引先刪，用量這時就變 0；檔案接著刪）；全部做完、
    // 清了 ImageCache 才報成功。
    await waitForText(tester, 'Cache cleared');

    expect(await tester.runAsync(() => store.watchUsage().first), {
      CacheCategory.image: 0,
      CacheCategory.chart: 0,
    });
    expect(cache.fileNames(), isEmpty);
    expect(imageCache.containsKey('decoded'), isFalse);
    expect(imageCache.liveImageCount, 0);
    expect(find.text('0 B'), findsNWidgets(2), reason: 'artwork and charts');
    expect(find.text('Cache cleared'), findsOneWidget);
  });

  // 清掉的排行（M4 PR 21）：首頁、探索頁重讀快取，並立刻重抓每個有榜單的插件。以真的快取庫與
  // 排行工作跑：兩個有榜單的插件、一個沒有宣告 `charts` 的。
  group('the charts after clearing', () {
    late List<FakeChartPlugin> plugins;

    ChartKey keyOf(String pluginId) => (pluginId: pluginId, chartId: 'hot');

    /// 開「網路」組，排行工作照 App 常駐，等第一輪排行寫進快取。之後每個榜單都抓不回來
    /// （重抓只看得到「有沒有被問」，快取一直是清掉後的樣子）。
    Future<(ShellHarness, CacheStore)> open(WidgetTester tester) async {
      plugins = [
        FakeChartPlugin(id: 'alpha', charts: const ['hot']),
        FakeChartPlugin(id: 'beta', charts: const ['hot']),
        FakeChartPlugin(id: 'gamma', declaresCharts: false),
      ];
      final cache = CacheHarness();
      final store = (await tester.runAsync(
        () => cache.open(limitBytes: 1 << 30),
      ))!;
      final h = ShellHarness(
        cacheStore: store,
        registryOfSources: true,
        sources: plugins,
      );
      await h.pumpApp(
        tester,
        const SingleChildScrollView(child: NetworkControls()),
      );
      final container = h.container(tester)
        ..listen(backgroundSchedulerProvider, (_, _) {})
        ..listen(chartJobsProvider, (_, _) {});
      for (final pluginId in ['alpha', 'beta']) {
        container.listen(chartContentProvider(keyOf(pluginId)), (_, _) {});
      }
      bool cached() => [
        for (final pluginId in ['alpha', 'beta'])
          container.read(chartContentProvider(keyOf(pluginId))).value,
      ].every((content) => content != null);
      for (var i = 0; i < 100 && !cached(); i++) {
        await h.loadSettings(tester);
      }
      expect(cached(), isTrue, reason: 'the first round of charts is cached');
      for (final plugin in plugins) {
        plugin.onChart = (_) => Completer<ChartPage>().future;
      }
      return (h, store);
    }

    Map<String, int> queries() => {
      for (final plugin in plugins)
        plugin.manifest.id: plugin.chartQueries.length,
    };

    Future<void> clear(WidgetTester tester) async {
      await tester.tap(find.text('Clear cache'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear cache'));
      await tester.pump();
    }

    testWidgets('the cached charts read again as gone and every plugin with '
        'charts is refreshed once', (tester) async {
      final (h, _) = await open(tester);
      final container = h.container(tester);
      final before = queries();
      final revision = container.read(chartCacheRevisionProvider);

      await clear(tester);
      await waitForText(tester, 'Cache cleared');
      for (var i = 0; i < 5; i++) {
        await h.loadSettings(tester);
      }

      expect(container.read(chartCacheRevisionProvider), greaterThan(revision));
      for (final pluginId in ['alpha', 'beta']) {
        expect(
          container.read(chartContentProvider(keyOf(pluginId))).value,
          isNull,
          reason: pluginId,
        );
      }
      expect(queries(), {
        'alpha': before['alpha']! + 1,
        'beta': before['beta']! + 1,
        'gamma': 0,
      });
    });

    testWidgets('a clear that fails neither reloads nor refreshes the charts', (
      tester,
    ) async {
      final (h, store) = await open(tester);
      final container = h.container(tester);
      final before = queries();
      final revision = container.read(chartCacheRevisionProvider);
      // 索引已經關掉：清除拋錯。
      await tester.runAsync(store.close);

      await clear(tester);
      for (var i = 0; i < 100 && h.log.history.isEmpty; i++) {
        await h.loadSettings(tester);
      }
      for (var i = 0; i < 5; i++) {
        await h.loadSettings(tester);
      }

      expect(
        h.log.history
            .where((r) => r.level == LogLevel.error)
            .map((r) => r.message),
        contains('Failed to clear the cache'),
      );
      expect(container.read(chartCacheRevisionProvider), revision);
      expect(queries(), before);
    });
  });

  testWidgets('a clear that fails is logged and not reported as done', (
    tester,
  ) async {
    final (h, _, store) = await openNetwork(tester, artworkBytes: 2048);
    // 索引已經關掉：清除拋錯。
    await tester.runAsync(store.close);

    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear cache'));
    for (var i = 0; i < 100 && h.log.history.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(
      h.log.history
          .where((r) => r.level == LogLevel.error)
          .map((r) => r.message),
      ['Failed to clear the cache'],
    );
    expect(find.text('Cache cleared'), findsNothing);
  });
}
