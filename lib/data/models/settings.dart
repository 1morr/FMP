import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

part 'settings.g.dart';

/// 应用设置实体（单例模式，始终使用 ID 0）
@collection
class Settings {
  Id id = 0;

  /// 主题模式: 0=system, 1=light, 2=dark
  int themeModeIndex = 0;

  /// 自定义颜色 (ARGB int)
  int? primaryColor;
  int? secondaryColor;
  int? backgroundColor;
  int? surfaceColor;
  int? textColor;
  int? cardColor;

  /// 缓存设置
  String? customCacheDir;
  int maxCacheSizeMB = 2048; // 默认 2GB
  String? customDownloadDir;

  /// 快捷键配置 (JSON 字符串)
  String? hotkeyConfig;

  /// 启用的音源列表
  List<String> enabledSources = ['bilibili', 'youtube'];

  /// 是否自动刷新导入的歌单
  bool autoRefreshImports = true;

  /// 默认刷新间隔（小时）
  int defaultRefreshIntervalHours = 24;

  /// 获取 ThemeMode
  @ignore
  ThemeMode get themeMode {
    switch (themeModeIndex) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// 设置 ThemeMode
  set themeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        themeModeIndex = 1;
        break;
      case ThemeMode.dark:
        themeModeIndex = 2;
        break;
      case ThemeMode.system:
        themeModeIndex = 0;
        break;
    }
  }

  /// 获取主色 Color
  @ignore
  Color? get primaryColorValue =>
      primaryColor != null ? Color(primaryColor!) : null;

  /// 设置主色 Color
  set primaryColorValue(Color? color) {
    primaryColor = color?.toARGB32();
  }

  @override
  String toString() =>
      'Settings(themeMode: $themeMode, maxCacheSizeMB: $maxCacheSizeMB)';
}
