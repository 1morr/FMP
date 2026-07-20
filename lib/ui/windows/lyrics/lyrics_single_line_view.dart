import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/lyrics/lyrics_window_style.dart';
import '../../widgets/lyrics/lyrics_styled_text.dart';
import '../../widgets/lyrics/lyrics_text_measurer.dart';

/// 單行歌詞檢視（放大呈現當前行，含兩段式字級擬合）。
///
/// 從 `lyrics_window.dart` 的 `_buildSingleLine` 抽出（C1a/C1e + C1b 單行半）。
/// caller 預先解析好 [mainText]/[subText]（含「當前行空則退回曲名」邏輯）並
/// 注入；本 leaf 負責 LayoutBuilder 內的字級擬合（refSize=100、minFontSize=24、
/// 寬度縮放 → 高度限制 → 換行後 TextPainter 重測的 two-pass
/// 流程）與呈現。點擊/右鍵回呼僅在 [isSynced] 且 [hasCurrentLine] 時啟用。
///
/// 副行字級比例與行高沿用共用常數（[LyricsTextMeasurer.subFontRatio]、
/// [LyricsTextStyles.lineHeight]），與播放器內嵌歌詞及多行模式一致。
class LyricsSingleLineView extends StatelessWidget {
  const LyricsSingleLineView({
    super.key,
    required this.mainText,
    this.subText,
    required this.transparentMode,
    required this.style,
    required this.isSynced,
    required this.hasCurrentLine,
    this.onTap,
    this.onSecondaryTap,
    this.boldSafetyFactor = LyricsTextMeasurer.boldSafetyFactor,
  });

  final String mainText;
  final String? subText;
  final bool transparentMode;
  final LyricsWindowStyle style;
  final bool isSynced;
  final bool hasCurrentLine;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final double boldSafetyFactor;

