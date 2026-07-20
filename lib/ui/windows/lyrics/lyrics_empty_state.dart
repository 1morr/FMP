import 'package:flutter/material.dart';

import '../../../services/lyrics/lyrics_window_style.dart';

/// 歌詞空狀態（等待歌詞）。
///
/// 從 `lyrics_window.dart` 的 `_buildEmpty` 抽出為可注入資料的 leaf widget
/// （C1a/C1e：讓歌詞視窗的純展示元件可脫離 desktop_multi_window engine 單獨
/// 做 widget 測試）。不持有任何生命週期或 channel，只依賴傳入的樣式與文案。
///
/// 配色規格與其他歌詞介面的「無歌詞」空態一致：非透明模式圖示
/// `colorScheme.outline`、文案 `colorScheme.onSurfaceVariant`、圖文間距 12。
/// 透明模式為桌面透明視窗專用分支：白 40% 圖示（含描邊陰影）、文案走
/// [LyricsWindowStyle.resolveSecondaryColor] 以支援自訂副歌詞色。
class LyricsEmptyState extends StatelessWidget {
  const LyricsEmptyState({
    super.key,
    required this.transparentMode,
    required this.style,
    required this.waitingText,
  });

  final bool transparentMode;
  final LyricsWindowStyle style;
  final String waitingText;

  @override
  Widget build(BuildContext context) {
    final t = transparentMode;
    final applyTextStyle = style.shouldApplyToText(transparentMode: t);
    final colorScheme = Theme.of(context).colorScheme;
    final waitingColor = t
        ? style.resolveSecondaryColor(
            isCurrent: true,
            transparentMode: t,
            fallbackCurrentColor: colorScheme.onSurfaceVariant,
            fallbackInactiveColor: colorScheme.onSurfaceVariant,
          )
        : colorScheme.onSurfaceVariant;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 48,
            color: t
                ? Colors.white.withValues(alpha: 0.4)
                : colorScheme.outline,
            shadows: t ? style.shadows : null,
          ),
          const SizedBox(height: 12),
          Text(
            waitingText,
            style: TextStyle(
              color: waitingColor,
              shadows: applyTextStyle ? style.shadows : null,
            ),
          ),
        ],
      ),
    );
  }
}
