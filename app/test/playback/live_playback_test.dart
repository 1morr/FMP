import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/playback/recovery_policy.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'fake_source_plugin.dart';
import 'playback_controller_test.dart' show Harness, track;

const _target = LiveTarget(
  pluginId: 'fmp-test',
  roomId: 'r1',
  title: 'Room one',
  hostName: 'Host',
);

LiveRoom _room({
  String roomId = 'r1',
  LiveRoomStatus status = LiveRoomStatus.live,
  String title = 'Room one',
  int? online,
}) => LiveRoom(roomId: roomId, title: title, status: status, online: online);

/// 直播間 `<roomId>.flv`，房間 id 含 `broken` 的開不起來；狀態預設開播中。
Harness _harness(FakeAsync async, {Duration? trackLength}) {
  final h = Harness(
    async,
    trackLength: trackLength ?? const Duration(hours: 1),
    failsToOpen: (url) => url.path.contains('broken'),
  );
  h.plugin
    ..onResolveLive = ((request) => [candidate('${request.roomId}.flv')])
    ..onLiveStatus = ((query) => _room(roomId: query.roomId));
  h.returnSettings = (rememberPosition: true, rewind: Duration.zero);
  return h;
}

void main() {
  group('entering and leaving a live room', () {
    test('records the queue snapshot and returns to it when stopped', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 30));

        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 5));

        final queue = h.controller.queue;
        expect(queue.mode, QueueMode.live);
        // 直播不是曲目；佇列照舊在那裡，停在進入時的那一首。
        expect(queue.current, isNull);
        expect(queue.currentIndex, 0);
        expect(queue.live!.snapshot.playing, isTrue);
        expect(
          queue.live!.snapshot.position.inSeconds,
          inInclusiveRange(29, 31),
        );
        expect(h.controller.state, isA<Playing>());
        expect(h.openedPaths, ['/a.m4a', '/r1.flv']);
        expect(h.controller.live?.title, 'Room one');
        expect(h.controller.live?.hostName, 'Host');
        // 直播不排前瞻，也不算播放歷史。
        expect(h.playedIds, ['a']);

        unawaited(h.controller.stopLive());
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.controller.live, isNull);
        expect(h.openedPaths, ['/a.m4a', '/r1.flv', '/a.m4a']);
        expect(h.backend.openedAt.last.inMilliseconds, closeTo(30000, 100));
        expect(h.controller.state, isA<Playing>());
        // 回到佇列是續播，不是新的一次播放。
        expect(h.playedIds, ['a']);
      });
    });

    test('a queue that was paused stays paused after the live room', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 10));
        unawaited(h.controller.pause());
        h.settle();

        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 1));
        expect(h.controller.state, isA<Playing>());

        unawaited(h.controller.stopLive());
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.controller.state, isA<Paused>());
      });
    });

    // 回到佇列走臨時播放的同一條路：「臨時播放回佇列倒退秒數」也套用（design §9.4 的
    // 更正，M3 PR 18b）。
    test('returning from a live room rewinds like a temporary play', () {
      fakeAsync((async) {
        final h = _harness(async)
          ..returnSettings = (
            rememberPosition: true,
            rewind: const Duration(seconds: 10),
          );
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 30));

        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 5));
        unawaited(h.controller.stopLive());
        h.elapse(const Duration(milliseconds: 100));

        expect(h.backend.openedAt.last.inMilliseconds, closeTo(20000, 100));
      });
    });

    test('a queue that never played is not started afterwards', () {
      fakeAsync((async) {
        final h = _harness(async);
        h.controller.addToQueue([track('a')]);

        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 1));
        unawaited(h.controller.stopLive());
        h.elapse(const Duration(seconds: 1));

        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.controller.state, isA<Idle>());
        expect(h.openedPaths, ['/r1.flv']);
      });
    });

    test('changing rooms keeps the snapshot of the first entry', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 30));

        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 20));
        unawaited(
          h.controller.playLive(
            const LiveTarget(
              pluginId: 'fmp-test',
              roomId: 'r2',
              title: 'Room two',
            ),
          ),
        );
        h.elapse(const Duration(seconds: 20));
        expect(h.controller.live?.target.roomId, 'r2');
        expect(h.openedPaths, ['/a.m4a', '/r1.flv', '/r2.flv']);

        unawaited(h.controller.stopLive());
        h.elapse(const Duration(milliseconds: 100));

        // 第一次進入時的位置，不是在第一個直播間的 20 秒。
        expect(h.backend.openedAt.last.inMilliseconds, closeTo(30000, 100));
        expect(h.openedPaths.last, '/a.m4a');
      });
    });

    test('picking a queue entry leaves the live room', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 3));
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 3));

        unawaited(h.controller.jumpTo(1));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.live, isNull);
        expect(h.openedPaths.last, '/b.m4a');
        expect(h.liveInfoJobs, isEmpty);
      });
    });

    test('previous, next and seek do nothing in a live room', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 3));
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 3));
        final opened = h.openedPaths.length;

        unawaited(h.controller.next());
        unawaited(h.controller.previous());
        unawaited(h.controller.seek(const Duration(seconds: 1)));
        h.elapse(const Duration(seconds: 1));

        expect(h.controller.queue.mode, QueueMode.live);
        expect(h.controller.queue.hasNext, isFalse);
        expect(h.openedPaths, hasLength(opened));
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('a temporary track ends the live room and returns to the same '
        'snapshot', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 30));
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 5));

        unawaited(h.controller.playTemporary(track('x')));
        h.elapse(const Duration(seconds: 1));
        expect(h.controller.queue.mode, QueueMode.temporary);
        expect(h.controller.live, isNull);
        expect(h.liveInfoJobs, isEmpty);

        unawaited(h.controller.next());
        h.elapse(const Duration(milliseconds: 100));
        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.backend.openedAt.last.inMilliseconds, closeTo(30000, 100));
      });
    });
    test('the playback diagnostics report the room, not a track', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 5));
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 1));

        final d = h.controller.diagnostics(backend: 'just_audio');
        expect(d.trackKey, 'fmp-test:r1');
        expect(d.pluginId, 'fmp-test');
        expect(d.stream?.url.path, '/r1.flv');
        expect(d.queue.live, isTrue);
        expect(d.queue.temporary, isFalse);
        expect(d.queue.currentIndex, 0);

        unawaited(h.controller.stopLive());
        h.elapse(const Duration(milliseconds: 100));
        final back = h.controller.diagnostics(backend: 'just_audio');
        expect(back.trackKey, 'fmp-test:a');
        expect(back.queue.live, isFalse);
      });
    });
  });

  group('pausing', () {
    test('stops the stream, and playing again resolves it again', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 3));
        expect(h.plugin.liveRequests, hasLength(1));

        unawaited(h.controller.pause());
        h.settle();
        expect(h.controller.state, isA<Paused>());
        expect(h.backend.current, isNull, reason: 'the stream is stopped');
        // 暫停不退出直播。
        expect(h.controller.queue.mode, QueueMode.live);

        unawaited(h.controller.play());
        h.elapse(const Duration(seconds: 1));
        expect(h.plugin.liveRequests, hasLength(2));
        expect(h.controller.state, isA<Playing>());
        expect(h.openedPaths, ['/r1.flv', '/r1.flv']);
      });
    });

    test('pressing play after the stream stopped by itself reconnects', () {
      fakeAsync((async) {
        final h = _harness(async);
        h.plugin.onLiveStatus = (_) => _room(status: LiveRoomStatus.offline);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 1));
        h.backend.endEarly();
        h.elapse(const Duration(milliseconds: 10));
        expect(h.controller.live?.phase, LivePhase.ended);

        h.plugin.onLiveStatus = (_) => _room();
        unawaited(h.controller.play());
        h.elapse(const Duration(seconds: 1));

        expect(h.controller.live?.phase, LivePhase.listening);
        expect(h.controller.state, isA<Playing>());
        expect(h.plugin.liveRequests, hasLength(2));
      });
    });
  });

  group('the stream ends early', () {
    test('asks the status first and reconnects after 1, 3 and 9 s, three '
        'times', () {
      fakeAsync((async) {
        final h = _harness(async);
        var room = 'r1';
        h.plugin.onResolveLive = (_) => [candidate('$room.flv')];
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 2));
        expect(h.controller.state, isA<Playing>());
        // 之後重連都開不起來。
        room = 'broken';

        h.backend.endEarly();
        h.settle();
        expect(h.plugin.liveStatusQueries, hasLength(1));
        var state = h.controller.state as Retrying;
        expect((state.attempt, state.delay), (1, const Duration(seconds: 1)));

        h.elapse(const Duration(milliseconds: 999));
        expect(h.plugin.liveRequests, hasLength(1));
        h.elapse(const Duration(milliseconds: 1));
        expect(h.plugin.liveRequests, hasLength(2));

        // 第二次失敗：再問一次狀態，3 秒後重連。
        h.settle();
        expect(h.plugin.liveStatusQueries, hasLength(2));
        state = h.controller.state as Retrying;
        expect((state.attempt, state.delay), (2, const Duration(seconds: 3)));
        h.elapse(const Duration(milliseconds: 2999));
        expect(h.plugin.liveRequests, hasLength(2));
        h.elapse(const Duration(milliseconds: 1));
        expect(h.plugin.liveRequests, hasLength(3));

        h.settle();
        expect(h.plugin.liveStatusQueries, hasLength(3));
        state = h.controller.state as Retrying;
        expect((state.attempt, state.delay), (3, const Duration(seconds: 9)));
        h.elapse(const Duration(milliseconds: 8999));
        expect(h.plugin.liveRequests, hasLength(3));
        h.elapse(const Duration(milliseconds: 1));
        expect(h.plugin.liveRequests, hasLength(4));

        // 第三次重連也失敗：用完了，不再問、不再重連，停在直播已結束。
        h.settle();
        expect(h.plugin.liveStatusQueries, hasLength(3));
        expect(h.controller.state, isA<Idle>());
        expect(h.controller.live?.phase, LivePhase.ended);
        h.elapse(const Duration(minutes: 1));
        expect(h.plugin.liveRequests, hasLength(4));
        // 直播已結束後仍留在直播模式，`live-info` 不再更新。
        expect(h.controller.queue.mode, QueueMode.live);
        expect(h.liveInfoJobs, isEmpty);
      });
    });

    test('a reconnect that works resumes listening', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 2));

        h.backend.endEarly();
        h.elapse(const Duration(seconds: 1, milliseconds: 100));

        expect(h.plugin.liveRequests, hasLength(2));
        expect(h.controller.state, isA<Playing>());
        expect(h.controller.live?.phase, LivePhase.listening);
      });
    });

    test('a finished stream counts as an early end, not as a finished '
        'track', () {
      fakeAsync((async) {
        // 直播間的串流 3 秒後「播完」：沒有下一首，也不是單曲循環的重播。
        final h = _harness(async, trackLength: const Duration(seconds: 3));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.elapse(const Duration(seconds: 1));
        h.controller.cycleLoopMode();
        h.controller.cycleLoopMode();
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 4));

        expect(h.plugin.liveStatusQueries, isNotEmpty);
        expect(h.controller.queue.mode, QueueMode.live);
      });
    });

    test('does not reconnect when the room is no longer live', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 2));
        h.plugin.onLiveStatus = (_) => _room(status: LiveRoomStatus.offline);

        h.backend.endEarly();
        h.elapse(const Duration(minutes: 1));

        expect(h.plugin.liveStatusQueries, hasLength(1));
        expect(h.plugin.liveRequests, hasLength(1));
        expect(h.controller.state, isA<Idle>());
        expect(h.controller.live?.phase, LivePhase.ended);
      });
    });

    test('shows a failed query, and does not take it for offline, when the '
        'status cannot be fetched', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 2));
        h.plugin.onLiveStatus = (_) => throw NetworkError(pluginId: 'fmp-test');

        h.backend.endEarly();
        h.elapse(const Duration(minutes: 1));

        expect(h.controller.state, isA<Failed>());
        expect(h.controller.live?.phase, LivePhase.statusFailed);
        expect(h.plugin.liveRequests, hasLength(1), reason: 'no reconnect');
      });
    });

    test('waits for the network without counting a reconnect', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 2));
        h.network = NetworkStatus.noInterface;

        h.backend.endEarly();
        h.elapse(const Duration(minutes: 1));
        final waiting = h.controller.state as Retrying;
        expect(waiting.waitingForNetwork, isTrue);
        expect(h.plugin.liveStatusQueries, isEmpty);
        expect(h.plugin.liveRequests, hasLength(1));

        h.setNetwork(NetworkStatus.online);
        h.elapse(const Duration(seconds: 1));
        expect(h.plugin.liveRequests, hasLength(2));
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('the reconnect count starts over after ten seconds of listening', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 2));
        h.backend.endEarly();
        h.elapse(const Duration(seconds: 2));
        expect(h.plugin.liveRequests, hasLength(2));

        h.elapse(const Duration(seconds: 15));
        h.backend.endEarly();
        h.settle();

        final state = h.controller.state as Retrying;
        expect((state.attempt, state.delay), (1, const Duration(seconds: 1)));
      });
    });

    test('a room the plugin cannot give a stream for stops instead of '
        'reconnecting', () {
      fakeAsync((async) {
        final h = _harness(async);
        h.plugin.onResolveLive = (_) => throw Unavailable(pluginId: 'fmp-test');

        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(minutes: 1));

        expect(h.controller.state, isA<Failed>());
        expect(h.plugin.liveRequests, hasLength(1));
        expect(h.plugin.liveStatusQueries, isEmpty);
      });
    });
  });

  group('a music request that the live room supersedes', () {
    test('is dropped when it finishes, and does not start another '
        'resolution', () {
      fakeAsync((async) {
        final gate = Completer<List<StreamCandidate>>();
        final h = Harness(
          async,
          respond: (_) => gate.future,
          trackLength: const Duration(hours: 1),
        );
        h.plugin
          ..onResolveLive = ((request) => [candidate('${request.roomId}.flv')])
          ..onLiveStatus = ((query) => _room(roomId: query.roomId));
        unawaited(h.playQueue([track('a'), track('b')]));
        h.settle();
        expect(h.plugin.requests, hasLength(1));

        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(milliseconds: 100));
        gate.complete([candidate('a.m4a')]);
        h.elapse(const Duration(seconds: 2));

        expect(h.openedPaths, ['/r1.flv'], reason: 'only the live stream');
        expect(h.plugin.requests, hasLength(1), reason: 'no more resolutions');
        expect(h.controller.state, isA<Playing>());
        expect(h.controller.queue.mode, QueueMode.live);
      });
    });
  });

  group('live-info', () {
    test('is registered with the plugin on entering and removed when '
        'leaving', () {
      fakeAsync((async) {
        final h = _harness(async);
        expect(h.liveInfoJobs, isEmpty);

        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 1));
        expect(h.liveInfoJobs.map((job) => job.pluginId), ['fmp-test']);

        // 暫停與換台都不重複登記。
        unawaited(h.controller.pause());
        h.settle();
        unawaited(h.controller.play());
        h.elapse(const Duration(seconds: 1));
        expect(h.liveInfoJobs, hasLength(1));

        unawaited(h.controller.stopLive());
        h.elapse(const Duration(seconds: 1));
        expect(h.liveInfoJobs, isEmpty);
        expect(h.controller.live, isNull);
      });
    });

    test('updates the title and the audience, and a failure leaves '
        'playback alone', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 1));
        final updates = <LiveInfo?>[];
        h.controller.liveChanges.listen(updates.add);

        h.plugin.onLiveStatus = (_) => _room(title: 'Late night', online: 4321);
        unawaited(h.liveInfoJobs.single.run());
        h.settle();
        expect(h.controller.live?.title, 'Late night');
        expect(h.controller.live?.online, 4321);
        expect(h.controller.live?.phase, LivePhase.listening);
        expect(updates.last?.title, 'Late night');

        h.plugin.onLiveStatus = (_) => throw NetworkError(pluginId: 'fmp-test');
        unawaited(h.liveInfoJobs.single.run());
        h.settle();
        expect(h.controller.live?.title, 'Late night');
        expect(h.controller.state, isA<Playing>());
      });
    });

    // 停用插件時排程器移除它的工作（#255）：重新啟用、仍在收聽就再登記。
    test('is registered again when its plugin comes back while '
        'listening', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 1));
        expect(h.liveInfoJobs, hasLength(1));

        h.removePlugin('fmp-test');
        expect(h.liveInfoJobs, isEmpty);
        expect(h.controller.live?.phase, LivePhase.listening);

        h.restorePlugin(h.plugin);
        expect(h.liveInfoJobs.map((job) => job.pluginId), ['fmp-test']);

        h.plugin.onLiveStatus = (_) => _room(title: 'Back', online: 7);
        unawaited(h.liveInfoJobs.single.run());
        h.settle();
        expect(h.controller.live?.title, 'Back');

        // 換到同插件的另一個直播間也有登記。
        unawaited(
          h.controller.playLive(
            const LiveTarget(pluginId: 'fmp-test', roomId: 'r2', title: 'Two'),
          ),
        );
        h.elapse(const Duration(seconds: 1));
        expect(h.liveInfoJobs.map((job) => job.pluginId), ['fmp-test']);
      });
    });

    test('a removed plugin is not registered again while it is gone, nor '
        'after the stream ended', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 1));

        h
          ..removePlugin('fmp-test')
          // 別的插件的清單改變不會替不在的插件登記。
          ..removePlugin('fmp-other');
        expect(h.liveInfoJobs, isEmpty);

        h.restorePlugin(h.plugin);
        h.plugin.onLiveStatus = (_) => _room(status: LiveRoomStatus.offline);
        h.backend.endEarly();
        h.elapse(const Duration(milliseconds: 10));
        expect(h.controller.live?.phase, LivePhase.ended);
        expect(h.liveInfoJobs, isEmpty);

        h.restorePlugin(h.otherPlugin);
        expect(h.liveInfoJobs, isEmpty, reason: 'the stream ended');
      });
    });

    test('a room stopped for good is not registered again when the plugins '
        'change', () {
      fakeAsync((async) {
        final h = _harness(async);
        h.plugin.onResolveLive = (_) => throw Unavailable(pluginId: 'fmp-test');
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 1));
        expect(h.controller.state, isA<Failed>());
        expect(h.controller.live?.phase, LivePhase.listening);
        expect(h.liveInfoJobs, isEmpty);

        h.removePlugin('fmp-other');
        expect(h.liveInfoJobs, isEmpty);
      });
    });

    test('is not registered again by a plugin change that arrives while '
        'disposing', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 1));

        unawaited(h.controller.dispose());
        h.removePlugin('fmp-other');
        expect(h.liveInfoJobs, isEmpty);
      });
    });

    test('a result that arrives after the room changed is dropped', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.playLive(_target));
        h.elapse(const Duration(seconds: 1));
        final gate = Completer<LiveRoom>();
        h.plugin.onLiveStatus = (_) => gate.future;
        unawaited(h.liveInfoJobs.single.run());
        h.settle();

        unawaited(h.controller.stopLive());
        h.settle();
        gate.complete(_room(title: 'Stale'));
        h.settle();

        expect(h.controller.live, isNull);
      });
    });
  });

  group('decideLiveRecovery', () {
    LiveRecoveryAction decide(
      PlaybackFailure failure, {
      NetworkStatus network = NetworkStatus.online,
      int reconnects = 0,
    }) => decideLiveRecovery(failure, network: network, reconnects: reconnects);

    test('confirms and reconnects after 1, 3 and 9 s, then gives up', () {
      for (final (reconnects, seconds) in [(0, 1), (1, 3), (2, 9)]) {
        expect(
          decide(const StreamInterrupted(), reconnects: reconnects),
          isA<ConfirmThenReconnect>()
              .having((a) => a.delay, 'delay', Duration(seconds: seconds))
              .having((a) => a.attempt, 'attempt', reconnects + 1),
        );
      }
      expect(
        decide(const StreamInterrupted(), reconnects: 3),
        isA<LiveGiveUp>(),
      );
    });

    test('treats every stream failure the same way', () {
      for (final failure in [
        const StreamInterrupted(),
        const StreamUnopenable(),
        const StreamUnopenable(httpStatus: 403),
        const BufferingStalled(),
        ResolveFailed(NetworkError(pluginId: 'p')),
        ResolveFailed(RateLimited(pluginId: 'p')),
      ]) {
        expect(
          decide(failure),
          isA<ConfirmThenReconnect>(),
          reason: '$failure',
        );
      }
    });

    test('waits for the network without counting, even when the attempts '
        'are used up', () {
      for (final network in [
        NetworkStatus.noInterface,
        NetworkStatus.unreachable,
      ]) {
        expect(
          decide(const StreamInterrupted(), network: network, reconnects: 3),
          isA<LiveWaitForNetwork>(),
          reason: '$network',
        );
      }
    });

    test('stops on errors that a reconnect cannot fix', () {
      for (final error in [
        Unavailable(pluginId: 'p'),
        NotFound(pluginId: 'p'),
        Unsupported(pluginId: 'p'),
        VerificationRequired(pluginId: 'p'),
      ]) {
        expect(decide(ResolveFailed(error)), isA<LiveStop>(), reason: '$error');
      }
      expect(decide(const PreviewOnly()), isA<LiveStop>());
    });
  });
}
