import '../../data/models/play_queue.dart';
import '../../data/models/track.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';

class AudioRuntimeSettings {
  const AudioRuntimeSettings({
    required this.rememberPlaybackPosition,
    required this.restartRewindSeconds,
    required this.tempPlayRewindSeconds,
  });

  final bool rememberPlaybackPosition;
  final int restartRewindSeconds;
  final int tempPlayRewindSeconds;

  bool get enabled => rememberPlaybackPosition;
}

class QueueRestoreState {
  const QueueRestoreState({
    required this.queue,
    required this.tracks,
    required this.currentIndex,
    required this.savedPosition,
    required this.savedVolume,
    required this.mixPlaylistId,
    required this.mixSeedVideoId,
    required this.mixTitle,
  });

  final PlayQueue queue;
  final List<Track> tracks;
  final int currentIndex;
  final Duration savedPosition;
  final double savedVolume;
  final String? mixPlaylistId;
  final String? mixSeedVideoId;
  final String? mixTitle;
}

class QueuePersistenceManager {
  QueuePersistenceManager({
    required QueueRepository queueRepository,
    required TrackRepository trackRepository,
    required SettingsRepository settingsRepository,
  })  : _queueRepository = queueRepository,
        _trackRepository = trackRepository,
        _settingsRepository = settingsRepository;

  final QueueRepository _queueRepository;
  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;

  Future<QueueRestoreState> restoreState() async {
    final queue = await _queueRepository.getOrCreate();
    final settings = await _settingsRepository.get();
    final tracks = queue.trackIds.isEmpty
        ? <Track>[]
        : await _trackRepository.getByIds(queue.trackIds);
    final savedPosition = settings.rememberPlaybackPosition
        ? Duration(milliseconds: queue.lastPositionMs)
        : Duration.zero;

    return QueueRestoreState(
      queue: queue,
      tracks: tracks,
      currentIndex: queue.currentIndex,
      savedPosition: savedPosition,
      savedVolume: queue.lastVolume,
      mixPlaylistId: queue.mixPlaylistId,
      mixSeedVideoId: queue.mixSeedVideoId,
      mixTitle: queue.mixTitle,
    );
  }

  Future<void> persistQueue({
    required PlayQueue? queue,
    required List<Track> tracks,
    required int currentIndex,
    required Duration currentPosition,
  }) async {
    if (queue == null) return;

    queue.trackIds = tracks.map((track) => track.id).toList();
    queue.currentIndex = currentIndex;
    queue.lastPositionMs = currentPosition.inMilliseconds;
    await _queueRepository.save(queue);
  }

  Future<void> savePositionNow({
    required PlayQueue? queue,
    required int currentIndex,
    required Duration currentPosition,
  }) async {
    if (queue == null) return;

    queue.currentIndex = currentIndex;
    queue.lastPositionMs = currentPosition.inMilliseconds;
    await _queueRepository.save(queue);
  }

  Future<void> saveVolume({
    required PlayQueue? queue,
    required double volume,
  }) async {
    if (queue == null) return;

    queue.lastVolume = volume.clamp(0.0, 1.0);
    await _queueRepository.save(queue);
  }

  Future<void> setMixMode({
    required PlayQueue? queue,
    required bool enabled,
    String? playlistId,
    String? seedVideoId,
    String? title,
  }) async {
    if (queue == null) return;

    queue.isMixMode = enabled;
    queue.mixPlaylistId = enabled ? playlistId : null;
    queue.mixSeedVideoId = enabled ? seedVideoId : null;
    queue.mixTitle = enabled ? title : null;
    await _queueRepository.save(queue);
  }

  Future<AudioRuntimeSettings> getPositionRestoreSettings() async {
    final settings = await _settingsRepository.get();
    return AudioRuntimeSettings(
      rememberPlaybackPosition: settings.rememberPlaybackPosition,
      restartRewindSeconds: settings.restartRewindSeconds,
      tempPlayRewindSeconds: settings.tempPlayRewindSeconds,
    );
  }
}
