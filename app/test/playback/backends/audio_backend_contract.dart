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
/// [missing] 是開不起來的網址（Dart 端就失敗，例如不存在的 asset），
/// [forbidden] 是 HTTP 回 403 的網址（引擎開流時才失敗；整合測試的伺服器在
/// `setUpAll` 才起來，所以在案例裡才讀）。[reportsHttpStatus]：引擎給不給得出
/// 狀態碼（見 `AudioBackend` 的 dartdoc）。[selectsOutputDevice]：平台宣告
/// 能不能選輸出裝置（`PlaybackSupport.outputDeviceSelection`）。[slack] 是引擎
/// 開流與事件延遲的餘裕。
void audioBackendContract({
  required DefineCase define,
  required Future<AudioBackend> Function() create,
  required Uri track,
  required Uri missing,
  required Uri Function() forbidden,
  required bool reportsHttpStatus,
  required bool selectsOutputDevice,
  required Duration trackLength,
  Duration slack = const Duration(seconds: 5),
}) {
  var nextId = 0;
  BackendSource source(Uri url) => BackendSource(id: ++nextId, url: url);

  final recorders = <Recorder>[];
  var created = 0;
  Future<Recorder> record() async {
    created++;
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

  // 這一案要排第一：mpv 只把 ffmpeg 的 log（狀態碼那一行）交給行程裡第一個
  // 還活著的實例，前面的案例放掉的播放器 media_kit 5 秒後才銷毀（見
  // `AudioBackend`）。順序被改了在假後端（`flutter test`）就紅，不必等到實機
  // 才看到 mpv 少了狀態碼。ExoPlayer 對 403 會重試幾次才報錯，所以等久一點。
  defineCase(
    'a source refused over HTTP fails as open with the status',
    () async {
      final recorder = await record();
      expect(
        created,
        1,
        reason:
            'this case must create the first backend of the run: mpv passes '
            'ffmpeg log lines (the HTTP status) only to the first live player',
      );
      final refused = source(forbidden());
      await recorder.backend.open(refused);

      await recorder.until(() => recorder.events.isNotEmpty, slack * 2);
      expect(recorder.events, [
        isA<SourceFailed>()
            .having((e) => e.id, 'id', refused.id)
            .having((e) => e.failure, 'failure', BackendFailure.open)
            .having(
              (e) => e.httpStatus,
              'httpStatus',
              reportsHttpStatus ? 403 : isNull,
            ),
      ]);
      await recorder.close();
    },
  );

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

  // 前瞻開不起來（M1 的後續）：目前這首照常播完、不接上前瞻，失敗算在前瞻上而且
  // 先到；之後不再說自己在播。[bad] 有兩種：Dart 端就失敗的（不存在的 asset），
  // 與引擎開流時才失敗的（HTTP 403：ExoPlayer 換到前瞻後才報、mpv 預開時與交接
  // 時各報一次）。
  Future<void> lookAheadFails(Uri Function() bad, Duration wait) async {
    final recorder = await record();
    final a = source(track);
    final next = source(bad());
    await recorder.backend.open(a);
    await recorder.untilReady(a.id, slack);
    await recorder.backend.setNext(next);

    await recorder.until(
      () => recorder.events.whereType<SourceEnded>().isNotEmpty,
      trackLength + wait,
    );
    expect(recorder.events, [
      isA<SourceFailed>()
          .having((e) => e.id, 'id', next.id)
          .having((e) => e.failure, 'failure', BackendFailure.open),
      isA<SourceEnded>()
          .having((e) => e.id, 'id', a.id)
          .having((e) => e.end, 'end', TrackEndReason.completed),
    ]);
    await recorder.until(
      () => recorder.statuses.lastOrNull?.playing == false,
      slack,
    );
    expect(recorder.statuses.last.sourceId, isNot(next.id));
    expect(recorder.progress.where((p) => p.sourceId == next.id), isEmpty);
    // 不會晚一點又冒出來。
    await Future<void>.delayed(trackLength);
    expect(recorder.events, hasLength(2));
    await recorder.close();
  }

  defineCase(
    'a look-ahead that cannot be opened fails without cutting the current '
    'source',
    () => lookAheadFails(() => missing, slack),
  );

  defineCase(
    'a look-ahead refused over HTTP fails without cutting the current source',
    () => lookAheadFails(forbidden, slack * 2),
  );

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
    await call(() => recorder.backend.setVolume(0.5));
    await call(() => recorder.backend.setSpeed(1.5));
    if (recorder.backend.outputDevices case final devices?) {
      await call(() => devices.select(null));
    }
    await call(recorder.backend.stop);
    await call(() => recorder.backend.open(source(missing)));
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    expect(early, isEmpty);
    await recorder.close();
  });

  // E19（design §7.6）：音量與速度在 open 之前設定也生效，接上前瞻、換來源後
  // 維持。速度看實際的播放時間：2 倍速時兩首（中間交接）在一首半的時間內播完，
  // 1 倍速要兩首的時間。
  defineCase(
    'volume and speed set before open hold across a handover and a new source',
    () async {
      final recorder = await record();
      final backend = recorder.backend;
      await backend.setVolume(0.4);
      await backend.setSpeed(2);
      final a = source(track);
      final b = source(track);
      await backend.open(a);
      await recorder.untilReady(a.id, slack);
      final readyAt = DateTime.now();
      await backend.setNext(b);

      await recorder.until(
        () => recorder.events.whereType<SourceEnded>().isNotEmpty,
        trackLength * 2 + slack,
      );
      final elapsed = DateTime.now().difference(readyAt);
      expect(recorder.events, [
        isA<SourceAdvanced>()
            .having((e) => e.from, 'from', a.id)
            .having((e) => e.to, 'to', b.id),
        isA<SourceEnded>().having((e) => e.id, 'id', b.id),
      ]);
      expect(
        elapsed,
        lessThan(trackLength * 1.5),
        reason: 'two tracks at 2x take about one track of time',
      );
      await eventually(
        () => (backend.volume - 0.4).abs() < 0.001,
        slack,
        'the volume after the handover',
      );
      expect(backend.speed, 2);

      final c = source(track);
      await backend.open(c);
      await recorder.untilReady(c.id, slack);
      expect(backend.volume, closeTo(0.4, 0.001));
      expect(backend.speed, 2);
      await recorder.close();
    },
  );

  defineCase('the speed is clamped to 0.5–2.0 and the volume to 0–1', () async {
    final recorder = await record();
    final backend = recorder.backend;
    await backend.setSpeed(3);
    expect(backend.speed, maxSpeed);
    await backend.setSpeed(0.1);
    expect(backend.speed, minSpeed);
    await backend.setVolume(1.5);
    await eventually(
      () => (backend.volume - 1).abs() < 0.001,
      slack,
      'the volume clamped to 1',
    );
    await recorder.close();
  });

  // 輸出裝置（design §7.6）：有沒有與平台宣告一致；Windows 選「系統預設」之後
  // 仍在播。裝置失敗（拔掉正在用的裝置）在實機手動驗。
  defineCase('output devices follow the platform declaration and choosing the '
      'system default keeps playing', () async {
    final recorder = await record();
    final devices = recorder.backend.outputDevices;
    expect(devices != null, selectsOutputDevice);
    if (devices == null) return recorder.close();

    final listed = await devices.available.first.timeout(slack);
    expect(listed, isNotEmpty);
    expect(
      [for (final device in listed) device.id],
      isNot(contains('auto')),
      reason: 'the system default is null, not a listed device',
    );
    final a = source(track);
    await recorder.backend.open(a);
    await recorder.untilReady(a.id, slack);
    await devices.select(null);
    final before = recorder.progress.length;

    await recorder.until(
      () => recorder.progress.skip(before).any((p) => p.sourceId == a.id),
      slack,
    );
    expect(recorder.statuses.last.playing, isTrue);
    expect(devices.selected, isNull);
    expect(recorder.events.whereType<OutputDeviceFailed>(), isEmpty);
    expect(recorder.events.whereType<SourceFailed>(), isEmpty);
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

/// 每 20 毫秒看一次 [condition]，超過 [timeout] 就以 [what] 失敗：引擎的屬性
/// （mpv 的 `volume`）晚一點才回報，又不一定伴隨事件。
Future<void> eventually(
  bool Function() condition,
  Duration timeout,
  String what,
) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timed out after $timeout waiting for $what.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
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
