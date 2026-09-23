import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Windows close handling and semantics', () {
    late String repoRoot;

    setUp(() {
      repoRoot = Directory.current.path;
    });

    String readSource(String relativePath) {
      return File('$repoRoot/$relativePath').readAsStringSync();
    }

    test(
      'custom title bar exposes explicit semantics labels for window controls',
      () {
        final source = readSource(
          'lib/ui/widgets/app_bars/custom_title_bar.dart',
        );

        expect(source, contains('tooltip: t.general.minimize'));
        expect(
          source,
          contains(
            'tooltip: _isMaximized ? t.general.restore : t.general.maximize',
          ),
        );
        expect(source, contains('tooltip: t.general.close'));
        expect(source, contains('Semantics('));
        expect(source, contains('label: widget.tooltip'));
        expect(source, contains('message: widget.tooltip'));
        expect(source, contains('excludeFromSemantics: true'));
        expect(source, contains('ExcludeSemantics('));
      },
    );

    test(
      'lyrics window avoids whole-tree semantics exclusion and labels title bar controls',
      () {
        final source = readSource('lib/ui/windows/lyrics_window.dart');

        // 整棵樹不得包 ExcludeSemantics（標題列控制項的語意必須可及）。
        expect(source, isNot(contains('return ExcludeSemantics(')));

        // 標題列控制項的 Semantics/Tooltip 邏輯已抽到 `lyrics_title_bar.dart`，
        // 於該檔驗證每個按鈕仍有 label + excludeFromSemantics + ExcludeSemantics。
        final titleBar = readSource(
          'lib/ui/windows/lyrics/lyrics_title_bar.dart',
        );
        expect(titleBar, contains('label: tooltip'));
        expect(titleBar, contains('excludeFromSemantics: true'));
        expect(
          titleBar,
          matches(RegExp(r'ExcludeSemantics\(\s*child: Icon\(')),
        );
      },
    );
  });
}
