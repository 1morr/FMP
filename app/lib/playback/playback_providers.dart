import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/backends/audio_backends.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/playback/stream_resolver.dart';
import 'package:fmp/plugins/plugin_registry.dart';

/// 平台宣告的播放能力；沒有時（未驗證的平台）讀它會拋 `Unsupported`。那些
/// 平台在 `main()` 就只開「此平台尚未支援」，走不到這裡。
final _playbackSupportProvider = Provider<PlaybackSupport>(
  (ref) =>
      ref.watch(platformCapabilitiesProvider).playback ?? (throw Unsupported()),
);

/// 整個 App 唯一的播放後端（Android 的音訊焦點見 `AudioBackend`）。
final audioBackendProvider = Provider<AudioBackend>((ref) {
  final backend = createAudioBackend(
    ref.watch(_playbackSupportProvider).backend,
    log: ref.watch(logProvider),
  );
  ref.onDispose(() => unawaited(backend.dispose()));
  return backend;
});

/// UI 唯一的播放入口（ADR 0018 §決定 1）。
final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final log = ref.watch(logProvider);
  final controller = PlaybackController(
    session: PlaybackSession(
      backend: ref.watch(audioBackendProvider),
      resolver: StreamResolver(
        plugin: (pluginId) => ref.read(pluginRegistryProvider).value?[pluginId],
        formats: ref.watch(_playbackSupportProvider).formats,
      ),
      log: log,
    ),
    log: log,
  );
  ref.onDispose(() => unawaited(controller.dispose()));
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

/// 目前這首的位置、時長與緩衝（高頻，ADR 0018 §決定 2）。後端第一次回報前
/// 還沒有值。
final playbackProgressProvider = StreamProvider<PlaybackProgress>(
  (ref) => ref.watch(playbackControllerProvider).progress,
);
