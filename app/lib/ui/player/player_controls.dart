import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/now_playing/play_modes.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 播放頁裡跟密度走的尺寸：[touch] 是手機與平板（`.pl-prog`、`.pl-ctl`、
/// 30 高的音源膠囊），否則是桌面與窄視窗（`.pl-dprog`、`.pl-dctl`、28 高）。
@immutable
class PlayerDensity {
  const PlayerDensity({required this.touch});

  final bool touch;

  double get barHeight => touch ? 6 : 5;
  double get timeSize => touch ? 12 : 11;
  double get timeGap => touch ? 7 : 6;
  double get controlsHeight => touch ? 76 : 60;
  double get button => touch ? 56 : 46;
  double get bigButton => touch ? 76 : 60;
  double get icon => touch ? 34 : 28;
  double get bigIcon => touch ? 46 : 38;
  double get modeIcon => touch ? 24 : 20;
  double get modeDotBottom => touch ? 8 : 6;
  double get signatureHeight => touch ? 30 : 28;
  double get signatureFont => touch ? 12 : 11.5;
}

/// 進度條（`.pl-prog`／`.pl-dprog`）：可以點或拖到某個位置（seek），拖動時
/// 時間跟著手指、放開才跳過去。下面左邊是位置、右邊是剩下的時間（「-2:33」）。
/// 觸控的圓點一直在（12）；滑鼠移上去或拖動時才出現。長度不知道時不能拖。
class PlayerProgress extends ConsumerStatefulWidget {
  const PlayerProgress({super.key, required this.density});

  final PlayerDensity density;

  /// 這個元件的上緣在畫出來的條上方多遠（點擊區多出來的那截）：照稿放條的
  /// 位置時要往上移這麼多。
  /// 觸控 12（稿上音源膠囊與條只隔 14），點擊區其餘的高都在條下面、蓋住
  /// 時間那一行。
  static double overhangOf(PlayerDensity density) => density.touch ? 12 : 7;

  @override
  ConsumerState<PlayerProgress> createState() => _PlayerProgressState();
}

class _PlayerProgressState extends ConsumerState<PlayerProgress> {
  /// 拖動中的位置（0–1）；沒在拖是 null。
  double? _dragging;
  bool _hovered = false;

  /// 點擊區的高：觸控補到 44（`DESIGN.md`〈無障礙〉），滑鼠 20。
  static double hitHeightOf(PlayerDensity density) => density.touch ? 44 : 20;

  double get _hitHeight => hitHeightOf(widget.density);

  double _fraction(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0, 1);

