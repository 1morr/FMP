import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/player/queue_view.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// Mix 的介面（M3 PR 19，ADR 0031 §決定 8–9）：曲目選單的「開始 Mix」只在插件宣告 `mix` 時
// 出現、Mix 中停用的項目附說明、隨機鈕停用、佇列分頁顯示 Mix 的標題。從外殼開始，和
// 使用者一樣。

const _shuffleTooltip = 'Shuffle (Ctrl+S)';
const _shuffleLocked = 'Shuffle is unavailable in a Mix';

MixBatch _batch(Iterable<String> ids, {String title = 'Late night mix'}) =>
    MixBatch(
      mixId: 'm1',
      title: title,
      tracks: [for (final id in ids) summary(id)],
      cursor: 'c2',
    );

ShellHarness _harness({bool mix = true}) {
  final h = ShellHarness(mix: mix, registryOfSources: true);
  h.plugin.onMix = (query) => _batch(['m1', 'm2', 'm3']);
  return h;
}

Future<void> _search(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'song');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  await tester.pump();
}

Finder _moreOf(String title) => find.descendant(
  of: find.widgetWithText(ListTile, title),
  matching: find.byTooltip('More options'),
);

Future<void> _openMenu(WidgetTester tester, String title) async {
  await tester.tap(_moreOf(title));
  await tester.pumpAndSettle();
}

Finder _item(String label) => find.widgetWithText(MenuItemButton, label);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<MenuItemButton>(_item(label)).onPressed != null;

Future<ShellHarness> _inMix(
  WidgetTester tester, {
  Size size = const Size(1000, 800),
}) async {
  final h = _harness();
  await h.pumpShell(tester, size: size);
  unawaited(h.controller.startMix(summary('seed').toTrackInfo()));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  expect(h.controller.queue.mode, QueueMode.mix);
  return h;
}

