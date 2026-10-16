import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/domain/mix_identity.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/mix_session.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';

import '../support/pump_until.dart' show settle;
import 'fake_source_plugin.dart';

// Mix 的開始與補歌（ADR 0031 §決定 9–10）：補歌時機、去重、換種子、標題、並行、失敗
// 與同一首內不重試。用真的 `QueueModel` 與假插件，不經控制器。

TrackSummary summary(String id) =>
    TrackSummary(sourceTypeId: 'fmp-test', sourceId: id, title: 'Song $id');

TrackInfo info(String id) => summary(id).toTrackInfo();

MixBatch batch(
  Iterable<String> ids, {
  String mixId = 'm1',
  String title = 'Mix',
  String? cursor,
}) => MixBatch(
  mixId: mixId,
  title: title,
  tracks: [for (final id in ids) summary(id)],
  cursor: cursor,
);

const initial = MixIdentity(
  pluginId: 'fmp-test',
  mixId: 'm1',
  title: 'My mix',
  cursor: 'c1',
);

final class Fixture {
  Fixture({
    MixIdentity identity = initial,
    int count = 5,
    bool pluginInstalled = true,
  }) {
    plugin = FakeSourcePlugin((_) => const [], mix: true);
    queue.startMix(identity, [for (var i = 0; i < count; i++) info('$i')]);
    session = MixSession(
      queue: queue,
      fetch: (pluginId, query) => plugin.mix(query),
      hasPlugin: (_) => pluginInstalled,
      log: log,
      onChanged: () => changes++,
    );
  }

  final queue = QueueModel();
  final log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
  late final FakeSourcePlugin plugin;
  late final MixSession session;
  int changes = 0;

  List<String> get ids => [
    for (final entry in queue.state.entries) entry.track.sourceId,
  ];

  /// 前進 [count] 首並讓每一首「開始」。
  void play(int count) {
    for (var i = 0; i < count; i++) {
      queue.moveNext();
      session.trackStarted();
    }
  }

  List<LogRecord> reports(String message) => [
    for (final record in log.history)
      if (record.tag == 'mix' && record.message == message) record,
  ];
}

