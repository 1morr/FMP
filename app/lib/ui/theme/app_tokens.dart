import 'package:material_ui/material_ui.dart';

/// 設計 token（ADR 0024 §決定 1）：間距、圓角、語意色、焦點框。
///
/// `lib/ui/`（本目錄除外）的間距、圓角、顏色只從這裡、`ColorScheme` 與
/// [AppLayout]（`app_layout.dart`）取，lint `fmp_design_tokens` 擋數字字面值與
/// `Colors.*`。字級只用 `TextTheme` 的 M3 角色，這裡沒有字級。
///
/// 取用：`AppTokens.of(context)`。間距與圓角不隨主題變，放在 extension 裡是為了
/// 只有一個入口。
@immutable
final class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.success,
    required this.warning,
    required this.focusRingColor,
  });

  /// 由主題的 [ColorScheme] 推出：語意色以固定的 seed 產生同亮度的 M3 色調
  /// （`ColorScheme.fromSeed` 的 primary 那一組），焦點框用 `primary`。
  factory AppTokens.forScheme(ColorScheme scheme) => AppTokens(
    success: SemanticColors._fromSeed(_successSeed, scheme.brightness),
    warning: SemanticColors._fromSeed(_warningSeed, scheme.brightness),
    focusRingColor: scheme.primary,
  );

  /// 目前主題的 token。主題由 `buildAppTheme` 建立，一定帶著它。
  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>()!;

  /// 成功的綠、警告的琥珀；只當 seed，實際顏色是 M3 依亮度算出的色調。
  static const _successSeed = Color(0xFF2E7D32);
  static const _warningSeed = Color(0xFFF9A825);

  /// 間距：4dp 的倍數，名稱是倍數（`x4` = 16dp）。
  AppSpacing get spacing => const AppSpacing();

  /// 圓角：M3 shape scale。
  AppRadius get radius => const AppRadius();

  final SemanticColors success;
  final SemanticColors warning;

  /// 焦點框：[focusRingWidth] 寬的 `primary`，向外擴 [focusRingOffset]。
  final Color focusRingColor;
  double get focusRingWidth => 2;
  double get focusRingOffset => 2;

  @override
  AppTokens copyWith({
    SemanticColors? success,
    SemanticColors? warning,
    Color? focusRingColor,
  }) => AppTokens(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    focusRingColor: focusRingColor ?? this.focusRingColor,
  );

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      success: SemanticColors.lerp(success, other.success, t),
      warning: SemanticColors.lerp(warning, other.warning, t),
      focusRingColor: Color.lerp(focusRingColor, other.focusRingColor, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppTokens &&
      other.success == success &&
      other.warning == warning &&
      other.focusRingColor == focusRingColor;

  @override
  int get hashCode => Object.hash(success, warning, focusRingColor);
}

/// 間距（dp）。ADR 0024 §決定 1 的九個值。
@immutable
final class AppSpacing {
  const AppSpacing();

  double get x1 => 4;
  double get x2 => 8;
  double get x3 => 12;
  double get x4 => 16;
  double get x5 => 20;
  double get x6 => 24;
  double get x8 => 32;
  double get x10 => 40;
  double get x12 => 48;
}

/// 圓角半徑（dp），M3 shape scale 的名稱。
@immutable
final class AppRadius {
  const AppRadius();

  double get extraSmall => 4;
  double get small => 8;
  double get medium => 12;
  double get large => 16;
  double get extraLarge => 28;
}

/// 一個語意色的四個色調，對應 M3 的 primary 那一組：[color]／[onColor] 給
/// 圖示與強調，[container]／[onContainer] 給底色與上面的文字。成對使用，
/// 對比度由 M3 的色調差保證。
@immutable
final class SemanticColors {
  const SemanticColors({
    required this.color,
    required this.onColor,
    required this.container,
    required this.onContainer,
  });

  factory SemanticColors._fromSeed(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return SemanticColors(
      color: scheme.primary,
      onColor: scheme.onPrimary,
      container: scheme.primaryContainer,
      onContainer: scheme.onPrimaryContainer,
    );
  }

  final Color color;
  final Color onColor;
  final Color container;
  final Color onContainer;

  static SemanticColors lerp(SemanticColors a, SemanticColors b, double t) =>
      SemanticColors(
        color: Color.lerp(a.color, b.color, t)!,
        onColor: Color.lerp(a.onColor, b.onColor, t)!,
        container: Color.lerp(a.container, b.container, t)!,
        onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is SemanticColors &&
      other.color == color &&
      other.onColor == onColor &&
      other.container == container &&
      other.onContainer == onContainer;

  @override
  int get hashCode => Object.hash(color, onColor, container, onContainer);
}
