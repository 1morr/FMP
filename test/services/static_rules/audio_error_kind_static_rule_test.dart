import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioController source error kind usage', () {
    test('dispose handles async backend cleanup errors', () {
      final source = File(
        'lib/services/audio/audio_provider.dart',
      ).readAsStringSync();

      // 釋放改由 `ref.onDispose` 觸發，方法名隨之改成 `_teardown`。
      final disposeStart = source.indexOf('void _teardown()');
      expect(disposeStart, isNot(-1));
      final disposeBody = source.substring(disposeStart);

      expect(disposeBody, contains('unawaited('));
      expect(disposeBody, contains('_audioService.dispose().catchError('));
      expect(disposeBody, contains('catchError'));
      expect(disposeBody, contains('logError('));
    });
  });
}
