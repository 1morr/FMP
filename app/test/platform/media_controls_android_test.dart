import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/media_controls/media_controls_android.dart';

import '../support/pump_until.dart';

NowPlaying nowPlaying({
  MediaPhase phase = MediaPhase.ready,
  bool playing = true,
  List<MediaControl> controls = const [
    MediaControl.previous,
    MediaControl.pause,
    MediaControl.next,
  ],
}) => NowPlaying(
  id: 'fmp-test:a',
  title: 'Song a',
  phase: phase,
  playing: playing,
  position: const Duration(seconds: 12),
  controls: controls,
);

void main() {
  group('a live room', () {
    NowPlaying live({bool seekable = false}) => NowPlaying(
      id: 'fmp-test:room',
      title: 'Room',
      uploader: 'Host',
      phase: MediaPhase.ready,
      playing: true,
      position: const Duration(seconds: 90),
      controls: const [MediaControl.pause],
      seekable: seekable,
    );

    test('has no seek action and only the pause button', () {
      final state = androidPlaybackStateOf(live());

      expect(state.systemActions, {audio.MediaAction.stop});
      expect(state.controls, [audio.MediaControl.pause]);
    });

    test('a seekable song keeps the seek action', () {
      expect(androidPlaybackStateOf(live(seekable: true)).systemActions, {
        audio.MediaAction.seek,
        audio.MediaAction.stop,
      });
      expect(androidPlaybackStateOf(nowPlaying()).systemActions, {
        audio.MediaAction.seek,
        audio.MediaAction.stop,
      });
    });
  });

  group('the playback state', () {
    test('follows the phase and whether it plays', () {
      final idle = androidPlaybackStateOf(
        nowPlaying(phase: MediaPhase.idle, playing: false),
      );
      expect(idle.processingState, audio.AudioProcessingState.idle);
      expect(idle.playing, isFalse);

      expect(
        androidPlaybackStateOf(nowPlaying(phase: MediaPhase.loading))
            .processingState,
        audio.AudioProcessingState.loading,
      );
      expect(
        androidPlaybackStateOf(nowPlaying(phase: MediaPhase.buffering))
            .processingState,
        audio.AudioProcessingState.buffering,
      );
      final ready = androidPlaybackStateOf(nowPlaying());
      expect(ready.processingState, audio.AudioProcessingState.ready);
      expect(ready.playing, isTrue);
      expect(ready.updatePosition, const Duration(seconds: 12));
    });

    test('an interruption is playing and buffering with the pause button', () {
      final state = androidPlaybackStateOf(
        nowPlaying(phase: MediaPhase.interrupted),
      );

      // 播放中：audio_service 的前景服務不放；緩衝中：系統不推算進度。
      expect(state.playing, isTrue);
      expect(state.processingState, audio.AudioProcessingState.buffering);
      expect(state.controls, [
        audio.MediaControl.skipToPrevious,
        audio.MediaControl.pause,
        audio.MediaControl.skipToNext,
      ]);
    });
  });

  group('async errors', () {
    test('are logged under the media controls tag', () async {
      final log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
      final errors = StreamController<Object>.broadcast();
      final subscription = reportAsyncErrors(errors.stream, log);

      errors.add(StateError('Background started FGS'));
      await settle();

      final reported = log.history.where(
        (r) => r.tag == 'media-controls' && r.level == LogLevel.error,
      );
      expect(reported, hasLength(1));
      expect(reported.single.message, contains('system media session'));

      await subscription.cancel();
      errors.add(StateError('after cancel'));
      await settle();
      expect(log.history.where((r) => r.tag == 'media-controls'), hasLength(1));
      await errors.close();
    });
  });

  group('the media key fix', () {
    const channel = MethodChannel('fmp/media_keys');
    late Log log;
    late List<String> calls;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
      calls = [];
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void mock(Future<Object?> Function() reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            calls.add(call.method);
            return reply();
          });
    }

    test('install reports what the native side answered', () async {
      mock(() async => true);
      expect(await MediaKeyFix(log).install(), isTrue);
      expect(calls, ['install']);

      mock(() async => false);
      expect(await MediaKeyFix(log).install(), isFalse);
    });

    test('a missing channel or a platform error is swallowed', () async {
      // 沒有登記處理者：MissingPluginException。
      expect(await MediaKeyFix(log).install(), isFalse);

      mock(() async => throw PlatformException(code: 'boom'));
      expect(await MediaKeyFix(log).install(), isFalse);
      expect(log.history.where((r) => r.level == LogLevel.error), isEmpty);
    });

    test('publish installs on a non-idle state and not on idle', () async {
      mock(() async => true);
      final controls = AndroidSystemMediaControls.forTest(
        log,
        MediaKeyFix(log),
      );

      await controls.publish(nowPlaying(phase: MediaPhase.idle));
      await settle();
      expect(calls, isEmpty);

      await controls.publish(nowPlaying());
      await controls.publish(nowPlaying(playing: false));
      await settle();
      expect(calls, ['install', 'install']);
    });

    test('a failing install does not break publish', () async {
      mock(() async => throw PlatformException(code: 'boom'));
      final controls = AndroidSystemMediaControls.forTest(
        log,
        MediaKeyFix(log),
      );

      await expectLater(controls.publish(nowPlaying()), completes);
      await settle();
    });
  });
}
