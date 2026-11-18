import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/plugins/plugins.dart';

import '../support/fake_audio_backend.dart';
import '../support/fake_http.dart';
import '../support/fjs.dart';

/// 播放（`playback/`）經 [playbackProvider] 測：插件跑在真的引擎裡、寫在這裡，
/// 音訊後端換成 [FakeAudioBackend]。零聯網。
void main() {
  late Directory logDir;
  late Log log;
  late PluginHost host;
  late FakeAudioBackend backend;
  late ProviderContainer container;

  const playable = Track(
    ref: TrackRef(pluginId: 'songs', trackId: 'ok'),
    title: 'Ok',
    author: 'A',
  );

  setUpAll(loadFjsForTests);
  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_playback_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    host = PluginHost(
      bundles: [
        PluginBundle(
          manifest: jsonEncode({
            'id': 'songs',
            'name': 'Songs',
            'version': '1.0.0',
            'capabilities': ['search', 'resolveStream'],
            'domains': ['api.example.com'],
          }),
          code: '''
            export async function search() { return { tracks: [] }; }
            export async function resolveStream({ trackId }) {
              if (trackId === 'gone') throw new PluginError('not_found');
              return {
                url: 'https://cdn.example.com/' + trackId + '.m4a',
                headers: { Referer: 'https://example.com' },
                codec: 'mp4a.40.2',
              };
            }
          ''',
        ),
      ],
      log: log,
      httpAdapter: FakeHttp((_) => const FakeResponse(404)),
    );
    backend = FakeAudioBackend();
    container = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(log),
        pluginHostProvider.overrideWith((_) => host),
        audioBackendProvider.overrideWithValue(backend),
        stallWarningAfterProvider.overrideWithValue(
          const Duration(milliseconds: 200),
        ),
      ],
      retry: (_, _) => null,
    );
  });
  tearDown(() async {
    container.dispose();
    await host.close();
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  PlaybackState? current() => container.read(playbackProvider);
  Playback playback() => container.read(playbackProvider.notifier);

  Future<String> closeAndReadLog() async {
    await log.close();
    return File('${logDir.path}/${Log.fileName}').readAsStringSync();
  }

  test('nothing is playing before the first track', () {
    expect(current(), isNull);
  });

  test('playing a track resolves its stream through the plugin, loads it '
      'with the headers and starts playing', () async {
    final statuses = <PlaybackStatus>[];
    container.listen(playbackProvider, (_, next) => statuses.add(next!.status));

    await playback().play(playable);

    expect(backend.calls, ['load', 'play']);
    final stream = backend.loaded.single;
    expect(stream.url, Uri.parse('https://cdn.example.com/ok.m4a'));
    expect(stream.headers, {'Referer': 'https://example.com'});
    expect(current()!.track, playable);
    expect(current()!.stream, stream);
    expect(current()!.status, PlaybackStatus.playing);
    expect(current()!.duration, const Duration(minutes: 3));
    expect(statuses.first, PlaybackStatus.resolving);
    expect(statuses, contains(PlaybackStatus.loading));
  });

  test('pause and resume go through the backend', () async {
    await playback().play(playable);

    await playback().pause();
    expect(current()!.status, PlaybackStatus.paused);

    await playback().resume();
    expect(current()!.status, PlaybackStatus.playing);
    expect(backend.calls, ['load', 'play', 'pause', 'play']);
  });

  group('playPause', () {
    test('pauses what plays and resumes what is paused', () async {
      await playback().play(playable);

      await playback().playPause();
      expect(current()!.status, PlaybackStatus.paused);
      await playback().playPause();
      expect(current()!.status, PlaybackStatus.playing);
      expect(backend.calls, ['load', 'play', 'pause', 'play']);
    });

    test('plays a finished track again from the start', () async {
      await playback().play(playable);
      backend.emit(
        backend.state.copyWith(status: AudioBackendStatus.completed),
      );

      await playback().playPause();
      expect(backend.calls, ['load', 'play', 'load', 'play']);
      expect(current()!.status, PlaybackStatus.playing);
    });

    test('retries a track that failed', () async {
      await playback().play(
        const Track(
          ref: TrackRef(pluginId: 'songs', trackId: 'gone'),
          title: 'Gone',
          author: 'B',
        ),
      );
      expect(current()!.status, PlaybackStatus.failed);
      final statuses = <PlaybackStatus>[];
      container.listen(
        playbackProvider,
        (_, next) => statuses.add(next!.status),
      );

      await playback().playPause();
      expect(statuses, [PlaybackStatus.resolving, PlaybackStatus.failed]);
    });

    test('does nothing before the first track', () async {
      await playback().playPause();
      expect(current(), isNull);
      expect(backend.calls, isEmpty);
    });
  });

  test('a stale completion while the next stream loads is ignored', () async {
    backend.holdLoad = Completer<void>();
    final playing = playback().play(playable);
    for (var i = 0; i < 100 && backend.calls.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(current()!.status, PlaybackStatus.loading);

    backend.emit(backend.state.copyWith(status: AudioBackendStatus.completed));
    expect(current()!.status, PlaybackStatus.loading);

    backend.holdLoad!.complete();
    await playing;
    expect(current()!.status, PlaybackStatus.playing);
  });

  test('stopping while a stream resolves never starts it', () async {
    final playing = playback().play(playable);
    expect(current()!.status, PlaybackStatus.resolving);

    await playback().stop();
    await playing;

    expect(current(), isNull);
    expect(backend.calls, isNot(contains('load')));
  });

  test('the backend state drives buffering, position and completion', () async {
    await playback().play(playable);

    backend.emit(backend.state.copyWith(status: AudioBackendStatus.buffering));
    expect(current()!.status, PlaybackStatus.buffering);

    backend.emit(
      backend.state.copyWith(
        status: AudioBackendStatus.ready,
        position: const Duration(seconds: 7),
      ),
    );
    expect(current()!.status, PlaybackStatus.playing);
    expect(current()!.position, const Duration(seconds: 7));

    backend.emit(
      backend.state.copyWith(
        status: AudioBackendStatus.completed,
        playing: false,
      ),
    );
    expect(current()!.status, PlaybackStatus.completed);
  });

  group('the shown length', () {
    const long = Track(
      ref: TrackRef(pluginId: 'songs', trackId: 'long'),
      title: 'Long',
      author: 'A',
      duration: Duration(minutes: 59, seconds: 33),
    );
    const other = Track(
      ref: TrackRef(pluginId: 'songs', trackId: 'other'),
      title: 'Other',
      author: 'A',
      duration: Duration(minutes: 3, seconds: 8),
    );

    test(
      'is the track\'s own when the backend reports a much shorter one',
      () async {
        // AVPlayer 遇到 CDN 中途斷線時把長度截短（事實 M14）。
        backend.loadedDuration = const Duration(minutes: 33, seconds: 10);
        await playback().play(long);

        expect(current()!.effectiveDuration, long.duration);
      },
    );

    test(
      'is the backend\'s when it is within a few seconds of the track\'s',
      () async {
        // 插件的時長是整數秒，後端的較準。
        backend.loadedDuration = const Duration(minutes: 59, seconds: 32);
        await playback().play(long);

        expect(
          current()!.effectiveDuration,
          const Duration(minutes: 59, seconds: 32),
        );
      },
    );

    test('is the backend\'s when the track has none', () async {
      backend.loadedDuration = const Duration(minutes: 4);
      await playback().play(playable);

      expect(current()!.effectiveDuration, const Duration(minutes: 4));
    });

    test('is the track\'s own while the backend reports zero', () async {
      // AVPlayer 還不知道長度時，just_audio 報 0（事實 I4）。
      backend.loadedDuration = Duration.zero;
      await playback().play(long);
      backend.emit(
        backend.state.copyWith(status: AudioBackendStatus.buffering),
      );

      expect(current()!.effectiveDuration, long.duration);
    });

    test(
      'never shows the previous track\'s length while the next one loads',
      () async {
        backend.loadedDuration = other.duration;
        await playback().play(other);
        backend.holdLoad = Completer<void>();
        final playing = playback().play(long);
        for (var i = 0; i < 100 && backend.loaded.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        // 上一首遲到的狀態，帶著它的長度。
        backend.emit(
          backend.state.copyWith(
            status: AudioBackendStatus.ready,
            duration: () => other.duration,
          ),
        );
        expect(current()!.track, long);
        expect(current()!.effectiveDuration, long.duration);

        backend.loadedDuration = const Duration(minutes: 59, seconds: 32);
        backend.holdLoad!.complete();
        await playing;
        expect(
          current()!.effectiveDuration,
          const Duration(minutes: 59, seconds: 32),
        );
      },
    );
  });

  test('a stream the plugin cannot resolve fails with its error category '
      'and loads nothing', () async {
    await playback().play(
      const Track(
        ref: TrackRef(pluginId: 'songs', trackId: 'gone'),
        title: 'Gone',
        author: 'B',
      ),
    );

    expect(current()!.status, PlaybackStatus.failed);
    expect(current()!.error, isA<NotFound>());
    expect(backend.calls, isEmpty);
  });

  test('a track from a source with no plugin is Unsupported', () async {
    await playback().play(
      const Track(
        ref: TrackRef(pluginId: 'nowhere', trackId: 'x'),
        title: 'X',
        author: 'C',
      ),
    );

    expect(current()!.status, PlaybackStatus.failed);
    expect(current()!.error, isA<Unsupported>());
  });

  test('a stream the backend cannot open fails with the backend\'s category '
      'and logs the native detail', () async {
    backend.failNextLoad = const AudioBackendError(
      NetworkError(),
      'code 0: Source error',
    );

    await playback().play(playable);

    expect(current()!.status, PlaybackStatus.failed);
    expect(current()!.error, isA<NetworkError>());
    expect(backend.calls, ['load']);
    final log = await closeAndReadLog();
    // 後端發出 failed 又丟錯，只記一次。
    expect('Playback failed'.allMatches(log), hasLength(1));
    expect(
      log,
      contains(
        'Playback failed: NetworkError (code 0: Source error) '
        'for songs/ok from cdn.example.com',
      ),
    );
  });

  test('a failure while playing is reported and logged', () async {
    await playback().play(playable);

    backend.emit(
      backend.state.copyWith(
        status: AudioBackendStatus.failed,
        error: () => const AudioBackendError(Unsupported(), 'ao: no device'),
      ),
    );

    expect(current()!.status, PlaybackStatus.failed);
    expect(current()!.error, isA<Unsupported>());
    expect(
      await closeAndReadLog(),
      contains(
        'Playback failed: Unsupported (ao: no device) '
        'for songs/ok from cdn.example.com',
      ),
    );
  });

  test('a backend that refuses to play fails with its category', () async {
    backend.failNextPlay = const AudioBackendError(
      Unsupported(),
      'code 1: renderer',
    );

    await playback().play(playable);

    expect(current()!.status, PlaybackStatus.failed);
    expect(current()!.error, isA<Unsupported>());
    expect(
      await closeAndReadLog(),
      contains('Playback failed: Unsupported (code 1: renderer)'),
    );
  });

  test(
    'a stream that failed to load is not later reported as stalled',
    () async {
      backend.holdLoad = Completer<void>();
      backend.failNextLoad = const AudioBackendError(NetworkError(), 'x');
      final playing = playback().play(playable);
      await _until(() => backend.calls.isNotEmpty);
      // 載入中（stall 計時器在跑）時失敗。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      backend.holdLoad!.complete();
      await playing;
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(current()!.status, PlaybackStatus.failed);
      expect(await closeAndReadLog(), isNot(contains('Playback stalled')));
    },
  );

  test(
    'a stream that reports a zero duration is logged (facts I4, W4)',
    () async {
      backend.loadedDuration = Duration.zero;

      await playback().play(playable);

      expect(
        await closeAndReadLog(),
        contains('WARNING Stream reported a zero duration'),
      );
    },
  );

  test(
    'buffering longer than the stall threshold is logged once (fact W4)',
    () async {
      await playback().play(playable);

      backend.emit(
        backend.state.copyWith(status: AudioBackendStatus.buffering),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      backend.emit(backend.state.copyWith(status: AudioBackendStatus.ready));

      final lines = (await closeAndReadLog())
          .split('\n')
          .where((l) => l.contains('Playback stalled'));
      expect(lines, hasLength(1));
      expect(lines.single, contains('WARNING Playback stalled: buffering'));
    },
  );

  test('short buffering is not logged', () async {
    await playback().play(playable);

    backend.emit(backend.state.copyWith(status: AudioBackendStatus.buffering));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    backend.emit(backend.state.copyWith(status: AudioBackendStatus.ready));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(await closeAndReadLog(), isNot(contains('Playback stalled')));
  });

  test(
    'playing another track while one is loading keeps only the latest',
    () async {
      backend.holdLoad = Completer<void>();
      final first = playback().play(playable);
      await _until(() => backend.calls.isNotEmpty);

      const second = Track(
        ref: TrackRef(pluginId: 'songs', trackId: 'two'),
        title: 'Two',
        author: 'D',
      );
      backend.holdLoad!.complete();
      backend.holdLoad = null;
      final latest = playback().play(second);
      await Future.wait([first, latest]);

      expect(current()!.track, second);
      expect(current()!.status, PlaybackStatus.playing);
      expect(backend.loaded.last.url.path, '/two.m4a');
      // 第一首載入完時已經不是它了，不會叫後端播它。
      expect(backend.calls, ['load', 'load', 'play']);
    },
  );
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('until');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
