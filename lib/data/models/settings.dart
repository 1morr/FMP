import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

part 'settings.g.dart';

/// 下载图片选项枚举
enum DownloadImageOption {
  /// 不下载图片
  none,
  /// 仅封面
  coverOnly,
  /// 封面和头像
  coverAndAvatar,
}

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
  int maxCacheSizeMB = 128; // 默认 128MB

  /// 下载目录
  String? customDownloadDir;

  /// 快捷键配置 (JSON 字符串)
  String? hotkeyConfig;

  /// 启用的音源列表
  List<String> enabledSources = ['bilibili', 'youtube'];

  /// 是否自动刷新导入的歌单
  bool autoRefreshImports = true;

  /// 默认刷新间隔（小时）
  int defaultRefreshIntervalHours = 24;

  /// 切歌时自动跳转到队列页面并定位当前歌曲
  bool autoScrollToCurrentTrack = false;

  // ========== 下载设置 ==========

  /// 最大并发下载数 (1-5)
  int maxConcurrentDownloads = 3;

  /// 下载图片选项: 0=none, 1=coverOnly, 2=coverAndAvatar
  int downloadImageOptionIndex = 1;

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

  /// 获取下载图片选项
  @ignore
  DownloadImageOption get downloadImageOption {
    switch (downloadImageOptionIndex) {
      case 0:
        return DownloadImageOption.none;
      case 2:
        return DownloadImageOption.coverAndAvatar;
      default:
        return DownloadImageOption.coverOnly;
    }
  }

  /// 设置下载图片选项
  set downloadImageOption(DownloadImageOption option) {
    switch (option) {
      case DownloadImageOption.none:
        downloadImageOptionIndex = 0;
        break;
      case DownloadImageOption.coverOnly:
        downloadImageOptionIndex = 1;
        break;
      case DownloadImageOption.coverAndAvatar:
        downloadImageOptionIndex = 2;
        break;
    }
  }

  @override
  String toString() =>
      'Settings(themeMode: $themeMode, maxCacheSizeMB: $maxCacheSizeMB)';
}