  void _seek(double fraction, Duration duration) {
    final target = Duration(
      microseconds: (duration.inMicroseconds * fraction).round(),
    );
    ref.read(playbackProvider.notifier).seek(target);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final density = widget.density;
    final state = ref.watch(playbackProvider);
    final duration = state?.effectiveDuration;
    final canSeek = duration != null && duration > Duration.zero;
    final position = state?.position ?? Duration.zero;
    final shown = switch ((_dragging, duration)) {
      (final f?, final d?) => Duration(
        microseconds: (d.inMicroseconds * f).round(),
      ),
      _ => position,
    };
    final fraction = canSeek
        ? (shown.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0)
        : 0.0;
    final knob = density.touch || _hovered || _dragging != null;
    final timeStyle = TextStyle(
      fontSize: density.timeSize,
      height: 16 / 12,
      letterSpacing: 0,
      color: colors.label2,
    ).tabular;
    final bar = LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return MouseRegion(
          cursor: canSeek ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: canSeek
                ? (details) =>
                      _seek(_fraction(details.localPosition, width), duration)
                : null,
            onHorizontalDragStart: canSeek
                ? (details) => setState(
                    () => _dragging = _fraction(details.localPosition, width),
                  )
                : null,
            onHorizontalDragUpdate: canSeek
                ? (details) => setState(
                    () => _dragging = _fraction(details.localPosition, width),
                  )
                : null,
            onHorizontalDragEnd: canSeek
                ? (_) {
                    final f = _dragging;
                    setState(() => _dragging = null);
                    if (f != null) _seek(f, duration);
                  }
                : null,
            onHorizontalDragCancel: () => setState(() => _dragging = null),
            child: SizedBox(
              height: _hitHeight,
              child: CustomPaint(
                painter: _BarPainter(
                  top: PlayerProgress.overhangOf(density),
                  fraction: fraction,
                  height: density.barHeight,
                  track: colors.fill2,
                  played: colors.label,
                  knob: knob && canSeek,
                ),
              ),
            ),
          ),
        );
      },
    );
    return Semantics(
      key: const Key('player-progress'),
      slider: true,
      label: t.player.progress,
      value: formatDuration(shown),
      increasedValue: canSeek
          ? formatDuration(_clamp(shown + _step, duration))
          : null,
      decreasedValue: canSeek
          ? formatDuration(_clamp(shown - _step, duration))
          : null,
      onIncrease: canSeek
          ? () => ref
                .read(playbackProvider.notifier)
                .seek(_clamp(position + _step, duration))
          : null,
      onDecrease: canSeek
          ? () => ref
                .read(playbackProvider.notifier)
                .seek(_clamp(position - _step, duration))
          : null,
      // 點擊區比畫出來的條高：上面多出 [PlayerProgress.overhangOf]，其餘在
      // 下面，時間疊在下面那截上。
      child: SizedBox(
        height: math.max(
          _hitHeight,
          PlayerProgress.overhangOf(density) +
              density.barHeight +
              density.timeGap +
              16,
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _hitHeight,
              child: bar,
            ),
            Positioned(
              top:
                  PlayerProgress.overhangOf(density) +
                  density.barHeight +
                  density.timeGap,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Text(formatDuration(shown), style: timeStyle),
                      const Spacer(),
                      if (canSeek)
                        Text(
                          '-${formatDuration(duration - shown)}',
                          style: timeStyle,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _step = Duration(seconds: 5);

  static Duration _clamp(Duration value, Duration max) => value < Duration.zero
      ? Duration.zero
      : value > max
      ? max
      : value;
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.top,
    required this.fraction,
    required this.height,
    required this.track,
    required this.played,
    required this.knob,
  });

  /// 條的上緣離點擊區上緣多遠。
  final double top;
  final double fraction;
  final double height;
  final Color track;
  final Color played;
  final bool knob;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(height / 2);
    final whole = Rect.fromLTWH(0, top, size.width, height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(whole, radius),
      Paint()..color = track,
    );
    final x = size.width * fraction;
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(whole, radius))
      ..drawRect(Rect.fromLTWH(0, top, x, height), Paint()..color = played)
      ..restore();
    if (!knob) return;
    final center = Offset(x, top + height / 2);
    canvas
      ..drawCircle(
        center.translate(0, 1),
        6,
        Paint()
          ..color = const Color.fromRGBO(0, 0, 0, .3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      )
      ..drawCircle(center, 6, Paint()..color = played);
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.top != top ||
      old.fraction != fraction ||
      old.height != height ||
      old.track != track ||
      old.played != played ||
      old.knob != knob;
}

/// 控制列（`.pl-ctl`／`.pl-dctl`）：隨機、上一首、播放／暫停、下一首、循環，
/// 兩端對齊。隨機、循環開著時強調色並在下方加一個點；沒有上一首、下一首時
/// 停用（40% 透明）。
class PlayerControls extends ConsumerWidget {
  const PlayerControls({super.key, required this.density});

  final PlayerDensity density;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final colors = context.fmpColors;
    final playing = ref.watch(
      playbackProvider.select((state) => state?.playing ?? false),
    );
    final (shuffled, repeat) = ref.watch(
      queueProvider.select((queue) => (queue.shuffled, queue.repeat)),
    );
    final skip = ref.watch(skipAvailableProvider);
    final queue = ref.read(queueProvider.notifier);
    final d = density;
    return SizedBox(
      height: d.controlsHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ControlButton(
            key: const Key('player-shuffle'),
            icon: FmpIcons.shuffle,
            label: t.playMode.shuffle,
            size: d.button,
            iconSize: d.modeIcon,
            color: shuffled ? colors.accent : colors.label2,
            on: shuffled,
            dotBottom: d.modeDotBottom,
            onTap: queue.toggleShuffle,
          ),
          _ControlButton(
            key: const Key('player-previous'),
            icon: FmpIcons.prev,
            label: t.nowPlaying.previous,
            size: d.button,
            iconSize: d.icon,
            color: colors.label,
            onTap: skip.previous ? queue.previous : null,
          ),
          _ControlButton(
            key: const Key('player-play'),
            icon: playing ? FmpIcons.pause : FmpIcons.play,
            label: playing ? t.nowPlaying.pause : t.nowPlaying.play,
            size: d.bigButton,
            iconSize: d.bigIcon,
            color: colors.label,
            onTap: () => ref.read(playbackProvider.notifier).playPause(),
          ),
          _ControlButton(
            key: const Key('player-next'),
            icon: FmpIcons.next,
            label: t.nowPlaying.next,
            size: d.button,
            iconSize: d.icon,
            color: colors.label,
            onTap: skip.next ? queue.next : null,
          ),
          _ControlButton(
            key: const Key('player-repeat'),
            icon: repeatIcon(repeat),
            label: repeatLabel(t, repeat),
            size: d.button,
            iconSize: d.modeIcon,
            color: repeat != Repeat.off ? colors.accent : colors.label2,
            on: repeat != Repeat.off,
            dotBottom: d.modeDotBottom,
            onTap: queue.cycleRepeat,
          ),
        ],
      ),
    );
  }
}

