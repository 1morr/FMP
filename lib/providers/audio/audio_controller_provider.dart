import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/models/source_ids.dart';
import '../../data/sources/source_provider.dart';
import '../../services/audio/audio_provider.dart';
import '../../services/audio/mix_playlist_types.dart';
import '../../services/audio/audio_runtime_platform.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/audio_stream_manager.dart';
import '../../services/audio/just_audio_service.dart';
import '../../services/audio/media_kit_audio_service.dart';
import '../../services/audio/queue_manager.dart';
import '../../services/audio/queue_persistence_manager.dart';
import '../account/source_auth_context_provider.dart';
import '../../services/lyrics/lyrics_auto_match_service.dart';
import '../database/database_provider.dart';
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

/// Mix 取用的窄能力入口。
///
/// `NotifierProvider` 的工廠不吃參數，所以 `AudioController` 需要的是一個
/// provider 而不是一個建構子參數；測試也覆寫這裡，不必假造整個 `SourceManager`。
final mixTracksFetcherProvider = Provider<MixTracksFetcher?>((ref) {
  return ref
      .watch(sourceManagerProvider)
      .dynamicPlaylistSource(SourceIds.youtube)
      ?.fetchMixTracks;
});

/// 歌詞自動匹配是可選協作者：沒有它播放照樣成立。
///
/// 獨立成一個可為 null 的入口，是為了讓播放測試不必為了它把歌詞與設定那一整
/// 條鏈拉起來 —— 那條鏈會碰 secure storage，在測試環境沒有實作。
final optionalLyricsAutoMatchServiceProvider =
    Provider<LyricsAutoMatchService?>((ref) {
  return ref.watch(lyricsAutoMatchServiceProvider);
});

/// AudioController Provider
///
/// 接線全部在 `AudioController.build()` 裡 —— `Notifier` 拿得到 `ref`，
/// 所以以前擠在這個工廠裡的 74 行不必再存在。
final audioControllerProvider =
    NotifierProvider<AudioController, PlayerState>(AudioController.new);
