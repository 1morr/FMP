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
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/playback/playback_controller.dart';
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
    );
    controller.states.listen(states.add);
  }

  final FakeAsync async;
  final FakeSourcePlugin plugin;
  final FakeAudioBackend backend;
  final log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
  late final PlaybackController controller;
  final states = <PlaybackState>[];

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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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

    test('a queue past the limit is not played; the current one goes on', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.controller.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        final queue = h.controller.queue;

        unawaited(
          h.controller.playQueue([
            for (var i = 0; i <= QueueModel.maxLength; i++) track('$i'),
          ]),
        );
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.queue, same(queue));
        expect(h.controller.state, isA<Playing>());
        expect(h.openedPaths, ['/a.m4a']);
      });
    });

    test('pause, play and seek go to the backend', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.controller.playQueue([track('a')]));
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
        unawaited(h.controller.playQueue([track('a')]));
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
        unawaited(h.controller.playQueue([track('a')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h2.controller.playQueue([track('a')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        expect(h.plugin.resolvedCount('b'), 1);

        // 從搜尋結果再點 b：前瞻已經放掉，網址從快取拿。
        unawaited(
          h.controller.playQueue([track('a'), track('b')], startIndex: 1),
        );
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
          unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 3));
        expect(h.controller.state, isA<Idle>());

        unawaited(h.controller.playQueue([track('a')]));
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
        unawaited(h.controller.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 3));
        expect(h.openedPaths, ['/a-1.m4a', '/a-2.m4a']);
        expect(h.plugin.resolvedCount('a'), 1);
        expect(h.logged('Stream URL invalidated'), hasLength(1));

        unawaited(h.controller.playQueue([track('a')]));
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
          unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
        unawaited(h.controller.playQueue([track('a')]));
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
        unawaited(h.controller.playQueue([track('a')]));
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
        unawaited(h.controller.playQueue([track('a'), track('b')]));
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
          h.controller.playQueue([
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
          );
          addTearDown(controller.dispose);
          addTearDown(backend.dispose);

          await controller.playQueue([track('a')]);
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
