import '../../../data/models/play_queue.dart';
import '../../../data/repositories/queue_repository.dart';
import '../../../data/repositories/settings_repository.dart';

typedef QueueAccessor = PlayQueue? Function();
typedef CurrentIndexAccessor = int Function();
typedef CurrentPositionAccessor = Duration Function();

class QueuePersistenceHelpers {
  QueuePersistenceHelpers({
    required QueueRepository queueRepository,
    required SettingsRepository settingsRepository,
    required QueueAccessor getCurrentQueue,
    required CurrentIndexAccessor getCurrentIndex,
    required CurrentPositionAccessor getCurrentPosition,
  })  : _queueRepository = queueRepository,
        _settingsRepository = settingsRepository,
        _getCurrentQueue = getCurrentQueue,
        _getCurrentIndex = getCurrentIndex,
        _getCurrentPosition = getCurrentPosition;

  final QueueRepository _queueRepository;
  final SettingsRepository _settingsRepository;
  final QueueAccessor _getCurrentQueue;
  final CurrentIndexAccessor _getCurrentIndex;
  final CurrentPositionAccessor _getCurrentPosition;

  Future<void> savePositionNow() async {
    final currentQueue = _getCurrentQueue();
    if (currentQueue == null) return;

    currentQueue.currentIndex = _getCurrentIndex();
    currentQueue.lastPositionMs = _getCurrentPosition().inMilliseconds;
    await _queueRepository.save(currentQueue);
  }

  Future<void> saveVolume(double volume) async {
    final currentQueue = _getCurrentQueue();
    if (currentQueue == null) return;

    currentQueue.lastVolume = volume.clamp(0.0, 1.0);
    await _queueRepository.save(currentQueue);
  }

  Future<({bool enabled, int restartRewindSeconds, int tempPlayRewindSeconds})>
      getPositionRestoreSettings() async {
    final settings = await _settingsRepository.get();
    return (
      enabled: settings.rememberPlaybackPosition,
      restartRewindSeconds: settings.restartRewindSeconds,
      tempPlayRewindSeconds: settings.tempPlayRewindSeconds,
    );
  }
}
