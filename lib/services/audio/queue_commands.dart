import '../../core/constants/app_constants.dart';
import '../../core/services/toast_service.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../i18n/strings.g.dart';
import 'queue_manager.dart';

/// 一次佇列變更的結果。
enum QueueMutationStatus {
  /// 佇列真的變了，呼叫端應該重新投影狀態。
  applied,

  /// 被規則擋下（Mix 模式、佇列已滿）。使用者已經看過提示了。
  blocked,

  /// 拋了例外。`error` 是原始例外。
  failed,
}

class QueueMutation {
  const QueueMutation._(this.status, [this.error]);

  const QueueMutation.applied() : this._(QueueMutationStatus.applied);
  const QueueMutation.blocked() : this._(QueueMutationStatus.blocked);
  const QueueMutation.failed(Object error)
    : this._(QueueMutationStatus.failed, error);

  final QueueMutationStatus status;
  final Object? error;

  bool get isApplied => status == QueueMutationStatus.applied;
}

/// 佇列變更命令。
///
/// `AudioController` 的七個佇列方法本來各自重寫同一套樣板：Mix 模式閘門 →
/// 呼叫 `QueueManager` → 把例外轉成 `state.error`。這裡收下前兩件事與例外處理，
/// controller 只剩「轉發 ＋ 依結果投影」。
///
/// 它**刻意不碰 `PlayerState`**，也不知道 detached 模式或臨時播放 —— 那些是播放
/// 工作階段的概念，留在 controller。Mix 模式同理：這裡不去猜，由呼叫端傳進來。
class QueueCommands with Logging {
  QueueCommands({
    required QueueManager queueManager,
    required ToastService toastService,
  }) : _queueManager = queueManager,
       _toastService = toastService;

  final QueueManager _queueManager;
  final ToastService _toastService;

  Future<QueueMutation> add(Track track, {required bool isMixMode}) {
    if (_blockedByMix(isMixMode)) return _blocked();
    logInfo('Adding to queue: ${track.title}');
    return _run('add track to queue', () async {
      if (await _queueManager.add(track)) return const QueueMutation.applied();
      _toastService.showError(
        t.audio.queueFull(count: AppConstants.maxQueueSize),
      );
      return const QueueMutation.blocked();
    });
  }

  Future<QueueMutation> addAll(List<Track> tracks, {required bool isMixMode}) {
    if (_blockedByMix(isMixMode)) return _blocked();
    logInfo('Adding ${tracks.length} tracks to queue');
    return _run('add tracks to queue', () async {
      await _queueManager.addAll(tracks);
      return const QueueMutation.applied();
    });
  }

  Future<QueueMutation> addNext(Track track, {required bool isMixMode}) {
    if (_blockedByMix(isMixMode)) return _blocked();
    logInfo('Adding next: ${track.title}');
    return _run('add track as next', () async {
      await _queueManager.addNext(track);
      return const QueueMutation.applied();
    });
  }

  Future<QueueMutation> removeAt(int index) {
    logDebug('Removing from queue at index: $index');
    return _run('remove from queue at index $index', () async {
      await _queueManager.removeAt(index);
      return const QueueMutation.applied();
    });
  }

  Future<QueueMutation> move(int oldIndex, int newIndex) {
    logDebug('Moving in queue: $oldIndex -> $newIndex');
    return _run('move in queue', () async {
      await _queueManager.move(oldIndex, newIndex);
      return const QueueMutation.applied();
    });
  }

  /// Mix 模式下靜默擋下：UI 應該已經禁用了按鈕，這只是額外保護，
  /// 不需要再彈一次提示。
  Future<QueueMutation> shuffle({required bool isMixMode}) {
    if (isMixMode) return _blocked();
    logInfo('Shuffling queue');
    return _run('shuffle queue', () async {
      await _queueManager.shuffle();
      return const QueueMutation.applied();
    });
  }

  Future<QueueMutation> clear() {
    logInfo('Clearing queue');
    return _run('clear queue', () async {
      await _queueManager.clear();
      return const QueueMutation.applied();
    });
  }

  bool _blockedByMix(bool isMixMode) {
    if (!isMixMode) return false;
    _toastService.showInfo(t.audio.mixPlaylistNoAdd);
    return true;
  }

  Future<QueueMutation> _blocked() async => const QueueMutation.blocked();

  Future<QueueMutation> _run(
    String description,
    Future<QueueMutation> Function() body,
  ) async {
    try {
      return await body();
    } catch (e, stack) {
      logError('Failed to $description', e, stack);
      return QueueMutation.failed(e);
    }
  }
}
