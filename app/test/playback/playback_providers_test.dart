import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/plugins/plugin_registry.dart';

import '../support/fake_network_interfaces.dart';
import '../support/memory_database.dart';
import '../support/pump_until.dart';
import 'fake_audio_backend.dart';
import 'fake_source_plugin.dart';

/// 組裝點（`playbackControllerProvider`）的接線：資料庫裡的佇列與「播放」設定怎麼
/// 到控制器。控制器與 store 本身的行為在 `queue_store_test.dart`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TrackInfo track(String id) =>
      TrackInfo(sourceTypeId: 'fmp-test', sourceId: id, title: 'Song $id');

  const player = PlayerState(
    currentPosition: 1,
    position: Duration(seconds: 83),
    loopMode: LoopMode.all,
    shuffleEnabled: false,
    volume: 0.4,
    muted: false,
  );

  Future<ProviderContainer> start(
    AppDatabase database, {
    required FakeAudioBackend backend,
    FakeSourcePlugin? plugin,
  }) async {
    final container = ProviderContainer(
      overrides: [
        if (plugin != null)
          pluginRegistryProvider.overrideWithBuild(
            (ref, notifier) => {plugin.manifest.id: plugin},
          ),
        appDatabaseProvider.overrideWithValue(database),
        logProvider.overrideWithValue(
          Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
        ),
        networkInterfacesProvider.overrideWithValue(FakeNetworkInterfaces()),
        audioBackendProvider.overrideWithValue(backend),
        platformCapabilitiesProvider.overrideWithValue(
          const PlatformCapabilities(
            dataDirectory: true,
            singleInstance: false,
            fontFallback: FontFallback.none,
            playback: PlaybackSupport(
              backend: AudioBackendKind.justAudio,
              formats: [PlayableFormat('mp4', 'aac')],
              outputDeviceSelection: false,
            ),
            networkInterfaces: false,
            cache: CacheSizes(
              defaultLimitMebibytes: 1,
              memoryImages: 1,
              memoryImageMebibytes: 1,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> seed(AppDatabase database, {int? restartRewind}) async {
    await QueueRepository(database).write(
      edit: QueueRangeEdit(
        from: 0,
        removed: 0,
        inserted: [track('a'), track('b'), track('c')],
      ),
      player: player,
    );
    if (restartRewind != null) {
      await PlaybackSettingsRepository(database)
          .write(restartRewindSeconds: restartRewind);
    }
  }

  test(
    'the stored queue and the restart rewind reach the controller',
    () async {
      final database = memoryDatabase();
      await seed(database, restartRewind: 10);
      final backend = FakeAudioBackend();
      final container = await start(database, backend: backend);

      // UI 在聽它；沒人聽時 Riverpod 會暫停它依賴的設定串流，讀設定就等不到值。
      container.listen(playbackControllerProvider, (_, _) {});
      final controller = container.read(playbackControllerProvider);
      await pumpUntil(() => controller.queue.entries.isNotEmpty);

      expect(controller.queue.entries.map((e) => e.track.sourceId), [
        'a',
        'b',
        'c',
      ]);
      expect(controller.queue.currentIndex, 1);
      expect(controller.queue.loopMode, LoopMode.all);
      expect(controller.volume, 0.4);
      expect(controller.state, isA<Idle>());
      expect(controller.position, const Duration(seconds: 73));
      expect(backend.opened, isEmpty, reason: 'nothing is loaded before play');
    },
  );

  test('without a stored rewind the position is the stored one', () async {
    final database = memoryDatabase();
    await seed(database);
    final container = await start(database, backend: FakeAudioBackend());

    // UI 在聽它；沒人聽時 Riverpod 會暫停它依賴的設定串流，讀設定就等不到值。
    container.listen(playbackControllerProvider, (_, _) {});
    final controller = container.read(playbackControllerProvider);
    await pumpUntil(() => controller.queue.entries.isNotEmpty);

    expect(controller.position, const Duration(seconds: 83));
  });

  test('the queue starts empty when nothing was stored', () async {
    final database = memoryDatabase();
    final container = await start(database, backend: FakeAudioBackend());

    // UI 在聽它；沒人聽時 Riverpod 會暫停它依賴的設定串流，讀設定就等不到值。
    container.listen(playbackControllerProvider, (_, _) {});
    final controller = container.read(playbackControllerProvider);
    await settle();

    expect(controller.queue.entries, isEmpty);
    expect(controller.state, isA<Idle>());
  });

  // design §7.8：控制器報的播放由記錄者寫進歷史，保留筆數讀「播放」設定。
  group('play history', () {
    Future<List<String>> historyTitles(AppDatabase database) async => [
      for (final entry in await PlayHistoryRepository(database).page(limit: 10))
        entry.track.sourceId,
    ];

    /// 等歷史裡的曲目 id 符合 [expected]（資料庫在 drift 的 isolate，要讓事件佇列跑）。
    Future<void> historyBecomes(
      AppDatabase database,
      List<String> expected,
    ) async {
      var ids = <String>[];
      for (var round = 0; round < 50; round++) {
        ids = await historyTitles(database);
        if (ids.length == expected.length && ids.join() == expected.join()) {
          return;
        }
        await settle();
      }
      expect(ids, expected);
    }

    test('a counted play is written to the history', () async {
      final database = memoryDatabase();
      final plugin = FakeSourcePlugin(
        (request) => [candidate('${request.sourceId}.m4a')],
      );
      final container = await start(
        database,
        backend: FakeAudioBackend(),
        plugin: plugin,
      );
      container.listen(playbackControllerProvider, (_, _) {});
      final controller = container.read(playbackControllerProvider);

      await controller.playTemporary(track('a'));

      await historyBecomes(database, ['a']);
    });

    test('the stored retention limit applies to what is written', () async {
      final database = memoryDatabase();
      await PlaybackSettingsRepository(database).write(playHistoryLimit: 1);
      final plugin = FakeSourcePlugin(
        (request) => [candidate('${request.sourceId}.m4a')],
      );
      final container = await start(
        database,
        backend: FakeAudioBackend(),
        plugin: plugin,
      );
      container.listen(playbackControllerProvider, (_, _) {});
      final controller = container.read(playbackControllerProvider);

      await controller.playTemporary(track('a'));
      await historyBecomes(database, ['a']);
      await controller.playTemporary(track('b'));

      await historyBecomes(database, ['b']);
    });
  });
}
