import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/settings_repository.dart';
import '../i18n/strings.g.dart';
import 'repository_providers.dart';

/// Locale 管理器
class LocaleNotifier extends StateNotifier<AppLocale?> {
  final SettingsRepository _settingsRepository;

  LocaleNotifier(this._settingsRepository) : super(null) {
    _loadSettings();
  }

  /// 加载语言设置
  Future<void> _loadSettings() async {
    final settings = await _settingsRepository.get();
    final locale = _parseLocale(settings.locale);
    // 先更新 slang 的全局 t，再更新 Riverpod state
    // 确保 Riverpod 触发 rebuild 时 t.xxx 已指向新 locale
    if (locale != null) {
      LocaleSettings.instance.setLocale(locale);
    } else {
      LocaleSettings.instance.useDeviceLocale();
    }
    state = locale;
  }

  /// 设置语言 (null = 跟随系统)
  Future<void> setLocale(AppLocale? locale) async {
    final localeStr = locale != null ? _localeToString(locale) : null;
    await _settingsRepository.update((s) => s.locale = localeStr);
    // 先更新 slang 的全局 t，再更新 Riverpod state
    // 确保 Riverpod 触发 rebuild 时 t.xxx 已指向新 locale
    if (locale != null) {
      LocaleSettings.instance.setLocale(locale);
    } else {
      LocaleSettings.instance.useDeviceLocale();
    }
    state = locale;
  }

  /// 解析 locale 字符串到 AppLocale
  AppLocale? _parseLocale(String? localeStr) {
    if (localeStr == null) return null;
    switch (localeStr) {
      case 'zh_CN':
        return AppLocale.zhCn;
      case 'zh_TW':
        return AppLocale.zhTw;
      case 'en':
        return AppLocale.en;
      default:
        return null;
    }
  }

  /// AppLocale 转换为存储字符串
  String _localeToString(AppLocale locale) {
    switch (locale) {
      case AppLocale.zhCn:
        return 'zh_CN';
      case AppLocale.zhTw:
        return 'zh_TW';
      case AppLocale.en:
        return 'en';
    }
  }
}

/// Locale Provider
final localeProvider = StateNotifierProvider<LocaleNotifier, AppLocale?>((ref) {
  final settingsRepository = ref.watch(settingsRepositoryProvider);
  return LocaleNotifier(settingsRepository);
});

/// 便捷 Provider - 当前 locale 显示名称
final localeDisplayNameProvider = Provider<String>((ref) {
  final locale = ref.watch(localeProvider);
  if (locale == null) return t.settings.language.followSystem;
  return _getLocaleDisplayName(locale);
});

/// 获取 locale 显示名称
String _getLocaleDisplayName(AppLocale locale) {
  switch (locale) {
    case AppLocale.zhCn:
      return '简体中文';
    case AppLocale.zhTw:
      return '繁體中文';
    case AppLocale.en:
      return 'English';
  }
}
