import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/layout_state.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/track_details.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 面板在這個等級以上才會出現（ADR 0024 §決定 3）：整個視窗 >= 840。
bool hasNowPlayingPanel(WindowClass windowClass) => switch (windowClass) {
  WindowClass.expanded || WindowClass.large || WindowClass.extraLarge => true,
  WindowClass.compact || WindowClass.medium => false,
};

/// 面板畫面上的寬度（design §9.4）：[stored]（記住的，沒記過用該等級的預設）夾在
/// 下限與視窗寬 x 0.4 之間；上限低於下限時以下限為準，高於資料庫收得下的
/// [AppLayout.panelMaxWidth] 時以它為準。只夾畫面上的值，不改寫記憶。
double panelWidthFor({
  required double? stored,
  required WindowClass windowClass,
  required double windowWidth,
}) {
  final fallback = windowClass == WindowClass.extraLarge
      ? AppLayout.panelDefaultWidthExtraLarge
      : AppLayout.panelDefaultWidth;
  final max = math.max(
    AppLayout.panelMinWidth,
    math.min(windowWidth * AppLayout.panelMaxFraction, AppLayout.panelMaxWidth),
  );
  return (stored ?? fallback).clamp(AppLayout.panelMinWidth, max);
}

/// 外殼內容區右側的把手加面板；收起時什麼都不佔。把手與面板在「內容」焦點區之內
/// （外殼把它放在那個 `FocusScope` 裡）。
///
/// 拖曳中只改畫面上的寬度（`_override`），放開才寫入 `layout_state`；鍵盤每按一次寫
/// 一次。寫入經資料庫的 stream 回來之前，畫面維持使用者設的值，不跳回舊的。
class NowPlayingPanelSide extends ConsumerStatefulWidget {
  const NowPlayingPanelSide({super.key});

  @override
  ConsumerState<NowPlayingPanelSide> createState() =>
      _NowPlayingPanelSideState();
}

class _NowPlayingPanelSideState extends ConsumerState<NowPlayingPanelSide> {
  double? _override;
  double _dragStart = 0;
  double _dragTotal = 0;

  double _widthOf(BuildContext context, double? stored) => panelWidthFor(
    stored: stored,
    windowClass: WindowClass.of(context),
    windowWidth: MediaQuery.sizeOf(context).width,
  );

  double _current(BuildContext context) =>
      _widthOf(context, _override ?? ref.read(panelStoredWidthProvider));

  void _set(BuildContext context, double width) =>
      setState(() => _override = _widthOf(context, width));

  void _step(BuildContext context, double delta) {
    _set(context, _current(context) + delta);
    _save();
  }

  /// 寫入畫面上的寬度。寫完而儲存的值已經等於它（寬度沒變，不會有新的 stream 值），或寫失敗
  /// 時，畫面改回以儲存的為準；其餘等 stream 追上（見 [build] 的 listen）。
  void _save() {
    final saving = _override;
    unawaited(
      savePanel(ref, width: saving).then((saved) {
        if (!mounted || _override != saving) return;
        if (!saved || ref.read(panelStoredWidthProvider) == saving) {
          setState(() => _override = null);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 儲存的值追上使用者設的值之後，改回以儲存的為準。
    ref.listen(panelStoredWidthProvider, (_, stored) {
      if (stored == _override) setState(() => _override = null);
    });
    if (!ref.watch(panelExpandedProvider)) return const SizedBox.shrink();
    final width = _widthOf(
      context,
      _override ?? ref.watch(panelStoredWidthProvider),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHandle(
          width: width,
          widenedTo: _widthOf(context, width + AppLayout.panelKeyboardStep),
          narrowedTo: _widthOf(context, width - AppLayout.panelKeyboardStep),
          onDragStart: () {
            _dragStart = _current(context);
            _dragTotal = 0;
          },
          // 面板在右：往左拖（dx 為負）變寬。
          onDragUpdate: (dx) {
            _dragTotal += dx;
            _set(context, _dragStart - _dragTotal);
          },
          onDragEnd: _save,
          onDragCancel: () => setState(() => _override = null),
          onWiden: () => _step(context, AppLayout.panelKeyboardStep),
          onNarrow: () => _step(context, -AppLayout.panelKeyboardStep),
        ),
        SizedBox(width: width, child: const NowPlayingPanel()),
      ],
    );
  }
}

/// 面板本身：標題列（收起鈕）加目前這首的 [TrackDetails]；佇列是空的時是空狀態。
/// 底色是主題的 surface，不用毛玻璃（毛玻璃只在播放頁，ADR 0024 §決定 1）。
class NowPlayingPanel extends ConsumerWidget {
  const NowPlayingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).shell;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final current = ref.watch(
      playbackQueueProvider.select((queue) => queue.value?.current),
    );
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.x4,
              end: spacing.x2,
              top: spacing.x2,
              bottom: spacing.x2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      t.panelTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: t.panelCollapseTooltip,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => rememberPanel(ref, expanded: false),
                ),
              ],
            ),
          ),
          Expanded(
            child: current == null
                ? EmptyState(
                    icon: Icons.music_note_outlined,
                    title: t.panelEmpty,
                  )
                : TrackDetails(track: current),
          ),
        ],
      ),
    );
  }
}

