import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

/// 播放列單獨放在視窗底部，寬度就是視窗寬度。
Future<ShellHarness> pumpBar(
  WidgetTester tester, {
  double width = 1000,
  ShellHarness? harness,
}) async {
  final h = harness ?? ShellHarness();
  await h.pumpApp(
    tester,
    const Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: WindowClassScope(child: PlayerBar()),
      ),
    ),
    size: Size(width, 600),
  );
  return h;
}

void main() {
  const play = 'Play (Space)';
  const pause = 'Pause (Space)';
  const previous = 'Previous (Ctrl+←)';
  const next = 'Next (Ctrl+→)';

  testWidgets('takes no space while nothing is queued', (tester) async {
    await pumpBar(tester);

    expect(tester.getSize(find.byType(PlayerBar)).height, 0);
  });

  // ADR 0024 §決定 5，只放 M1 有的功能（音量、隨機、循環、輸出裝置在 M2）。
  group('controls per width', () {
    for (final (width, controls) in [
      (360.0, {pause, next}),
      (599.0, {pause, next}),
      (600.0, {previous, pause, next}),
      (839.0, {previous, pause, next}),
      (840.0, {previous, pause, next}),
      (1600.0, {previous, pause, next}),
    ]) {
      testWidgets('$width wide: $controls; the title keeps 160dp', (
        tester,
      ) async {
        final h = await pumpBar(tester, width: width);
        await h.play(tester, [summary('a'), summary('b')]);
        await tester.pump(const Duration(milliseconds: 100));

        final tooltips = {
          for (final button in tester.widgetList<IconButton>(
            find.descendant(
              of: find.byType(PlayerBar),
              matching: find.byType(IconButton),
            ),
          ))
            button.tooltip,
        };
        expect(tooltips, controls);
        expect(find.byType(Slider), findsOneWidget);
        expect(
          tester.getSize(find.byKey(PlayerBar.titleKey)).width,
          greaterThanOrEqualTo(160),
        );
        expect(find.text('Song a'), findsOneWidget);
        expect(find.text('Uploader a'), findsOneWidget);
      });
    }
  });

  group('state from the controller', () {
    testWidgets('loading shows a labelled spinner; pressing it pauses', (
      tester,
    ) async {
      final pending = Completer<List<StreamCandidate>>();
      final h = ShellHarness();
      h.plugin.respond = (_) => pending.future;
      await pumpBar(tester, harness: h);
      await h.play(tester, [summary('a')]);

      expect(h.controller.state, isA<Loading>());
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(find.byTooltip(pause), findsOneWidget);

      await tester.tap(find.byTooltip(pause));
      await tester.pump();
      pending.complete([candidate('a.m4a')]);
      await tester.pump();
      await tester.pump();
      expect(h.controller.state, isA<Paused>());
      expect(find.byTooltip(play), findsOneWidget);
    });

    testWidgets('play, pause, previous and next go to the controller', (
      tester,
    ) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.controller.state, isA<Playing>());

      await tester.tap(find.byTooltip(pause));
      await tester.pump();
      expect(h.controller.state, isA<Paused>());
      await tester.tap(find.byTooltip(play));
      await tester.pump();
      expect(h.controller.state, isA<Playing>());

      await tester.tap(find.byTooltip(next));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.controller.queue.currentIndex, 1);
      expect(find.text('Song b'), findsOneWidget);
      // 最後一首：下一首停用。
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.skip_next),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byTooltip(previous));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.controller.queue.currentIndex, 0);
    });

    testWidgets('dragging the progress bar seeks on release', (tester) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('3:00'), findsOneWidget, reason: 'the duration');

      final slider = find.byType(Slider);
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      // 拖動中只改畫面，還沒 seek。
      expect(
        h.container(tester).read(playbackProgressProvider).value!.position,
        lessThan(const Duration(seconds: 5)),
      );
      await gesture.up();
      await tester.pump();

      // 從中間附近開始播：位置跳到約 1:30。
      await tester.pump(const Duration(milliseconds: 60));
      final position = h
          .container(tester)
          .read(playbackProgressProvider)
          .value!
          .position
          .inSeconds;
      expect(position, greaterThan(60));
    });
  });
}
