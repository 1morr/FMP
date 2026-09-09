import 'package:fmp/core/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLogger.redactSensitive', () {
    test('redacts eparams (netease encrypted payload) key=value pairs', () {
      // 對應 netease_playlist_service.dart:373 data: {'eparams': <加密 blob>}。
      const json = "{'eparams': 'ENC-12345abcdef=='}";
      const form = 'eparams=ENC-12345abcdef&foo=bar';
      for (final input in const [json, form]) {
        final out = AppLogger.redactSensitive(input);
        expect(out, contains('[REDACTED]'));
        expect(out, isNot(contains('ENC-12345abcdef')));
      }
    });

    test('redacts apiKey in JSON and query forms', () {
      const json = '{"apiKey":"sk-live-abcdef123"}';
      const query = 'apiKey=sk-live-abcdef123';

      expect(AppLogger.redactSensitive(json), contains('[REDACTED]'));
      expect(
        AppLogger.redactSensitive(json),
        isNot(contains('sk-live-abcdef123')),
      );
      expect(
        AppLogger.redactSensitive(query),
        isNot(contains('sk-live-abcdef123')),
      );
    });

    test('redacts the bare csrf parameter, not just __csrf', () {
      // Bilibili 的写操作把 bili_jct 的值当作裸 csrf 参数发出
      // （bilibili_favorites_service.dart:131/169/200，
      // bilibili_account_service.dart:351/399）。遮蔽清单原本只有 __csrf，
      // 这条路径上的 token 会原样进日志。
      expect(
        AppLogger.redactSensitive('POST /x/v3/fav/resource/deal csrf=abc123'),
        isNot(contains('abc123')),
      );
      expect(
        AppLogger.redactSensitive('{"csrf": "abc123", "media_id": 42}'),
        isNot(contains('abc123')),
      );
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
