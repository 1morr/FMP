import 'dart:io' show Platform;
import 'package:flutter/material.dart';

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
  static const Color defaultPrimaryColor = Color(0xFF6750A4);

  /// 可选字体列表（按平台）
  static List<FontOption> get availableFonts {
    if (Platform.isWindows) {
      return const [
        FontOption(null, '系统默认'),
        FontOption('Microsoft YaHei UI', '微软雅黑'),
        FontOption('SimSun', '宋体'),
        FontOption('SimHei', '黑体'),
        FontOption('KaiTi', '楷体'),
        FontOption('FangSong', '仿宋'),
        FontOption('Yu Gothic UI', 'Yu Gothic UI'),
        FontOption('Meiryo', 'Meiryo'),
      ];
    }
    // Android
    return const [
      FontOption(null, '系统默认'),
      FontOption('sans-serif', '无衬线 (Roboto)'),
      FontOption('serif', '衬线 (Noto Serif)'),
      FontOption('sans-serif-medium', '无衬线 中等'),
      FontOption('sans-serif-light', '无衬线 细体'),
      FontOption('sans-serif-condensed', '无衬线 窄体'),
      FontOption('monospace', '等宽'),
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
    final seedColor = primaryColor ?? defaultPrimaryColor;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    final fallback = _buildFontFallback(fontFamily);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      fontFamily: (fontFamily != null && fontFamily.isNotEmpty) ? fontFamily : null,

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
          borderRadius: BorderRadius.circular(12),
        ),
        color: colorScheme.surfaceContainerHighest,
      ),

      // 列表瓦片主题
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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
    final seedColor = primaryColor ?? defaultPrimaryColor;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    final fallback = _buildFontFallback(fontFamily);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      fontFamily: (fontFamily != null && fontFamily.isNotEmpty) ? fontFamily : null,

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
          borderRadius: BorderRadius.circular(12),
        ),
        color: colorScheme.surfaceContainerHighest,
      ),

      // 列表瓦片主题
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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
