import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../services/lyrics/lyrics_window_style.dart';
import '../../widgets/lyrics/lyrics_styled_text.dart';

/// 單行歌詞呈現（主行 + 選用翻譯/羅馬拼音副行）。
///
/// 從 `lyrics_window.dart` 的 `_buildLyricsLine` 抽出為可注入資料的 leaf widget
/// （C1a/C1e：脫離 desktop_multi_window engine 單獨做 widget 測試）。樣式完全
/// 由傳入的 [style] / [transparentMode] / [isCurrent] / [fontSizes] 決定；
/// 點擊/右鍵回呼由 caller 注入，僅在 [isSynced] 且 [hasTimestamp] 時啟用。
class LyricsLineItem extends StatelessWidget {
  const LyricsLineItem({
    super.key,
    required this.text,
    this.subText,
    required this.isCurrent,
    required this.fontSizes,
    required this.transparentMode,
    required this.style,
    required this.isSynced,
    required this.hasTimestamp,
    this.onTap,
    this.onSecondaryTap,
  });

  final String text;
  final String? subText;
  final bool isCurrent;
  final ({double main, double sub}) fontSizes;
  final bool transparentMode;
  final LyricsWindowStyle style;
  final bool isSynced;
  final bool hasTimestamp;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final t = transparentMode;
    final applyTextStyle = style.shouldApplyToText(transparentMode: t);
    final colorScheme = Theme.of(context).colorScheme;

    final mainColor = style.resolveMainColor(
      isCurrent: isCurrent,
      transparentMode: t,
      fallbackCurrentColor: colorScheme.onSurface,
      fallbackInactiveColor: colorScheme.onSurface.withValues(alpha: 0.4),
    );
    final subColor = style.resolveSecondaryColor(
      isCurrent: isCurrent,
      transparentMode: t,
      fallbackCurrentColor: colorScheme.onSurface.withValues(alpha: 0.7),
      fallbackInactiveColor: colorScheme.onSurface.withValues(alpha: 0.3),
    );

    final tapEnabled = isSynced && hasTimestamp;

    return GestureDetector(
      onTap: tapEnabled ? onTap : null,
      onSecondaryTap: tapEnabled ? onSecondaryTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedDefaultTextStyle(
              duration: AnimationDurations.medium,
              style: LyricsTextStyles.fromTheme(
                context,
                fontSize: fontSizes.main,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: mainColor,
                height: LyricsTextStyles.lineHeight,
              ),
              child: Builder(
                builder: (context) {
                  final style = DefaultTextStyle.of(context).style;
                  if (!applyTextStyle) {
                    return Text(text, textAlign: TextAlign.center);
                  }
                  return LyricsStyledText(
                    text,
                    style: style,
                    lyricsStyle: this.style,
                    textAlign: TextAlign.center,
                  );
                },
              ),
            ),
            if (subText != null && subText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: AnimatedDefaultTextStyle(
                  duration: AnimationDurations.medium,
                  style: LyricsTextStyles.fromTheme(
                    context,
                    fontSize: fontSizes.sub,
                    fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
                    color: subColor,
                    height: LyricsTextStyles.lineHeight,
                  ),
                  child: Builder(
                    builder: (context) {
                      final style = DefaultTextStyle.of(context).style;
                      if (!applyTextStyle) {
                        return Text(subText!, textAlign: TextAlign.center);
                      }
                      return LyricsStyledText(
                        subText!,
                        style: style,
                        lyricsStyle: this.style,
                        textAlign: TextAlign.center,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
