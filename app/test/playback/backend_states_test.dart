import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
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

    states.reset();

    expect(
      states.current,
      const AudioBackendState(status: AudioBackendStatus.loading),
    );
    states.update((s) => s.copyWith(status: AudioBackendStatus.ready));
    expect(states.current.status, AudioBackendStatus.ready);
  });
}
