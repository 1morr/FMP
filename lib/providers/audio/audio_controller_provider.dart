import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/services/toast_service.dart';
import '../../data/repositories/play_history_repository.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/models/source_ids.dart';
import '../../data/sources/source_provider.dart';
import '../../services/audio/audio_provider.dart';
import '../../services/audio/audio_runtime_platform.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/audio_stream_manager.dart';
import '../../services/audio/just_audio_service.dart';
import '../../services/audio/media_kit_audio_service.dart';
import '../../services/audio/now_playing_publisher.dart';
import '../../services/audio/queue_manager.dart';
import '../../services/audio/queue_persistence_manager.dart';
import '../../services/audio/queue_state.dart';
import '../../services/network/connectivity_service.dart';
import '../account/source_auth_context_provider.dart';
import '../database/database_provider.dart';
import '../database/repository_providers.dart';
import '../download/file_exists_cache.dart';
import '../library/library_invalidation_coordinator.dart';
import '../lyrics/lyrics_provider.dart';
import 'stream_resolution_provider.dart';

/// AudioService Provider（平台条件选择）
/// Android/iOS: JustAudioService (ExoPlayer, 更轻量)
/// Windows/Linux: MediaKitAudioService (libmpv, 支持设备切换)
final audioServiceProvider = Provider<FmpAudioService>((ref) {
  final runtimePlatform = ref.watch(audioRuntimePlatformProvider);
  if (runtimePlatform == AudioRuntimePlatform.mobile) {
    return JustAudioService();
  }
  return MediaKitAudioService();
});

final queuePersistenceManagerProvider =
    Provider<QueuePersistenceManager>((ref) {
  final db = ref.watch(databaseProvider).requireValue;

  return QueuePersistenceManager(
    queueRepository: QueueRepository(db),
    trackRepository: TrackRepository(db),
    settingsRepository: SettingsRepository(db),
  );
});

final audioStreamManagerProvider = Provider<AudioStreamManager>((ref) {
  final manager = AudioStreamManager(
    streamResolutionService: ref.watch(streamResolutionServiceProvider),
    sourceAuthContext: ref.watch(sourceAuthContextProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// QueueManager Provider
final queueManagerProvider = Provider<QueueManager>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final queuePersistenceManager = ref.watch(queuePersistenceManagerProvider);

  return QueueManager(
    queueRepository: QueueRepository(db),
    trackRepository: TrackRepository(db),
    queuePersistenceManager: queuePersistenceManager,
  );
});

/// AudioController Provider
final audioControllerProvider =
    StateNotifierProvider<AudioController, PlayerState>((ref) {
  final audioService = ref.watch(audioServiceProvider);
  final queueManager = ref.watch(queueManagerProvider);
  final toastService = ref.watch(toastServiceProvider);

  // 获取播放历史仓库（可能为 null，如果数据库未初始化）
  PlayHistoryRepository? playHistoryRepository;
  try {
    playHistoryRepository = ref.watch(playHistoryRepositoryProvider);
  } catch (_) {
    // 数据库未初始化时忽略
  }

  final controller = AudioController(
    audioService: audioService,
    queueManager: queueManager,
    audioStreamManager: ref.watch(audioStreamManagerProvider),
    toastService: toastService,
    nowPlayingPublisher: ref.watch(nowPlayingPublisherProvider),
    playHistoryRepository: playHistoryRepository,
    // Lyrics settings must not rebuild the playback controller. The latest
    // values are read from SettingsRepository when auto-match actually runs.
    lyricsAutoMatchService: ref.read(lyricsAutoMatchServiceProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    queuePersistenceManager: ref.watch(queuePersistenceManagerProvider),
    mixTracksFetcher: ref
        .watch(sourceManagerProvider)
        .dynamicPlaylistSource(SourceIds.youtube)
        ?.fetchMixTracks,
  );

  // 设置网络恢复监听（用于断网重连自动恢复播放）
  final connectivityNotifier = ref.watch(connectivityProvider.notifier);
  controller
      .setupNetworkRecoveryListener(connectivityNotifier.onNetworkRecovered);

  // 设置歌词自动匹配状态回调
  controller.onLyricsAutoMatchStateChanged = (isMatching) {
    ref.read(lyricsAutoMatchingProvider.notifier).state = isMatching;
  };

  controller.onQueueStateChanged = (queueState) {
    ref.read(queueStateProvider.notifier).state = queueState;
  };

  final downloadPathSubscription =
      ref.watch(audioStreamManagerProvider).downloadPathsChangedStream.listen(
    (event) {
      final playlistIds = <int>{};
      for (final info in event.track.playlistInfo) {
        if (info.playlistId > 0) {
          playlistIds.add(info.playlistId);
        }
      }
      ref.read(libraryInvalidationCoordinatorProvider).downloadStateChanged(
            savePaths: event.removedPaths,
            affectedPlaylistIds: playlistIds,
            includeDownloadedCategories: event.removedPaths.isNotEmpty,
            fileExistsChanged: false,
          );
      for (final path in event.removedPaths) {
        ref.read(fileExistsCacheProvider.notifier).remove(path);
      }
    },
  );
  ref.onDispose(downloadPathSubscription.cancel);

  // 启动初始化（异步，但不阻塞）
  // _ensureInitialized 会在每个操作前确保初始化完成
  Future.microtask(() => controller.initialize());

  return controller;
});
