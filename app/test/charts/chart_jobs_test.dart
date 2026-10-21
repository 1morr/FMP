import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/charts/chart_cache.dart';
import 'package:fmp/charts/chart_entries.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/scheduler/background_scheduler.dart';
import 'package:fmp/settings/network_settings.dart';

import '../support/fake_network_interfaces.dart';
import '../support/memory_database.dart';
import 'fake_chart_plugin.dart';

// 排行工作（M4 design §6.2、ADR 0017）：每個有啟用榜單的插件一個 `charts:<pluginId>`、單一榜單失敗
// 不退避並標記、全部失敗才退避、間隔與啟用榜單改變時重新登記、停用時刪快取、手動刷新。以真的
// 排程器加假時鐘跑（radio_test.dart 的做法），快取用記憶體裡的（真的快取庫由 chart_cache_test.dart
// 守）。

final _start = DateTime.utc(2026, 10, 16, 12);

final _testPlugins = NotifierProvider<_TestPlugins, Map<String, SourcePlugin>>(
  _TestPlugins.new,
);

final class _TestPlugins extends Notifier<Map<String, SourcePlugin>> {
  @override
  Map<String, SourcePlugin> build() => const {};

  void set(Map<String, SourcePlugin> plugins) => state = plugins;
}

ChartKey _key(String chartId, [String pluginId = 'fmp-test']) =>
    (pluginId: pluginId, chartId: chartId);

final class _Env {
  _Env({bool online = true}) {
    interfaces = FakeNetworkInterfaces(available: online);
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        logProvider.overrideWithValue(log),
        networkInterfacesProvider.overrideWithValue(interfaces),
        platformCapabilitiesProvider.overrideWithValue(
          const PlatformCapabilities(
            dataDirectory: true,
            singleInstance: false,
            secureStorage: false,
            fontFallback: FontFallback.none,
            playback: null,
            networkInterfaces: false,
            files: false,
            loginWebView: false,
            urlOpener: false,
            restartsItself: false,
            shareFiles: false,
            pluginDevTools: false,
            cache: CacheSizes(
              defaultLimitMebibytes: 256,
              memoryImages: 1,
              memoryImageMebibytes: 1,
            ),
          ),
        ),
        chartCacheProvider.overrideWith((ref) => cache),
        pluginRegistryProvider.overrideWithBuild(
          (ref, notifier) => ref.watch(_testPlugins),
        ),
      ],
    );
  }

  final database = memoryDatabase();
  final cache = FakeChartCache();
  late final FakeNetworkInterfaces interfaces;
  late final Log log;
  late final ProviderContainer container;

  ChartJobs get jobs => container.read(chartJobsProvider.notifier);

  Set<ChartKey> get failures => container.read(chartFailuresProvider);

  /// 排程器、排行工作與它的輸入都建起來。
  void start(FakeAsync async, List<SourcePlugin> plugins) {
    container
      ..listen(networkStatusProvider, (_, _) {})
      ..listen(networkProvider, (_, _) {})
      ..listen(chartFailuresProvider, (_, _) {})
      ..listen(chartJobsProvider, (_, _) {})
      ..read(backgroundSchedulerProvider);
    setPlugins(async, plugins);
    async.flushMicrotasks();
  }

  /// 插件清單變成 [plugins]。
  void setPlugins(FakeAsync async, List<SourcePlugin> plugins) {
    container.read(_testPlugins.notifier).set({
      for (final plugin in plugins) plugin.manifest.id: plugin,
    });
    // 依賴改了的 provider 在測試 binding 裡不會自己重建（沒有影格），讀它才會。
    container.read(pluginRegistryProvider);
    _settle(async);
  }

  void setEnabled(
    FakeAsync async,
    String chartId, {
    required bool enabled,
    String pluginId = 'fmp-test',
  }) {
    unawaited(
      container
          .read(chartSettingsRepositoryProvider)
          .setEnabled(pluginId, chartId, enabled: enabled),
    );
    _settle(async);
  }

  void setInterval(FakeAsync async, int? minutes) {
    unawaited(
      container.read(networkProvider.notifier).setChartRefreshInterval(minutes),
    );
    _settle(async);
  }

  /// 手動刷新；回傳結果，失敗時回傳丟出的錯誤。
  Object? runNow(FakeAsync async, [String pluginId = 'fmp-test']) {
    Object? outcome;
    var done = false;
    jobs
        .runNow(pluginId)
        .then<void>((result) => outcome = result)
        .catchError((Object error) => outcome = error)
        .whenComplete(() => done = true);
    async.flushMicrotasks();
    expect(done, isTrue, reason: 'runNow did not complete');
    return outcome;
  }

  int get backoffs =>
      log.history.where((r) => r.message == 'Background job backed off').length;

  List<LogRecord> logs(String message) => [
    for (final record in log.history)
      if (record.message == message) record,
  ];

  void dispose() => container.dispose();
}

