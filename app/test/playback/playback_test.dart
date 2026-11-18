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

  /// 假的時鐘：過期前重新解析看它（[playbackClockProvider]）。
  final start = DateTime.utc(2027, 1, 15, 8);
  late DateTime now;

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
          code:
              '''
            export async function search() { return { tracks: [] }; }
            export async function resolveStream({ trackId }) {
              if (trackId === 'gone') throw new PluginError('not_found');
              const stream = {
                url: 'https://cdn.example.com/' + trackId + '.m4a',
                headers: { Referer: 'https://example.com' },
                codec: 'mp4a.40.2',
              };
              // 有效期是 [start] 後 10 分鐘（事實 F5 的 deadline）。
              if (trackId === 'expiring') {
                stream.expiresAtMs = ${start.millisecondsSinceEpoch} + 600000;
              }
              return stream;
            }
          ''',
        ),
      ],
      log: log,
      httpAdapter: FakeHttp((_) => const FakeResponse(404)),
    );
    backend = FakeAudioBackend();
    now = start;
    container = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(log),
        pluginHostProvider.overrideWith((_) => host),
        audioBackendProvider.overrideWithValue(backend),
        playbackClockProvider.overrideWithValue(() => now),
        stallTimeoutsProvider.overrideWithValue(
          const StallTimeouts(
            starting: Duration(milliseconds: 300),
            playing: Duration(milliseconds: 200),
          ),
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

  group('seek', () {
    test(
      'playing from a position seeks after loading, before playing',
      () async {
        await playback().play(playable, from: const Duration(seconds: 80));

        expect(backend.calls, ['load', 'seek 80000', 'play']);
        expect(current()!.position, const Duration(seconds: 80));
        expect(current()!.status, PlaybackStatus.playing);
      },
    );

    test('seek moves the loaded track', () async {
      await playback().play(playable);

      await playback().seek(const Duration(seconds: 30));

      expect(backend.calls, ['load', 'play', 'seek 30000']);
      expect(current()!.position, const Duration(seconds: 30));
    });

    test('seek does nothing before the first track', () async {
      await playback().seek(const Duration(seconds: 30));

      expect(backend.calls, isEmpty);
    });

    test('a backend that cannot seek re-resolves and starts from the same '
        'position', () async {
      backend.failNextSeek = const AudioBackendError(NetworkError(), 'x');

      await playback().play(playable, from: const Duration(seconds: 80));

      expect(current()!.status, PlaybackStatus.playing);
      expect(backend.calls, [
        'load',
        'seek 80000',
        'load',
        'seek 80000',
        'play',
      ]);
    });
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

  group('failure', () {
    const cdn403 = AudioBackendError(
      NetworkError(),
      'InvalidResponseCodeException: Response code: 403',
    );

    test('a stream the CDN refuses (403) is resolved again once and plays '
        'the new stream', () async {
      final statuses = <PlaybackStatus>[];
      container.listen(
        playbackProvider,
        (_, next) => statuses.add(next!.status),
      );
      backend.failNextLoad = cdn403;

      await playback().play(playable);

      expect(backend.calls, ['load', 'load', 'play']);
      expect(current()!.status, PlaybackStatus.playing);
      // 重新解析時不報失敗：提示與跳下一首只看最後的結果。
      expect(statuses, isNot(contains(PlaybackStatus.failed)));
      final log = await closeAndReadLog();
      expect(
        log,
        contains(
          'Playback failed: NetworkError (InvalidResponseCodeException: '
          'Response code: 403) for songs/ok from cdn.example.com',
        ),
      );
      expect(log, contains('INFO Resolving the stream again: songs/ok'));
    });

    test('a stream that fails again after resolving it again fails with the '
        'backend\'s category', () async {
      backend.failLoadOf = (_) =>
          const AudioBackendError(NetworkError(), 'code 0: Source error');

      await playback().play(playable);

      expect(current()!.status, PlaybackStatus.failed);
      expect(current()!.error, isA<NetworkError>());
      expect(backend.calls, ['load', 'load']);
      final log = await closeAndReadLog();
      // 每次後端發出 failed 又丟錯，各記一次。
      expect('Playback failed'.allMatches(log), hasLength(2));
      expect('Resolving the stream again'.allMatches(log), hasLength(1));
    });

    test('a failure while playing resolves the stream again and goes on '
        'from where it stopped', () async {
      await playback().play(playable);
      backend.emit(
        backend.state.copyWith(position: const Duration(minutes: 2)),
      );

      backend.emit(
        backend.state.copyWith(
          status: AudioBackendStatus.failed,
          error: () => cdn403,
        ),
      );
      await _until(() => current()!.status == PlaybackStatus.playing);

      expect(backend.calls, ['load', 'play', 'load', 'seek 120000', 'play']);
      expect(
        await closeAndReadLog(),
        contains('Playback failed: NetworkError (InvalidResponseCodeException'),
      );
    });

    test('a second failure of the same track is final', () async {
      await playback().play(playable);
      Future<void> fail() async => backend.emit(
        backend.state.copyWith(
          status: AudioBackendStatus.failed,
          error: () => const AudioBackendError(Unsupported(), 'ao: no device'),
        ),
      );

      await fail();
      await _until(() => current()!.status == PlaybackStatus.playing);
      await fail();

      expect(current()!.status, PlaybackStatus.failed);
      expect(current()!.error, isA<Unsupported>());
      expect(backend.loaded, hasLength(2));
      expect(
        await closeAndReadLog(),
        contains(
          'Playback failed: Unsupported (ao: no device) '
          'for songs/ok from cdn.example.com',
        ),
      );
    });

    test('playing the track again gets a new attempt', () async {
      backend.failLoadOf = (_) => cdn403;
      await playback().play(playable);
      expect(current()!.status, PlaybackStatus.failed);

      backend.failLoadOf = null;
      backend.failNextLoad = cdn403;
      await playback().play(playable);

      expect(current()!.status, PlaybackStatus.playing);
      expect(backend.loaded, hasLength(4));
    });

    test('a failure while paused resolves the stream again but stays '
        'paused', () async {
      await playback().play(playable);
      backend.emit(
        backend.state.copyWith(position: const Duration(minutes: 2)),
      );
      await playback().pause();
      backend.calls.clear();

      backend.emit(
        backend.state.copyWith(
          status: AudioBackendStatus.failed,
          error: () => cdn403,
        ),
      );
      await _until(() => current()!.status == PlaybackStatus.paused);

      expect(backend.calls, ['load', 'seek 120000']);
      expect(current()!.position, const Duration(minutes: 2));
    });

    test('after playing well for 30 seconds, a later failure is resolved '
        'again too', () async {
      Future<void> fail() async => backend.emit(
        backend.state.copyWith(
          status: AudioBackendStatus.failed,
          error: () => cdn403,
        ),
      );
      await playback().play(playable);
      await fail();
      await _until(() => current()!.status == PlaybackStatus.playing);

      backend.emit(
        backend.state.copyWith(position: const Duration(seconds: 31)),
      );
      await fail();
      await _until(() => backend.loaded.length == 3);
      await _until(() => current()!.status == PlaybackStatus.playing);

      expect(current()!.status, PlaybackStatus.playing);
    });

    test('a plugin error is not resolved again', () async {
      final statuses = <PlaybackStatus>[];
      container.listen(
        playbackProvider,
        (_, next) => statuses.add(next!.status),
      );

      await playback().play(
        const Track(
          ref: TrackRef(pluginId: 'songs', trackId: 'gone'),
          title: 'Gone',
          author: 'B',
        ),
      );

      expect(statuses, [PlaybackStatus.resolving, PlaybackStatus.failed]);
      expect(await closeAndReadLog(), isNot(contains('Resolving the stream')));
    });
  });

  group('expiry', () {
    const expiring = Track(
      ref: TrackRef(pluginId: 'songs', trackId: 'expiring'),
      title: 'Expiring',
      author: 'E',
    );

    Future<void> playThenPauseAt(Track track, Duration position) async {
      await playback().play(track);
      backend.emit(backend.state.copyWith(position: position));
      await playback().pause();
      backend.calls.clear();
    }

    test('resuming less than 2 minutes before the stream expires resolves '
        'it again first and goes on from the same position', () async {
      await playThenPauseAt(expiring, const Duration(minutes: 3));
      now = start.add(const Duration(minutes: 8, seconds: 1));

      await playback().resume();

      expect(backend.calls, ['load', 'seek 180000', 'play']);
      expect(backend.loaded, hasLength(2));
      expect(current()!.status, PlaybackStatus.playing);
      expect(
        await closeAndReadLog(),
        contains('INFO Resolving the stream again before it expires'),
      );
    });

    test('resuming earlier than that uses the stream as it is', () async {
      await playThenPauseAt(expiring, const Duration(minutes: 3));
      now = start.add(const Duration(minutes: 7, seconds: 59));

      await playback().resume();

      expect(backend.calls, ['play']);
    });

    test('seeking less than 2 minutes before expiry resolves it again and '
        'stays paused at the new position', () async {
      await playThenPauseAt(expiring, const Duration(minutes: 3));
      now = start.add(const Duration(minutes: 9));

      await playback().seek(const Duration(minutes: 1));

      expect(backend.calls, ['load', 'seek 60000']);
      expect(current()!.status, PlaybackStatus.paused);
      expect(current()!.position, const Duration(minutes: 1));
    });

    test('seeking while playing near expiry goes on playing', () async {
      await playback().play(expiring);
      backend.calls.clear();
      now = start.add(const Duration(minutes: 9));

      await playback().seek(const Duration(minutes: 1));

      expect(backend.calls, ['load', 'seek 60000', 'play']);
      expect(current()!.status, PlaybackStatus.playing);
    });

    test('a stream without an expiry is never resolved ahead', () async {
      await playThenPauseAt(playable, const Duration(minutes: 3));
      now = start.add(const Duration(days: 1));

      await playback().resume();
      await playback().seek(const Duration(minutes: 1));

      expect(backend.calls, ['play', 'seek 60000']);
    });
  });

  test('a backend that refuses to play resolves the stream again', () async {
    backend.failNextPlay = const AudioBackendError(
      Unsupported(),
      'code 1: renderer',
    );

    await playback().play(playable);

    expect(backend.calls, ['load', 'play', 'load', 'play']);
    expect(current()!.status, PlaybackStatus.playing);
    expect(
      await closeAndReadLog(),
      contains('Playback failed: Unsupported (code 1: renderer)'),
    );
  });

  test(
    'a stream that failed to load is not later reported as stalled',
    () async {
      backend.holdLoad = Completer<void>();
      backend.failLoadOf = (_) => const AudioBackendError(NetworkError(), 'x');
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

  group('watchdog (fact W4)', () {
    test('buffering while playing for longer than the threshold fails like '
        'a broken stream: resolved again, from the same position', () async {
      await playback().play(playable);
      backend.emit(
        backend.state.copyWith(
          status: AudioBackendStatus.buffering,
          position: const Duration(seconds: 42),
        ),
      );

      await _until(() => backend.loaded.length == 2);
      await _until(() => current()!.status == PlaybackStatus.playing);

      expect(backend.calls, ['load', 'play', 'load', 'seek 42000', 'play']);
      expect(
        await closeAndReadLog(),
        contains(
          'WARNING Playback stalled: buffering for over 200 ms: songs/ok',
        ),
      );
    });

    test('stalling again after that is final, as a network error', () async {
      await playback().play(playable);
      backend.emit(
        backend.state.copyWith(status: AudioBackendStatus.buffering),
      );
      await _until(() => current()!.status == PlaybackStatus.playing);
      backend.emit(
        backend.state.copyWith(status: AudioBackendStatus.buffering),
      );

      await _until(() => current()!.status == PlaybackStatus.failed);
      expect(current()!.error, isA<NetworkError>());
      // 不讓卡住的串流之後自己播出聲。
      expect(backend.calls.last, 'pause');
    });

    test('buffering shorter than the threshold is a normal hiccup', () async {
      await playback().play(playable);

      backend.emit(
        backend.state.copyWith(status: AudioBackendStatus.buffering),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      backend.emit(backend.state.copyWith(status: AudioBackendStatus.ready));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(backend.loaded, hasLength(1));
      expect(current()!.status, PlaybackStatus.playing);
      expect(await closeAndReadLog(), isNot(contains('Playback stalled')));
    });

    test('a slow start within the start threshold is not cut short, though '
        'it is longer than the playing one', () async {
      backend.holdLoad = Completer<void>();
      final playing = playback().play(playable);
      await _until(() => backend.calls.isNotEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      backend.holdLoad!.complete();
      await playing;
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(backend.loaded, hasLength(1));
      expect(current()!.status, PlaybackStatus.playing);
    });

    test('a start that takes longer than the start threshold fails like a '
        'broken stream', () async {
      backend.holdLoad = Completer<void>();
      unawaited(playback().play(playable));

      await _until(() => backend.loaded.length == 2);
      expect(
        await closeAndReadLog(),
        contains('WARNING Playback stalled: starting for over 300 ms'),
      );
      backend.holdLoad!.complete();
    });

    test('a paused stream that buffers is left alone', () async {
      await playback().play(playable);
      await playback().pause();

      backend.emit(
        backend.state.copyWith(status: AudioBackendStatus.buffering),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(backend.loaded, hasLength(1));
    });
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

  group('preload (brief〈播放〉)', () {
    const next = Track(
      ref: TrackRef(pluginId: 'songs', trackId: 'next'),
      title: 'Next',
      author: 'N',
    );
    const expiring = Track(
      ref: TrackRef(pluginId: 'songs', trackId: 'expiring'),
      title: 'Expiring',
      author: 'E',
    );

    test('the next track is resolved and handed to the backend once the '
        'current one sounds, not before', () async {
      backend.holdLoad = Completer();
      final playing = playback().play(playable);
      playback().preloadNext(next);
      // 解析一首要經插件引擎，給它足夠的時間。
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(backend.preloads, isEmpty);

      backend.holdLoad!.complete();
      await playing;
      await _until(() => backend.preloads.isNotEmpty);

      expect(backend.preloads.single!.url.path, '/next.m4a');
      expect(identical(backend.preloaded, backend.preloads.single), isTrue);
    });

    test('a track that sounds before its load returns still preloads the '
        'next one', () async {
      // just_audio 的 playing 跨來源保留：新的一條常在 setAudioSource 回來
      // 之前就出聲。
      playback().preloadNext(next);
      backend.holdLoad = Completer();
      final playing = playback().play(playable);
      await _until(() => backend.calls.contains('load'));
      backend.emit(
        backend.state.copyWith(status: AudioBackendStatus.ready, playing: true),
      );
      backend.holdLoad!.complete();
      await playing;

      await _until(() => backend.preloads.isNotEmpty);
      expect(backend.preloads.single!.url.path, '/next.m4a');
    });

    test('playing the preloaded track switches to it without resolving it '
        'again', () async {
      await playback().play(playable);
      playback().preloadNext(next);
      await _until(() => backend.preloads.isNotEmpty);
      final statuses = <PlaybackStatus>[];
      container.listen(playbackProvider, (_, s) => statuses.add(s!.status));
      backend.calls.clear();

      await playback().play(next);

      expect(backend.calls, ['switch', 'play']);
      expect(identical(current()!.stream, backend.preloads.single), isTrue);
      expect(current()!.track, next);
      expect(current()!.status, PlaybackStatus.playing);
      expect(statuses, isNot(contains(PlaybackStatus.resolving)));
    });

    test('when the backend moves on to the preloaded stream by itself, the '
        'current track completes, and playing the next one keeps the sound '
        'going', () async {
      await playback().play(playable);
      playback().preloadNext(next);
      await _until(() => backend.preloads.isNotEmpty);
      backend.calls.clear();

      backend.advance();
      // 播放層還沒換到下一首時，後端報的下一首的狀態不算這一首的。
      expect(current()!.track, playable);
      expect(current()!.status, PlaybackStatus.completed);

      await playback().play(next);

      expect(backend.calls, ['load current', 'play']);
      expect(current()!.track, next);
      expect(current()!.status, PlaybackStatus.playing);
      expect(current()!.duration, const Duration(minutes: 3));
    });

    test('a preloaded stream less than 2 minutes before it expires is '
        'resolved again when played (architecture〈快取〉)', () async {
      await playback().play(playable);
      playback().preloadNext(expiring);
      await _until(() => backend.preloads.isNotEmpty);
      now = start.add(const Duration(minutes: 8, seconds: 1));
      backend.calls.clear();

      await playback().play(expiring);

      expect(backend.calls, ['load', 'play']);
      expect(identical(current()!.stream, backend.preloads.single), isFalse);
    });

    test(
      'a waiting preload is resolved again 2 minutes before it expires',
      () async {
        // 預載時離「過期前 2 分鐘」只剩 100 毫秒。
        now = start.add(
          const Duration(minutes: 8) - const Duration(milliseconds: 100),
        );
        await playback().play(playable);
        playback().preloadNext(expiring);
        await _until(() => backend.preloads.isNotEmpty);
        now = start.add(const Duration(minutes: 8));

        await _until(() => backend.preloads.length == 2);

        expect(identical(backend.preloads[0], backend.preloads[1]), isFalse);
        expect(identical(backend.preloaded, backend.preloads[1]), isTrue);
      },
    );

    test('a new next track replaces the preload, and no next track clears '
        'it', () async {
      await playback().play(playable);
      playback().preloadNext(next);
      await _until(() => backend.preloads.isNotEmpty);

      playback().preloadNext(expiring);
      await _until(() => backend.preloaded?.url.path == '/expiring.m4a');

      playback().preloadNext(null);
      await _until(() => backend.preloaded == null);
      expect(backend.preloads.last, isNull);
    });

    test('a new next track takes the old preload off the backend right '
        'away, so a natural end cannot play it, even when the new one fails '
        'to resolve', () async {
      const gone = Track(
        ref: TrackRef(pluginId: 'songs', trackId: 'gone'),
        title: 'Gone',
        author: 'G',
      );
      await playback().play(playable);
      playback().preloadNext(next);
      await _until(() => backend.preloaded != null);

      playback().preloadNext(gone);
      await _until(() => backend.preloads.length == 2);

      expect(backend.preloads.last, isNull);
      expect(backend.preloaded, isNull);
    });

    test('a track loaded fresh gets the preload handed over again once it '
        'sounds, without resolving the next track again', () async {
      await playback().play(playable);
      playback().preloadNext(next);
      await _until(() => backend.preloads.isNotEmpty);

      // 重新開別的串流，後端的清單整個換掉。
      await playback().play(expiring);
      await _until(() => backend.preloads.length == 2);

      expect(identical(backend.preloads[0], backend.preloads[1]), isTrue);
    });

    test('a next track that fails to resolve is only logged; playing it '
        'resolves as usual', () async {
      const gone = Track(
        ref: TrackRef(pluginId: 'songs', trackId: 'gone'),
        title: 'Gone',
        author: 'G',
      );
      await playback().play(playable);
      playback().preloadNext(gone);
      await pumpEventQueue(times: 50);
      expect(backend.preloads, isEmpty);
      expect(current()!.status, PlaybackStatus.playing);

      await playback().play(gone);

      expect(current()!.status, PlaybackStatus.failed);
      expect(current()!.error, isA<NotFound>());
    });
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('until');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
