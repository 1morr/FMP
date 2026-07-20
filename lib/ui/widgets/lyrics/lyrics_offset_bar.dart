import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import 'lyrics_offset_math.dart';

/// 歌詞偏移量調整列（offset bar，純展示 leaf，C1d）。
///
/// 從 `lyrics_window.dart` 的 `_buildOffsetBar` + `_offsetButton` 抽出，後提升
/// 為播放器內嵌歌詞（`LyricsDisplay`）與桌面歌詞視窗共用的單一實作。注入目前
/// [offsetMs]、[offsetLabel] / [resetTooltip] 文案，以及 [onAdjust]
/// （±100/500/1000ms）與 [onReset] 回呼。reset 按鈕在 offsetMs == 0 時自動
/// 停用（與原行為一致）。顯示值透過 [LyricsOffsetMath.format] 格式化。
///
/// 本元件只負責內容列（label + 數值晶片 + 按鈕，外包 FittedBox 縮放）；
/// 外層容器（背景、圓角、邊框、padding）由 caller 依所在介面提供。
///
/// 樣式規格（兩介面統一）：
/// - 非透明模式：數值晶片 `primaryContainer` alpha 0.5 底 + `primary` 文字 +
///   [AppRadius.borderRadiusXs]；按鈕圖示 `primary`；label `onSurfaceVariant`。
/// - 透明模式為桌面透明視窗專用分支：白系配色（晶片白 15% 底）。
/// - [compact] 使用較小字級/圖示/內距（Detail Panel 與桌面視窗）；否則為
///   全螢幕播放器的標準尺寸。
class LyricsOffsetBar extends StatelessWidget {
  const LyricsOffsetBar({
    super.key,
    required this.offsetMs,
    required this.offsetLabel,
    required this.resetTooltip,
    required this.onAdjust,
    required this.onReset,
    this.transparentMode = false,
    this.compact = false,
  });

  final int offsetMs;
  final String offsetLabel;
  final String resetTooltip;
  final void Function(int deltaMs) onAdjust;
  final VoidCallback onReset;
  final bool transparentMode;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = transparentMode;
    final colorScheme = Theme.of(context).colorScheme;

    final labelColor = t ? Colors.white70 : colorScheme.onSurfaceVariant;
    final valueColor = t ? Colors.white : colorScheme.primary;
    final btnColor = t ? Colors.white : colorScheme.primary;
    final chipBg = t
        ? Colors.white.withValues(alpha: 0.15)
        : colorScheme.primaryContainer.withValues(alpha: 0.5);
    final disabledColor = t
        ? Colors.white.withValues(alpha: 0.3)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.3);

    final fontSize = compact ? 12.0 : 13.0;
    final canReset = offsetMs != 0;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            offsetLabel,
            style: TextStyle(fontSize: fontSize, color: labelColor),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: AppRadius.borderRadiusXs,
            ),
            child: Text(
              LyricsOffsetMath.format(offsetMs),
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _button(Icons.fast_rewind, -1000, btnColor),
          _button(Icons.remove, -500, btnColor),
          _button(Icons.remove_circle_outline, -100, btnColor),
          const SizedBox(width: 4),
          Tooltip(
            message: resetTooltip,
            child: InkWell(
              onTap: canReset ? onReset : null,
              borderRadius: AppRadius.borderRadiusXs,
              child: Padding(
                padding: EdgeInsets.all(compact ? 4 : 6),
                child: Icon(
                  Icons.refresh,
                  size: compact ? 16 : 18,
                  color: canReset ? btnColor : disabledColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _button(Icons.add_circle_outline, 100, btnColor),
          _button(Icons.add, 500, btnColor),
          _button(Icons.fast_forward, 1000, btnColor),
        ],
      ),
    );
  }

  Widget _button(IconData icon, int deltaMs, Color color) {
    return Tooltip(
      message: _deltaTooltip(deltaMs),
      child: InkWell(
        onTap: () => onAdjust(deltaMs),
        borderRadius: AppRadius.borderRadiusXs,
        child: Padding(
          padding: EdgeInsets.all(compact ? 4 : 6),
          child: Icon(icon, size: compact ? 16 : 18, color: color),
        ),
      ),
    );
  }

  /// 由 delta 毫秒數產生按鈕 Tooltip（'-1s' / '+0.5s' / '-0.1s'）。
  static String _deltaTooltip(int deltaMs) {
    final sign = deltaMs < 0 ? '-' : '+';
    final seconds = deltaMs.abs() / 1000;
    return '$sign${seconds.toStringAsFixed(seconds.truncateToDouble() == seconds ? 0 : 1)}s';
  }
}
