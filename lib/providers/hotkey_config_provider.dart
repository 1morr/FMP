import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/hotkey_config.dart';
import '../data/repositories/settings_repository.dart';
import 'repository_providers.dart';
import 'windows_desktop_provider.dart';

/// 快捷键配置 Provider
///
/// 管理全局快捷键的配置，包括保存和加载。
final hotkeyConfigProvider =
    StateNotifierProvider<HotkeyConfigNotifier, HotkeyConfig>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  final desktopService = ref.watch(windowsDesktopServiceProvider);
  return HotkeyConfigNotifier(repo, desktopService);
});

/// 快捷键配置状态管理器
class HotkeyConfigNotifier extends StateNotifier<HotkeyConfig> {
  final SettingsRepository _repo;
  final dynamic _desktopService; // WindowsDesktopService?

  HotkeyConfigNotifier(this._repo, this._desktopService)
      : super(HotkeyConfig.defaults()) {
    _load();
  }

  /// 从数据库加载配置
  Future<void> _load() async {
    final settings = await _repo.get();
    state = HotkeyConfig.fromJsonString(settings.hotkeyConfig);
    // 应用配置到桌面服务
    _applyToDesktopService();
  }

  /// 更新快捷键绑定
  Future<void> updateBinding(HotkeyBinding binding) async {
    // 检查冲突
    final conflict = state.findConflict(binding);
    if (conflict != null) {
      // 有冲突，清除冲突的绑定
      state = state.clearBinding(conflict);
    }

    state = state.updateBinding(binding);
    await _save();
    _applyToDesktopService();
  }

  /// 清除快捷键绑定
  Future<void> clearBinding(HotkeyAction action) async {
    state = state.clearBinding(action);
    await _save();
    _applyToDesktopService();
  }

  /// 重置为默认配置
  Future<void> resetToDefaults() async {
    state = HotkeyConfig.defaults();
    await _save();
    _applyToDesktopService();
  }

  /// 保存配置到数据库
  Future<void> _save() async {
    final jsonStr = state.toJsonString();
    await _repo.update((s) => s.hotkeyConfig = jsonStr);
  }

  /// 应用配置到桌面服务
  void _applyToDesktopService() {
    _desktopService?.applyHotkeyConfig(state);
  }
}
