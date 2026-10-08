import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio;
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
}
