import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/app_material.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';

/// 平台沒有資料目錄實作時的畫面（Linux、macOS、iOS 驗證前，ADR 0009
/// §決定 4）。不啟動資料層，只告訴使用者這個平台還不能用；語言與主題跟隨
/// 系統，也沒有字型 fallback（未驗證平台的能力宣告是「沒有」）。
class UnsupportedPlatformApp extends ConsumerWidget {
  const UnsupportedPlatformApp({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = localeForSystem(ref.watch(systemLocalesProvider));
    return fmpMaterialApp(
      title: flavor.displayName,
      locale: locale,
      themeMode: ThemeMode.system,
      fontFamilyFallback: const [],
      home: Scaffold(
        body: Center(
          child: Text(
            appLocaleOf(locale).buildSync().startup.unsupportedPlatform,
          ),
        ),
      ),
    );
  }
}
