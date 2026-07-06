import 'package:flutter/material.dart';

/// 純邏輯：歌詞多行字級擬合（C1b，多行半）。
///
/// 從 `lyrics_window.dart` 的 `_ensureRefWidth` / `_getFontSizes` 抽出，讓字級
/// 數學可單獨測試（原本埋在 State 內、與 `_cachedRefWidth` 快取混合）。快取
/// 仍由 caller（State）持有；本類別只負責無狀態的尺寸計算。
///
/// 單行（single-line）量測因含兩段式高度重測與不同常數，視覺等價性需 golden
/// 守護，留待 C1a leaf-golden round 一併抽出。
class LyricsTextMeasurer {
  LyricsTextMeasurer._();

  /// 計算代表行的參考寬度：所有非空行 TextPainter 寬度的中位數。
  ///
  /// [styleBuilder] 接收 (fontSize, fontWeight) 回傳量測用的 TextStyle；
  /// caller 自主題產生（與 `LyricsTextStyles.fromTheme` 一致），讓本函式不依賴
  /// `BuildContext`。所有行皆為空時回傳 0。
  static double medianReferenceWidth({
    required Iterable<String> texts,
    required double refFontSize,
    required TextStyle Function(double fontSize, FontWeight weight)
        styleBuilder,
    required TextDirection textDirection,
  }) {
    final widths = <double>[];
    for (final text in texts) {
      if (text.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: styleBuilder(refFontSize, FontWeight.bold),
        ),
        maxLines: 1,
        textDirection: textDirection,
      )..layout();
      widths.add(painter.width);
      painter.dispose();
    }
    if (widths.isEmpty) return 0;
    widths.sort();
    return widths[widths.length ~/ 2];
  }

  /// 依參考寬度與可用寬度推算主/副字級，clamp 到 [minFontSize, maxFontSize]。
  ///
  /// [referenceWidth] 為 null 或 <= 0 時（無可用代表行）退回主字級 =
  /// [maxFontSize]。否則以 `refFontSize * (safeWidth / referenceWidth)` 推算，
  /// 其中 `safeWidth = availableWidth * boldSafetyFactor`；副字級 =
  /// 主字級 * [subFontRatio]，同樣 clamp。
  static ({double main, double sub}) fontSizesFromReferenceWidth({
    required double? referenceWidth,
    required double availableWidth,
    required double minFontSize,
    required double maxFontSize,
    required double refFontSize,
    required double subFontRatio,
    required double boldSafetyFactor,
  }) {
    if (referenceWidth == null || referenceWidth <= 0) {
      final sub =
          (maxFontSize * subFontRatio).clamp(minFontSize, maxFontSize);
      return (main: maxFontSize, sub: sub);
    }
    final safeWidth = availableWidth * boldSafetyFactor;
    final mainSize = (refFontSize * (safeWidth / referenceWidth))
        .clamp(minFontSize, maxFontSize);
    final subSize =
        (mainSize * subFontRatio).clamp(minFontSize, maxFontSize);
    return (main: mainSize, sub: subSize);
  }
}
