import 'package:flutter/material.dart';

import 'lyrics_offset_math.dart';

/// 歌詞偏移量調整列（offset bar，純展示 leaf，C1d）。
///
/// 從 `lyrics_window.dart` 的 `_buildOffsetBar` + `_offsetButton` 抽出。注入
/// 目前 [offsetMs]、[transparentMode]、[offsetLabel] 文案，以及 [onAdjust]
/// （±100/500/1000ms）與 [onReset] 回呼。reset 按鈕在 offsetMs == 0 時自動
/// 停用（與原行為一致）。顯示值透過 [LyricsOffsetMath.format] 格式化。
class LyricsOffsetBar extends StatelessWidget {
  const LyricsOffsetBar({
    super.key,
    required this.offsetMs,
    required this.transparentMode,
    required this.offsetLabel,
    required this.onAdjust,
    required this.onReset,
  });

  final int offsetMs;
  final bool transparentMode;
  final String offsetLabel;
  final void Function(int deltaMs) onAdjust;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final t = transparentMode;
    final colorScheme = Theme.of(context).colorScheme;

    final labelColor = t ? Colors.white70 : colorScheme.onSurfaceVariant;
    final valueColor = t ? Colors.white : colorScheme.onSurface;
    final btnColor = t ? Colors.white : colorScheme.onSurface;
    final bgColor = t
        ? Colors.black.withValues(alpha: 0.85)
        : Theme.of(context).scaffoldBackgroundColor;
    final borderColor =
        t ? Colors.white12 : colorScheme.outlineVariant.withValues(alpha: 0.3);
    final chipBg = t
        ? Colors.white.withValues(alpha: 0.15)
        : colorScheme.surfaceContainerHighest;

    final canReset = offsetMs != 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(offsetLabel,
                style: TextStyle(fontSize: 12, color: labelColor)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                LyricsOffsetMath.format(offsetMs),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: valueColor),
              ),
            ),
            const SizedBox(width: 12),
            _button(Icons.fast_rewind, -1000, btnColor),
            _button(Icons.remove, -500, btnColor),
            _button(Icons.remove_circle_outline, -100, btnColor),
            const SizedBox(width: 4),
            InkWell(
              onTap: canReset ? onReset : null,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.refresh,
                  size: 16,
                  color: canReset
                      ? btnColor
                      : btnColor.withValues(alpha: 0.3),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _button(Icons.add_circle_outline, 100, btnColor),
            _button(Icons.add, 500, btnColor),
            _button(Icons.fast_forward, 1000, btnColor),
          ],
        ),
      ),
    );
  }

  Widget _button(IconData icon, int deltaMs, Color color) {
    return InkWell(
      onTap: () => onAdjust(deltaMs),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
