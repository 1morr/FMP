import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/library/playlist_refresh_job.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/scheduler/background_scheduler.dart';

import '../support/fake_network_interfaces.dart';
import '../support/memory_database.dart';
import 'fake_import_plugin.dart';

// 匯入歌單的自動刷新工作（ADR 0033 §決定 4、M4 design §6.1、§5.2）：到期條件、由舊到新、
// 單張失敗繼續、全部失敗退避、沒有到期算成功、取消。以真的排程器加假時鐘跑（radio_test.dart
// 的做法）；刷新器自己的行為在 `playlist_refresher_test.dart`。

final _start = DateTime.utc(2026, 10, 16, 12);

final _testPlugins = NotifierProvider<_TestPlugins, Map<String, SourcePlugin>>(
  _TestPlugins.new,
);

final class _TestPlugins extends Notifier<Map<String, SourcePlugin>> {
  @override
  Map<String, SourcePlugin> build() => const {};

  void set(Map<String, SourcePlugin> plugins) => state = plugins;
}

final class _Env {
  _Env() {
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        logProvider.overrideWithValue(log),
        networkInterfacesProvider.overrideWithValue(FakeNetworkInterfaces()),
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
        pluginRegistryProvider.overrideWithBuild(
          (ref, notifier) => ref.watch(_testPlugins),
        ),
      ],
    );
  }

  final database = memoryDatabase();
  final plugin = FakeImportPlugin();
  late final Log log;
  late final ProviderContainer container;

  PlaylistRepository get repository =>
      container.read(playlistRepositoryProvider);

  /// 插件清單、排程器與工作都建起來。
  void start(FakeAsync async) {
    container
      ..listen(networkStatusProvider, (_, _) {})
      ..read(backgroundSchedulerProvider)
      ..read(playlistRefreshJobProvider);
    setPlugins(async, [plugin]);
    async.flushMicrotasks();
  }

  void setPlugins(FakeAsync async, List<SourcePlugin> plugins) {
    container.read(_testPlugins.notifier).set({
      for (final plugin in plugins) plugin.manifest.id: plugin,
    });
    container.read(pluginRegistryProvider);
    _settle(async);
  }

  /// 建一張匯入歌單，可指定間隔、上次刷新時間與狀態。回傳 id。
  int add(
    FakeAsync async,
    String remoteId, {
    int? hours = 24,
    Duration? refreshedAgo,
    String status = 'active',
    String pluginId = 'fmp-test',
  }) => _await(async, () async {
    final id = (await repository.createImported(
      pluginId: pluginId,
      remoteId: remoteId,
      info: RemotePlaylistInfo(name: remoteId),
    ))!;
    await repository.setRefreshInterval(id, hours);
    final last = refreshedAgo == null
        ? 'NULL'
        : '${_start.subtract(refreshedAgo).millisecondsSinceEpoch}';
    await database.customStatement(
      "UPDATE playlist_remote SET last_refreshed_at = $last, status = '$status' "
      'WHERE playlist_id = $id',
    );
    return id;
  });

  PlaylistRemote remote(FakeAsync async, int id) =>
      _await(async, () async => (await repository.remote(id))!);

  /// 這個插件被問過的遠端歌單 id，依順序。
  List<String> get queried => [
    for (final q in plugin.pageQueries) q.playlistId,
  ];

  int get backoffs =>
      log.history.where((r) => r.message == 'Background job backed off').length;

  void dispose() => container.dispose();
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

/// drift 的串流與 provider 的重建要過一個計時器才送達，只跑微任務不夠。
void _settle(FakeAsync async) => async.elapse(const Duration(milliseconds: 10));

void _fake(void Function(FakeAsync async) body) =>
    fakeAsync(body, initialTime: _start);

