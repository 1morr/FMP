import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/settings.dart';
import '../data/repositories/settings_repository.dart';
import 'repository_providers.dart';

/// 主题状态
class ThemeState {
  final ThemeMode themeMode;
  final Color? primaryColor;
  final String? fontFamily;
  final bool isLoading;

  const ThemeState({
    this.themeMode = ThemeMode.system,
    this.primaryColor,
    this.fontFamily,
    this.isLoading = true,
  });

  ThemeState copyWith({
    ThemeMode? themeMode,
    Color? primaryColor,
    String? fontFamily,
    bool? isLoading,
    bool clearPrimaryColor = false,
    bool clearFontFamily = false,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      primaryColor: clearPrimaryColor ? null : (primaryColor ?? this.primaryColor),
      fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
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
      fontFamily: _settings!.fontFamily,
      isLoading: false,
    );
  }

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_settings == null) return;

    await _settingsRepository.update((s) => s.themeMode = mode);
    _settings!.themeMode = mode;
    state = state.copyWith(themeMode: mode);
  }

  /// 设置主题色
  Future<void> setPrimaryColor(Color? color) async {
    if (_settings == null) return;

    await _settingsRepository.update((s) => s.primaryColorValue = color);
    _settings!.primaryColorValue = color;
    state = state.copyWith(
      primaryColor: color,
      clearPrimaryColor: color == null,
    );
  }

  /// 设置字体
  Future<void> setFontFamily(String? fontFamily) async {
    if (_settings == null) return;

    await _settingsRepository.update((s) => s.fontFamily = fontFamily);
    _settings!.fontFamily = fontFamily;
    state = state.copyWith(
      fontFamily: fontFamily,
      clearFontFamily: fontFamily == null || fontFamily.isEmpty,
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

/// 便捷 Provider - 当前字体
final fontFamilyProvider = Provider<String?>((ref) {
  return ref.watch(themeProvider).fontFamily;
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
