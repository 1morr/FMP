import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fmp/ui/widgets/controls/scoped_slider.dart';

void main() {
  // Slider 的數值指示器放進哪個 Overlay，由 Slider 往上找到的第一個 Overlay
  // 決定。落在 Navigator 的 Overlay 時，Windows 的無障礙樹會停止更新。
  testWidgets('the value indicator goes into the slider’s own overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ScopedSlider(value: 0.5, onChanged: (_) {})),
      ),
    );

    final sliderOverlay = Overlay.of(tester.element(find.byType(Slider)));
    final navigatorOverlay = tester
        .state<NavigatorState>(find.byType(Navigator))
        .overlay;

    expect(navigatorOverlay, isNotNull);
    expect(sliderOverlay, isNot(same(navigatorOverlay)));
  });

  testWidgets('drags still report values', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ScopedSlider(
              value: 0.5,
              divisions: 10,
              label: 'label',
              onChanged: values.add,
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ScopedSlider), const Offset(60, 0));
    await tester.pump();

    expect(values, isNotEmpty);
    expect(values.last, greaterThan(0.5));
    expect(tester.takeException(), isNull);
  });
}
