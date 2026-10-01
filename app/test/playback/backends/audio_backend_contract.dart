import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/backends/backend_rules.dart';

// 後端契約（ADR 0018 §如何確認）：同一份行為斷言，跑假後端（`flutter test`，
// fake_audio_backend_contract_test.dart）與平台的真後端（`integration_test/
// audio_backend_contract_test.dart`：Android 是 just_audio、Windows 是
// media_kit）。真後端要 platform channel 或 libmpv，在 `flutter test` 裡建不
// 起來。規則本身（結束分類、前瞻的清單修改）另外在 backend_rules_test.dart。

/// 定義一個測試案例：`flutter test` 傳 `test`，整合測試傳包了 `testWidgets`
/// 的版本。
typedef DefineCase = void Function(String description, Future<void> Function());

/// 對 [create] 建出的後端跑契約。[track] 是長 [trackLength] 的音檔，
/// [missing] 是開不起來的網址；[slack] 是引擎開流與事件延遲的餘裕。
void audioBackendContract({
  required DefineCase define,
  required Future<AudioBackend> Function() create,
  required Uri track,
  required Uri missing,
  required Duration trackLength,
  Duration slack = const Duration(seconds: 5),
}) {
  var nextId = 0;
  BackendSource source(Uri url) => BackendSource(id: ++nextId, url: url);

  final recorders = <Recorder>[];
  Future<Recorder> record() async {
    final recorder = Recorder(await create());
    recorders.add(recorder);
    return recorder;
  }

  // 失敗的案例也放掉引擎：留著還在播的播放器會拖累下一個案例。
  void defineCase(String description, Future<void> Function() body) =>
      define(description, () async {
        try {
          await body();
        } finally {
          for (final recorder in recorders) {
            await recorder.close();
          }
          recorders.clear();
        }
      });

  defineCase('plays a source to the end and reports it completed', () async {
    final recorder = await record();
    final a = source(track);
    await recorder.backend.open(a);

    await recorder.until(
      () => recorder.events.whereType<SourceEnded>().isNotEmpty,
      trackLength + slack,
    );
    expect(recorder.events, [
      isA<SourceEnded>()
          .having((e) => e.id, 'id', a.id)
          .having((e) => e.end, 'end', TrackEndReason.completed),
    ]);
    expect(
      recorder.statuses,
      contains(
        isA<BackendStatus>()
            .having((s) => s.sourceId, 'sourceId', a.id)
            .having((s) => s.playing, 'playing', isTrue)
            .having((s) => s.phase, 'phase', BackendPhase.ready),
      ),
    );
    expect(
      recorder.progress.where(
        (p) => p.sourceId == a.id && p.progress.position > Duration.zero,
      ),
      isNotEmpty,
    );
    await recorder.close();
  });

  defineCase('hands over to the look-ahead', () async {
    final recorder = await record();
    final a = source(track);
    final b = source(track);
    await recorder.backend.open(a);
    await recorder.untilReady(a.id, slack);
    await recorder.backend.setNext(b);

    await recorder.until(
      () => recorder.events.whereType<SourceEnded>().isNotEmpty,
      trackLength * 2 + slack,
    );
    expect(recorder.events, [
      isA<SourceAdvanced>()
          .having((e) => e.from, 'from', a.id)
          .having((e) => e.to, 'to', b.id)
          .having((e) => e.end, 'end', TrackEndReason.completed),
      isA<SourceEnded>()
          .having((e) => e.id, 'id', b.id)
          .having((e) => e.end, 'end', TrackEndReason.completed),
    ]);
    expect(
      recorder.statuses,
      contains(
        isA<BackendStatus>()
            .having((s) => s.sourceId, 'sourceId', b.id)
            .having((s) => s.playing, 'playing', isTrue),
      ),
    );
    await recorder.close();
  });

  defineCase('a replaced look-ahead is the one handed over', () async {
    final recorder = await record();
    final a = source(track);
    final b = source(track);
    final c = source(track);
    await recorder.backend.open(a);
    await recorder.untilReady(a.id, slack);
    await recorder.backend.setNext(b);
    await recorder.backend.setNext(c);

    await recorder.until(
      () => recorder.events.whereType<SourceAdvanced>().isNotEmpty,
      trackLength + slack,
    );
    expect(
      recorder.events.first,
      isA<SourceAdvanced>()
          .having((e) => e.from, 'from', a.id)
          .having((e) => e.to, 'to', c.id),
    );
    await recorder.close();
  });

  defineCase('a cleared look-ahead is not played', () async {
    final recorder = await record();
    final a = source(track);
    await recorder.backend.open(a);
    await recorder.untilReady(a.id, slack);
    await recorder.backend.setNext(source(track));
    await recorder.backend.setNext(null);

    await recorder.until(
      () => recorder.events.whereType<SourceEnded>().isNotEmpty,
      trackLength + slack,
    );
    expect(recorder.events, [
      isA<SourceEnded>().having((e) => e.id, 'id', a.id),
    ]);
    await recorder.close();
  });

  defineCase('a source that cannot be opened fails as open', () async {
    final recorder = await record();
    final bad = source(missing);
    await recorder.backend.open(bad);

    await recorder.until(() => recorder.events.isNotEmpty, slack);
    expect(recorder.events, [
      isA<SourceFailed>()
          .having((e) => e.id, 'id', bad.id)
          .having((e) => e.failure, 'failure', BackendFailure.open),
    ]);
    await recorder.close();
  });

  // 換來源時引擎可能還在送上一個檔案的位置、結束與錯誤（media_kit 的事件不帶
  // 項目）：它們不能算到新的來源上。
  Future<Recorder> playPastHalf(BackendSource a) async {
    final recorder = await record();
    await recorder.backend.open(a);
    await recorder.until(
      () => recorder.progress.any(
        (p) => p.sourceId == a.id && p.progress.position >= trackLength ~/ 2,
      ),
      trackLength + slack,
    );
    return recorder;
  }

  defineCase(
    'a source opened over a playing one starts at its own position',
    () async {
      final a = source(track);
      final b = source(track);
      final recorder = await playPastHalf(a);
      await recorder.backend.open(b);

      await recorder.until(
        () => recorder.progress.any((p) => p.sourceId == b.id),
        slack,
      );
      expect(
        recorder.progress
            .firstWhere((p) => p.sourceId == b.id)
            .progress
            .position,
        lessThan(trackLength ~/ 2),
      );
      await recorder.close();
    },
  );

  defineCase(
    'a source opened over a playing one reports its own failure',
    () async {
      final a = source(track);
      final bad = source(missing);
      final recorder = await playPastHalf(a);
      await recorder.backend.open(bad);

      await recorder.until(() => recorder.events.isNotEmpty, slack);
      expect(recorder.events, [
        isA<SourceFailed>()
            .having((e) => e.id, 'id', bad.id)
            .having((e) => e.failure, 'failure', BackendFailure.open),
      ]);
      expect(recorder.progress.where((p) => p.sourceId == bad.id), isEmpty);
      await recorder.close();
    },
  );

  defineCase('pausing before the source is ready keeps it paused', () async {
    final recorder = await record();
    final a = source(track);
    final opened = recorder.backend.open(a);
    await recorder.backend.pause();
    await opened;
    await recorder.untilReady(a.id, slack);

    // 播著的話這段時間會播到一半以上。
    await Future<void>.delayed(trackLength ~/ 2);
    expect(recorder.statuses.last.sourceId, a.id);
    expect(recorder.statuses.last.playing, isFalse);
    expect(
      recorder.progress.where(
        (p) => p.sourceId == a.id && p.progress.position >= trackLength ~/ 4,
      ),
      isEmpty,
    );
    expect(recorder.events, isEmpty);
    await recorder.close();
  });

  defineCase('starts at the given position', () async {
    final recorder = await record();
    final a = source(track);
    final start = trackLength ~/ 2;
    await recorder.backend.open(a, start: start);

    await recorder.until(
      () => recorder.progress.any((p) => p.sourceId == a.id),
      slack,
    );
    expect(
      recorder.progress.firstWhere((p) => p.sourceId == a.id).progress.position,
      greaterThanOrEqualTo(start - const Duration(milliseconds: 100)),
    );
    await recorder.close();
  });

  // PlaybackSession 把回報同步轉給控制器（broadcast(sync: true)），控制器處理時
  // 又會呼叫後端：回報在呼叫回來之前就送達的話，會在處理途中重入而拋錯。
  defineCase('reports arrive only after the call returns', () async {
    final recorder = await record();
    var calling = false;
    final early = <Object?>[];
    void check(Object? value) {
      if (calling) early.add(value);
    }

    final subscriptions = [
      recorder.backend.status.listen(check),
      recorder.backend.progress.listen(check),
      recorder.backend.events.listen(check),
    ];
    Future<void> call(Future<void> Function() method) {
      calling = true;
      try {
        return method();
      } finally {
        calling = false;
      }
    }

    final a = source(track);
    await call(() => recorder.backend.open(a));
    await recorder.untilReady(a.id, slack);
    await call(() => recorder.backend.setNext(source(track)));
    await call(recorder.backend.pause);
    await call(recorder.backend.play);
    await call(() => recorder.backend.seek(Duration.zero));
    await call(recorder.backend.stop);
    await call(() => recorder.backend.open(source(missing)));
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    expect(early, isEmpty);
    await recorder.close();
  });

  defineCase('pause and play toggle the playing flag', () async {
    final recorder = await record();
    final a = source(track);
    await recorder.backend.open(a);
    await recorder.untilReady(a.id, slack);

    await recorder.backend.pause();
    await recorder.until(
      () =>
          recorder.statuses.lastOrNull?.playing == false &&
          recorder.statuses.last.sourceId == a.id,
      slack,
    );
    expect(recorder.events, isEmpty);

    await recorder.backend.play();
    await recorder.until(
      () => recorder.statuses.lastOrNull?.playing ?? false,
      slack,
    );
    await recorder.close();
  });
}