/// 面板左邊的分隔線：滑鼠拖曳（游標是左右調整）、鍵盤 左右鍵調寬；可用 Tab 聚焦。
class _PanelHandle extends ConsumerStatefulWidget {
  const _PanelHandle({
    required this.width,
    required this.widenedTo,
    required this.narrowedTo,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onWiden,
    required this.onNarrow,
  });

  /// 面板目前的寬度（語意的值），以及語意的「增加／減少」一步之後的寬度。
  final double width;
  final double widenedTo;
  final double narrowedTo;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  final VoidCallback onWiden;
  final VoidCallback onNarrow;

  @override
  ConsumerState<_PanelHandle> createState() => _PanelHandleState();
}

class _PanelHandleState extends ConsumerState<_PanelHandle> {
  final _focus = FocusNode(debugLabel: 'Now playing panel handle');
  var _hovering = false;
  var _dragging = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    // 左鍵讓把手往左，面板變寬；右鍵變窄（照畫面方向）。
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onWiden();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onNarrow();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).shell;
    final tokens = AppTokens.of(context);
    final highlighted = _focus.hasFocus || _hovering || _dragging;
    return Tooltip(
      message: t.panelResizeTooltip,
      // 名稱在下面的 Semantics（連同目前寬度），不讓 Tooltip 再報一次。
      excludeFromSemantics: true,
      child: Semantics(
        label: t.panelResizeTooltip,
        value: '${widget.width.round()}',
        increasedValue: '${widget.widenedTo.round()}',
        decreasedValue: '${widget.narrowedTo.round()}',
        onIncrease: widget.onWiden,
        onDecrease: widget.onNarrow,
        child: Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          onFocusChange: (_) => setState(() {}),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // 從按下的位置算起：寬度跟著指標，不吃掉一段拖曳的啟動距離。
              dragStartBehavior: DragStartBehavior.down,
              onHorizontalDragStart: (_) {
                setState(() => _dragging = true);
                widget.onDragStart();
              },
              onHorizontalDragUpdate: (details) =>
                  widget.onDragUpdate(details.delta.dx),
              onHorizontalDragEnd: (_) {
                setState(() => _dragging = false);
                widget.onDragEnd();
              },
              onHorizontalDragCancel: () {
                if (!_dragging) return;
                setState(() => _dragging = false);
                widget.onDragCancel();
              },
              child: SizedBox(
                width: AppLayout.panelHandleWidth,
                child: Center(
                  // Center 給的是鬆的約束，不給高度的話線是 0 高、看不到。
                  child: SizedBox(
                    width: tokens.focusRingWidth,
                    height: double.infinity,
                    child: ColoredBox(
                      color: highlighted
                          ? tokens.focusRingColor
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
