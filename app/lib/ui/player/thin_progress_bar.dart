import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/player/player_controls.dart';
import 'package:fmp/ui/shell/playback_shortcuts.dart' show seekStepSeconds;
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 播放列頂端的進度細線（ADR 0035 §決定 4，P-12）：平時 2dp，[hovering]（滑鼠在播放列上）或
/// 拖曳中變 6dp、出現把手，把手上方浮著「位置 / 時長」。點細線跳轉，水平拖曳 seek（放開才送出）。
///
/// 可點可拖的範圍是頂端 [AppLayout.thinProgressHit]，線畫在最上緣；放在 `Stack` 裡貼著
/// 播放列的上緣（把手與時間會畫到播放列外面，`Stack` 要 `Clip.none`）。語意同原本的
/// `Slider`：名稱「播放進度」、值是位置文字、增減各 10%。
class ThinProgressBar extends ConsumerStatefulWidget {
  const ThinProgressBar({super.key, required this.hovering});

  /// 滑鼠是否在播放列上。
  final bool hovering;

  @override
  ConsumerState<ThinProgressBar> createState() => _ThinProgressBarState();
}

class _ThinProgressBarState extends ConsumerState<ThinProgressBar> {
  /// 拖動中的位置（毫秒）；沒在拖是 `null`。
  double? _dragging;

  final _focus = FocusNode(debugLabel: 'Progress line');
  var _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  double _at(double dx, double width, double max) =>
      width <= 0 ? 0 : (dx / width * max).clamp(0.0, max);

  void _seek(double milliseconds) => unawaited(
    ref
        .read(playbackControllerProvider)
        .seek(Duration(milliseconds: milliseconds.round())),
  );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).player;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = AppTokens.of(context);
    final view = watchProgressView(ref);
    final seekable = view.seekable;
    final max = view.max;
    final position = seekable
        ? (_dragging ?? view.startsAt).clamp(0.0, max)
        : 0.0;
    final fraction = max > 0 ? position / max : 0.0;
    final grown =
        seekable && (widget.hovering || _dragging != null || _focused);
    final lineHeight = grown
        ? AppLayout.thinProgressHoverHeight
        : AppLayout.thinProgressHeight;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppLayout.thinProgressDuration;
    String text(double milliseconds) =>
        formatDuration(Duration(milliseconds: milliseconds.round()));
    final step = max * 0.1;

    // ←／→ 一次 [seekStepSeconds] 秒（同 Shift+←／→）；有修飾鍵的交給全域快捷鍵。
    KeyEventResult onKey(FocusNode node, KeyEvent event) {
      if (event is KeyUpEvent || !seekable) return KeyEventResult.ignored;
      final keyboard = HardwareKeyboard.instance;
      if (keyboard.isControlPressed ||
          keyboard.isShiftPressed ||
          keyboard.isAltPressed ||
          keyboard.isMetaPressed) {
        return KeyEventResult.ignored;
      }
      final delta = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowLeft => -seekStepSeconds * 1000.0,
        LogicalKeyboardKey.arrowRight => seekStepSeconds * 1000.0,
        _ => null,
      };
      if (delta == null) return KeyEventResult.ignored;
      _seek((position + delta).clamp(0.0, max));
      return KeyEventResult.handled;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Semantics(
          label: t.progress,
          slider: true,
          value: text(position),
          increasedValue: text((position + step).clamp(0.0, max)),
          decreasedValue: text((position - step).clamp(0.0, max)),
          onIncrease: seekable
              ? () => _seek((position + step).clamp(0.0, max))
              : null,
          onDecrease: seekable
              ? () => _seek((position - step).clamp(0.0, max))
              : null,
          child: Focus(
            focusNode: _focus,
            onKeyEvent: onKey,
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: GestureDetector(
              // 手勢的語意（點、左右捲動）不要：滑桿的增減已經是輔助技術的操作。
              excludeFromSemantics: true,
              behavior: HitTestBehavior.translucent,
              // 從按下的位置算起：拖曳不吃掉一段啟動距離。
              dragStartBehavior: DragStartBehavior.down,
              onTapUp: seekable
                  ? (details) =>
                        _seek(_at(details.localPosition.dx, width, max))
                  : null,
              onHorizontalDragStart: seekable
                  ? (details) => setState(
                      () =>
                          _dragging = _at(details.localPosition.dx, width, max),
                    )
                  : null,
              onHorizontalDragUpdate: seekable
                  ? (details) => setState(
                      () =>
                          _dragging = _at(details.localPosition.dx, width, max),
                    )
                  : null,
              onHorizontalDragEnd: seekable
                  ? (_) {
                      final target = _dragging;
                      setState(() => _dragging = null);
                      if (target != null) _seek(target);
                    }
                  : null,
              onHorizontalDragCancel: () => setState(() => _dragging = null),
              child: Container(
                height: AppLayout.thinProgressHit,
                width: double.infinity,
                // 焦點框：主題的焦點色（同其他控制項）。
                foregroundDecoration: _focused
                    ? BoxDecoration(
                        border: Border.all(
                          color: tokens.focusRingColor,
                          width: tokens.focusRingWidth,
                        ),
                      )
                    : null,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: duration,
                      height: lineHeight,
                      color: colors.outlineVariant,
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: fraction,
                        child: ColoredBox(color: colors.primary),
                      ),
                    ),
                    if (grown) ...[
                      PositionedDirectional(
                        start:
                            (width * fraction -
                            AppLayout.thinProgressThumb / 2),
                        top:
                            (AppLayout.thinProgressHoverHeight -
                                AppLayout.thinProgressThumb) /
                            2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(
                            dimension: AppLayout.thinProgressThumb,
                          ),
                        ),
                      ),
                      // 時間浮在把手上方（往播放列外畫）；靠近兩端時夾在視窗內。
                      PositionedDirectional(
                        start: (width * fraction - 48).clamp(
                          0.0,
                          (width - 96).clamp(0.0, double.infinity),
                        ),
                        width: 96,
                        bottom: AppLayout.thinProgressHit + tokens.spacing.x1,
                        child: ExcludeSemantics(
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.inverseSurface,
                                borderRadius: BorderRadius.circular(
                                  tokens.radius.small,
                                ),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: tokens.spacing.x2,
                                  vertical: tokens.spacing.x1,
                                ),
                                child: Text(
                                  '${text(position)} / '
                                  '${view.duration == null ? '-:--' : formatDuration(view.duration!)}',
                                  maxLines: 1,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.onInverseSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
