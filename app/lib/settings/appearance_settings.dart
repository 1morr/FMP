import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/platform/platform_capabilities.dart';

/// 外觀設定套用預設之後的值（ADR 0011 §決定 7）。
@immutable
final class Appearance {
  const Appearance({
    required this.themeMode,
    required this.locale,
    required this.fontFamily,
    required this.stored,
  });

  final ThemeModeSetting themeMode;
  final LocaleSetting locale;

  /// 生效的字型；`null`＝系統預設。
  final String? fontFamily;

  /// 使用者設定過的值；欄位為 `null` 表示沒設定過、目前用的是預設（設定頁
  /// 顯示為「跟隨系統」）。
  final AppearanceSettings stored;

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.themeMode == themeMode &&
      other.locale == locale &&
      other.fontFamily == fontFamily &&
      other.stored == stored;

  @override
  int get hashCode => Object.hash(themeMode, locale, fontFamily, stored);

  @override
  String toString() =>
      'Appearance(themeMode: $themeMode, locale: $locale, '
      'fontFamily: $fontFamily, stored: $stored)';
}

/// 在讀取時套用預設：沒設定過的欄位用 [defaultThemeMode]／[defaultLocale]，字型是系統預設
/// （`null`）；存的字型不在 [fontChoices]（目前平台的清單）裡也當作系統預設。主題色不在這裡
/// 套預設：主題要分「沒選過」（純 `fromSeed`）與「選過」（照舊版覆寫主色），直接讀
/// `stored.seedColor`。
///
/// 預設值只在這裡出現、不寫進資料庫，所以改預設不需要 migration，也不會動到
/// 使用者設定過的值。
Appearance resolveAppearance(
  AppearanceSettings stored, {
  required ThemeModeSetting defaultThemeMode,
  required LocaleSetting defaultLocale,
  required List<String> fontChoices,
}) => Appearance(
  themeMode: stored.themeMode ?? defaultThemeMode,
  locale: stored.locale ?? defaultLocale,
  // 存的字型不在目前平台的清單（例如還原別的平台的備份）就當沒設定過。
  fontFamily: fontChoices.contains(stored.fontFamily)
      ? stored.fontFamily
      : null,
  stored: stored,
);

/// 系統的語言偏好清單對到 App 支援的語言：依序取第一個支援的，都不支援才用
/// base locale 繁中（ADR 0024 §決定 7）。`['fr', 'en']` 是 en，不是繁中。
LocaleSetting localeForSystem(List<Locale> preferred) {
  for (final locale in preferred) {
    if (supportedLocaleFor(locale) case final supported?) return supported;
  }
  return LocaleSetting.zhTw;
}

/// 一個系統語言對到 App 支援的語言；不支援時為 `null`。
///
/// 中文先看書寫系統（`zh-Hant`、`zh-Hans`），沒有再看地區：港澳台為繁中，
/// 中國、新加坡、馬來西亞為簡中；兩者都沒有的 `zh` 仍是中文，用 base
/// locale 繁中。
LocaleSetting? supportedLocaleFor(Locale system) => switch (system) {
  Locale(languageCode: 'en') => LocaleSetting.en,
  Locale(languageCode: 'zh', scriptCode: 'Hant') => LocaleSetting.zhTw,
  Locale(languageCode: 'zh', scriptCode: 'Hans') => LocaleSetting.zhCn,
  Locale(languageCode: 'zh', countryCode: 'TW' || 'HK' || 'MO') =>
    LocaleSetting.zhTw,
  Locale(languageCode: 'zh', countryCode: 'CN' || 'SG' || 'MY') =>
    LocaleSetting.zhCn,
  Locale(languageCode: 'zh') => LocaleSetting.zhTw,
  _ => null,
};

/// 系統的語言偏好清單（由最偏好起）；系統語言在執行中改變時跟著更新。
final systemLocalesProvider =
    NotifierProvider<SystemLocalesNotifier, List<Locale>>(
      SystemLocalesNotifier.new,
    );

final class SystemLocalesNotifier extends Notifier<List<Locale>>
    with WidgetsBindingObserver {
  @override
  List<Locale> build() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    return binding.platformDispatcher.locales;
  }

  /// 引擎傳來的清單可能是 `null`，改讀 dispatcher 目前的值。
  @override
  void didChangeLocales(List<Locale>? locales) {
    state = WidgetsBinding.instance.platformDispatcher.locales;
  }
}

/// 外觀設定：監看 `appearance_settings` 那一列，對外是套用預設後的
/// [Appearance]。
final appearanceProvider =
    StreamNotifierProvider<AppearanceNotifier, Appearance>(
      AppearanceNotifier.new,
    );

final class AppearanceNotifier extends StreamNotifier<Appearance> {
  @override
  Stream<Appearance> build() {
    final defaultLocale = localeForSystem(ref.watch(systemLocalesProvider));
    final fontChoices = ref.watch(platformCapabilitiesProvider).fontChoices;
    return ref
        .watch(appearanceSettingsRepositoryProvider)
        .watch()
        .map(
          (stored) => resolveAppearance(
            stored,
            defaultThemeMode: ThemeModeSetting.system,
            defaultLocale: defaultLocale,
            fontChoices: fontChoices,
          ),
        );
  }

  /// 只寫主題模式這個欄位；`null` 清回沒設定過（跟隨預設，也就是系統）。
  Future<void> setThemeMode(ThemeModeSetting? themeMode) {
    final repository = ref.read(appearanceSettingsRepositoryProvider);
    return themeMode == null
        ? repository.clear(themeMode: true)
        : repository.write(themeMode: themeMode);
  }

  /// 只寫語言這個欄位；`null` 清回沒設定過（跟隨系統的語言偏好）。
  Future<void> setLocale(LocaleSetting? locale) {
    final repository = ref.read(appearanceSettingsRepositoryProvider);
    return locale == null
        ? repository.clear(locale: true)
        : repository.write(locale: locale);
  }

  /// 只寫主題色這個欄位；`null` 清回沒設定過（預設的紫）。
  Future<void> setSeedColor(Color? color) {
    final repository = ref.read(appearanceSettingsRepositoryProvider);
    return color == null
        ? repository.clear(seedColor: true)
        : repository.write(seedColor: color);
  }

  /// 只寫字型這個欄位；`null` 清回沒設定過（系統預設）。
  Future<void> setFontFamily(String? family) {
    final repository = ref.read(appearanceSettingsRepositoryProvider);
    return family == null
        ? repository.clear(fontFamily: true)
        : repository.write(fontFamily: family);
  }
}
