import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/theme/appearance.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/data/settings_store.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/common/focus_ring.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/settings/settings_controls.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/settings/settings_sections.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell.dart';

/// 設定頁（`docs/design/settings.html`）：手機的群組列表與桌面、中寬度的
/// 分類欄加窗格，M1 只有外觀與播放；改了立刻生效。保存與還原在
/// `test/app/settings_test.dart`。
void main() {
  const phone = Size(390, 844);
  const tablet = Size(820, 1180);
  const desktop = Size(1280, 800);

  setUp(() => LocaleSettings.setLocaleSync(AppLocale.zhTw));
  tearDown(
    () => LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> start(
    WidgetTester tester,
    Size size, {
    Map<String, String> saved = const {},
    bool reduceMotion = false,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (reduceMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    await tester.pumpWidget(
      buildRoot(overrides: [savedSettingsProvider.overrideWithValue(saved)]),
    );
    await settle(tester);
    await openDestination(tester, Destination.settings);
    await settle(tester);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await settle(tester);
  }

  /// 選單裡的項目（選單疊在頁面上面，同樣的字可能也在列尾）。
  Finder menuItem(String text) => find.text(text).last;

  Brightness brightness(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(SettingsPage))).brightness;

  FmpColors colors(WidgetTester tester) =>
      tester.element(find.byType(SettingsPage)).fmpColors;

  /// 畫面上每一塊玻璃畫成哪一級。
  Set<GlassTier> glassTiers(WidgetTester tester) => {
    for (final element in find.byType(Glass).evaluate())
      if (find
          .descendant(
            of: find.byWidget(element.widget),
            matching: find.byType(LiquidGlassLens),
          )
          .evaluate()
          .isNotEmpty)
        GlassTier.refract
      else if (find
          .descendant(
            of: find.byWidget(element.widget),
            matching: find.byType(LiquidGlassLite),
          )
          .evaluate()
          .isNotEmpty)
        GlassTier.standard
      else
        GlassTier.minimal,
  };

  group('phone', () {
    testWidgets('lists only appearance and playback', (tester) async {
      await start(tester, phone);

      for (final text in ['外觀', '主題', '強調色', '語言', '玻璃效果', '播放', '臨時播放結束後倒退']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      for (final text in ['帳號', '插件', '音質', '歌詞', '儲存空間', '關於']) {
        expect(find.text(text), findsNothing, reason: text);
      }
      // 列尾是目前的值。
      expect(find.text('跟隨系統'), findsNWidgets(2));
      expect(find.text('完整'), findsOneWidget);
      expect(find.text('10 秒'), findsOneWidget);
    });

    testWidgets('the theme menu switches to dark at once', (tester) async {
      await start(tester, phone);
      expect(brightness(tester), Brightness.light);

      await tap(tester, find.text('主題'));
      expect(find.text('淺色'), findsOneWidget);
      await tap(tester, menuItem('深色'));

      expect(brightness(tester), Brightness.dark);
      expect(find.text('深色'), findsOneWidget);
      expect(containerOf(tester).read(themeModeProvider), ThemeMode.dark);
    });

    testWidgets('a swatch switches the accent at once', (tester) async {
      await start(tester, phone);

      await tap(tester, find.bySemanticsLabel('青綠'));

      expect(colors(tester).accent, Accent.teal.tone500);
      expect(find.text('青綠'), findsOneWidget);
    });

    testWidgets('the language menu switches every string at once', (
      tester,
    ) async {
      await start(tester, phone);

      await tap(tester, find.text('語言'));
      await tap(tester, menuItem('English'));

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Settings'), findsWidgets);
    });

    testWidgets('choosing to follow the system goes back to the system '
        'language', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      LocaleSettings.setLocaleSync(AppLocale.en);
      await start(tester, phone, saved: {'appearance.language': 'en'});

      await tap(tester, find.text('Language'));
      await tap(tester, menuItem('System'));

      expect(find.text('外观'), findsOneWidget);
    });

    testWidgets('following the system, the app changes language when the '
        'system does', (tester) async {
      await start(tester, phone);

      tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await settle(tester);

      expect(find.text('外观'), findsOneWidget);
    });

    testWidgets('a chosen language stays when the system changes', (
      tester,
    ) async {
      await start(tester, phone, saved: {'appearance.language': 'zh-TW'});

      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await settle(tester);

      expect(find.text('外觀'), findsOneWidget);
    });

    testWidgets('the glass menu explains each choice and switches every '
        'glass together', (tester) async {
      await start(tester, phone);
      expect(glassTiers(tester), {GlassTier.refract});

      await tap(tester, find.text('玻璃效果'));
      for (final hint in ['折射、模糊與高光', '只有模糊，比較省效能', '實心背景']) {
        expect(find.text(hint), findsOneWidget, reason: hint);
      }
      await tap(tester, menuItem('關閉'));

      expect(glassTiers(tester), {GlassTier.minimal});
      expect(find.text('關閉'), findsOneWidget);
    });

    testWidgets('the rewind menu offers the old choices and sets the '
        'temporary play rewind', (tester) async {
      await start(tester, phone);

      await tap(tester, find.text('臨時播放結束後倒退'));
      for (final option in ['不倒退', '3 秒', '5 秒', '15 秒', '30 秒']) {
        expect(find.text(option), findsOneWidget, reason: option);
      }
      await tap(tester, menuItem('30 秒'));

      expect(
        containerOf(tester).read(temporaryPlayRewindProvider),
        const Duration(seconds: 30),
      );
      expect(find.text('30 秒'), findsOneWidget);
    });

    testWidgets('opens with the saved settings', (tester) async {
      await start(
        tester,
        phone,
        saved: {
          'appearance.theme': 'dark',
          'appearance.accent': 'violet',
          'appearance.glass': 'lite',
          'playback.temporaryPlayRewindSeconds': '5',
        },
      );

      expect(brightness(tester), Brightness.dark);
      expect(colors(tester).accent, Accent.violet.tone300);
      expect(glassTiers(tester), {GlassTier.standard});
      expect(find.text('5 秒'), findsOneWidget);
      expect(find.text('堇紫'), findsOneWidget);
    });
  });

  group('desktop', () {
    testMac('shows the two categories, appearance first', (tester) async {
      await start(tester, desktop);

      expect(find.text('外觀'), findsWidgets);
      expect(find.text('播放'), findsOneWidget);
      expect(find.text('介面語言'), findsOneWidget);
      expect(find.text('跟隨系統（繁體中文）'), findsNothing);
      for (final text in ['帳號', '插件', '歌詞', '匯入歌單', '儲存空間', '資料', '關於']) {
        expect(find.text(text), findsNothing, reason: text);
      }
    });

    testMac('a theme tile applies at once', (tester) async {
      await start(tester, desktop);

      await tap(tester, find.bySemanticsLabel('深色'));

      expect(brightness(tester), Brightness.dark);
    });

    testMac('the glass rows explain each choice and switch every glass '
        'together', (tester) async {
      await start(tester, desktop);

      for (final hint in ['折射、模糊與高光', '只有模糊，比較省效能', '實心背景']) {
        expect(find.text(hint), findsOneWidget, reason: hint);
      }
      await tap(tester, find.text('輕量'));

      expect(glassTiers(tester), {GlassTier.standard});
    });

    testMac('the language popup names the system language', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'GB')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      LocaleSettings.setLocaleSync(AppLocale.en);
      await start(tester, desktop);

      expect(find.text('System (English)'), findsOneWidget);
      await tap(tester, find.text('System (English)'));
      await tap(tester, menuItem('简体中文'));
      expect(find.text('界面语言'), findsOneWidget);
    });

    testMac('the playback stepper walks through the choices and stops at '
        'the ends', (tester) async {
      await start(tester, desktop);
      await tap(tester, find.text('播放'));

      expect(find.text('10 秒'), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('增加'));
      expect(find.text('15 秒'), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('增加'));
      expect(find.text('30 秒'), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('增加'));
      expect(find.text('30 秒'), findsOneWidget);
      expect(
        containerOf(tester).read(temporaryPlayRewindProvider),
        const Duration(seconds: 30),
      );

      for (var i = 0; i < 6; i++) {
        await tap(tester, find.bySemanticsLabel('減少'));
      }
      expect(find.text('不倒退'), findsOneWidget);
    });

    testMac('the chosen category is kept when coming back', (tester) async {
      await start(tester, desktop);
      await tap(tester, find.text('播放'));

      await openDestination(tester, Destination.home);
      await openDestination(tester, Destination.settings);
      await settle(tester);

      expect(find.text('臨時播放結束後倒退'), findsOneWidget);
    });

    testMac('⌘, opens the settings from any page', (tester) async {
      await start(tester, desktop);
      await openDestination(tester, Destination.home);
      expect(find.byType(HomePage), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await settle(tester);

      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('Ctrl+, opens the settings on Windows', (tester) async {
      await start(tester, desktop);
      await openDestination(tester, Destination.home);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);

      expect(find.byType(SettingsPage), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  group('tablet', () {
    testWidgets('uses the split layout with touch-sized controls', (
      tester,
    ) async {
      await start(tester, tablet);

      expect(find.text('介面語言'), findsOneWidget);
      expect(
        tester.getSize(find.byType(SettingsPopupButton)).height,
        greaterThanOrEqualTo(44),
      );

      await tap(tester, find.text('播放'));
      final plus = find.descendant(
        of: find.bySemanticsLabel('增加'),
        matching: find.byType(GestureDetector),
      );
      expect(tester.getSize(plus.first).height, greaterThanOrEqualTo(44));
    });
  });

  group('accessibility', () {
    testMac('the settings controls draw the focus ring when reached by '
        'keyboard', (tester) async {
      await start(tester, desktop);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      final reached = <String>{};
      for (var i = 0; i < 60 && reached.length < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        for (final label in ['播放', '深色', '青綠', '跟隨系統（', '實心背景']) {
          final ring = find.ancestor(
            of: find.textContaining(label),
            matching: find.byType(FocusRing),
          );
          if (ring.evaluate().any((e) => (e.widget as FocusRing).visible)) {
            reached.add(label);
          }
        }
      }
      expect(reached, {'播放', '深色', '青綠', '跟隨系統（', '實心背景'});
    });

    /// 按 Tab 直到 [label] 那一塊畫出焦點外框；[byText] 時以畫面上的字找，
    /// 否則以螢幕閱讀器的名字找。
    Future<bool> tabTo(
      WidgetTester tester,
      String label, {
      bool byText = true,
    }) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final target = byText ? find.text(label) : find.bySemanticsLabel(label);
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final ring = find.ancestor(
          of: target,
          matching: find.byType(FocusRing),
        );
        final inside = find.descendant(
          of: target,
          matching: find.byType(FocusRing),
        );
        if ([
          ...ring.evaluate(),
          ...inside.evaluate(),
        ].any((e) => (e.widget as FocusRing).visible)) {
          return true;
        }
      }
      return false;
    }

    testMac('the stepper buttons draw the focus ring when reached by '
        'keyboard', (tester) async {
      await start(tester, desktop);
      await tap(tester, find.text('播放'));

      expect(await tabTo(tester, '增加', byText: false), isTrue);
    });

    testWidgets('a phone settings row draws the focus ring when reached by '
        'keyboard', (tester) async {
      await start(tester, phone);

      expect(await tabTo(tester, '臨時播放結束後倒退'), isTrue);
    });

    testMac('on a desktop the stepper and the language popup take at least '
        '28 tall clicks', (tester) async {
      await start(tester, desktop);

      expect(
        tester.getSize(find.byType(SettingsPopupButton)).height,
        greaterThanOrEqualTo(28),
      );
      await tap(tester, find.text('播放'));
      final plus = find.descendant(
        of: find.bySemanticsLabel('增加'),
        matching: find.byType(GestureDetector),
      );
      final size = tester.getSize(plus.first);
      expect(size.width, greaterThanOrEqualTo(28));
      expect(size.height, greaterThanOrEqualTo(28));
    });

    testWidgets('on a phone the swatches take 44 square taps', (tester) async {
      await start(tester, phone);

      final swatch = find.descendant(
        of: find.bySemanticsLabel('靛藍'),
        matching: find.byType(GestureDetector),
      );
      final size = tester.getSize(swatch.first);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('with reduced motion a settings menu only fades in', (
      tester,
    ) async {
      await start(tester, phone, reduceMotion: true);

      await tester.tap(find.text('主題'));
      await tester.pump(const Duration(milliseconds: 40));

      final menu = find.ancestor(
        of: find.text('淺色'),
        matching: find.byType(FadeTransition),
      );
      expect(menu, findsWidgets);
      for (final type in [SlideTransition, ScaleTransition]) {
        expect(
          find.ancestor(of: find.text('淺色'), matching: find.byType(type)),
          findsNothing,
          reason: '$type',
        );
      }
    });

    testMac('with reduced motion switching categories only fades', (
      tester,
    ) async {
      await start(tester, desktop, reduceMotion: true);

      await tester.tap(find.text('播放'));
      await tester.pump(const Duration(milliseconds: 5));

      // 窗格本身的過場（新的窗格外面包的那幾層）。
      Finder around(Type type) => find.ancestor(
        of: find.byType(PlaybackPane),
        matching: find.descendant(
          of: find.byKey(const Key('settings-pane')),
          matching: find.byType(type),
        ),
      );
      expect(around(FadeTransition), findsWidgets);
      expect(around(SlideTransition), findsNothing);
      expect(around(ScaleTransition), findsNothing);
    });
  });

  group('motion', () {
    /// [swatch] 色點的選取環現在的縮放與透明度。
    (double, double) ring(WidgetTester tester, String swatch) {
      final ring = find.descendant(
        of: find.bySemanticsLabel(swatch),
        matching: find.byType(SelectionRing),
      );
      final scale = tester.widget<ScaleTransition>(
        find.descendant(of: ring, matching: find.byType(ScaleTransition)),
      );
      final fade = tester.widget<FadeTransition>(
        find.descendant(of: ring, matching: find.byType(FadeTransition)),
      );
      return (scale.scale.value, fade.opacity.value);
    }

    testWidgets('a chosen swatch grows its ring with a spring', (tester) async {
      await start(tester, phone);

      await tester.tap(find.bySemanticsLabel('青綠'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final (midScale, midOpacity) = ring(tester, '青綠');
      expect(midScale, inExclusiveRange(.85, 1.2));
      expect(midOpacity, inExclusiveRange(0, 1));

      await settle(tester);
      expect(ring(tester, '青綠'), (1.0, 1.0));
    });

    testWidgets('with reduced motion a chosen swatch only fades its ring in', (
      tester,
    ) async {
      await start(tester, phone, reduceMotion: true);

      await tester.tap(find.bySemanticsLabel('青綠'));
      await tester.pump();
      // 系統開減少動態效果時 Flutter 把動畫縮成 5% 的時長（280 → 14ms）。
      await tester.pump(const Duration(milliseconds: 5));
      final (scale, opacity) = ring(tester, '青綠');
      expect(scale, 1.0);
      expect(opacity, inExclusiveRange(0, 1));
    });

    testMac('the category pill slides to the chosen category', (tester) async {
      await start(tester, desktop);
      final pill = find.byKey(const Key('settings-category-pill'));
      final from = tester.getTopLeft(pill).dy;

      await tester.tap(find.text('播放'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.getTopLeft(pill).dy;
      await settle(tester);
      final to = tester.getTopLeft(pill).dy;

      expect(to, greaterThan(from));
      expect(mid, inExclusiveRange(from, to + 8));
    });

    testMac('a new stepper value cross-fades with the old one', (tester) async {
      await start(tester, desktop);
      await tap(tester, find.text('播放'));

      await tester.tap(find.bySemanticsLabel('增加'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('10 秒'), findsOneWidget);
      expect(find.text('15 秒'), findsOneWidget);

      await settle(tester);
      expect(find.text('10 秒'), findsNothing);
    });
  });
}

/// 桌面密度（macOS）的測試；跑完由框架還原平台。
void testMac(String description, WidgetTesterCallback body) => testWidgets(
  description,
  body,
  variant: TargetPlatformVariant.only(TargetPlatform.macOS),
);
