import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/widgets/app_bars/custom_title_bar.dart';

/// Windows 自訂標題列的三個視窗按鈕。
///
/// 標題列由 app 外層在 `MaterialApp.builder` 裡掛上，位置在 Navigator 的
/// Overlay 之上；Tooltip 需要 Overlay，所以那裡只能不掛 Tooltip。讀屏看的是
/// 按鈕自己的語意標籤，不靠 Tooltip。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // `initState` 會問視窗是否最大化；測試裡沒有 window_manager 的原生端。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          return call.method == 'isMaximized' ? false : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  /// 沒有 MaterialApp、也就沒有 Navigator 與 Overlay 的最小外殼。
  Widget bare() {
    LocaleSettings.setLocale(AppLocale.en);
    return TranslationProvider(
      child: const ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [CustomTitleBar()]),
        ),
      ),
    );
  }

  Widget app({required bool aboveNavigator}) {
    LocaleSettings.setLocale(AppLocale.en);
    return TranslationProvider(
      child: ProviderScope(
        child: aboveNavigator
            ? MaterialApp(
                builder: (context, child) => Column(
                  children: [
                    const CustomTitleBar(),
                    Expanded(child: child!),
                  ],
                ),
                home: const SizedBox.shrink(),
              )
            : const MaterialApp(home: Scaffold(body: CustomTitleBar())),
      ),
    );
  }

  testWidgets('above the Navigator it builds without a Tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(app(aboveNavigator: true));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomTitleBar), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('inside the Navigator each control gets a Tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(app(aboveNavigator: false));
    await tester.pump();

    expect(find.byType(Tooltip), findsNWidgets(3));
  });

  testWidgets('each window control is announced by its own label', (
    tester,
  ) async {
    // 只量元件自己的標籤。掛在 `MaterialApp.builder` 裡還能不能被讀屏看到，
    // 取決於 app 外層有沒有把路由隔成獨立的語意容器，由
    // `test/app_content_wrapper_test.dart` 量。
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(bare());
    await tester.pump();

    for (final label in [
      t.general.minimize,
      t.general.maximize,
      t.general.close,
    ]) {
      final control = find.bySemanticsLabel(label);
      expect(control, findsOneWidget, reason: label);
      expect(
        tester.getSemantics(control).flagsCollection.isButton,
        isTrue,
        reason: label,
      );
    }
    semantics.dispose();
  });
}
