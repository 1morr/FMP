import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/plugins/runtime/script_errors.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final navigatorKey = GlobalKey<NavigatorState>();
  late ProviderContainer container;

  /// `MaterialApp` 以 `ToastHost` 包住 Navigator，和 App 一樣；回傳 [Toaster]。
  Future<Toaster> pumpHost(WidgetTester tester) async {
    final toaster = Toaster(
      log: Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
      translations: AppLocale.zhTw.buildSync,
      sourceName: (_) => null,
    );
    addTearDown(toaster.dispose);
    container = ProviderContainer.test(
      overrides: [toasterProvider.overrideWithValue(toaster)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: buildAppTheme(
            Brightness.light,
            fontFamilyFallback: const [],
            textLocale: _hant,
          ),
          builder: (context, navigator) => ToastHost(child: navigator!),
          home: const Scaffold(body: Center(child: Text('home'))),
        ),
      ),
    );
    return toaster;
  }

  /// 顯示中的提示的那一塊 Material（不含 margin）。
  Finder snackMaterial() => find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(Material),
  );

  testWidgets('a new toast replaces the current one at once', (tester) async {
    final toaster = await pumpHost(tester);

    toaster.success('第一則');
    await tester.pumpAndSettle();
    toaster.info('第二則');
    await tester.pump();

    expect(find.text('第一則'), findsNothing);
    expect(find.text('第二則'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  group('durations', () {
    for (final (kind, seconds) in [
      (ToastKind.success, 4),
      (ToastKind.info, 4),
      (ToastKind.warning, 6),
      (ToastKind.error, 6),
    ]) {
      testWidgets('${kind.name} stays $seconds seconds', (tester) async {
        final toaster = await pumpHost(tester);
        switch (kind) {
          case ToastKind.success:
            toaster.success('訊息');
          case ToastKind.info:
            toaster.info('訊息');
          case ToastKind.warning:
            toaster.warning('訊息');
          case ToastKind.error:
            toaster.error(NotFound(), operation: 'Open failed', tag: 'test');
        }
        await tester.pumpAndSettle();

        await tester.pump(
          Duration(seconds: seconds) - const Duration(milliseconds: 100),
        );
        expect(find.byType(SnackBar), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      });
    }

    testWidgets('a toast with an action still goes away', (tester) async {
      final toaster = await pumpHost(tester);

      toaster.info(
        '已刪除',
        action: ToastAction(label: '復原', onPressed: () {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('復原'), findsOneWidget);
      await tester.pump(ToastKind.info.duration);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('with accessible navigation it stays until closed', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final toaster = await pumpHost(tester);

      toaster.success('已加入');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.text('已加入'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('above every route (ADR 0023 §決定 3)', () {
    Future<void> expectOnTop(WidgetTester tester, Toaster toaster) async {
      toaster.warning('在最上層');
      await tester.pumpAndSettle();
      // hitTestable：點在文字中央的是提示本身，沒有被路由或遮罩蓋住。
      expect(find.text('在最上層').hitTestable(), findsOneWidget);
    }

    testWidgets('a full-screen route', (tester) async {
      final toaster = await pumpHost(tester);
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const Scaffold(body: Center(child: Text('全螢幕'))),
        ),
      );
      await tester.pumpAndSettle();

      await expectOnTop(tester, toaster);
      expect(find.text('全螢幕'), findsOneWidget);
    });

    testWidgets('a dialog', (tester) async {
      final toaster = await pumpHost(tester);
      showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('對話框')),
      );
      await tester.pumpAndSettle();

      await expectOnTop(tester, toaster);
      expect(find.text('對話框'), findsOneWidget);
    });

    testWidgets('a bottom sheet', (tester) async {
      final toaster = await pumpHost(tester);
      showModalBottomSheet<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const SizedBox(height: 600, child: Text('面板')),
      );
      await tester.pumpAndSettle();

      await expectOnTop(tester, toaster);
    });
  });

  group('position', () {
    testWidgets('sits above the height the shell publishes', (tester) async {
      final toaster = await pumpHost(tester);
      const spacing = AppSpacing();

      toaster.info('底部');
      await tester.pumpAndSettle();
      expect(tester.getRect(snackMaterial()).bottom, 600 - spacing.x4);

      container.read(toastBottomInsetProvider.notifier).set(80);
      toaster.info('外殼之上');
      await tester.pumpAndSettle();
      expect(tester.getRect(snackMaterial()).bottom, 600 - 80 - spacing.x4);
    });

    testWidgets('the published height already includes the safe area', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetPadding);
      final toaster = await pumpHost(tester);
      container.read(toastBottomInsetProvider.notifier).set(80);

      toaster.info('外殼之上');
      await tester.pumpAndSettle();

      expect(
        tester.getRect(snackMaterial()).bottom,
        600 - 80 - const AppSpacing().x4,
      );
    });

    // 鍵盤比外殼高時，提示在鍵盤上面；鍵盤蓋住了安全區，所以位移是鍵盤高度
    // 減掉 viewPadding（Scaffold 已經墊過的安全區），不是再加上去。
    for (final (name, shell) in [
      ('no shell', 0.0),
      ('a shell under it', 80.0),
    ]) {
      testWidgets('sits above the keyboard with $name', (tester) async {
        // FakeViewPadding 是物理像素；比例 1 讓數字就是 dp。
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(bottom: 24);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.reset);
        final toaster = await pumpHost(tester);
        container.read(toastBottomInsetProvider.notifier).set(shell);

        toaster.info('鍵盤之上');
        await tester.pumpAndSettle();

        expect(
          tester.getRect(snackMaterial()).bottom,
          600 - 300 - const AppSpacing().x4,
        );
      });
    }

    testWidgets('is at most 560 wide and centred on a wide window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final toaster = await pumpHost(tester);

      toaster.info('桌面');
      await tester.pumpAndSettle();

      final rect = tester.getRect(snackMaterial());
      expect(rect.width, 560);
      expect(rect.center.dx, 700);
    });

    testWidgets('keeps a margin on a narrow window', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final toaster = await pumpHost(tester);

      toaster.info('手機');
      await tester.pumpAndSettle();

      expect(
        tester.getRect(snackMaterial()).width,
        400 - 2 * const AppSpacing().x4,
      );
    });
  });

  testWidgets('each kind has its color', (tester) async {
    final toaster = await pumpHost(tester);
    final theme = buildAppTheme(
      Brightness.light,
      fontFamilyFallback: const [],
      textLocale: _hant,
    );
    final tokens = theme.extension<AppTokens>()!;
    Color? background() =>
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor;

    toaster.success('成功');
    await tester.pumpAndSettle();
    expect(background(), tokens.success.container);
    toaster.info('資訊');
    await tester.pumpAndSettle();
    expect(background(), theme.colorScheme.inverseSurface);
    toaster.warning('警告');
    await tester.pumpAndSettle();
    expect(background(), tokens.warning.container);
    toaster.error(NotFound(), operation: 'Open failed', tag: 'test');
    await tester.pumpAndSettle();
    expect(background(), theme.colorScheme.errorContainer);
  });

  testWidgets("a plugin's own message never reaches the screen", (
    tester,
  ) async {
    final toaster = await pumpHost(tester);

    toaster.error(
      structuredScriptError(
        pluginId: 'fmp-test',
        fmpError: 'RateLimited',
        message: 'FAKE_SERVER_TEXT_123',
      ),
      operation: 'Search failed',
      tag: 'search',
    );
    await tester.pumpAndSettle();

    expect(find.text('fmp-test 請求太頻繁，請稍後再試'), findsOneWidget);
    expect(find.textContaining('FAKE_SERVER_TEXT_123'), findsNothing);
  });

  testWidgets('nothing is shown while the app is in the background', (
    tester,
  ) async {
    final toaster = await pumpHost(tester);
    final binding = tester.binding;
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    addTearDown(
      () => binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );

    toaster.error(NetworkError(), operation: 'Sync failed', tag: 'test');
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    // 桌面視窗失去焦點（inactive）仍在畫面上，照常顯示。
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    toaster.info('失去焦點');
    await tester.pumpAndSettle();
    expect(find.text('失去焦點'), findsOneWidget);
  });
}

const _hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
