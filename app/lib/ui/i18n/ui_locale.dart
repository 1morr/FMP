import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/domain/appearance.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/settings/appearance_settings.dart';

// 介面語言的各種表示（Flutter、slang、字型）全部從 LocaleSetting 對出來，
// 只在這個檔案對（ADR 0024 §決定 7）。

/// 給 `MaterialApp.locale` 的 Flutter locale：中文一律帶書寫系統。
///
/// 文字的 locale 決定 CJK 字形（Android 依它在系統的 Noto CJK 裡挑繁或簡），
/// Material 的內建字串也依書寫系統選 `zh_Hant_TW`／`zh_Hans`（`material_ui` 的
/// `getMaterialTranslation`）。slang 的 locale 是 `zh-TW`／`zh-CN`（ADR 的
/// `base_locale: zh-TW`），兩者在這裡對應。
Locale flutterLocaleOf(LocaleSetting locale) => switch (locale) {
  LocaleSetting.zhTw => const Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hant',
    countryCode: 'TW',
  ),
  LocaleSetting.zhCn => const Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hans',
    countryCode: 'CN',
  ),
  LocaleSetting.en => const Locale('en'),
};

/// 主題文字樣式的 locale（`buildAppTheme` 的 `textLocale`）：決定漢字的繁簡
/// 字形。中文介面就是 [flutterLocaleOf]；英文介面照 ADR 0024 §決定 2 用繁中，
/// 英文字不受影響。
Locale textLocaleOf(LocaleSetting locale) => flutterLocaleOf(switch (locale) {
  LocaleSetting.en => LocaleSetting.zhTw,
  LocaleSetting.zhTw || LocaleSetting.zhCn => locale,
});

/// `MaterialApp.supportedLocales`：三種語言的 [flutterLocaleOf]。`locale` 一律
/// 明確給定，所以系統語言對到哪一種由 `localeForSystem` 決定，不經 Flutter 的
/// locale 解析。
final supportedFlutterLocales = [
  for (final locale in LocaleSetting.values) flutterLocaleOf(locale),
];

/// slang 的語言。
AppLocale appLocaleOf(LocaleSetting locale) => switch (locale) {
  LocaleSetting.zhTw => AppLocale.zhTw,
  LocaleSetting.zhCn => AppLocale.zhCn,
  LocaleSetting.en => AppLocale.en,
};

/// 字型 fallback 的語言（平台層的 `FontFallback.familiesFor`）。
FontLanguage fontLanguageOf(LocaleSetting locale) => switch (locale) {
  LocaleSetting.zhTw => FontLanguage.zhTw,
  LocaleSetting.zhCn => FontLanguage.zhCn,
  LocaleSetting.en => FontLanguage.en,
};

/// 語言選單上的名稱：每個語言用它自己的寫法，不隨介面語言翻譯（Android、
/// iOS 語言設定的慣例），所以不放翻譯檔。
String localeEndonym(LocaleSetting locale) => switch (locale) {
  LocaleSetting.zhTw => '繁體中文',
  LocaleSetting.zhCn => '简体中文',
  LocaleSetting.en => 'English',
};

/// 目前的介面語言：外觀設定的生效值；設定還沒讀出來時先跟隨系統，不留空白的
/// 第一幀。
final uiLocaleProvider = Provider<LocaleSetting>(
  (ref) =>
      ref.watch(appearanceProvider.select((value) => value.value?.locale)) ??
      localeForSystem(ref.watch(systemLocalesProvider)),
);

/// 目前介面語言的翻譯。沒有 slang 的全域 `t`：widget 以
/// `ref.watch(translationsProvider)` 取，`Toaster` 以 `ref.read` 取。
final translationsProvider = Provider<Translations>(
  (ref) => appLocaleOf(ref.watch(uiLocaleProvider)).buildSync(),
);

/// [locale] 的 CJK 字型 fallback（ADR 0024 §決定 2）。
List<String> fontFamilyFallbackOf(FontFallback fonts, LocaleSetting locale) =>
    fonts.familiesFor(fontLanguageOf(locale));

/// 目前介面語言的 CJK 字型 fallback。
///
/// 在 [uiLocaleProvider] 的 listener 裡不要 `ref.read` 它：listener 可能比它先
/// 收到通知，讀到的是上一個語言的清單；改以 listener 拿到的語言呼叫
/// [fontFamilyFallbackOf]。
final fontFamilyFallbackProvider = Provider<List<String>>(
  (ref) => fontFamilyFallbackOf(
    ref.watch(platformCapabilitiesProvider).fontFallback,
    ref.watch(uiLocaleProvider),
  ),
);
