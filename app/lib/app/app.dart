import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/ui/placeholder/placeholder_page.dart';

/// Riverpod 3 預設會自動重試失敗的 provider（10 次、約 38 秒），連
/// `UnmountedRefException` 也會重試（brief 事實 K5），所以全域關掉。
Duration? noRetry(int retryCount, Object error) => null;

/// App 的根：`main` 直接 `runApp` 它，測試也從這裡起。
Widget buildRoot() {
  return ProviderScope(
    retry: noRetry,
    child: TranslationProvider(child: const FmpApp()),
  );
}

class FmpApp extends StatelessWidget {
  const FmpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => context.t.app.name,
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const PlaceholderPage(),
    );
  }
}
