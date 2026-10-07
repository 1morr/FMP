import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/app/app_lifecycle.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/backends/audio_backends.dart';
import 'package:fmp/playback/now_playing_publisher.dart';
import 'package:fmp/playback/play_history_recorder.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_events.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_store.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/playback/stream_resolver.dart';
import 'package:fmp/plugins/plugin_artwork.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/settings/playback_settings.dart';

/// 平台宣告的播放能力；沒有時（未驗證的平台）讀它會拋 `Unsupported`。那些
/// 平台在 `main()` 就只開「此平台尚未支援」，走不到這裡。
final _playbackSupportProvider = Provider<PlaybackSupport>(
  (ref) =>
      ref.watch(platformCapabilitiesProvider).playback ?? (throw Unsupported()),
);

/// 整個 App 唯一的播放後端（Android 的音訊焦點見 `AudioBackend`）。
final audioBackendProvider = Provider<AudioBackend>((ref) {
  final backend = createAudioBackend(
    ref.watch(_playbackSupportProvider),
    log: ref.watch(logProvider),
  );
  ref.onDispose(() => unawaited(backend.dispose()));
  return backend;
});

/// 臨時播放回到佇列時要的兩個「播放」設定值。資料庫的值還沒讀出來時是預設。
final temporaryReturnSettingsProvider = Provider<TemporaryReturnSettings>((
  ref,
) {
  final preferences =
      ref.watch(playbackPreferencesProvider).value ??
      PlaybackPreferencesNotifier.resolve(PlaybackSettings.empty);
  return (
    rememberPosition: preferences.rememberPosition,
    rewind: Duration(seconds: preferences.tempPlayRewindSeconds),
  );
});

/// 「跳過試聽片段」（預設開）。資料庫的值還沒讀出來時是預設。
final skipPreviewClipsProvider = Provider<bool>(
  (ref) =>
      (ref.watch(playbackPreferencesProvider).value ??
              PlaybackPreferencesNotifier.resolve(PlaybackSettings.empty))
          .skipPreviewClips,
);

/// 解析串流時送給插件的偏好（音質、格式偏好）。資料庫的值還沒讀出來時是預設。
final streamPreferencesProvider = Provider<StreamPreferences>((ref) {
  final preferences =
      ref.watch(playbackPreferencesProvider).value ??
      PlaybackPreferencesNotifier.resolve(PlaybackSettings.empty);
  return (
    quality: preferences.audioQuality,
    formatPriority: preferences.audioFormatPriority,
  );
});

