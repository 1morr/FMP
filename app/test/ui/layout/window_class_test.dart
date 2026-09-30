import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/layout/window_class.dart';

void main() {
  group('forWidth uses the M3 breakpoints', () {
    for (final (width, expected) in [
      (0.0, WindowClass.compact),
      (599.9, WindowClass.compact),
      (600.0, WindowClass.medium),
      (839.9, WindowClass.medium),
      (840.0, WindowClass.expanded),
      (1199.9, WindowClass.expanded),
      (1200.0, WindowClass.large),
      (1599.9, WindowClass.large),
      (1600.0, WindowClass.extraLarge),
      (double.infinity, WindowClass.extraLarge),
    ]) {
      test('$width is ${expected.name}', () {
        expect(WindowClass.forWidth(width), expected);
      });
    }
  });

  group('WindowClassScope', () {
    /// 在 [width] 寬的區域放一個 scope，子樹是同一個 [probe] 實例：它只在
    /// 依賴的等級改變時重建。
    Future<void> pumpAt(WidgetTester tester, double width, Widget probe) =>
        tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: WindowClassScope(child: probe),
              ),
            ),
          ),
        );

    Widget probeInto(List<WindowClass> seen) => Builder(
      builder: (context) {
        seen.add(WindowClass.of(context));
        return const SizedBox.shrink();
      },
    );

    testWidgets('measures the space it is given, not the screen', (
      tester,
    ) async {
      final seen = <WindowClass>[];
      await pumpAt(tester, 700, probeInto(seen));

      expect(seen, [WindowClass.medium]);
    });

    testWidgets('rebuilds dependents only when the class changes', (
      tester,
    ) async {
      final seen = <WindowClass>[];
      final probe = probeInto(seen);
      // 測試畫面寬 800，寬度都在它之內。
      await pumpAt(tester, 500, probe);
      await pumpAt(tester, 550, probe);
      await pumpAt(tester, 700, probe);

      expect(seen, [WindowClass.compact, WindowClass.medium]);
    });
  });
}
