import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/appearance.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// App 的 seed 色：沿用舊版的預設（M3 baseline 的紫）。preset 與自訂色在設定頁
/// 做外觀設定時再加（ADR 0024 §決定 1）。
const appSeedColor = Color(0xFF6750A4);

/// 淺色或深色主題（ADR 0024 §決定 1）：M3 元件、[appSeedColor] 產生的
/// `ColorScheme`、[AppTokens]。
///
/// [fontFamilyFallback] 是目前介面語言的 CJK 字型清單，由平台層提供
/// （`PlatformCapabilities.fontFallback`，ADR 0024 §決定 2）；空清單表示交給
/// 引擎依文字的 locale 挑（Android）。
///
/// [textLocale] 放進每個文字樣式，決定漢字用繁中或簡中字形：不指名字型的平台
/// 只看它。英文介面的 `MaterialApp.locale` 是 `en`，漢字會落到系統的第一個 CJK
/// 字型（Android 是簡中），所以樣式另外帶中文的 locale（`textLocaleOf`）。樣式
/// 的 locale 蓋過 `Text.locale`，要顯示另一種字形的文字改在樣式上指定。
ThemeData buildAppTheme(
  Brightness brightness, {
  required List<String> fontFamilyFallback,
  required Locale textLocale,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: appSeedColor,
    brightness: brightness,
  );
  final localized = _textThemeWithLocale(textLocale);
  return ThemeData(
    colorScheme: scheme,
    fontFamilyFallback: fontFamilyFallback.isEmpty ? null : fontFamilyFallback,
    // ThemeData 把它合併進預設的字級，只加 locale。
    textTheme: localized,
    primaryTextTheme: localized,
    extensions: [AppTokens.forScheme(scheme)],
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// 每個角色只帶 [locale] 的 `TextTheme`。
TextTheme _textThemeWithLocale(Locale locale) {
  final style = TextStyle(locale: locale);
  return TextTheme(
    displayLarge: style,
    displayMedium: style,
    displaySmall: style,
    headlineLarge: style,
    headlineMedium: style,
    headlineSmall: style,
    titleLarge: style,
    titleMedium: style,
    titleSmall: style,
    bodyLarge: style,
    bodyMedium: style,
    bodySmall: style,
    labelLarge: style,
    labelMedium: style,
    labelSmall: style,
  );
}

/// 外觀設定的主題模式對到 Flutter 的。
ThemeMode themeModeOf(ThemeModeSetting setting) => switch (setting) {
  ThemeModeSetting.system => ThemeMode.system,
  ThemeModeSetting.light => ThemeMode.light,
  ThemeModeSetting.dark => ThemeMode.dark,
};
