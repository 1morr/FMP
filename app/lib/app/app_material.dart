import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/appearance.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_theme.dart';

/// App 根元件共用的 `MaterialApp`（ADR 0024 §決定 1、2、7）：淺色與深色主題、
/// 介面語言（帶書寫系統的 locale，見 `flutterLocaleOf`）、Material 的內建字串、
/// 漢字的字形（`textLocaleOf`）。
///
/// `localizationsDelegates` 用 `material_ui` 的 `GlobalMaterialLocalizations`，
/// 不是 `flutter_localizations` 的：後者提供的是凍結的
/// `package:flutter/material.dart` 的型別（`material_ui` 的 README）。
MaterialApp fmpMaterialApp({
  required String title,
  required LocaleSetting locale,
  required ThemeMode themeMode,
  required List<String> fontFamilyFallback,
  required Widget home,
  TransitionBuilder? builder,
}) => MaterialApp(
  title: title,
  theme: buildAppTheme(
    Brightness.light,
    fontFamilyFallback: fontFamilyFallback,
    textLocale: textLocaleOf(locale),
  ),
  darkTheme: buildAppTheme(
    Brightness.dark,
    fontFamilyFallback: fontFamilyFallback,
    textLocale: textLocaleOf(locale),
  ),
  themeMode: themeMode,
  locale: flutterLocaleOf(locale),
  supportedLocales: supportedFlutterLocales,
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: builder,
  home: home,
);
