import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/backends/just_audio_backend.dart';
import 'package:fmp/playback/backends/media_kit_backend.dart';

/// 兩個音訊後端把原生播放器的錯誤轉成錯誤分類。原生播放器本身在
/// integration_test 裡跑；這裡只測對照表。
void main() {
  group('just_audio codes', () {
    test('ExoPlayer source and remote errors are network errors (fact K3)', () {
      expect(classifyJustAudioError(0), isA<NetworkError>());
      expect(classifyJustAudioError(3), isA<NetworkError>());
    });

    test('ExoPlayer renderer errors are Unsupported', () {
      expect(classifyJustAudioError(1), isA<Unsupported>());
    });

    test('NSURLErrorDomain codes are network errors', () {
      expect(classifyJustAudioError(-1001), isA<NetworkError>()); // 逾時
      expect(classifyJustAudioError(-1009), isA<NetworkError>()); // 沒網路
      expect(classifyJustAudioError(-1100), isA<NetworkError>());
    });

    test('AVFoundation format errors are Unsupported (fact M5)', () {
      expect(classifyJustAudioError(-11828), isA<Unsupported>());
      expect(classifyJustAudioError(-11821), isA<Unsupported>());
    });

    test('anything else is a parse failure', () {
      expect(classifyJustAudioError(2), isA<ParseFailure>());
      expect(classifyJustAudioError(-11800), isA<ParseFailure>());
      expect(classifyJustAudioError(-999), isA<ParseFailure>());
      expect(classifyJustAudioError(-4000), isA<ParseFailure>());
    });
  });

  group('mpv log', () {
    test('lines below error level are not failures', () {
      expect(classifyMpvLog('stream', 'warn', 'slow'), isNull);
      expect(classifyMpvLog('ao', 'info', 'device changed'), isNull);
    });

    test('opening the url fails as a network error', () {
      expect(
        classifyMpvLog('ffmpeg', 'error', 'tcp: Connection refused'),
        isA<NetworkError>(),
      );
      expect(
        classifyMpvLog('stream', 'error', 'Failed to open https://x'),
        isA<NetworkError>(),
      );
      expect(classifyMpvLog('file', 'error', 'not found'), isA<NetworkError>());
    });

    test('ffmpeg errors other than tcp are not failures, like media_kit', () {
      expect(classifyMpvLog('ffmpeg', 'error', 'mov: stray atom'), isNull);
    });

    test('audio output and decoder errors are Unsupported (fact W4: media_kit '
        'does not forward ao)', () {
      expect(
        classifyMpvLog('ao', 'error', 'Could not open device'),
        isA<Unsupported>(),
      );
      expect(classifyMpvLog('ad', 'error', 'decode'), isA<Unsupported>());
      expect(classifyMpvLog('vd', 'fatal', 'decode'), isA<Unsupported>());
    });

    test('player errors are parse failures; unknown prefixes are ignored', () {
      expect(
        classifyMpvLog('cplayer', 'error', 'Failed to recognize file format'),
        isA<ParseFailure>(),
      );
      expect(classifyMpvLog('lua', 'error', 'script'), isNull);
    });
  });
}
