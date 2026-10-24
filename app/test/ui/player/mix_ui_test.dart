import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/queue/queue_view.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// Mix 的介面（M3 PR 19，ADR 0031 §決定 8–9）：曲目選單的「開始 Mix」只在插件宣告 `mix` 時
// 出現、Mix 中停用的項目附說明、隨機鈕停用、佇列分頁顯示 Mix 的標題。從外殼開始，和
// 使用者一樣。

const _shuffleTooltip = 'Shuffle (Ctrl+S)';
const _shuffleLocked = 'Shuffle is unavailable in a Mix';
const _loopOffTooltip = 'Repeat: off (Ctrl+R)';
const _loopOffInMix = 'Repeat: off (Ctrl+R; no "all" in a Mix)';
const _loopOneInMix = 'Repeat: one (Ctrl+R; no "all" in a Mix)';

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

    testWidgets('the loop button has no "all" and says so', (tester) async {
      final h = await _inMix(tester);

      expect(find.byTooltip(_loopOffInMix), findsOneWidget);
      expect(find.byTooltip(_loopOffTooltip), findsNothing);
      await tester.tap(find.byTooltip(_loopOffInMix));
      await tester.pump();
      expect(h.controller.queue.loopMode, LoopMode.one);
      expect(find.byTooltip(_loopOneInMix), findsOneWidget);

      // Ctrl+R 走同一個 cycleLoopMode。
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(h.controller.queue.loopMode, LoopMode.off);
    });

    testWidgets('the loop item of the "⋯" menu says so too', (tester) async {
      // 播放列在 rail 旁邊：視窗 800 時是 medium，循環在「⋯」裡。
      final h = await _inMix(tester, size: const Size(800, 800));

      await tester.tap(
        find.descendant(
          of: find.byType(PlayerBar),
          matching: find.byTooltip('More'),
        ),
      );
      await tester.pumpAndSettle();
      expect(_item('Repeat: off (no "all" in a Mix)'), findsOneWidget);
      await tester.tap(_item('Repeat: off (no "all" in a Mix)'));
      await tester.pumpAndSettle();
      expect(h.controller.queue.loopMode, LoopMode.one);
    });

    testWidgets('outside a mix the loop button goes off, all, one', (
      tester,
    ) async {
      final h = _harness();
      await h.pumpShell(tester);
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byTooltip(_loopOffTooltip), findsOneWidget);
      await tester.tap(find.byTooltip(_loopOffTooltip));
      await tester.pump();
      expect(h.controller.queue.loopMode, LoopMode.all);
    });

    testWidgets('the player page disables shuffle and has no loop "all" too', (
      tester,
    ) async {
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
      expect(find.byTooltip(_loopOffInMix), findsWidgets);
      expect(find.byTooltip(_loopOffTooltip), findsNothing);
    });
  });

  group('the queue', () {
    Future<void> openQueue(WidgetTester tester, Size size) async {
      await tester.tap(ShellHarness.navigationItem(ShellDestination.queue));
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

    // 「加入歌單…」不動佇列（M4 PR 3）：Mix 中照常，佇列與 Mix 都不變。
    testWidgets('a row menu adds the song to a playlist and leaves the mix '
        'alone', (tester) async {
      final h = await _inMix(tester);
      final id = (await tester.runAsync(
        () => h
            .container(tester)
            .read(playlistRepositoryProvider)
            .create(name: 'Road'),
      ))!;
      await openQueue(tester, const Size(1000, 800));
      final before = [
        for (final e in h.controller.queue.entries) e.track.sourceId,
      ];

      await _openMenu(tester, 'Song m2');
      expect(_enabled(tester, 'Add to playlist…'), isTrue);
      await tester.tap(_item('Add to playlist…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Road'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      for (var i = 0; i < 3; i++) {
        await h.loadSettings(tester);
      }
      await tester.pumpAndSettle();

      final stored = (await tester.runAsync(
        () => h.container(tester).read(playlistRepositoryProvider).entries(id),
      ))!;
      expect([for (final e in stored) e.track.sourceId], ['m2']);
      expect(h.controller.queue.mode, QueueMode.mix);
      expect([
        for (final e in h.controller.queue.entries) e.track.sourceId,
      ], before);
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