void main() {
  group('when to refill', () {
    test('only when one song or fewer is left after the current one', () async {
      final f = Fixture();
      f.plugin.onMix = (_) => batch(['5', '6'], cursor: 'c2');

      f.session.trackStarted();
      expect(f.plugin.mixQueries, isEmpty, reason: 'four songs left');
      f.play(1);
      expect(f.plugin.mixQueries, isEmpty, reason: 'three songs left');
      f.play(1);
      expect(f.plugin.mixQueries, isEmpty, reason: 'two songs left');
      f.play(1);
      await settle();
      expect(f.plugin.mixQueries, hasLength(1), reason: 'one song left');
    });

    test('also on the last song', () async {
      final f = Fixture(count: 1);
      f.plugin.onMix = (_) => batch(['5'], cursor: 'c2');

      f.session.trackStarted();
      await settle();

      expect(f.plugin.mixQueries, hasLength(1));
    });

    test('not in a temporary play, but again once it is over', () async {
      final f = Fixture(count: 2);
      f.plugin.onMix = (_) => batch(['9'], cursor: 'c2');
      f.queue.playTemporary(info('t'), position: Duration.zero, playing: true);

      f.session.trackStarted();
      await settle();
      expect(f.plugin.mixQueries, isEmpty);

      f.queue.moveNext();
      f.session.trackStarted();
      await settle();
      expect(f.plugin.mixQueries, hasLength(1));
    });

    test('not outside a mix', () async {
      final f = Fixture();
      f.queue.clear();
      f.queue.append([info('a')]);

      f.session.trackStarted();
      await settle();

      expect(f.plugin.mixQueries, isEmpty);
    });

    test('not when the plugin is gone, and without a failure report', () async {
      final f = Fixture(count: 1, pluginInstalled: false);

      f.session.trackStarted();
      await settle();

      expect(f.plugin.mixQueries, isEmpty);
      expect(f.reports('Mix refill failed'), isEmpty);
      expect(f.session.refilling, isFalse);
    });
  });

  group('what comes back', () {
    test('continues with the mix id and the cursor, then appends', () async {
      final f = Fixture(count: 2);
      f.plugin.onMix = (_) => batch(['2', '3'], cursor: 'c2');

      f.session.trackStarted();
      await settle();

      final query = f.plugin.mixQueries.single as MixContinueQuery;
      expect(query.mixId, 'm1');
      expect(query.cursor, 'c1');
      expect(f.ids, ['0', '1', '2', '3']);
      expect(f.queue.state.mix?.cursor, 'c2');
      expect(f.changes, 1);
    });

    test('drops songs that are already queued', () async {
      final f = Fixture(count: 3);
      f.plugin.onMix = (_) => batch(['2', '3', '3', '4'], cursor: 'c2');

      f.session.trackStarted();
      f.play(1);
      await settle();

      expect(f.ids, ['0', '1', '2', '3', '4']);
    });

    test(
      'an empty cursor seeds a new batch from the last queued song',
      () async {
        final f = Fixture(
          count: 2,
          identity: initial.copyWith(clearCursor: true),
        );
        f.plugin.onMix = (_) =>
            batch(['1', '7', '8'], mixId: 'm2', title: 'Second', cursor: 'd1');

        f.session.trackStarted();
        await settle();

        final query = f.plugin.mixQueries.single as MixSeedQuery;
        expect(query.sourceId, '1');
        expect(query.cid, isNull);
        // 種子本身去重，Mix 身分換成新的。
        expect(f.ids, ['0', '1', '7', '8']);
        expect(f.queue.state.mix?.mixId, 'm2');
        expect(f.queue.state.mix?.cursor, 'd1');
      },
    );

    test('a seed of a part carries the part id', () async {
      final f = Fixture(identity: initial.copyWith(clearCursor: true));
      f.queue.startMix(initial.copyWith(clearCursor: true), [
        info('0'),
        summaryWithCid('v', 3).toTrackInfo(),
      ]);
      f.plugin.onMix = (_) => batch(['x'], mixId: 'm2');

      f.session.trackStarted();
      await settle();

      final query = f.plugin.mixQueries.single as MixSeedQuery;
      expect((query.sourceId, query.cid), ('v', 3));
    });

    test(
      'the title stays while the mix id stays, even if the plugin says another',
      () async {
        final f = Fixture(count: 2);
        f.plugin.onMix = (_) => batch(['2'], title: 'Mix', cursor: 'c2');

        f.session.trackStarted();
        await settle();

        expect(f.queue.state.mix?.title, 'My mix');
      },
    );

    test('the title is replaced when the mix id changes', () async {
      final f = Fixture(
        count: 2,
        identity: initial.copyWith(clearCursor: true),
      );
      f.plugin.onMix = (_) =>
          batch(['2'], mixId: 'm2', title: 'Second', cursor: 'd1');

      f.session.trackStarted();
      await settle();

      expect(f.queue.state.mix?.mixId, 'm2');
      expect(f.queue.state.mix?.title, 'Second');
    });
  });

  group('failures', () {
    test('a failed request is reported, not shown, and not retried on the same song', () async {
      final f = Fixture(count: 3);
      f.plugin.onMix = (_) => throw NetworkError(pluginId: 'fmp-test');

      f.play(1);
      await settle();
      f.session.trackStarted();
      f.session.trackStarted();
      await settle();

      expect(f.plugin.mixQueries, hasLength(1));
      expect(f.reports('Mix refill failed'), hasLength(1));
      expect(f.changes, 0);
      expect(f.ids, ['0', '1', '2']);
    });

    test('the next song tries again', () async {
      final f = Fixture(count: 3);
      var calls = 0;
      f.plugin.onMix = (_) {
        calls++;
        if (calls == 1) throw NetworkError(pluginId: 'fmp-test');
        return batch(['3'], cursor: 'c2');
      };

      f.play(1);
      await settle();
      expect(calls, 1);
      f.play(1);
      await settle();

      expect(calls, 2);
      expect(f.ids, ['0', '1', '2', '3']);
    });

    test(
      'a batch with nothing new is reported and not retried on the same song',
      () async {
        final f = Fixture(count: 2);
        f.plugin.onMix = (_) => batch(['0', '1'], cursor: 'c2');

        f.session.trackStarted();
        await settle();
        f.session.trackStarted();
        await settle();

        expect(f.plugin.mixQueries, hasLength(1));
        expect(f.reports('Mix refill added no track'), hasLength(1));
        expect(f.ids, ['0', '1']);
        // 游標照樣前進。
        expect(f.queue.state.mix?.cursor, 'c2');
      },
    );

    test('an error that is not an AppError is reported too', () async {
      final f = Fixture(count: 1);
      f.plugin.onMix = (_) => throw StateError('boom');

      f.session.trackStarted();
      await settle();

      expect(f.reports('Mix refill failed'), hasLength(1));
      expect(f.session.refilling, isFalse);
    });
  });

  group('one refill at a time', () {
    test(
      'a song that starts while one is running does not start another',
      () async {
        final f = Fixture(count: 3);
        final pending = Completer<MixBatch>();
        f.plugin.onMix = (_) => pending.future;

        f.play(1);
        f.play(1);
        f.session.trackStarted();

        expect(f.plugin.mixQueries, hasLength(1));
        expect(f.session.refilling, isTrue);
        pending.complete(batch(['3'], cursor: 'c2'));
        await settle();
        expect(f.session.refilling, isFalse);
        expect(f.ids, ['0', '1', '2', '3']);
      },
    );

    test('whenIdle completes when the running refill is done', () async {
      final f = Fixture(count: 1);
      final pending = Completer<MixBatch>();
      f.plugin.onMix = (_) => pending.future;
      f.session.trackStarted();

      var idle = false;
      unawaited(f.session.whenIdle.then((_) => idle = true));
      await settle();
      expect(idle, isFalse);

      pending.complete(batch(['9'], cursor: 'c2'));
      await settle();

      expect(idle, isTrue);
      expect(f.ids, ['0', '9']);
    });

    test('whenIdle is already done when nothing runs', () async {
      final f = Fixture();

      await f.session.whenIdle;

      expect(f.session.refilling, isFalse);
    });

    test('a result for a mix that was replaced meanwhile is dropped', () async {
      final f = Fixture(count: 1);
      final pending = Completer<MixBatch>();
      f.plugin.onMix = (_) => pending.future;
      f.session.trackStarted();

      f.queue.startMix(initial.copyWith(mixId: 'other'), [
        info('a'),
        info('b'),
        info('c'),
      ]);
      pending.complete(batch(['9'], cursor: 'c2'));
      await settle();

      expect(f.ids, ['a', 'b', 'c']);
      expect(f.queue.state.mix?.mixId, 'other');
      expect(f.changes, 0);
    });

    test('a result after the mix was left is dropped', () async {
      final f = Fixture(count: 1);
      final pending = Completer<MixBatch>();
      f.plugin.onMix = (_) => pending.future;
      f.session.trackStarted();

      f.queue.clear();
      pending.complete(batch(['9'], cursor: 'c2'));
      await settle();

      expect(f.ids, isEmpty);
      expect(f.queue.state.mix, isNull);
    });
  });

  group('starting a mix', () {
    test('replaces the queue with the batch and takes its identity', () async {
      final f = Fixture(count: 2);
      f.plugin.onMix = (_) =>
          batch(['a', 'b', 'a', 'c'], mixId: 'z', title: 'Z', cursor: 'k');

      await f.session.start('fmp-test', MixSeedQuery(sourceId: 'seed'));

      final query = f.plugin.mixQueries.single as MixSeedQuery;
      expect(query.sourceId, 'seed');
      expect(f.ids, ['a', 'b', 'c']);
      expect(
        f.queue.state.mix,
        const MixIdentity(
          pluginId: 'fmp-test',
          mixId: 'z',
          title: 'Z',
          cursor: 'k',
        ),
      );
      expect(f.queue.state.currentIndex, 0);
    });

    test(
      'a failure leaves the queue alone and is thrown for the caller',
      () async {
        final f = Fixture(count: 2);
        f.plugin.onMix = (_) => throw RateLimited(pluginId: 'fmp-test');

        await expectLater(
          f.session.start('fmp-test', MixSeedQuery(sourceId: 'seed')),
          throwsA(isA<RateLimited>()),
        );

        expect(f.ids, ['0', '1']);
        expect(f.queue.state.mix, initial);
      },
    );

    test(
      'a mix without tracks is NotFound and leaves the queue alone',
      () async {
        final f = Fixture(count: 2);
        f.plugin.onMix = (_) => batch([]);

        await expectLater(
          f.session.start('fmp-test', MixSeedQuery(sourceId: 'seed')),
          throwsA(isA<NotFound>()),
        );

        expect(f.ids, ['0', '1']);
      },
    );
  });
}

TrackSummary summaryWithCid(String id, int cid) => TrackSummary(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  cid: cid,
  title: 'Song $id',
);
