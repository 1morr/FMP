import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/scheduler/background_scheduler.dart';

import '../support/fake_network_interfaces.dart';
import '../support/memory_database.dart';
import 'fake_audio_backend.dart';
import 'fake_source_plugin.dart';

/// `playbackControllerProvider` 把控制器的 `live-info` 登記到真的排程器（接線）：
/// 工作 id、所屬插件與固定 1 分鐘的間隔；控制器本身的行為在 `live_playback_test.dart`。
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

  const target = LiveTarget(pluginId: 'fmp-test', roomId: 'r1', title: 'Room');

  test('the job id and interval are fixed', () {
    expect(liveInfoJobId, 'live-info');
    expect(liveInfoInterval, const Duration(minutes: 1));
  });

  test('is scheduled every minute while listening and gone after stopping', () {
    fakeAsync((async) {
      final plugin = FakeSourcePlugin((_) => const [], live: true)
        ..onResolveLive = ((request) => [candidate('${request.roomId}.flv')])
        ..onLiveStatus = ((query) => LiveRoom(
          roomId: query.roomId,
          title: 'Room',
          status: LiveRoomStatus.live,
          online: 10,
        ));
      final container = _container(plugin);
      addTearDown(container.dispose);
      container
        ..listen(playbackControllerProvider, (_, _) {})
        ..listen(playbackLiveProvider, (_, _) {})
        ..read(backgroundSchedulerProvider);
      final controller = container.read(playbackControllerProvider);
      async.elapse(const Duration(seconds: 1));
      container.read(pluginRegistryProvider);

      unawaited(controller.playLive(target));
      async.elapse(const Duration(seconds: 2));
      // 登記後馬上跑一次（沒有上次成功時間）。
      expect(plugin.liveStatusQueries, hasLength(1));
      expect(controller.live?.online, 10);

      async.elapse(const Duration(seconds: 56));
      expect(
        plugin.liveStatusQueries,
        hasLength(1),
        reason: 'not yet a minute',
      );
      async.elapse(const Duration(seconds: 4));
      expect(plugin.liveStatusQueries, hasLength(2));
      async.elapse(const Duration(minutes: 1));
      expect(plugin.liveStatusQueries, hasLength(3));

      unawaited(controller.stopLive());
      async.elapse(const Duration(minutes: 10));
      expect(plugin.liveStatusQueries, hasLength(3), reason: 'removed');
      container.dispose();
    });
  });

  // 控制器在 provider 的 onDispose 裡釋放，那裡不能碰別的 provider（Riverpod 3 的
  // assert）；釋放時還在收聽的話，`live-info` 仍要從排程器移除。
  test('rebuilding the controller while listening removes the job', () {
    fakeAsync((async) {
      final plugin = FakeSourcePlugin((_) => const [], live: true)
        ..onResolveLive = ((request) => [candidate('${request.roomId}.flv')])
        ..onLiveStatus = ((query) => LiveRoom(
          roomId: query.roomId,
          title: 'Room',
          status: LiveRoomStatus.live,
        ));
      final container = _container(plugin);
      addTearDown(container.dispose);
      container
        ..listen(playbackControllerProvider, (_, _) {})
        ..read(backgroundSchedulerProvider);
      final controller = container.read(playbackControllerProvider);
      async.elapse(const Duration(seconds: 1));
      container.read(pluginRegistryProvider);

      unawaited(controller.playLive(target));
      async.elapse(const Duration(seconds: 2));
      expect(plugin.liveStatusQueries, hasLength(1));

      container.invalidate(playbackControllerProvider);
      expect(container.read(playbackControllerProvider), isNot(controller));
      async.elapse(const Duration(minutes: 10));
      expect(plugin.liveStatusQueries, hasLength(1), reason: 'removed');
      RunNowResult? result;
      unawaited(
        container
            .read(backgroundSchedulerProvider.notifier)
            .runNow(liveInfoJobId)
            .then((value) => result = value),
      );
      async.flushMicrotasks();
      expect(result, RunNowResult.unknown);
      container.dispose();
    });
  });
}

/// 真的排程器與控制器，插件只有 [plugin]。
ProviderContainer _container(FakeSourcePlugin plugin) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(memoryDatabase()),
      logProvider.overrideWithValue(
        Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
      ),
      networkInterfacesProvider.overrideWithValue(FakeNetworkInterfaces()),
      audioBackendProvider.overrideWithValue(
        FakeAudioBackend(durationOf: (_) => const Duration(hours: 1)),
      ),
      systemMediaControlsProvider.overrideWithValue(null),
      pluginRegistryProvider.overrideWithBuild(
        (ref, notifier) => {'fmp-test': plugin},
      ),
      platformCapabilitiesProvider.overrideWithValue(
        const PlatformCapabilities(
          dataDirectory: true,
          singleInstance: false,
          secureStorage: false,
          fontFallback: FontFallback.none,
          playback: PlaybackSupport(
            backend: AudioBackendKind.justAudio,
            formats: [PlayableFormat('mp4', 'aac')],
            outputDeviceSelection: false,
          ),
          networkInterfaces: false,
          files: false,
          loginWebView: false,
          urlOpener: false,
          restartsItself: false,
          shareFiles: false,
          pluginDevTools: false,
          cache: CacheSizes(
            defaultLimitMebibytes: 1,
            memoryImages: 1,
            memoryImageMebibytes: 1,
          ),
        ),
      ),
    ],
  );
}
