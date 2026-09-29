import 'package:flutter/foundation.dart';

/// 決定 CJK 字型 fallback 順序的介面語言（ADR 0024 §決定 7 的三種語言）。
enum FontLanguage { zhTw, zhCn, en }

/// 各介面語言的 `TextStyle.fontFamilyFallback`（ADR 0024 §決定 2）。
///
/// 平台只提供繁中、簡中兩份清單；英文照 ADR 是繁中在前、簡中在後，由
/// [familiesFor] 組出，各平台不必各寫一次。主題怎麼套用在 M1 PR 12。
@immutable
final class FontFallback {
  const FontFallback({
    required this.traditionalChinese,
    required this.simplifiedChinese,
  });

  /// 沒有可指名的系統字型：字形交給引擎依文字的 locale 挑選，所以主題
  /// （M1 PR 12）要讓文字帶介面語言的 locale（例如 `MaterialApp.locale`）。
  static const none = FontFallback(
    traditionalChinese: [],
    simplifiedChinese: [],
  );

  final List<String> traditionalChinese;
  final List<String> simplifiedChinese;

  /// [language] 的 fallback 字型，依優先順序排列。
  List<String> familiesFor(FontLanguage language) => switch (language) {
    FontLanguage.zhTw => traditionalChinese,
    FontLanguage.zhCn => simplifiedChinese,
    FontLanguage.en => [...traditionalChinese, ...simplifiedChinese],
  };
}
