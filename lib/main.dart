import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/logger.dart';
import 'data/models/settings.dart';
import 'i18n/strings.g.dart';
import 'providers/database/database_provider.dart';
import 'services/audio/audio_handler.dart';
import 'services/audio/windows_smtc_handler.dart';
import 'services/radio/radio_refresh_service.dart';
import 'services/update/update_service.dart';
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

  // FlutterError.onError 只覆盖框架同步错误。平台通道回调、微任务里抛出的
  // 错误走 PlatformDispatcher.onError；不设它们在 release 模式下不留任何痕迹。
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Uncaught platform error', error, stack, 'PlatformError');
    return true;
  };

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    launchMinimized = args.contains('--minimized');

    // 初始化 i18n（先使用设备语言，后续由 LocaleProvider 加载用户设置覆盖）。
    // 必须排在任何读 t.* 的程式码之前 —— 这一行原本在 runApp() 前才跑，
    // 而 AudioService.init() 早在它之前就把 t.notification.channelName
    // 读走了，于是 Android 的通知频道名永远落在 fallback 的英文。
    // 频道名只在首次建立时写入系统，之后改语言也不会更新。
    LocaleSettings.useDeviceLocale();

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
      // 失败时退回未接系统通知的 handler：没有后台控制比整个 app 起不来好，
      // 而 audioHandler 是 late 字段，抛出后每一次访问都会变成
      // LateInitializationError，看起来像别的毛病。
      try {
        audioHandler = await AudioService.init(
          builder: () => FmpAudioHandler(),
          config: AudioServiceConfig(
            androidNotificationChannelId: 'com.personal.fmp.channel.audio',
            androidNotificationChannelName: t.notification.channelName,
            androidNotificationChannelDescription:
                t.notification.channelDescription,
            androidNotificationOngoing: true,
            androidShowNotificationBadge: true,
            androidStopForegroundOnPause: true,
            fastForwardInterval: const Duration(seconds: 10),
            rewindInterval: const Duration(seconds: 10),
          ),
        );
      } catch (e, stack) {
        AppLogger.error(
            'AudioService.init failed; background playback and the media '
            'notification are unavailable this session',
            e,
            stack,
            'Startup');
        audioHandler = FmpAudioHandler();
      }
    } else {
      // 桌面平台不需要后台播放服务，但为了代码一致性创建一个 dummy handler
      audioHandler = FmpAudioHandler();
    }

    // 初始化 media_kit（仅桌面平台需要，Android 使用 just_audio）
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        MediaKit.ensureInitialized();
      } catch (e, stack) {
        // 抛在 runApp 之前 = 白屏。让 app 起来，播放失败会由后端翻译成
        // PlaybackEndReason 显示给用户，而不是什么都不显示。
        AppLogger.error('MediaKit.ensureInitialized failed; desktop playback '
            'will not work this session', e, stack, 'Startup');
      }
    }

    // Windows 平台初始化（并行化 SMTC 和窗口管理器以优化启动时间）
    if (Platform.isWindows) {
      // 并行初始化 SMTC 和 WindowManager
      await Future.wait([
        _guardStartupStep('SMTC', _initializeSmtc),
        _guardStartupStep('WindowManager', _initializeWindowManager),
      ]);
      // SMTC 初始化失败时 windowsSmtcHandler 仍是未赋值的 late 字段，
      // 补一个未连接原生会话的实例：它的方法都对 _smtc == null 提前返回。
      if (!_smtcHandlerReady) {
        windowsSmtcHandler = WindowsSmtcHandler();
      }
      // 清理旧更新文件（fire-and-forget，不阻塞启动）
      UpdateService.cleanupOldWindowsUpdateFiles();
    } else if (Platform.isLinux || Platform.isMacOS) {
      // 非 Windows 桌面平台只初始化窗口管理器
      windowsSmtcHandler = WindowsSmtcHandler();
      await _guardStartupStep('WindowManager', _initializeWindowManager);
    } else {
      // 移动平台不需要窗口管理
      windowsSmtcHandler = WindowsSmtcHandler();
    }

    // 延迟初始化后台服务，避免阻塞首帧渲染
    // 首頁排行榜和電台刷新在第一帧渲染后启动，用户感知不到延迟
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 初始化電台刷新服務（後台加載）
      RadioRefreshService.instance = RadioRefreshService();
    });

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
  _smtcHandlerReady = true;
}

bool _smtcHandlerReady = false;

/// 跑一个启动步骤，失败时记录并继续。
///
/// runApp() 之前抛出的任何异常都是白屏 —— 用户看不到、日志也没有。启动期的
/// 每一步都是可降级的：少了系统媒体控制或窗口管理，app 仍然能用。
Future<void> _guardStartupStep(String name, Future<void> Function() step) async {
  try {
    await step();
  } catch (e, stack) {
    AppLogger.error('Startup step "$name" failed; continuing without it', e,
        stack, 'Startup');
  }
}

/// 初始化桌面窗口管理器
Future<void> _initializeWindowManager() async {
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    minimumSize:
        Size(AppConstants.minimumWindowWidth, AppConstants.minimumWindowHeight),
    size:
        Size(AppConstants.defaultWindowWidth, AppConstants.defaultWindowHeight),
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
    final isar = await openFmpDatabase();
    final settings = await isar.settings.get(0);
    if (settings != null) {
      preloadedThemeMode = settings.themeMode;
      preloadedPrimaryColor = settings.primaryColorValue;
      preloadedFontFamily = settings.fontFamily;
    }
  } catch (e, stack) {
    // 预读失败不影响启动（继续用默认主题），但必须留痕：这里是 Isar 第一次
    // 打开数据库的地方，吞掉异常会让真正的数据库故障看起来像"主题没生效"。
    AppLogger.error(
        'Theme preload failed; falling back to default theme', e, stack,
        'Startup');
  }
}
