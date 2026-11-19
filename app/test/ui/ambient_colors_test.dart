import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/player/ambient_colors.dart';

/// 播放頁背景的封面色（`docs/design/DESIGN.md`〈封面色只用在播放頁背景〉）：
/// 從封面像素取三色；取不到時用稿的預設。
void main() {
  /// [count] 個 RGBA 像素，第 i 個的顏色由 [color] 給。
  Uint8List pixels(int count, List<int> Function(int i) color) {
    final out = Uint8List(count * 4);
    for (var i = 0; i < count; i++) {
      final c = color(i);
      out.setRange(i * 4, i * 4 + 4, c);
    }
    return out;
  }

  /// 兩個顏色的各色版差不超過 [tolerance]。
  Matcher near(Color expected, [int tolerance = 8]) => predicate<Color>((c) {
    int ch(double v) => (v * 255).round();
    return (ch(c.r) - ch(expected.r)).abs() <= tolerance &&
        (ch(c.g) - ch(expected.g)).abs() <= tolerance &&
        (ch(c.b) - ch(expected.b)).abs() <= tolerance;
  }, 'is within $tolerance of $expected');

  group('ambientColorsFromRgba', () {
    test('the most common colour is the base, the next two distinct ones '
        'are second and third', () {
      // 紅 50、藍 30、綠 15、近似紅（差距不到 48）5。
      const red = [200, 40, 40, 255];
      const blue = [40, 40, 200, 255];
      const green = [40, 200, 40, 255];
      const nearRed = [190, 50, 50, 255];
      final rgba = pixels(100, (i) {
        if (i < 50) return red;
        if (i < 80) return blue;
        if (i < 95) return green;
        return nearRed;
      });

      final colors = ambientColorsFromRgba(rgba);

      expect(colors.base, near(const Color.fromARGB(255, 200, 40, 40), 1));
      expect(colors.second, near(const Color.fromARGB(255, 40, 40, 200), 1));
      expect(colors.third, near(const Color.fromARGB(255, 40, 200, 40), 1));
    });

    test('a colour too close to one already picked is skipped', () {
      // 近似紅比藍多，但離底色紅太近，所以第二色是藍。
      const red = [200, 40, 40, 255];
      const nearRed = [190, 50, 50, 255];
      const blue = [40, 40, 200, 255];
      final rgba = pixels(100, (i) {
        if (i < 50) return red;
        if (i < 80) return nearRed;
        return blue;
      });

      final colors = ambientColorsFromRgba(rgba);

      expect(colors.second, near(const Color.fromARGB(255, 40, 40, 200), 1));
      expect(
        colors.second,
        isNot(near(const Color.fromARGB(255, 190, 50, 50))),
      );
    });

    test('a single-colour image gets a lighter and a darker shade of the '
        'base', () {
      const grey = [120, 120, 120, 255];
      final colors = ambientColorsFromRgba(pixels(64, (_) => grey));

      expect(colors.base, near(const Color.fromARGB(255, 120, 120, 120), 1));
      expect(colors.second, isNot(colors.base));
      expect(colors.third, isNot(colors.base));
      expect(colors.second, isNot(colors.third));
      final lightness = [
        HSLColor.fromColor(colors.second).lightness,
        HSLColor.fromColor(colors.third).lightness,
      ];
      final base = HSLColor.fromColor(colors.base).lightness;
      expect(lightness.any((l) => l > base), isTrue);
      expect(lightness.any((l) => l < base), isTrue);
    });

    test('fully transparent pixels give the fallback', () {
      final rgba = pixels(32, (_) => [10, 20, 30, 0]);
      expect(ambientColorsFromRgba(rgba), AmbientColors.fallback);
    });

    test('empty input gives the fallback', () {
      expect(ambientColorsFromRgba(Uint8List(0)), AmbientColors.fallback);
    });
  });

  group('ambientColorsProvider', () {
    /// 左邊 3/4 是 [left]、右邊 1/4 是 [right] 的 64×64 PNG。
    Future<Uint8List> png(Color left, Color right) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawRect(const Rect.fromLTWH(0, 0, 48, 64), Paint()..color = left)
        ..drawRect(const Rect.fromLTWH(48, 0, 16, 64), Paint()..color = right);
      final image = await recorder.endRecording().toImage(64, 64);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    ProviderContainer containerWith(ImageProvider Function(String) loader) {
      final container = ProviderContainer(
        overrides: [coverImageLoaderProvider.overrideWithValue(loader)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('no cover url gives the fallback', () async {
      final container = containerWith((_) => MemoryImage(Uint8List(0)));
      expect(
        await container.read(ambientColorsProvider(null).future),
        AmbientColors.fallback,
      );
    });

    testWidgets('a cover that fails to decode gives the fallback', (
      tester,
    ) async {
      final container = containerWith(
        (_) => MemoryImage(Uint8List.fromList([1, 2, 3, 4, 5])),
      );
      final colors = await tester.runAsync(
        () => container.read(ambientColorsProvider('cover').future),
      );
      expect(colors, AmbientColors.fallback);
    });

    testWidgets('the base is the dominant colour of the cover', (tester) async {
      const dominant = Color(0xFFC83C3C);
      const accent = Color(0xFF2850D2);
      final bytes = (await tester.runAsync(() => png(dominant, accent)))!;
      final container = containerWith((_) => MemoryImage(bytes));

      final colors = await tester.runAsync(
        () => container.read(ambientColorsProvider('cover').future),
      );

      expect(colors!.base, near(dominant));
      expect(colors.second, near(accent));
    });
  });
}
