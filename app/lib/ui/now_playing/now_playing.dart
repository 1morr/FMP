import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

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
