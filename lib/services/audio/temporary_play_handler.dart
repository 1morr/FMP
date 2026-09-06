import '../../core/logger.dart';
import 'audio_playback_types.dart';

class RestorePlaybackPlan {
  const RestorePlaybackPlan({
    required this.savedIndex,
    required this.savedPosition,
    required this.savedWasPlaying,
    required this.rewindSeconds,
  });

  final int savedIndex;
  final Duration savedPosition;
  final bool savedWasPlaying;
  final int rewindSeconds;
}

/// 擁有「臨時播放開始前，佇列停在哪裡」這份快照。
///
/// 從搜尋結果點一首歌會離開佇列播放，播完（或使用者返回）要回到原本那首與原本
/// 的進度。快照本身放在這裡，而不是 `AudioController` —— 那邊過去用三個欄位存，
/// 每一條離開臨時播放的路徑都要記得三個一起清。
///
/// **它不擁有播放模式**：進入臨時播放同時要把 `PlayMode` 翻成 `temporary`，而模式
/// 還被 Mix、detached 與佇列投影讀著，跟這份快照沒有共同的生命週期。所以
/// [enterTemporary] 收 `currentMode` 當參數，模式仍由 `AudioController` 自己翻。
///
/// **它不啟動播放**：[buildRestorePlan] 只算出「要回到哪個 index、哪個位置」，
/// 真正的還原走 `AudioController._restoreQueuePlayback`，理由與 `playAt` 留在
/// 那裡一樣 —— 那是 transport 命令。
class TemporaryPlayHandler with Logging {
  TemporaryPlayHandler();

  int? _savedQueueIndex;
  Duration? _savedPosition;
  bool? _savedWasPlaying;

  /// 佇列投影要用它算出「臨時播放時，接下來會播的是佇列的哪一段」。
  int? get savedQueueIndex => _savedQueueIndex;

  bool get hasSavedState => _savedQueueIndex != null;

  /// 進入臨時播放，記下目前佇列的位置。
  ///
  /// 已經在臨時播放中時**保留最早那份快照** —— 連續點兩首搜尋結果，要回到的是
  /// 原本的佇列位置，不是上一首臨時播放的。
  void enterTemporary({
    required PlayMode currentMode,
    required bool hasQueueTrack,
    required int currentIndex,
    required Duration currentPosition,
    required bool currentWasPlaying,
  }) {
    if (currentMode == PlayMode.temporary) {
      return;
    }
    if (!hasQueueTrack) {
      clear();
      return;
    }
    _savedQueueIndex = currentIndex;
    _savedPosition = currentPosition;
    _savedWasPlaying = currentWasPlaying;
    logDebug(
        'Saved playback state: index: $currentIndex, position: $currentPosition');
  }

  void clear() {
    _savedQueueIndex = null;
    _savedPosition = null;
    _savedWasPlaying = null;
  }

  /// 依自己存的快照算出還原計畫。沒有快照就是 null。
  RestorePlaybackPlan? buildRestorePlan({
    required bool rememberPosition,
    required int rewindSeconds,
  }) {
    final savedIndex = _savedQueueIndex;
    if (savedIndex == null) {
      return null;
    }

    return RestorePlaybackPlan(
      savedIndex: savedIndex,
      savedPosition:
          rememberPosition ? (_savedPosition ?? Duration.zero) : Duration.zero,
      savedWasPlaying: _savedWasPlaying ?? false,
      rewindSeconds: rememberPosition ? rewindSeconds : 0,
    );
  }

  /// 從電台返回佇列用。**刻意不讀自己的狀態** —— 那份快照是 `RadioController`
  /// 存的，不是這裡存的。
  RestorePlaybackPlan? buildQueueRestorePlan({
    required int? savedQueueIndex,
    required Duration savedPosition,
    required bool savedWasPlaying,
  }) {
    if (savedQueueIndex == null) {
      return null;
    }

    return RestorePlaybackPlan(
      savedIndex: savedQueueIndex,
      savedPosition: savedPosition,
      savedWasPlaying: savedWasPlaying,
      rewindSeconds: 0,
    );
  }
}
