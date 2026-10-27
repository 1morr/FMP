import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/plugins/source_icon.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

// 音源圖示（U PR 13，ADR 0035，R7.5、R7.10）：manifest 的 `icon`（`data:` 直接解碼、`https` 經插件的
// 媒體 client），沒有或讀不到時是名稱的縮寫。

/// 1×1 的 PNG。
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<void> _show(
  WidgetTester tester, {
  Uri? icon,
  String name = 'Test Source',
  String pluginId = 'fmp-test',
}) async {
  final plugin = FakeSourcePlugin((_) => [], name: name, icon: icon);
  final h = ShellHarness(sources: [plugin], registryOfSources: true);
  await h.pumpApp(
    tester,
    Scaffold(
      body: Center(child: SourceIcon(pluginId: pluginId, size: 24)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('sourceAbbreviation', () {
    test('two words: their initials; one word: its first two characters; '
        'upper case', () {
      expect(sourceAbbreviation('Bilibili Music'), 'BM');
      expect(sourceAbbreviation('Test Source'), 'TS');
      expect(sourceAbbreviation('youtube'), 'YO');
      expect(sourceAbbreviation('fmp-test'), 'FT');
      expect(sourceAbbreviation('NetEase'), 'NE');
    });

    test('Chinese names take their first two characters', () {
      expect(sourceAbbreviation('嗶哩嗶哩'), '嗶哩');
      expect(sourceAbbreviation('網易雲'), '網易');
    });

    test('a short or empty name is kept or a question mark', () {
      expect(sourceAbbreviation('x'), 'X');
      expect(sourceAbbreviation(''), '?');
      expect(sourceAbbreviation('  - '), '?');
    });
  });

  group('SourceIcon', () {
    testWidgets('without an icon it is the abbreviation', (tester) async {
      await _show(tester);

      expect(find.text('TS'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a data icon is decoded and shown instead of the '
        'abbreviation', (tester) async {
      await _show(
        tester,
        icon: Uri.parse('data:image/png;base64,${base64Encode(_png)}'),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('TS'), findsNothing);
    });

    testWidgets('an https icon is read through the plugin like an '
        'artwork', (tester) async {
      await _show(tester, icon: Uri.parse('https://cdn.example/icon.png'));

      final image = tester.widget<ArtworkImage>(find.byType(ArtworkImage));
      expect(image.pluginId, 'fmp-test');
      expect(
        image.artwork.single.url.toString(),
        'https://cdn.example/icon.png',
      );
      // 讀不到（測試裡沒有 cache manager）時是縮寫。
      expect(find.text('TS'), findsOneWidget);
    });

    testWidgets('an icon that is not a bitmap falls back to the abbreviation', (
      tester,
    ) async {
      await _show(
        tester,
        icon: Uri.parse('data:image/svg+xml;base64,PHN2Zz48L3N2Zz4='),
      );

      expect(find.text('TS'), findsOneWidget);
    });

    testWidgets('a plugin that is not in the list uses its id', (tester) async {
      await _show(tester, pluginId: 'gone-plugin');

      expect(find.text('GP'), findsOneWidget);
    });
  });
}
