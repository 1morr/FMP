/// `lib/` 裡的 Slider 都要走 `ScopedSlider`，不准直接建 Material 的 Slider。
///
/// Material 的 `Slider` / `RangeSlider` 一建立就把數值指示器放進最近的
/// Overlay。落在 Navigator 的 Overlay 時，Windows 的無障礙樹會停在舊狀態，
/// Narrator 讀不到 App 內容（原因寫在 `ScopedSlider` 的 dartdoc）。
/// 壞掉時畫面正常、測試全綠，只有開報讀器才發現，所以只能靠讀源碼擋。
///
/// **比的是集合。** 在 `ScopedSlider` 以外直接建 Slider 的 (檔案, 建構子) 要是
/// 空集合。換行、`.adaptive` 都認得；`SliderTheme`、`ScopedSlider`、
/// 名字剛好以 Slider 結尾的類別、註解都不算。兩個方向都由本檔最後兩條測試示範。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/dart_source.dart';

/// 唯一可以直接建 Slider 的檔案。
const _scopedSliderPath = 'lib/ui/widgets/controls/scoped_slider.dart';

final _rawSlider = RegExp(
  r'(?<!\w)((?:Range)?Slider(?:\s*\.\s*adaptive)?)\s*\(',
);

/// 直接建了 Material Slider 的地方，格式是 `檔案: 建構子`。
Set<String> rawSliders(Map<String, String> sourcesByPath) => {
  for (final MapEntry(key: path, value: source) in sourcesByPath.entries)
    if (path != _scopedSliderPath)
      for (final match in _rawSlider.allMatches(stripDartComments(source)))
        '$path: ${match.group(1)!.replaceAll(RegExp(r'\s'), '')}',
};

void main() {
  group('slider overlay', () {
    test('every slider in lib goes through ScopedSlider', () {
      final sources = {
        for (final entity in Directory('lib').listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !entity.path.endsWith('.g.dart'))
            entity.path.replaceAll(r'\', '/'): entity.readAsStringSync(),
      };

      // 掃描本身要有作用：路徑寫錯時結果也會是空集合。
      expect(sources.length, greaterThan(300));
      expect(sources[_scopedSliderPath], contains('Slider('));
      expect(
        rawSliders(sources),
        isEmpty,
        reason:
            'Use ScopedSlider: a Slider whose value indicator lands in the '
            "Navigator's Overlay freezes the Windows accessibility tree.",
      );
    });

    test('a raw slider turns the rule red, however it is written', () {
      const offender = '''
final a = Slider(value: 0.5, onChanged: (_) {});
final b = Slider
    .adaptive(
      value: 0.5,
      onChanged: null,
    );
final c = RangeSlider (values: range, onChanged: null);
''';
      const prefixed =
          "final d = material.Slider(value: 0.5, onChanged: null);";

      expect(
        rawSliders({'lib/ui/a.dart': offender, 'lib/ui/b.dart': prefixed}),
        {
          'lib/ui/a.dart: Slider',
          'lib/ui/a.dart: Slider.adaptive',
          'lib/ui/a.dart: RangeSlider',
          'lib/ui/b.dart: Slider',
        },
      );
    });

    test('themes, ScopedSlider, lookalikes and comments do not', () {
      const fine = '''
// 以前寫成 Slider(value: volume)，Narrator 讀不到整個 App。
/// 見 [Slider] 與 Slider(...) 的指示器。
final theme = SliderTheme(data: SliderThemeData(), child: child);
final a = ScopedSlider(value: 0.5, onChanged: (_) {});
final b = _LabeledSlider(value: 0.5);
final c = CupertinoSlider(value: 0.5, onChanged: null);
''';

      expect(rawSliders({'lib/ui/a.dart': fine}), isEmpty);
    });
  });
}
