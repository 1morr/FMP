import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/audio/audio_handler.dart';

/// 全局 AudioHandler 实例，供 AudioController 使用
late FmpAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android/iOS 后台播放初始化（使用 audio_service 替代 just_audio_background）
  if (Platform.isAndroid || Platform.isIOS) {
    audioHandler = await AudioService.init(
      builder: () => FmpAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.personal.fmp.channel.audio',
        androidNotificationChannelName: 'FMP 音频播放',
        androidNotificationChannelDescription: 'FMP 音乐播放器后台播放通知',
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

  // 初始化 media_kit 作为 just_audio 的 Windows/Linux 后端
  // 这替代了 just_audio_windows，避免其平台线程消息队列溢出问题
  JustAudioMediaKit.ensureInitialized();

  // 仅在桌面平台初始化窗口管理器
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
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

  // TODO: 初始化 Isar 数据库
  // TODO: 初始化音频服务
  // TODO: 初始化平台特定服务（托盘、快捷键等）

  runApp(
    const ProviderScope(
      child: FMPApp(),
    ),
  );
}
