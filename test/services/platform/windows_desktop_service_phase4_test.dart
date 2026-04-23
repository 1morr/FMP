import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 4 Task 6 Windows close handling and semantics', () {
    late String repoRoot;

    setUp(() {
      repoRoot = Directory.current.path;
    });

    String readSource(String relativePath) {
      return File('$repoRoot/$relativePath').readAsStringSync();
    }

    test('Windows desktop service exposes one close-intent path for both close sources', () {
      final source =
          readSource('lib/services/platform/windows_desktop_service.dart');

      expect(
        source,
        contains(
          'Future<void> handleCloseIntent({required bool fromSystemClose}) async {',
        ),
      );
      expect(
        source,
        contains('Future<void> handleCloseButton() => handleCloseIntent('),
      );
      expect(source, contains('fromSystemClose: false,'));
      expect(
        source,
        contains('void onWindowClose() => unawaited(handleCloseIntent('),
      );
      expect(source, contains('fromSystemClose: true,'));
      expect(
        source,
        isNot(
          contains(
            'Future<void> handleCloseIntent({required bool fromSystemClose}) async {\n    if (!Platform.isWindows || !_isInitialized) return;',
          ),
        ),
      );
      expect(
        source,
        isNot(contains('Future<void> minimizeToTray() async {\n    if (!Platform.isWindows || !_isInitialized) return;')),
      );
    });

    test('custom title bar close button uses unified close-intent handler', () {
      final source = readSource('lib/ui/widgets/custom_title_bar.dart');

      expect(source, contains('service.handleCloseIntent(fromSystemClose: false)'));
      expect(source, isNot(contains('service.handleCloseButton()')));
    });

    test('custom title bar exposes explicit semantics labels for window controls', () {
      final source = readSource('lib/ui/widgets/custom_title_bar.dart');

      expect(source, contains('tooltip: t.general.minimize'));
      expect(source, contains('tooltip: _isMaximized ? t.general.restore : t.general.maximize'));
      expect(source, contains('tooltip: t.general.close'));
      expect(source, contains('Semantics('));
      expect(source, contains('label: widget.tooltip'));
      expect(source, contains('message: widget.tooltip'));
      expect(source, contains('ExcludeSemantics('));
    });

    test('main Windows app tree is no longer wrapped in ExcludeSemantics', () {
      final source = readSource('lib/app.dart');

      expect(
        source,
        isNot(contains('content = ExcludeSemantics(child: content);')),
      );
    });

    test('lyrics window avoids whole-tree semantics exclusion and labels title bar controls', () {
      final source = readSource('lib/ui/windows/lyrics_window.dart');

      expect(source, isNot(contains('return ExcludeSemantics(')));
      expect(source, contains('label: tooltip'));
      expect(source, contains('ExcludeSemantics(child: Icon('));
    });
  });
}