void main() {
  group('the Start Mix item', () {
    testWidgets('is in the menu of a result when the source has mix', (
      tester,
    ) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _search(tester);

      await _openMenu(tester, 'Song a');

      expect(_item('Start Mix'), findsOneWidget);
      expect(_enabled(tester, 'Start Mix'), isTrue);
      expect(h.controller.queue.mode, QueueMode.queue);
    });

    testWidgets('is not there when the source has no mix', (tester) async {
      final h = _harness(mix: false);
      await h.pumpShell(tester);
      await _search(tester);

      await _openMenu(tester, 'Song a');

      expect(_item('Play'), findsOneWidget);
      expect(_item('Start Mix'), findsNothing);
    });

    testWidgets('starts a mix from the song and plays it', (tester) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _search(tester);
      await _openMenu(tester, 'Song a');

      await tester.tap(_item('Start Mix'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final query = h.plugin.mixQueries.single as MixSeedQuery;
      expect(query.sourceId, 'a');
      expect(h.controller.queue.mode, QueueMode.mix);
      expect(h.controller.queue.mix?.title, 'Late night mix');
      expect(h.controller.queue.entries, hasLength(3));
    });

    testWidgets('a failure shows an error and leaves the queue alone', (
      tester,
    ) async {
      final h = _harness();
      h.plugin.onMix = (_) => throw RateLimited(pluginId: 'fmp-test');
      await h.pumpShell(tester);
      await h.play(tester, [summary('x')]);
      await _search(tester);
      await _openMenu(tester, 'Song a');

      await tester.tap(_item('Start Mix'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(h.controller.queue.mode, QueueMode.queue);
      expect(h.controller.queue.entries, hasLength(1));
      expect(find.textContaining('Too many requests'), findsWidgets);
      // 提示的計時器在樹拆掉前走完。
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('in a mix', () {
    testWidgets('play next and add to queue are disabled and say why', (
      tester,
    ) async {
      final h = await _inMix(tester);
      await _search(tester);

      await _openMenu(tester, 'Song a');

      expect(_item('Play next (unavailable in a Mix)'), findsOneWidget);
      expect(_enabled(tester, 'Play next (unavailable in a Mix)'), isFalse);
      expect(_item('Add to queue (unavailable in a Mix)'), findsOneWidget);
      expect(_enabled(tester, 'Add to queue (unavailable in a Mix)'), isFalse);
      // 播放與開始新的 Mix 照常。
      expect(_enabled(tester, 'Play'), isTrue);
      expect(_enabled(tester, 'Start Mix'), isTrue);
      expect(h.controller.queue.entries, hasLength(3));
    });

    testWidgets('outside a mix the same items are plain and enabled', (
      tester,
    ) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _search(tester);

      await _openMenu(tester, 'Song a');

      expect(_enabled(tester, 'Play next'), isTrue);
      expect(_enabled(tester, 'Add to queue'), isTrue);
      expect(find.textContaining('unavailable in a Mix'), findsNothing);
    });

    testWidgets('the shuffle button of the bar is disabled with a reason', (
      tester,
    ) async {
      final h = await _inMix(tester);

      expect(find.byTooltip(_shuffleLocked), findsOneWidget);
      expect(find.byTooltip(_shuffleTooltip), findsNothing);
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.shuffle),
      );
      expect(button.onPressed, isNull);
      h.controller.setShuffle(true);
      await tester.pump();
      expect(h.controller.queue.shuffleEnabled, isFalse);
    });

    testWidgets('outside a mix the shuffle button works', (tester) async {
      final h = _harness();
      await h.pumpShell(tester);
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byTooltip(_shuffleLocked), findsNothing);
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.shuffle),
      );
      expect(button.onPressed, isNotNull);
      await tester.tap(find.byTooltip(_shuffleTooltip));
      await tester.pump();
      expect(h.controller.queue.shuffleEnabled, isTrue);
    });

    testWidgets('the Ctrl+S shortcut does not turn shuffle on', (tester) async {
      final h = await _inMix(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(h.controller.queue.shuffleEnabled, isFalse);
    });

    testWidgets('the player page disables shuffle too', (tester) async {
      await _inMix(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byKey(PlayerBar.titleKey),
              matching: find.byType(Text),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsOneWidget);
      expect(find.byTooltip(_shuffleLocked), findsWidgets);
      expect(find.byTooltip(_shuffleTooltip), findsNothing);
    });
  });

  group('the queue', () {
    Future<void> openQueue(WidgetTester tester, Size size) async {
      await tester.tap(
        find
            .descendant(
              of: find.byKey(PlayerBar.titleKey),
              matching: find.byType(Text),
            )
            .first,
      );
      await tester.pumpAndSettle();
      if (size.width < 840) {
        await tester.tap(find.byKey(PlayerPage.queueKey));
      } else {
        await tester.tap(find.widgetWithText(Tab, 'Queue'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(QueueView), findsOneWidget);
    }

    for (final size in const [Size(400, 800), Size(1000, 800)]) {
      testWidgets('shows the title of the mix at ${size.width}', (
        tester,
      ) async {
        await _inMix(tester, size: size);

        await openQueue(tester, size);

        expect(find.byKey(QueueView.mixNoteKey), findsOneWidget);
        expect(find.text('Mix: Late night mix'), findsOneWidget);
        // 隨機的說明不在：Mix 沒有隨機。
        expect(find.textContaining('shuffle order'), findsNothing);
      });
    }

    testWidgets('has no mix title outside a mix', (tester) async {
      final h = _harness();
      await h.pumpShell(tester);
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 200));

      await openQueue(tester, const Size(1000, 700));

      expect(find.byKey(QueueView.mixNoteKey), findsNothing);
    });

    testWidgets('a row menu starts a mix from that song', (tester) async {
      final h = await _inMix(tester);
      await openQueue(tester, const Size(1000, 800));

      await _openMenu(tester, 'Song m2');
      expect(_item('Start Mix'), findsOneWidget);
      await tester.tap(_item('Start Mix'));
      await tester.pump();
      await tester.pump();

      expect((h.plugin.mixQueries.last as MixSeedQuery).sourceId, 'm2');
    });

    testWidgets('a row menu of a source without mix has no Start Mix', (
      tester,
    ) async {
      final h = _harness(mix: false);
      await h.pumpShell(tester);
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 200));
      await openQueue(tester, const Size(1000, 800));

      await _openMenu(tester, 'Song a');

      expect(_item('Start Mix'), findsNothing);
    });

    testWidgets('dragging a song keeps the mix title', (tester) async {
      final h = await _inMix(tester);
      await openQueue(tester, const Size(1000, 800));
      expect(find.byKey(QueueView.mixNoteKey), findsOneWidget);

      h.controller.move(0, 1);
      await tester.pump();

      expect(find.byKey(QueueView.mixNoteKey), findsOneWidget);
    });
  });
}
