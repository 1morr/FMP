import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:fmp/app/i18n/plural_rules.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/platform/traffic_lights.dart';
import 'package:fmp/playback/media_controls.dart';
import 'package:fmp/app/router.dart';
import 'package:fmp/ui/now_playing/playback_shortcuts.dart';
import 'package:go_router/go_router.dart';

/// Riverpod 3 預設會自動重試失敗的 provider（10 次、約 38 秒），連
/// `UnmountedRefException` 也會重試（brief 事實 K5），所以全域關掉。
Duration? noRetry(int retryCount, Object error) => null;

/// App 的根：`main` 直接 `runApp` 它，測試也從這裡起。[overrides] 放
/// 啟動時才備好的東西，例如資料庫。
Widget buildRoot({List<Override> overrides = const []}) {
  configurePluralRules();
  return ProviderScope(
    retry: noRetry,
    overrides: overrides,
    child: TrafficLights(child: TranslationProvider(child: const FmpApp())),
  );
}

class FmpApp extends ConsumerStatefulWidget {
  const FmpApp({super.key});

  @override
  ConsumerState<FmpApp> createState() => _FmpAppState();
}

class _FmpAppState extends ConsumerState<FmpApp> {
  final GoRouter _router = buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // App 開著就讓系統媒體控制接著播放（沒有媒體控制時是 null）。
    ref.watch(mediaControlsBindingProvider);
    final density = Density.current;
    return MaterialApp.router(
      routerConfig: _router,
      // 深淺色跟系統；設定頁的主題選項之後再接。
      themeMode: ThemeMode.system,
      theme: buildTheme(brightness: Brightness.light, density: density),
      darkTheme: buildTheme(brightness: Brightness.dark, density: density),
      onGenerateTitle: (context) => context.t.app.name,
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => PlaybackShortcuts(child: child!),
    );
  }
}
