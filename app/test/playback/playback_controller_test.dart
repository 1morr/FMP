import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/domain/stream_preferences.dart';
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
    int? Function(Uri url)? httpStatusOf,
    FakeOutputDevices? outputDevices,
  }) : plugin = FakeSourcePlugin(
         respond ?? (request) => [candidate('${request.sourceId}.m4a')],
       ),
       backend = FakeAudioBackend(
         durationOf: (_) => trackLength,
         failsToOpen: failsToOpen ?? (_) => false,
         httpStatusOf: httpStatusOf ?? (_) => null,
         outputDevices: outputDevices,
       ) {
    controller = PlaybackController(
      session: PlaybackSession(
        backend: backend,
        resolver: StreamResolver(
          plugin: (id) => id == plugin.manifest.id ? plugin : null,
          formats: const [PlayableFormat('mp4', 'aac')],
          preferences: () => streamPreferences,
          log: log,
        ),
        log: log,
      ),
      log: log,
      temporaryReturnSettings: () => returnSettings,
      skipPreviewClips: () => skipPreviewClips,
      networkStatus: () => network,
      networkStatusChanges: _networkChanges.stream,
      preferredOutputDevice: () async => preferredOutputDevice,
      saveOutputDevice: (device) async => savedOutputDevices.add(device),
    );
    controller.states.listen(states.add);
    controller.events.listen(events.add);
    controller.plays.listen(plays.add);
  }

  final _networkChanges = StreamController<NetworkStatus>.broadcast();

  /// 控制器讀到的網路狀態；改它用 [setNetwork]。
  NetworkStatus network = NetworkStatus.online;

  /// 「跳過試聽片段」（預設同 App 的預設：開）。
  bool skipPreviewClips = true;

  /// 送給插件的偏好（預設同 App 的預設：高音質、Opus 優先）。
  StreamPreferences streamPreferences = (
    quality: AudioQuality.high,
    formatPriority: AudioFormatPriority.opusFirst,
  );

  /// 記住的輸出裝置 id（「播放」設定的 `output_device_id`）。
  String? preferredOutputDevice;

  /// 控制器每次寫進設定的輸出裝置，依序。
  final savedOutputDevices = <OutputDevice?>[];

  /// 網路狀態變成 [status]，並通知控制器。
  void setNetwork(NetworkStatus status) {
    network = status;
    _networkChanges.add(status);
    settle();
  }

  final FakeAsync async;
  final FakeSourcePlugin plugin;
  final FakeAudioBackend backend;
  final log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
  late final PlaybackController controller;
  final states = <PlaybackState>[];
  final events = <PlaybackEvent>[];

  /// 控制器報的每一次「這一首算一次播放」，依序。
  final plays = <CountedPlay>[];

  /// [plays] 的曲目 id。
  List<String> get playedIds => [for (final play in plays) play.track.sourceId];

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

    test('the opened candidate is logged with its format and bitrate', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          respond: (request) async => [
            candidate(
              '${request.sourceId}.m4a',
              headers: const {'Referer': 'https://cdn.example/'},
              bitrate: 66000,
            ),
          ],
        );
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(milliseconds: 100));

        // 實機驗證音質偏好時讀這一筆（M2 PR 8）；標頭只記名稱。
        expect(h.logged('Opening stream').single.fields, {
          'track': 'fmp-test:a',
          'candidate': 0,
          'container': 'mp4',
          'codec': 'aac',
          'bitrate': 66000,
          'headers': ['Referer'],
        });
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

    test('after the quality changes the track is resolved again with it', () {
      fakeAsync((async) {
        final h = Harness(async);
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 3));
        expect(h.controller.state, isA<Idle>());

        h.streamPreferences = (
          quality: AudioQuality.low,
          formatPriority: AudioFormatPriority.opusFirst,
        );
        unawaited(h.controller.play());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.plugin.resolvedCount('a'), 2);
        expect(h.plugin.requests.last.quality, AudioQuality.low);
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
        // 沒有狀態碼：先重新解析一次（插件回同樣的網址），再換候選。
        expect(h.openedPaths, ['/a-1.m4a', '/a-1.m4a', '/a-2.m4a']);
        expect(h.plugin.resolvedCount('a'), 2);
        expect(h.logged('Stream URL invalidated'), hasLength(2));

        // 再播一次：快取裡沒有它，重新解析；第一個候選照樣開不起來，又走一次
        // 重新解析與換候選。
        unawaited(h.controller.play());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.plugin.resolvedCount('a'), 4);
        expect(h.openedPaths.last, '/a-2.m4a');
      });
    });
  });

  // 假後端照契約：前瞻開不起來時，交接那一刻先報前瞻失敗、再報目前這首播完
  // （ExoPlayer 的形狀）。
  group('a look-ahead that cannot be opened', () {
    test('the current track plays on to its end; the next is resolved again '
        'when its turn comes', () {
      fakeAsync((async) {
        var resolutions = 0;
        final h = Harness(
          async,
          respond: (request) => [
            candidate(
              request.sourceId == 'b'
                  ? 'b-${++resolutions}.m4a'
                  : '${request.sourceId}.m4a',
            ),
          ],
          failsToOpen: (url) => url.path == '/b-1.m4a',
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        expect(h.backend.nextSources.last?.url.path, '/b-1.m4a');

        h.elapse(const Duration(seconds: 2));
        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.state, isA<Playing>());
        // 失敗的網址作廢了：b 重新解析、開的是新的網址；a 只開過一次、沒有重試。
        expect(h.openedPaths, ['/a.m4a', '/b-2.m4a']);
        expect(h.plugin.resolvedCount('a'), 1);
        expect(h.plugin.resolvedCount('b'), 2);
        expect(h.logged('Look-ahead failed to open'), hasLength(1));
        expect(
          h.logged('Look-ahead failed to open').single.fields,
          containsPair('track', 'fmp-test:b'),
        );
        expect(h.logged('Stream URL invalidated'), hasLength(1));
        expect(h.logged('Look-ahead handover'), isEmpty);
        expect(h.logged('Playback recovery'), isEmpty);
        expect(h.states.whereType<Retrying>(), isEmpty);
      });
    });

    test('when the next track fails again it goes through recovery', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          respond: (request) => [
            candidate('${request.sourceId}-1.m4a'),
            candidate('${request.sourceId}-2.m4a'),
          ],
          failsToOpen: (url) => url.path == '/b-1.m4a',
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 2, milliseconds: 100));

        // 重新解析還是同一個網址（插件就是這麼回）：開不起來、沒有狀態碼，
        // 再重新解析一次，仍開不起來就換候選。
        expect(h.openedPaths, ['/a-1.m4a', '/b-1.m4a', '/b-1.m4a', '/b-2.m4a']);
        expect(h.plugin.resolvedCount('b'), 3);
        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.state, isA<Playing>());
        expect(h.logged('Playback recovery').map((r) => r.fields['action']), [
          'reResolve',
          'nextCandidate',
        ]);
      });
    });

    test('an HTTP status from the backend goes into the log', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          failsToOpen: (url) => url.path == '/b.m4a',
          httpStatusOf: (url) => url.path == '/b.m4a' ? 403 : null,
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 2, milliseconds: 100));

        expect(
          h.logged('Look-ahead failed to open').single.fields,
          containsPair('httpStatus', 403),
        );
        expect(
          h.logged('Stream failed').map((r) => r.fields['httpStatus']),
          everyElement(403),
        );
        expect(h.logged('Stream failed'), isNotEmpty);
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

          // 沒有狀態碼的先重新解析一次（design §7.5），之後才換候選。
          expect(h.openedPaths, ['/a-1.m4a', '/a-1.m4a', '/a-2.m4a']);
          expect(h.controller.state, isA<Playing>());
          expect(h.plugin.resolvedCount('a'), 2);
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

        expect(h.openedPaths, ['/a-1.m4a', '/a-1.m4a', '/a-2.m4a', '/b-1.m4a']);
        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.state, isA<Playing>());
        expect(
          h.events.single,
          isA<TrackSkipped>()
              .having((e) => e.error, 'error', isA<Unsupported>())
              .having((e) => e.track, 'track', track('a')),
        );
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
        // 第一首跳過，第二首停下：停下只提示一次。
        expect(h.events, [
          isA<TrackSkipped>().having((e) => e.track, 'track', track('a')),
          isA<PlaybackStopped>()
              .having((e) => e.track, 'track', track('b'))
              .having((e) => e.failedInARow, 'failedInARow', 2)
              .having((e) => e.error, 'error', isA<NotFound>()),
        ]);

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

  // design §7.5 的表在控制器上的樣子（純規則在 recovery_policy_test.dart）。
  group('recovery: refused and unopenable streams', () {
    List<Object?> actions(Harness h) => [
      for (final record in h.logged('Playback recovery'))
        record.fields['action'],
    ];

    test('a 403 resolves again first; a fresh URL plays', () {
      fakeAsync((async) {
        var resolutions = 0;
        final h = Harness(
          async,
          respond: (request) => [
            candidate('${request.sourceId}-${++resolutions}.m4a'),
          ],
          failsToOpen: (url) => url.path == '/a-1.m4a',
          httpStatusOf: (_) => 403,
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.openedPaths, ['/a-1.m4a', '/a-2.m4a']);
        expect(h.plugin.resolvedCount('a'), 2);
        expect(h.controller.state, isA<Playing>());
        expect(h.controller.queue.currentIndex, 0);
        expect(actions(h), ['reResolve']);
        expect(h.events, isEmpty);
      });
    });

    test('still refused: the next candidate once, then skipped as '
        'Unavailable without a reason', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          respond: (request) => [
            candidate('${request.sourceId}-1.m4a'),
            candidate('${request.sourceId}-2.m4a'),
          ],
          failsToOpen: (url) => url.path.startsWith('/a-'),
          httpStatusOf: (_) => 403,
        );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.openedPaths, ['/a-1.m4a', '/a-1.m4a', '/a-2.m4a', '/b-1.m4a']);
        expect(actions(h), ['reResolve', 'nextCandidate', 'skip']);
        expect(
          h.events.single,
          isA<TrackSkipped>().having(
            (e) => e.error,
            'error',
            isA<Unavailable>().having((e) => e.reason, 'reason', isNull),
          ),
        );
        expect(h.controller.queue.currentIndex, 1);
      });
    });

    for (final status in [404, 410]) {
      test('$status: resolves again once, then skipped as NotFound', () {
        fakeAsync((async) {
          final h = Harness(
            async,
            failsToOpen: (url) => url.path == '/a.m4a',
            httpStatusOf: (_) => status,
          );
          unawaited(h.playQueue([track('a'), track('b')]));
          h.elapse(const Duration(milliseconds: 100));

          expect(h.openedPaths, ['/a.m4a', '/a.m4a', '/b.m4a']);
          expect(actions(h), ['reResolve', 'skip']);
          expect(
            h.events.single,
            isA<TrackSkipped>().having(
              (e) => e.error,
              'error',
              isA<NotFound>(),
            ),
          );
        });
      });
    }

    // Android（just_audio）的開流失敗一律沒有狀態碼（design §7.6 的更正）。
    test('without a status it also resolves again first', () {
      fakeAsync((async) {
        var resolutions = 0;
        final h = Harness(
          async,
          respond: (request) => [
            candidate('${request.sourceId}-${++resolutions}.m4a'),
          ],
          failsToOpen: (url) => url.path == '/a-1.m4a',
        );
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.openedPaths, ['/a-1.m4a', '/a-2.m4a']);
        expect(h.controller.state, isA<Playing>());
        expect(actions(h), ['reResolve']);
      });
    });

    test('another status switches the candidate without resolving again', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          respond: (request) => [
            candidate('${request.sourceId}-1.m4a'),
            candidate('${request.sourceId}-2.m4a'),
          ],
          failsToOpen: (url) => url.path == '/a-1.m4a',
          httpStatusOf: (_) => 500,
        );
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.openedPaths, ['/a-1.m4a', '/a-2.m4a']);
        expect(h.plugin.resolvedCount('a'), 1);
        expect(actions(h), ['nextCandidate']);
      });
    });
  });

  group('recovery: offline (design §5.3)', () {
    test('a network error while offline waits without counting or skipping, '
        'and retries as soon as the network is back', () {
      fakeAsync((async) {
        var failing = true;
        final h = Harness(
          async,
          respond: (request) => failing && request.sourceId == 'a'
              ? throw NetworkError(pluginId: 'fmp-test')
              : [candidate('${request.sourceId}.m4a')],
        );
        h.setNetwork(NetworkStatus.noInterface);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.settle();

        expect(
          h.controller.state,
          isA<Retrying>()
              .having((s) => s.delay, 'delay', isNull)
              .having((s) => s.waitingForNetwork, 'waiting', isTrue)
              .having((s) => s.attempt, 'attempt', 0)
              .having((s) => s.error, 'error', isA<NetworkError>()),
        );
        // 等多久都不重試、不跳過、不提示。
        h.elapse(const Duration(minutes: 1));
        expect(h.plugin.resolvedCount('a'), 1);
        expect(h.controller.queue.currentIndex, 0);
        expect(h.events, isEmpty);
        // unreachable 也還是在等。
        h.setNetwork(NetworkStatus.unreachable);
        expect(h.plugin.resolvedCount('a'), 1);

        failing = false;
        h.setNetwork(NetworkStatus.online);
        expect(h.plugin.resolvedCount('a'), 2);
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Playing>());
        expect(h.controller.queue.currentIndex, 0);
        expect(h.logged('Network is back; retrying'), hasLength(1));
        expect(h.events, isEmpty);
      });
    });

    test('waiting does not use up the retries', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          respond: (request) => request.sourceId == 'a'
              ? throw NetworkError(pluginId: 'fmp-test')
              : [candidate('${request.sourceId}.m4a')],
        );
        h.setNetwork(NetworkStatus.noInterface);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.settle();

        h.setNetwork(NetworkStatus.online);
        // 回來後還是失敗：照常從第一次重試開始。
        expect(
          h.controller.state,
          isA<Retrying>()
              .having((s) => s.attempt, 'attempt', 1)
              .having((s) => s.delay, 'delay', const Duration(seconds: 1)),
        );
      });
    });

    test('an interruption while offline resumes from its position', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 5));

        h.setNetwork(NetworkStatus.unreachable);
        h.backend.interrupt();
        h.settle();
        expect(
          h.controller.state,
          isA<Retrying>().having((s) => s.waitingForNetwork, 'waiting', true),
        );
        expect(h.backend.current, isNull);
        h.elapse(const Duration(seconds: 20));
        expect(h.backend.opened, hasLength(1));

        h.setNetwork(NetworkStatus.online);
        h.elapse(const Duration(milliseconds: 100));
        expect(h.backend.openedAt.last.inMilliseconds, closeTo(5000, 100));
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('pausing while waiting stops waiting; play starts again', () {
      fakeAsync((async) {
        var failing = true;
        final h = Harness(
          async,
          respond: (request) => failing
              ? throw NetworkError(pluginId: 'fmp-test')
              : [candidate('${request.sourceId}.m4a')],
        );
        h.setNetwork(NetworkStatus.noInterface);
        unawaited(h.playQueue([track('a')]));
        h.settle();

        unawaited(h.controller.pause());
        h.settle();
        expect(h.controller.state, isA<Paused>());
        failing = false;
        h.setNetwork(NetworkStatus.online);
        expect(h.plugin.resolvedCount('a'), 1);

        unawaited(h.controller.play());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Playing>());
      });
    });
  });

  group('recovery: counting', () {
    test('ten seconds of normal playback reset the retry count', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(minutes: 5));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 5));

        h.backend.interrupt();
        h.elapse(const Duration(seconds: 1, milliseconds: 100));
        expect(h.controller.state, isA<Playing>());
        h.elapse(const Duration(seconds: 11));
        expect(
          h.logged('Retry count reset after normal playback'),
          hasLength(1),
        );
        // 以位置前進累計：週期計時器只有假後端自己的那一個。
        expect(async.periodicTimerCount, 1);

        h.backend.interrupt();
        h.settle();
        expect(
          h.controller.state,
          isA<Retrying>().having((s) => s.attempt, 'attempt', 1),
        );
      });
    });

    test('less than ten seconds keeps counting', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(minutes: 5));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 5));

        h.backend.interrupt();
        h.elapse(const Duration(seconds: 1, milliseconds: 100));
        h.elapse(const Duration(seconds: 8));

        h.backend.interrupt();
        h.settle();
        expect(
          h.controller.state,
          isA<Retrying>().having((s) => s.attempt, 'attempt', 2),
        );
        expect(h.logged('Retry count reset after normal playback'), isEmpty);
      });
    });

    test('seeking forward is not playback', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(minutes: 5));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 5));

        h.backend.interrupt();
        h.elapse(const Duration(seconds: 1, milliseconds: 100));
        unawaited(h.controller.seek(const Duration(minutes: 2)));
        h.elapse(const Duration(seconds: 1));

        h.backend.interrupt();
        h.settle();
        expect(
          h.controller.state,
          isA<Retrying>().having((s) => s.attempt, 'attempt', 2),
        );
      });
    });
  });

  group('recovery: buffering starved for 15 seconds', () {
    test('resolves again the first time and plays on from there', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(minutes: 5));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 20));

        h.backend.stall();
        h.elapse(const Duration(seconds: 14));
        expect(h.controller.state, isA<Buffering>());
        expect(h.plugin.resolvedCount('a'), 1);

        h.elapse(const Duration(seconds: 1, milliseconds: 100));
        expect(h.logged('Buffering stalled'), hasLength(1));
        expect(h.plugin.resolvedCount('a'), 2);
        expect(h.backend.openedAt.last.inMilliseconds, closeTo(20000, 100));
        expect(h.controller.state, isA<Playing>());
        expect(h.controller.queue.currentIndex, 0);
      });
    });

    test('the second time on the same track it is skipped', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(minutes: 5));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 2));
        h.backend.stall();
        h.elapse(const Duration(seconds: 16));
        h.elapse(const Duration(seconds: 2));

        h.backend.stall();
        h.elapse(const Duration(seconds: 16));
        expect(h.controller.queue.currentIndex, 1);
        expect(
          h.events.single,
          isA<TrackSkipped>().having(
            (e) => e.error,
            'error',
            isA<NetworkError>(),
          ),
        );
      });
    });

    test('data arriving in time cancels it', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(minutes: 5));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 2));

        h.backend.stall();
        h.elapse(const Duration(seconds: 10));
        h.backend.resume();
        h.elapse(const Duration(seconds: 30));

        expect(h.logged('Buffering stalled'), isEmpty);
        expect(h.plugin.resolvedCount('a'), 1);
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('offline it waits for the network instead', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(minutes: 5));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 2));

        h.setNetwork(NetworkStatus.noInterface);
        h.backend.stall();
        h.elapse(const Duration(seconds: 16));
        expect(
          h.controller.state,
          isA<Retrying>().having((s) => s.waitingForNetwork, 'waiting', true),
        );
      });
    });
  });

  group('recovery: preview clips', () {
    test('"skip preview clips" on: skipped with the reason', () {
      fakeAsync((async) {
        final h = Harness(async);
        h.plugin.previewOnly = (request) => request.sourceId == 'a';
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.openedPaths, ['/b.m4a']);
        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.previewing, isFalse);
        expect(
          h.events.single,
          isA<TrackSkipped>().having(
            (e) => e.error,
            'error',
            isA<Unavailable>().having(
              (e) => e.reason,
              'reason',
              UnavailableReason.previewOnly,
            ),
          ),
        );
      });
    });

    test('off: plays it marked as a preview, announced once', () {
      fakeAsync((async) {
        final h = Harness(async);
        h.skipPreviewClips = false;
        h.plugin.previewOnly = (request) => request.sourceId == 'a';
        final previews = <bool>[];
        h.controller.previewChanges.listen(previews.add);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.openedPaths, ['/a.m4a']);
        expect(h.controller.previewing, isTrue);
        expect(
          h.events.single,
          isA<PreviewPlaying>().having((e) => e.track, 'track', track('a')),
        );

        // 下一首不是試聽：標示拿掉。
        h.elapse(const Duration(seconds: 2));
        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.previewing, isFalse);
        expect(previews, [true, false]);
      });
    });

    test('a preview clip is not prepared as the look-ahead; it is handled '
        'when its turn comes', () {
      fakeAsync((async) {
        final h = Harness(async);
        h.skipPreviewClips = false;
        h.plugin.previewOnly = (request) => request.sourceId == 'b';
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(milliseconds: 100));
        expect(h.backend.nextSources.nonNulls, isEmpty);
        expect(h.logged('Look-ahead skipped: preview only'), hasLength(1));

        h.elapse(const Duration(seconds: 2));
        expect(h.controller.queue.currentIndex, 1);
        expect(h.openedPaths, ['/a.m4a', '/b.m4a']);
        expect(h.plugin.resolvedCount('b'), 1);
        expect(h.controller.previewing, isTrue);
      });
    });

    test('looping a preview clip announces it only once', () {
      fakeAsync((async) {
        final h = Harness(async);
        h.skipPreviewClips = false;
        h.plugin.previewOnly = (_) => true;
        h.controller
          ..cycleLoopMode()
          ..cycleLoopMode();
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 5));

        expect(h.openedPaths, hasLength(greaterThanOrEqualTo(2)));
        expect(h.events.whereType<PreviewPlaying>(), hasLength(1));
        expect(h.controller.previewing, isTrue);
      });
    });
  });

  // PR 10 留下的：單曲循環時換過候選，前瞻要接換過的那個，不是開不起來的第一個。
  test('loop one after a candidate switch repeats the candidate that '
      'played', () {
    fakeAsync((async) {
      final h = Harness(
        async,
        respond: (request) => [
          candidate('${request.sourceId}-1.m4a'),
          candidate('${request.sourceId}-2.m4a'),
        ],
        failsToOpen: (url) => url.path == '/a-1.m4a',
        httpStatusOf: (_) => 500,
      );
      h.controller
        ..cycleLoopMode()
        ..cycleLoopMode();
      unawaited(h.playQueue([track('a')]));
      h.elapse(const Duration(milliseconds: 100));
      expect(h.openedPaths, ['/a-1.m4a', '/a-2.m4a']);
      expect(h.backend.nextSources.last?.url.path, '/a-2.m4a');

      h.elapse(const Duration(seconds: 2));
      expect(h.logged('Look-ahead handover'), hasLength(1));
      expect(h.openedPaths, ['/a-1.m4a', '/a-2.m4a']);
      expect(h.logged('Playback recovery'), hasLength(1));
      expect(h.controller.state, isA<Playing>());
    });
  });

  // 換成單曲循環時清前瞻的修改還在後端排隊，使用者就換了歌：排隊回來後不能
  // 把上一首當成新那首的前瞻。
  test('switching to loop one and then to another song does not prepare the '
      'previous song as the look-ahead', () {
    fakeAsync((async) {
      final pending = Completer<List<StreamCandidate>>();
      final h = Harness(
        async,
        respond: (request) => request.sourceId == 'c'
            ? pending.future
            : [candidate('${request.sourceId}.m4a')],
      );
      unawaited(h.playQueue([track('a'), track('b'), track('c')]));
      h.elapse(const Duration(milliseconds: 100));
      final gate = Completer<void>();
      h.backend.setNextGate = gate.future;

      h.controller
        ..cycleLoopMode()
        ..cycleLoopMode();
      h.settle();
      unawaited(h.controller.jumpTo(2));
      h.settle();
      gate.complete();
      h.settle();

      expect(
        [
          for (final record in h.logged('Look-ahead prepared'))
            record.fields['track'],
        ],
        ['fmp-test:b'],
      );
      pending.complete([candidate('c.m4a')]);
      h.elapse(const Duration(milliseconds: 100));
      expect(h.controller.queue.current?.sourceId, 'c');
      expect(h.controller.state, isA<Playing>());
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
        // 跳過（回到佇列）並提示是哪一首。
        expect(
          h.events.single,
          isA<TrackSkipped>()
              .having((e) => e.track, 'track', track('x'))
              .having((e) => e.error, 'error', isA<NotFound>()),
        );
      });
    });

    // 臨時曲目不在佇列裡：跳過它不會讓「連續跳過達佇列長度」提早成立，佇列
    // 只有一首時也回到那一首。
    test('a temporary track that cannot be played returns to a queue of one '
        'song', () {
      fakeAsync((async) {
        final h = Harness(
          async,
          trackLength: const Duration(seconds: 60),
          respond: (request) => request.sourceId == 'x'
              ? throw NotFound(pluginId: 'fmp-test')
              : [candidate('${request.sourceId}.m4a')],
        );
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 30));

        unawaited(h.controller.playTemporary(track('x')));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.controller.state, isA<Playing>());
        expect(
          h.events.single,
          isA<TrackSkipped>().having((e) => e.track, 'track', track('x')),
        );
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

  // E19（design §7.6）：音量、靜音與速度交給後端（後端換歌後維持，見後端
  // 契約）。
  group('volume, mute and speed', () {
    test('the volume goes to the backend and holds across tracks', () {
      fakeAsync((async) {
        final h = Harness(async);
        unawaited(h.controller.setVolume(0.3));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 3));

        expect(h.controller.queue.currentIndex, 1);
        expect(h.backend.volume, 0.3);
        expect(h.controller.volume, 0.3);

        unawaited(h.controller.setVolume(1.4));
        h.settle();
        expect(h.controller.volume, 1);
        expect(h.backend.volume, 1);
      });
    });

    test('mute remembers the volume and unmuting returns to it', () {
      fakeAsync((async) {
        final h = Harness(async);
        unawaited(h.controller.setVolume(0.6));
        unawaited(h.controller.toggleMute());
        h.settle();
        expect(h.controller.muted, isTrue);
        expect(h.controller.volume, 0.6);
        expect(h.backend.volume, 0);

        unawaited(h.controller.toggleMute());
        h.settle();
        expect(h.controller.muted, isFalse);
        expect(h.backend.volume, 0.6);
      });
    });

    test('setting the volume while muted unmutes', () {
      fakeAsync((async) {
        final h = Harness(async);
        unawaited(h.controller.toggleMute());
        unawaited(h.controller.setVolume(0.4));
        h.settle();
        expect(h.controller.muted, isFalse);
        expect(h.backend.volume, 0.4);
      });
    });

    test('the speed is observable, clamped and starts at 1', () {
      fakeAsync((async) {
        final h = Harness(async);
        final seen = <double>[];
        final subscription = h.controller.speedChanges.listen(seen.add);
        expect(h.controller.speed, 1.0);

        unawaited(h.controller.setSpeed(1.25));
        unawaited(h.controller.setSpeed(5));
        h.settle();

        expect(h.controller.speed, 2.0);
        expect(seen, [1.25, 2.0]);
        unawaited(subscription.cancel());
      });
    });

    test('the speed goes to the backend, clamped there', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(seconds: 60));
        unawaited(h.controller.setSpeed(1.5));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 2));
        expect(h.backend.speed, 1.5);

        unawaited(h.controller.setSpeed(4));
        h.settle();
        expect(h.backend.speed, 2);
      });
    });
  });

  // Android 的音訊中斷與拔耳機（design §7.6、舊版 `playback.md` §3.7）：後端
  // 只回報，暫停與續播在控制器。
  group('audio interruptions', () {
    Harness playing(FakeAsync async) {
      final h = Harness(async, trackLength: const Duration(minutes: 3));
      unawaited(h.playQueue([track('a'), track('b')]));
      h.elapse(const Duration(seconds: 1));
      expect(h.controller.state, isA<Playing>());
      return h;
    }

    test('an interruption pauses and its end resumes the same track', () {
      fakeAsync((async) {
        final h = playing(async);
        h.backend.audioInterrupted();
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Paused>());
        expect(h.backend.playing, isFalse);
        expect(h.logged('Audio interrupted; pausing'), hasLength(1));

        h.elapse(const Duration(seconds: 30));
        h.backend.audioInterruptionEnded();
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Playing>());
        expect(h.controller.queue.currentIndex, 0);
        // 同一個來源接著播，沒有重新開流。
        expect(h.openedPaths, ['/a.m4a']);
        expect(h.logged('Audio interruption ended; resuming'), hasLength(1));
      });
    });

    test('a song the user paused is not resumed by the end', () {
      fakeAsync((async) {
        final h = playing(async);
        unawaited(h.controller.pause());
        h.elapse(const Duration(milliseconds: 100));
        h.backend.audioInterrupted();
        h.elapse(const Duration(milliseconds: 100));
        h.backend.audioInterruptionEnded();
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Paused>());
        expect(h.backend.playing, isFalse);
      });
    });

    test('pausing during the interruption keeps it paused after the end', () {
      fakeAsync((async) {
        final h = playing(async);
        h.backend.audioInterrupted();
        h.elapse(const Duration(milliseconds: 100));
        unawaited(h.controller.pause());
        h.elapse(const Duration(milliseconds: 100));
        h.backend.audioInterruptionEnded();
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Paused>());
      });
    });

    test('playing during the interruption, then pausing, is not resumed by '
        'the end', () {
      fakeAsync((async) {
        final h = playing(async);
        h.backend.audioInterrupted();
        h.elapse(const Duration(milliseconds: 100));
        unawaited(h.controller.play());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Playing>());
        unawaited(h.controller.pause());
        h.elapse(const Duration(milliseconds: 100));
        h.backend.audioInterruptionEnded();
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Paused>());
      });
    });

    test('next during the interruption loads the next song paused and the '
        'end resumes it', () {
      fakeAsync((async) {
        final h = playing(async);
        h.backend.audioInterrupted();
        h.elapse(const Duration(milliseconds: 100));
        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.state, isA<Paused>());
        expect(h.backend.playing, isFalse);

        h.backend.audioInterruptionEnded();
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Playing>());
        expect(h.controller.queue.currentIndex, 1);
      });
    });

    test('an end that does not resume leaves it paused', () {
      fakeAsync((async) {
        final h = playing(async);
        h.backend.audioInterrupted();
        h.elapse(const Duration(milliseconds: 100));
        h.backend.audioInterruptionEnded(resume: false);
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Paused>());
        // 之後再來一個結束也不續播：中斷已經忘掉了。
        h.backend.audioInterruptionEnded();
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Paused>());
      });
    });

    test('an interruption while idle does not start anything at its end', () {
      fakeAsync((async) {
        final h = Harness(async);
        expect(h.controller.addToQueue([track('a')]), isTrue);
        h.backend.audioInterrupted();
        h.elapse(const Duration(milliseconds: 100));
        h.backend.audioInterruptionEnded();
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Idle>());
        expect(h.backend.opened, isEmpty);
      });
    });

    test(
      'an interruption while waiting to retry resumes from the position',
      () {
        fakeAsync((async) {
          final h = Harness(async, trackLength: const Duration(minutes: 3));
          unawaited(h.playQueue([track('a')]));
          h.elapse(const Duration(seconds: 5));
          h.backend.interrupt();
          h.settle();
          expect(h.controller.state, isA<Retrying>());

          h.backend.audioInterrupted();
          h.settle();
          expect(h.controller.state, isA<Paused>());
          // 排好的重試取消了：中斷期間不會自己開流出聲。
          h.elapse(const Duration(seconds: 20));
          expect(h.backend.opened, hasLength(1));

          h.backend.audioInterruptionEnded();
          h.elapse(const Duration(milliseconds: 100));
          expect(h.controller.state, isA<Playing>());
          expect(h.backend.opened, hasLength(2));
          expect(
            h.backend.openedAt.last,
            greaterThan(const Duration(seconds: 4)),
          );
        });
      },
    );

    test('unplugged headphones only pause', () {
      fakeAsync((async) {
        final h = playing(async);
        h.backend.becameNoisy();
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Paused>());
        expect(h.logged('Headphones unplugged; pausing'), hasLength(1));
        // 之後的中斷結束不會從喇叭續播。
        h.backend.audioInterruptionEnded();
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Paused>());
      });
    });

    test('headphones unplugged during an interruption cancel the resume', () {
      fakeAsync((async) {
        final h = playing(async);
        h.backend.audioInterrupted();
        h.elapse(const Duration(milliseconds: 100));
        h.backend.becameNoisy();
        h.elapse(const Duration(milliseconds: 100));
        h.backend.audioInterruptionEnded();
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Paused>());
      });
    });
  });

  // design §7.5、§7.6：桌面輸出裝置失敗暫停並提示，不跳過。mpv 的 `completed`
  // 可能比 `[ao]` 那幾行早到（2026-10-07 實測，backend_rules_test.dart），所以
  // 已經排好的重試也要收掉（舊專案 issue #106）。
  group('a failed output device', () {
    test('pauses at the position and says so, without skipping', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(minutes: 3));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 5));

        h.backend.failOutputDevice();
        h.settle();
        expect(h.controller.state, isA<Paused>());
        expect(
          h.events.whereType<OutputDeviceFailed>().single.fellBack,
          isFalse,
        );
        expect(h.events.whereType<TrackSkipped>(), isEmpty);
        expect(h.controller.queue.currentIndex, 0);
        expect(h.backend.current, isNull, reason: 'the source is released');

        // 按播放：從失敗的位置重新開流（mpv 才會再開一次輸出）。
        h.elapse(const Duration(seconds: 10));
        unawaited(h.controller.play());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.state, isA<Playing>());
        expect(h.openedPaths, ['/a.m4a', '/a.m4a']);
        expect(
          h.backend.openedAt.last,
          greaterThan(const Duration(seconds: 4)),
        );
      });
    });

    test('an early end that arrived first does not retry into the dead '
        'device', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(minutes: 3));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 5));

        h.backend.endEarly();
        h.settle();
        expect(h.controller.state, isA<Retrying>());
        h.backend.failOutputDevice();
        h.settle();
        expect(h.controller.state, isA<Paused>());

        h.elapse(const Duration(seconds: 30));
        expect(h.controller.state, isA<Paused>());
        expect(h.backend.opened, hasLength(1));
      });
    });

    test('an early end that arrives after it is ignored', () {
      fakeAsync((async) {
        final h = Harness(async, trackLength: const Duration(minutes: 3));
        unawaited(h.playQueue([track('a')]));
        h.elapse(const Duration(seconds: 5));
        final source = h.backend.current!;

        h.backend.failOutputDevice();
        h.settle();
        // 停下之前就送出的結束（`stop` 還在路上）。
        h.backend.endEarlyFor(source);
        h.elapse(const Duration(seconds: 30));

        expect(h.controller.state, isA<Paused>());
        expect(h.backend.opened, hasLength(1));
      });
    });

    test('while idle only says so', () {
      fakeAsync((async) {
        final h = Harness(async);
        h.backend.failOutputDevice();
        h.settle();
        expect(h.controller.state, isA<Idle>());
        expect(
          h.events.whereType<OutputDeviceFailed>().single.fellBack,
          isFalse,
        );
      });
    });

    // 擁有者 2026-10-07：選過的裝置失敗時，這次執行改用系統預設輸出，偏好不清，
    // 按播放才不會再撞同一個裝置。
    group('falls back to the system default output', () {
      const headphones = OutputDevice(id: 'wasapi/{b}', name: 'Headphones');
      const speakers = OutputDevice(id: 'wasapi/{a}', name: 'Speakers');

      test('for a device the user chose, keeping the preference', () {
        fakeAsync((async) {
          final devices = FakeOutputDevices(const [speakers, headphones]);
          final h = Harness(
            async,
            trackLength: const Duration(minutes: 3),
            outputDevices: devices,
          );
          unawaited(h.controller.selectOutputDevice(headphones));
          h.settle();
          unawaited(h.playQueue([track('a'), track('b')]));
          h.elapse(const Duration(seconds: 5));
          expect(h.controller.outputDeviceState.selected, headphones);

          h.backend.failOutputDevice();
          h.settle();

          expect(h.controller.state, isA<Paused>());
          expect(devices.selections, [headphones, null]);
          expect(h.controller.outputDeviceState.selected, isNull);
          expect(h.savedOutputDevices, [
            headphones,
          ], reason: 'the remembered preference is not cleared');
          expect(
            h.events.whereType<OutputDeviceFailed>().single.fellBack,
            isTrue,
          );

          // 按播放：從原位置繼續，輸出已經是系統預設，不再選回失敗的裝置。
          unawaited(h.controller.play());
          h.elapse(const Duration(milliseconds: 100));
          expect(h.controller.state, isA<Playing>());
          expect(devices.selections, [headphones, null]);
          expect(h.openedPaths, ['/a.m4a', '/a.m4a']);
          expect(
            h.backend.openedAt.last,
            greaterThan(const Duration(seconds: 4)),
          );
        });
      });

      test('for the remembered device applied at start', () {
        fakeAsync((async) {
          final devices = FakeOutputDevices();
          final h = Harness(
            async,
            trackLength: const Duration(minutes: 3),
            outputDevices: devices,
          )..preferredOutputDevice = headphones.id;
          devices.list(const [speakers, headphones]);
          h.settle();
          expect(h.controller.outputDeviceState.selected, headphones);
          unawaited(h.playQueue([track('a')]));
          h.elapse(const Duration(seconds: 5));

          h.backend.failOutputDevice();
          h.settle();

          expect(devices.selections, [headphones, null]);
          expect(h.controller.outputDeviceState.selected, isNull);
          expect(h.savedOutputDevices, isEmpty);
          expect(
            h.events.whereType<OutputDeviceFailed>().single.fellBack,
            isTrue,
          );
        });
      });

      test('not when the system default itself failed', () {
        fakeAsync((async) {
          final devices = FakeOutputDevices(const [speakers]);
          final h = Harness(
            async,
            trackLength: const Duration(minutes: 3),
            outputDevices: devices,
          );
          unawaited(h.playQueue([track('a')]));
          h.elapse(const Duration(seconds: 5));

          h.backend.failOutputDevice();
          h.settle();

          expect(h.controller.state, isA<Paused>());
          expect(devices.selections, isEmpty);
          expect(
            h.events.whereType<OutputDeviceFailed>().single.fellBack,
            isFalse,
          );
        });
      });

      test('also while idle', () {
        fakeAsync((async) {
          final devices = FakeOutputDevices(const [speakers, headphones]);
          final h = Harness(async, outputDevices: devices);
          unawaited(h.controller.selectOutputDevice(headphones));
          h.settle();

          h.backend.failOutputDevice();
          h.settle();

          expect(devices.selections, [headphones, null]);
          expect(h.controller.outputDeviceState.selected, isNull);
          expect(
            h.events.whereType<OutputDeviceFailed>().single.fellBack,
            isTrue,
          );
        });
      });
    });
  });

  // design §7.6：記住的裝置在清單第一次就緒時套用一次；不在清單裡就用系統
  // 預設，偏好不清掉（舊版 `audio_provider.dart` 的
  // `_restorePreferredAudioDevice`）。
  group('output devices', () {
    const speakers = OutputDevice(id: 'wasapi/{a}', name: 'Speakers');
    const headphones = OutputDevice(id: 'wasapi/{b}', name: 'Headphones');

    test('the remembered device is chosen when the list is first ready', () {
      fakeAsync((async) {
        final devices = FakeOutputDevices();
        final h = Harness(async, outputDevices: devices)
          ..preferredOutputDevice = headphones.id;
        h.settle();
        expect(devices.selections, isEmpty);

        devices.list(const [speakers, headphones]);
        h.settle();
        expect(devices.selections, [headphones]);
        expect(h.savedOutputDevices, isEmpty);
        expect(h.logged('Preferred output device restored'), hasLength(1));
      });
    });

    test('a remembered device that is not connected leaves the default and '
        'the preference', () {
      fakeAsync((async) {
        final devices = FakeOutputDevices();
        final h = Harness(async, outputDevices: devices)
          ..preferredOutputDevice = headphones.id;
        devices.list(const [speakers]);
        h.settle();

        expect(devices.selections, isEmpty);
        expect(h.savedOutputDevices, isEmpty);
        expect(
          h.logged('Preferred output device is not connected'),
          hasLength(1),
        );

        // 只套用第一次：之後插上那個裝置也不自己換過去。
        devices.list(const [speakers, headphones]);
        h.settle();
        expect(devices.selections, isEmpty);
      });
    });

    test('a list that was ready before the controller is used too', () {
      fakeAsync((async) {
        final devices = FakeOutputDevices(const [speakers, headphones]);
        final h = Harness(async, outputDevices: devices)
          ..preferredOutputDevice = speakers.id;
        h.settle();
        expect(devices.selections, [speakers]);
      });
    });

    test('without a remembered device nothing is chosen', () {
      fakeAsync((async) {
        final devices = FakeOutputDevices(const [speakers]);
        final h = Harness(async, outputDevices: devices);
        h.settle();
        expect(devices.selections, isEmpty);
      });
    });

    test(
      'choosing a device selects and remembers it; the default clears it',
      () {
        fakeAsync((async) {
          final devices = FakeOutputDevices(const [speakers, headphones]);
          final h = Harness(async, outputDevices: devices);
          h.settle();

          unawaited(h.controller.selectOutputDevice(headphones));
          h.settle();
          unawaited(h.controller.selectOutputDevice(null));
          h.settle();

          expect(devices.selections, [headphones, null]);
          expect(h.savedOutputDevices, [headphones, null]);
        });
      },
    );

    test('a choice made before the list is ready is not overridden', () {
      fakeAsync((async) {
        final devices = FakeOutputDevices();
        final h = Harness(async, outputDevices: devices)
          ..preferredOutputDevice = headphones.id;
        unawaited(h.controller.selectOutputDevice(speakers));
        h.settle();
        devices.list(const [speakers, headphones]);
        h.settle();

        expect(devices.selections, [speakers]);
      });
    });

    test('the state follows the list, the user and the remembered device', () {
      fakeAsync((async) {
        final devices = FakeOutputDevices();
        final h = Harness(async, outputDevices: devices)
          ..preferredOutputDevice = headphones.id;
        final states = <OutputDeviceState>[];
        h.controller.outputDeviceChanges.listen(states.add);
        expect(h.controller.outputDeviceState.devices, isEmpty);
        expect(h.controller.outputDeviceState.selected, isNull);

        devices.list(const [speakers, headphones]);
        h.settle();
        expect(h.controller.outputDeviceState.devices, [speakers, headphones]);
        expect(h.controller.outputDeviceState.selected, headphones);

        unawaited(h.controller.selectOutputDevice(null));
        h.settle();
        expect(h.controller.outputDeviceState.selected, isNull);

        devices.list(const [speakers]);
        h.settle();
        expect(h.controller.outputDeviceState.devices, const [speakers]);
        expect(states, isNotEmpty);
        expect(states.last.devices, [speakers]);
      });
    });

    test('a platform without output devices ignores a choice', () {
      fakeAsync((async) {
        final h = Harness(async);
        unawaited(h.controller.selectOutputDevice(speakers));
        h.settle();
        expect(h.savedOutputDevices, isEmpty);
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
                preferences: () => (
                  quality: AudioQuality.high,
                  formatPriority: AudioFormatPriority.opusFirst,
                ),
                log: log,
              ),
              log: log,
            ),
            log: log,
            temporaryReturnSettings: () =>
                (rememberPosition: true, rewind: Duration.zero),
            skipPreviewClips: () => true,
            networkStatus: () => NetworkStatus.online,
            networkStatusChanges: const Stream.empty(),
            preferredOutputDevice: () async => null,
            saveOutputDevice: (_) async {},
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

  // design §7.8：一次「開始一首」在第一次出聲時算一次播放；同一次開始裡的重試、
  // 換候選、暫停後繼續，啟動恢復後的第一次播放，以及回到佇列都不算。
  group('play history counting', () {
    Harness longTracks(FakeAsync async) =>
        Harness(async, trackLength: const Duration(seconds: 60));

    group('counts', () {
      test('the first song of a queue, with the time it became audible', () {
        fakeAsync((async) {
          final h = longTracks(async);
          final start = h.now();

          unawaited(h.playQueue([track('a'), track('b')]));
          h.elapse(const Duration(milliseconds: 100));

          expect(h.playedIds, ['a']);
          expect(h.plays.single.track, track('a'));
          expect(
            h.plays.single.at.difference(start),
            lessThan(const Duration(seconds: 1)),
          );
        });
      });

      test('next, previous and jumping to a song', () {
        fakeAsync((async) {
          final h = longTracks(async);
          unawaited(h.playQueue([track('a'), track('b'), track('c')]));
          h.elapse(const Duration(milliseconds: 100));

          unawaited(h.controller.next());
          h.elapse(const Duration(milliseconds: 100));
          expect(h.playedIds, ['a', 'b']);

          // 播不到 3 秒按上一首：往前一首（超過 3 秒是回到開頭，不算）。
          unawaited(h.controller.previous());
          h.elapse(const Duration(milliseconds: 100));
          expect(h.playedIds, ['a', 'b', 'a']);

          unawaited(h.controller.jumpTo(2));
          h.elapse(const Duration(milliseconds: 100));
          expect(h.playedIds, ['a', 'b', 'a', 'c']);
        });
      });

      test('a song that ends and the queue moves on, by look-ahead', () {
        fakeAsync((async) {
          final h = Harness(async);
          unawaited(h.playQueue([track('a'), track('b')]));
          h.elapse(const Duration(milliseconds: 100));
          expect(h.playedIds, ['a']);

          h.elapse(const Duration(seconds: 2));

          expect(h.logged('Look-ahead handover'), hasLength(1));
          expect(h.playedIds, ['a', 'b']);
        });
      });

      test('a temporary play', () {
        fakeAsync((async) {
          final h = longTracks(async);
          unawaited(h.controller.playTemporary(track('x')));
          h.elapse(const Duration(milliseconds: 100));

          unawaited(h.controller.playTemporary(track('y')));
          h.elapse(const Duration(milliseconds: 100));

          expect(h.playedIds, ['x', 'y']);
        });
      });

      test('every lap of loop one by look-ahead, without resolving again', () {
        fakeAsync((async) {
          final h = Harness(async);
          unawaited(h.playQueue([track('a'), track('b')]));
          h.elapse(const Duration(milliseconds: 100));
          h.controller
            ..cycleLoopMode()
            ..cycleLoopMode();
          h.settle();

          h.elapse(const Duration(milliseconds: 4200));

          expect(h.logged('Look-ahead handover'), hasLength(2));
          expect(h.playedIds, ['a', 'a', 'a'], reason: 'the start and 2 laps');
          expect(h.plugin.resolvedCount('a'), 1);
        });
      });

      test('every lap of loop one that restarts the song (no look-ahead)', () {
        fakeAsync((async) {
          final h = Harness(async);
          unawaited(h.playQueue([track('a')]));
          h.elapse(const Duration(milliseconds: 100));
          // 設單曲循環的前瞻修改還在排隊：播完時引擎沒有東西可接，從頭再開。
          h.backend.setNextGate = Completer<void>().future;
          h.controller
            ..cycleLoopMode()
            ..cycleLoopMode();

          h.elapse(const Duration(seconds: 2, milliseconds: 300));

          expect(h.logged('Look-ahead handover'), isEmpty);
          expect(h.openedPaths, ['/a.m4a', '/a.m4a'], reason: 'reopened');
          expect(h.playedIds, ['a', 'a']);
          expect(h.plugin.resolvedCount('a'), 1, reason: 'no new resolution');
        });
      });

      test(
        'a song the user paused on before it loaded counts once it plays',
        () {
          fakeAsync((async) {
            final h = longTracks(async);
            unawaited(h.playQueue([track('a'), track('b')]));
            h.elapse(const Duration(milliseconds: 100));
            unawaited(h.controller.pause());
            h.settle();

            unawaited(h.controller.next());
            h.elapse(const Duration(milliseconds: 100));
            expect(h.controller.state, isA<Paused>());
            expect(h.playedIds, ['a'], reason: 'b is loaded but not audible');

            unawaited(h.controller.play());
            h.elapse(const Duration(milliseconds: 100));
            expect(h.playedIds, ['a', 'b']);
          });
        },
      );
    });

    group('does not count', () {
      test('a retry; the song counts once when it finally plays', () {
        fakeAsync((async) {
          var calls = 0;
          final h = Harness(
            async,
            trackLength: const Duration(seconds: 60),
            respond: (request) => ++calls == 1
                ? throw NetworkError(pluginId: 'fmp-test')
                : [candidate('${request.sourceId}.m4a')],
          );
          unawaited(h.playQueue([track('a')]));
          h.settle();
          expect(h.controller.state, isA<Retrying>());
          expect(h.playedIds, isEmpty, reason: 'it was never audible');

          h.elapse(const Duration(seconds: 1, milliseconds: 100));

          expect(h.controller.state, isA<Playing>());
          expect(h.playedIds, ['a']);
        });
      });

      test('a retry after the song was already audible', () {
        fakeAsync((async) {
          final h = longTracks(async);
          unawaited(h.playQueue([track('a')]));
          h.elapse(const Duration(seconds: 5));
          expect(h.playedIds, ['a']);

          h.backend.endEarly();
          h.settle();
          expect(h.controller.state, isA<Retrying>());
          h.elapse(const Duration(seconds: 1, milliseconds: 100));

          expect(h.controller.state, isA<Playing>());
          expect(h.playedIds, ['a']);
          expect(h.plugin.resolvedCount('a'), 2, reason: 'it did re-resolve');
        });
      });

      test('re-resolving and a candidate switch within the same start', () {
        fakeAsync((async) {
          final h = Harness(
            async,
            trackLength: const Duration(seconds: 60),
            respond: (request) => [
              candidate('${request.sourceId}-1.m4a'),
              candidate('${request.sourceId}-2.m4a'),
            ],
            failsToOpen: (url) => !url.path.startsWith('/a-2'),
          );

          unawaited(h.playQueue([track('a')]));
          h.elapse(const Duration(milliseconds: 100));

          expect(h.openedPaths, ['/a-1.m4a', '/a-1.m4a', '/a-2.m4a']);
          expect(h.playedIds, ['a']);
        });
      });

      test('pausing and resuming, and a seek', () {
        fakeAsync((async) {
          final h = longTracks(async);
          unawaited(h.playQueue([track('a')]));
          h.elapse(const Duration(seconds: 1));

          for (var i = 0; i < 3; i++) {
            unawaited(h.controller.pause());
            h.elapse(const Duration(milliseconds: 100));
            unawaited(h.controller.play());
            h.elapse(const Duration(milliseconds: 100));
          }
          unawaited(h.controller.seek(const Duration(seconds: 30)));
          h.elapse(const Duration(milliseconds: 100));

          expect(h.playedIds, ['a']);
        });
      });

      test('previous after 3 seconds, which only restarts the song', () {
        fakeAsync((async) {
          final h = longTracks(async);
          unawaited(h.playQueue([track('a'), track('b')]));
          h.elapse(const Duration(seconds: 5));

          unawaited(h.controller.previous());
          h.elapse(const Duration(milliseconds: 100));

          expect(h.openedPaths, ['/a.m4a'], reason: 'a seek, not a new open');
          expect(h.playedIds, ['a']);
        });
      });

      test('returning to the queue song after a temporary play', () {
        fakeAsync((async) {
          final h = longTracks(async);
          unawaited(h.playQueue([track('a'), track('b')]));
          h.elapse(const Duration(seconds: 30));
          unawaited(h.controller.playTemporary(track('x')));
          h.elapse(const Duration(seconds: 5));
          expect(h.playedIds, ['a', 'x']);

          unawaited(h.controller.next());
          h.elapse(const Duration(milliseconds: 200));

          expect(h.openedPaths, ['/a.m4a', '/x.m4a', '/a.m4a']);
          expect(h.controller.state, isA<Playing>());
          expect(h.playedIds, ['a', 'x']);
        });
      });

      test('playing again after the output device failed', () {
        fakeAsync((async) {
          final h = longTracks(async);
          unawaited(h.playQueue([track('a')]));
          h.elapse(const Duration(seconds: 5));
          h.backend.failOutputDevice();
          h.settle();

          unawaited(h.controller.play());
          h.elapse(const Duration(milliseconds: 100));

          expect(h.openedPaths, ['/a.m4a', '/a.m4a']);
          expect(h.playedIds, ['a']);
        });
      });

      test('a song that never became audible before the queue moved on', () {
        fakeAsync((async) {
          final h = Harness(
            async,
            trackLength: const Duration(seconds: 60),
            respond: (request) => request.sourceId == 'a'
                ? throw Unsupported(pluginId: 'fmp-test')
                : [candidate('${request.sourceId}.m4a')],
          );

          unawaited(h.playQueue([track('a'), track('b')]));
          h.elapse(const Duration(milliseconds: 200));

          expect(h.events.whereType<TrackSkipped>(), hasLength(1));
          expect(h.playedIds, ['b'], reason: 'a was skipped without a sound');
        });
      });
    });

    group('after a restart', () {
      void restore(Harness h) {
        expect(
          h.controller.restore(
            tracks: [track('a'), track('b')],
            currentIndex: 0,
            loopMode: LoopMode.off,
            shuffle: false,
            position: const Duration(seconds: 30),
            volume: 1,
            muted: false,
          ),
          isTrue,
        );
      }

      test('the first play is not counted, the next song is', () {
        fakeAsync((async) {
          final h = longTracks(async);
          restore(h);

          unawaited(h.controller.play());
          h.elapse(const Duration(milliseconds: 100));
          expect(h.controller.state, isA<Playing>());
          expect(h.playedIds, isEmpty);

          unawaited(h.controller.next());
          h.elapse(const Duration(milliseconds: 100));
          expect(h.playedIds, ['b']);
        });
      });

      test('a temporary play counts, the play that follows it does not', () {
        fakeAsync((async) {
          final h = longTracks(async);
          restore(h);

          unawaited(h.controller.playTemporary(track('x')));
          h.elapse(const Duration(milliseconds: 100));
          expect(h.playedIds, ['x']);

          // 臨時播放結束、佇列仍停著；按播放仍是恢復後的第一次播放。
          unawaited(h.controller.next());
          h.elapse(const Duration(milliseconds: 100));
          expect(h.controller.state, isA<Idle>());
          unawaited(h.controller.play());
          h.elapse(const Duration(milliseconds: 100));

          expect(h.controller.state, isA<Playing>());
          expect(h.controller.startedFromRestore, isTrue);
          expect(h.playedIds, ['x']);
        });
      });
    });
  });
}
