import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/settings.dart';
import '../data/repositories/settings_repository.dart';
import 'database_provider.dart';

/// 主题状态
class ThemeState {
  final ThemeMode themeMode;
  final Color? primaryColor;
  final bool isLoading;

  const ThemeState({
    this.themeMode = ThemeMode.system,
    this.primaryColor,
    this.isLoading = true,
  });

  ThemeState copyWith({
    ThemeMode? themeMode,
    Color? primaryColor,
    bool? isLoading,
    bool clearPrimaryColor = false,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      primaryColor: clearPrimaryColor ? null : (primaryColor ?? this.primaryColor),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 主题管理器
class ThemeNotifier extends StateNotifier<ThemeState> {
  final SettingsRepository _settingsRepository;
  Settings? _settings;

  ThemeNotifier(this._settingsRepository) : super(const ThemeState()) {
    _loadSettings();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    _settings = await _settingsRepository.get();
    state = ThemeState(
      themeMode: _settings!.themeMode,
      primaryColor: _settings!.primaryColorValue,
      isLoading: false,
    );
  }

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_settings == null) return;

    _settings!.themeMode = mode;
    await _settingsRepository.save(_settings!);
    state = state.copyWith(themeMode: mode);
  }

  /// 设置主题色
  Future<void> setPrimaryColor(Color? color) async {
    if (_settings == null) return;

    _settings!.primaryColorValue = color;
    await _settingsRepository.save(_settings!);
    state = state.copyWith(
      primaryColor: color,
      clearPrimaryColor: color == null,
    );
  }

  /// 切换主题模式
  Future<void> toggleThemeMode() async {
    final nextMode = switch (state.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setThemeMode(nextMode);
  }
}

/// 设置仓库 Provider
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return SettingsRepository(db);
});

/// 主题 Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  final settingsRepository = ref.watch(settingsRepositoryProvider);
  return ThemeNotifier(settingsRepository);
});

/// 便捷 Provider - 当前主题模式
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(themeProvider).themeMode;
});

/// 便捷 Provider - 当前主题色
final primaryColorProvider = Provider<Color?>((ref) {
  return ref.watch(themeProvider).primaryColor;
});

/// 预设颜色列表
const List<Color> presetColors = [
  Color(0xFF6750A4), // 默认紫色 (Material 3)
  Color(0xFF0061A4), // 蓝色
  Color(0xFF006E1C), // 绿色
  Color(0xFFBA1A1A), // 红色
  Color(0xFF984061), // 粉色
  Color(0xFF7C5800), // 橙色
  Color(0xFF006A6A), // 青色
  Color(0xFF4758A9), // 靛蓝色
];
