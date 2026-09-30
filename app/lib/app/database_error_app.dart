import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/app_material.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';

/// 資料庫開不起來時的畫面（ADR 0010 §決定 3）：App 不在半開的資料庫上啟動，
/// 只顯示錯誤。重試、匯出診斷等選項隨舊資料匯入（M5）與 log（ADR 0025）再加。
///
/// 讀不到外觀設定，所以語言與主題都跟隨系統。
class DatabaseErrorApp extends ConsumerWidget {
  const DatabaseErrorApp({
    super.key,
    required this.flavor,
    required this.error,
    required this.fontFallback,
  });

  final AppFlavor flavor;

  /// 開啟時拋出的錯誤，原樣顯示供回報問題。
  final Object error;

  /// 平台的 CJK 字型 fallback（`PlatformCapabilities.fontFallback`）。
  final FontFallback fontFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = localeForSystem(ref.watch(systemLocalesProvider));
    final t = appLocaleOf(locale).buildSync();
    return fmpMaterialApp(
      title: flavor.displayName,
      locale: locale,
      themeMode: ThemeMode.system,
      fontFamilyFallback: fontFamilyFallbackOf(fontFallback, locale),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.startup.databaseError,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                SelectableText('$error'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
