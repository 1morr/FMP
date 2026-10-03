import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_events.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/playback/stream_resolver.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:path/path.dart' as p;

import '../support/pump_until.dart';
import 'fake_audio_backend.dart';
import 'fake_source_plugin.dart';

TrackInfo track(String id) =>
    TrackInfo(sourceTypeId: 'fmp-test', sourceId: id, title: 'Song $id');

/// 控制器加假後端、假插件與 log，全部在 [async] 的假時間裡。
final class Harness {
  Harness(
    this.async, {
    FutureOr<List<StreamCandidate>> Function(StreamRequest request)? respond,
    Duration trackLength = const Duration(seconds: 2),
    bool Function(Uri url)? failsToOpen,
  }) : plugin = FakeSourcePlugin(
         respond ?? (request) => [candidate('${request.sourceId}.m4a')],
       ),
       backend = FakeAudioBackend(
         durationOf: (_) => trackLength,
         failsToOpen: failsToOpen ?? (_) => false,
       ) {
    controller = PlaybackController(
      session: PlaybackSession(
        backend: backend,
        resolver: StreamResolver(
          plugin: (id) => id == plugin.manifest.id ? plugin : null,
          formats: const [PlayableFormat('mp4', 'aac')],
          log: log,
        ),
        log: log,
      ),
      log: log,
      temporaryReturnSettings: () => returnSettings,
    );
    controller.states.listen(states.add);
    controller.events.listen(events.add);
  }

  final FakeAsync async;
  final FakeSourcePlugin plugin;
  final FakeAudioBackend backend;
  final log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
  late final PlaybackController controller;
  final states = <PlaybackState>[];
  final events = <PlaybackEvent>[];

  /// 臨時播放回到佇列時控制器讀到的設定（預設同 App 的預設）。
  TemporaryReturnSettings returnSettings = (
    rememberPosition: true,
    rewind: const Duration(seconds: 10),
  );

  /// 把 [tracks] 加進（空的）佇列，從第 [startIndex] 首開始播。
  Future<void> playQueue(List<TrackInfo> tracks, {int startIndex = 0}) {
    expect(controller.addToQueue(tracks), isTrue);
    return controller.jumpTo(startIndex);
  }

  /// fakeAsync 裡的 `clock` 跟著假時間走。
  DateTime now() => clock.now();

  void elapse(Duration duration) => async.elapse(duration);

  /// 讓已排定的非同步工作跑完（不前進時間）。
  void settle() => async.flushMicrotasks();

  List<String> get openedPaths => [
    for (final source in backend.opened) source.url.path,
  ];

  List<LogRecord> logged(String message) => [
    for (final record in log.history)
      if (record.message == message) record,
  ];
}

