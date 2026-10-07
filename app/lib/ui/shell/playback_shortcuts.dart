import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/ui/shell/shell_shortcuts.dart';

// App 內的播放快捷鍵（ADR 0024 §決定 8、design §9.5）：固定、不可自訂。
//
// 抽成一個 widget，外殼與播放頁各包一層：播放頁是另一個 route，
// 不在外殼的 `Shortcuts` 之下，放在 Navigator 之上又會搶走對話框裡的空白鍵。
// 對話框開著時焦點在對話框的 route 裡，這些鍵不作用。
//
// 這幾個鍵同時是文字編輯鍵（空白鍵、Ctrl／Shift 加方向鍵，Ctrl+S、Ctrl+R 之類的
// 組合鍵也不該在打字時觸發），所以 action 都用 [TextInputAwareAction]：焦點在輸入
// 框時停用，`Shortcuts` 不處理，按鍵往上交給文字編輯。

/// 播放與暫停。
final class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

final class PreviousTrackIntent extends Intent {
  const PreviousTrackIntent();
}

final class NextTrackIntent extends Intent {
  const NextTrackIntent();
}

/// 從目前位置前後移動 [offset]。
final class SeekByIntent extends Intent {
  const SeekByIntent(this.offset);

  final Duration offset;
}

/// 音量加減 [percent] 個百分點（夾在 0–100%）；靜音中就是取消靜音再調整。
final class VolumeByIntent extends Intent {
  const VolumeByIntent(this.percent);

  final int percent;
}

final class ToggleShuffleIntent extends Intent {
  const ToggleShuffleIntent();
}

/// 循環模式輪轉（關閉 → 全部 → 單曲）。
final class CycleLoopIntent extends Intent {
  const CycleLoopIntent();
}

/// Ctrl+L：播放頁的右欄切到歌詞；播放頁沒開（佇列不空）時先開播放頁。這個 intent 的
/// action 不在 [PlaybackShortcuts]：外殼（開播放頁）與播放頁（切分頁）各接各的。
final class ShowLyricsIntent extends Intent {
  const ShowLyricsIntent();
}

/// Ctrl+Q：同 [ShowLyricsIntent]，切到佇列。
final class ShowQueueIntent extends Intent {
  const ShowQueueIntent();
}

/// Shift+←／→ 一次移動幾秒。
const seekStepSeconds = 5;

/// Ctrl+↑／↓ 一次調整幾個百分點。
const volumeStepPercent = 5;

/// 播放快捷鍵表。按鍵也寫在提示文字裡（翻譯檔的 `*Tooltip`），改這裡要一起改。
const playbackShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.space): PlayPauseIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
      PreviousTrackIntent(),
  SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
      NextTrackIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): SeekByIntent(
    Duration(seconds: -seekStepSeconds),
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): SeekByIntent(
    Duration(seconds: seekStepSeconds),
  ),
  SingleActivator(LogicalKeyboardKey.arrowUp, control: true): VolumeByIntent(
    volumeStepPercent,
  ),
  SingleActivator(LogicalKeyboardKey.arrowDown, control: true): VolumeByIntent(
    -volumeStepPercent,
  ),
  SingleActivator(LogicalKeyboardKey.keyS, control: true):
      ToggleShuffleIntent(),
  SingleActivator(LogicalKeyboardKey.keyR, control: true): CycleLoopIntent(),
  SingleActivator(LogicalKeyboardKey.keyL, control: true): ShowLyricsIntent(),
  SingleActivator(LogicalKeyboardKey.keyQ, control: true): ShowQueueIntent(),
};

/// 在 [child] 之上加播放快捷鍵（[playbackShortcuts]），動作都呼叫
/// `PlaybackController`。
class PlaybackShortcuts extends ConsumerWidget {
  const PlaybackShortcuts({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 控制器在按鍵時才讀：建構時讀會在沒有播放後端的環境（測試）直接拋錯。
    PlaybackController controller() => ref.read(playbackControllerProvider);
    return Shortcuts(
      shortcuts: playbackShortcuts,
      child: Actions(
        actions: {
          PlayPauseIntent: TextInputAwareAction<PlayPauseIntent>(
            onInvoke: (_) => _playPause(ref),
          ),
          PreviousTrackIntent: TextInputAwareAction<PreviousTrackIntent>(
            onInvoke: (_) => unawaited(controller().previous()),
          ),
          NextTrackIntent: TextInputAwareAction<NextTrackIntent>(
            onInvoke: (_) => unawaited(controller().next()),
          ),
          SeekByIntent: TextInputAwareAction<SeekByIntent>(
            onInvoke: (intent) => _seekBy(ref, intent.offset),
          ),
          VolumeByIntent: TextInputAwareAction<VolumeByIntent>(
            onInvoke: (intent) => _volumeBy(ref, intent.percent),
          ),
          ToggleShuffleIntent: TextInputAwareAction<ToggleShuffleIntent>(
            onInvoke: (_) =>
                controller().setShuffle(!controller().queue.shuffleEnabled),
          ),
          CycleLoopIntent: TextInputAwareAction<CycleLoopIntent>(
            onInvoke: (_) => controller().cycleLoopMode(),
          ),
        },
        child: child,
      ),
    );
  }

  static void _playPause(WidgetRef ref) {
    final controller = ref.read(playbackControllerProvider);
    switch (controller.state) {
      case Playing() || Loading() || Buffering() || Retrying():
        unawaited(controller.pause());
      case Idle() || Paused() || Failed():
        unawaited(controller.play());
    }
  }

  static void _seekBy(WidgetRef ref, Duration offset) {
    final controller = ref.read(playbackControllerProvider);
    final Duration from;
    final Duration? duration;
    if (controller.state is Idle) {
      // 沒有來源：進度 stream 留著上一個來源的回報。啟動恢復後還沒播時移動的是
      // 恢復的起點（同播放列的進度條）；其他按播放都從頭開始，不動。
      final restored = controller.restoredPosition;
      if (restored == null) return;
      from = restored;
      duration = controller.queue.current?.duration;
    } else {
      final progress = ref.read(playbackProgressProvider).value;
      if (progress == null) return;
      from = progress.position;
      duration = progress.duration;
    }
    var target = from + offset;
    if (target.isNegative) target = Duration.zero;
    if (duration != null && target > duration) target = duration;
    unawaited(controller.seek(target));
  }

  /// 音量以整數百分點算，免得連按累積浮點誤差；靜音中 `setVolume` 就取消靜音。
  static void _volumeBy(WidgetRef ref, int percent) {
    final controller = ref.read(playbackControllerProvider);
    final next = ((controller.volume * 100).round() + percent).clamp(0, 100);
    unawaited(controller.setVolume(next / 100));
  }
}
