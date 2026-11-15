import 'package:fmp/app/theme/accent.dart';
import 'package:fmp/app/theme/colors.dart';
import 'package:fmp/app/theme/metrics.dart';
import 'package:fmp/app/theme/text.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:material_ui/material_ui.dart';

export 'package:fmp/app/theme/accent.dart';
export 'package:fmp/app/theme/colors.dart';
export 'package:fmp/app/theme/metrics.dart';
export 'package:fmp/app/theme/motion.dart';
export 'package:fmp/app/theme/text.dart';

/// App 的主題：設計系統的 token 放在 [ThemeData.extensions]，Material 元件的
/// 顏色與字級也對到同一組 token。[density] 由 `platform/` 給（[Density.current]）。
ThemeData buildTheme({
  required Brightness brightness,
  required Density density,
  Accent accent = Accent.none,
}) {
  final colors = FmpColors.of(brightness, accent);
  final text = FmpText.of(density);
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: colors.accentFill,
    onPrimary: colors.accentInk,
    secondary: colors.accentFill,
    onSecondary: colors.accentInk,
    error: colors.danger,
    onError: const Color(0xFFFFFFFF),
    surface: colors.bg,
    onSurface: colors.label,
    onSurfaceVariant: colors.label2,
    surfaceContainer: colors.cell,
    surfaceContainerHighest: colors.cell2,
    outline: colors.sepStrong,
    outlineVariant: colors.sep,
    scrim: colors.scrim,
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colors.bg,
    // 密度由 platform/ 決定，不讓 Material 依平台自己猜。
    visualDensity: density == Density.touch
        ? VisualDensity.standard
        : VisualDensity.compact,
    materialTapTargetSize: density == Density.touch
        ? MaterialTapTargetSize.padded
        : MaterialTapTargetSize.shrinkWrap,
    textTheme: TextTheme(
      displaySmall: text.large,
      headlineMedium: text.title1,
      headlineSmall: text.title2,
      titleLarge: text.title3,
      titleMedium: text.head,
      titleSmall: text.sub,
      bodyLarge: text.callout,
      bodyMedium: text.body,
      bodySmall: text.foot,
      labelLarge: text.sub,
      labelMedium: text.cap,
      labelSmall: text.cap2,
    ).apply(bodyColor: colors.label, displayColor: colors.label),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accentSoft,
      selectionHandleColor: colors.accent,
    ),
    dividerColor: colors.sep,
    extensions: [colors, text, FmpMetrics.of(density)],
  );
}

/// 畫面讀 token 的地方。
extension FmpThemeContext on BuildContext {
  FmpColors get fmpColors => Theme.of(this).extension<FmpColors>()!;
  FmpText get fmpText => Theme.of(this).extension<FmpText>()!;
  FmpMetrics get fmpMetrics => Theme.of(this).extension<FmpMetrics>()!;
}
