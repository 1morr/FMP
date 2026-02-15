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

/// 音质等级
enum AudioQualityLevel {
  /// 最高码率
  high,
  /// 中等码率
  medium,
  /// 最低码率（省流量）
  low,
}

/// 音频格式（用户可排序优先级）
enum AudioFormat {
  /// Opus 编码 (WebM 容器，音质好、体积小，兼容性稍差)
  opus,
  /// AAC 编码 (MP4/M4A 容器，兼容性好)
  aac,
}

/// 流类型
enum StreamType {
  /// 纯音频流
  audioOnly,
  /// 混合流 (视频+音频)
  muxed,
  /// HLS 分段流 (仅 YouTube)
  hls,
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
  int maxCacheSizeMB = 32; // 默认 32MB

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

  /// 记住播放位置（应用重启后从上次位置继续播放）
  bool rememberPlaybackPosition = true;

  /// 应用重启恢复时回退秒数（0 = 从精确位置恢复）
  int restartRewindSeconds = 0;

  /// 临时播放恢复时回退秒数
  int tempPlayRewindSeconds = 10;

  // ========== 下载设置 ==========

  /// 最大并发下载数 (1-5)
  int maxConcurrentDownloads = 3;

  /// 下载图片选项: 0=none, 1=coverOnly, 2=coverAndAvatar
  int downloadImageOptionIndex = 1;

  // ========== 桌面平台设置 ==========

  /// 关闭窗口时最小化到托盘（仅 Windows）
  bool minimizeToTrayOnClose = true;

  /// 启用全局快捷键（仅 Windows）
  bool enableGlobalHotkeys = true;

  /// 开机自启动（仅 Windows）
  bool launchAtStartup = false;

  /// 自启动时最小化到托盘（仅 Windows）
  bool launchMinimized = false;

  /// 自定义字体 (null 或空 = 系统默认)
  String? fontFamily;

  /// 语言设置 (null = 跟随系统, 'zh_CN', 'zh_TW', 'en')
  String? locale;

  // ========== 音频质量设置 ==========

  /// 音质等级: 0=high, 1=medium, 2=low
  int audioQualityLevelIndex = 0;

  /// 格式优先级 (逗号分隔: "aac,opus,m4a,webm")
  /// 按顺序尝试，第一个可用的格式被选中
  String audioFormatPriority = 'aac,opus';

  /// YouTube 流优先级 (逗号分隔: "audioOnly,muxed,hls")
  String youtubeStreamPriority = 'audioOnly,muxed,hls';

  /// Bilibili 流优先级 (逗号分隔: "audioOnly,muxed")
  String bilibiliStreamPriority = 'audioOnly,muxed';

  /// 首选音频输出设备 ID (null = 自动/跟随系统)
  String? preferredAudioDeviceId;

  /// 首选音频输出设备名称 (用于 UI 显示，设备 ID 可能变化)
  String? preferredAudioDeviceName;

  // ========== 歌词设置 ==========

  /// 自动匹配歌词（播放时自动搜索并匹配）
  bool autoMatchLyrics = true;

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

  /// 获取音质等级
  @ignore
  AudioQualityLevel get audioQualityLevel {
    switch (audioQualityLevelIndex) {
      case 1:
        return AudioQualityLevel.medium;
      case 2:
        return AudioQualityLevel.low;
      default:
        return AudioQualityLevel.high;
    }
  }

  /// 设置音质等级
  set audioQualityLevel(AudioQualityLevel level) {
    switch (level) {
      case AudioQualityLevel.high:
        audioQualityLevelIndex = 0;
        break;
      case AudioQualityLevel.medium:
        audioQualityLevelIndex = 1;
        break;
      case AudioQualityLevel.low:
        audioQualityLevelIndex = 2;
        break;
    }
  }

  /// 获取格式优先级列表
  @ignore
  List<AudioFormat> get audioFormatPriorityList {
    if (audioFormatPriority.isEmpty) {
      return [AudioFormat.aac, AudioFormat.opus];
    }
    return audioFormatPriority.split(',').map((s) {
      switch (s.trim()) {
        case 'opus':
          return AudioFormat.opus;
        default:
          return AudioFormat.aac;
      }
    }).toList();
  }

  /// 设置格式优先级列表
  set audioFormatPriorityList(List<AudioFormat> list) {
    audioFormatPriority = list.map((f) {
      switch (f) {
        case AudioFormat.opus:
          return 'opus';
        case AudioFormat.aac:
          return 'aac';
      }
    }).join(',');
  }

  /// 获取 YouTube 流优先级列表
  @ignore
  List<StreamType> get youtubeStreamPriorityList {
    if (youtubeStreamPriority.isEmpty) {
      return [StreamType.audioOnly, StreamType.muxed, StreamType.hls];
    }
    return youtubeStreamPriority.split(',').map((s) {
      switch (s.trim()) {
        case 'muxed':
          return StreamType.muxed;
        case 'hls':
          return StreamType.hls;
        default:
          return StreamType.audioOnly;
      }
    }).toList();
  }

  /// 设置 YouTube 流优先级列表
  set youtubeStreamPriorityList(List<StreamType> list) {
    youtubeStreamPriority = list.map((t) {
      switch (t) {
        case StreamType.audioOnly:
          return 'audioOnly';
        case StreamType.muxed:
          return 'muxed';
        case StreamType.hls:
          return 'hls';
      }
    }).join(',');
  }

  /// 获取 Bilibili 流优先级列表
  @ignore
  List<StreamType> get bilibiliStreamPriorityList {
    if (bilibiliStreamPriority.isEmpty) {
      return [StreamType.audioOnly, StreamType.muxed];
    }
    return bilibiliStreamPriority.split(',').map((s) {
      switch (s.trim()) {
        case 'muxed':
          return StreamType.muxed;
        default:
          return StreamType.audioOnly;
      }
    }).toList();
  }

  /// 设置 Bilibili 流优先级列表
  set bilibiliStreamPriorityList(List<StreamType> list) {
    bilibiliStreamPriority = list.map((t) {
      switch (t) {
        case StreamType.audioOnly:
          return 'audioOnly';
        case StreamType.muxed:
          return 'muxed';
        case StreamType.hls:
          return 'hls';
      }
    }).join(',');
  }

  @override
  String toString() =>
      'Settings(themeMode: $themeMode, maxCacheSizeMB: $maxCacheSizeMB)';
}
