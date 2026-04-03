import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:window_manager/window_manager.dart';

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/logger.dart';
import 'data/models/track.dart';
import 'data/models/playlist.dart';
import 'data/models/play_queue.dart';
import 'data/models/settings.dart';
import 'data/models/search_history.dart';
import 'data/models/download_task.dart';
import 'data/models/play_history.dart';
import 'data/models/radio_station.dart';
import 'data/models/lyrics_match.dart';
import 'data/models/account.dart';
import 'i18n/strings.g.dart';
import 'services/audio/audio_handler.dart';
import 'services/audio/windows_smtc_handler.dart';
import 'services/cache/ranking_cache_service.dart';
import 'services/radio/radio_refresh_service.dart';
import 'ui/windows/lyrics_window.dart';

/// 全局 AudioHandler 实例，供 AudioController 使用
late FmpAudioHandler audioHandler;

/// 全局 Windows SMTC Handler 实例，供 AudioController 使用
late WindowsSmtcHandler windowsSmtcHandler;

/// Whether launched in minimized mode (auto-start to tray)
bool launchMinimized = false;

/// 预读的主题模式（在 runApp 之前从 Isar 读取，避免启动闪屏）
ThemeMode preloadedThemeMode = ThemeMode.system;

/// 预读的主题色
Color? preloadedPrimaryColor;

/// 预读的字体
String? preloadedFontFamily;

void main(List<String> args) async {
  // 子窗口入口：如果是由 desktop_multi_window 创建的子窗口，走独立入口
  if (args.firstOrNull == 'multi_window') {
    lyricsWindowMain(args);
    return;
  }

  // 捕获 Flutter 框架层错误（渲染、布局等）
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.error(
      'FlutterError: ${details.exception}',
      details.exception,
      details.stack,
      'FlutterError',
    );
    // Debug 模式保留默认行为（红屏），Release 模式静默记录
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    }
  };

  runZonedGuarded(() async {
    // 初始化 Marionette（debug + profile 模式，用于 AI 代理运行时交互）
    // kReleaseMode 为 false 时包含 debug 和 profile 两种模式
    if (!kReleaseMode) {
      MarionetteBinding.ensureInitialized();
    } else {
      WidgetsFlutterBinding.ensureInitialized();
    }

    launchMinimized = args.contains('--minimized');

    // 预读主题设置，避免启动时主题闪烁（白→黑→白）
    await _preloadThemeSettings();

  // 限制 Flutter 图片内存缓存大小，减少内存占用
  // 默认值：maximumSize = 1000, maximumSizeBytes = 100 MB
  // 配合 ThumbnailUrlUtils 缩略图优化（200×200 ≈ 160KB decoded），适当增大缓存
  // 避免首页 50+ 张缩略图导致缓存抖动（频繁驱逐→重新解码→CPU 浪费）
  if (Platform.isAndroid || Platform.isIOS) {
    // 移动端：100 张 / 50 MB（首页+探索页同时可见 ~50 张缩略图）
    PaintingBinding.instance.imageCache.maximumSize = 100;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
  } else {
    // 桌面端：200 张 / 80 MB（三栏布局同时可见更多图片）
    PaintingBinding.instance.imageCache.maximumSize = 200;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 80 * 1024 * 1024;
  }

  // Android/iOS 后台播放初始化（使用 audio_service 替代 just_audio_background）
  if (Platform.isAndroid || Platform.isIOS) {
    audioHandler = await AudioService.init(
      builder: () => FmpAudioHandler(),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.personal.fmp.channel.audio',
        androidNotificationChannelName: t.notification.channelName,
        androidNotificationChannelDescription: t.notification.channelDescription,
        androidNotificationOngoing: true,
        androidShowNotificationBadge: true,
        androidStopForegroundOnPause: true,
        fastForwardInterval: const Duration(seconds: 10),
        rewindInterval: const Duration(seconds: 10),
      ),
    );
  } else {
    // 桌面平台不需要后台播放服务，但为了代码一致性创建一个 dummy handler
    audioHandler = FmpAudioHandler();
  }

  // 初始化 media_kit（仅桌面平台需要，Android 使用 just_audio）
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    MediaKit.ensureInitialized();
  }

  // Windows 平台初始化（并行化 SMTC 和窗口管理器以优化启动时间）
  if (Platform.isWindows) {
    // 并行初始化 SMTC 和 WindowManager
    await Future.wait([
      _initializeSmtc(),
      _initializeWindowManager(),
    ]);
  } else if (Platform.isLinux || Platform.isMacOS) {
    // 非 Windows 桌面平台只初始化窗口管理器
    windowsSmtcHandler = WindowsSmtcHandler();
    await _initializeWindowManager();
  } else {
    // 移动平台不需要窗口管理
    windowsSmtcHandler = WindowsSmtcHandler();
  }

  // 延迟初始化后台服务，避免阻塞首帧渲染
  // 首頁排行榜和電台刷新在第一帧渲染后启动，用户感知不到延迟
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // 初始化首頁排行榜緩存服務（後台加載）
    RankingCacheService.instance = RankingCacheService();
    RankingCacheService.instance.initialize();

    // 初始化電台刷新服務（後台加載）
    RadioRefreshService.instance = RadioRefreshService();
  });

  // 初始化 i18n（先使用设备语言，后续由 LocaleProvider 加载用户设置覆盖）
  LocaleSettings.useDeviceLocale();

  runApp(
    ProviderScope(
      child: TranslationProvider(
        child: const FMPApp(),
      ),
    ),
  );
  }, (error, stackTrace) {
    AppLogger.error('Uncaught async error', error, stackTrace, 'Zone');
  });
}

/// 初始化 Windows SMTC（系统媒体传输控制）
Future<void> _initializeSmtc() async {
  await SMTCWindows.initialize();
  windowsSmtcHandler = WindowsSmtcHandler();
  await windowsSmtcHandler.initialize();
}

/// 初始化桌面窗口管理器
Future<void> _initializeWindowManager() async {
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    minimumSize: Size(AppConstants.minimumWindowWidth, AppConstants.minimumWindowHeight),
    size: Size(AppConstants.defaultWindowWidth, AppConstants.defaultWindowHeight),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (!launchMinimized) {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  // Windows: 设置关闭窗口时最小化到托盘而不是退出
  if (Platform.isWindows) {
    await windowManager.setPreventClose(true);
  }
}

/// 预读主题设置（在 runApp 之前调用，避免启动时主题闪烁）
///
/// 提前打开 Isar 读取 Settings，databaseProvider 后续 open 同名数据库会复用此实例。
Future<void> _preloadThemeSettings() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final isar = await Isar.open(
      [
        TrackSchema,
        PlaylistSchema,
        PlayQueueSchema,
        SettingsSchema,
        SearchHistorySchema,
        DownloadTaskSchema,
        PlayHistorySchema,
        RadioStationSchema,
        LyricsMatchSchema,
        AccountSchema,
      ],
      directory: dir.path,
      name: 'fmp_database',
      maxSizeMiB: 64,
      compactOnLaunch: const CompactCondition(
        minFileSize: 8 * 1024 * 1024,
        minRatio: 2.0,
      ),
    );
    final settings = await isar.settings.get(0);
    if (settings != null) {
      preloadedThemeMode = settings.themeMode;
      preloadedPrimaryColor = settings.primaryColorValue;
      preloadedFontFamily = settings.fontFamily;
    }
  } catch (_) {
    // 预读失败不影响启动，使用默认值
  }
}