/// 色場上的圓形圖示鈕（`.pl-ctl .ibtn`）：滑過時 `--fill` 的圓底，鍵盤選得到。
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.size,
    required this.iconSize,
    required this.color,
    required this.onTap,
    this.on,
    this.dotBottom = 8,
  });

  final FmpIcons icon;
  final String label;
  final double size;
  final double iconSize;
  final Color color;
  final VoidCallback? onTap;

  /// 開關鈕（隨機、循環）開著沒有；一般的鈕是 null。
  final bool? on;
  final double dotBottom;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final enabled = onTap != null;
    Widget button = ShellButton(
      onTap: onTap,
      tooltip: label,
      label: label,
      focusRadius: 999,
      builder: (context, hovered) => Opacity(
        opacity: enabled ? 1 : .4,
        child: AnimatedContainer(
          duration: FmpMotion.fast,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: hovered && enabled ? colors.fill : null,
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              FmpIcon(icon, size: iconSize, color: color),
              if (on ?? false)
                Positioned(
                  bottom: dotBottom,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (on != null) button = Semantics(toggled: on, child: button);
    return button;
  }
}

/// 音源膠囊（招牌，`.pl-sig`，`docs/design/DESIGN.md`〈播放頁音源膠囊〉）：清
/// 玻璃，音源符號＋全名。存取等級與音質（M2）、點開曲目資訊的 ›（票 17）還
/// 沒有，不出現（spec〈共同規則〉）。
class SignatureCapsule extends ConsumerWidget {
  const SignatureCapsule({super.key, required this.density});

  final PlayerDensity density;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pluginId = ref.watch(
      playbackProvider.select((state) => state?.track.ref.pluginId),
    );
    if (pluginId == null) return const SizedBox.shrink();
    final name = ref.watch(pluginManifestProvider(pluginId))?.name ?? pluginId;
    return Semantics(
      label: context.t.player.source(name: name),
      container: true,
      excludeSemantics: true,
      child: Glass(
        variant: GlassVariant.clear,
        child: SizedBox(
          height: density.signatureHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 9, right: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SourceMarkIcon(pluginId: pluginId, size: 14),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: density.signatureFont,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: const Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 頂列中間的播放來源（`.pl-ctx`，`DESIGN.md`〈待確認〉11）：「佇列 · 第 6 /
/// 64 首」與下一首；臨時播放時強調色的「臨時播放」與回到佇列第幾首。
class PlayerContext extends ConsumerWidget {
  const PlayerContext({super.key, this.align = TextAlign.center});

  final TextAlign align;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final colors = context.fmpColors;
    final queue = ref.watch(queueProvider);
    final temporary = ref.watch(temporaryPlayProvider);
    final current = queue.currentIndex;
    final String title;
    final String? detail;
    if (temporary != null) {
      title = t.player.context.temporary;
      detail = current == null
          ? t.player.context.stopsAfter
          : t.player.context.returnsTo(number: current + 1);
    } else if (current != null) {
      title = t.player.context.queue(
        number: current + 1,
        total: queue.entries.length,
      );
      detail = switch (queue.upcoming) {
        final next? => t.player.context.next(title: next.track.title),
        null => null,
      };
    } else {
      title = t.player.queue;
      detail = null;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: TextStyle(
            fontSize: 13,
            height: 17 / 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: temporary != null ? colors.accent : colors.label,
          ),
        ),
        if (detail != null)
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(
              fontSize: 12,
              height: 15 / 12,
              letterSpacing: 0,
              color: colors.label2,
            ),
          ),
      ],
    );
  }
}
