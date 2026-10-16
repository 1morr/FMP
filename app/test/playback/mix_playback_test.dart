import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/playback_events.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'playback_controller_test.dart' show Harness, track;

// Mix 經播放控制器（ADR 0031 §決定 9–10）：開始、補歌三批後換種子、被拒絕的操作、清空退出、
// 臨時播放回到 Mix、播到底時等補歌。佇列與補歌各自的規則在 `queue_model_test.dart`、
// `mix_session_test.dart`；這裡守它們接在控制器上的樣子。

TrackSummary _summary(String id) =>
    TrackSummary(sourceTypeId: 'fmp-test', sourceId: id, title: 'Song $id');

MixBatch _batch(
  Iterable<String> ids, {
  String mixId = 'm1',
  String title = 'Mix',
  String? cursor,
}) => MixBatch(
  mixId: mixId,
  title: title,
  tracks: [for (final id in ids) _summary(id)],
  cursor: cursor,
);

/// fmp-test 的三批（每批 5 首，第二批重複第一批的第 3 首，第三批沒有 cursor），之後
/// 以最後一首當種子開 `m2`。
MixBatch _threeBatches(MixQuery query) => switch (query) {
  MixSeedQuery(:final sourceId) when sourceId == 'seed' => _batch([
    'a1',
    'a2',
    'a3',
    'a4',
    'a5',
  ], cursor: 'c2'),
  MixSeedQuery() => _batch(
    ['b1', 'b2', 'b3', 'b4', 'b5'],
    mixId: 'm2',
    title: 'Second',
    cursor: 'd2',
  ),
  MixContinueQuery(cursor: 'c2') => _batch(
    ['a3', 'a6', 'a7', 'a8', 'a9'],
    title: 'Other title',
    cursor: 'c3',
  ),
  MixContinueQuery(cursor: 'c3') => _batch(['a10', 'a11', 'a12', 'a13', 'a14']),
  MixContinueQuery() => throw NotFound(pluginId: 'fmp-test'),
};

List<String> _ids(Harness h) => [
  for (final entry in h.controller.queue.entries) entry.track.sourceId,
];

/// 開始 Mix 之後補歌送出的請求（第一個請求是開始本身）。
List<MixQuery> _refills(Harness h) => h.plugin.mixQueries.skip(1).toList();

Harness _harness(FakeAsync async) {
  final h = Harness(async);
  h.plugin.onMix = _threeBatches;
  h.returnSettings = (rememberPosition: true, rewind: Duration.zero);
  return h;
}

