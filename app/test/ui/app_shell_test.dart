import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fmp/ui/shell/caption_buttons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/search/search_field.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/shell/detail_panel.dart';
import 'package:fmp/ui/shell/nav_rail.dart';
import 'package:fmp/ui/shell/phone_dock.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:fmp/ui/shell/side_bar.dart';
import 'package:fmp/app/theme/theme.dart';

import '../support/a11y.dart';
import '../support/motion.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/theme/appearance.dart';
import 'package:fmp/app/theme/accent.dart';

/// App 外殼的路由與導覽（`docs/design/DESIGN.md`〈外殼〉）：打開在首頁，四個
/// 分頁與搜尋都到得了，返回行為照手機的分頁慣例。三種寬度各用一個視窗大小。
void main() {
  const phone = Size(390, 844);
  const tablet = Size(820, 1180);
  const desktop = Size(1280, 800);

  setUp(() => LocaleSettings.setLocaleSync(AppLocale.zhTw));
  tearDown(
    () => LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale),
  );

  Future<void> start(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildRoot());
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<bool> systemBack(WidgetTester tester) async {
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    return handled;
  }

  Finder inDock(String text) =>
      find.descendant(of: find.byType(PhoneDock), matching: find.text(text));

  group('phone', () {
    testWidgets('opens on home with the four tabs and the search orb', (
      tester,
    ) async {
      await start(tester, phone);

      expect(find.byType(HomePage), findsOneWidget);
      for (final label in ['首頁', '音樂庫', '佇列', '設定']) {
        expect(inDock(label), findsOneWidget);
      }
      expect(find.byTooltip('搜尋'), findsOneWidget);
      expect(find.byType(NavRail), findsNothing);
      expect(find.byType(SideBar), findsNothing);
    });

    testWidgets('each tab opens its page', (tester) async {
      await start(tester, phone);

      await tap(tester, inDock('音樂庫'));
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.text('還沒有歌單'), findsOneWidget);
      await tap(tester, inDock('佇列'));
      expect(find.byType(QueuePage), findsOneWidget);
      await tap(tester, inDock('設定'));
      expect(find.byType(SettingsPage), findsOneWidget);
      await tap(tester, inDock('首頁'));
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('search turns the tabs into an orb back to the tab it came '
        'from, and keeps the query', (tester) async {
      await start(tester, phone);
      await tap(tester, inDock('音樂庫'));

      await tap(tester, find.byTooltip('搜尋'));
      expect(find.byType(SearchPage), findsOneWidget);
      expect(inDock('音樂庫'), findsNothing);
      await tester.enterText(find.byType(TextField), '晴天');

      await tap(tester, find.byTooltip('回到音樂庫'));
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tap(tester, find.byTooltip('搜尋'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '晴天',
      );
    });

    testWidgets('with the keyboard up the search field rides on top of it at '
        'full width and the orb steps aside', (tester) async {
      await start(tester, phone);
      await tap(tester, find.byTooltip('搜尋'));
      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final field = tester.getRect(
        find.ancestor(
          of: find.byType(SearchField),
          matching: find.byType(Glass),
        ),
      );
      expect(field.width, phone.width - 28);
      expect(field.bottom, phone.height - 300 - 12);
      expect(find.byTooltip('回到首頁').hitTestable(), findsNothing);

      tester.view.resetViewInsets();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到首頁').hitTestable(), findsOneWidget);
    });

    testWidgets('system back leaves search for the tab underneath, goes '
        'from another tab to home, and leaves the app from home', (
      tester,
    ) async {
      await start(tester, phone);
      await tap(tester, inDock('佇列'));
      await tap(tester, find.byTooltip('搜尋'));

      expect(await systemBack(tester), isTrue);
      expect(find.byType(QueuePage), findsOneWidget);

      expect(await systemBack(tester), isTrue);
      expect(find.byType(HomePage), findsOneWidget);

      expect(await systemBack(tester), isFalse);
    });
  });

  /// 手機 dock 的動態（`docs/design/DESIGN.md`〈狀態變化對照〉）：選取的字色
  /// out 280；減少動態效果時選取膠囊不滑不放大、只淡入淡出，進出搜尋時導覽
  /// 不變形、只淡入淡出。
  group('phone dock motion', () {
    const halfway = Duration(milliseconds: 140);

    Color labelColor(WidgetTester tester, String label) =>
        tester.widget<Text>(inDock(label)).style!.color!;

    Finder indicator(String name) => find.byKey(Key('tab-indicator-$name'));

    /// [finder] 外面所有淡入淡出相乘的透明度。
    double opacityAbove(WidgetTester tester, Finder finder) => tester
        .widgetList<FadeTransition>(
          find.ancestor(of: finder, matching: find.byType(FadeTransition)),
        )
        .fold(1.0, (value, fade) => value * fade.opacity.value);

    testWidgets('the selected tab label turns the accent color over out 280', (
      tester,
    ) async {
      await start(tester, phone);
      // 沒有強調色時淺色的強調色就是墨色，看不出過渡。
      await ProviderScope.containerOf(tester.element(find.byType(PhoneDock)))
          .read(accentProvider.notifier)
          .set(Accent.violet);
      await tester.pumpAndSettle();
      final colors = tester.element(find.byType(PhoneDock)).fmpColors;
      await tester.tap(inDock('佇列'));
      await tester.pump();
      await tester.pump(halfway);
      final mid = labelColor(tester, '佇列');
      expect(mid, isNot(colors.glassInk));
      expect(mid, isNot(colors.accent));
      await tester.pumpAndSettle();
      expect(labelColor(tester, '佇列'), colors.accent);
      expect(labelColor(tester, '首頁'), colors.glassInk);
    });

    testWidgets('with reduced motion the selection pill neither slides nor '
        'grows: the old one fades out where it was, the new one fades in', (
      tester,
    ) async {
      reduceMotion(tester);
      await start(tester, phone);
      final homeRect = tester.getRect(indicator('home'));
      await tester.tap(inDock('佇列'));
      await tester.pump();
      await tester.pump(halfway);
      expect(tester.getRect(indicator('home')), homeRect);
      expect(opacityAbove(tester, indicator('home')), inExclusiveRange(0, 1));
      expect(opacityAbove(tester, indicator('queue')), inExclusiveRange(0, 1));
      // 不放大：膠囊外面沒有縮放（dock 自己的位移不算）。
      expect(
        tester
            .widgetList<Transform>(
              find.ancestor(
                of: indicator('queue'),
                matching: find.byType(Transform),
              ),
            )
            .map((t) => t.transform.getMaxScaleOnAxis()),
        everyElement(1),
      );
      await tester.pumpAndSettle();
      expect(opacityAbove(tester, indicator('home')), 0);
      expect(opacityAbove(tester, indicator('queue')), 1);
    });

    testWidgets('with reduced motion entering search cross-fades the dock '
        'instead of morphing it', (tester) async {
      reduceMotion(tester);
      await start(tester, phone);
      await tester.tap(find.byTooltip('搜尋'));
      await tester.pump();
      await tester.pump(halfway);
      // 舊的導覽膠囊與新的返回圓鈕同時在、各自原本的大小，正在交叉淡出。
      final back = find.byTooltip('回到首頁');
      expect(back, findsOneWidget);
      expect(inDock('首頁'), findsOneWidget);
      expect(tester.getSize(back).width, 62);
      expect(opacityAbove(tester, back), inExclusiveRange(0, 1));
      expect(opacityAbove(tester, inDock('首頁')), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(inDock('首頁'), findsNothing);
    });
  });

  group('medium', () {
    testWidgets('the rail reaches search, the four tabs, and floats the '
        'detail panel', (tester) async {
      await start(tester, tablet);
      expect(find.byType(NavRail), findsOneWidget);
      expect(find.byType(PhoneDock), findsNothing);
      expect(find.byType(DetailPanel), findsNothing);

      Finder inRail(String text) =>
          find.descendant(of: find.byType(NavRail), matching: find.text(text));
      for (final (label, page) in [
        ('音樂庫', LibraryPage),
        ('佇列', QueuePage),
        ('設定', SettingsPage),
        ('首頁', HomePage),
      ]) {
        await tap(tester, inRail(label));
        expect(find.byType(page), findsOneWidget);
      }

      // 細欄的搜尋是項目，欄位在搜尋頁頂端。
      await tap(tester, inRail('搜尋'));
      expect(find.byType(SearchPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SearchPage),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
      expect(await systemBack(tester), isTrue);
      expect(find.byType(HomePage), findsOneWidget);

      await tap(tester, find.byTooltip('顯示詳情面板'));
      expect(find.byType(DetailPanel), findsOneWidget);
      expect(find.text('正在播放'), findsOneWidget);
      await tap(tester, find.byTooltip('收起面板'));
      expect(find.byType(DetailPanel), findsNothing);
    });
  });

  testWidgets('the search shortcut opens search and focuses its field, also '
      'in the medium layout where the field lives on the search page', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final size in [const Size(960, 720), desktop]) {
      await start(tester, size);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(find.byType(SearchPage), findsOneWidget, reason: '$size');
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
        reason: '$size',
      );
    }
    debugDefaultTargetPlatformOverride = null;
  });

  group('wide', () {
    testWidgets('the sidebar reaches the four tabs, its field opens search, '
        'and the detail panel collapses', (tester) async {
      await start(tester, desktop);
      expect(find.byType(SideBar), findsOneWidget);
      expect(find.byType(DetailPanel), findsOneWidget);

      Finder inSide(String text) =>
          find.descendant(of: find.byType(SideBar), matching: find.text(text));
      for (final (label, page) in [
        ('音樂庫', LibraryPage),
        ('佇列', QueuePage),
        ('首頁', HomePage),
      ]) {
        await tap(tester, inSide(label));
        expect(find.byType(page), findsOneWidget);
      }

      await tap(tester, find.byType(TextField));
      expect(find.byType(SearchPage), findsOneWidget);
      await tap(tester, inSide('首頁'));
      expect(find.byType(HomePage), findsOneWidget);

      // 系統返回（例如平板的返回鍵）：非首頁的分頁回首頁。
      await tap(tester, inSide('佇列'));
      expect(await systemBack(tester), isTrue);
      expect(find.byType(HomePage), findsOneWidget);

      await tap(tester, find.byTooltip('收起面板'));
      expect(find.byType(DetailPanel), findsNothing);
      await tap(tester, find.byTooltip('顯示詳情面板'));
      expect(find.byType(DetailPanel), findsOneWidget);
    });

    testWidgets('one mouse click on the sidebar field opens search with the '
        'caret in the field, ready to type', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await start(tester, desktop);

      await tester.tap(find.byType(TextField), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(find.byType(SearchPage), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      // 打字直接進欄位（不必再點一下）。
      tester.testTextInput.enterText('夜');
      await tester.pump();
      expect(field.controller!.text, '夜');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the page title sits 24 clear of the sidebar', (tester) async {
      await start(tester, desktop);
      // 第一個是大標題；頂列另有一個捲動後才淡入的小標題。
      final title = find
          .descendant(of: find.byType(HomePage), matching: find.text('首頁'))
          .first;
      // 側欄外框右緣 256，頁面左內距 24（DESIGN.md〈桌面〉）。
      expect(tester.getTopLeft(title).dx, 256 + 24);
    });

    testWidgets('settings opens with the detail panel collapsed', (
      tester,
    ) async {
      await start(tester, desktop);
      await tap(
        tester,
        find.descendant(of: find.byType(SideBar), matching: find.text('設定')),
      );
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.byType(DetailPanel), findsNothing);

      await tap(
        tester,
        find.descendant(of: find.byType(SideBar), matching: find.text('首頁')),
      );
      expect(find.byType(DetailPanel), findsOneWidget);
    });

    testWidgets('the search field shows the shortcut of the platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await start(tester, desktop);
      expect(find.text('⌘K'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('windows caption buttons', () {
    const channel = MethodChannel('fmp/window');
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'isMaximized' ? false : null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    /// 原生端經頻道送來的訊息。
    Future<void> fromNative(
      WidgetTester tester,
      String method, [
      Object? args,
    ]) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    /// 在 Windows 上跑 [body]；平台覆寫要在測試本體裡還原。
    void windowsTest(String description, WidgetTesterCallback body) =>
        testWidgets(description, (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.windows;
          try {
            await body(tester);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });

    Finder button(String label) => find.descendant(
      of: find.byType(CaptionButtons),
      matching: find.bySemanticsLabel(label),
    );

    windowsTest('sit at the window top right, 46 by 32 each, in both desktop '
        'layouts', (tester) async {
      for (final size in [const Size(960, 720), desktop]) {
        await start(tester, size);
        final w = size.width;
        expect(
          tester.getRect(button('最小化')),
          Rect.fromLTWH(w - 138, 0, 46, 32),
          reason: '$size',
        );
        expect(
          tester.getRect(button('最大化')),
          Rect.fromLTWH(w - 92, 0, 46, 32),
          reason: '$size',
        );
        expect(
          tester.getRect(button('關閉')),
          Rect.fromLTWH(w - 46, 0, 46, 32),
          reason: '$size',
        );
      }
    });

    windowsTest('are not drawn on macOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await start(tester, desktop);
      expect(find.byType(CaptionButtons), findsNothing);
    });

    windowsTest('minimize, maximize and close ask the window', (tester) async {
      await start(tester, desktop);
      for (final (label, method) in [
        ('最小化', 'minimize'),
        ('最大化', 'zoom'),
        ('關閉', 'close'),
      ]) {
        calls.clear();
        await tap(tester, button(label));
        expect(calls.map((c) => c.method), [method], reason: label);
      }
    });

    windowsTest('tell the window where the maximize button is, so Windows '
        'can open Snap Layouts over it', (tester) async {
      await start(tester, desktop);
      final report = calls.lastWhere(
        (c) => c.method == 'setMaximizeButtonRect',
      );
      // 量的是離視窗右上角的距離，視窗改變大小時不用重報。
      expect(report.arguments, {
        'right': 46.0,
        'top': 0.0,
        'width': 46.0,
        'height': 32.0,
      });
    });

    windowsTest('the maximize button turns into restore while the window is '
        'maximized', (tester) async {
      await start(tester, desktop);
      await fromNative(tester, 'maximized', true);
      expect(button('還原'), findsOneWidget);
      expect(button('最大化'), findsNothing);
      await fromNative(tester, 'maximized', false);
      expect(button('最大化'), findsOneWidget);
    });

    windowsTest('the maximize button shows the hover and press that Windows '
        'reports, since Flutter does not see the pointer there', (
      tester,
    ) async {
      await start(tester, desktop);
      CaptionButton maximize() => tester.widget<CaptionButton>(
        find.ancestor(of: button('最大化'), matching: find.byType(CaptionButton)),
      );
      expect((maximize().hovered, maximize().pressed), (false, false));
      await fromNative(tester, 'maximizeButton', {
        'hovered': true,
        'pressed': false,
      });
      expect((maximize().hovered, maximize().pressed), (true, false));
      await fromNative(tester, 'maximizeButton', {
        'hovered': true,
        'pressed': true,
      });
      expect((maximize().hovered, maximize().pressed), (true, true));
      await fromNative(tester, 'maximizeButton', {
        'hovered': false,
        'pressed': false,
      });
      expect((maximize().hovered, maximize().pressed), (false, false));
    });

    windowsTest('the empty top bar drags the window and double-clicking it '
        'maximizes', (tester) async {
      await start(tester, desktop);
      const topBar = Offset(700, 30);
      calls.clear();
      await tester.dragFrom(topBar, const Offset(120, 80));
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['startDrag']);

      calls.clear();
      await tester.tapAt(topBar);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(topBar);
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['zoom']);
    });

    windowsTest('double-clicking a button in the top bar does not maximize', (
      tester,
    ) async {
      await start(tester, desktop);
      calls.clear();
      final hide = tester.getCenter(find.byTooltip('收起面板'));
      await tester.tapAt(hide);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(tester.getCenter(find.byTooltip('顯示詳情面板')));
      await tester.pumpAndSettle();

      expect(calls.map((c) => c.method), isNot(contains('zoom')));
      expect(find.byType(DetailPanel), findsOneWidget);
    });

    windowsTest('wide: the top-bar glass button gives up the 138 the '
        'caption buttons take', (tester) async {
      await start(tester, desktop);
      await tap(tester, find.byTooltip('收起面板'));
      // 頂列 `.wtop` 的右端退到 138，玻璃鈕再內縮 16。
      expect(
        tester.getRect(find.byTooltip('顯示詳情面板')).right,
        desktop.width - 138 - 16,
      );
      expect(find.byType(GlassIconButton), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(CaptionButtons),
          matching: find.byTooltip('顯示詳情面板'),
        ),
        findsNothing,
      );
    });

    const medium = Size(960, 720);
    Finder showDetail() => find.descendant(
      of: find.byType(CaptionButtons),
      matching: find.byTooltip('顯示詳情面板'),
    );

    windowsTest('medium: showing the detail panel is a fourth flat caption '
        'button left of minimize, not a glass button in the top bar', (
      tester,
    ) async {
      await start(tester, medium);
      expect(
        tester.getRect(showDetail()),
        const Rect.fromLTWH(960 - 184, 0, 46, 32),
      );
      expect(
        find.ancestor(
          of: find.byTooltip('顯示詳情面板'),
          matching: find.byType(GlassIconButton),
        ),
        findsNothing,
      );
      // 內容頂列的右端讓出四顆鈕與鈕前的 8。
      final bar = ShellInsets.topBarOf(tester.element(find.byType(HomePage)));
      expect(bar.right, 184 + 8);

      await tap(tester, showDetail());
      expect(find.byType(DetailPanel), findsOneWidget);
      // 面板開著時這顆淡出，點不到。
      expect(showDetail().hitTestable(), findsNothing);
      await tap(tester, find.byTooltip('收起面板'));
      expect(find.byType(DetailPanel), findsNothing);
      expect(showDetail().hitTestable(), findsOneWidget);
    });

    windowsTest('medium: the flat button fills on hover like the other '
        'caption buttons', (tester) async {
      await start(tester, medium);
      Color? fill() {
        final box = tester.widget<AnimatedContainer>(
          find.descendant(
            of: showDetail(),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (box.decoration as BoxDecoration?)?.color;
      }

      expect(fill(), const Color(0x00000000));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: tester.getCenter(showDetail()));
      await tester.pumpAndSettle();
      expect(fill(), tester.element(showDetail()).fmpColors.fill);
    });

    windowsTest('medium: the flat button fills darker while pressed', (
      tester,
    ) async {
      await start(tester, medium);
      Color? fill() {
        final box = tester.widget<AnimatedContainer>(
          find.descendant(
            of: showDetail(),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (box.decoration as BoxDecoration?)?.color;
      }

      final press = await tester.startGesture(tester.getCenter(showDetail()));
      await tester.pumpAndSettle();
      expect(fill(), tester.element(showDetail()).fmpColors.fill2);
      await press.up();
      await tester.pumpAndSettle();
      expect(find.byType(DetailPanel), findsOneWidget);
    });

    windowsTest('medium: with reduced motion the flat button still fades out '
        'when the panel opens', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await start(tester, medium);
      final fade = find.ancestor(
        of: showDetail(),
        matching: find.byType(FadeTransition),
      );
      await tester.tap(showDetail());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(
        tester.widget<FadeTransition>(fade.first).opacity.value,
        inExclusiveRange(0, 1),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FadeTransition>(fade.first).opacity.value, 0);
    });

    windowsTest('medium: pressing or double-clicking the flat button neither '
        'drags nor maximizes the window', (tester) async {
      await start(tester, medium);
      calls.clear();
      await tester.dragFrom(
        tester.getCenter(showDetail()),
        const Offset(120, 80),
      );
      await tester.pumpAndSettle();
      // 拖出點擊範圍就不算按下。
      expect(find.byType(DetailPanel), findsNothing);
      final center = tester.getCenter(showDetail());
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(
        calls.map((c) => c.method),
        isNot(anyOf(contains('startDrag'), contains('zoom'))),
      );
    });

    windowsTest('medium: Tab reaches the flat button', (tester) async {
      final semantics = tester.ensureSemantics();
      await start(tester, medium);
      expect(await tabThrough(tester, 16), contains('顯示詳情面板'));
      semantics.dispose();
    });

    windowsTest('macOS keeps the glass button in the medium top bar', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await start(tester, medium);
      expect(
        find.ancestor(
          of: find.byTooltip('顯示詳情面板'),
          matching: find.byType(GlassIconButton),
        ),
        findsOneWidget,
      );
    });

    windowsTest('the detail panel starts its header below the caption '
        'buttons, with the hide button back at its right end', (tester) async {
      await start(tester, desktop);
      final docked = tester.getRect(find.byTooltip('收起面板'));
      expect(docked.top, greaterThanOrEqualTo(32));
      // 標頭右內距 10，和其他平台一樣。
      expect(docked.right, 1280 - 10);

      await start(tester, medium);
      await tap(tester, showDetail());
      // 浮動面板從視窗鈕下方再 8 開始。
      expect(tester.getRect(find.byType(DetailPanel)).top, 32 + 8);
      expect(tester.getRect(find.byTooltip('收起面板')).right, 960 - 8 - 10);
    });
  });

  group('macos traffic lights', () {
    const channel = MethodChannel('fmp/window');
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    List<Object?> sent() => [
      for (final call in calls)
        if (call.method == 'setTrafficLights') call.arguments,
    ];

    // 燈位照稿（docs/design/assets/fmp.css）：側欄 `.side .lights` 離側欄內容
    // 左緣 8、細欄 `.rail .lights` 離細欄內容左緣 7，上內距都是 14；框是側欄
    // 與細欄的內容寬（側欄 8＋內距 8 到 256−8、細欄 8＋內距 6 到 80−6）。
    for (final (size, spot) in [
      (desktop, {'x': 24.0, 'y': 22.0, 'minX': 16.0, 'maxX': 248.0}),
      (
        const Size(960, 720),
        {'x': 21.0, 'y': 22.0, 'minX': 14.0, 'maxX': 74.0},
      ),
    ]) {
      testWidgets('tells macOS where the lights go in the ${size.width} wide '
          'layout', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await start(tester, size);
        expect(sent().last, spot);
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('moves the lights when the layout changes width', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await start(tester, desktop);
      tester.view.physicalSize = const Size(960, 720);
      await tester.pumpAndSettle();
      expect(sent().last, {'x': 21.0, 'y': 22.0, 'minX': 14.0, 'maxX': 74.0});
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('other platforms have no traffic lights to place', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await start(tester, desktop);
      expect(sent(), isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
