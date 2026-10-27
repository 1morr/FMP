import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/player/track_details.dart';
import 'package:fmp/ui/queue/queue_view.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/shell/window_title_bar.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_audio_backend.dart';
import '../support/fake_artwork.dart';
import '../support/fake_window_chrome.dart';
import '../support/shell_harness.dart';

// M2 PR 18a：播放頁（design §9.3、§9.5、§9.6）。每個測試從外殼開始，點播放列的曲名
// 與封面那一塊開頁，和使用者一樣。

const _close = 'Close the player (Esc)';
const _info = 'Track info';
const _closeInfo = 'Close track info';
const _addToPlaylist = 'Add to playlist';
const _speakers = OutputDevice(id: 'wasapi/{a}', name: 'Speakers');
const _more = 'More';

/// 播放列上的曲名（點它開播放頁）。
final _barTitle = find
    .descendant(of: find.byKey(PlayerBar.titleKey), matching: find.byType(Text))
    .first;

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
}) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

/// 外殼開好、佇列裡兩首（播第一首）；還沒開播放頁。
Future<ShellHarness> _pumpPlaying(
  WidgetTester tester, {
  Size size = const Size(1000, 700),
  ShellHarness? harness,
  bool playing = true,
}) async {
  final h = harness ?? ShellHarness();
  await h.pumpShell(tester, size: size);
  if (playing) {
    await h.play(tester, [summary('a'), summary('b')]);
  } else {
    h.controller.addToQueue([
      summary('a').toTrackInfo(),
      summary('b').toTrackInfo(),
    ]);
    await tester.pump();
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 200));
  return h;
}

/// 點播放列的曲名與封面那一塊開播放頁。
Future<void> _openByTap(WidgetTester tester) async {
  await tester.tap(_barTitle);
  await tester.pumpAndSettle();
  expect(find.byType(PlayerPage), findsOneWidget);
}

