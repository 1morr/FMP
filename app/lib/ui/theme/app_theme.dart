import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/appearance.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 淺色或深色主題（ADR 0024 §決定 1、ADR 0035 §決定 5）：M3 元件、[seedColor] 產生的
/// `ColorScheme`、[AppTokens]，與舊版的元件主題（卡片、輸入框、清單列、AppBar、
/// 導覽指示）。
///
/// [seedColor] 是使用者選的主題色，`null`＝沒選過（預設的紫，純 `fromSeed`）；選過的色照舊版
/// （`lib/ui/theme/app_theme.dart` 的 `_colorScheme`）直接當 `primary`，見 [appColorScheme]。
///
/// [fontFamily] 是使用者選的字型（`null`＝系統預設）：放進 `ThemeData.fontFamily`，
/// 排在 [fontFamilyFallback] 之前，所以選了字型之後 CJK fallback 仍接在後面。
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
  Color? seedColor,
  String? fontFamily,
}) {
  final scheme = appColorScheme(brightness, seedColor);
  final localized = _textThemeWithLocale(textLocale);
  const radius = AppRadius();
  return ThemeData(
    colorScheme: scheme,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback.isEmpty ? null : fontFamilyFallback,
    // ThemeData 把它合併進預設的字級，只加 locale。
    textTheme: localized,
    primaryTextTheme: localized,
    extensions: [AppTokens.forScheme(scheme)],
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    // 以下是舊版的元件主題（`lib/ui/theme/app_theme.dart`），數值照舊版。
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius.medium),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius.small),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    navigationRailTheme: NavigationRailThemeData(
      elevation: 0,
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      elevation: 0,
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: _inputBorder(radius, BorderSide.none),
      enabledBorder: _inputBorder(radius, BorderSide.none),
      focusedBorder: _inputBorder(
        radius,
        BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
    ),
  );
}

/// 主題的 `ColorScheme`，照舊版的 `_colorScheme`：沒選過主題色（[seedColor] 為 `null`）是純
/// `fromSeed(預設)`；選過任何顏色都先 `fromSeed`，再把 `primary` 換成那個顏色本身，
/// `primaryContainer` 是它疊在 `surface` 上的 18%（淺色）或 32%（深色），前景色依對比取黑或白，
/// `surfaceTint` 也跟著。所以色塊畫的顏色就是實際的主色。
ColorScheme appColorScheme(Brightness brightness, Color? seedColor) {
  final base = ColorScheme.fromSeed(
    seedColor: seedColor ?? appSeedColor,
    brightness: brightness,
  );
  if (seedColor == null) return base;
  final primary = seedColor.withValues(alpha: 1);
  final container = Color.alphaBlend(
    primary.withValues(alpha: brightness == Brightness.light ? 0.18 : 0.32),
    base.surface,
  );
  return base.copyWith(
    primary: primary,
    onPrimary: foregroundColorFor(primary),
    primaryContainer: container,
    onPrimaryContainer: foregroundColorFor(container),
    surfaceTint: primary,
  );
}

/// [background] 上對比較高的前景色：黑或白（舊版的 `_foregroundColorFor`）。
Color foregroundColorFor(Color background) {
  final luminance = background.computeLuminance();
  final blackContrast = (luminance + 0.05) / 0.05;
  final whiteContrast = 1.05 / (luminance + 0.05);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

OutlineInputBorder _inputBorder(AppRadius radius, BorderSide side) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius.medium),
      borderSide: side,
    );

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
