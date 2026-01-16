import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../data/repositories/settings_repository.dart';
import '../services/platform/windows_desktop_service.dart';
import 'repository_providers.dart';
import 'windows_desktop_provider.dart';

/// 最小化到托盘设置 Provider
final minimizeToTrayProvider = StateNotifierProvider<_MinimizeToTrayNotifier, bool>((ref) {
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  return _MinimizeToTrayNotifier(settingsRepo, ref);
});

class _MinimizeToTrayNotifier extends StateNotifier<bool> {
  final SettingsRepository _repo;
  final Ref _ref;

  _MinimizeToTrayNotifier(this._repo, this._ref) : super(true) {
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
    final settings = await _repo.get();
    settings.minimizeToTrayOnClose = state;
    await _repo.save(settings);
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
  }

  Future<void> toggle() async {
    state = !state;
    final settings = await _repo.get();
    settings.enableGlobalHotkeys = state;
    await _repo.save(settings);
    // 注意：重新启用/禁用快捷键需要重启应用才能生效
    // 这是 hotkey_manager 的限制
  }
}
