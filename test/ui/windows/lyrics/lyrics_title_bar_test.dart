import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/windows/lyrics/lyrics_title_bar.dart';

LyricsTitleBarLabels get _labels => const LyricsTitleBarLabels(
      previous: 'prev',
      play: 'play',
      pause: 'pause',
      next: 'next',
      styleSettings: 'style',
      fullLyrics: 'full',
      singleLine: 'single',
      normalMode: 'normal',
      transparentMode: 'transparent',
      unpin: 'unpin',
      pin: 'pin',
      offsetAdjust: 'offset',
      close: 'close',
    );

Widget host({required LyricsTitleBar child}) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('LyricsTitleBar (C1e leaf)', () {
    testWidgets('renders title and artist', (tester) async {
      await tester.pumpWidget(host(
        child: LyricsTitleBar(
          title: 'My Song',
          artist: 'Artist',
          transparentMode: false,
          isPlaying: false,
          displayModeIcon: Icons.title,
          displayModeTooltip: 'mode',
          singleLineMode: false,
          alwaysOnTop: true,
          isSynced: false,
          hasLines: false,
          showOffsetControls: false,
          labels: _labels,
          onDragStart: (_) {},
          onPrevious: () {},
          onPlayPause: () {},
          onNext: () {},
          onCycleDisplayMode: () {},
          onShowStyleDialog: () {},
          onToggleSingleLine: () {},
          onToggleTransparent: () {},
          onToggleAlwaysOnTop: () {},
          onToggleOffsetControls: () {},
          onClose: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('My Song'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
    });

    testWidgets('shows pause icon when playing, play icon when not',
        (tester) async {
      for (final playing in [true, false]) {
        await tester.pumpWidget(host(
          child: LyricsTitleBar(
            title: 't',
            artist: null,
            transparentMode: false,
            isPlaying: playing,
            displayModeIcon: Icons.title,
            displayModeTooltip: 'm',
            singleLineMode: false,
            alwaysOnTop: false,
            isSynced: false,
            hasLines: false,
            showOffsetControls: false,
            labels: _labels,
            onDragStart: (_) {},
            onPrevious: () {},
            onPlayPause: () {},
            onNext: () {},
            onCycleDisplayMode: () {},
            onShowStyleDialog: () {},
            onToggleSingleLine: () {},
            onToggleTransparent: () {},
            onToggleAlwaysOnTop: () {},
            onToggleOffsetControls: () {},
            onClose: () {},
          ),
        ));
        await tester.pumpAndSettle();
        expect(
          find.byIcon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          findsOneWidget,
        );
      }
    });

    testWidgets('offset button shows only when synced and has lines',
        (tester) async {
      Future<void> pump({required bool synced, required bool hasLines}) async {
        await tester.pumpWidget(host(
          child: LyricsTitleBar(
            title: 't',
            artist: null,
            transparentMode: false,
            isPlaying: false,
            displayModeIcon: Icons.title,
            displayModeTooltip: 'm',
            singleLineMode: false,
            alwaysOnTop: false,
            isSynced: synced,
            hasLines: hasLines,
            showOffsetControls: false,
            labels: _labels,
            onDragStart: (_) {},
            onPrevious: () {},
            onPlayPause: () {},
            onNext: () {},
            onCycleDisplayMode: () {},
            onShowStyleDialog: () {},
            onToggleSingleLine: () {},
            onToggleTransparent: () {},
            onToggleAlwaysOnTop: () {},
            onToggleOffsetControls: () {},
            onClose: () {},
          ),
        ));
        await tester.pumpAndSettle();
      }

      await pump(synced: true, hasLines: true);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);

      await pump(synced: false, hasLines: true);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);

      await pump(synced: true, hasLines: false);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
    });

    testWidgets('tapping transport buttons fires injected callbacks',
        (tester) async {
      var prev = 0, playPause = 0, next = 0, close = 0;
      await tester.pumpWidget(host(
        child: LyricsTitleBar(
          title: 't',
          artist: null,
          transparentMode: false,
          isPlaying: true,
          displayModeIcon: Icons.title,
          displayModeTooltip: 'm',
          singleLineMode: false,
          alwaysOnTop: false,
          isSynced: false,
          hasLines: false,
          showOffsetControls: false,
          labels: _labels,
          onDragStart: (_) {},
          onPrevious: () => prev++,
          onPlayPause: () => playPause++,
          onNext: () => next++,
          onCycleDisplayMode: () {},
          onShowStyleDialog: () {},
          onToggleSingleLine: () {},
          onToggleTransparent: () {},
          onToggleAlwaysOnTop: () {},
          onToggleOffsetControls: () {},
          onClose: () => close++,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(prev, 1);
      expect(playPause, 1);
      expect(next, 1);
      expect(close, 1);
    });
  });
}
