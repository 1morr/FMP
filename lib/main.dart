import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
