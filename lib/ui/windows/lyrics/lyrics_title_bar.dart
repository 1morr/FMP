import 'package:flutter/material.dart';

import '../../../services/lyrics/lyrics_window_style.dart';

/// 歌詞視窗標題列（純展示 leaf，C1a/C1e）。
///
/// 從 `lyrics_window.dart` 的 `_buildTitleBar` 抽出。所有副作用（window_manager
/// 拖曳/置頂、setState、channel 命令）皆由 caller 注入為 callback，本 leaf
/// 不直接依賴 `window_manager` 或 desktop_multi_window，故可在 flutter_test
/// 中單獨 pump 並驗證各按鈕的回呼。
class LyricsTitleBar extends StatelessWidget {
  const LyricsTitleBar({
    super.key,
    required this.title,
    required this.artist,
    required this.transparentMode,
    required this.isPlaying,
    required this.displayModeIcon,
    required this.displayModeTooltip,
    required this.singleLineMode,
    required this.alwaysOnTop,
    required this.isSynced,
    required this.hasLines,
    required this.showOffsetControls,
    required this.labels,
    required this.onDragStart,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onCycleDisplayMode,
    required this.onShowStyleDialog,
    required this.onToggleSingleLine,
    required this.onToggleTransparent,
    required this.onToggleAlwaysOnTop,
    required this.onToggleOffsetControls,
    required this.onClose,
  });

  final String? title;
  final String? artist;
  final bool transparentMode;
  final bool isPlaying;
  final IconData displayModeIcon;
  final String displayModeTooltip;
  final bool singleLineMode;
  final bool alwaysOnTop;
  final bool isSynced;
  final bool hasLines;
  final bool showOffsetControls;
  final LyricsTitleBarLabels labels;

  // ── 副作用 callback（由 caller 注入）──
  final GestureDragStartCallback onDragStart;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onCycleDisplayMode;
  final VoidCallback onShowStyleDialog;
  final VoidCallback onToggleSingleLine;
  final VoidCallback onToggleTransparent;
  final VoidCallback onToggleAlwaysOnTop;
  final VoidCallback onToggleOffsetControls;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = transparentMode;
    final colorScheme = Theme.of(context).colorScheme;

    final iconColor = t ? Colors.white70 : colorScheme.onSurfaceVariant;
    final titleColor = t ? Colors.white : colorScheme.onSurface;
    final subtitleColor = t ? Colors.white70 : colorScheme.onSurfaceVariant;
    final activeColor = t ? Colors.amber : colorScheme.primary;
    final bgColor = t ? Colors.black.withValues(alpha: 0.85) : null;
    final borderColor =
        t ? Colors.white12 : colorScheme.outlineVariant.withValues(alpha: 0.3);

    return GestureDetector(
      onPanStart: onDragStart,
      child: Container(
        height: LyricsWindowLayout.titleBarHeight,
        padding: const EdgeInsets.only(left: 16, right: 4, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Row(
          children: [
            Icon(Icons.lyrics_outlined, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title ?? 'Lyrics',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (artist != null)
                    Text(
                      artist!,
                      style: TextStyle(fontSize: 11, color: subtitleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            _button(Icons.skip_previous_rounded, 18, onPrevious,
                color: iconColor, semanticsLabel: labels.previous),
            _button(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              20,
              onPlayPause,
              color: titleColor,
              semanticsLabel: isPlaying ? labels.pause : labels.play,
            ),
            _button(Icons.skip_next_rounded, 18, onNext,
                color: iconColor, semanticsLabel: labels.next),
            const SizedBox(width: 4),
            _button(displayModeIcon, 16, onCycleDisplayMode,
                color: iconColor,
                tooltip: displayModeTooltip,
                semanticsLabel: displayModeTooltip),
            _button(Icons.palette_outlined, 16, onShowStyleDialog,
                color: iconColor,
                tooltip: labels.styleSettings,
                semanticsLabel: labels.styleSettings),
            _button(
              singleLineMode ? Icons.view_headline : Icons.short_text,
              16,
              onToggleSingleLine,
              color: singleLineMode ? activeColor : iconColor,
              tooltip: singleLineMode ? labels.fullLyrics : labels.singleLine,
              semanticsLabel:
                  singleLineMode ? labels.fullLyrics : labels.singleLine,
            ),
            _button(
              t ? Icons.opacity : Icons.format_color_fill,
              16,
              onToggleTransparent,
              color: t ? activeColor : iconColor,
              tooltip: t ? labels.normalMode : labels.transparentMode,
              semanticsLabel: t ? labels.normalMode : labels.transparentMode,
            ),
            _button(
              alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
              16,
              onToggleAlwaysOnTop,
              color: alwaysOnTop ? activeColor : iconColor,
              tooltip: alwaysOnTop ? labels.unpin : labels.pin,
              semanticsLabel: alwaysOnTop ? labels.unpin : labels.pin,
            ),
            if (isSynced && hasLines)
              _button(
                Icons.timer_outlined,
                16,
                onToggleOffsetControls,
                color: showOffsetControls ? activeColor : iconColor,
                tooltip: labels.offsetAdjust,
                semanticsLabel: labels.offsetAdjust,
              ),
            _button(Icons.close, 16, onClose,
                color: iconColor,
                tooltip: labels.close,
                semanticsLabel: labels.close),
          ],
        ),
      ),
    );
  }

  Widget _button(
    IconData icon,
    double size,
    VoidCallback onPressed, {
    Color? color,
    String? tooltip,
    required String semanticsLabel,
  }) {
    final button = IconButton(
      icon: ExcludeSemantics(child: Icon(icon, size: size, color: color)),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );

    return Semantics(
      button: true,
      label: tooltip ?? semanticsLabel,
      child: tooltip == null
          ? button
          : Tooltip(
              message: tooltip,
              excludeFromSemantics: true,
              child: button,
            ),
    );
  }
}

/// 標題列在地化文案（打包傳遞，避免 leaf 參數過多）。
class LyricsTitleBarLabels {
  const LyricsTitleBarLabels({
    required this.previous,
    required this.play,
    required this.pause,
    required this.next,
    required this.styleSettings,
    required this.fullLyrics,
    required this.singleLine,
    required this.normalMode,
    required this.transparentMode,
    required this.unpin,
    required this.pin,
    required this.offsetAdjust,
    required this.close,
  });

  final String previous;
  final String play;
  final String pause;
  final String next;
  final String styleSettings;
  final String fullLyrics;
  final String singleLine;
  final String normalMode;
  final String transparentMode;
  final String unpin;
  final String pin;
  final String offsetAdjust;
  final String close;
}
