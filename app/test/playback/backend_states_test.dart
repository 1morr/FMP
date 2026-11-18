import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/backends/backend_states.dart';

/// 兩個音訊後端共用的狀態保管。
void main() {
  late BackendStates states;
  late List<AudioBackendState> emitted;

  setUp(() {
    states = BackendStates();
    emitted = [];
    states.stream.listen(emitted.add);
  });
  tearDown(() => states.close());

  const error = AudioBackendError(NetworkError(), 'code 0');
  final first = AudioStream(url: Uri.parse('https://cdn.example.com/1.m4a'));
  final next = AudioStream(url: Uri.parse('https://cdn.example.com/2.m4a'));

  test(
    'emits each change once and skips updates that change nothing',
    () async {
      states.update((s) => s.copyWith(status: AudioBackendStatus.ready));
      states.update((s) => s.copyWith(status: AudioBackendStatus.ready));
      states.update((s) => s.copyWith(position: const Duration(seconds: 1)));
      await pumpEventQueue();

      expect(emitted, hasLength(2));
      expect(states.current.position, const Duration(seconds: 1));
    },
  );

  test('a failure sticks until the next load, whatever the player reports '
      'after it', () async {
    states.update(
      (s) => s.copyWith(status: AudioBackendStatus.ready, playing: true),
    );
    states.fail(error);
    states.update((s) => s.copyWith(status: AudioBackendStatus.idle));
    states.fail(const AudioBackendError(Unsupported(), 'later'));
    await pumpEventQueue();

    expect(states.current.status, AudioBackendStatus.failed);
    expect(states.current.playing, isFalse);
    expect(states.current.error, error);
    expect(emitted.last.error, error);
  });

  test('reset starts a new load from a clean state', () async {
    states.update(
      (s) => s.copyWith(
        status: AudioBackendStatus.ready,
        position: const Duration(seconds: 9),
        duration: () => const Duration(minutes: 2),
      ),
    );
    states.fail(error);

    states.reset(next);

    expect(
      states.current,
      AudioBackendState(stream: next, status: AudioBackendStatus.loading),
    );
    states.update((s) => s.copyWith(status: AudioBackendStatus.ready));
    expect(states.current.status, AudioBackendStatus.ready);
  });

  test('when the player moves on to the preloaded stream by itself, the '
      'current one completes first, then the states are the next one\'s, '
      'still playing', () async {
    states
      ..reset(first)
      ..update(
        (s) => s.copyWith(
          status: AudioBackendStatus.ready,
          playing: true,
          position: const Duration(minutes: 3),
          duration: () => const Duration(minutes: 3),
        ),
      );
    await pumpEventQueue();
    emitted.clear();

    states.advancedTo(next);
    await pumpEventQueue();

    expect(emitted.map((s) => (s.stream, s.status)), [
      (first, AudioBackendStatus.completed),
      (next, AudioBackendStatus.buffering),
    ]);
    expect(states.current.playing, isTrue);
    expect(states.current.position, Duration.zero);
    expect(states.current.duration, isNull);
  });

  test('after moving on by itself, positions the player still reports for '
      'the finished stream are dropped until the next one reports its own', () {
    states
      ..reset(first)
      ..update(
        (s) => s.copyWith(
          status: AudioBackendStatus.ready,
          playing: true,
          duration: () => const Duration(minutes: 49),
        ),
      )
      ..position(const Duration(minutes: 49));

    states
      ..advancedTo(next)
      // AVPlayer 實測：接過去後還報了一次上一條結尾再往後的位置。
      ..position(const Duration(minutes: 49, milliseconds: 84));
    expect(states.current.position, Duration.zero);

    states.position(const Duration(milliseconds: 4));
    expect(states.current.position, const Duration(milliseconds: 4));
    states.position(const Duration(seconds: 2));
    expect(states.current.position, const Duration(seconds: 2));
  });
}