void main() {
  group('starting', () {
    test('replaces the queue, plays the first song and takes the title', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.playQueue([track('x'), track('y')]));
        h.elapse(const Duration(milliseconds: 100));

        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(milliseconds: 100));

        final queue = h.controller.queue;
        expect(queue.mode, QueueMode.mix);
        expect(queue.mix?.title, 'Mix');
        expect(_ids(h), ['a1', 'a2', 'a3', 'a4', 'a5']);
        expect(queue.currentIndex, 0);
        expect(h.controller.state, isA<Playing>());
        expect(h.openedPaths.last, '/a1.m4a');
        expect(h.playedIds.last, 'a1');
      });
    });

    test('starts from a stored seed: replaces the queue, passes the seed', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.playQueue([track('x'), track('y')]));
        h.elapse(const Duration(milliseconds: 100));

        unawaited(
          h.controller.startMixFromSeed(
            'fmp-test',
            MixSeedQuery(sourceId: 'seed', cid: 7),
          ),
        );
        h.elapse(const Duration(milliseconds: 100));

        final query = h.plugin.mixQueries.first as MixSeedQuery;
        expect(query.sourceId, 'seed');
        expect(query.cid, 7);
        expect(h.controller.queue.mode, QueueMode.mix);
        expect(_ids(h), isNotEmpty);
        expect(_ids(h), isNot(contains('x')));
        expect(h.playedIds.last, 'a1');
      });
    });

    test('a failure throws, shows nothing and leaves the queue alone', () {
      fakeAsync((async) {
        final h = _harness(async);
        h.plugin.onMix = (_) => throw RateLimited(pluginId: 'fmp-test');
        unawaited(h.playQueue([track('x'), track('y')]));
        h.elapse(const Duration(milliseconds: 100));

        Object? error;
        h.controller.startMix(track('seed')).catchError((Object e) {
          error = e;
        });
        h.elapse(const Duration(milliseconds: 100));

        expect(error, isA<RateLimited>());
        expect(h.controller.queue.mode, QueueMode.queue);
        expect(_ids(h), ['x', 'y']);
        expect(h.controller.state, isA<Playing>());
      });
    });
  });

  group('refilling while it plays', () {
    test('three batches, then a new seed from the last song', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(milliseconds: 100));
        expect(_refills(h), isEmpty);

        // 第 4 首開始時之後只剩 1 首：續取第二批，重複的 a3 被丟掉。
        h.elapse(const Duration(seconds: 6));
        expect(h.controller.queue.currentIndex, 3);
        expect(_refills(h), hasLength(1));
        expect((_refills(h).last as MixContinueQuery).cursor, 'c2');
        expect(_ids(h), ['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8', 'a9']);
        // 同一個 mixId 續取，標題不被插件另給的標題蓋掉。
        expect(h.controller.queue.mix?.title, 'Mix');
        expect(h.controller.queue.mix?.cursor, 'c3');

        // 第 8 首開始時補第三批，Mix 到此沒有更多。
        h.elapse(const Duration(seconds: 8));
        expect(h.controller.queue.currentIndex, 7);
        expect(_refills(h), hasLength(2));
        expect(_ids(h), hasLength(14));
        expect(h.controller.queue.mix?.cursor, isNull);

        // 第 13 首開始時 cursor 已空：以佇列最後一首當種子，Mix 身分換成 m2 與它的標題。
        h.elapse(const Duration(seconds: 10));
        expect(h.controller.queue.currentIndex, 12);
        expect(_refills(h), hasLength(3));
        final seed = _refills(h).last as MixSeedQuery;
        expect(seed.sourceId, 'a14');
        expect(h.controller.queue.mix?.mixId, 'm2');
        expect(h.controller.queue.mix?.title, 'Second');
        expect(_ids(h).sublist(14), ['b1', 'b2', 'b3', 'b4', 'b5']);
        expect(h.controller.state, isA<Playing>());
      });
    });

    test('the look-ahead follows the songs that were just appended', () {
      fakeAsync((async) {
        final h = _harness(async);
        h.plugin.onMix = (query) => switch (query) {
          MixSeedQuery() => _batch(['a1', 'a2'], cursor: 'c2'),
          MixContinueQuery() => _batch(['a3'], cursor: 'c3'),
        };
        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(milliseconds: 500));

        // 佇列的最後一首之後補到了新歌：第 2 首開始時前瞻接的是 a3。
        h.elapse(const Duration(seconds: 2));
        expect(h.controller.queue.currentIndex, 1);
        expect(_ids(h), ['a1', 'a2', 'a3']);
        expect(h.backend.nextSources.last?.url.path, '/a3.m4a');
      });
    });
  });

  group('refused operations', () {
    test('add, play next and shuffle change nothing and say nothing', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(milliseconds: 100));
        final before = _ids(h);

        expect(h.controller.addToQueue([track('z')]), isFalse);
        expect(h.controller.playNext([track('z')]), isFalse);
        h.controller.setShuffle(true);
        h.settle();

        expect(_ids(h), before);
        expect(h.controller.queue.shuffleEnabled, isFalse);
        // 入口本來就停用：不當成「佇列滿了」提示。
        expect(h.events, isEmpty);
      });
    });

    test('dragging and removing still work', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(milliseconds: 100));

        h.controller.move(4, 1);
        unawaited(h.controller.removeAt(0));
        h.elapse(const Duration(milliseconds: 100));

        expect(_ids(h).toSet(), {'a5', 'a2', 'a3', 'a4'});
        expect(h.controller.queue.mode, QueueMode.mix);
      });
    });

    test('clearing the queue leaves the mix and stops', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(milliseconds: 100));

        unawaited(h.controller.clear());
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.mode, QueueMode.queue);
        expect(h.controller.queue.mix, isNull);
        expect(h.controller.queue.entries, isEmpty);
        expect(h.controller.state, isA<Idle>());
        // 退出之後又能加入了。
        expect(h.controller.addToQueue([track('z')]), isTrue);
      });
    });
  });

  group('around the mix', () {
    test(
      'a temporary play comes back to the mix queue and keeps refilling',
      () {
        fakeAsync((async) {
          final h = _harness(async);
          unawaited(h.controller.startMix(track('seed')));
          h.elapse(const Duration(seconds: 3));
          expect(h.controller.queue.currentIndex, 1);

          unawaited(h.controller.playTemporary(track('t')));
          h.elapse(const Duration(milliseconds: 500));
          expect(h.controller.queue.mode, QueueMode.temporary);
          expect(h.controller.queue.mix, isNotNull);

          // 臨時曲目播完，回到 Mix 的第 2 首（從進入時的位置續播）。
          h.elapse(const Duration(milliseconds: 1600));
          expect(h.controller.queue.mode, QueueMode.mix);
          expect(h.controller.queue.currentIndex, 1);
          expect(h.openedPaths.last, '/a2.m4a');
          // 臨時播放中沒有補歌。
          expect(_refills(h), isEmpty);
        });
      },
    );

    test('starting another mix replaces the first one', () {
      fakeAsync((async) {
        final h = _harness(async);
        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(milliseconds: 100));

        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.mode, QueueMode.mix);
        expect(h.controller.queue.currentIndex, 0);
        expect(h.openedPaths.last, '/a1.m4a');
      });
    });
  });

  group('the end of the queue', () {
    /// 一首的 Mix：第 1 首開始時就補歌，由 [pending] 決定什麼時候回來。
    Harness lone(FakeAsync async, Completer<MixBatch> pending) {
      final h = _harness(async);
      h.plugin.onMix = (query) => switch (query) {
        MixSeedQuery(:final sourceId) when sourceId == 'seed' => _batch([
          'a1',
        ], cursor: 'c2'),
        _ => pending.future,
      };
      return h;
    }

    test('waits for a running refill and plays what it brings', () {
      fakeAsync((async) {
        final pending = Completer<MixBatch>();
        final h = lone(async, pending);
        unawaited(h.controller.startMix(track('seed')));

        // a1 播完了，補歌還沒回來：不結束，等。
        h.elapse(const Duration(seconds: 3));
        expect(h.controller.state, isA<Loading>());
        expect(h.controller.queue.currentIndex, 0);

        pending.complete(_batch(['a2', 'a3'], cursor: 'c3'));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.queue.currentIndex, 1);
        expect(h.controller.state, isA<Playing>());
        expect(h.openedPaths.last, '/a2.m4a');
      });
    });

    test('stops when the refill brings nothing new', () {
      fakeAsync((async) {
        final pending = Completer<MixBatch>();
        final h = lone(async, pending);
        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(seconds: 3));
        expect(h.controller.state, isA<Loading>());

        pending.complete(_batch(['a1'], cursor: 'c3'));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Idle>());
        expect(h.controller.queue.currentIndex, 0);
      });
    });

    test('stops when the refill fails', () {
      fakeAsync((async) {
        final pending = Completer<MixBatch>();
        final h = lone(async, pending);
        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(seconds: 3));

        pending.completeError(NetworkError(pluginId: 'fmp-test'));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Idle>());
        expect(h.events, isEmpty);
      });
    });

    test('stops at once when no refill is running', () {
      fakeAsync((async) {
        final h = _harness(async);
        h.plugin.onMix = (query) => switch (query) {
          MixSeedQuery(:final sourceId) when sourceId == 'seed' => _batch([
            'a1',
          ], cursor: 'c2'),
          _ => throw NetworkError(pluginId: 'fmp-test'),
        };
        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(seconds: 3));

        // 補歌已經失敗過了（同一首內不重試），播完就結束。
        expect(_refills(h), hasLength(1));
        expect(h.controller.state, isA<Idle>());
      });
    });

    test('a song picked while waiting wins over the refill', () {
      fakeAsync((async) {
        final pending = Completer<MixBatch>();
        final h = lone(async, pending);
        unawaited(h.controller.startMix(track('seed')));
        h.elapse(const Duration(seconds: 3));
        expect(h.controller.state, isA<Loading>());

        unawaited(h.controller.jumpTo(0));
        h.elapse(const Duration(milliseconds: 100));
        pending.complete(_batch(['a2'], cursor: 'c3'));
        h.elapse(const Duration(milliseconds: 100));

        // 重新播 a1，補來的 a2 只是附加在後面，不會被「等待」接手而插隊播出。
        expect(h.controller.queue.currentIndex, 0);
        expect(h.openedPaths.last, '/a1.m4a');
      });
    });

    /// 兩首的 Mix，第 2 首播不了：第 1 首開始時就補歌（由 [pending] 決定什麼時候
    /// 回來），跳到第 2 首時補歌還在跑。
    Harness failingLast(FakeAsync async, Completer<MixBatch> pending) {
      final h = _harness(async);
      h.plugin.onMix = (query) => switch (query) {
        MixSeedQuery(:final sourceId) when sourceId == 'seed' => _batch([
          'a1',
          'a2',
        ], cursor: 'c2'),
        _ => pending.future,
      };
      final respond = h.plugin.respond;
      h.plugin.respond = (request) => request.sourceId == 'a2'
          ? throw Unavailable(pluginId: 'fmp-test')
          : respond(request);
      unawaited(h.controller.startMix(track('seed')));
      h.elapse(const Duration(milliseconds: 100));
      unawaited(h.controller.jumpTo(1));
      h.elapse(const Duration(milliseconds: 100));
      return h;
    }

    test('a skipped last song waits for the refill and moves on', () {
      fakeAsync((async) {
        final pending = Completer<MixBatch>();
        final h = failingLast(async, pending);

        // a2 播不了，補歌還沒回來：不停下，等。
        expect(h.controller.state, isNot(isA<Failed>()));
        expect(h.events, isEmpty);

        pending.complete(_batch(['a3'], cursor: 'c3'));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.events, [isA<TrackSkipped>()]);
        expect(h.controller.queue.currentIndex, 2);
        expect(h.openedPaths.last, '/a3.m4a');
      });
    });

    test('a skipped last song stops when the refill brings nothing', () {
      fakeAsync((async) {
        final pending = Completer<MixBatch>();
        final h = failingLast(async, pending);

        pending.completeError(NetworkError(pluginId: 'fmp-test'));
        h.elapse(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Failed>());
        expect(h.controller.queue.currentIndex, 1);
      });
    });

    test(
      'a refill that returns after the controller is disposed is harmless',
      () {
        fakeAsync((async) {
          final pending = Completer<MixBatch>();
          final h = lone(async, pending);
          unawaited(h.controller.startMix(track('seed')));
          h.elapse(const Duration(seconds: 1));

          unawaited(h.controller.dispose());
          h.settle();
          pending.complete(_batch(['a2'], cursor: 'c3'));
          h.settle();
        });
      },
    );
  });
}
