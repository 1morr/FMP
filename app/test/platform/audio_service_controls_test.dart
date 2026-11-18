import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/audio_service_controls.dart';
import 'package:fmp/playback/media_controls.dart';
import 'package:fmp/playback/playback.dart' show PlaybackStatus;

/// audio_service 這一層（Android、iOS、macOS）：[NowPlaying] 轉成它的
/// `MediaItem` 與 `PlaybackState`，它收到的系統指令轉成 [MediaCommand]。
/// 直接用 handler，不經 `AudioService.init`（那要平台）。
void main() {
  late AudioServiceControls controls;
  late List<MediaCommand> commands;

  const track = Track(
    ref: TrackRef(pluginId: 'songs', trackId: 'a'),
    title: 'Title',
    author: 'Author',
    duration: Duration(minutes: 3),
    coverUrl: 'https://img.example.com/a.webp',
  );

  NowPlaying nowPlaying({
    PlaybackStatus status = PlaybackStatus.playing,
    Duration position = const Duration(seconds: 12),
    Duration? duration = const Duration(minutes: 3),
    bool canPrevious = true,
    bool canNext = true,
  }) => NowPlaying(
    track: track,
    status: status,
    position: position,
    duration: duration,
    canPrevious: canPrevious,
    canNext: canNext,
  );

  setUp(() {
    controls = AudioServiceControls();
    commands = [];
    controls.commands.listen(commands.add);
  });

  test('shows the title, author, cover and length as the media item', () {
    controls.show(nowPlaying());

    final item = controls.mediaItem.value!;
    expect(item.title, 'Title');
    expect(item.artist, 'Author');
    expect(item.artUri, Uri.parse('https://img.example.com/a.webp'));
    expect(item.duration, const Duration(minutes: 3));
  });

  test('a playing track shows the pause button, the skip buttons and a '
      'seekable position', () {
    controls.show(nowPlaying());

    final state = controls.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.updatePosition, const Duration(seconds: 12));
    expect(state.controls, [
      MediaControl.skipToPrevious,
      MediaControl.pause,
      MediaControl.skipToNext,
    ]);
    expect(state.androidCompactActionIndices, [0, 1, 2]);
    expect(state.systemActions, contains(MediaAction.seek));
  });

  test('a paused track without neighbours shows only the play button', () {
    controls.show(
      nowPlaying(
        status: PlaybackStatus.paused,
        canPrevious: false,
        canNext: false,
      ),
    );

    final state = controls.playbackState.value;
    expect(state.playing, isFalse);
    expect(state.controls, [MediaControl.play]);
    expect(state.androidCompactActionIndices, [0]);
  });

  test('loading, buffering, finished and failed map to the processing '
      'states', () {
    AudioProcessingState processing(PlaybackStatus status) {
      controls.show(nowPlaying(status: status));
      return controls.playbackState.value.processingState;
    }

    expect(processing(PlaybackStatus.resolving), AudioProcessingState.loading);
    expect(processing(PlaybackStatus.loading), AudioProcessingState.loading);
    expect(
      processing(PlaybackStatus.buffering),
      AudioProcessingState.buffering,
    );
    expect(
      processing(PlaybackStatus.completed),
      AudioProcessingState.completed,
    );
    expect(processing(PlaybackStatus.failed), AudioProcessingState.error);
  });

  test('an unknown length cannot be seeked', () {
    controls.show(nowPlaying(duration: null));

    expect(controls.mediaItem.value!.duration, isNull);
    expect(controls.playbackState.value.systemActions, isEmpty);
  });

  test('nothing playing clears the media item and goes idle', () {
    controls.show(nowPlaying());
    controls.show(null);

    expect(controls.mediaItem.value, isNull);
    expect(
      controls.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
    expect(controls.playbackState.value.playing, isFalse);
  });

  test('the same track does not resend the media item', () async {
    final items = <MediaItem?>[];
    controls.mediaItem.listen(items.add);
    controls.show(nowPlaying());
    controls.show(nowPlaying(position: const Duration(seconds: 40)));
    controls.show(nowPlaying(status: PlaybackStatus.paused));
    await Future<void>.delayed(Duration.zero);

    // BehaviorSubject 先重播目前的值（null），再加上第一次 show 的那個。
    expect(items, hasLength(2));
  });

  test('a length learned later for the same track updates the media item '
      '(MediaItem == only compares the id)', () async {
    final items = <MediaItem?>[];
    controls.mediaItem.listen(items.add);
    controls.show(nowPlaying(duration: null));
    controls.show(nowPlaying(duration: const Duration(minutes: 3)));
    await Future<void>.delayed(Duration.zero);

    expect(items, hasLength(3));
    expect(controls.mediaItem.value!.duration, const Duration(minutes: 3));
  });

  test('system buttons become commands', () async {
    await controls.play();
    await controls.pause();
    await controls.skipToNext();
    await controls.skipToPrevious();
    await controls.seek(const Duration(seconds: 30));
    await Future<void>.delayed(Duration.zero);

    expect(commands, const [
      PlayCommand(),
      PauseCommand(),
      NextCommand(),
      PreviousCommand(),
      SeekCommand(Duration(seconds: 30)),
    ]);
  });

  test('the play/pause media key toggles from what is shown', () async {
    controls.show(nowPlaying());
    await controls.click();
    controls.show(nowPlaying(status: PlaybackStatus.paused));
    await controls.click();
    await Future<void>.delayed(Duration.zero);

    expect(commands, const [PauseCommand(), PlayCommand()]);
  });

  test('stop (dismissing the notification) pauses', () async {
    await controls.stop();
    await Future<void>.delayed(Duration.zero);

    expect(commands, const [PauseCommand()]);
  });
}
