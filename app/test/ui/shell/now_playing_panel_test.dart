import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/shell/now_playing_panel.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// 右側「正在播放」面板（design §9.4，M2 PR 19）。

const _resize = 'Drag or press ←/→ to resize';
const _collapse = 'Collapse the now playing panel';
const _hide = 'Hide the now playing panel';
const _show = 'Show the now playing panel';

final _panel = find.byType(NowPlayingPanel);
// 名稱在 Semantics 上（Tooltip 不重複報），所以不能用 find.byTooltip。
final _handle = find.byWidgetPredicate(
  (widget) => widget is Tooltip && widget.message == _resize,
);
final _barTitle = find.descendant(
  of: find.byType(PlayerBar),
  matching: find.text('Song a'),
);

/// 把手裡拿焦點的那個 `Focus`。
Focus _handleFocus(WidgetTester tester) => tester.widget<Focus>(
  find.descendant(of: _handle, matching: find.byType(Focus)).first,
);

double _panelWidth(WidgetTester tester) => tester.getSize(_panel).width;

/// 寫進 `layout_state`（要真的事件迴圈）並讓畫面跟上。
Future<void> _store(
  WidgetTester tester,
  ShellHarness h, {
  bool? expanded,
  double? width,
}) async {
  await tester.runAsync(
    () => h
        .container(tester)
        .read(layoutStateRepositoryProvider)
        .write(panelExpanded: expanded, panelWidth: width),
  );
  await h.loadSettings(tester);
}

Future<LayoutState> _stored(WidgetTester tester, ShellHarness h) async {
  await h.loadSettings(tester);
  return (await tester.runAsync(
    () => h.container(tester).read(layoutStateRepositoryProvider).read(),
  ))!;
}

/// 每次 `layout_state` 被寫入就加一（以資料庫自己的通知數，不看值）。
List<int> _countWrites(WidgetTester tester, ShellHarness h) {
  final database = h.container(tester).read(appDatabaseProvider);
  final writes = <int>[];
  final subscription = database
      .tableUpdates(TableUpdateQuery.onTable(database.layoutStateTable))
      .listen((_) => writes.add(writes.length + 1));
  addTearDown(() => unawaited(subscription.cancel()));
  return writes;
}

