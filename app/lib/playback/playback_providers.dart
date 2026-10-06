import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/backends/audio_backends.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_events.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/playback/stream_resolver.dart';
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
  ref.onDispose(() {
    unawaited(controller.dispose());
    unawaited(networkChanges.close());
  });
  return controller;
});

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
