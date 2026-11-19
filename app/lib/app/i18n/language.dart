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
  AppLocale? decode(String raw) => _decode(raw);

  static AppLocale? _decode(String raw) =>
      AppLocale.values.where((l) => l.languageTag == raw).firstOrNull;

  @override
  String encode(AppLocale? value) => value?.languageTag ?? _system;

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
        final raw? => _decode(raw),
        null => null,
      });
}

/// 把介面切成 [choice]；null（跟隨系統）時照系統的第一個語言（[appLocaleFor]）。
void applyLanguage(AppLocale? choice) => LocaleSettings.setLocaleSync(
  choice ?? appLocaleFor(WidgetsBinding.instance.platformDispatcher.locale),
);

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