void main() {
  group('when it shows', () {
    for (final (width, shown) in [
      (400.0, false),
      (700.0, false),
      (839.0, false),
      (840.0, true),
      (1000.0, true),
      (1800.0, true),
    ]) {
      testWidgets('window $width wide: ${shown ? 'panel' : 'no panel'}', (
        tester,
      ) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: Size(width, 800));
        await h.play(tester, [summary('a')]);
        await h.loadSettings(tester);

        expect(_panel, shown ? findsOneWidget : findsNothing);
        expect(_handle, shown ? findsOneWidget : findsNothing);
        // 播放列的圖示鈕只在播放列第三段（>= 840 寬；導覽那一側佔 116，所以視窗 >= 956）；較窄的一段是「⋯」的勾選項。
        expect(
          find.byTooltip(_hide),
          width >= 956 ? findsOneWidget : findsNothing,
          reason: 'the icon button is the bar\'s top tier only',
        );
      });
    }

    testWidgets('collapsed: neither the panel nor the handle takes space', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 800));
      final before = tester.getSize(find.byType(SearchPage)).width;
      await _store(tester, h, expanded: false);

      expect(_panel, findsNothing);
      expect(_handle, findsNothing);
      expect(
        tester.getSize(find.byType(SearchPage)).width,
        greaterThan(before),
      );
    });

    testWidgets('an empty queue shows the empty state', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 800));

      expect(
        find.descendant(of: _panel, matching: find.text('Nothing is playing')),
        findsOneWidget,
      );
      expect(find.text('Now playing'), findsOneWidget);
    });

    testWidgets('a current song shows its details', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 800));
      await h.play(tester, [summary('a'), summary('b')], index: 1);

      expect(
        find.descendant(of: _panel, matching: find.text('Song b')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _panel, matching: find.text('Nothing is playing')),
        findsNothing,
      );
    });

    testWidgets('pages measure the width left of the panel', (tester) async {
      final h = ShellHarness();
      // 1000 寬：rail 之後是 expanded（884），再扣掉面板（400）與把手之後的內容區是 476、
      // compact，設定頁因此是分組清單（沒有分隔線）；收起面板時是 expanded 的 list-detail。
      await h.pumpShell(tester, size: const Size(1000, 800));
      await tester.tap(find.text('Settings').first);
      await h.loadSettings(tester);

      expect(find.byType(VerticalDivider), findsNothing);
    });
  });

  group('width', () {
    for (final (name, window, stored, expected) in [
      ('the default', const Size(1100, 800), null, 412.0),
      ('the extraLarge default', const Size(1800, 900), null, 480.0),
      ('a stored width inside the range', const Size(1800, 900), 600.0, 600.0),
      (
        'a stored width over 40% of the window',
        const Size(1000, 800),
        900.0,
        400.0,
      ),
      ('a stored width under the minimum', const Size(1800, 900), 100.0, 320.0),
    ]) {
      testWidgets(name, (tester) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: window);
        if (stored != null) await _store(tester, h, width: stored);

        expect(_panelWidth(tester), expected);
      });
    }

    testWidgets('a stored width at 840 goes to the maximum, 336', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(840, 800));
      await _store(tester, h, width: 900);

      expect(_panelWidth(tester), 336);
    });

    testWidgets('the default is clamped to the maximum at 840', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(840, 800));

      expect(_panelWidth(tester), 336);
    });

    testWidgets(
      'resizing the window clamps what is shown, not what is stored',
      (tester) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: const Size(1800, 900));
        await _store(tester, h, width: 600);
        expect(_panelWidth(tester), 600);

        tester.view.physicalSize = const Size(1000, 800);
        await tester.pump();
        expect(_panelWidth(tester), 400);
        expect((await _stored(tester, h)).panelWidth, 600);

        tester.view.physicalSize = const Size(1800, 900);
        await tester.pump();
        expect(_panelWidth(tester), 600);
      },
    );

    test(
      'panelWidthFor: the range is [320, 40% of the window, at most 1600]',
      () {
        double width(double? stored, WindowClass windowClass, double window) =>
            panelWidthFor(
              stored: stored,
              windowClass: windowClass,
              windowWidth: window,
            );

        expect(width(null, WindowClass.large, 1500), 412);
        expect(width(null, WindowClass.extraLarge, 2000), 480);
        expect(width(1000, WindowClass.large, 1500), 600);
        expect(width(10, WindowClass.large, 1500), 320);
        // 視窗 840：上限 336，預設 412 夾成 336；上限低於下限（視窗 700）取下限。
        expect(width(null, WindowClass.expanded, 840), 336);
        expect(width(1000, WindowClass.expanded, 700), 320);
        // 40% 超過 1600 時以 1600 為上限（資料庫的 CHECK）。
        expect(width(2000, WindowClass.extraLarge, 4400), 1600);
      },
    );
  });

  group('dragging', () {
    testWidgets('left widens, right narrows, and only the release writes', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1800, 900));
      await h.loadSettings(tester);
      final writes = _countWrites(tester, h);
      expect(_panelWidth(tester), 480);

      final gesture = await tester.startGesture(tester.getCenter(_handle));
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-70, 0));
      await tester.pump();
      expect(_panelWidth(tester), 580);
      await h.loadSettings(tester);
      expect(writes, isEmpty, reason: 'nothing is written while dragging');
      expect((await _stored(tester, h)).panelWidth, isNull);

      await gesture.up();
      await tester.pump();
      expect(_panelWidth(tester), 580);
      await h.loadSettings(tester);
      expect(writes, hasLength(1));
      expect((await _stored(tester, h)).panelWidth, 580);

      final narrow = await tester.startGesture(tester.getCenter(_handle));
      await narrow.moveBy(const Offset(50, 0));
      await tester.pump();
      expect(_panelWidth(tester), 530);
      await narrow.up();
      await h.loadSettings(tester);
      expect(writes, hasLength(2));
      expect((await _stored(tester, h)).panelWidth, 530);
    });

    testWidgets('the width stays inside the range while dragging', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1800, 900));

      final wide = await tester.startGesture(tester.getCenter(_handle));
      await wide.moveBy(const Offset(-2000, 0));
      await tester.pump();
      expect(_panelWidth(tester), 720, reason: '40% of 1800');
      // 寬度是按下的寬度減去指標的總位移：指標回到起點就回到 480，再往右 100 是 380。
      await wide.moveBy(const Offset(2000, 0));
      await tester.pump();
      expect(_panelWidth(tester), 480);
      await wide.moveBy(const Offset(2000, 0));
      await tester.pump();
      expect(_panelWidth(tester), 320);
      await wide.up();
      await h.loadSettings(tester);
      expect((await _stored(tester, h)).panelWidth, 320);
    });

    testWidgets('past 4000 wide the width stops at 1600, which the database '
        'accepts', (tester) async {
      // 視窗 4400 的 40% 是 1760，但 layout_state 的 CHECK 擋 > 1600：沒有這個上限時
      // 放開會寫入失敗（錯誤歷史多一筆），畫面再跳回記住的寬度。
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(4400, 1200));
      await h.loadSettings(tester);

      final gesture = await tester.startGesture(tester.getCenter(_handle));
      await gesture.moveBy(const Offset(-1400, 0));
      await tester.pump();
      expect(_panelWidth(tester), 1600);
      await gesture.up();
      await h.loadSettings(tester);
      await h.loadSettings(tester);

      expect((await _stored(tester, h)).panelWidth, 1600);
      expect(_panelWidth(tester), 1600);
    });

    testWidgets('the cursor is a left-right resize', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 800));

      final region = tester.widget<MouseRegion>(
        find.descendant(
          of: _handle,
          matching: find.byWidgetPredicate(
            (w) =>
                w is MouseRegion &&
                w.cursor == SystemMouseCursors.resizeLeftRight,
          ),
        ),
      );
      expect(region.cursor, SystemMouseCursors.resizeLeftRight);
    });

    testWidgets(
      'the divider line runs the full height and lights up on focus',
      (tester) async {
        // 線放在 Center 裡、沒給高度時是 0 高：畫面上看不到分隔線，聚焦也看不出來。
        final h = ShellHarness();
        await h.pumpShell(tester, size: const Size(1000, 800));
        final line = find.descendant(
          of: _handle,
          matching: find.byType(ColoredBox),
        );
        expect(tester.getSize(line).height, tester.getSize(_handle).height);
        final idle = tester.widget<ColoredBox>(line).color;

        final focus = _handleFocus(tester).focusNode!..requestFocus();
        await tester.pump();
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        expect(tester.widget<ColoredBox>(line).color, isNot(idle));
      },
    );
  });

  group('keyboard', () {
    testWidgets('left widens by 16, right narrows by 16, each press writes', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1800, 900));
      await h.loadSettings(tester);
      final writes = _countWrites(tester, h);
      _handleFocus(tester).focusNode!.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(_panelWidth(tester), 496);
      await h.loadSettings(tester);
      expect(writes, hasLength(1));
      expect((await _stored(tester, h)).panelWidth, 496);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_panelWidth(tester), 464);
      await h.loadSettings(tester);
      expect(writes, hasLength(3));
      expect((await _stored(tester, h)).panelWidth, 464);
    });

    testWidgets('the keys stop at the range', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 800));
      await _store(tester, h, width: 400);
      _handleFocus(tester).focusNode!.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(_panelWidth(tester), 400, reason: '40% of 1000');

      await _store(tester, h, width: 330);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_panelWidth(tester), 320);
    });

    testWidgets('the handle is in the tab order, after the pages', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 800));
      await h.play(tester, [summary('a')]);
      // F6 兩次到內容區。
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      final handle = _handleFocus(tester).focusNode!;

      var reached = false;
      for (var i = 0; i < 20 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        reached = handle.hasFocus;
      }
      expect(reached, isTrue);
      // 把手之後是面板的收起鈕，仍在「內容」焦點區裡。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final context = FocusManager.instance.primaryFocus!.context!;
      expect(
        context.findAncestorWidgetOfExactType<NowPlayingPanel>(),
        isNotNull,
      );
      expect(FocusScope.of(context).debugLabel, 'Shell content');
    });

    testWidgets('the semantics name the handle and its value', (tester) async {
      final handle = tester.ensureSemantics();
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1800, 900));

      final node = find.semantics.byValue('480');
      expect(node, findsOneWidget);
      final data = node.evaluate().single.getSemanticsData();
      expect(data.increasedValue, '496');
      expect(data.decreasedValue, '464');
      expect(data.label, _resize);
      handle.dispose();
    });
  });

  group('the toggles', () {
    testWidgets('the title bar button collapses and the bar button reopens', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 800));
      await h.play(tester, [summary('a')]);
      final barWidth = tester.getSize(find.byType(PlayerBar)).width;
      final stored = _countWrites(tester, h);

      await tester.tap(find.byTooltip(_collapse));
      await h.loadSettings(tester);
      expect(_panel, findsNothing);
      expect(stored, hasLength(1));
      expect((await _stored(tester, h)).panelExpanded, isFalse);
      expect(find.byTooltip(_show), findsOneWidget);
      expect(tester.getSize(find.byType(PlayerBar)).width, barWidth);

      await tester.tap(find.byTooltip(_show));
      await h.loadSettings(tester);
      expect(_panel, findsOneWidget);
      expect(stored, hasLength(2));
      expect((await _stored(tester, h)).panelExpanded, isTrue);
      expect(find.byTooltip(_hide), findsOneWidget);
      expect(tester.getSize(find.byType(PlayerBar)).width, barWidth);
    });

    testWidgets('the player bar tiers do not change when the panel toggles', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 800));
      await h.play(tester, [summary('a')]);
      // 1000 寬的播放列（884）是第三段：有隨機與循環，沒有「更多」。
      expect(find.byTooltip('Shuffle (Ctrl+S)'), findsOneWidget);
      expect(find.byTooltip('More'), findsNothing);

      await tester.tap(find.byTooltip(_hide));
      await h.loadSettings(tester);

      expect(find.byTooltip('Shuffle (Ctrl+S)'), findsOneWidget);
      expect(find.byTooltip('More'), findsNothing);
    });

    testWidgets('the middle tier has a checkable item in its menu', (
      tester,
    ) async {
      final h = ShellHarness();
      // 視窗 840：rail 之後播放列 724，是第二段。
      await h.pumpShell(tester, size: const Size(840, 800));
      await h.play(tester, [summary('a')]);
      expect(
        find.byTooltip(_hide),
        findsNothing,
        reason: 'no icon button here',
      );

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxMenuButton>(
              find.widgetWithText(CheckboxMenuButton, 'Now playing panel'),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.text('Now playing panel'));
      await h.loadSettings(tester);
      await h.loadSettings(tester);

      expect(_panel, findsNothing);
      expect((await _stored(tester, h)).panelExpanded, isFalse);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxMenuButton>(
              find.widgetWithText(CheckboxMenuButton, 'Now playing panel'),
            )
            .value,
        isFalse,
      );
    });

    testWidgets(
      'a bar narrower than the window has no toggle without a panel',
      (tester) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: const Size(760, 800));
        await h.play(tester, [summary('a')]);

        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();

        expect(find.text('Now playing panel'), findsNothing);
      },
    );

    testWidgets('the player page menu has the item at expanded and up', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 800));
      await h.play(tester, [summary('a')]);
      await tester.tap(_barTitle);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Now playing panel'));
      await h.loadSettings(tester);

      expect((await _stored(tester, h)).panelExpanded, isFalse);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxMenuButton>(
              find.widgetWithText(CheckboxMenuButton, 'Now playing panel'),
            )
            .value,
        isFalse,
      );
    });

    for (final width in [400.0, 700.0]) {
      testWidgets('the player page menu has no item at $width wide', (
        tester,
      ) async {
        final h = ShellHarness();
        await h.pumpShell(tester, size: Size(width, 800));
        await h.play(tester, [summary('a')]);
        await tester.tap(_barTitle);
        await tester.pumpAndSettle();
        expect(find.byType(PlayerPage), findsOneWidget);

        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();

        expect(find.text('Playback speed'), findsOneWidget);
        expect(find.text('Now playing panel'), findsNothing);
      });
    }
  });
}
