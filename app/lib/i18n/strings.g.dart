/// Generated file. Do not edit.
///
/// Source: lib/i18n
/// To regenerate, run: `dart run slang`
///
/// Locales: 3
/// Strings: 390 (130 per locale)

// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'package:slang/slang.dart';
export 'package:slang/slang.dart';

import 'strings_en.g.dart' as l_en;
import 'strings_zh_CN.g.dart' as l_zh_CN;
part 'strings_zh_TW.g.dart';

/// Supported locales.
///
/// Usage:
/// - LocaleSettings.setLocale(AppLocale.zhTw) // set locale
/// - Locale locale = AppLocale.zhTw.flutterLocale // get flutter locale from enum
/// - if (LocaleSettings.currentLocale == AppLocale.zhTw) // locale check
enum AppLocale with BaseAppLocale<AppLocale, Translations> {
  zhTw(languageCode: 'zh', countryCode: 'TW'),
  en(languageCode: 'en'),
  zhCn(languageCode: 'zh', countryCode: 'CN');

  const AppLocale({
    required this.languageCode,
    this.scriptCode, // ignore: unused_element, unused_element_parameter
    this.countryCode, // ignore: unused_element, unused_element_parameter
  });

  @override
  final String languageCode;
  @override
  final String? scriptCode;
  @override
  final String? countryCode;

  @override
  Future<Translations> build({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
  }) async {
    return buildSync(
      overrides: overrides,
      cardinalResolver: cardinalResolver,
      ordinalResolver: ordinalResolver,
    );
  }

  @override
  Translations buildSync({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
  }) {
    switch (this) {
      case AppLocale.zhTw:
        return TranslationsZhTw(
          overrides: overrides,
          cardinalResolver: cardinalResolver,
          ordinalResolver: ordinalResolver,
        );
      case AppLocale.en:
        return l_en.TranslationsEn(
          overrides: overrides,
          cardinalResolver: cardinalResolver,
          ordinalResolver: ordinalResolver,
        );
      case AppLocale.zhCn:
        return l_zh_CN.TranslationsZhCn(
          overrides: overrides,
          cardinalResolver: cardinalResolver,
          ordinalResolver: ordinalResolver,
        );
    }
  }
}

/// Provides utility functions without any side effects.
class AppLocaleUtils extends BaseAppLocaleUtils<AppLocale, Translations> {
  AppLocaleUtils._()
    : super(baseLocale: AppLocale.zhTw, locales: AppLocale.values);

  static final instance = AppLocaleUtils._();

  // static aliases (checkout base methods for documentation)
  static AppLocale parse(String rawLocale) => instance.parse(rawLocale);
  static AppLocale parseLocaleParts({
    required String languageCode,
    String? scriptCode,
    String? countryCode,
  }) => instance.parseLocaleParts(
    languageCode: languageCode,
    scriptCode: scriptCode,
    countryCode: countryCode,
  );
  static List<String> get supportedLocalesRaw => instance.supportedLocalesRaw;
}
