import 'audio_types.dart';

/// 後端說的話，經過「控制器自己正在載入」這條規則修正之後的值。
///
/// 控制器換歌時會先 `FmpAudioService.stop()` 再開新流，而 stop 會讓後端送出
/// `idle`。那個 `idle` 是控制器自己造成的，不是「播放結束了」—— 直接投影出去
/// 的話，換歌的瞬間 UI 與通知列會閃一下「已停止」，然後才回到載入中。
///
/// 這條規則在 `AGENTS.md`（Platform Split 一節）寫了很久，但一直只存在於
/// `_onPlayerStateChanged` 裡的區域變數，沒有任何測試。抽成純函數是為了讓它
/// 可以被單獨釘住 —— 它曾經只套用在 Android 通知列，Windows SMTC 收的是後端
/// 原始值，兩個平台對同一件事說法不同。
class EffectivePlaybackState {
  const EffectivePlaybackState({
    required this.isPlaying,
    required this.isBuffering,
    required this.isLoading,
    required this.processingState,
    required this.position,
  });

  /// [backendPosition] 由呼叫端讀進來 —— 這個類別不持有後端。
  factory EffectivePlaybackState.from({
    required FmpPlayerState backend,
    required bool controllerIsLoading,
    required Duration backendPosition,
  }) {
    final backendIdleDuringLoad =
        controllerIsLoading &&
        backend.processingState == FmpAudioProcessingState.idle;
    final processingState = backendIdleDuringLoad
        ? FmpAudioProcessingState.loading
        : backend.processingState;

    return EffectivePlaybackState(
      isPlaying: backendIdleDuringLoad ? false : backend.playing,
      isBuffering: processingState == FmpAudioProcessingState.buffering,
      // 控制器的載入階段優先：解析串流時後端還沒有任何東西可播，它說 idle 或
      // ready 都不算數。
      isLoading:
          controllerIsLoading ||
          processingState == FmpAudioProcessingState.loading,
      processingState: processingState,
      // 載入中一律報 0：後端的位置這時要嘛還是上一首的，要嘛是垃圾值。
      position: controllerIsLoading ? Duration.zero : backendPosition,
    );
  }

  final bool isPlaying;
  final bool isBuffering;
  final bool isLoading;
  final FmpAudioProcessingState processingState;
  final Duration position;
}
