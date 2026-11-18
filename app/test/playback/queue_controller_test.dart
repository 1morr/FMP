import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/temporary_play.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';

import '../support/fake_audio_backend.dart';
import '../support/fake_http.dart';
import '../support/fjs.dart';

/// 佇列接上播放（brief〈播放〉）：經 [queueProvider] 與 [playbackProvider]
/// 測，插件跑在真的引擎裡，音訊後端換成 [FakeAudioBackend]。零聯網。
void main() {
  late Directory logDir;
  late Log log;
  late PluginHost host;
  late FakeAudioBackend backend;
  late ProviderContainer container;

  Track track(String id) => Track(
    ref: TrackRef(pluginId: 'songs', trackId: id),
    title: id,
    author: 'A',
  );

  setUpAll(loadFjsForTests);
  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_queue_');
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
              if (trackId.startsWith('gone')) {
                throw new PluginError('not_found');
              }
              if (trackId.startsWith('verify')) {
                throw new PluginError('verification_required');
              }
              return { url: 'https://cdn.example.com/' + trackId + '.m4a' };
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
        queueRandomProvider.overrideWithValue(Random(1)),
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

  QueueController queue() => container.read(queueProvider.notifier);
  String? playing() => container.read(playbackProvider)?.track.ref.trackId;
  String? currentInQueue() =>
      container.read(queueProvider).current?.track.ref.trackId;
  PlaybackFailure? failure() => container.read(playbackFailureProvider);
  List<String> loaded() => [
    for (final stream in backend.loaded) stream.url.pathSegments.last,
  ];

  /// 等插件解析、後端開始播（真的引擎要真的時間）。
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      final status = container.read(playbackProvider)?.status;
      if (status != PlaybackStatus.resolving &&
          status != PlaybackStatus.loading) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void finishCurrent() => backend.emit(
    backend.state.copyWith(
      status: AudioBackendStatus.completed,
      playing: false,
    ),
  );

  test(
    'adding to an empty queue starts playing the first added track',
    () async {
      await queue().add([track('a'), track('b')]);

      expect(playing(), 'a');
      expect(container.read(playbackProvider)!.status, PlaybackStatus.playing);
      expect(loaded(), ['a.m4a']);
    },
  );

  test('adding while playing only queues the tracks', () async {
    await queue().add([track('a')]);
    await queue().add([track('b')]);
    await queue().playNext([track('c')]);

    expect(playing(), 'a');
    expect(loaded(), ['a.m4a']);
    expect(
      [
        for (final e in container.read(queueProvider).entries)
          e.track.ref.trackId,
      ],
      ['a', 'c', 'b'],
    );
  });

  test('a finished track moves on to the next one', () async {
    await queue().add([track('a'), track('b')]);

    finishCurrent();
    await settle();

    expect(currentInQueue(), 'b');
    expect(playing(), 'b');
    expect(loaded(), ['a.m4a', 'b.m4a']);
  });

  test('the last finished track stops there', () async {
    await queue().add([track('a')]);

    finishCurrent();
    await settle();

    expect(currentInQueue(), 'a');
    expect(container.read(playbackProvider)!.status, PlaybackStatus.completed);
    expect(loaded(), ['a.m4a']);
  });

  test('next and previous play the neighbouring tracks', () async {
    await queue().add([track('a'), track('b')]);

    await queue().next();
    expect(playing(), 'b');
    await queue().previous();
    expect(playing(), 'a');
    expect(loaded(), ['a.m4a', 'b.m4a', 'a.m4a']);
  });

  test('next on the last track does nothing', () async {
    await queue().add([track('a')]);

    await queue().next();
    expect(playing(), 'a');
    expect(loaded(), ['a.m4a']);
  });

  test('playAt plays the chosen entry', () async {
    await queue().add([track('a'), track('b'), track('c')]);

    await queue().playAt(2);
    expect(playing(), 'c');
  });

  test('moving tracks does not interrupt playback', () async {
    await queue().add([track('a'), track('b'), track('c')]);

    queue().move(2, 0);

    expect(playing(), 'a');
    expect(currentInQueue(), 'a');
    expect(loaded(), ['a.m4a']);
  });

  group('remove', () {
    test('removing the current track plays the next one', () async {
      await queue().add([track('a'), track('b')]);

      await queue().remove(0);

      expect(playing(), 'b');
      expect(loaded(), ['a.m4a', 'b.m4a']);
    });

    test('removing another track keeps playing', () async {
      await queue().add([track('a'), track('b')]);

      await queue().remove(1);

      expect(playing(), 'a');
      expect(loaded(), ['a.m4a']);
    });

    test('removing the current last track stops playback', () async {
      await queue().add([track('a'), track('b')]);
      await queue().next();

      await queue().remove(1);

      expect(container.read(playbackProvider), isNull);
      expect(backend.calls.last, 'pause');
      expect(currentInQueue(), isNull);
    });
  });

  test('after the playing last track is removed, adding plays the added '
      'track', () async {
    await queue().add([track('a'), track('b')]);
    await queue().next();
    await queue().remove(1);
    expect(container.read(queueProvider).current, isNull);
    expect(container.read(playbackProvider), isNull);

    await queue().add([track('c')]);

    expect(currentInQueue(), 'c');
    expect(playing(), 'c');
  });

  test('with a current track that is paused, adding neither moves nor starts '
      'it', () async {
    await queue().add([track('a')]);
    await container.read(playbackProvider.notifier).pause();

    await queue().add([track('b')]);
    await queue().playNext([track('c')]);

    expect(currentInQueue(), 'a');
    expect(container.read(playbackProvider)!.status, PlaybackStatus.paused);
    expect(loaded(), ['a.m4a']);
  });

  test(
    'after the last track finished, adding neither moves nor starts it',
    () async {
      await queue().add([track('a')]);
      finishCurrent();
      await settle();

      await queue().add([track('b')]);

      expect(currentInQueue(), 'a');
      expect(
        container.read(playbackProvider)!.status,
        PlaybackStatus.completed,
      );
      expect(loaded(), ['a.m4a']);
    },
  );

  test('clearing the queue stops playback', () async {
    await queue().add([track('a'), track('b')]);

    await queue().clear();

    expect(container.read(queueProvider).isEmpty, isTrue);
    expect(container.read(playbackProvider), isNull);
    expect(backend.calls.last, 'pause');
  });

  /// 播放模式（brief〈播放〉的隨機與循環）接上播放；group 名稱引 brief 那一點。
  group('播放模式', () {
    List<String> order() => [
      for (final e in container.read(queueProvider).entries)
        e.track.ref.trackId,
    ];

    test('單曲循環：a finished track plays again', () async {
      await queue().add([track('a'), track('b')]);
      queue().cycleRepeat();
      queue().cycleRepeat();
      expect(container.read(queueProvider).repeat, Repeat.one);

      finishCurrent();
      await settle();

      expect(currentInQueue(), 'a');
      expect(playing(), 'a');
      expect(loaded(), ['a.m4a', 'a.m4a']);
    });

    test('列表循環：the last finished track goes on to the first', () async {
      await queue().add([track('a'), track('b')]);
      queue().cycleRepeat();
      await queue().next();

      finishCurrent();
      await settle();

      expect(playing(), 'a');
      expect(loaded(), ['a.m4a', 'b.m4a', 'a.m4a']);
    });

    test('開關隨機不打斷正在播的那首', () async {
      await queue().add([track('a'), track('b'), track('c')]);
      await queue().next();

      queue().toggleShuffle();
      expect(container.read(queueProvider).shuffled, isTrue);
      expect(order().first, 'b');
      queue().toggleShuffle();
      expect(container.read(queueProvider).shuffled, isFalse);
      expect(order(), ['a', 'b', 'c']);

      expect(playing(), 'b');
      expect(loaded(), ['a.m4a', 'b.m4a']);
    });

    test('隨機加列表循環：after the whole queue finishes, a reshuffled round '
        'starts playing', () async {
      await queue().add([track('a'), track('b'), track('c')]);
      queue().cycleRepeat();
      queue().toggleShuffle();

      for (var i = 0; i < 3; i++) {
        finishCurrent();
        await settle();
      }

      final now = container.read(queueProvider);
      expect(now.shuffled, isTrue);
      expect(now.currentIndex, 0);
      expect(playing(), now.current!.track.ref.trackId);
      expect(loaded(), hasLength(4));
    });

    test('只開隨機：the last finished track stops there', () async {
      await queue().add([track('a'), track('b'), track('c')]);
      queue().toggleShuffle();

      for (var i = 0; i < 3; i++) {
        finishCurrent();
        await settle();
      }

      expect(container.read(queueProvider).currentIndex, 2);
      expect(
        container.read(playbackProvider)!.status,
        PlaybackStatus.completed,
      );
      expect(loaded(), hasLength(3));
    });

    test('列表循環時用 × 移除正在播的最後一首，接著播第一首', () async {
      await queue().add([track('a'), track('b')]);
      queue().cycleRepeat();
      await queue().next();

      await queue().remove(1);

      expect(playing(), 'a');
      expect(loaded(), ['a.m4a', 'b.m4a', 'a.m4a']);
    });
  });

  group('失敗處理（brief〈播放〉）', () {
    /// 等失敗後的處理（跳下一首、回佇列）做完：它在下一個 microtask 開始。
    Future<void> settleFailures() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
        await settle();
      }
    }

    test('a track that cannot play is skipped: the next one plays and the '
        'failure says so', () async {
      await queue().add([track('gone'), track('b')]);
      await settleFailures();

      expect(currentInQueue(), 'b');
      expect(playing(), 'b');
      expect(failure()!.outcome, FailureOutcome.skipped);
      expect(failure()!.state.track, track('gone'));
      expect(failure()!.state.error, isA<NotFound>());
    });

    test('a stream the CDN keeps refusing (403) is resolved again once, then '
        'skipped', () async {
      backend.failLoadOf = (stream) => stream.url.path == '/a.m4a'
          ? const AudioBackendError(NetworkError(), 'Response code: 403')
          : null;

      await queue().add([track('a'), track('b')]);
      await settleFailures();

      expect(loaded(), ['a.m4a', 'a.m4a', 'b.m4a']);
      expect(playing(), 'b');
      expect(failure()!.outcome, FailureOutcome.skipped);
    });

    test('three failures in a row stop on the third, which stays failed, '
        'and the failure says so', () async {
      await queue().add([
        track('gone1'),
        track('gone2'),
        track('gone3'),
        track('d'),
      ]);
      await settleFailures();

      expect(currentInQueue(), 'gone3');
      expect(container.read(playbackProvider)!.status, PlaybackStatus.failed);
      expect(loaded(), isEmpty);
      expect(failure()!.outcome, FailureOutcome.stopped);
      expect(failure()!.streak, 3);
      expect(failure()!.state.track, track('gone3'));
    });

    test('a track that plays resets the count', () async {
      await queue().add([
        track('gone1'),
        track('gone2'),
        track('ok'),
        track('gone3'),
        track('gone4'),
        track('e'),
      ]);
      await settleFailures();
      expect(playing(), 'ok');

      finishCurrent();
      await settleFailures();

      expect(playing(), 'e');
      expect(container.read(playbackProvider)!.status, PlaybackStatus.playing);
      expect(failure()!.streak, 2);
    });

    test('after stopping, the next failure counts from one again', () async {
      await queue().add([
        track('gone1'),
        track('gone2'),
        track('gone3'),
        track('gone4'),
        track('e'),
      ]);
      await settleFailures();
      expect(failure()!.outcome, FailureOutcome.stopped);

      await queue().next();
      await settleFailures();

      expect(failure()!.streak, 1);
      expect(playing(), 'e');
    });

    test('choosing a track yourself starts the count again', () async {
      // 跳過兩首後，第三首（c）還在載入時使用者自己臨時播放一首壞的。
      backend.holdLoad = Completer<void>();
      await queue().add([track('gone1'), track('gone2'), track('c')]);
      await _until(() => backend.calls.contains('load'));
      expect(failure()!.streak, 2);

      await queue().playTemporarily(track('gone9'));
      await settleFailures();

      expect(failure()!.state.track, track('gone9'));
      expect(failure()!.streak, 1);
      expect(failure()!.outcome, FailureOutcome.returnedToQueue);
      backend.holdLoad!.complete();
    });

    test('the last track failing stays there: nothing to skip to', () async {
      await queue().add([track('a'), track('gone')]);
      await queue().next();
      await settleFailures();

      expect(currentInQueue(), 'gone');
      expect(failure()!.outcome, FailureOutcome.stayed);
    });

    test(
      'a source asking for verification stops there instead of skipping',
      () async {
        await queue().add([track('verify'), track('b')]);
        await settleFailures();

        expect(currentInQueue(), 'verify');
        expect(loaded(), isEmpty);
        expect(failure()!.outcome, FailureOutcome.stayed);
        expect(failure()!.state.error, isA<VerificationRequired>());
      },
    );
  });

  group('臨時播放（brief〈播放〉）', () {
    TemporaryPlay? temporary() => container.read(temporaryPlayProvider);
    List<String> ids() => [
      for (final e in container.read(queueProvider).entries)
        e.track.ref.trackId,
    ];

    /// 後端回報播到 [position]。
    void at(Duration position) =>
        backend.emit(backend.state.copyWith(position: position));

    /// 最後一次載入之後後端收到的呼叫，不含預載；換到預載的那條也算載入
    /// （記成 `load`）。這一組測臨時播放，預載有沒有及時交給後端看時機。
    List<String> sinceLastLoad() {
      final calls = [
        for (final call in backend.calls)
          if (!call.startsWith('preload')) call == 'switch' ? 'load' : call,
      ];
      return calls.sublist(calls.lastIndexOf('load'));
    }

    Future<void> finishTemporary() async {
      finishCurrent();
      await settle();
    }

    test(
      'plays the track outside the queue and leaves the queue as it was',
      () async {
        await queue().add([track('a'), track('b')]);

        await queue().playTemporarily(track('x'));

        expect(playing(), 'x');
        expect(ids(), ['a', 'b']);
        expect(currentInQueue(), 'a');
        expect(temporary()!.track.ref.trackId, 'x');
      },
    );

    test('播完回到佇列原本那首，倒退 10 秒接著播', () async {
      await queue().add([track('a'), track('b')]);
      at(const Duration(seconds: 90));
      await queue().playTemporarily(track('x'));
      await settle();

      await finishTemporary();

      expect(playing(), 'a');
      expect(sinceLastLoad(), ['load', 'seek 80000', 'play']);
      expect(container.read(playbackProvider)!.status, PlaybackStatus.playing);
      expect(temporary(), isNull);
      expect(currentInQueue(), 'a');
    });

    test('下一首 returns to the queue track instead of moving on', () async {
      await queue().add([track('a'), track('b')]);
      at(const Duration(seconds: 90));
      await queue().playTemporarily(track('x'));
      await settle();

      await queue().next();
      await settle();

      expect(playing(), 'a');
      expect(sinceLastLoad(), ['load', 'seek 80000', 'play']);
      expect(temporary(), isNull);
    });

    test('上一首 returns to the queue track too', () async {
      await queue().add([track('a'), track('b')]);
      await queue().next();
      at(const Duration(seconds: 90));
      await queue().playTemporarily(track('x'));
      await settle();

      await queue().previous();
      await settle();

      expect(playing(), 'b');
      expect(sinceLastLoad(), ['load', 'seek 80000', 'play']);
    });

    test('連續臨時播放 keeps the earliest queue position', () async {
      await queue().add([track('a'), track('b')]);
      at(const Duration(seconds: 90));
      await queue().playTemporarily(track('x'));
      await settle();
      at(const Duration(seconds: 30));

      await queue().playTemporarily(track('y'));
      await settle();
      expect(playing(), 'y');
      expect(temporary()!.track.ref.trackId, 'y');

      await finishTemporary();
      expect(playing(), 'a');
      expect(sinceLastLoad(), ['load', 'seek 80000', 'play']);
    });

    test('倒退秒數可設定', () async {
      container
          .read(temporaryPlayRewindProvider.notifier)
          .set(const Duration(seconds: 5));
      await queue().add([track('a')]);
      at(const Duration(seconds: 90));
      await queue().playTemporarily(track('x'));
      await settle();

      await finishTemporary();

      expect(sinceLastLoad(), ['load', 'seek 85000', 'play']);
    });

    test('rewinding past the start plays from the start', () async {
      await queue().add([track('a')]);
      at(const Duration(seconds: 4));
      await queue().playTemporarily(track('x'));
      await settle();

      await finishTemporary();

      expect(playing(), 'a');
      expect(sinceLastLoad(), ['load', 'play']);
    });

    test('returning plays even when the queue was paused before', () async {
      await queue().add([track('a')]);
      at(const Duration(seconds: 90));
      await container.read(playbackProvider.notifier).pause();
      await queue().playTemporarily(track('x'));
      await settle();

      await finishTemporary();

      expect(playing(), 'a');
      expect(container.read(playbackProvider)!.status, PlaybackStatus.playing);
    });

    test('卡片的「下一首播放」 puts the temporary track after the queue track '
        'and keeps playing it as the current track', () async {
      await queue().add([track('a'), track('b')]);
      await queue().playTemporarily(track('x'));
      await settle();

      queue().queueTemporaryNext();

      expect(ids(), ['a', 'x', 'b']);
      expect(currentInQueue(), 'x');
      expect(playing(), 'x');
      expect(loaded(), ['a.m4a', 'x.m4a']);
      expect(temporary(), isNull);

      finishCurrent();
      await settle();
      expect(playing(), 'b');
    });

    test('removing the queue track to return to does not interrupt; it '
        'returns to the track that took its place, from the start', () async {
      await queue().add([track('a'), track('b')]);
      at(const Duration(seconds: 90));
      await queue().playTemporarily(track('x'));
      await settle();

      await queue().remove(0);
      expect(playing(), 'x');
      expect(loaded(), ['a.m4a', 'x.m4a']);

      await finishTemporary();
      expect(playing(), 'b');
      expect(sinceLastLoad(), ['load', 'play']);
    });

    test('adding while playing temporarily does not interrupt it, even with '
        'no queue track to return to', () async {
      await queue().playTemporarily(track('x'));
      await settle();

      await queue().add([track('a')]);
      expect(playing(), 'x');
      expect(loaded(), ['x.m4a']);

      await finishTemporary();
      expect(playing(), 'a');
    });

    test(
      'with nothing in the queue to return to, a finished temporary '
      'track ends temporary play there; adding then plays as usual',
      () async {
        await queue().playTemporarily(track('x'));
        await settle();
        expect(container.read(skipAvailableProvider), (
          previous: false,
          next: false,
        ));

        await finishTemporary();
        expect(playing(), 'x');
        expect(
          container.read(playbackProvider)!.status,
          PlaybackStatus.completed,
        );
        expect(temporary(), isNull);

        await queue().add([track('a')]);
        expect(playing(), 'a');
      },
    );

    test('started after the queue finished, it goes back to the last track '
        'from the start', () async {
      await queue().add([track('a')]);
      at(const Duration(minutes: 3));
      finishCurrent();
      await settle();

      await queue().playTemporarily(track('x'));
      await settle();
      await finishTemporary();

      expect(playing(), 'a');
      expect(sinceLastLoad(), ['load', 'play']);
    });

    test('skipping is on while there is a queue track to return to', () async {
      await queue().add([track('a')]);
      expect(container.read(skipAvailableProvider), (
        previous: false,
        next: false,
      ));

      await queue().playTemporarily(track('x'));

      expect(container.read(skipAvailableProvider), (
        previous: true,
        next: true,
      ));
    });

    test('playing a queue entry ends temporary play', () async {
      await queue().add([track('a'), track('b')]);
      await queue().playTemporarily(track('x'));
      await settle();

      await queue().playAt(1);

      expect(playing(), 'b');
      expect(temporary(), isNull);
      expect(sinceLastLoad(), ['load', 'play']);
    });

    test('returnToQueue goes back right away', () async {
      await queue().add([track('a')]);
      at(const Duration(seconds: 90));
      await queue().playTemporarily(track('x'));
      await settle();

      await queue().returnToQueue();
      await settle();

      expect(playing(), 'a');
      expect(sinceLastLoad(), ['load', 'seek 80000', 'play']);
    });

    test('clearing the queue stops playback and ends temporary play', () async {
      await queue().add([track('a')]);
      await queue().playTemporarily(track('x'));
      await settle();

      await queue().clear();

      expect(container.read(playbackProvider), isNull);
      expect(temporary(), isNull);
    });

    test('a temporary track that fails returns to the queue like a finished '
        'one', () async {
      await queue().add([track('a')]);
      at(const Duration(seconds: 90));
      // 重新解析也開不了的串流。
      backend.failLoadOf = (stream) => stream.url.path == '/x.m4a'
          ? const AudioBackendError(NetworkError(), 'x')
          : null;

      final statuses = <String>[];
      container.listen(playbackProvider, (_, next) {
        statuses.add('${next?.track.ref.trackId} ${next?.status.name}');
      });

      await queue().playTemporarily(track('x'));
      // 失敗之後下一個 microtask 才回去。
      await Future<void>.delayed(Duration.zero);
      await settle();

      expect(statuses, contains('x failed'));
      expect(loaded(), ['a.m4a', 'x.m4a', 'x.m4a', 'a.m4a']);
      expect(playing(), 'a');
      expect(sinceLastLoad(), ['load', 'seek 80000', 'play']);
      expect(temporary(), isNull);
      expect(failure()!.outcome, FailureOutcome.returnedToQueue);
      expect(failure()!.state.track, track('x'));
    });

    test('單曲循環 does not repeat a temporary track', () async {
      await queue().add([track('a')]);
      queue()
        ..cycleRepeat()
        ..cycleRepeat();
      await queue().playTemporarily(track('x'));
      await settle();

      await finishTemporary();

      expect(playing(), 'a');
    });
  });

  group('預載下一首（brief〈播放〉）', () {
    String? preloaded() => backend.preloaded?.url.pathSegments.last;

    Future<void> preloadedIs(String? file) => _until(() => preloaded() == file);

    test(
      'once a track sounds, the next track in the queue is preloaded',
      () async {
        await queue().add([track('a'), track('b'), track('c')]);
        await settle();

        await preloadedIs('b.m4a');
        expect(backend.preloads, hasLength(1));
      },
    );

    test('pressing next plays the preloaded track without resolving it '
        'again', () async {
      await queue().add([track('a'), track('b'), track('c')]);
      await preloadedIs('b.m4a');
      backend.calls.clear();

      await queue().next();

      expect(playing(), 'b');
      expect(backend.calls.take(2), ['switch', 'play']);
      expect(container.read(playbackProvider)!.status, PlaybackStatus.playing);
      // 接著預載再下一首。
      await preloadedIs('c.m4a');
    });

    test(
      'pressing next onto the last track still switches to the preload',
      () async {
        await queue().add([track('a'), track('b')]);
        await preloadedIs('b.m4a');
        backend.calls.clear();

        await queue().next();
        await pumpEventQueue();

        expect(playing(), 'b');
        expect(backend.calls.first, 'switch');
      },
    );

    test('a track finishing moves on to the preloaded one, keeping the sound '
        'going', () async {
      await queue().add([track('a'), track('b')]);
      await preloadedIs('b.m4a');
      backend.calls.clear();

      backend.advance();
      await _until(() => playing() == 'b');
      await settle();

      expect(currentInQueue(), 'b');
      expect(backend.calls.take(2), ['load current', 'play']);
      expect(container.read(playbackProvider)!.status, PlaybackStatus.playing);
    });

    test(
      'moving a track, playing next and shuffling change the preload',
      () async {
        await queue().add([track('a'), track('b'), track('c'), track('d')]);
        await preloadedIs('b.m4a');

        queue().move(2, 1);
        await preloadedIs('c.m4a');

        await queue().playNext([track('x')]);
        await preloadedIs('x.m4a');

        queue().toggleShuffle();
        final upcoming = container.read(queueProvider).upcoming!.track;
        await preloadedIs('${upcoming.ref.trackId}.m4a');
      },
    );

    test('nothing is preloaded after the last track; list repeat preloads '
        'the first', () async {
      await queue().add([track('a')]);
      await settle();
      await pumpEventQueue(times: 20);
      expect(backend.preloads, isEmpty);

      queue().cycleRepeat();
      expect(container.read(queueProvider).repeat, Repeat.all);
      await _until(() => backend.preloads.isNotEmpty);
      expect(preloaded(), 'a.m4a');
    });

    test('repeat one preloads the same track again', () async {
      await queue().add([track('a'), track('b')]);
      await preloadedIs('b.m4a');

      queue()
        ..cycleRepeat()
        ..cycleRepeat();
      expect(container.read(queueProvider).repeat, Repeat.one);

      await preloadedIs('a.m4a');
    });

    test('during temporary play the track to go back to is preloaded, and '
        'going back switches to it and rewinds', () async {
      await queue().add([track('a'), track('b')]);
      await settle();
      backend.emit(
        backend.state.copyWith(position: const Duration(minutes: 1)),
      );
      await queue().playTemporarily(track('x'));
      await settle();
      await preloadedIs('a.m4a');
      backend.calls.clear();

      await queue().next();

      expect(playing(), 'a');
      expect(backend.calls.take(3), ['switch', 'seek 50000', 'play']);
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