void main() {
  group('opening and closing', () {
    testWidgets('tapping the title and artwork opens the page, a button does '
        'not', (tester) async {
      await _pumpPlaying(tester);
      expect(find.byType(PlayerPage), findsNothing);

      await tester.tap(find.byTooltip('Next (Ctrl+→)'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
      await tester.tap(find.byTooltip('Shuffle (Ctrl+S)'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);

      await _openByTap(tester);
    });

    for (final (name, size) in [
      ('compact', const Size(400, 800)),
      ('medium', const Size(700, 800)),
    ]) {
      testWidgets('the bar opens it at $name too', (tester) async {
        await _pumpPlaying(tester, size: size);
        await _openByTap(tester);
      });
    }

    testWidgets('the collapse button closes it', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);

      expect(find.byTooltip(_close), findsOneWidget);
      await tester.tap(find.byKey(PlayerPage.closeKey));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('Esc closes it', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('with a dialog open Esc closes the dialog first', (
      tester,
    ) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(PlayerPage)),
          builder: (_) => const AlertDialog(content: Text('A dialog')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A dialog'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('A dialog'), findsNothing);
      expect(find.byType(PlayerPage), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('Esc closes the speed menu before the page', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playback speed'));
      await tester.pumpAndSettle();
      expect(find.text('1.5×'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('1.5×'), findsNothing);
      expect(find.byType(PlayerPage), findsOneWidget);
    });

    testWidgets('the back key closes only the page', (tester) async {
      final h = await _pumpPlaying(tester);
      await h.openHistory(tester);
      await _openByTap(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      // 外殼還停在音樂庫裡的歷史頁，沒有被返回鍵退出內頁或帶回首頁。
      expect(find.text('No play history yet'), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('focus returns to the player bar after closing', (
      tester,
    ) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('Open the player'),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Open the player');
    });

    // 關閉的轉場中播放頁不收點擊，點擊落到底下的播放列：這時再開的播放頁不能被舊的
    // route 在轉場結束、被丟掉時標成「沒開」，否則提示會回到播放列的高度、再點播放列
    // 又會推第二個。
    testWidgets('reopening it while it is still closing keeps it open', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_barTitle, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsOneWidget);
      expect(h.container(tester).read(playerPageOpenProvider), isTrue);

      expect(find.byType(PlayerPage), findsOneWidget);

      // The first page giving the focus back must not pull it out of the new
      // one: Esc still reaches the page.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
    });

    // 佇列在 push 之後、頁面第一次 build 之前就空了：頁面的 listen 看不到「變空」那一次，
    // 但也不能留下一個沒有收合鈕、沒有快捷鍵的空白頁。
    testWidgets('it closes itself when the queue is empty by its first frame', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester);
      await tester.tap(_barTitle);
      h.controller.clear();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(PlayerPage), findsNothing);
      expect(h.container(tester).read(playerPageOpenProvider), isFalse);
    });

    testWidgets('it closes itself when the queue is cleared', (tester) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);

      h.controller.clear();
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      expect(h.container(tester).read(playerPageOpenProvider), isFalse);
    });
  });

  group('shortcuts', () {
    // ADR 0035 §決定 7：Ctrl+L 在歌詞（M7）之前不做事，連播放頁也不開。
    testWidgets('Ctrl+L does nothing before the lyrics exist', (tester) async {
      await _pumpPlaying(tester);
      await _chord(tester, LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('Ctrl+L does nothing while the queue is empty', (tester) async {
      await ShellHarness().pumpShell(tester);

      await _chord(tester, LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('Ctrl+Q on the page closes it, selects the queue destination '
        'and focuses the queue page', (tester) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);

      await _chord(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      expect(h.container(tester).read(playerPageOpenProvider), isFalse);
      expect(find.byType(QueueView).hitTestable(), findsOneWidget);
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(focused.findAncestorWidgetOfExactType<QueueView>(), isNotNull);
    });

    testWidgets('Ctrl+L on the page does nothing before the lyrics exist', (
      tester,
    ) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);

      await _chord(tester, LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsOneWidget);
    });

    testWidgets('the playback keys work on the page', (tester) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);
      expect(h.controller.state, isA<Playing>());

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(h.controller.state, isA<Paused>());

      await _chord(tester, LogicalKeyboardKey.keyS);
      expect(h.controller.queue.shuffleEnabled, isTrue);
      await _chord(tester, LogicalKeyboardKey.keyR);
      expect(h.controller.queue.loopMode, LoopMode.all);
      await _chord(tester, LogicalKeyboardKey.arrowDown);
      expect(h.controller.volume, closeTo(0.95, 0.001));
    });

    testWidgets('F6 moves between the controls and the open details panel and '
        'Tab stays in the region', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);
      await tester.tap(find.byKey(PlayerPage.infoKey));
      await tester.pumpAndSettle();

      // F6 cycles through the two regions and comes back.
      final scopes = <FocusScopeNode>[];
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f6);
        await tester.pump();
        scopes.add(FocusManager.instance.primaryFocus!.enclosingScope!);
      }
      expect(scopes[1], isNot(scopes[0]));
      expect(scopes[2], scopes[0]);

      // Tab only walks inside the region: after many presses the focus is
      // still within the same scope.
      final scope = FocusManager.instance.primaryFocus!.enclosingScope;
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus!.enclosingScope, scope);
      }
    });
  });

  group('layout choice', () {
    // 840 and 520 are the legacy thresholds; 914x411 and 914x360 are the
    // logical sizes of common landscape phones.
    for (final (size, expected) in [
      (const Size(840, 520), PlayerLayout.wide),
      (const Size(839, 520), PlayerLayout.narrow),
      (const Size(840, 519), PlayerLayout.short),
      (const Size(839, 519), PlayerLayout.short),
      (const Size(1600, 900), PlayerLayout.wide),
      (const Size(1000, 400), PlayerLayout.short),
      (const Size(914, 411), PlayerLayout.short),
      (const Size(914, 360), PlayerLayout.short),
      (const Size(400, 800), PlayerLayout.narrow),
      (const Size(700, 800), PlayerLayout.narrow),
      // Short but not wider than tall: a portrait window, not a landscape phone.
      (const Size(400, 519), PlayerLayout.narrow),
      (const Size(519, 519), PlayerLayout.narrow),
    ]) {
      test('$size is $expected', () {
        expect(resolvePlayerLayout(size), expected);
      });
    }
  });

  group('layouts', () {
    List<String> shown(Iterable<String> tooltips) => [
      for (final tooltip in tooltips)
        if (find.byTooltip(tooltip).evaluate().isNotEmpty) tooltip,
    ];

    const controls = [
      'Shuffle (Ctrl+S)',
      'Previous (Ctrl+←)',
      'Pause (Space)',
      'Next (Ctrl+→)',
      'Repeat: off (Ctrl+R)',
      _more,
      _close,
    ];

    final title = find.descendant(
      of: find.byType(PlayerPage),
      matching: find.text('Song a'),
    );
    // The cover is the artwork that is not the 256dp backdrop source.
    final cover = find.descendant(
      of: find.byType(PlayerPage),
      matching: find.byWidgetPredicate(
        (widget) => widget is ArtworkImage && widget.size != 256,
      ),
    );

    for (final (name, size) in [
      ('compact', const Size(400, 800)),
      ('medium', const Size(700, 800)),
    ]) {
      testWidgets('$name: artwork above the controls, no cover/lyrics toggle', (
        tester,
      ) async {
        await _pumpPlaying(tester, size: size);
        await _openByTap(tester);

        expect(shown(controls), controls);
        expect(find.byType(TabBar), findsNothing);
        expect(find.byIcon(Icons.queue_music), findsNothing);
        expect(find.bySemanticsLabel(RegExp('lyrics')), findsNothing);
        expect(
          tester.getRect(cover).bottom,
          lessThan(tester.getRect(title).top),
        );
        // The title is centered.
        expect(tester.getRect(title).center.dx, closeTo(size.width / 2, 1));
      });
    }

    testWidgets('wide: one centered column of at most 720', (tester) async {
      await _pumpPlaying(tester, size: const Size(1400, 900));
      await _openByTap(tester);

      expect(shown(controls), controls);
      final progress = tester.getRect(find.byType(Slider).first);
      expect(progress.width, lessThanOrEqualTo(720));
      expect(progress.center.dx, closeTo(700, 1));
      expect(tester.getRect(cover).bottom, lessThan(tester.getRect(title).top));
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('short: the artwork on the left, the controls on the right', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(914, 411));
      await _openByTap(tester);

      expect(shown(controls), controls);
      expect(tester.getRect(cover).right, lessThan(tester.getRect(title).left));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the artwork is at most 420 with a large radius and a shadow', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(1400, 1200));
      await _openByTap(tester);

      final sizes = [
        for (final artwork in tester.widgetList<ArtworkImage>(
          find.byType(ArtworkImage),
        ))
          artwork.size,
      ];
      expect(sizes, contains(420));
      expect(sizes.where((size) => size > 420), isEmpty);

      final frame = tester.widget<DecoratedBox>(
        find.ancestor(of: cover, matching: find.byType(DecoratedBox)).first,
      );
      final decoration = frame.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(16));
      expect(decoration.boxShadow, isNotEmpty);

      // A shorter window shrinks it instead of overflowing.
      tester.view.physicalSize = const Size(1400, 620);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final shrunk = tester
          .widgetList<ArtworkImage>(find.byType(ArtworkImage))
          .map((artwork) => artwork.size);
      expect(shrunk.where((size) => size != 256 && size < 420), isNotEmpty);
    });

    testWidgets('the layout follows the window when it is resized', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(1000, 700));
      await _openByTap(tester);
      expect(tester.getRect(cover).bottom, lessThan(tester.getRect(title).top));

      tester.view.physicalSize = const Size(914, 411);
      await tester.pumpAndSettle();
      expect(tester.getRect(cover).right, lessThan(tester.getRect(title).left));
      expect(find.byType(PlayerPage), findsOneWidget);
    });

    // The smallest windows the layouts are meant for: no overflow, and the
    // controls stay reachable.
    for (final (name, size) in [
      ('narrow 320x480', const Size(320, 480)),
      ('narrow 360x640', const Size(360, 640)),
      ('short 640x360', const Size(640, 360)),
      ('short 914x360', const Size(914, 360)),
      ('wide 840x520', const Size(840, 520)),
    ]) {
      testWidgets('$name does not overflow', (tester) async {
        await _pumpPlaying(tester, size: size);
        await _openByTap(tester);

        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Pause (Space)').hitTestable(), findsOneWidget);
      });
    }

    testWidgets('the controls follow the legacy sizes', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);

      expect(
        tester.getSize(find.byTooltip('Pause (Space)')),
        const Size.square(80),
      );
      expect(
        tester.getSize(find.byTooltip('Next (Ctrl+→)')).width,
        greaterThan(48),
      );
      // No glass behind the controls.
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.widget<Text>(title).style?.fontWeight, FontWeight.bold);
    });
  });

  group('top row', () {
    const outputDevice = 'Output device';
    const mute = 'Mute';

    testWidgets('on a phone: add, info and the menu, no volume or device', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(400, 800));
      await _openByTap(tester);

      for (final tooltip in [_close, _addToPlaylist, _info, _more]) {
        expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
      }
      expect(find.byTooltip(outputDevice), findsNothing);
      expect(find.byTooltip(mute), findsNothing);
    });

    testWidgets('with output device selection (desktop): the device and the '
        'volume too', (tester) async {
      final h = ShellHarness(
        outputDeviceSelection: true,
        outputDevices: FakeOutputDevices(const [_speakers]),
      );
      await _pumpPlaying(tester, harness: h);
      await _openByTap(tester);

      for (final tooltip in [
        _close,
        _addToPlaylist,
        outputDevice,
        mute,
        _info,
        _more,
      ]) {
        expect(
          find.descendant(
            of: find.byType(PlayerPage),
            matching: find.byTooltip(tooltip),
          ),
          findsOneWidget,
          reason: tooltip,
        );
      }
      expect(
        find.descendant(
          of: find.byType(PlayerPage),
          matching: find.byType(Slider),
        ),
        findsNWidgets(2),
        reason: 'the progress bar and the volume slider',
      );
    });

    testWidgets('the mute button in the top row mutes', (tester) async {
      final h = ShellHarness(
        outputDeviceSelection: true,
        outputDevices: FakeOutputDevices(const [_speakers]),
      );
      await _pumpPlaying(tester, harness: h);
      await _openByTap(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(PlayerPage),
          matching: find.byTooltip(mute),
        ),
      );
      await tester.pump();

      expect(h.controller.muted, isTrue);
    });

    testWidgets('a small desktop window does not overflow the top row', (
      tester,
    ) async {
      final h = ShellHarness(
        outputDeviceSelection: true,
        outputDevices: FakeOutputDevices(const [_speakers]),
      );
      await _pumpPlaying(tester, harness: h, size: const Size(360, 640));
      await _openByTap(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('add to playlist opens the usual flow', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);

      await tester.tap(find.byTooltip(_addToPlaylist));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('track details', () {
    testWidgets('narrow: the info button opens a bottom sheet', (tester) async {
      await _pumpPlaying(tester, size: const Size(400, 800));
      await _openByTap(tester);

      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();

      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(TrackDetails),
        ),
        findsOneWidget,
      );
      expect(find.text('Test Source'), findsOneWidget);
      expect(find.byKey(PlayerPage.detailsPanelKey), findsNothing);

      // The sheet can be dragged up.
      final before = tester.getRect(find.byType(TrackDetails)).top;
      await tester.drag(find.byType(TrackDetails), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(TrackDetails)).top, lessThan(before));

      // Dismissing it leaves the page open.
      await tester.tapAt(const Offset(200, 10));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byType(PlayerPage), findsOneWidget);
    });

    testWidgets('short: the info button opens a bottom sheet too', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(914, 411));
      await _openByTap(tester);

      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();

      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide: the info button slides in a panel from the right', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(1200, 800));
      await _openByTap(tester);
      expect(find.byKey(PlayerPage.detailsPanelKey), findsNothing);

      await tester.tap(find.byTooltip(_info));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final sliding = tester.getRect(find.byKey(PlayerPage.detailsPanelKey));
      await tester.pumpAndSettle();
      final settled = tester.getRect(find.byKey(PlayerPage.detailsPanelKey));

      expect(sliding.left, greaterThan(settled.left));
      expect(settled.right, 1200);
      expect(settled.width, 400);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(PlayerPage.detailsPanelKey),
          matching: find.byType(TrackDetails),
        ),
        findsOneWidget,
      );
      expect(find.text('Test Source'), findsOneWidget);

      await tester.tap(find.byTooltip(_closeInfo));
      await tester.pumpAndSettle();
      expect(find.byKey(PlayerPage.detailsPanelKey), findsNothing);
      expect(find.byType(PlayerPage), findsOneWidget);
    });

    testWidgets('wide: the panel keeps only the safe area of its own edge', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(1200, 800));
      tester.view.padding = const FakeViewPadding(left: 48, right: 24);
      tester.view.viewPadding = const FakeViewPadding(left: 48, right: 24);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();

      final header = tester.getRect(
        find.descendant(
          of: find.byKey(PlayerPage.detailsPanelKey),
          matching: find.text(_info),
        ),
      );
      // 16dp from the panel's start, not pushed in by the window's left inset.
      expect(header.left, closeTo(1200 - 400 + 16, 1));
      expect(
        tester.getRect(find.byTooltip(_closeInfo)).right,
        lessThanOrEqualTo(1200 - 24),
      );
    });

    testWidgets('wide: Esc closes the panel first, then the page', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(1200, 800));
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(PlayerPage.detailsPanelKey), findsNothing);
      expect(find.byType(PlayerPage), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
    });

    // 返回鍵同 Esc：先關面板，再關頁面（U PR 15，PR 7 審查）。
    testWidgets('wide: the back key closes the panel first, then the page', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(1200, 800));
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(PlayerPage.detailsPanelKey), findsNothing);
      expect(find.byType(PlayerPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
    });

    // 只有返回鍵與 Esc 先關面板：收合鈕與 Ctrl+Q 是「離開這一頁」，面板開著也關整頁
    // （頁面的 PopScope 不能攔下它們）。
    testWidgets('wide: with the panel open the collapse button closes the '
        'page', (tester) async {
      await _pumpPlaying(tester, size: const Size(1200, 800));
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(_close));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('wide: with the panel open Ctrl+Q closes the page and selects '
        'the queue', (tester) async {
      final h = await _pumpPlaying(tester, size: const Size(1200, 800));
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();

      await _chord(tester, LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      expect(h.container(tester).read(playerPageOpenProvider), isFalse);
      expect(find.byType(QueueView).hitTestable(), findsOneWidget);
    });

    testWidgets('wide: with the panel closed the back key closes the page', (
      tester,
    ) async {
      await _pumpPlaying(tester, size: const Size(1200, 800));
      await _openByTap(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
    });

    // 視窗跨過外殼的斷點時外殼換了導覽元件，巢狀 Navigator 重建；焦點不能被搶進被蓋住的
    // 內容區，播放頁之後仍收得到 Esc、F6（U PR 15，PR 7 審查）。
    for (final (name, from, to) in [
      ('wide to compact', const Size(1200, 800), const Size(500, 800)),
      ('compact to wide', const Size(500, 800), const Size(1200, 800)),
    ]) {
      testWidgets('crossing the shell breakpoint ($name) keeps the keys on the '
          'page', (tester) async {
        await _pumpPlaying(tester, size: from);
        await _openByTap(tester);

        tester.view.physicalSize = to;
        await tester.pumpAndSettle();

        final focus = FocusManager.instance.primaryFocus!.context!;
        expect(focus.findAncestorWidgetOfExactType<PlayerPage>(), isNotNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.f6);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus!.context!
              .findAncestorWidgetOfExactType<PlayerPage>(),
          isNotNull,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byType(PlayerPage), findsNothing);
      });
    }

    testWidgets('wide: narrowing the window drops the panel', (tester) async {
      await _pumpPlaying(tester, size: const Size(1200, 800));
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(500, 800);
      await tester.pumpAndSettle();

      expect(find.byKey(PlayerPage.detailsPanelKey), findsNothing);
      expect(find.byType(PlayerPage), findsOneWidget);
    });

    // Only the height changes, so the window class of the shell underneath
    // stays the same and only the page's layout goes from wide to short.
    testWidgets('wide: after a resize drops the focused panel, Esc closes the '
        'page', (tester) async {
      await _pumpPlaying(tester, size: const Size(1000, 700));
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();
      // The focus in the panel (the controls are the first region).
      for (var i = 0; i < 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f6);
        await tester.pump();
      }

      tester.view.physicalSize = const Size(1000, 500);
      await tester.pumpAndSettle();
      expect(find.byKey(PlayerPage.detailsPanelKey), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('wide: closing the panel from inside it keeps the keys on the '
        'page', (tester) async {
      await _pumpPlaying(tester, size: const Size(1200, 800));
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();

      // F6 into the panel (the controls are the first region), Esc closes it,
      // and the next Esc still reaches the page.
      bool inPanel() {
        var found = false;
        FocusManager.instance.primaryFocus!.context!.visitAncestorElements((
          element,
        ) {
          found = element.widget.key == PlayerPage.detailsPanelKey;
          return !found;
        });
        return found;
      }

      for (var i = 0; i < 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f6);
        await tester.pump();
      }
      expect(inPanel(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(PlayerPage.detailsPanelKey), findsNothing);
      // The focus is back in the controls, not lost.
      expect(
        FocusManager.instance.primaryFocus!.ancestors.map(
          (node) => node.debugLabel,
        ),
        contains('Player page controls'),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('the sheet closes with the page when the queue is cleared', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester, size: const Size(400, 800));
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();

      h.controller.clear();
      await tester.pumpAndSettle();

      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byType(PlayerPage), findsNothing);
      expect(h.container(tester).read(playerPageOpenProvider), isFalse);
    });

    testWidgets('the details show the song and its source', (tester) async {
      await _pumpPlaying(tester, size: const Size(1200, 800));
      await _openByTap(tester);
      await tester.tap(find.byTooltip(_info));
      await tester.pumpAndSettle();

      final panel = find.byKey(PlayerPage.detailsPanelKey);
      for (final text in ['Song a', 'Uploader a', '3:05', 'Test Source']) {
        expect(
          find.descendant(of: panel, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
    });

    testWidgets('the details name a source without a name by its id', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpApp(
        tester,
        const Scaffold(
          body: TrackDetails(
            track: TrackInfo(
              sourceTypeId: 'gone-source',
              sourceId: '1',
              title: 'Lost song',
            ),
          ),
        ),
      );

      expect(find.text('gone-source'), findsOneWidget);
    });
  });

  group('transition', () {
    SlideTransition slide(WidgetTester tester) =>
        tester.widget<SlideTransition>(
          find
              .ancestor(
                of: find.byType(PlayerPage),
                matching: find.byType(SlideTransition),
              )
              .first,
        );

    testWidgets('slides up from the bottom to open', (tester) async {
      await _pumpPlaying(tester);
      await tester.tap(_barTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final dy = slide(tester).position.value.dy;
      expect(dy, greaterThan(0));
      expect(dy, lessThan(1));
      expect(dy, closeTo(1 - Curves.easeOutCubic.transform(100 / 300), 0.02));

      await tester.pumpAndSettle();
      expect(slide(tester).position.value, Offset.zero);
    });

    testWidgets('slides down to close', (tester) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);

      await tester.tap(find.byKey(PlayerPage.closeKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final dy = slide(tester).position.value.dy;
      expect(dy, greaterThan(0));
      expect(dy, lessThan(1));
      // The reverse curve is applied to the animation value going 1 to 0.
      expect(
        dy,
        closeTo(1 - Curves.easeInCubic.transform(1 - 100 / 300), 0.02),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
    });

    testWidgets('with reduced motion it fades instead of moving', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pumpPlaying(tester);
      await tester.tap(_barTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.ancestor(
          of: find.byType(PlayerPage),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byType(PlayerPage),
          matching: find.byType(FadeTransition),
        ),
        findsWidgets,
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
    });
  });

  group('speed', () {
    Future<void> openSpeedMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip(_more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playback speed'));
      await tester.pumpAndSettle();
    }

    bool checked(WidgetTester tester, String label) {
      final item = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, label),
      );
      return (item.leadingIcon! as Visibility).visible;
    }

    testWidgets('the menu has the seven speeds and checks the current one', (
      tester,
    ) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);
      await openSpeedMenu(tester);

      const labels = [
        '0.5×',
        '0.75×',
        '1.0×',
        '1.25×',
        '1.5×',
        '1.75×',
        '2.0×',
      ];
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        [for (final label in labels) checked(tester, label)],
        [false, false, true, false, false, false, false],
      );
    });

    testWidgets('choosing one calls the controller and moves the check', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester);
      await _openByTap(tester);
      await openSpeedMenu(tester);

      await tester.tap(find.text('1.5×'));
      await tester.pumpAndSettle();

      expect(h.controller.speed, 1.5);
      expect(h.backend.speed, 1.5);

      await openSpeedMenu(tester);
      expect(checked(tester, '1.5×'), isTrue);
      expect(checked(tester, '1.0×'), isFalse);
    });
  });

  group('status and progress', () {
    testWidgets('waiting for the network is shown on the page', (tester) async {
      final h = ShellHarness();
      h.plugin.respond = (_) => throw NetworkError(pluginId: 'fmp-test');
      await h.pumpShell(tester);
      await h.setNetwork(tester, NetworkStatus.noInterface);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(_barTitle);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('Waiting for the network'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(PlayerPage),
          matching: find.textContaining('Waiting for the network'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('after a restore the page shows the restored position', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      h.controller.restore(
        tracks: [summary('a').toTrackInfo()],
        currentIndex: 0,
        loopMode: LoopMode.off,
        shuffle: false,
        position: const Duration(seconds: 83),
        volume: 1,
        muted: false,
      );
      await tester.pump();
      await tester.pump();

      await _openByTap(tester);

      expect(
        find.descendant(
          of: find.byType(PlayerPage),
          matching: find.text('1:23'),
        ),
        findsOneWidget,
      );
    });
  });

  group('backdrop', () {
    testWidgets('a song with artwork gets a backdrop of it', (tester) async {
      final h = ShellHarness(artworkManager: FakeArtworkManager());
      await h.pumpShell(tester);
      await h.play(tester, [
        summary('a', artwork: TestArtwork.lightest.artwork),
      ]);
      await _openByTap(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(find.byType(ArtworkImage), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('toasts', () {
    testWidgets('the toast sits on the safe area while the page is open', (
      tester,
    ) async {
      final h = await _pumpPlaying(tester, size: const Size(1000, 700));
      tester.view.padding = const FakeViewPadding(bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pump();
      final container = h.container(tester);
      final withBar = container.read(toastBottomInsetProvider);
      expect(withBar, greaterThan(24), reason: 'the bar is below the toast');

      await _openByTap(tester);
      await tester.pump();
      expect(container.read(toastBottomInsetProvider), 24);

      h.toaster.warning('A toast over the page');
      await tester.pumpAndSettle();
      final toast = tester.getRect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(Material),
        ),
      );
      // 16dp of margin above the safe area.
      expect(toast.bottom, closeTo(700 - 24 - 16, 1));

      await tester.pumpAndSettle(const Duration(seconds: 7));
      await tester.tap(find.byKey(PlayerPage.closeKey));
      await tester.pumpAndSettle();
      expect(container.read(toastBottomInsetProvider), withBar);
    });
  });

  // U PR 15（ADR 0035 §決定 6）：Windows 自繪標題列在根 Navigator 外面，播放頁開著時仍是同一條；頂列後面是拖曳區。
  group('window chrome', () {
    testWidgets(
      'the one title bar stays over the page, with a drag area under the top row',
      (tester) async {
        final chrome = FakeWindowChrome();
        await _pumpPlaying(tester, harness: ShellHarness(windowChrome: chrome));
        await _openByTap(tester);

        final bar = find.byType(WindowTitleBar);
        expect(bar, findsOneWidget);
        expect(tester.getTopLeft(bar), Offset.zero);

        await tester.tap(
          find.descendant(of: bar, matching: find.byTooltip('Minimize')),
        );
        expect(chrome.calls, ['minimize']);
      },
    );

    testWidgets('dragging the empty top row moves the window', (tester) async {
      final chrome = FakeWindowChrome();
      await _pumpPlaying(tester, harness: ShellHarness(windowChrome: chrome));
      await _openByTap(tester);

      // The title bar is 36dp tall; the top row starts under it. The gap between
      // the collapse button and the right-hand buttons is empty.
      await tester.dragFrom(const Offset(500, 36 + 32), const Offset(40, 10));
      await tester.pump(const Duration(milliseconds: 500));

      expect(chrome.calls, ['startDragging']);
    });

    testWidgets('a platform without a custom title bar has neither', (
      tester,
    ) async {
      await _pumpPlaying(tester);
      await _openByTap(tester);

      expect(find.byType(WindowTitleBar), findsNothing);
    });
  });
}
