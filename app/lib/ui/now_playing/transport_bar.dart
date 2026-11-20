import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/router.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/now_playing/now_playing.dart';
import 'package:fmp/ui/now_playing/play_modes.dart';
import 'package:fmp/ui/now_playing/spine.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 桌面與中寬度的播放膠囊（`.transport`，`docs/design/DESIGN.md`〈桌面〉
/// 〈中寬度〉）：玻璃膠囊本身是書脊式進度條；三欄，左邊封面、標題、音源符號
/// ＋作者（點了打開播放頁），中間隨機、上一首、播放、下一首、循環，右邊
/// 時間。膠囊窄於 640 時收掉時間。歌詞、佇列、音量還沒有，不出現
/// 入口。
///
/// 滑鼠版（[touch] 是假）可以改進度：點或拖膠囊的空白處、拖折線，放開才
/// 跳過去。滑鼠移到空白處時游標變成左右箭頭、折線加粗、滑鼠的位置畫一條淡
/// 刻線，膠囊上方浮出那個位置的時間（2026-11-19 擁有者選的樣子）。平板照
/// 手機的迷你播放器只顯示。
class TransportBar extends ConsumerStatefulWidget {
  const TransportBar({super.key, required this.state, required this.touch});

  /// 平板版（`.transport.touch`）的高度；滑鼠版 64。
  static double heightOf({required bool touch}) => touch ? 68 : 64;

  final PlaybackState state;

  /// 平板：高 68、封面 48、播放 50，手機字級。
  final bool touch;