/// drift 的串流與 provider 的重建要過一個計時器才送達，只跑微任務不夠。
void _settle(FakeAsync async) => async.elapse(const Duration(milliseconds: 10));

void _fake(void Function(FakeAsync async) body) =>
    fakeAsync(body, initialTime: _start);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
  });

  group('which plugins get a job', () {
    test('a plugin with enabled charts fetches each of them and caches '
        'the tracks with the time', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin();
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        expect(plugin.chartQueries, ['hot', 'new']);
        final hot = env.cache.entries[_key('hot')]!;
        expect(hot.fetchedAt, _start);
        expect(hot.tracks, [
          const TrackInfo(
            sourceTypeId: 'fmp-test',
            sourceId: 'hot-1',
            title: 'Track 1 of hot',
          ),
          const TrackInfo(
            sourceTypeId: 'fmp-test',
            sourceId: 'hot-2',
            title: 'Track 2 of hot',
          ),
        ]);
        expect(env.cache.entries.keys, [_key('hot'), _key('new')]);
        expect(env.failures, isEmpty);
        expect(env.backoffs, 0);
        final finished = env.logs('Chart refresh finished').single;
        expect(finished.fields, {
          'pluginId': 'fmp-test',
          'succeeded': 2,
          'failed': 0,
        });
        env.dispose();
      });
    });

    test('a plugin that does not declare charts gets no job', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(declaresCharts: false);
        env.start(async, [plugin]);
        async.elapse(const Duration(hours: 2));

        expect(plugin.chartListCalls, 0);
        expect(plugin.chartQueries, isEmpty);
        expect(env.runNow(async), RunNowResult.unknown);
        env.dispose();
      });
    });

    test('a plugin with no charts gets no job', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const []);
        env.start(async, [plugin]);
        async.elapse(const Duration(hours: 2));

        expect(plugin.chartQueries, isEmpty);
        expect(env.runNow(async), RunNowResult.unknown);
        env.dispose();
      });
    });

    test('every chart disabled: no job is registered and nothing is '
        'fetched', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin();
        env.setEnabled(async, 'hot', enabled: false);
        env.setEnabled(async, 'new', enabled: false);
        env.start(async, [plugin]);
        async.elapse(const Duration(hours: 2));

        expect(plugin.chartQueries, isEmpty);
        expect(env.runNow(async), RunNowResult.unknown);
        expect(env.cache.entries, isEmpty);
        env.dispose();
      });
    });

    test('a disabled chart is skipped; one the plugin has and the settings '
        'never heard of is enabled', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const ['hot', 'new', 'extra']);
        // 設定裡還有插件已經拿掉的榜單的列：不影響。
        env.setEnabled(async, 'hot', enabled: false);
        env.setEnabled(async, 'gone', enabled: false);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        expect(plugin.chartQueries, ['new', 'extra']);
        env.dispose();
      });
    });

    test('a row with no enabled value counts as enabled, and a row of another '
        'plugin does not apply', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin();
        // PR 21 的排序只寫 sort_order：enabled 留空＝啟用。
        unawaited(
          env.database
              .into(env.database.chartSettingsTable)
              .insert(
                ChartSettingsTableCompanion.insert(
                  pluginId: 'fmp-test',
                  chartId: 'hot',
                  sortOrder: const Value(1),
                ),
              ),
        );
        env.setEnabled(async, 'new', enabled: false, pluginId: 'other');
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        expect(plugin.chartQueries, ['hot', 'new']);
        env.dispose();
      });
    });

    test('a plugin that fails to list its charts still gets a job: the run '
        'fails and backs off, and a retry fetches the charts', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin()
          ..listError = NetworkError(pluginId: 'fmp-test');
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        expect(plugin.chartQueries, isEmpty);
        expect(env.logs('Failed to list the charts of a plugin'), hasLength(1));
        expect(env.backoffs, 1, reason: 'the run asked again and failed');
        expect(env.runNow(async), isA<NetworkError>());

        // 沒有任何設定改變：退避到期的重試就抓到了。
        plugin.listError = null;
        async.elapse(const Duration(minutes: 3));
        expect(plugin.chartQueries, ['hot', 'new']);
        expect(env.cache.entries.keys, [_key('hot'), _key('new')]);
        env.dispose();
      });
    });

    test('a new plugin instance that fails to list its charts keeps the job '
        'and the cache', () {
      _fake((async) {
        final env = _Env();
        env.start(async, [FakeChartPlugin()]);
        async.elapse(const Duration(seconds: 1));
        final updated = FakeChartPlugin()
          ..listError = NetworkError(pluginId: 'fmp-test');

        env.setPlugins(async, [updated]);

        expect(env.cache.removedPlugins, isEmpty);
        expect(env.cache.removedCharts, isEmpty);
        expect(env.cache.entries.keys, [_key('hot'), _key('new')]);
        expect(env.runNow(async), isA<NetworkError>());
        env.dispose();
      });
    });

    test('a chart disabled while the list was unknown loses its cache once a '
        'run gets the list; from then on changes are compared as usual', () {
      _fake((async) {
        final env = _Env();
        env.start(async, [FakeChartPlugin()]);
        async.elapse(const Duration(seconds: 1));
        final updated = FakeChartPlugin()
          ..listError = NetworkError(pluginId: 'fmp-test');
        env.setPlugins(async, [updated]);
        env.setEnabled(async, 'hot', enabled: false);
        expect(env.cache.removedCharts, isEmpty);

        updated.listError = null;
        expect(env.runNow(async), RunNowResult.completed);

        expect(updated.chartQueries, ['new']);
        expect(env.cache.removedCharts, [_key('hot')]);
        expect(env.cache.entries.keys, [_key('new')]);

        env.setEnabled(async, 'new', enabled: false);
        expect(env.cache.removedPlugins, ['fmp-test']);
        expect(env.runNow(async), RunNowResult.unknown);
        env.dispose();
      });
    });

    test('a run that gets the list and finds every chart disabled removes '
        "the job and the plugin's cache", () {
      _fake((async) {
        final env = _Env();
        env.start(async, [FakeChartPlugin()]);
        async.elapse(const Duration(seconds: 1));
        final updated = FakeChartPlugin()
          ..listError = NetworkError(pluginId: 'fmp-test');
        env.setPlugins(async, [updated]);
        env.setEnabled(async, 'hot', enabled: false);
        env.setEnabled(async, 'new', enabled: false);

        updated.listError = null;
        env.runNow(async);

        expect(updated.chartQueries, isEmpty);
        expect(env.cache.removedPlugins, ['fmp-test']);
        expect(env.cache.entries, isEmpty);
        expect(env.runNow(async), RunNowResult.unknown);
        env.dispose();
      });
    });

    test('two plugins each get their own job, run one after the other', () {
      _fake((async) {
        final env = _Env();
        final first = FakeChartPlugin(id: 'first', charts: const ['a']);
        final second = FakeChartPlugin(id: 'second', charts: const ['b']);
        env.start(async, [first, second]);
        async.elapse(const Duration(seconds: 1));

        expect(first.chartQueries, ['a']);
        expect(second.chartQueries, ['b']);
        expect(
          env.cache.entries.keys,
          containsAll([_key('a', 'first'), _key('b', 'second')]),
        );
        env.dispose();
      });
    });
  });

  group('failures', () {
    test('one failing chart is marked, the others are cached, and the job '
        'does not back off', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const ['hot', 'broken', 'new'])
          ..onChart = (chartId) => chartId == 'broken'
              ? throw NetworkError(pluginId: 'fmp-test')
              : FakeChartPlugin().onChart(chartId);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        expect(plugin.chartQueries, ['hot', 'broken', 'new']);
        expect(env.cache.entries.keys, [_key('hot'), _key('new')]);
        expect(env.failures, {_key('broken')});
        expect(env.backoffs, 0);
        final finished = env.logs('Chart refresh finished').single;
        expect(finished.fields, containsPair('succeeded', 2));
        expect(finished.fields, containsPair('failed', 1));
        expect(env.logs('Chart update failed'), hasLength(1));
        env.dispose();
      });
    });

    test('a chart that works again loses its mark, and the old content '
        'stays while it is marked', () {
      _fake((async) {
        final env = _Env();
        var broken = false;
        final plugin = FakeChartPlugin(charts: const ['hot'])
          ..onChart = (chartId) => broken
              ? throw NetworkError(pluginId: 'fmp-test')
              : FakeChartPlugin().onChart(chartId);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));
        final firstFetch = env.cache.entries[_key('hot')]!.fetchedAt;

        broken = true;
        async.elapse(const Duration(hours: 1));
        expect(env.failures, {_key('hot')});
        expect(
          env.cache.entries[_key('hot')]!.fetchedAt,
          firstFetch,
          reason: 'a failed update keeps what was cached',
        );

        broken = false;
        env.runNow(async);
        expect(env.failures, isEmpty);
        expect(
          env.cache.entries[_key('hot')]!.fetchedAt.isAfter(firstFetch),
          isTrue,
        );
        env.dispose();
      });
    });

    test('when every chart fails the job fails and backs off', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin()
          ..onChart = (_) => throw NetworkError(pluginId: 'fmp-test');
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        expect(plugin.chartQueries, ['hot', 'new']);
        expect(env.backoffs, 1);
        expect(env.failures, {_key('hot'), _key('new')});
        expect(env.cache.entries, isEmpty);
        final runs = _await(
          async,
          () => env.container.read(schedulerRunsRepositoryProvider).all(),
        );
        expect(runs, isEmpty, reason: 'no success time was recorded');

        // 退避一分鐘後再試。
        async.elapse(const Duration(seconds: 58));
        expect(plugin.chartQueries, hasLength(2));
        async.elapse(const Duration(seconds: 3));
        expect(plugin.chartQueries, hasLength(4));
        env.dispose();
      });
    });

    test('a chartList that fails fails the run and backs off', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin();
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));
        plugin.listError = NetworkError(pluginId: 'fmp-test');

        final outcome = env.runNow(async);

        expect(outcome, isA<NetworkError>());
        expect(env.failures, isEmpty);
        env.dispose();
      });
    });
  });

  // 重啟後工作通常還沒到期（上次成功加間隔）；有啟用的榜單沒有快取（上次失敗、被淘汰、快取讀不
  // 出來）時登記成立即到期，畫面才不會一直轉圈到下一輪。
  group('a chart missing from the cache', () {
    /// 上一次執行剛成功（重啟前），快取裡只有 [cached]。
    _Env restarted(FakeAsync async, List<String> cached, {bool online = true}) {
      final env = _Env(online: online);
      _await(
        async,
        () => env.container
            .read(schedulerRunsRepositoryProvider)
            .record(chartJobId('fmp-test'), clock.now()),
      );
      for (final chartId in cached) {
        env.cache.entries[_key(chartId)] = ChartCacheEntry(
          fetchedAt: clock.now().toUtc(),
          tracks: const [],
        );
      }
      return env;
    }

    test('after a restart is fetched at once, with the rest of the job', () {
      _fake((async) {
        final env = restarted(async, ['hot']);
        final plugin = FakeChartPlugin(charts: const ['hot', 'new']);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        expect(plugin.chartQueries, ['hot', 'new']);
        expect(env.cache.entries.keys, containsAll([_key('hot'), _key('new')]));

        // 成功之後回到一小時一次。
        async.elapse(const Duration(minutes: 58));
        expect(plugin.chartQueries, hasLength(2));
        async.elapse(const Duration(minutes: 2));
        expect(plugin.chartQueries, hasLength(4));
        env.dispose();
      });
    });

    // 一直抓不到的榜單：冷啟動（標記只在記憶體）時讓工作立即到期一次；之後它已標失敗，設定變更
    // 重新登記時不再讓整個插件立刻重抓。
    test('a chart that always fails: one run at a restart, then nothing '
        'before the interval, even when the settings change', () {
      _fake((async) {
        final env = restarted(async, ['hot']);
        final plugin = FakeChartPlugin(charts: const ['hot', 'broken'])
          ..onChart = (chartId) => chartId == 'broken'
              ? throw NetworkError(pluginId: 'fmp-test')
              : FakeChartPlugin().onChart(chartId);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));
        expect(plugin.chartQueries, ['hot', 'broken']);
        expect(env.failures, {_key('broken')});

        async.elapse(const Duration(minutes: 30));
        expect(plugin.chartQueries, hasLength(2));

        // 改間隔會重新登記：broken 已標失敗，不算缺快取，照上次成功加新間隔。
        env.setInterval(async, 120);
        async.elapse(const Duration(minutes: 88));
        expect(plugin.chartQueries, hasLength(2));
        async.elapse(const Duration(minutes: 3));
        expect(plugin.chartQueries, hasLength(4));
        env.dispose();
      });
    });

    test('every chart cached: nothing is fetched before the interval', () {
      _fake((async) {
        final env = restarted(async, ['hot', 'new']);
        final plugin = FakeChartPlugin(charts: const ['hot', 'new']);
        env.start(async, [plugin]);
        async.elapse(const Duration(minutes: 59));
        expect(plugin.chartQueries, isEmpty);

        async.elapse(const Duration(minutes: 2));
        expect(plugin.chartQueries, ['hot', 'new']);
        env.dispose();
      });
    });

    test('a cache that cannot be read counts as missing', () {
      _fake((async) {
        final env = restarted(async, ['hot', 'new']);
        env.cache.readError = StateError('cache unavailable');
        final plugin = FakeChartPlugin(charts: const ['hot', 'new']);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        expect(plugin.chartQueries, ['hot', 'new']);
        env.dispose();
      });
    });

    test('started offline: fetched once the network is back', () {
      _fake((async) {
        final env = restarted(async, ['hot'], online: false);
        final plugin = FakeChartPlugin(charts: const ['hot', 'new']);
        env.start(async, [plugin]);
        async.elapse(const Duration(minutes: 5));
        expect(plugin.chartQueries, isEmpty);

        env.interfaces.change(available: true);
        async.elapse(const Duration(seconds: 1));
        expect(plugin.chartQueries, ['hot', 'new']);
        env.dispose();
      });
    });

    test('with the interval off nothing is fetched by itself', () {
      _fake((async) {
        final env = restarted(async, ['hot']);
        env.setInterval(async, 0);
        final plugin = FakeChartPlugin(charts: const ['hot', 'new']);
        env.start(async, [plugin]);
        async.elapse(const Duration(hours: 5));
        expect(plugin.chartQueries, isEmpty);
        env.dispose();
      });
    });
  });

  group('the interval', () {
    test('defaults to an hour, counted from the last success', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const ['hot']);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));
        expect(plugin.chartQueries, hasLength(1));

        async.elapse(const Duration(minutes: 59));
        expect(plugin.chartQueries, hasLength(1));
        async.elapse(const Duration(minutes: 2));
        expect(plugin.chartQueries, hasLength(2));
        env.dispose();
      });
    });

    test('a changed interval registers the job again with the new one', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const ['hot']);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));
        expect(plugin.chartQueries, hasLength(1));

        env.setInterval(async, 30);
        async.elapse(const Duration(minutes: 29));
        expect(plugin.chartQueries, hasLength(1));
        async.elapse(const Duration(minutes: 2));
        expect(plugin.chartQueries, hasLength(2));

        env.setInterval(async, 240);
        async.elapse(const Duration(hours: 3));
        expect(plugin.chartQueries, hasLength(2));
        async.elapse(const Duration(hours: 1));
        expect(plugin.chartQueries, hasLength(3));
        env.dispose();
      });
    });

    test('off registers the job without a schedule: nothing runs by itself '
        'but a manual refresh does', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const ['hot']);
        env.setInterval(async, 0);
        env.start(async, [plugin]);
        async.elapse(const Duration(hours: 10));

        expect(plugin.chartQueries, isEmpty);
        expect(env.cache.entries, isEmpty);

        expect(env.runNow(async), RunNowResult.completed);

        expect(plugin.chartQueries, ['hot']);
        expect(env.cache.entries.keys, [_key('hot')]);
        async.elapse(const Duration(hours: 10));
        expect(plugin.chartQueries, hasLength(1));
        env.dispose();
      });
    });

    test(
      'turning it off stops the schedule, turning it on again resumes it',
      () {
        _fake((async) {
          final env = _Env();
          final plugin = FakeChartPlugin(charts: const ['hot']);
          env.start(async, [plugin]);
          async.elapse(const Duration(seconds: 1));

          env.setInterval(async, 0);
          async.elapse(const Duration(hours: 3));
          expect(plugin.chartQueries, hasLength(1));

          env.setInterval(async, 60);
          async.elapse(const Duration(seconds: 1));
          expect(plugin.chartQueries, hasLength(2));
          env.dispose();
        });
      },
    );

    test(
      'does not run while the network is offline, and runs when it is back',
      () {
        _fake((async) {
          final env = _Env(online: false);
          final plugin = FakeChartPlugin(charts: const ['hot']);
          env.start(async, [plugin]);
          async.elapse(const Duration(hours: 1));
          expect(plugin.chartQueries, isEmpty);

          env.interfaces.change(available: true);
          async.flushMicrotasks();
          expect(plugin.chartQueries, hasLength(1));
          env.dispose();
        });
      },
    );
  });

  group('registering again', () {
    test('only a changed plugin, interval or set of enabled charts replaces '
        'the job: an unrelated settings write does not cut a run short', () {
      _fake((async) {
        final env = _Env();
        final release = Completer<void>();
        final plugin = FakeChartPlugin(charts: const ['hot', 'new'])
          ..onChart = (chartId) async {
            if (chartId == 'hot') await release.future;
            return FakeChartPlugin().onChart(chartId);
          };
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));
        expect(plugin.chartQueries, ['hot']);

        // 啟用榜單的集合沒變（把本來就啟用的榜單再寫成啟用）：進行中的這一次不被打斷。
        env.setEnabled(async, 'new', enabled: true);
        release.complete();
        async.elapse(const Duration(seconds: 1));

        expect(env.cache.entries.keys, [_key('hot'), _key('new')]);
        expect(plugin.chartQueries, [
          'hot',
          'new',
        ], reason: 'the run went on; no second run started');
        env.dispose();
      });
    });

    test('a run in progress is dropped when its chart set changes', () {
      _fake((async) {
        final env = _Env();
        final release = Completer<void>();
        final plugin = FakeChartPlugin(charts: const ['hot', 'new'])
          ..onChart = (chartId) async {
            if (chartId == 'hot') await release.future;
            return FakeChartPlugin().onChart(chartId);
          };
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));
        expect(plugin.chartQueries, ['hot']);

        env.setEnabled(async, 'hot', enabled: false);
        release.complete();
        async.elapse(const Duration(seconds: 1));

        // 舊的那一次已過期，什麼都不寫；新的登記只抓還啟用的榜單。
        expect(env.cache.entries.keys, [_key('new')]);
        expect(plugin.chartQueries, ['hot', 'new']);
        expect(env.cache.removedCharts, [_key('hot')]);
        env.dispose();
      });
    });

    test('a new plugin instance (an update) replaces the job and keeps '
        'the cache; a chart it adds is enabled and fetched at once', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const ['hot']);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));
        final updated = FakeChartPlugin(charts: const ['hot', 'extra']);

        // 新增的 extra 沒有快取：重新登記成立即到期，不等一整個間隔。
        env.setPlugins(async, [updated]);
        async.elapse(const Duration(seconds: 1));

        expect(updated.chartQueries, ['hot', 'extra']);
        expect(plugin.chartQueries, [
          'hot',
        ], reason: 'the old one is not asked');
        expect(env.cache.removedPlugins, isEmpty);
        expect(env.cache.removedCharts, isEmpty);
        env.dispose();
      });
    });

    test('a chart the new version of the plugin dropped loses its cache', () {
      _fake((async) {
        final env = _Env();
        env.start(async, [
          FakeChartPlugin(charts: const ['hot', 'new']),
        ]);
        async.elapse(const Duration(seconds: 1));
        expect(env.cache.entries.keys, [_key('hot'), _key('new')]);

        env.setPlugins(async, [
          FakeChartPlugin(charts: const ['hot']),
        ]);

        expect(env.cache.entries.keys, [_key('hot')]);
        expect(env.cache.removedCharts, [_key('new')]);
        env.dispose();
      });
    });
  });

  group('turning charts and plugins off', () {
    test('a disabled chart loses its cache and its mark, the others are '
        'left alone', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const ['hot', 'broken', 'new'])
          ..onChart = (chartId) => chartId == 'broken'
              ? throw NetworkError(pluginId: 'fmp-test')
              : FakeChartPlugin().onChart(chartId);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));
        expect(env.cache.entries.keys, [_key('hot'), _key('new')]);
        expect(env.failures, {_key('broken')});

        env.setEnabled(async, 'hot', enabled: false);
        env.setEnabled(async, 'broken', enabled: false);

        expect(env.cache.entries.keys, [_key('new')]);
        expect(
          env.cache.removedCharts,
          containsAll([_key('hot'), _key('broken')]),
        );
        expect(env.cache.removedPlugins, isEmpty);
        expect(env.failures, isEmpty);
        // 之後的刷新只抓還啟用的。
        plugin.chartQueries.clear();
        env.runNow(async);
        expect(plugin.chartQueries, ['new']);
        env.dispose();
      });
    });

    test('enabling a chart again fetches it right away, not on the next '
        'interval', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const ['hot', 'new']);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));
        env.setEnabled(async, 'hot', enabled: false);
        expect(env.cache.entries.keys, [_key('new')]);
        plugin.chartQueries.clear();

        // 停用時刪了 hot 的快取：重新登記成立即到期。
        env.setEnabled(async, 'hot', enabled: true);
        async.elapse(const Duration(seconds: 1));

        expect(plugin.chartQueries, ['hot', 'new']);
        expect(env.cache.entries.keys, containsAll([_key('hot'), _key('new')]));
        env.dispose();
      });
    });

    test('disabling the last enabled chart removes the job and the '
        "plugin's cache", () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin();
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        env.setEnabled(async, 'hot', enabled: false);
        env.setEnabled(async, 'new', enabled: false);

        expect(env.cache.entries, isEmpty);
        expect(env.cache.removedPlugins, ['fmp-test']);
        expect(env.runNow(async), RunNowResult.unknown);
        plugin.chartQueries.clear();
        async.elapse(const Duration(hours: 3));
        expect(plugin.chartQueries, isEmpty);
        env.dispose();
      });
    });

    test('a plugin that leaves the list (disabled or removed) loses its '
        'job, cache and marks; coming back registers it again', () {
      _fake((async) {
        final env = _Env();
        final other = FakeChartPlugin(id: 'other', charts: const ['x']);
        final plugin = FakeChartPlugin()
          ..onChart = (chartId) => chartId == 'new'
              ? throw NetworkError(pluginId: 'fmp-test')
              : FakeChartPlugin().onChart(chartId);
        env.start(async, [plugin, other]);
        async.elapse(const Duration(seconds: 1));
        expect(env.failures, {_key('new')});

        env.setPlugins(async, [other]);

        expect(env.cache.entries.keys, [_key('x', 'other')]);
        expect(env.cache.removedPlugins, ['fmp-test']);
        expect(env.failures, isEmpty);
        expect(env.runNow(async), RunNowResult.unknown);

        // 回來時快取已經刪了：立即到期，不等上次成功加間隔。
        final back = FakeChartPlugin();
        env.setPlugins(async, [back, other]);
        async.elapse(const Duration(seconds: 1));
        expect(back.chartQueries, ['hot', 'new']);
        env.dispose();
      });
    });
  });

  group('refreshing by hand', () {
    test('runs the job whatever the interval says, and again', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const ['hot']);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        expect(env.runNow(async), RunNowResult.completed);
        expect(env.runNow(async), RunNowResult.completed);

        expect(plugin.chartQueries, hasLength(3));
        env.dispose();
      });
    });

    test('offline sends nothing and says so', () {
      _fake((async) {
        final env = _Env(online: false);
        final plugin = FakeChartPlugin();
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        expect(env.runNow(async), RunNowResult.offline);

        expect(plugin.chartQueries, isEmpty);
        env.dispose();
      });
    });

    test('an unknown plugin has no job', () {
      _fake((async) {
        final env = _Env();
        env.start(async, [FakeChartPlugin()]);
        async.elapse(const Duration(seconds: 1));

        expect(env.runNow(async, 'nobody'), RunNowResult.unknown);
        env.dispose();
      });
    });

    test('when every chart fails the error comes back to the caller, with '
        'no log line of the scheduler', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const ['hot']);
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));
        plugin.onChart = (_) => throw NetworkError(pluginId: 'fmp-test');
        final failedBefore = env.logs('Background job failed').length;

        final outcome = env.runNow(async);

        expect(outcome, isA<NetworkError>());
        expect(env.failures, {_key('hot')});
        expect(env.logs('Background job failed'), hasLength(failedBefore));
        env.dispose();
      });
    });
  });

  group('what the screens read', () {
    test('the cached chart follows each write and each delete', () {
      _fake((async) {
        final env = _Env();
        final plugin = FakeChartPlugin(charts: const ['hot']);
        final seen = <ChartCacheEntry?>[];
        env.container.listen(
          chartContentProvider(_key('hot')),
          (_, next) => seen.add(next.value),
          fireImmediately: true,
        );
        env.start(async, [plugin]);
        async.elapse(const Duration(seconds: 1));

        expect(seen.last, isNotNull);
        expect(seen.last!.tracks, hasLength(2));

        env.setEnabled(async, 'hot', enabled: false);
        async.flushMicrotasks();

        expect(seen.last, isNull);
        env.dispose();
      });
    });

    // 首頁、探索頁與設定頁的榜單清單（chartEntriesProvider，M4 PR 21）：ChartJobs 已取得的
    // chartList 加 chart_settings 的啟用與順序。
    group('the chart list', () {
      /// 目前的清單，`(插件/榜單, 啟用)` 依順序；`null`＝還在讀。
      List<(String, bool)>? entries(_Env env) =>
          switch (env.container.read(chartEntriesProvider)) {
            null => null,
            final entries => [
              for (final entry in entries)
                ('${entry.pluginId}/${entry.chartId}', entry.enabled),
            ],
          };

      void listen(_Env env) =>
          env.container.listen(chartEntriesProvider, (_, _) {});

      void setOrder(FakeAsync async, _Env env, List<ChartKey> order) {
        unawaited(
          env.container.read(chartSettingsRepositoryProvider).setOrder(order),
        );
        _settle(async);
      }

      test('without settings: plugin list order, then chartList order, '
          'with names from the plugin', () {
        _fake((async) {
          final env = _Env();
          listen(env);
          env.start(async, [
            FakeChartPlugin(id: 'alpha'),
            FakeChartPlugin(id: 'beta', charts: const ['top']),
          ]);

          expect(entries(env), [
            ('alpha/hot', true),
            ('alpha/new', true),
            ('beta/top', true),
          ]);
          final first = env.container.read(chartEntriesProvider)!.first;
          expect(first.title, 'HOT');
          expect(first.sourceName, 'Fake alpha');
          expect(first.key, _key('hot', 'alpha'));
          env.dispose();
        });
      });

      test('sort_order first, the rest after it in the default order', () {
        _fake((async) {
          final env = _Env();
          listen(env);
          env.start(async, [
            FakeChartPlugin(id: 'alpha', charts: const ['hot', 'new', 'old']),
            FakeChartPlugin(id: 'beta', charts: const ['top']),
          ]);
          // 只排了兩個：其餘依插件清單與 chartList 的順序接在後面。
          setOrder(async, env, [_key('top', 'beta'), _key('old', 'alpha')]);

          expect(entries(env), [
            ('beta/top', true),
            ('alpha/old', true),
            ('alpha/hot', true),
            ('alpha/new', true),
          ]);

          setOrder(async, env, [
            _key('new', 'alpha'),
            _key('top', 'beta'),
            _key('hot', 'alpha'),
            _key('old', 'alpha'),
          ]);
          expect(entries(env), [
            ('alpha/new', true),
            ('beta/top', true),
            ('alpha/hot', true),
            ('alpha/old', true),
          ]);
          env.dispose();
        });
      });

      test('a disabled chart stays on the list, marked disabled', () {
        _fake((async) {
          final env = _Env();
          listen(env);
          env.start(async, [FakeChartPlugin()]);
          env.setEnabled(async, 'hot', enabled: false);

          expect(entries(env), [
            ('fmp-test/hot', false),
            ('fmp-test/new', true),
          ]);
          expect(
            [
              for (final entry in env.container.read(enabledChartsProvider)!)
                entry.chartId,
            ],
            ['new'],
          );
          env.dispose();
        });
      });

      test('a chart the plugin adds is enabled; one it drops is gone even '
          'with a row left in chart_settings', () {
        _fake((async) {
          final env = _Env();
          listen(env);
          env.start(async, [FakeChartPlugin()]);
          env.setEnabled(async, 'new', enabled: false);
          setOrder(async, env, [_key('new'), _key('hot')]);

          // 新版插件：拿掉 new、加了 extra。
          env.setPlugins(async, [
            FakeChartPlugin(charts: const ['hot', 'extra']),
          ]);

          expect(entries(env), [
            ('fmp-test/hot', true),
            ('fmp-test/extra', true),
          ]);
          env.dispose();
        });
      });

      test('a disabled plugin and a plugin without charts have none', () {
        _fake((async) {
          final env = _Env();
          listen(env);
          env.start(async, [
            FakeChartPlugin(id: 'alpha', charts: const ['hot']),
            FakeChartPlugin(id: 'beta', charts: const ['top']),
            FakeChartPlugin(id: 'gamma', declaresCharts: false),
          ]);
          expect(entries(env), [('alpha/hot', true), ('beta/top', true)]);

          // 停用 beta：它不在插件清單上了。
          env.setPlugins(async, [
            FakeChartPlugin(id: 'alpha', charts: const ['hot']),
          ]);
          expect(entries(env), [('alpha/hot', true)]);
          env.dispose();
        });
      });

      test('a plugin shows up once its chartList is known; one whose '
          'chartList fails has no charts', () {
        _fake((async) {
          final env = _Env();
          listen(env);
          final gate = Completer<void>();
          final slow = FakeChartPlugin(id: 'slow', charts: const ['hot'])
            ..listGate = gate.future;
          final broken = FakeChartPlugin(id: 'broken')
            ..listError = NetworkError(pluginId: 'broken');
          env.start(async, [broken, slow]);

          // 排行工作還沒對齊完：還沒有清單。
          expect(entries(env), isEmpty);

          gate.complete();
          _settle(async);
          expect(entries(env), [('slow/hot', true)]);
          env.dispose();
        });
      });

      test('a plugin whose chartList is still outstanding does not hold back '
          'the charts already known', () {
        _fake((async) {
          final env = _Env();
          listen(env);
          final gate = Completer<void>();
          final fast = FakeChartPlugin(id: 'fast', charts: const ['top']);
          final slow = FakeChartPlugin(id: 'slow', charts: const ['hot'])
            ..listGate = gate.future;
          env.start(async, [fast, slow]);

          // slow 還卡著：fast 的榜單已經在了。
          expect(entries(env), [('fast/top', true)]);

          gate.complete();
          _settle(async);
          expect(entries(env), [('fast/top', true), ('slow/hot', true)]);
          env.dispose();
        });
      });

      test('without ChartJobs running there are no charts, and nothing '
          'is read', () {
        _fake((async) {
          final env = _Env();
          listen(env);
          async.flushMicrotasks();

          expect(entries(env), isEmpty);
          expect(env.container.exists(chartJobsProvider), isFalse);
          expect(env.container.exists(chartSettingsProvider), isFalse);
          env.dispose();
        });
      });

      test('reading the list again does not ask the plugin again', () {
        _fake((async) {
          final env = _Env();
          listen(env);
          final plugin = FakeChartPlugin();
          env.start(async, [plugin]);
          async.elapse(const Duration(seconds: 1));
          final calls = plugin.chartListCalls;

          for (var i = 0; i < 3; i++) {
            env.container.invalidate(chartEntriesProvider);
            expect(entries(env), hasLength(2));
          }
          env.setEnabled(async, 'hot', enabled: false);
          expect(entries(env), hasLength(2));

          expect(plugin.chartListCalls, calls);
          env.dispose();
        });
      });
    });
  });
}

T _await<T>(FakeAsync async, Future<T> Function() body) {
  late T value;
  var done = false;
  unawaited(
    body().then((v) {
      value = v;
      done = true;
    }),
  );
  async.flushMicrotasks();
  expect(done, isTrue, reason: 'the future did not complete');
  return value;
}
