import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/domain/radio.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/radio/radio_service.dart';
import 'package:fmp/radio/radio_status_jobs.dart';
import 'package:fmp/scheduler/background_scheduler.dart';
import 'package:fmp/settings/network_settings.dart';

import '../playback/fake_source_plugin.dart';
import '../support/fake_network_interfaces.dart';
import '../support/memory_database.dart';

/// 測試設定插件清單的 provider：改它就等於插件清單改變（啟用、停用、安裝、移除）。
final _testPlugins = NotifierProvider<_TestPlugins, Map<String, SourcePlugin>>(
  _TestPlugins.new,
);

final class _TestPlugins extends Notifier<Map<String, SourcePlugin>> {
  @override
  Map<String, SourcePlugin> build() => const {};

  void set(Map<String, SourcePlugin> plugins) => state = plugins;
}

FakeSourcePlugin _plugin(String id) =>
    FakeSourcePlugin((_) => const [], id: id, live: true)
      ..onLiveStatus = ((query) => _room(query.roomId));

LiveRoom _room(
  String roomId, {
  LiveRoomStatus status = LiveRoomStatus.live,
  String title = 'On air',
  int? online,
}) => LiveRoom(roomId: roomId, title: title, status: status, online: online);

/// 資料庫、真的排程器與網路狀態，插件由 [plugins] 決定。
final class _Env {
  _Env({this.online = true, List<FakeSourcePlugin>? plugins}) {
    this.plugins = plugins ?? [_plugin('bilibili')];
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
        pluginRegistryProvider.overrideWithBuild(
          (ref, notifier) => ref.watch(_testPlugins),
        ),
      ],
    );
  }

  final bool online;
  final database = memoryDatabase();
  late final List<FakeSourcePlugin> plugins;
  late final FakeNetworkInterfaces interfaces;
  late final Log log;
  late final ProviderContainer container;

  RadioRepository get repository => container.read(radioRepositoryProvider);
  RadioService get service => container.read(radioServiceProvider);

  /// 插件清單變成 [plugins]（預設是全部）。
  void setPlugins(FakeAsync async, [Iterable<FakeSourcePlugin>? plugins]) {
    container.read(_testPlugins.notifier).set({
      for (final plugin in plugins ?? this.plugins) plugin.manifest.id: plugin,
    });
    // 依賴改了的 provider 在測試 binding 裡不會自己重建（沒有影格），讀它才會。
    container.read(pluginRegistryProvider);
    _settle(async);
  }

  /// 排程器、電台狀態工作與它的輸入都建起來。
  void start(FakeAsync async) {
    container
      ..listen(networkStatusProvider, (_, _) {})
      ..listen(networkProvider, (_, _) {})
      ..listen(radioEntriesProvider, (_, _) {})
      ..read(backgroundSchedulerProvider)
      ..read(radioStatusJobsProvider);
    setPlugins(async);
    async.flushMicrotasks();
  }

  Future<bool> add(String pluginId, String roomId, {RadioLiveStatus? status}) =>
      repository.add(
        pluginId: pluginId,
        roomId: roomId,
        title: 'Station $roomId',
        addedAt: DateTime.utc(2026, 10, 14),
        liveStatus: status,
      );

  Future<void> setInterval(FakeAsync async, int? minutes) async {
    unawaited(
      container.read(networkProvider.notifier).setRadioStatusInterval(minutes),
    );
    _settle(async);
  }

  /// 目前電台的顯示狀態，依 id 排序前的清單順序。
  List<RadioStatus> statuses(FakeAsync async) => _await(async, () async {
    return [
      for (final entry in container.read(radioEntriesProvider).requireValue)
        entry.status,
    ];
  });

  /// 資料庫裡每個電台最後一次查到的狀態。
  List<RadioLiveStatus?> stored(FakeAsync async) => _await(async, () async {
    return [for (final station in await repository.list()) station.liveStatus];
  });

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
    fakeAsync(body, initialTime: DateTime.utc(2026, 10, 14, 12));

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

  group('adding a station by URL', () {
    test('the first plugin that recognizes the URL wins', () async {
      final first = _plugin('first')..onLiveRoomFromUrl = ((_) => null);
      final second = _plugin('second')
        ..onLiveRoomFromUrl = ((_) => const LiveRoomRef(roomId: 'x'));
      final third = _plugin('third')
        ..onLiveRoomFromUrl = ((_) => const LiveRoomRef(roomId: 'y'));
      final env = _Env(plugins: [first, second, third]);
      addTearDown(env.dispose);
      env.container.read(_testPlugins.notifier).set({
        for (final p in env.plugins) p.manifest.id: p,
      });

      final result = await env.service.addFromUrl(' https://live.test/x ');

      expect(result, AddRadioResult.added);
      expect(first.liveUrlQueries.single.url, 'https://live.test/x');
      expect(second.liveUrlQueries, hasLength(1));
      expect(third.liveUrlQueries, isEmpty, reason: 'after the winner');
      final station = (await env.repository.list()).single;
      expect((station.pluginId, station.roomId), ('second', 'x'));
      expect(station.title, 'On air');
      expect(station.liveStatus, RadioLiveStatus.live);
    });

    test('says so when no plugin recognizes the URL', () async {
      final plugin = _plugin('p')..onLiveRoomFromUrl = ((_) => null);
      final env = _Env(plugins: [plugin]);
      addTearDown(env.dispose);
      env.container.read(_testPlugins.notifier).set({'p': plugin});

      expect(
        await env.service.addFromUrl('https://example.test/'),
        AddRadioResult.unrecognizedUrl,
      );
      expect(
        await env.service.addFromUrl('   '),
        AddRadioResult.unrecognizedUrl,
      );
      expect(await env.repository.list(), isEmpty);
      expect(plugin.liveStatusQueries, isEmpty);
    });

    test('writes and compares the room id that liveStatus returns, not the '
        'one in the URL', () async {
      // B 站短號 1 回長號 5440。
      final plugin = _plugin('p')
        ..onLiveRoomFromUrl = ((_) => const LiveRoomRef(roomId: '1'))
        ..onLiveStatus = ((_) => _room('5440'));
      final env = _Env(plugins: [plugin]);
      addTearDown(env.dispose);
      env.container.read(_testPlugins.notifier).set({'p': plugin});

      expect(
        await env.service.addFromUrl('https://live.test/1'),
        AddRadioResult.added,
      );
      expect((await env.repository.list()).single.roomId, '5440');
      // 第二次用網址裡的另一種寫法，仍是同一個房間。
      expect(
        await env.service.addFromUrl('https://live.test/5440'),
        AddRadioResult.alreadyAdded,
      );
      expect(await env.repository.list(), hasLength(1));
    });

    test('never asks a plugin that is disabled, removed or has no live '
        'capability', () async {
      final enabled = _plugin('enabled')..onLiveRoomFromUrl = ((_) => null);
      final disabled = _plugin('disabled')
        ..onLiveRoomFromUrl = ((_) => const LiveRoomRef(roomId: 'z'));
      final noLive = FakeSourcePlugin((_) => const [], id: 'no-live')
        ..onLiveRoomFromUrl = ((_) => const LiveRoomRef(roomId: 'q'));
      final env = _Env(plugins: [enabled, disabled, noLive]);
      addTearDown(env.dispose);
      // 停用的插件不在清單上。
      env.container.read(_testPlugins.notifier).set({
        'enabled': enabled,
        'no-live': noLive,
      });

      expect(
        await env.service.addFromUrl('https://live.test/z'),
        AddRadioResult.unrecognizedUrl,
      );
      expect(enabled.liveUrlQueries, hasLength(1));
      expect(disabled.liveUrlQueries, isEmpty);
      expect(noLive.liveUrlQueries, isEmpty);
    });

    test('a failing plugin call is passed on, nothing is written', () async {
      final plugin = _plugin('p')
        ..onLiveRoomFromUrl = ((_) => const LiveRoomRef(roomId: 'x'))
        ..onLiveStatus = ((_) => throw NetworkError(pluginId: 'p'));
      final env = _Env(plugins: [plugin]);
      addTearDown(env.dispose);
      env.container.read(_testPlugins.notifier).set({'p': plugin});

      await expectLater(
        env.service.addFromUrl('https://live.test/x'),
        throwsA(isA<NetworkError>()),
      );
      expect(await env.repository.list(), isEmpty);
    });
    test('a failure that is not an AppError reaches the caller as one, and '
        'the next plugin is not asked', () async {
      final broken = _plugin('broken')
        ..onLiveRoomFromUrl = ((_) => throw StateError('isolate gone'));
      final next = _plugin('next')
        ..onLiveRoomFromUrl = ((_) => const LiveRoomRef(roomId: 'x'))
        ..onLiveStatus = ((query) => LiveRoom(
          roomId: query.roomId,
          title: 'Room',
          status: LiveRoomStatus.live,
        ));
      final env = _Env(plugins: [broken, next]);
      addTearDown(env.dispose);
      env.container.read(_testPlugins.notifier).set({
        'broken': broken,
        'next': next,
      });

      await expectLater(
        env.service.addFromUrl('https://live.test/x'),
        throwsA(isA<UnexpectedError>()),
      );
      expect(next.liveUrlQueries, isEmpty);
      expect(await env.repository.list(), isEmpty);
    });
  });

  group('adding a search result as a station', () {
    test(
      'writes it with its status, and a duplicate says already added',
      () async {
        final env = _Env();
        addTearDown(env.dispose);
        final room = LiveRoom(
          roomId: '77',
          title: 'Evening show',
          hostName: 'Host',
          artwork: [Artwork(url: Uri.parse('https://example.test/c.jpg'))],
          status: LiveRoomStatus.offline,
        );

        expect(
          await env.service.addRoom('bilibili', room),
          AddRadioResult.added,
        );
        expect(
          await env.service.addRoom('bilibili', room),
          AddRadioResult.alreadyAdded,
        );

        final station = (await env.repository.list()).single;
        expect(station.title, 'Evening show');
        expect(station.hostName, 'Host');
        expect(
          station.artwork.single.url.toString(),
          'https://example.test/c.jpg',
        );
        expect(station.liveStatus, RadioLiveStatus.offline);
        expect(station.statusCheckedAt, isNotNull);
      },
    );

    test('remove and reorder go to the repository', () async {
      final env = _Env();
      addTearDown(env.dispose);
      for (final room in ['a', 'b', 'c']) {
        await env.add('bilibili', room);
      }
      final ids = {for (final s in await env.repository.list()) s.roomId: s.id};

      await env.service.reorder([ids['c']!, ids['b']!, ids['a']!]);
      await env.service.remove(ids['b']!);

      expect(
        [for (final s in await env.repository.list()) s.roomId],
        ['c', 'a'],
      );
    });
  });

  group('the four states of a station', () {
    test('live, offline, never checked, and a failed query that is neither '
        'offline nor stored', () {
      _fake((async) {
        final env = _Env();
        final plugin = env.plugins.single;
        // 四個電台：開播中、未開播、還沒查過（沒有 job 的插件）、查詢失敗。
        _await(async, () async {
          await env.add('bilibili', 'live', status: RadioLiveStatus.live);
          await env.add('bilibili', 'offline', status: RadioLiveStatus.offline);
          await env.add('other', 'unchecked');
          await env.add('bilibili', 'broken', status: RadioLiveStatus.live);
        });
        plugin.onLiveStatus = (query) => query.roomId == 'broken'
            ? throw NetworkError(pluginId: 'bilibili')
            : _room(
                query.roomId,
                status: query.roomId == 'offline'
                    ? LiveRoomStatus.offline
                    : LiveRoomStatus.live,
              );
        env.start(async);
        async.elapse(const Duration(seconds: 1));

        expect(env.statuses(async), [
          RadioStatus.live,
          RadioStatus.offline,
          RadioStatus.unchecked,
          RadioStatus.queryFailed,
        ]);
        // 「查詢失敗」不寫進資料庫，也沒有把原本存的狀態改成未開播。
        expect(env.stored(async), [
          RadioLiveStatus.live,
          RadioLiveStatus.offline,
          null,
          RadioLiveStatus.live,
        ]);
        env.dispose();
      });
    });

    test('a failed query clears when the next check works', () {
      _fake((async) {
        final env = _Env();
        final plugin = env.plugins.single;
        _await(async, () => env.add('bilibili', 'a'));
        plugin.onLiveStatus = (_) => throw NetworkError(pluginId: 'bilibili');
        env.start(async);
        async.elapse(const Duration(seconds: 1));
        expect(env.statuses(async), [RadioStatus.queryFailed]);

        plugin.onLiveStatus = (query) => _room(query.roomId);
        unawaited(env.service.refresh());
        _settle(async);

        expect(env.statuses(async), [RadioStatus.live]);
        env.dispose();
      });
    });
  });

  group('the status job', () {
    test('queries every station of the plugin in order and stores the '
        'result', () {
      _fake((async) {
        final env = _Env();
        _await(async, () async {
          await env.add('bilibili', 'a');
          await env.add('bilibili', 'b');
          await env.add('other', 'c');
        });
        env.plugins.single.onLiveStatus = (query) => _room(
          query.roomId,
          status: query.roomId == 'b'
              ? LiveRoomStatus.offline
              : LiveRoomStatus.live,
          title: 'Title ${query.roomId}',
        );
        env.start(async);
        async.elapse(const Duration(seconds: 1));

        expect(
          [for (final q in env.plugins.single.liveStatusQueries) q.roomId],
          ['a', 'b'],
        );
        expect(env.stored(async), [
          RadioLiveStatus.live,
          RadioLiveStatus.offline,
          null,
        ]);
        final list = _await(async, env.repository.list);
        expect(list.first.liveTitle, 'Title a');
        expect(list.first.statusCheckedAt, DateTime.utc(2026, 10, 14, 12));
        env.dispose();
      });
    });

    test('one failing station fails only its own row and the job still '
        'counts as done', () {
      _fake((async) {
        final env = _Env();
        _await(async, () async {
          await env.add('bilibili', 'a');
          await env.add('bilibili', 'bad');
          await env.add('bilibili', 'c');
        });
        env.plugins.single.onLiveStatus = (query) => query.roomId == 'bad'
            ? throw NetworkError(pluginId: 'bilibili')
            : _room(query.roomId);
        env.start(async);
        async.elapse(const Duration(seconds: 1));

        expect(env.statuses(async), [
          RadioStatus.live,
          RadioStatus.queryFailed,
          RadioStatus.live,
        ]);
        // 沒有退避，也記了成功時間：下一次是 5 分鐘後。
        expect(
          env.log.history.where(
            (r) => r.message == 'Background job backed off',
          ),
          isEmpty,
        );
        final runs = _await(
          async,
          () => env.container.read(schedulerRunsRepositoryProvider).all(),
        );
        expect(runs.keys, contains('radio-status:bilibili'));
        async.elapse(const Duration(minutes: 4, seconds: 58));
        expect(env.plugins.single.liveStatusQueries, hasLength(3));
        async.elapse(const Duration(seconds: 5));
        expect(env.plugins.single.liveStatusQueries, hasLength(6));
        env.dispose();
      });
    });

    test('when every station fails the job fails and backs off', () {
      _fake((async) {
        final env = _Env();
        _await(async, () async {
          await env.add('bilibili', 'a');
          await env.add('bilibili', 'b');
        });
        env.plugins.single.onLiveStatus = (_) =>
            throw NetworkError(pluginId: 'bilibili');
        env.start(async);
        async.elapse(const Duration(seconds: 1));

        expect(env.statuses(async), [
          RadioStatus.queryFailed,
          RadioStatus.queryFailed,
        ]);
        expect(
          env.log.history.where(
            (r) => r.message == 'Background job backed off',
          ),
          hasLength(1),
        );
        final runs = _await(
          async,
          () => env.container.read(schedulerRunsRepositoryProvider).all(),
        );
        expect(runs, isEmpty, reason: 'a failed job has no success time');
        env.dispose();
      });
    });

    test('a result that arrives after the plugin was disabled is dropped', () {
      _fake((async) {
        final env = _Env();
        _await(async, () => env.add('bilibili', 'a'));
        final gate = Completer<LiveRoom>();
        env.plugins.single.onLiveStatus = (_) => gate.future;
        env.start(async);
        async.elapse(const Duration(seconds: 1));
        expect(env.plugins.single.liveStatusQueries, hasLength(1));

        env.setPlugins(async, const []);
        gate.complete(_room('a'));
        _settle(async);
        async.elapse(const Duration(seconds: 1));

        expect(env.stored(async), [null]);
        expect(env.statuses(async), [RadioStatus.unchecked]);
        env.dispose();
      });
    });

    test('follows the plugin list: disabling stops it, enabling again '
        'brings it back', () {
      _fake((async) {
        final env = _Env();
        _await(async, () => env.add('bilibili', 'a'));
        env.start(async);
        async.elapse(const Duration(seconds: 1));
        final plugin = env.plugins.single;
        expect(plugin.liveStatusQueries, hasLength(1));

        env.setPlugins(async, const []);
        async.elapse(const Duration(hours: 1));
        expect(plugin.liveStatusQueries, hasLength(1), reason: 'disabled');

        // 重新啟用是新的插件實例；停用了一小時，上次成功早就過期，回來馬上查。
        final reloaded = _plugin('bilibili');
        env.setPlugins(async, [reloaded]);
        async.elapse(const Duration(seconds: 1));
        expect(reloaded.liveStatusQueries, hasLength(1));
        async.elapse(const Duration(minutes: 5, seconds: 1));
        expect(reloaded.liveStatusQueries, hasLength(2));
        env.dispose();
      });
    });

    test('follows the station list: the first station starts the job, the '
        'last one stops it', () {
      _fake((async) {
        final env = _Env();
        env.start(async);
        async.elapse(const Duration(minutes: 30));
        final plugin = env.plugins.single;
        expect(plugin.liveStatusQueries, isEmpty, reason: 'no stations');
        expect(
          env.container
              .read(radioStatusJobsProvider.notifier)
              .registeredPluginIds(),
          isEmpty,
        );

        _await(async, () => env.add('bilibili', 'a'));
        async.elapse(const Duration(seconds: 1));
        expect(plugin.liveStatusQueries, hasLength(1));

        // 第二個電台加進來不打斷、不另開一個工作；下一次到期時一起查。
        _await(async, () => env.add('bilibili', 'b'));
        async.elapse(const Duration(seconds: 1));
        expect(plugin.liveStatusQueries, hasLength(1));
        async.elapse(const Duration(minutes: 5));
        expect(plugin.liveStatusQueries, hasLength(3));

        _await(async, () async {
          for (final station in await env.repository.list()) {
            await env.repository.remove(station.id);
          }
        });
        async.elapse(const Duration(hours: 1));
        expect(plugin.liveStatusQueries, hasLength(3));
        expect(
          env.container
              .read(radioStatusJobsProvider.notifier)
              .registeredPluginIds(),
          isEmpty,
        );
        env.dispose();
      });
    });

    test('an interval change takes effect, and 0 turns the schedule off '
        'but not the refresh', () {
      _fake((async) {
        final env = _Env();
        _await(async, () => env.add('bilibili', 'a'));
        env.start(async);
        final plugin = env.plugins.single;
        async.elapse(const Duration(seconds: 1));
        expect(plugin.liveStatusQueries, hasLength(1));

        // 間隔改成 1 分：從上次成功算起，不是從改設定那一刻算起。
        unawaited(env.setInterval(async, 1));
        async.elapse(const Duration(seconds: 57));
        expect(plugin.liveStatusQueries, hasLength(1));
        async.elapse(const Duration(seconds: 3));
        expect(plugin.liveStatusQueries, hasLength(2));
        async.elapse(const Duration(minutes: 1));
        expect(plugin.liveStatusQueries, hasLength(3));

        unawaited(env.setInterval(async, 0));
        async.elapse(const Duration(hours: 2));
        expect(plugin.liveStatusQueries, hasLength(3), reason: 'off');

        unawaited(env.service.refresh());
        _settle(async);
        expect(plugin.liveStatusQueries, hasLength(4), reason: 'manual');
        env.dispose();
      });
    });

    test('does not run while the app is hidden or the network is offline', () {
      _fake((async) {
        final env = _Env(online: false);
        _await(async, () => env.add('bilibili', 'a'));
        env.start(async);
        async.elapse(const Duration(hours: 1));
        expect(env.plugins.single.liveStatusQueries, isEmpty);

        env.interfaces.change(available: true);
        async.flushMicrotasks();
        expect(env.plugins.single.liveStatusQueries, hasLength(1));
        env.dispose();
      });
    });
  });

  group('refreshing by hand', () {
    test('runs every plugin job whatever the interval says', () {
      _fake((async) {
        final bilibili = _plugin('bilibili');
        final other = _plugin('other');
        final env = _Env(plugins: [bilibili, other]);
        _await(async, () async {
          await env.add('bilibili', 'a');
          await env.add('other', 'b');
        });
        env.start(async);
        async.elapse(const Duration(seconds: 1));
        unawaited(env.setInterval(async, 0));
        final before = (
          bilibili.liveStatusQueries.length,
          other.liveStatusQueries.length,
        );

        final result = _await(async, env.service.refresh);

        expect(result, RadioRefreshResult.completed);
        expect(bilibili.liveStatusQueries.length, before.$1 + 1);
        expect(other.liveStatusQueries.length, before.$2 + 1);
        env.dispose();
      });
    });

    test('tells offline from done, and nothing to refresh from both', () {
      _fake((async) {
        final env = _Env();
        env.start(async);
        expect(
          _await(async, env.service.refresh),
          RadioRefreshResult.nothingToRefresh,
        );

        _await(async, () => env.add('bilibili', 'a'));
        async.elapse(const Duration(seconds: 1));
        env.interfaces.change(available: false);
        async.flushMicrotasks();
        final queries = env.plugins.single.liveStatusQueries.length;

        expect(_await(async, env.service.refresh), RadioRefreshResult.offline);
        expect(env.plugins.single.liveStatusQueries, hasLength(queries));
        env.dispose();
      });
    });

    test('hands the error to the caller when every station failed', () {
      _fake((async) {
        final env = _Env();
        _await(async, () => env.add('bilibili', 'a'));
        env.start(async);
        async.elapse(const Duration(seconds: 1));
        env.plugins.single.onLiveStatus = (_) =>
            throw NetworkError(pluginId: 'bilibili');

        Object? error;
        unawaited(
          env.service.refresh().then<void>((_) {}, onError: (e) => error = e),
        );
        async.flushMicrotasks();

        expect(error, isA<NetworkError>());
        env.dispose();
      });
    });
  });
}
