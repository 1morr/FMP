import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/breakpoints.dart';

void main() {
  group('WindowClass.of', () {
    test('maps the M3 boundaries, inclusive at each lower bound', () {
      final cases = <double, WindowClass>{
        0: WindowClass.compact,
        599: WindowClass.compact,
        600: WindowClass.medium,
        839: WindowClass.medium,
        840: WindowClass.expanded,
        1199: WindowClass.expanded,
        1200: WindowClass.large,
        1599: WindowClass.large,
        1600: WindowClass.extraLarge,
        3440: WindowClass.extraLarge,
      };
      for (final entry in cases.entries) {
        expect(
          WindowClass.of(entry.key),
          entry.value,
          reason: '${entry.key}dp',
        );
      }
    });

    test('840 and 1600 are the bounds that FMP used to be missing', () {
      // 1920 螢幕貼半邊 = 960dp，以前和 600dp 拿到完全一樣的版面。
      expect(WindowClass.of(960), WindowClass.expanded);
    });
  });

  group('WindowClass.atLeast', () {
    test('orders by the declared sequence', () {
      expect(WindowClass.expanded.atLeast(WindowClass.medium), isTrue);
      expect(WindowClass.expanded.atLeast(WindowClass.expanded), isTrue);
      expect(WindowClass.expanded.atLeast(WindowClass.large), isFalse);
      expect(WindowClass.compact.atLeast(WindowClass.compact), isTrue);
    });
  });

  group('columnsFor', () {
    test('counts how many ideal columns fit in the container', () {
      final cases = <double, int>{
        0: 1,
        399: 1,
        400: 1,
        599: 1,
        800: 2,
        868: 2,
        1199: 2,
        1200: 3,
        1700: 3,
        3440: 3,
      };
      for (final entry in cases.entries) {
        expect(columnsFor(entry.key), entry.value, reason: '${entry.key}dp');
      }
    });

    test(
      'an unbounded container falls on the column cap, it does not throw',
      () {
        // `floor()` 對 infinity 會拋 UnsupportedError，所以先夾再取整。
        expect(columnsFor(double.infinity), 3);
      },
    );

    test('a wide window with a wide panel still asks the container', () {
      // 這正是舊的「視窗級距直接當欄數」模型測不到的情境：視窗 1700、
      // 面板 500、導覽軌 72、spacer 24 —— 內容區 1104dp 是兩欄，不是視窗
      // 級距說的三欄。
      expect(columnsFor(1700 - 500 - 72 - 24), 2);
    });
  });
}