/// 每個遠端歌單回一頁，標題是它的 id。
PlaylistPage _echo(PlaylistPageQuery query) =>
    page(['t-${query.playlistId}'], title: query.playlistId);

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

  group('which playlists are due', () {
    test('only active, enabled, interval-elapsed playlists of an enabled '
        'source, never-refreshed first and then oldest first', () {
      _fake((async) {
        final env = _Env();
        env.plugin.onPage = _echo;
        env
          ..add(async, 'old', refreshedAgo: const Duration(hours: 50))
          ..add(async, 'never')
          ..add(async, 'older', refreshedAgo: const Duration(hours: 100))
          ..add(async, 'exact', refreshedAgo: const Duration(hours: 24))
          ..add(async, 'fresh', refreshedAgo: const Duration(hours: 23))
          ..add(
            async,
            'off',
            hours: null,
            refreshedAgo: const Duration(days: 9),
          )
          ..add(async, 'gone', status: 'sourceGone')
          ..add(async, 'auth', status: 'authRequired')
          ..add(async, 'other-source', pluginId: 'other')
          ..add(
            async,
            'short',
            hours: 1,
            refreshedAgo: const Duration(hours: 2),
          );
        env.start(async);
        async.elapse(const Duration(seconds: 1));

        expect(env.queried, ['never', 'older', 'old', 'exact', 'short']);
        expect(env.backoffs, 0);
        env.dispose();
      });
    });

    test('a source that is not on the list is not asked', () {
      _fake((async) {
        final env = _Env();
        env.add(async, 'p');
        env.container.read(_testPlugins.notifier).set(const {});
        env.container
          ..listen(networkStatusProvider, (_, _) {})
          ..read(backgroundSchedulerProvider)
          ..read(playlistRefreshJobProvider);
        _settle(async);
        async.elapse(const Duration(seconds: 1));

        expect(env.queried, isEmpty);
        env.dispose();
      });
    });

    test('nothing due is a success, and a playlist becomes due once its '
        'interval has passed', () {
      _fake((async) {
        final env = _Env();
        env.plugin.onPage = _echo;
        final id = env.add(
          async,
          'p',
          hours: 1,
          refreshedAgo: const Duration(minutes: 1),
        );
        env.start(async);
        async.elapse(const Duration(seconds: 1));
        expect(env.queried, isEmpty);
        final runs = _await(
          async,
          () => env.container.read(schedulerRunsRepositoryProvider).all(),
        );
        expect(runs.keys, contains(playlistRefreshJobId));
        expect(env.backoffs, 0);

        // 工作每 30 分鐘看一次；一小時過去之前不選它。
        async.elapse(const Duration(minutes: 30));
        expect(env.queried, isEmpty, reason: '31 minutes is not an hour');
        async.elapse(const Duration(minutes: 30));
        expect(env.queried, ['p']);
        expect(env.remote(async, id).lastRefreshedAt, isNotNull);
        env.dispose();
      });
    });
  });

  group('failures', () {
    test('one failing playlist keeps no refresh time, the others still '
        'run and the job does not back off', () {
      _fake((async) {
        final env = _Env();
        env.plugin.onPage = (query) => query.playlistId == 'bad'
            ? throw NetworkError(pluginId: 'fmp-test')
            : _echo(query);
        final a = env.add(async, 'a', refreshedAgo: const Duration(days: 4));
        final bad = env.add(
          async,
          'bad',
          refreshedAgo: const Duration(days: 3),
        );
        final c = env.add(async, 'c', refreshedAgo: const Duration(days: 2));
        env.start(async);
        async.elapse(const Duration(seconds: 1));

        expect(env.queried, ['a', 'bad', 'c']);
        expect(env.remote(async, a).lastResult, PlaylistRefreshResult.complete);
        expect(env.remote(async, c).lastResult, PlaylistRefreshResult.complete);
        final failed = env.remote(async, bad);
        expect(failed.lastResult, PlaylistRefreshResult.failed);
        expect(
          failed.lastRefreshedAt,
          _start.subtract(const Duration(days: 3)),
          reason: 'a failure does not move the refresh time',
        );
        expect(env.backoffs, 0);

        // 下一輪（30 分鐘後）只再試失敗的那一張，成功的不再選。
        async.elapse(const Duration(minutes: 29));
        expect(env.queried, hasLength(3));
        async.elapse(const Duration(minutes: 2));
        expect(env.queried.skip(3), isNotEmpty);
        expect(env.queried.skip(3), everyElement('bad'));
        env.dispose();
      });
    });

    test('when every due playlist fails the job fails and backs off', () {
      _fake((async) {
        final env = _Env();
        env.plugin.onPage = (_) => throw NetworkError(pluginId: 'fmp-test');
        env.add(async, 'a');
        env.add(async, 'b');
        env.start(async);
        async.elapse(const Duration(seconds: 1));

        expect(env.queried, ['a', 'b']);
        expect(env.backoffs, 1);
        final runs = _await(
          async,
          () => env.container.read(schedulerRunsRepositoryProvider).all(),
        );
        expect(runs, isEmpty);
        env.dispose();
      });
    });

    test('a playlist whose source is gone is marked and never picked '
        'again', () {
      _fake((async) {
        final env = _Env();
        env.plugin.onPage = (_) => throw NotFound(pluginId: 'fmp-test');
        final id = env.add(async, 'a');
        env.start(async);
        async.elapse(const Duration(seconds: 1));
        expect(env.remote(async, id).status, PlaylistRemoteStatus.sourceGone);

        async.elapse(const Duration(hours: 3));
        expect(env.queried, ['a']);
        env.dispose();
      });
    });
  });

  group('cancelling', () {
    test('turning the interval off stops the one in progress and the next '
        'one still runs', () {
      _fake((async) {
        final env = _Env();
        final gate = Completer<PlaylistPage>();
        env.plugin.onPage = (query) =>
            query.playlistId == 'a' ? gate.future : _echo(query);
        final a = env.add(async, 'a', refreshedAgo: const Duration(days: 3));
        final b = env.add(async, 'b', refreshedAgo: const Duration(days: 2));
        env.start(async);
        async.elapse(const Duration(seconds: 1));
        expect(env.queried, ['a'], reason: 'a is in progress');

        _await(async, () => env.repository.setRefreshInterval(a, null));
        _settle(async);
        gate.complete(page(['x']));
        async.elapse(const Duration(seconds: 1));

        expect(env.queried, ['a', 'b']);
        final stopped = env.remote(async, a);
        expect(
          stopped.lastRefreshedAt,
          _start.subtract(const Duration(days: 3)),
        );
        expect(
          _await(async, () => env.repository.entries(a)),
          isEmpty,
          reason: 'the page that arrived after the change was dropped',
        );
        expect(env.remote(async, b).lastResult, PlaylistRefreshResult.complete);
        expect(env.backoffs, 0);
        env.dispose();
      });
    });

    test('a lone cancelled playlist is neither a failure nor a success', () {
      _fake((async) {
        final env = _Env();
        final gate = Completer<PlaylistPage>();
        env.plugin.onPage = (_) => gate.future;
        final a = env.add(async, 'a');
        env.start(async);
        async.elapse(const Duration(seconds: 1));

        _await(async, () => env.repository.setRefreshInterval(a, null));
        _settle(async);
        gate.complete(page(['x']));
        async.elapse(const Duration(seconds: 1));

        // 沒有退避；工作這一輪本身算跑完了。
        expect(env.backoffs, 0);
        final runs = _await(
          async,
          () => env.container.read(schedulerRunsRepositoryProvider).all(),
        );
        expect(runs.keys, contains(playlistRefreshJobId));
        env.dispose();
      });
    });

    test('disabling the source stops the one in progress', () {
      _fake((async) {
        final env = _Env();
        final gate = Completer<PlaylistPage>();
        env.plugin.onPage = (_) => gate.future;
        final a = env.add(async, 'a');
        env.start(async);
        async.elapse(const Duration(seconds: 1));
        expect(env.queried, ['a']);

        env.setPlugins(async, const []);
        gate.complete(page(['x']));
        async.elapse(const Duration(seconds: 1));

        expect(env.remote(async, a).lastRefreshedAt, isNull);
        expect(_await(async, () => env.repository.entries(a)), isEmpty);
        expect(env.backoffs, 0);
        env.dispose();
      });
    });

    test('an interval turned off between the list and its turn is '
        'skipped', () {
      _fake((async) {
        final env = _Env();
        final gate = Completer<PlaylistPage>();
        env.plugin.onPage = (query) =>
            query.playlistId == 'a' ? gate.future : _echo(query);
        final a = env.add(async, 'a', refreshedAgo: const Duration(days: 3));
        final b = env.add(async, 'b', refreshedAgo: const Duration(days: 2));
        env.start(async);
        async.elapse(const Duration(seconds: 1));

        _await(async, () => env.repository.setRefreshInterval(b, null));
        _settle(async);
        gate.complete(page(['a']));
        async.elapse(const Duration(seconds: 1));

        expect(env.queried, ['a']);
        // 關掉的是 b：進行中的 a 不受影響。
        expect(env.remote(async, a).lastResult, PlaylistRefreshResult.complete);
        env.dispose();
      });
    });
  });

  // 每張各取一次刷新器的鎖（design §5.2）：手動刷新最多等目前那一張，排在下一張之前。
  test('a manual refresh waits for the one in progress and goes before the '
      'next', () {
    _fake((async) {
      final env = _Env();
      final gate = Completer<PlaylistPage>();
      env.plugin.onPage = (query) =>
          query.playlistId == 'a' ? gate.future : _echo(query);
      env
        ..add(async, 'a', refreshedAgo: const Duration(days: 3))
        ..add(async, 'b', refreshedAgo: const Duration(days: 2));
      final manual = env.add(
        async,
        'm',
        refreshedAgo: const Duration(hours: 1),
      );
      env.start(async);
      async.elapse(const Duration(seconds: 1));
      expect(env.queried, ['a']);

      unawaited(env.container.read(playlistRefresherProvider).refresh(manual));
      async.elapse(const Duration(seconds: 1));
      expect(env.queried, ['a'], reason: 'one refresh at a time');

      gate.complete(page(['a']));
      async.elapse(const Duration(seconds: 1));
      expect(env.queried, ['a', 'm', 'b']);
      env.dispose();
    });
  });

  test('nothing runs while the app is hidden, and what is due runs once it '
      'is visible again', () {
    _fake((async) {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      final env = _Env();
      env.plugin.onPage = _echo;
      env.add(async, 'a');
      env.start(async);
      async.elapse(const Duration(hours: 2));
      expect(env.queried, isEmpty);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      async.elapse(const Duration(seconds: 1));
      expect(env.queried, ['a']);
      env.dispose();
    });
  });
}
