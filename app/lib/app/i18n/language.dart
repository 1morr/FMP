import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/data/settings_store.dart';

/// 設定「外觀 › 語言」：null 是跟隨系統（預設），否則是選定的語言。改了
/// 立刻生效（slang 的 [LocaleSettings]，`TranslationProvider` 以下跟著重畫）。
final languageProvider = NotifierProvider<LanguageSetting, AppLocale?>(
  LanguageSetting.new,
);

class LanguageSetting extends SavedSetting<AppLocale?> {
  static const _key = 'appearance.language';
  static const _system = 'system';

  @override
  String get key => _key;

  @override
  AppLocale? get fallback => null;

  @override
  ({AppLocale? value})? decode(String raw) => raw == _system
      ? (value: null)
      : switch (decodeChoice(raw)) {
          final locale? => (value: locale),
          null => null,
        };

  @override
  String encode(AppLocale? value) => encodeChoice(value);

  /// 存的寫法：每個語言明寫 BCP 47 的 tag，跟隨系統是 `system`。設定頁的
  /// 語言選單也用它當值。
  static String encodeChoice(AppLocale? choice) => switch (choice) {
    null => _system,
    AppLocale.zhTw => 'zh-TW',
    AppLocale.zhCn => 'zh-CN',
    AppLocale.en => 'en',
  };

  /// [encodeChoice] 的反向；`system` 與讀不懂的都是 null（跟隨系統）。
  static AppLocale? decodeChoice(String raw) =>
      AppLocale.values.where((l) => encodeChoice(l) == raw).firstOrNull;

  @override
  Future<void> set(AppLocale? value) {
    final saving = super.set(value);
    applyLanguage(value);
    return saving;
  }

  /// 開 App 時（`runApp` 之前）照存的設定 [saved] 切好語言，第一個畫面就是
  /// 那個語言。
  static void applySaved(Map<String, String> saved) =>
      applyLanguage(switch (saved[_key]) {
        final raw? => decodeChoice(raw),
        null => null,
      });
}

/// 把介面切成 [choice]；null（跟隨系統）時照系統的第一個語言（[appLocaleFor]）。
void applyLanguage(AppLocale? choice) =>
    LocaleSettings.setLocaleSync(choice ?? appLocaleFor(systemLocale()));

/// 系統偏好的第一個語言。
Locale systemLocale() {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  return dispatcher.locales.firstOrNull ?? dispatcher.locale;
}

/// 跟隨系統時用哪個語言：繁體（`Hant`，或台灣、香港、澳門）是 zh-TW，其他
/// 中文（`Hans`、中國、新加坡、沒寫地區）是 zh-CN，英文是 en；三語以外都用
/// zh-TW（brief〈介面〉：zh-TW 為主）。
AppLocale appLocaleFor(Locale system) {
  switch (system.languageCode) {
    case 'zh':
      return switch (system.scriptCode) {
        'Hant' => AppLocale.zhTw,
        'Hans' => AppLocale.zhCn,
        _ =>
          const {'TW', 'HK', 'MO'}.contains(system.countryCode)
              ? AppLocale.zhTw
              : AppLocale.zhCn,
      };
    case 'en':
      return AppLocale.en;
    default:
      return AppLocale.zhTw;
  }
}
