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

  group('isSelectableOutputDevice', () {
    test('lists the Windows audio devices, not auto or mpv internals', () {
      expect(isSelectableOutputDevice('wasapi/{0.0.0.00000000}.{abc}'), isTrue);
      expect(isSelectableOutputDevice('auto'), isFalse);
      expect(isSelectableOutputDevice('openal'), isFalse);
    });
  });

  group('speed and volume', () {
    test('the speed is clamped to 0.5–2.0', () {
      expect(clampSpeed(1.25), 1.25);
      expect(clampSpeed(0.5), 0.5);
      expect(clampSpeed(2), 2);
      expect(clampSpeed(0.1), minSpeed);
      expect(clampSpeed(3), maxSpeed);
    });

    test('the volume is clamped to 0–1', () {
      expect(clampVolume(0.3), 0.3);
      expect(clampVolume(-0.2), 0);
      expect(clampVolume(1.5), 1);
    });
  });

  // design §7.6：just_audio 0.10.6 的內建處理在 duck 結束時無條件把音量乘 2
  // （`setVolume(min(1.0, volume * 2))`），音樂用途開始 duck 時卻不減半，所以
  // 後端自己處理：duck 只在引擎的輸出減半，使用者的音量不動。
  group('audio interruptions (Android)', () {
    test('each interruption maps to one response', () {
      expect(
        respondToInterruption(begin: true, kind: InterruptionKind.duck),
        InterruptionResponse.duck,
      );
      expect(
        respondToInterruption(begin: false, kind: InterruptionKind.duck),
        InterruptionResponse.unduck,
      );
      expect(
        respondToInterruption(begin: true, kind: InterruptionKind.pause),
        InterruptionResponse.interrupted,
      );
      expect(
        respondToInterruption(begin: true, kind: InterruptionKind.unknown),
        InterruptionResponse.lost,
      );
      expect(
        respondToInterruption(begin: false, kind: InterruptionKind.pause),
        InterruptionResponse.endedResumable,
      );
      expect(
        respondToInterruption(begin: false, kind: InterruptionKind.unknown),
        InterruptionResponse.ended,
      );
    });

    test('a duck halves the output and leaves the user volume alone', () {
      const user = 0.8;
      expect(outputVolume(user, ducked: false), user);
      expect(outputVolume(user, ducked: true), user * duckFactor);
      expect(duckFactor, 0.5);
      // duck 期間改了音量：輸出跟著新的音量減半；duck 結束時回到新的音量，
      // 不是減半前的兩倍。
      const changed = 0.6;
      expect(outputVolume(changed, ducked: true), changed * duckFactor);
      expect(outputVolume(changed, ducked: false), changed);
    });

    // audio_session 0.2.4 的 `setActive`：暫停類、unknown 類中斷開始時把它自己
    // 的 duck 記號歸零，之後拿回焦點報的是暫停類的結束，不是 duck 的結束；
    // unknown 類（`AUDIOFOCUS_LOSS`）原生端直接放掉焦點，之後沒有事件。
    group('the output is halved only during a duck', () {
      bool duckedAfterAll(List<(bool, InterruptionKind)> events) {
        var ducked = false;
        for (final (begin, kind) in events) {
          ducked = duckedAfter(respondToInterruption(begin: begin, kind: kind));
        }
        return ducked;
      }

      test('a duck and its end', () {
        expect(duckedAfterAll([(true, InterruptionKind.duck)]), isTrue);
        expect(
          duckedAfterAll([
            (true, InterruptionKind.duck),
            (false, InterruptionKind.duck),
          ]),
          isFalse,
        );
      });

      test('a duck that turns into a pause ends at full volume', () {
        expect(
          duckedAfterAll([
            (true, InterruptionKind.duck),
            (true, InterruptionKind.pause),
            (false, InterruptionKind.pause),
          ]),
          isFalse,
        );
      });

      test('a duck followed by a permanent loss is not left halved', () {
        expect(
          duckedAfterAll([
            (true, InterruptionKind.duck),
            (true, InterruptionKind.unknown),
          ]),
          isFalse,
        );
      });
    });
  });

  // 樣本是 2026-10-07 在 Windows 以 media_kit 1.2.6（libmpv，`MPVLogLevel.warn`）
  // 選一個不存在的 WASAPI 裝置（開流時與播放中各一次）錄下的 `PlayerLog`。兩次都
  // 是同一串：`[ao/wasapi]`、三行 `[ao]`、`[cplayer]`，`[cplayer]` 那一行同時進
  // media_kit 的 error stream；`completed` 在它們之前或之間送到。
  group('isOutputDeviceFailure', () {
    test('the lines mpv writes when the audio output cannot be opened', () {
      for (final (prefix, text) in [
        (
          'ao/wasapi',
          "Failed to find device '{00000000-0000-0000-0000-000000000000}'",
        ),
        ('ao', "Failed to initialize audio driver 'wasapi'"),
        (
          'ao',
          'This audio driver/device was forced with the --audio-device '
              'option.',
        ),
        ('ao', 'Try unsetting it.'),
        ('cplayer', 'Could not open/initialize audio device -> no sound.'),
      ]) {
        expect(
          isOutputDeviceFailure(prefix: prefix, level: 'error', text: text),
          isTrue,
          reason: '[$prefix] $text',
        );
      }
      expect(
        isOutputDeviceFailureMessage(
          'Could not open/initialize audio device -> no sound.',
        ),
        isTrue,
      );
    });

    test('other lines are not', () {
      for (final (prefix, level, text) in [
        // 同一次錄音裡與裝置無關的兩行。
        ('lavf', 'error', 'Failed to create file cache.'),
        ('playlist', 'warn', 'Reading plaintext playlist.'),
        // 開不起來的來源（舊專案 issue #41：「could not open」不是裝置）。
        ('stream', 'error', 'Failed to open http://127.0.0.1:1/a.wav.'),
        ('cplayer', 'error', 'Failed to recognize file format.'),
        // 層級不是 error、名稱只是 ao 開頭。
        ('ao', 'warn', "Failed to initialize audio driver 'wasapi'"),
        ('aoutput', 'error', 'x'),
      ]) {
        expect(
          isOutputDeviceFailure(prefix: prefix, level: level, text: text),
          isFalse,
          reason: '[$prefix] $level: $text',
        );
      }
      expect(isOutputDeviceFailureMessage('Failed to open x.'), isFalse);
      expect(
        isOutputDeviceFailureMessage('tcp: Connection to tcp://x failed'),
        isFalse,
      );
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
