import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'i18n/strings.g.dart';
import 'services/audio/audio_handler.dart';
import 'services/audio/windows_smtc_handler.dart';
import 'services/cache/ranking_cache_service.dart';
import 'services/radio/radio_refresh_service.dart';

/// 全局 AudioHandler 实例，供 AudioController 使用
late FmpAudioHandler audioHandler;

/// 全局 Windows SMTC Handler 实例，供 AudioController 使用
late WindowsSmtcHandler windowsSmtcHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 限制 Flutter 图片内存缓存大小，减少内存占用
  // 默认值：maximumSize = 1000, maximumSizeBytes = 100 MB
  // 优化后：maximumSize = 200, maximumSizeBytes = 50 MB
  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;

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
        fastForwardInterval: Duration(seconds: 10),
        rewindInterval: Duration(seconds: 10),
      ),
    );
  } else {
    // 桌面平台不需要后台播放服务，但为了代码一致性创建一个 dummy handler
    audioHandler = FmpAudioHandler();
  }

  // 初始化 media_kit（直接使用，不通过 just_audio）
  // 原生支持 httpHeaders，解决了 just_audio_media_kit 代理对 audio-only 流的兼容性问题
  MediaKit.ensureInitialized();

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

  // 初始化首頁排行榜緩存服務（後台加載，不阻塞啟動）
  RankingCacheService.instance = RankingCacheService();
  RankingCacheService.instance.initialize(); // 不等待，後台執行

  // 初始化電台刷新服務（後台加載，不阻塞啟動）
  // 注意：Repository 由 RadioController 設置，定時刷新在設置後自動啟動
  RadioRefreshService.instance = RadioRefreshService();

  // 初始化 i18n（先使用设备语言，后续由 LocaleProvider 加载用户设置覆盖）
  LocaleSettings.useDeviceLocale();

  runApp(
    ProviderScope(
      child: TranslationProvider(
        child: const FMPApp(),
      ),
    ),
  );
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
    minimumSize: Size(400, 500), // 最小窗口大小
    size: Size(1280, 800), // 默认窗口大小
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Windows: 设置关闭窗口时最小化到托盘而不是退出
  if (Platform.isWindows) {
    await windowManager.setPreventClose(true);
  }
}
