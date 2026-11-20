import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 鍵盤（←／→）與螢幕閱讀器調整進度時一次跳多少。
const seekStep = Duration(seconds: 5);

/// 進度條上的 [dx] 在 [width] 寬的條上是第幾成，夾在 0–1。
double seekFraction(double dx, double width) =>
    width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

/// [duration] 的 [fraction]（0–1）成。
Duration durationAt(double fraction, Duration duration) =>
    Duration(microseconds: (duration.inMicroseconds * fraction).round());

/// [position] 夾在 0 到 [duration] 之間；不知道長度時只夾下限。
Duration clampPosition(Duration position, Duration? duration) {
  if (position < Duration.zero) return Duration.zero;
  if (duration != null && position > duration) return duration;
  return position;
}

/// 「1:36 / 4:12」：位置與長度；長度不知道時只寫位置。
String playbackTime(PlaybackState state) {
  final duration = state.effectiveDuration;
  final position = formatDuration(state.position);
  return duration == null
      ? position
      : '$position / ${formatDuration(duration)}';
}

/// 玻璃上的播放與暫停鈕（`.ibtn`）：hover 時 `--glass-press` 的圓底。
class PlayPauseButton extends ConsumerWidget {
  const PlayPauseButton({
    super.key,
    required this.playing,
    required this.size,
    required this.iconSize,
  });

  final bool playing;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final label = playing ? t.nowPlaying.pause : t.nowPlaying.play;
    final colors = context.fmpColors;
    return ShellButton(
      onTap: () => ref.read(playbackProvider.notifier).playPause(),
      tooltip: label,
      label: label,
      focusRadius: 999,
      builder: (context, hovered) => AnimatedContainer(
        duration: FmpMotion.fast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: hovered ? colors.glassPress : null,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: FmpIcon(
          playing ? FmpIcons.pause : FmpIcons.play,
          size: iconSize,
          color: colors.glassInk,
        ),
      ),
    );
  }
}

/// 玻璃上的上一首、下一首鈕（`.ibtn`）：沒有上一首、下一首時停用，40% 透明
/// （`docs/design/DESIGN.md`〈選單〉的停用項）。
class SkipButton extends ConsumerWidget {
  const SkipButton({
    super.key,
    required this.forward,
    required this.size,
    required this.iconSize,
  });

  /// 真是下一首，假是上一首。
  final bool forward;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final colors = context.fmpColors;
    final skip = ref.watch(skipAvailableProvider);
    final enabled = forward ? skip.next : skip.previous;
    final label = forward ? t.nowPlaying.next : t.nowPlaying.previous;
    final controller = ref.read(queueProvider.notifier);
    return ShellButton(
      onTap: !enabled
          ? null
          : forward
          ? controller.next
          : controller.previous,
      tooltip: label,
      label: label,
      focusRadius: 999,
      builder: (context, hovered) => Opacity(
        opacity: enabled ? 1 : 0.4,
        child: AnimatedContainer(
          duration: FmpMotion.fast,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: hovered && enabled ? colors.glassPress : null,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: FmpIcon(
            forward ? FmpIcons.next : FmpIcons.prev,
            size: iconSize,
            color: colors.glassInk,
          ),
        ),
      ),
    );
  }
}

/// 迷你播放器與播放膠囊在臨時播放時標題旁的「臨時」小標（`.qu-tag`）：
/// 17 高、圓角 5，強調色底、11 號粗體。
class TemporaryTag extends StatelessWidget {
  const TemporaryTag({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Container(
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accentFill,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        context.t.nowPlaying.temporaryTag,
        maxLines: 1,
        style: TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: colors.accentInk,
        ),
      ),
    );
  }
}

/// 標題與它後面的「臨時」小標（`.mi b`：flex、間距 6）：標題過長時截斷，
/// 小標不截。
class NowPlayingTitle extends ConsumerWidget {
  const NowPlayingTitle({super.key, required this.title, required this.style});

  final String title;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final temporary = ref.watch(
      temporaryPlayProvider.select((value) => value != null),
    );
    final text = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (!temporary) return text;
    return Row(
      children: [
        Flexible(child: text),
        const SizedBox(width: 6),
        const TemporaryTag(),
      ],
    );
  }
}
