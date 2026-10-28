import 'package:audio_service/audio_service.dart' as audio;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/media_controls/media_controls_macos.dart';

NowPlaying nowPlaying({
  MediaPhase phase = MediaPhase.ready,
  Uri? artworkFile,
}) => NowPlaying(
  id: 'fmp-test:a',
  title: 'Song a',
  uploader: 'Up',
  duration: const Duration(minutes: 3),
  phase: phase,
  playing: true,
  position: const Duration(seconds: 12),
  controls: const [MediaControl.pause],
  artworkFile: artworkFile,
);

void main() {
  late MacosSystemMediaControls controls;

  setUp(() {
    controls = MacosSystemMediaControls.forTest(
      Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
    );
  });

  test('publish pushes the media item and the playback state', () async {
    final handler = controls.handlerForTest;

    await controls.publish(nowPlaying(artworkFile: Uri.file('/tmp/cover.jpg')));

    expect(handler.mediaItem.value?.title, 'Song a');
    expect(handler.mediaItem.value?.artist, 'Up');
    expect(handler.mediaItem.value?.artUri, Uri.file('/tmp/cover.jpg'));
    final state = handler.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.processingState, audio.AudioProcessingState.ready);
    expect(state.updatePosition, const Duration(seconds: 12));
  });

  test(
    'an idle state resets the playback state and keeps the media item',
    () async {
      final handler = controls.handlerForTest;

      await controls.publish(nowPlaying());
      await controls.publish(nowPlaying(phase: MediaPhase.idle));

      expect(handler.mediaItem.value?.title, 'Song a');
      expect(
        handler.playbackState.value.processingState,
        audio.AudioProcessingState.idle,
      );
    },
  );
}