void main() {
  group('playing a queue', () {
    test('hands over to the look-ahead, which is resolved only once', () {
      fakeAsync((async) {
        final h = Harness(async);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Playing>());
        expect(h.plugin.resolvedCount('b'), 1);
        expect(h.backend.nextSources.last?.url.path, '/b.m4a');

        h.elapse(const Duration(seconds: 2));
        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.state, isA<Playing>());
        // b 由前瞻接上，後端只 open 過 a。
        expect(h.openedPaths, ['/a.m4a']);
        expect(h.logged('Look-ahead handover'), hasLength(1));
        expect(h.logged('Look-ahead handover').single.fields, {
          'from': 'fmp-test:a',
          'to': 'fmp-test:b',
          'end': 'completed',
          'previousPositionMs': greaterThanOrEqualTo(1900),
          'previousDurationMs': 2000,
          'sinceLastProgressMs': lessThanOrEqualTo(100),
        });

        h.elapse(const Duration(seconds: 3));
        expect(h.controller.state, isA<Idle>());
        expect(h.plugin.resolvedCount('a'), 1);
        expect(h.plugin.resolvedCount('b'), 1);
        expect(h.logged('Track audible'), hasLength(2));
        expect(
          h.logged('Track audible').last.fields,
          containsPair('sinceHandoverMs', isA<int>()),
        );
      });
    });

    test('pausing and resuming does not resolve the look-ahead again', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        for (var i = 0; i < 3; i++) {
          unawaited(h.controller.pause());
          h.elapse(const Duration(milliseconds: 100));
          unawaited(h.controller.play());
          h.elapse(const Duration(milliseconds: 100));
        }

        expect(h.controller.state, isA<Playing>());
        expect(h.plugin.resolvedCount('b'), 1);
        expect(h.backend.nextSources, hasLength(1));
      });
    });

    test('next uses the prepared look-ahead without resolving again', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));

        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.currentIndex, 1);
        expect(h.openedPaths, ['/a.m4a', '/b.m4a']);
        expect(h.plugin.resolvedCount('b'), 1);
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('previous at the first track restarts it; next at the last does '
        'nothing', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 5));

        unawaited(h.controller.previous());
        h.settle();
        expect(h.controller.queue.currentIndex, 0);
        expect(h.openedPaths, ['/a.m4a']);

        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));
        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.queue.currentIndex, 1);
        expect(h.openedPaths, ['/a.m4a', '/b.m4a']);

        unawaited(h.controller.previous());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.queue.currentIndex, 0);
        expect(h.openedPaths, ['/a.m4a', '/b.m4a', '/a.m4a']);
      });
    });

    test('adding past the limit adds nothing and reports QueueFull; the '
        'current track goes on', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        final queue = h.controller.queue;
        final tooMany = [
          for (var i = 0; i < QueueModel.maxLength - 1; i++) track('$i'),
        ];

        expect(h.controller.addToQueue(tooMany), isFalse);
        expect(h.controller.playNext(tooMany), isFalse);
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue, same(queue));
        expect(h.events, [
          isA<QueueFull>().having((e) => e.limit, 'limit', 10000),
          isA<QueueFull>(),
        ]);
        expect(h.controller.state, isA<Playing>());
        expect(h.openedPaths, ['/a.m4a']);

        // 剛好到上限可以加。
        expect(h.controller.addToQueue(tooMany.sublist(1)), isTrue);
        expect(h.controller.queue.entries, hasLength(QueueModel.maxLength));
        expect(h.events, hasLength(2));
      });
    });

    test('pause, play and seek go to the backend', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(milliseconds: 100));

        unawaited(h.controller.pause());
        h.settle();
        expect(h.controller.state, isA<Paused>());
        expect(h.backend.playing, isFalse);

        unawaited(h.controller.play());
        h.settle();
        expect(h.controller.state, isA<Playing>());

        final positions = <Duration>[];
        h.controller.progress.listen((p) => positions.add(p.position));
        unawaited(h.controller.seek(const Duration(seconds: 30)));
        h.settle();
        expect(positions.last, const Duration(seconds: 30));
      });
    });

    test('pausing while loading stays paused once loaded', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        final h = Harness(
          async,
          respond: (request) async {
            await gate.future;
            return [candidate('${request.sourceId}.m4a')];
          },
        );
        unawaited(h.playQueue([track('a')]));
        h.settle();
        expect(h.controller.state, isA<Loading>());

        unawaited(h.controller.pause());
        gate.complete();
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Paused>());
        expect(h.backend.playing, isFalse);
      });
    });

    test('a seek while resolving is where the track starts', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        final h = Harness(
          async,
          trackLength: const Duration(seconds: 60),
          respond: (request) async {
            await gate.future;
            return [candidate('${request.sourceId}.m4a')];
          },
        );
        unawaited(h.playQueue([track('a')]));
        h.settle();
        unawaited(h.controller.seek(const Duration(seconds: 20)));
        gate.complete();
        h.elapse(const Duration(milliseconds: 100));

        expect(h.backend.openedAt, [const Duration(seconds: 20)]);
      });
    });

    test('disposing while resolving opens nothing and sets no look-ahead', () {
      fakeAsync((async) {
        final gates = {'a': Completer<void>(), 'b': Completer<void>()};
        final h = Harness(
          async,
          trackLength: const Duration(seconds: 60),
          respond: (request) async {
            await gates[request.sourceId]!.future;
            return [candidate('${request.sourceId}.m4a')];
          },
        );
        // a 載入好、b 的前瞻還在解析時 dispose。
        unawaited(h.playQueue([track('a'), track('b')]));
        gates['a']!.complete();
        h.elapse(const Duration(milliseconds: 100));
        expect(h.plugin.resolvedCount('b'), 1);
        unawaited(h.controller.dispose());
        gates['b']!.complete();
        h.elapse(const Duration(milliseconds: 100));
        expect(h.backend.nextSources, isEmpty);

        // 解析中 dispose：解析回來後不開流。
        final gate = Completer<void>();
        final h2 = Harness(
          async,
          respond: (request) async {
            await gate.future;
            return [candidate('${request.sourceId}.m4a')];
          },
        );
        unawaited(h2.playQueue([track('a')]));
        h2.settle();
        unawaited(h2.controller.dispose());
        gate.complete();
        h2.elapse(const Duration(milliseconds: 100));
        expect(h2.backend.opened, isEmpty);
      });
    });

    test('a superseded resolution is dropped', () {
      fakeAsync((async) {
        final slow = Completer<List<StreamCandidate>>();
        final h = Harness(
          async,
          respond: (request) => request.sourceId == 'a'
              ? slow.future
              : [candidate('${request.sourceId}.m4a')],
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.settle();
        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));
        slow.complete([candidate('a.m4a')]);
        h.elapse(const Duration(milliseconds: 100));

        expect(h.openedPaths, ['/b.m4a']);
        expect(h.controller.queue.currentIndex, 1);
      });
    });

    test('the backend only gets media headers', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          respond: (request) => [
            candidate(
              '${request.sourceId}.m4a',
              headers: {
                'Referer': 'https://www.example.test/',
                'Cookie': 'SESSDATA=FAKE_SESSDATA_123',
              },
            ),
          ],
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.backend.opened.single.headers, {
          'Referer': 'https://www.example.test/',
        });
        expect(h.backend.nextSources.last?.headers, {
          'Referer': 'https://www.example.test/',
        });
      });
    });
  });

  group('expiry', () {
    test('an expiring look-ahead is resolved again before the handover', () {
      fakeAsync((async) {
        late Harness h;
        h = Harness(
          async,
          trackLength: const Duration(minutes: 3),
          respond: (request) => [
            candidate(
              '${request.sourceId}-${h.plugin.requests.length}.m4a',
              expiresAt: h.now().add(const Duration(minutes: 6)),
            ),
          ],
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        expect(h.plugin.resolvedCount('b'), 1);
        final first = h.backend.nextSources.last;

        // 6 分鐘的期限、5 分鐘的餘裕：1 分鐘時換掉前瞻，不拿快取裡同一個網址。
        h.elapse(const Duration(minutes: 1));
        expect(h.plugin.resolvedCount('b'), 2);
        final refreshed = h.backend.nextSources.last;
        expect(refreshed?.id, isNot(first?.id));
        expect(refreshed?.url.path, isNot(first?.url.path));
        expect(h.logged('Look-ahead refreshed before expiry'), hasLength(1));

        h.elapse(const Duration(minutes: 2));
        expect(h.controller.queue.currentIndex, 1);
        expect(h.openedPaths, hasLength(1));
      });
    });

    test('next resolves again when the prepared look-ahead is stale', () {
      fakeAsync((async) {
        late Harness h;
        h = Harness(
          async,
          trackLength: const Duration(minutes: 10),
          respond: (request) => [
            candidate(
              '${request.sourceId}.m4a',
              // 解析出來就在 5 分鐘的餘裕內：不排重新解析、不進快取，到用的
              // 時候才檢查。
              expiresAt: h.now().add(const Duration(minutes: 4)),
            ),
          ],
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        expect(h.plugin.resolvedCount('b'), 1);

        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.plugin.resolvedCount('b'), 2);
        expect(h.logged('Look-ahead expired; resolving again'), hasLength(1));
        expect(h.openedPaths, ['/a.m4a', '/b.m4a']);
      });
    });

    test('a look-ahead outside the margin is used as it is', () {
      fakeAsync((async) {
        late Harness h;
        h = Harness(
          async,
          trackLength: const Duration(minutes: 10),
          respond: (request) => [
            candidate(
              '${request.sourceId}.m4a',
              expiresAt: h.now().add(const Duration(minutes: 6)),
            ),
          ],
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        // 離過期還有 5 分鐘多一點。
        h.elapse(const Duration(seconds: 50));

        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.plugin.resolvedCount('b'), 1);
        expect(h.logged('Look-ahead expired; resolving again'), isEmpty);
      });
    });
  });

  group('stream URL cache', () {
    test('playing a track the look-ahead resolved does not resolve it '
        'again', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        expect(h.plugin.resolvedCount('b'), 1);

        // 從搜尋結果再點 b（臨時播放）：前瞻已經放掉，網址從快取拿。
        unawaited(h.controller.playTemporary(track('b')));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Playing>());
        expect(h.openedPaths, ['/a.m4a', '/b.m4a']);
        expect(h.plugin.resolvedCount('b'), 1);
        expect(h.logged('Resolving stream'), hasLength(2));
      });
    });

    test(
      'a look-ahead slower than the current track is resolved only once',
      () {
        fakeAsync((async) {
          final gate = Completer<void>();
          final h = Harness(
            async,
            respond: (request) async {
              if (request.sourceId == 'b') await gate.future;
              return [candidate('${request.sourceId}.m4a')];
            },
          );
          unawaited(h.playQueue([track('a'), track('b')]));
          // a 播完（2 秒）時 b 的前瞻還在解析：照一般的下一首開始，共用同一個請求。
          h.elapse(const Duration(seconds: 3));
          expect(h.controller.queue.currentIndex, 1);
          expect(h.controller.state, isA<Loading>());

          gate.complete();
          h.elapse(const Duration(milliseconds: 100));
          expect(h.controller.state, isA<Playing>());
          expect(h.openedPaths, ['/a.m4a', '/b.m4a']);
          expect(h.plugin.resolvedCount('b'), 1);
          expect(h.backend.nextSources.nonNulls, isEmpty);
        });
      },
    );

    test('playing a track again uses the cached stream', () {
      fakeAsync((async) {
        final h = Harness(async);
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 3));
        expect(h.controller.state, isA<Idle>());

        unawaited(h.controller.play());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.openedPaths, ['/a.m4a', '/a.m4a']);
        expect(h.plugin.resolvedCount('a'), 1);
      });
    });

    test('a stream that failed to open is resolved again next time', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          respond: (request) => [
            candidate('${request.sourceId}-1.m4a'),
            candidate('${request.sourceId}-2.m4a'),
          ],
          failsToOpen: (url) => url.path == '/a-1.m4a',
        );
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 3));
        expect(h.openedPaths, ['/a-1.m4a', '/a-2.m4a']);
        expect(h.plugin.resolvedCount('a'), 1);
        expect(h.logged('Stream URL invalidated'), hasLength(1));

        unawaited(h.controller.play());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.plugin.resolvedCount('a'), 2);
      });
    });
  });

  group('recovery', () {
    test(
      'a stream that cannot be opened switches to the next candidate once',
      () {
        fakeAsync((async) {
          final h = Harness(
            async,
            respond: (request) => [
              candidate('${request.sourceId}-1.m4a'),
              candidate('${request.sourceId}-2.m4a'),
              candidate('${request.sourceId}-3.m4a'),
            ],
            failsToOpen: (url) => !url.path.startsWith('/a-2'),
          );
          unawaited(h.playQueue([track('a'), track('b')]));
          h.elapse(const Duration(milliseconds: 100));

          expect(h.openedPaths, ['/a-1.m4a', '/a-2.m4a']);
          expect(h.controller.state, isA<Playing>());
          expect(h.plugin.resolvedCount('a'), 1);
        });
      },
    );

    test('after the second candidate fails too the track is skipped', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          respond: (request) => [
            candidate('${request.sourceId}-1.m4a'),
            candidate('${request.sourceId}-2.m4a'),
            candidate('${request.sourceId}-3.m4a'),
          ],
          failsToOpen: (url) => url.path.startsWith('/a-'),
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.openedPaths, ['/a-1.m4a', '/a-2.m4a', '/b-1.m4a']);
        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('NotFound skips to the next track at once', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          respond: (request) => request.sourceId == 'a'
              ? throw NotFound(pluginId: 'fmp-test')
              : [candidate('${request.sourceId}.m4a')],
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.currentIndex, 1);
        expect(h.openedPaths, ['/b.m4a']);
        expect(h.states.whereType<Retrying>(), isEmpty);
      });
    });

    test('network errors retry after 1, 3 and 9 seconds, then skip', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          respond: (request) => request.sourceId == 'a'
              ? throw NetworkError(pluginId: 'fmp-test')
              : [candidate('${request.sourceId}.m4a')],
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.settle();
        expect(
          h.controller.state,
          isA<Retrying>()
              .having((s) => s.attempt, 'attempt', 1)
              .having((s) => s.delay, 'delay', const Duration(seconds: 1))
              .having((s) => s.error, 'error', isA<NetworkError>()),
        );

        h.elapse(const Duration(seconds: 1));
        expect(h.plugin.resolvedCount('a'), 2);
        expect(
          h.controller.state,
          isA<Retrying>().having((s) => s.attempt, 'attempt', 2),
        );

        h.elapse(const Duration(seconds: 3));
        expect(h.plugin.resolvedCount('a'), 3);
        expect(
          h.controller.state,
          isA<Retrying>().having((s) => s.attempt, 'attempt', 3),
        );

        h.elapse(const Duration(seconds: 9));
        expect(h.plugin.resolvedCount('a'), 4);
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('an interrupted stream retries from its position', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 5));

        h.backend.interrupt();
        h.settle();
        expect(h.controller.state, isA<Retrying>());

        h.elapse(const Duration(seconds: 1));
        expect(h.plugin.resolvedCount('a'), 2);
        expect(
          h.backend.openedAt.last,
          greaterThanOrEqualTo(const Duration(seconds: 4)),
        );
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('a seek while waiting to retry is where the retry starts', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 5));

        h.backend.interrupt();
        h.settle();
        expect(h.controller.state, isA<Retrying>());
        unawaited(h.controller.seek(const Duration(seconds: 30)));
        h.elapse(const Duration(seconds: 1));

        expect(h.backend.openedAt.last, const Duration(seconds: 30));
      });
    });

    test('stops once the whole queue has been skipped', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          respond: (_) => throw NotFound(pluginId: 'fmp-test'),
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));

        expect(
          h.controller.state,
          isA<Failed>().having((s) => s.error, 'error', isA<NotFound>()),
        );
        expect(h.plugin.requests, hasLength(2));
        expect(h.backend.current, isNull);

        // 再按播放從目前這首（b）重新開始，連續跳過的計數歸零。
        unawaited(h.controller.play());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.plugin.requests, hasLength(3));
      });
    });

    test('a source not installed is skipped like any unplayable track', () {
      fakeAsync((async) {
        final h = Harness(async);
        unawaited(
          h.playQueue([
            const TrackInfo(sourceTypeId: 'missing', sourceId: 'x', title: 'x'),
            track('b'),
          ]),
        );
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.state, isA<Playing>());
      });
    });
  });

  group('temporary play', () {
    /// 佇列 a、b 播到 a 的 30 秒，臨時播放 x 播了 5 秒。
    Harness startTemporary(FakeAsync async, {bool pauseFirst = false}) {
      final h = Harness(async, trackLength: const Duration(seconds: 60));
      unawaited(h.playQueue([track('a'), track('b')]));
      h.elapse(const Duration(seconds: 30));
      if (pauseFirst) {
        unawaited(h.controller.pause());
        h.settle();
      }
      unawaited(h.controller.playTemporary(track('x')));
      h.elapse(const Duration(seconds: 5));
      expect(h.controller.queue.mode, QueueMode.temporary);
      expect(h.controller.queue.current?.sourceId, 'x');
      expect(h.controller.state, isA<Playing>());
      return h;
    }

    void expectBackAtA(Harness h, {required int atMs}) {
      expect(h.controller.queue.mode, QueueMode.queue);
      expect(h.controller.queue.currentIndex, 0);
      expect(h.openedPaths, ['/a.m4a', '/x.m4a', '/a.m4a']);
      expect(
        h.backend.openedAt.last.inMilliseconds,
        atMs == 0 ? 0 : closeTo(atMs, 100),
      );
    }

    for (final (name, trigger) in <(String, void Function(Harness))>[
      (
        'the temporary track ends',
        (h) => h.elapse(const Duration(seconds: 56)),
      ),
      ('next is pressed', (h) => unawaited(h.controller.next())),
      ('previous is pressed', (h) => unawaited(h.controller.previous())),
    ]) {
      test('returns to the queue track 10 s back when $name', () {
        fakeAsync((async) {
          final h = startTemporary(async);

          trigger(h);
          h.elapse(const Duration(milliseconds: 100));

          expectBackAtA(h, atMs: 20000);
          expect(h.controller.state, isA<Playing>());
          // 回到的那首與它之後的前瞻都從網址快取拿。
          expect(h.plugin.resolvedCount('a'), 1);
          expect(h.plugin.resolvedCount('b'), 1);
        });
      });
    }

    for (final (remember, rewind, atMs) in [
      (true, 10, 20000),
      (true, 0, 30000),
      (false, 10, 0),
      (false, 0, 0),
    ]) {
      test('remember position $remember, rewind $rewind s: back at '
          '${atMs ~/ 1000} s', () {
        fakeAsync((async) {
          final h = startTemporary(async)
            ..returnSettings = (
              rememberPosition: remember,
              rewind: Duration(seconds: rewind),
            );

          unawaited(h.controller.next());
          h.elapse(const Duration(milliseconds: 100));

          expectBackAtA(h, atMs: atMs);
        });
      });
    }

    test('a queue that was paused is only loaded, not played', () {
      fakeAsync((async) {
        final h = startTemporary(async, pauseFirst: true);

        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));

        expectBackAtA(h, atMs: 20000);
        expect(h.controller.state, isA<Paused>());
        expect(h.backend.playing, isFalse);
      });
    });

    test('a second temporary play keeps the first return point', () {
      fakeAsync((async) {
        final h = startTemporary(async);
        unawaited(h.controller.playTemporary(track('y')));
        h.elapse(const Duration(seconds: 5));

        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));

        expect(h.openedPaths, ['/a.m4a', '/x.m4a', '/y.m4a', '/a.m4a']);
        expect(h.backend.openedAt.last.inMilliseconds, closeTo(20000, 100));
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('prepares no look-ahead, so the queue track is never handed over '
        'from its start', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..returnSettings = (rememberPosition: true, rewind: Duration.zero);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 1));
        final lookAheads = h.backend.nextSources.length;

        unawaited(h.controller.playTemporary(track('x')));
        h.elapse(const Duration(milliseconds: 1500));
        expect(h.backend.nextSources, hasLength(lookAheads));

        // x（2 秒）播完：a 從快照的位置重新開流，不是由引擎從頭接上。
        h.elapse(const Duration(seconds: 1));
        expect(h.logged('Look-ahead handover'), isEmpty);
        expect(h.openedPaths, ['/a.m4a', '/x.m4a', '/a.m4a']);
        expect(h.backend.openedAt.last.inMilliseconds, closeTo(1000, 100));
      });
    });

    test('over an empty queue, songs added meanwhile wait in Idle', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.controller.playTemporary(track('x')));
        h.elapse(const Duration(seconds: 5));
        expect(h.controller.addToQueue([track('a')]), isTrue);
        expect(h.controller.playNext([track('b')]), isTrue);

        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Idle>());
        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.controller.queue.current?.sourceId, 'a');
        expect(h.openedPaths, ['/x.m4a']);
        expect(h.plugin.resolvedCount('a'), 0);

        unawaited(h.controller.play());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.openedPaths, ['/x.m4a', '/a.m4a']);
        expect(h.backend.openedAt.last, Duration.zero);
      });
    });

    test('over an empty queue, next is enabled and ends it in Idle', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.controller.playTemporary(track('x')));
        h.elapse(const Duration(seconds: 1));
        expect(h.controller.queue.hasNext, isTrue);

        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Idle>());
        expect(h.controller.queue.current, isNull);
        expect(h.backend.current, isNull);
      });
    });

    test('a temporary track that cannot be played returns to the queue', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          trackLength: const Duration(seconds: 60),
          respond: (request) => request.sourceId == 'x'
              ? throw NotFound(pluginId: 'fmp-test')
              : [candidate('${request.sourceId}.m4a')],
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 30));

        unawaited(h.controller.playTemporary(track('x')));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.controller.queue.currentIndex, 0);
        expect(h.backend.openedAt.last.inMilliseconds, closeTo(20000, 100));
        expect(h.controller.state, isA<Playing>());
      });
    });
  });

  group('loop one', () {
    /// 循環依 off → all → one 輪轉。
    void loopOne(Harness h) {
      h.controller
        ..cycleLoopMode()
        ..cycleLoopMode();
      expect(h.controller.queue.loopMode, LoopMode.one);
    }

    int resolutionsOf(Harness h, String id) => h
        .logged('Resolving stream')
        .where((r) => r.fields['track'] == 'fmp-test:$id')
        .length;

    test('two rounds hand over the same stream; it is resolved once', () {
      fakeAsync((async) {
        final h = Harness(async);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        loopOne(h);
        h.settle();
        expect(h.backend.nextSources.last?.url.path, '/a.m4a');

        h.elapse(const Duration(milliseconds: 4200));

        expect(h.logged('Look-ahead handover'), hasLength(2));
        expect(h.logged('Look-ahead handover').map((r) => r.fields['repeat']), [
          true,
          true,
        ]);
        expect(h.controller.queue.currentIndex, 0);
        expect(h.controller.state, isA<Playing>());
        expect(h.openedPaths, ['/a.m4a']);
        expect(resolutionsOf(h, 'a'), 1);
      });
    });

    test('a stream about to expire is resolved again before the repeat', () {
      fakeAsync((async) {
        late Harness h;
        h = Harness(
          async,
          trackLength: const Duration(seconds: 3),
          respond: (request) => [
            candidate(
              '${request.sourceId}.m4a',
              expiresAt: h.now().add(
                ResolvedStream.expiryMargin + const Duration(seconds: 1),
              ),
            ),
          ],
        );
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(milliseconds: 100));
        loopOne(h);

        // 網址在解析後 1 秒進入餘裕：重播用的前瞻那時重新解析。
        h.elapse(const Duration(milliseconds: 1500));
        expect(resolutionsOf(h, 'a'), 2);
        expect(h.logged('Look-ahead refreshed before expiry'), hasLength(1));

        h.elapse(const Duration(milliseconds: 1500));
        expect(h.logged('Look-ahead handover'), hasLength(1));
        expect(h.controller.queue.currentIndex, 0);
        expect(h.openedPaths, ['/a.m4a']);
      });
    });

    test('in a temporary play it repeats the temporary track, which still '
        'returns to the queue', () {
      fakeAsync((async) {
        final h = Harness(async)
          ..returnSettings = (rememberPosition: true, rewind: Duration.zero);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 1));
        loopOne(h);
        unawaited(h.controller.playTemporary(track('x')));

        h.elapse(const Duration(milliseconds: 4200));
        expect(h.logged('Look-ahead handover'), hasLength(2));
        expect(h.controller.queue.mode, QueueMode.temporary);
        expect(h.controller.queue.current?.sourceId, 'x');
        expect(resolutionsOf(h, 'x'), 1);

        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.controller.queue.currentIndex, 0);
        expect(h.openedPaths, ['/a.m4a', '/x.m4a', '/a.m4a']);
        expect(h.backend.openedAt.last.inMilliseconds, closeTo(1000, 100));
      });
    });
  });

  group('editing the queue prepares the look-ahead again', () {
    /// 佇列 [ids] 從第一首開始播、前瞻已經準備好。
    Harness playing(FakeAsync async, List<String> ids) {
      final h = Harness(async);
      unawaited(h.playQueue([for (final id in ids) track(id)]));
      h.elapse(const Duration(milliseconds: 100));
      return h;
    }

    /// 前瞻是 [id]，a 播完時交接到它（沒有再開流）。
    void expectHandoverTo(Harness h, String id) {
      h.settle();
      expect(h.backend.nextSources.last?.url.path, '/$id.m4a');
      h.elapse(const Duration(seconds: 2));
      expect(h.controller.queue.current?.sourceId, id);
      expect(
        h.logged('Look-ahead handover').single.fields['to'],
        'fmp-test:$id',
      );
      expect(h.openedPaths, ['/a.m4a']);
    }

    test('dragging another song into the next place', () {
      fakeAsync((async) {
        final h = playing(async, ['a', 'b', 'c', 'd']);
        h.controller.move(2, 1);
        expectHandoverTo(h, 'c');
      });
    });

    test('play next', () {
      fakeAsync((async) {
        final h = playing(async, ['a', 'b', 'c']);
        expect(h.controller.playNext([track('x')]), isTrue);
        expectHandoverTo(h, 'x');
      });
    });

    test('adding to a queue that had no next song', () {
      fakeAsync((async) {
        final h = playing(async, ['a']);
        expect(h.backend.nextSources, isEmpty);
        expect(h.controller.addToQueue([track('b')]), isTrue);
        expectHandoverTo(h, 'b');
      });
    });

    test('removing the next song', () {
      fakeAsync((async) {
        final h = playing(async, ['a', 'b', 'c']);
        unawaited(h.controller.removeAt(1));
        expectHandoverTo(h, 'c');
      });
    });

    test('turning shuffle on', () {
      fakeAsync((async) {
        final h = playing(async, ['a', 'b', 'c', 'd', 'e', 'f']);
        h.controller.setShuffle(true);
        final queue = h.controller.queue;
        final next = queue.entries[queue.shuffleOrder![1]].track.sourceId;
        expectHandoverTo(h, next);
      });
    });

    test('the engine taking over the replaced look-ahead plays the new next '
        'song', () {
      fakeAsync((async) {
        final h = playing(async, ['a', 'b', 'c']);
        final gate = Completer<void>();
        h.backend.setNextGate = gate.future;

        // 清掉 b 的修改還在排隊時 a 播完，引擎接上了 b。
        h.controller.move(2, 1);
        h.elapse(const Duration(seconds: 2));

        expect(h.controller.queue.current?.sourceId, 'c');
        expect(h.openedPaths, ['/a.m4a', '/c.m4a']);
        expect(h.logged('Look-ahead handover'), isEmpty);
        gate.complete();
        h.elapse(const Duration(milliseconds: 100));
        expect(h.backend.current?.url.path, '/c.m4a');
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('the engine taking over the look-ahead of a removed last song stops '
        'it in Idle', () {
      fakeAsync((async) {
        final h = playing(async, ['a', 'b']);
        final gate = Completer<void>();
        h.backend.setNextGate = gate.future;

        // 清掉 b 的修改還在排隊時 a 播完，引擎接上了 b；佇列已經沒有下一首。
        unawaited(h.controller.removeAt(1));
        h.elapse(const Duration(seconds: 2));

        expect(h.controller.state, isA<Idle>());
        expect(h.backend.playing, isFalse, reason: 'b must not be heard');
        gate.complete();
        h.elapse(const Duration(seconds: 3));
        expect(h.backend.playing, isFalse);
        expect(h.openedPaths, ['/a.m4a']);
        expect(h.logged('Look-ahead handover'), isEmpty);
      });
    });

    test('an edit that keeps the next song keeps the look-ahead', () {
      fakeAsync((async) {
        final h = playing(async, ['a', 'b', 'c', 'd']);
        final lookAheads = h.backend.nextSources.length;

        h.controller.move(3, 2);
        h.settle();

        expect(h.backend.nextSources, hasLength(lookAheads));
        expectHandoverTo(h, 'b');
      });
    });
  });

  group('queue operations', () {
    test('previous within 3 s goes back; after 3 s it restarts the track', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        unawaited(h.controller.next());
        h.elapse(const Duration(seconds: 4));
        final positions = <Duration>[];
        h.controller.progress.listen((p) => positions.add(p.position));

        unawaited(h.controller.previous());
        h.settle();
        expect(h.controller.queue.currentIndex, 1);
        expect(h.openedPaths, ['/a.m4a', '/b.m4a']);
        expect(positions.last, Duration.zero);

        h.elapse(const Duration(seconds: 1));
        unawaited(h.controller.previous());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.queue.currentIndex, 0);
        expect(h.openedPaths, ['/a.m4a', '/b.m4a', '/a.m4a']);
      });
    });

    test('jumping to a song plays it and ends a temporary play', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a'), track('b'), track('c')]));
        h.elapse(const Duration(milliseconds: 100));
        unawaited(h.controller.playTemporary(track('x')));
        h.elapse(const Duration(milliseconds: 100));

        unawaited(h.controller.jumpTo(2));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.controller.queue.currentIndex, 2);
        expect(h.openedPaths.last, '/c.m4a');
        expect(h.backend.openedAt.last, Duration.zero);
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('removing the playing song plays the next one; removing the last '
        'song stops', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));

        unawaited(h.controller.removeAt(0));
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.queue.current?.sourceId, 'b');
        expect(h.openedPaths, ['/a.m4a', '/b.m4a']);
        expect(h.controller.state, isA<Playing>());

        unawaited(h.controller.removeAt(0));
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.queue.current, isNull);
        expect(h.controller.state, isA<Idle>());
        expect(h.backend.current, isNull);
      });
    });

    test('clearing stops in Idle and ends a temporary play', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        unawaited(h.controller.playTemporary(track('x')));
        h.elapse(const Duration(milliseconds: 100));

        unawaited(h.controller.clear());
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.entries, isEmpty);
        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.controller.state, isA<Idle>());
        expect(h.backend.current, isNull);
      });
    });

    test('adding to an empty queue shows the song without playing it', () {
      fakeAsync((async) {
        final h = Harness(async);
        expect(h.controller.addToQueue([track('a')]), isTrue);
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.current?.sourceId, 'a');
        expect(h.controller.state, isA<Idle>());
        expect(h.plugin.requests, isEmpty);
      });
    });
  });

  group('engine messages in the log', () {
    // 引擎的錯誤可能帶完整的簽名網址（YouTube.js 探針看到 mpv 的
    // `ffmpeg: Opening '…/videoplayback?…'`）。後端以 SourceFailed.cause 交出，
    // 控制器只以 error 交給 log 門面：記憶體歷史與 log 檔都要是遮過的。
    const secrets = [
      'FAKE_SIG_VALUE_123',
      'FAKE_LSIG_VALUE_456',
      'FAKE_N_VALUE_789',
      '203.0.113.9',
      'FAKE_UPSIG_VALUE',
      'FAKE_E_VALUE',
      '1790000001',
    ];
    const signedUrl =
        'https://rr3---sn-fake.googlevideo.com/videoplayback?expire=1790000000'
        '&ei=FAKE_EI&ip=203.0.113.9&id=o-FAKE&itag=251'
        '&sig=FAKE_SIG_VALUE_123&lsig=FAKE_LSIG_VALUE_456&n=FAKE_N_VALUE_789';
    const bilibiliUrl =
        'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/x.m4s'
        '?e=FAKE_E_VALUE&deadline=1790000001&upsig=FAKE_UPSIG_VALUE';

    for (final (name, cause, host) in <(String, Object, String)>[
      ('an mpv log line', "ffmpeg: Opening '$signedUrl'", 'googlevideo.com'),
      (
        'an exception',
        HttpException('Source error', uri: Uri.parse(signedUrl)),
        'googlevideo.com',
      ),
      (
        'a Bilibili mpv log line',
        'ffmpeg: tcp: Connection to $bilibiliUrl failed',
        'bilivideo.com',
      ),
    ]) {
      test(
        'a signed URL in $name is redacted in the history and the file',
        () async {
          final temp = await Directory.systemTemp.createTemp(
            'fmp_playback_log',
          );
          addTearDown(() => temp.delete(recursive: true));
          final log = Log(
            redactor: Redactor(),
            minimumLevel: LogLevel.debug,
            file: LogFile(Directory(p.join(temp.path, logDirectoryName))),
          );
          final plugin = FakeSourcePlugin((_) => [candidate('a.m4a')]);
          final backend = FakeAudioBackend(
            durationOf: (_) => const Duration(minutes: 5),
          );
          final controller = PlaybackController(
            session: PlaybackSession(
              backend: backend,
              resolver: StreamResolver(
                plugin: (_) => plugin,
                formats: const [PlayableFormat('mp4', 'aac')],
                log: log,
              ),
              log: log,
            ),
            log: log,
            temporaryReturnSettings: () =>
                (rememberPosition: true, rewind: Duration.zero),
          );
          addTearDown(controller.dispose);
          addTearDown(backend.dispose);

          controller.addToQueue([track('a')]);
          await controller.play();
          await pumpUntil(() => controller.state is Playing);
          backend.interrupt(cause: cause);
          await pumpUntil(() => controller.state is Retrying);
          await log.file!.flush();

          final history = log.history.map((r) => r.toJsonLine()).join('\n');
          final file = await log.file!.currentFile.readAsString();
          expect(log.history.map((r) => r.message), contains('Stream failed'));
          expect(file, contains(host));
          for (final secret in secrets) {
            expect(history, isNot(contains(secret)), reason: 'history');
            expect(file, isNot(contains(secret)), reason: 'file');
          }
        },
      );
    }
  });
}
