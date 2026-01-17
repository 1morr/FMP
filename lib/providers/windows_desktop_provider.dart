import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/audio/audio_provider.dart';
import '../../services/platform/windows_desktop_service.dart';

/// Windows 桌面服务 Provider
///
/// 在 Windows 平台上提供系统托盘、全局快捷键和窗口管理功能。
/// 自动监听 AudioController 状态变化并更新托盘显示。
final windowsDesktopServiceProvider = Provider<WindowsDesktopService?>((ref) {
  if (!Platform.isWindows) return null;

  final service = WindowsDesktopService();

  // 监听播放状态变化，更新托盘
  ref.listen(audioControllerProvider, (previous, next) {
    service.updatePlaybackState(
      isPlaying: next.isPlaying,
      currentTrack: next.currentTrack,
    );
  });

  // 设置回调函数
  final controller = ref.read(audioControllerProvider.notifier);
  service.onPlayPause = () => controller.togglePlayPause();
  service.onNext = () => controller.next();
  service.onPrevious = () => controller.previous();
  service.onStop = () => controller.stop();
  service.onVolumeUp = () => controller.adjustVolume(0.1);
  service.onVolumeDown = () => controller.adjustVolume(-0.1);
  service.onMute = () => controller.toggleMute();

  // 初始化服务（不自动注册快捷键，由 globalHotkeysEnabledProvider 控制）
  service.initialize(enableHotkeys: false);

  // 清理
  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

/// Windows 桌面服务初始化 Provider
///
/// 用于在应用启动时初始化 Windows 桌面特性。
/// 返回 true 表示初始化成功。
final windowsDesktopInitProvider = FutureProvider<bool>((ref) async {
  if (!Platform.isWindows) return false;

  final service = ref.watch(windowsDesktopServiceProvider);
  if (service == null) return false;

  await service.initialize();
  return true;
});
