import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/backends/backend_rules.dart';

void main() {
  group('classifyTrackEnd', () {
    const duration = Duration(seconds: 200);

    test('the end within the tolerance is completed', () {
      expect(
        classifyTrackEnd(position: duration, duration: duration),
        TrackEndReason.completed,
      );
      expect(
        classifyTrackEnd(
          position: duration - completionTolerance,
          duration: duration,
        ),
        TrackEndReason.completed,
      );
    });

    test('stopping before the tolerance is an early end', () {
      expect(
        classifyTrackEnd(
          position:
              duration - completionTolerance - const Duration(milliseconds: 1),
          duration: duration,
        ),
        TrackEndReason.endedEarly,
      );
      expect(
        classifyTrackEnd(
          position: const Duration(seconds: 30),
          duration: duration,
        ),
        TrackEndReason.endedEarly,
      );
    });

    test('a duration never reported is an early end', () {
      expect(
        classifyTrackEnd(position: Duration.zero, duration: null),
        TrackEndReason.endedEarly,
      );
      expect(
        classifyTrackEnd(position: Duration.zero, duration: Duration.zero),
        TrackEndReason.endedEarly,
      );
    });
  });

  group('LookAheadEdit', () {
    test('appends to a playlist holding only the current source', () {
      final edit = LookAheadEdit.of(
        itemCount: 1,
        currentIndex: 0,
        append: true,
      );
      expect(edit.removeIndices, isEmpty);
      expect(edit.append, isTrue);
    });

    test('replaces an existing look-ahead', () {
      final edit = LookAheadEdit.of(
        itemCount: 2,
        currentIndex: 0,
        append: true,
      );
      expect(edit.removeIndices, [1]);
      expect(edit.append, isTrue);
    });

    test('after a handover trims the played source, highest index first', () {
      final edit = LookAheadEdit.of(
        itemCount: 3,
        currentIndex: 1,
        append: false,
      );
      expect(edit.removeIndices, [2, 0]);
      expect(edit.append, isFalse);
    });

    test('applying it leaves the current source first and one look-ahead', () {
      // 照順序套用到一份清單上，結果是 [目前, 新前瞻]。
      for (final (count, current) in [(1, 0), (2, 0), (2, 1), (4, 2)]) {
        final playlist = [for (var i = 0; i < count; i++) 'item$i'];
        final edit = LookAheadEdit.of(
          itemCount: count,
          currentIndex: current,
          append: true,
        );
        for (final index in edit.removeIndices) {
          playlist.removeAt(index);
        }
        if (edit.append) playlist.add('next');
        expect(playlist, ['item$current', 'next'], reason: '$count/$current');
      }
    });

    test('does nothing without a current source', () {
      for (final (count, current) in [(0, 0), (2, -1), (2, 2)]) {
        final edit = LookAheadEdit.of(
          itemCount: count,
          currentIndex: current,
          append: true,
        );
        expect(edit.removeIndices, isEmpty);
        expect(edit.append, isFalse);
      }
    });
  });

  // 樣本是 2026-10-06 在 Windows 以 media_kit 1.2.6（libmpv，`PlayerConfiguration
  // (logLevel: MPVLogLevel.warn)`）對 loopback HTTP 伺服器錄下的 `PlayerLog.text`。
  group('httpStatusFromLogLine', () {
    test('reads the status from the ffmpeg HTTP error lines mpv passes on', () {
      // [ffmpeg] warn：伺服器回 403、404。
      expect(httpStatusFromLogLine('http: HTTP error 403 Forbidden'), 403);
      expect(httpStatusFromLogLine('http: HTTP error 404 Not Found'), 404);
    });

    test('other failures have no status', () {
      for (final line in [
        // [stream] error：緊接在 403 那一行之後，網址裡的數字不是狀態碼。
        'Failed to open http://127.0.0.1:51442/forbidden.wav.',
        // [ffmpeg] error：連不上（Windows 的 -138 是逾時）。
        'tcp: Connection to tcp://127.0.0.1:1 failed: Error number -138 '
            'occurred',
        // [lavf] error：本機檔案也會有的一行。
        'Failed to create file cache.',
        // just_audio 在 Android 對同一個 403 給的 PlayerException（模擬器錄下）。
        '(0) Source error',
      ]) {
        expect(httpStatusFromLogLine(line), isNull, reason: line);
      }
    });
  });

  group('BackendSource', () {
    test('keeps only the media headers (ADR 0012)', () {
      final source = BackendSource(
        id: 1,
        url: Uri.parse('https://cdn.example/a.m4a'),
        headers: {
          'Referer': 'https://www.example.test/',
          'User-Agent': 'FMP',
          'Cookie': 'SESSDATA=FAKE_SESSDATA_123',
          'Authorization': 'Bearer FAKE_TOKEN',
          'X-Custom-Token': 'FAKE',
        },
      );
      expect(source.headers, {
        'Referer': 'https://www.example.test/',
        'User-Agent': 'FMP',
      });
      expect(() => source.headers['Cookie'] = 'x', throwsUnsupportedError);
    });
  });
}
