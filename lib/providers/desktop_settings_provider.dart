import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../data/repositories/settings_repository.dart';
import '../services/platform/windows_desktop_service.dart';
import 'repository_providers.dart';
import 'windows_desktop_provider.dart';

/// 最小化到托盘设置 Provider
final minimizeToTrayProvider = StateNotifierProvider<_MinimizeToTrayNotifier, bool>((ref) {
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  return _MinimizeToTrayNotifier(settingsRepo);
});

class _MinimizeToTrayNotifier extends StateNotifier<bool> {
  final SettingsRepository _repo;

  _MinimizeToTrayNotifier(this._repo) : super(true) {
    _load();
  }

  Future<void> _load() async {
    final settings = await _repo.get();
    state = settings.minimizeToTrayOnClose;
    // 应用设置到 window_manager
    await windowManager.setPreventClose(state);
  }

  Future<void> toggle() async {
    state = !state;
    await _repo.update((s) => s.minimizeToTrayOnClose = state);
    // 应用设置到 window_manager
    await windowManager.setPreventClose(state);
  }
}

/// 全局快捷键设置 Provider
final globalHotkeysEnabledProvider = StateNotifierProvider<_GlobalHotkeysNotifier, bool>((ref) {
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  final desktopService = ref.watch(windowsDesktopServiceProvider);
  return _GlobalHotkeysNotifier(settingsRepo, desktopService);
});

class _GlobalHotkeysNotifier extends StateNotifier<bool> {
  final SettingsRepository _repo;
  final WindowsDesktopService? _desktopService;

  _GlobalHotkeysNotifier(this._repo, this._desktopService) : super(true) {
    _load();
  }

  Future<void> _load() async {
    final settings = await _repo.get();
    state = settings.enableGlobalHotkeys;
    // 应用设置到桌面服务
    await _desktopService?.setHotkeysEnabled(state);
  }

  Future<void> toggle() async {
    state = !state;
    await _repo.update((s) => s.enableGlobalHotkeys = state);
    // 立即应用设置
    await _desktopService?.setHotkeysEnabled(state);
  }
}

/// 开机自启动状态
class LaunchAtStartupState {
  final bool enabled;
  final bool minimized;

  const LaunchAtStartupState({this.enabled = false, this.minimized = false});

  LaunchAtStartupState copyWith({bool? enabled, bool? minimized}) {
    return LaunchAtStartupState(
      enabled: enabled ?? this.enabled,
      minimized: minimized ?? this.minimized,
    );
  }
}

/// 开机自启动设置 Provider
final launchAtStartupProvider =
    StateNotifierProvider<LaunchAtStartupNotifier, LaunchAtStartupState>((ref) {
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  return LaunchAtStartupNotifier(settingsRepo);
});

class LaunchAtStartupNotifier extends StateNotifier<LaunchAtStartupState> {
  final SettingsRepository _repo;

  LaunchAtStartupNotifier(this._repo) : super(const LaunchAtStartupState()) {
    _load();
  }

  Future<void> _load() async {
    final settings = await _repo.get();
    state = LaunchAtStartupState(
      enabled: settings.launchAtStartup,
      minimized: settings.launchMinimized,
    );
    // 初始化 launch_at_startup
    await _setupLaunchAtStartup();
    // 同步系统状态
    await _applyToSystem();
  }

  Future<void> _setupLaunchAtStartup() async {
    final packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
    );
  }

  Future<void> toggleEnabled() async {
    final newEnabled = !state.enabled;
    state = state.copyWith(enabled: newEnabled);
    await _repo.update((s) => s.launchAtStartup = newEnabled);
    await _applyToSystem();
  }

  Future<void> setMinimized(bool minimized) async {
    state = state.copyWith(minimized: minimized);
    await _repo.update((s) => s.launchMinimized = minimized);
    // 重新应用（需要更新启动参数）
    await _applyToSystem();
  }

  Future<void> _applyToSystem() async {
    if (state.enabled) {
      // 先禁用再重新启用，确保参数更新
      await launchAtStartup.disable();
      // 重新 setup 以包含/排除 --minimized 参数
      final packageInfo = await PackageInfo.fromPlatform();
      final args = state.minimized ? ['--minimized'] : <String>[];
      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
        args: args,
      );
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }
}