/// UI 唯一的播放入口（ADR 0018 §決定 1）。
final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final log = ref.watch(logProvider);
  // 設定在用到時才讀（臨時播放結束、遇到試聽片段、每次解析）：先訂閱，資料庫
  // 的值那時已經讀出來；不用 watch，改設定不重建控制器。網路狀態同樣不重建，
  // 改變經 stream 交給控制器。
  ref.listen(temporaryReturnSettingsProvider, (_, _) {});
  ref.listen(skipPreviewClipsProvider, (_, _) {});
  ref.listen(streamPreferencesProvider, (_, _) {});
  ref.listen(playbackPreferencesProvider, (_, _) {});
  final networkChanges = StreamController<NetworkStatus>.broadcast();
  ref.listen(networkStatusProvider, (_, status) => networkChanges.add(status));
  final controller = PlaybackController(
    session: PlaybackSession(
      backend: ref.watch(audioBackendProvider),
      resolver: StreamResolver(
        plugin: (pluginId) => ref.read(pluginRegistryProvider).value?[pluginId],
        formats: ref.watch(_playbackSupportProvider).formats,
        preferences: () => ref.read(streamPreferencesProvider),
        log: log,
      ),
      log: log,
    ),
    log: log,
    temporaryReturnSettings: () => ref.read(temporaryReturnSettingsProvider),
    skipPreviewClips: () => ref.read(skipPreviewClipsProvider),
    networkStatus: () => ref.read(networkStatusProvider),
    networkStatusChanges: networkChanges.stream,
    // 裝置清單第一次就緒時才讀：等資料庫的值讀出來，不拿還沒載入的空設定。
    preferredOutputDevice: () async =>
        (await ref.read(playbackPreferencesProvider.future)).outputDevice?.id,
    saveOutputDevice: (device) =>
        ref.read(playbackPreferencesProvider.notifier).setOutputDevice(device),
  );
  // 佇列與播放狀態的持久化（design §7.7）：讀回上次的狀態交給控制器（`Idle`、
  // 不解析），再跟著它存。重啟倒退的兩個設定在恢復時讀一次，等資料庫的值讀出來。
  final lifecycleChanges = StreamController<AppLifecycleState>.broadcast();
  ref.listen(appLifecycleProvider, (_, state) => lifecycleChanges.add(state));
  final store = QueueStore(
    repository: ref.watch(queueRepositoryProvider),
    log: log,
  );
  unawaited(
    store.attach(
      controller,
      lifecycle: lifecycleChanges.stream,
      restartSettings: () async {
        final preferences = await ref.read(playbackPreferencesProvider.future);
        return (
          rememberPosition: preferences.rememberPosition,
          rewind: Duration(seconds: preferences.restartRewindSeconds),
        );
      },
    ),
  );
  // 播放歷史（design §7.8）：控制器報「這一首算一次播放」，記錄者寫進資料庫。
  final recorder = PlayHistoryRecorder(
    repository: ref.watch(playHistoryRepositoryProvider),
    limit: () async =>
        (await ref.read(playbackPreferencesProvider.future)).playHistoryLimit,
    log: log,
  )..listen(controller.plays);
  // 系統媒體控制（design §8.2）：平台宣告有而且初始化成功才建。
  final mediaControls =
      ref.read(platformCapabilitiesProvider).mediaControls == null
      ? null
      : ref.read(systemMediaControlsProvider);
  final publisher = mediaControls == null
      ? null
      : (NowPlayingPublisher(
          controls: mediaControls,
          artworkFile: (track) => _artworkFile(ref, track),
          log: log,
        )..attach(controller));
  ref.onDispose(() {
    publisher?.dispose();
    recorder.dispose();
    store.dispose();
    unawaited(lifecycleChanges.close());
    unawaited(controller.dispose());
    unawaited(networkChanges.close());
  });
  return controller;
});

/// 系統媒體控制的封面：[track] 的封面經它的插件的 cache manager 取得本機檔
/// （統一快取庫、每跳檢查、大小上限都套用）。通知上的封面較大，挑 512 px。
///
/// 快取庫第一次被讀時才開、插件清單在啟動時載入：啟動恢復的那首在兩者好之前就要
/// 封面，所以先等它們（快取庫開不起來就丟出，publisher 當作沒有封面）。publisher
/// 每首只問一次，這時回 `null` 那首在通知上就一直沒有封面。
Future<Uri?> _artworkFile(Ref ref, TrackInfo track) async {
  final picked = pickArtwork(track.artwork, 512);
  if (picked == null) return null;
  await ref.read(cacheStoreProvider.future);
  await ref.read(pluginRegistryProvider.future);
  final manager = ref.read(artworkCacheManagerProvider(track.sourceTypeId));
  if (manager == null) return null;
  final file = await manager.getSingleFile(picked.url.toString());
  return file.uri;
}

/// 播放狀態：先給目前的值，之後每次改變。
final playbackStateProvider = StreamProvider<PlaybackState>((ref) async* {
  final controller = ref.watch(playbackControllerProvider);
  yield controller.state;
  yield* controller.states;
});

/// 佇列：先給目前的值，之後每次改變。
final playbackQueueProvider = StreamProvider<QueueState>((ref) async* {
  final controller = ref.watch(playbackControllerProvider);
  yield controller.queue;
  yield* controller.queueStates;
});

/// 播放控制器的一次性事件（design §7.9）。外殼以 `ref.listen` 轉成提示。
final playbackEventsProvider = StreamProvider<PlaybackEvent>(
  (ref) => ref.watch(playbackControllerProvider).events,
);

/// 目前這首照播的是不是試聽片段（播放列標「試聽」）：先給目前的值，之後每次
/// 改變。
final playbackPreviewProvider = StreamProvider<bool>((ref) async* {
  final controller = ref.watch(playbackControllerProvider);
  yield controller.previewing;
  yield* controller.previewChanges;
});

/// 目前這首的位置、時長與緩衝（高頻，ADR 0018 §決定 2）。後端第一次回報前
/// 還沒有值。
final playbackProgressProvider = StreamProvider<PlaybackProgress>(
  (ref) => ref.watch(playbackControllerProvider).progress,
);
