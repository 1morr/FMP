import 'dart:io' show Platform;
import 'package:flutter/material.dart';

import '../../core/constants/ui_constants.dart';
import '../../i18n/strings.g.dart';
import 'theme_preset_colors.dart';

/// 字体选项
class FontOption {
  final String? fontFamily;
  final String displayName;

  const FontOption(this.fontFamily, this.displayName);
}

/// Material 3 主题配置
class AppTheme {
  AppTheme._();

  /// 默认主色
  static const Color defaultPrimaryColor = defaultThemePrimaryColor;

  static ColorScheme _colorScheme({
    required Brightness brightness,
    Color? primaryColor,
  }) {
    final seedColor = primaryColor ?? defaultPrimaryColor;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    if (primaryColor == null) {
      return colorScheme;
    }

    final primary = primaryColor.withValues(alpha: 1);
    final primaryContainer = _primaryContainerColor(
      primary: primary,
      surface: colorScheme.surface,
      brightness: brightness,
    );

    return colorScheme.copyWith(
      primary: primary,
      onPrimary: _foregroundColorFor(primary),
      primaryContainer: primaryContainer,
      onPrimaryContainer: _foregroundColorFor(primaryContainer),
      inversePrimary: primary,
      surfaceTint: primary,
    );
  }

  static Color _primaryContainerColor({
    required Color primary,
    required Color surface,
    required Brightness brightness,
  }) {
    final alpha = brightness == Brightness.light ? 0.18 : 0.32;
    return Color.alphaBlend(primary.withValues(alpha: alpha), surface);
  }

  static Color _foregroundColorFor(Color background) {
    return background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  /// 可选字体列表（按平台）
  static List<FontOption> get availableFonts {
    if (Platform.isWindows) {
      return [
        FontOption(null, t.general.systemDefault),
        FontOption('Microsoft YaHei UI', t.settings.font.microsoftYaHei),
        FontOption('SimSun', t.settings.font.simsun),
        FontOption('SimHei', t.settings.font.simhei),
        FontOption('KaiTi', t.settings.font.kaiti),
        FontOption('FangSong', t.settings.font.fangsong),
        const FontOption('Yu Gothic UI', 'Yu Gothic UI'),
        const FontOption('Meiryo', 'Meiryo'),
      ];
    }
    // Android
    return [
      FontOption(null, t.general.systemDefault),
      FontOption('sans-serif', t.settings.font.sansSerif),
      FontOption('serif', t.settings.font.serif),
      FontOption('sans-serif-medium', t.settings.font.sansSerifMedium),
      FontOption('sans-serif-light', t.settings.font.sansSerifLight),
      FontOption('sans-serif-condensed', t.settings.font.sansSerifCondensed),
      FontOption('monospace', t.settings.font.monospace),
    ];
  }

  /// 根据用户选择的字体构建 CJK 字体回退列表
  static List<String> _buildFontFallback(String? fontFamily) {
    if (Platform.isWindows) {
      // 用户选了具体字体时，把它放在 fallback 最前面
      if (fontFamily != null && fontFamily.isNotEmpty) {
        return [fontFamily, 'Microsoft YaHei UI', 'Microsoft YaHei'];
      }
      return const ['Microsoft YaHei UI', 'Microsoft YaHei'];
    }
    return const ['Noto Sans SC'];
  }

  /// 创建浅色主题
  static ThemeData lightTheme({Color? primaryColor, String? fontFamily}) {
    final colorScheme = _colorScheme(
      brightness: Brightness.light,
      primaryColor: primaryColor,
    );

    final fallback = _buildFontFallback(fontFamily);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      fontFamily:
          (fontFamily != null && fontFamily.isNotEmpty) ? fontFamily : null,

      // AppBar 主题
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),

      // 卡片主题
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusLg,
        ),
        color: colorScheme.surfaceContainerHighest,
      ),

      // 列表瓦片主题
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusMd,
        ),
      ),

      // 导航栏主题
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      // 导航轨道主题
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
      ),

      // 导航抽屉主题
      navigationDrawerTheme: NavigationDrawerThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
      ),

      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusLg,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusLg,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusLg,
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),

      // 滑块主题
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamilyFallback: fallback),
    );
  }

  /// 创建深色主题
  static ThemeData darkTheme({Color? primaryColor, String? fontFamily}) {
    final colorScheme = _colorScheme(
      brightness: Brightness.dark,
      primaryColor: primaryColor,
    );

    final fallback = _buildFontFallback(fontFamily);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      fontFamily:
          (fontFamily != null && fontFamily.isNotEmpty) ? fontFamily : null,

      // AppBar 主题
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),

      // 卡片主题
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusLg,
        ),
        color: colorScheme.surfaceContainerHighest,
      ),

      // 列表瓦片主题
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusMd,
        ),
      ),

      // 导航栏主题
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      // 导航轨道主题
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
      ),

      // 导航抽屉主题
      navigationDrawerTheme: NavigationDrawerThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
      ),

      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusLg,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusLg,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusLg,
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),

      // 滑块主题
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamilyFallback: fallback),
    );
  }
}