  @override
  ConsumerState<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends ConsumerState<TransportBar> {
  /// 滑鼠在空白處的位置（0–1）；不在是 null。
  double? _hover;

  /// 拖動中的位置（0–1）；沒在拖是 null。
  double? _drag;

  Duration? get _duration {
    final duration = widget.state.effectiveDuration;
    return duration != null && duration > Duration.zero ? duration : null;
  }

  double _fraction(Offset local, double width) => seekFraction(local.dx, width);

  @override
  void didUpdateWidget(TransportBar old) {
    super.didUpdateWidget(old);
    // 換了一首：拖到一半的不算數（手勢跟著拆掉，不會再收到放開）。
    if (old.state.track.ref != widget.state.track.ref) {
      _drag = null;
      _hover = null;
    }
  }

  void _seek(double fraction) {
    final duration = _duration;
    if (duration == null) return;
    ref.read(playbackProvider.notifier).seek(durationAt(fraction, duration));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final text = context.fmpText;
    final state = widget.state;
    final touch = widget.touch;
    final track = state.track;
    final height = TransportBar.heightOf(touch: touch);
    final seekable = !touch && _duration != null;
    final title = text.body.copyWith(
      fontSize: touch ? 15 : 13,
      height: touch ? 19 / 15 : null,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: colors.glassInk,
    );
    final sub = text.sub.copyWith(
      fontSize: touch ? 13 : 12,
      height: touch ? 17 / 13 : null,
      letterSpacing: 0,
      color: colors.glassInk2,
    );
    final progress =
        _drag ?? spineProgress(state.position, state.effectiveDuration);
    final hint = _drag ?? _hover;
    final info = Semantics(
      onTapHint: context.t.player.open,
      child: ShellButton(
        key: const Key('transport-open'),
        onTap: () => context.push(playerPath),
        focusRadius: 10,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Cover(url: track.coverUrl, size: touch ? 48 : 44, radius: 10),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NowPlayingTitle(title: track.title, style: title),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SourceMarkIcon(
                        pluginId: track.ref.pluginId,
                        size: touch ? 15 : 14,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          track.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sub,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final glass = Glass(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) {
            final compact = box.maxWidth < 640;
            final width = box.maxWidth;
            return Stack(
              children: [
                Positioned.fill(
                  child: Spine(
                    progress: progress,
                    hovered: hint != null,
                    hint: _hover != null && _drag == null ? _hover : null,
                  ),
                ),
                // 空白處：內容沒接住的點擊、拖動與滑鼠移動落到這一層。
                // 螢幕閱讀器把這一層當成進度滑桿（同播放頁的進度條），不是
                // 一塊沒有名字的點擊區；鍵盤用 ←／→（`PlaybackShortcuts`）。
                if (seekable)
                  Positioned.fill(
                    child: Semantics(
                      container: true,
                      slider: true,
                      label: context.t.player.progress,
                      value: formatDuration(state.position),
                      increasedValue: formatDuration(
                        clampPosition(state.position + seekStep, _duration),
                      ),
                      decreasedValue: formatDuration(
                        clampPosition(state.position - seekStep, _duration),
                      ),
                      onIncrease: () => ref
                          .read(playbackProvider.notifier)
                          .seek(
                            clampPosition(state.position + seekStep, _duration),
                          ),
                      onDecrease: () => ref
                          .read(playbackProvider.notifier)
                          .seek(
                            clampPosition(state.position - seekStep, _duration),
                          ),
                      child: MouseRegion(
                        key: const Key('transport-seek'),
                        cursor: SystemMouseCursors.resizeLeftRight,
                        onHover: (event) => setState(
                          () => _hover = _fraction(event.localPosition, width),
                        ),
                        onExit: (_) => setState(() => _hover = null),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTapUp: (details) =>
                              _seek(_fraction(details.localPosition, width)),
                          onHorizontalDragStart: (details) => setState(
                            () =>
                                _drag = _fraction(details.localPosition, width),
                          ),
                          onHorizontalDragUpdate: (details) => setState(
                            () =>
                                _drag = _fraction(details.localPosition, width),
                          ),
                          onHorizontalDragEnd: (_) {
                            final f = _drag;
                            setState(() => _drag = null);
                            if (f != null) _seek(f);
                          },
                          onHorizontalDragCancel: () =>
                              setState(() => _drag = null),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(left: 10, right: touch ? 12 : 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: info,
                        ),
                      ),
                      const SizedBox(width: 14),
                      PlayModeIconButton.shuffle(touch: touch),
                      const SizedBox(width: 6),
                      SkipButton(
                        forward: false,
                        size: touch ? 44 : 32,
                        iconSize: 20,
                      ),
                      const SizedBox(width: 6),
                      PlayPauseButton(
                        playing: state.playing,
                        size: touch ? 50 : 38,
                        iconSize: 24,
                      ),
                      const SizedBox(width: 6),
                      SkipButton(
                        forward: true,
                        size: touch ? 44 : 32,
                        iconSize: 20,
                      ),
                      const SizedBox(width: 6),
                      PlayModeIconButton.repeat(touch: touch),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: compact
                              ? null
                              : IgnorePointer(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Text(
                                      playbackTime(state),
                                      maxLines: 1,
                                      style: text.cap
                                          .copyWith(
                                            fontSize: touch ? 12 : 11,
                                            letterSpacing: 0,
                                            color: colors.glassInk2,
                                          )
                                          .tabular,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    // 自成一個語意節點，螢幕閱讀器不把它和頁面的字併在一起。
    return Semantics(
      container: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          glass,
          if (hint != null && _duration != null)
            Positioned.fill(
              child: IgnorePointer(
                child: _TimeBubble(
                  at: hint,
                  time: formatDuration(durationAt(hint, _duration!)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 膠囊上方 6 的小玻璃泡泡，寫滑鼠位置（或拖到的位置）的時間；水平置中在
/// 那個位置，不超出膠囊兩端。
class _TimeBubble extends StatelessWidget {
  const _TimeBubble({required this.at, required this.time});

  final double at;
  final String time;

  static const _height = 26.0;
  static const _width = 56.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return LayoutBuilder(
      builder: (context, box) {
        final left = (box.maxWidth * at - _width / 2).clamp(
          0.0,
          box.maxWidth - _width,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              key: const Key('transport-seek-time'),
              left: left,
              top: -6 - _height,
              width: _width,
              height: _height,
              child: Glass(
                child: Center(
                  child: Text(
                    time,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: colors.glassInk,
                    ).tabular,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
