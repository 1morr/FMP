import 'package:fmp/core/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLogger.redactSensitive', () {
    test('redacts eparams (netease encrypted payload) key=value pairs (F7)', () {
      // 對應 netease_playlist_service.dart:373 data: {'eparams': <加密 blob>}。
      const json = "{'eparams': 'ENC-12345abcdef=='}";
      const form = 'eparams=ENC-12345abcdef&foo=bar';
      for (final input in const [json, form]) {
        final out = AppLogger.redactSensitive(input);
        expect(out, contains('[REDACTED]'));
        expect(out, isNot(contains('ENC-12345abcdef')));
      }
    });

    test('redacts apiKey in JSON and query forms (F7)', () {
      const json = '{"apiKey":"sk-live-abcdef123"}';
      const query = 'apiKey=sk-live-abcdef123';

      expect(AppLogger.redactSensitive(json), contains('[REDACTED]'));
      expect(AppLogger.redactSensitive(json), isNot(contains('sk-live-abcdef123')));
      expect(AppLogger.redactSensitive(query), isNot(contains('sk-live-abcdef123')));
    });

    test('preserves existing coverage: SESSDATA / MUSIC_U / Authorization', () {
      // 回歸守護：新增 key 不得削弱既有 redaction。
      expect(
        AppLogger.redactSensitive('SESSDATA=abc123'),
        isNot(contains('abc123')),
      );
      expect(
        AppLogger.redactSensitive('MUSIC_U=deadbeef'),
        isNot(contains('deadbeef')),
      );
      expect(
        AppLogger.redactSensitive('Authorization: Bearer xyz'),
        contains('[REDACTED]'),
      );
    });
  });
}