  @override
  Widget build(BuildContext context) {
    final t = transparentMode;
    final applyTextStyle = style.shouldApplyToText(transparentMode: t);
    final colorScheme = Theme.of(context).colorScheme;

    final mainColor = style.resolveMainColor(
      isCurrent: true,
      transparentMode: t,
      fallbackCurrentColor: colorScheme.onSurface,
      fallbackInactiveColor: colorScheme.onSurface,
    );
    final subColor = style.resolveSecondaryColor(
      isCurrent: true,
      transparentMode: t,
      fallbackCurrentColor: colorScheme.onSurface.withValues(alpha: 0.6),
      fallbackInactiveColor: colorScheme.onSurface.withValues(alpha: 0.6),
    );
    final hasSubText = subText != null && subText!.isNotEmpty;
    final tapEnabled = isSynced && hasCurrentLine;

    return GestureDetector(
      onTap: tapEnabled ? onTap : null,
      onSecondaryTap: tapEnabled ? onSecondaryTap : null,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth - 32;
          final maxH = constraints.maxHeight - 24;
          if (maxW <= 0 || maxH <= 0) return const SizedBox.shrink();

          const refSize = 100.0;
          const subRatio = LyricsTextMeasurer.subFontRatio;
          const minFontSize = 24.0;
          final td = Directionality.of(context);
          final baseTextStyle = LyricsTextStyles.themeBase(context);

          // 测量主文本单行宽度
          final mainPainter = TextPainter(
            text: TextSpan(
              text: mainText,
              style: LyricsTextStyles.fromBase(
                baseTextStyle,
                fontSize: refSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            maxLines: 1,
            textDirection: td,
          )..layout();
          final mainTextW = mainPainter.width;
          mainPainter.dispose();

          final safeW = maxW * boldSafetyFactor;

          // 主文本：按宽度缩放（单行填满）
          double mainFontSize =
              mainTextW > 0 ? (refSize * safeW / mainTextW) : refSize;

          // 副文本字号
          double subFontSize = 0;
          if (hasSubText) {
            final subPainter = TextPainter(
              text: TextSpan(
                text: subText,
                style: LyricsTextStyles.fromBase(
                  baseTextStyle,
                  fontSize: refSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
              maxLines: 1,
              textDirection: td,
            )..layout();
            final subTextW = subPainter.width;
            subPainter.dispose();

            final subByWidth =
                subTextW > 0 ? (refSize * safeW / subTextW) : refSize;
            final subCap = mainFontSize * subRatio;
            subFontSize = math.min(subByWidth, subCap).clamp(8.0, 200.0);
          }

          // 高度约束（单行估算）
          const lineH = LyricsTextStyles.lineHeight;
          final estMainH = mainFontSize * lineH;
          final estSubH = hasSubText ? subFontSize * lineH : 0.0;
          if (estMainH + estSubH > maxH && estMainH + estSubH > 0) {
            final scale = maxH / (estMainH + estSubH);
            mainFontSize *= scale;
            subFontSize *= scale;
          }

          // 应用最小字号 — 低于最小值时允许换行
          final mainWrap = mainFontSize < minFontSize;
          final subWrap = hasSubText && subFontSize < minFontSize * subRatio;
          if (mainWrap) mainFontSize = minFontSize;
          if (subWrap && hasSubText) subFontSize = minFontSize * subRatio;

          // 换行后用 TextPainter 测量实际高度，再做高度约束
          if (mainWrap || subWrap) {
            double actualH = 0;
            final mp = TextPainter(
              text: TextSpan(
                text: mainText,
                style: LyricsTextStyles.fromBase(
                  baseTextStyle,
                  fontSize: mainFontSize,
                  fontWeight: FontWeight.bold,
                  height: LyricsTextStyles.lineHeight,
                ),
              ),
              textDirection: td,
            )..layout(maxWidth: maxW);
            actualH += mp.height;
            mp.dispose();

            if (hasSubText) {
              final sp = TextPainter(
                text: TextSpan(
                  text: subText,
                  style: LyricsTextStyles.fromBase(
                    baseTextStyle,
                    fontSize: subFontSize,
                    fontWeight: FontWeight.w500,
                    height: LyricsTextStyles.lineHeight,
                  ),
                ),
                textDirection: td,
              )..layout(maxWidth: maxW);
              actualH += sp.height;
              sp.dispose();
            }

            if (actualH > maxH && actualH > 0) {
              final scale = maxH / actualH;
              mainFontSize = (mainFontSize * scale).clamp(10.0, 200.0);
              subFontSize = (subFontSize * scale).clamp(8.0, 200.0);
            }
          }

          mainFontSize = mainFontSize.clamp(10.0, 200.0);
          if (hasSubText) {
            subFontSize = subFontSize.clamp(8.0, 200.0);
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (applyTextStyle)
                    LyricsStyledText(
                      mainText,
                      style: LyricsTextStyles.fromBase(
                        baseTextStyle,
                        fontSize: mainFontSize,
                        fontWeight: FontWeight.bold,
                        color: mainColor,
                        height: LyricsTextStyles.lineHeight,
                      ),
                      lyricsStyle: style,
                      textAlign: TextAlign.center,
                      maxLines: mainWrap ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      mainText,
                      style: LyricsTextStyles.fromBase(
                        baseTextStyle,
                        fontSize: mainFontSize,
                        fontWeight: FontWeight.bold,
                        color: mainColor,
                        height: LyricsTextStyles.lineHeight,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: mainWrap ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (hasSubText)
                    applyTextStyle
                        ? LyricsStyledText(
                            subText!,
                            style: LyricsTextStyles.fromBase(
                              baseTextStyle,
                              fontSize: subFontSize,
                              fontWeight: FontWeight.w500,
                              color: subColor,
                              height: LyricsTextStyles.lineHeight,
                            ),
                            lyricsStyle: style,
                            textAlign: TextAlign.center,
                            maxLines: subWrap ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : Text(
                            subText!,
                            style: LyricsTextStyles.fromBase(
                              baseTextStyle,
                              fontSize: subFontSize,
                              fontWeight: FontWeight.w500,
                              color: subColor,
                              height: LyricsTextStyles.lineHeight,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: subWrap ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