/// 收下後端發出的一切。
final class Recorder {
  Recorder(this.backend) {
    _subscriptions
      ..add(backend.status.listen((s) => _record(statuses, s)))
      ..add(backend.progress.listen((p) => _record(progress, p)))
      ..add(backend.events.listen((e) => _record(events, e)));
  }

  final AudioBackend backend;
  final statuses = <BackendStatus>[];
  final progress = <SourceProgress>[];
  final events = <BackendEvent>[];
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _waiters = <(bool Function(), Completer<void>)>[];

  void _record<T>(List<T> list, T value) {
    list.add(value);
    for (final waiter in [..._waiters]) {
      final (condition, done) = waiter;
      if (condition()) {
        _waiters.remove(waiter);
        done.complete();
      }
    }
  }

  /// 等到 [condition] 成立（每收到一個值檢查一次）；超過 [timeout] 就失敗並列出
  /// 收到的東西。真後端要實際播放，所以等的是實際時間。
  Future<void> until(bool Function() condition, Duration timeout) {
    if (condition()) return Future.value();
    final done = Completer<void>();
    final waiter = (condition, done);
    _waiters.add(waiter);
    final timer = Timer(timeout, () {
      if (done.isCompleted) return;
      _waiters.remove(waiter);
      done.completeError(
        TestFailure(
          'Timed out after $timeout.\n'
          'events: $events\n'
          'statuses: $statuses',
        ),
      );
    });
    return done.future.whenComplete(timer.cancel);
  }

  /// 等到 [sourceId] 載入好（ready）。
  Future<void> untilReady(int sourceId, Duration timeout) => until(
    () => statuses.any(
      (s) => s.sourceId == sourceId && s.phase == BackendPhase.ready,
    ),
    timeout,
  );

  var _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await backend.dispose();
  }
}
