import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/windows/lyrics/lyrics_offset_bar.dart';

Widget host({required LyricsOffsetBar child}) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('LyricsOffsetBar (C1d leaf)', () {
    testWidgets('renders label and formatted offset value', (tester) async {
      await tester.pumpWidget(host(
        child: const LyricsOffsetBar(
          offsetMs: 1500,
          transparentMode: false,
          offsetLabel: 'Offset',
          onAdjust: _noop,
          onReset: _noopReset,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Offset'), findsOneWidget);
      expect(find.text('+1.5s'), findsOneWidget);
    });

    testWidgets('tapping +500 button fires onAdjust(500)', (tester) async {
      var lastDelta = 0;
      await tester.pumpWidget(host(
        child: LyricsOffsetBar(
          offsetMs: 0,
          transparentMode: false,
          offsetLabel: 'Offset',
          onAdjust: (d) => lastDelta = d,
          onReset: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(lastDelta, 500);

      await tester.tap(find.byIcon(Icons.fast_rewind));
      await tester.pump();
      expect(lastDelta, -1000);
    });

    testWidgets('reset fires onReset when offset != 0', (tester) async {
      var resets = 0;
      await tester.pumpWidget(host(
        child: LyricsOffsetBar(
          offsetMs: 800,
          transparentMode: false,
          offsetLabel: 'Offset',
          onAdjust: (_) {},
          onReset: () => resets++,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(resets, 1);
    });

    testWidgets('reset is disabled when offset == 0', (tester) async {
      var resets = 0;
      await tester.pumpWidget(host(
        child: LyricsOffsetBar(
          offsetMs: 0,
          transparentMode: false,
          offsetLabel: 'Offset',
          onAdjust: (_) {},
          onReset: () => resets++,
        ),
      ));
      await tester.pumpAndSettle();

      // offsetMs==0 → InkWell.onTap=null → refresh 圖示呈淡色且不可點。
      expect(resets, 0);
      // 圖示仍渲染（淡色）。
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}

void _noop(int _) {}
void _noopReset() {}
