import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_lifecycle.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/scheduler_runs_repository.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/scheduler/background_scheduler.dart';

import '../support/fake_network_interfaces.dart';
import '../support/memory_database.dart';

/// 一個假工作：記下每次執行的時間，可以讓它卡住、丟錯。
final class _Probe {
  _Probe(this.id, {this.pluginId, this.interval = const Duration(minutes: 10)});

  final String id;
  final String? pluginId;
  final Duration? interval;

  final starts = <DateTime>[];
  final contexts = <JobContext>[];
  Object? failWith;
  Completer<void>? gate;
  int running = 0;
  int maxRunning = 0;

  SchedulerJob get job => SchedulerJob(
    id: id,
    pluginId: pluginId,
    interval: interval,
    run: (context) async {
      starts.add(clock.now());
      contexts.add(context);
      running++;
      maxRunning = running > maxRunning ? running : maxRunning;
      try {
        if (gate case final gate?) await gate.future;
        if (failWith case final error?) throw error;
      } finally {
        running--;
      }
    },
  );
}

/// 第一次 [check] 等到測試放行才回答的介面。
final class _SlowFirstCheck implements NetworkInterfaces {
  _SlowFirstCheck(this._inner);

  final FakeNetworkInterfaces _inner;
  final firstCheck = Completer<void>();

  @override
  Future<bool> check() async {
    await firstCheck.future;
    return _inner.check();
  }

  @override
  Stream<bool> get changes => _inner.changes;
}

/// 測試環境：真的網路狀態與生命週期 provider，由假介面與測試 binding 驅動。
final class _Env {
  _Env({
    AppDatabase? database,
    bool online = true,
    bool slowFirstCheck = false,
  }) {
    this.database = database ?? memoryDatabase();
    interfaces = FakeNetworkInterfaces(available: online);
    slow = slowFirstCheck ? _SlowFirstCheck(interfaces) : null;
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(this.database),
        logProvider.overrideWithValue(log),
        networkInterfacesProvider.overrideWithValue(slow ?? interfaces),
      ],
    );
  }

  late final AppDatabase database;
  late final FakeNetworkInterfaces interfaces;
  late final _SlowFirstCheck? slow;
  late final Log log;
  late final ProviderContainer container;
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  BackgroundScheduler get scheduler =>
      container.read(backgroundSchedulerProvider.notifier);

  /// 建立排程器與它的輸入，讓計時器對準第一個到期的工作。
  void start(FakeAsync async) {
    container
      ..listen(networkStatusProvider, (_, _) {})
      ..read(backgroundSchedulerProvider);
    async.flushMicrotasks();
  }

  void lifecycle(FakeAsync async, AppLifecycleState state) {
    binding.handleAppLifecycleStateChanged(state);
    async.flushMicrotasks();
  }

  void hide(FakeAsync async) {
    lifecycle(async, AppLifecycleState.inactive);
    lifecycle(async, AppLifecycleState.hidden);
  }

  /// 從背景化的 `hidden` 再到 `paused`（手機切到背景）。
  void pause(FakeAsync async) => lifecycle(async, AppLifecycleState.paused);

  void show(FakeAsync async) {
    // 合法的轉換順序：paused → hidden → inactive → resumed。
    final current = container.read(appLifecycleProvider);
    if (current == AppLifecycleState.paused) {
      lifecycle(async, AppLifecycleState.hidden);
    }
    if (current == AppLifecycleState.paused ||
        current == AppLifecycleState.hidden) {
      lifecycle(async, AppLifecycleState.inactive);
    }
    lifecycle(async, AppLifecycleState.resumed);
  }

  void network(FakeAsync async, {required bool available}) {
    interfaces.change(available: available);
    async.flushMicrotasks();
  }

  void dispose() => container.dispose();
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // 測試 binding 是行程共用的：每個測試結束回到前景。
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
  });

  test('does not run while hidden or paused, nor while offline', () {
    _fake((async) {
      final env = _Env();
      final probe = _Probe('a');
      env.start(async);
      env.hide(async);
      env.scheduler.register(probe.job);
      async.elapse(const Duration(hours: 1));
      expect(probe.starts, isEmpty, reason: 'hidden');

      env.pause(async);
      async.elapse(const Duration(hours: 1));
      expect(probe.starts, isEmpty, reason: 'paused');

      env.show(async);
      expect(probe.starts, hasLength(1), reason: 'visible, never run before');

      env.network(async, available: false);
      async.elapse(const Duration(hours: 1));
      expect(probe.starts, hasLength(1), reason: 'offline');
      env.dispose();
    });
  });

  test('becoming visible and online back to back runs a due job once', () {
    _fake((async) {
      final env = _Env();
      final probe = _Probe('a', interval: const Duration(minutes: 5));
      env.start(async);
      env.scheduler.register(probe.job);
      async.flushMicrotasks();
      env
        ..hide(async)
        ..network(async, available: false);
      async.elapse(const Duration(minutes: 30));

      // 生命週期與網路在同一段同步程式碼裡改變，中間不跑微任務。
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        env.binding.handleAppLifecycleStateChanged(state);
      }
      env.interfaces.change(available: true);
      async.flushMicrotasks();

      expect(probe.starts, hasLength(2));
      expect(async.pendingTimers, hasLength(1));
      env.dispose();
    });
  });

  test('waits for the first interface check before running anything', () {
    _fake((async) {
      final env = _Env(online: false, slowFirstCheck: true);
      final probe = _Probe('a');
      env.start(async);
      env.scheduler.register(probe.job);
      async.elapse(const Duration(minutes: 1));
      // 網路狀態的預設是 online，但還沒查過介面：不跑。
      expect(env.container.read(networkStatusProvider), NetworkStatus.online);
      expect(probe.starts, isEmpty);

      env.slow!.firstCheck.complete();
      async.flushMicrotasks();
      expect(probe.starts, isEmpty, reason: 'offline after the check');

      env.network(async, available: true);
      expect(probe.starts, hasLength(1));
      env.dispose();
    });
  });

  test('inactive counts as visible', () {
    _fake((async) {
      final env = _Env();
      final probe = _Probe('a');
      env.start(async);
      env.lifecycle(async, AppLifecycleState.inactive);
      env.scheduler.register(probe.job);
      async.flushMicrotasks();

      expect(probe.starts, hasLength(1));
      env.dispose();
    });
  });

  test('when it becomes possible again, every due job runs once and the '
      'others wait', () {
    _fake((async) {
      final env = _Env();
      final due1 = _Probe('due1', interval: const Duration(minutes: 5));
      final due2 = _Probe('due2', interval: const Duration(minutes: 5));
      final late = _Probe('late', interval: const Duration(minutes: 60));
      env.start(async);
      env.scheduler
        ..register(due1.job)
        ..register(due2.job)
        ..register(late.job);
      async.flushMicrotasks();
      expect([due1, due2, late].map((p) => p.starts.length), [1, 1, 1]);

      env.hide(async);
      async.elapse(const Duration(minutes: 30));
      expect([due1, due2, late].map((p) => p.starts.length), [1, 1, 1]);

      env.show(async);

      // 5 分鐘的兩個到期了，各補跑一次（不是 6 次）；60 分鐘的沒到期。
      expect([due1, due2, late].map((p) => p.starts.length), [2, 2, 1]);
      env.dispose();
    });
  });

  test('never holds more than one timer, and none when it cannot run', () {
    _fake((async) {
      final env = _Env();
      env.start(async);
      env.scheduler
        ..register(_Probe('a', interval: const Duration(minutes: 5)).job)
        ..register(_Probe('b', interval: const Duration(minutes: 7)).job)
        ..register(_Probe('c', interval: const Duration(minutes: 9)).job);
      async.flushMicrotasks();
      expect(async.pendingTimers, hasLength(1));

      env.scheduler.register(
        _Probe('d', interval: const Duration(minutes: 1)).job,
      );
      async.flushMicrotasks();
      expect(async.pendingTimers, hasLength(1));

      for (var i = 0; i < 20; i++) {
        async.elapse(const Duration(minutes: 1));
        expect(async.pendingTimers.length, lessThanOrEqualTo(1));
      }

      env.hide(async);
      expect(async.pendingTimers, isEmpty, reason: 'hidden');
      env.show(async);
      expect(async.pendingTimers, hasLength(1));
      env.network(async, available: false);
      expect(async.pendingTimers, isEmpty, reason: 'offline');
      env.dispose();
      expect(async.pendingTimers, isEmpty, reason: 'disposed');
    });
  });

  test('a job runs again after its interval, not before', () {
    _fake((async) {
      final env = _Env();
      final probe = _Probe('a', interval: const Duration(minutes: 10));
      env.start(async);
      env.scheduler.register(probe.job);
      async.flushMicrotasks();
      expect(probe.starts, hasLength(1));

      async.elapse(const Duration(minutes: 9, seconds: 59));
      expect(probe.starts, hasLength(1));
      async.elapse(const Duration(seconds: 1));
      expect(probe.starts, hasLength(2));
      env.dispose();
    });
  });

  group('runNow', () {
    test('ignores the interval, even when hidden', () {
      _fake((async) {
        final env = _Env();
        final probe = _Probe('a', interval: const Duration(hours: 24));
        env.start(async);
        env.scheduler.register(probe.job);
        async.flushMicrotasks();
        expect(probe.starts, hasLength(1));
        env.hide(async);

        RunNowResult? result;
        env.scheduler.runNow('a').then((value) => result = value);
        async.flushMicrotasks();

        expect(result, RunNowResult.completed);
        expect(probe.starts, hasLength(2));
        env.dispose();
      });
    });

    test('runs a job whose interval is off, and only then', () {
      _fake((async) {
        final env = _Env();
        final probe = _Probe('a', interval: null);
        env.start(async);
        env.scheduler.register(probe.job);
        async.elapse(const Duration(days: 2));
        expect(probe.starts, isEmpty);

        env.scheduler.runNow('a');
        async.flushMicrotasks();
        expect(probe.starts, hasLength(1));
        async.elapse(const Duration(days: 2));
        expect(probe.starts, hasLength(1));
        env.dispose();
      });
    });

    test('does not call the job when offline and says so', () {
      _fake((async) {
        final env = _Env();
        final probe = _Probe('a', interval: const Duration(hours: 24));
        env.start(async);
        env.scheduler.register(probe.job);
        async.flushMicrotasks();
        env.network(async, available: false);

        RunNowResult? result;
        env.scheduler.runNow('a').then((value) => result = value);
        async.flushMicrotasks();

        expect(result, RunNowResult.offline);
        expect(probe.starts, hasLength(1), reason: 'only the first run');
        env.dispose();
      });
    });

    test('reports an unknown job and a job that is already running', () {
      _fake((async) {
        final env = _Env();
        final probe = _Probe('a')..gate = Completer<void>();
        env.start(async);
        env.scheduler.register(probe.job);
        async.flushMicrotasks();
        expect(probe.running, 1);

        final results = <RunNowResult>[];
        env.scheduler
          ..runNow('nope').then(results.add)
          ..runNow('a').then(results.add);
        async.flushMicrotasks();

        expect(results, [RunNowResult.unknown, RunNowResult.alreadyRunning]);
        expect(probe.starts, hasLength(1), reason: 'no second run');
        probe.gate!.complete();
        async.flushMicrotasks();
        env.dispose();
      });
    });

    test('a failure backs the job off and reaches the caller, not the log', () {
      _fake((async) {
        final env = _Env();
        final probe = _Probe('a', interval: null)..failWith = StateError('x');
        env.start(async);
        env.scheduler.register(probe.job);

        Object? caught;
        env.scheduler.runNow('a').catchError((Object e) {
          caught = e;
          return RunNowResult.completed;
        });
        async.flushMicrotasks();

        expect(caught, isA<StateError>());
        expect(
          env.log.history.where((r) => r.message == 'Background job failed'),
          isEmpty,
        );
        env.dispose();
      });
    });
  });

  group('removal', () {
    test('an unregistered job stops running and its running pass is stale', () {
      _fake((async) {
        final env = _Env();
        final probe = _Probe(
          'a',
          pluginId: 'p',
          interval: const Duration(minutes: 5),
        )..gate = Completer<void>();
        env.start(async);
        env.scheduler.register(probe.job);
        async.flushMicrotasks();
        expect(probe.contexts.single.isCurrent, isTrue);

        env.scheduler.unregisterPlugin('p');
        expect(probe.contexts.single.isCurrent, isFalse);
        probe.gate!.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(hours: 1));

        expect(probe.starts, hasLength(1), reason: 'never runs again');
        expect(
          await_(
            env.database.select(env.database.schedulerRunsTable).get(),
            async,
          ),
          isEmpty,
          reason: 'a stale pass records no success',
        );
        env.dispose();
      });
    });

    test('unregister by id and replacing both make the old pass stale', () {
      _fake((async) {
        final env = _Env();
        final first = _Probe('a')..gate = Completer<void>();
        final second = _Probe('a');
        env.start(async);
        env.scheduler.register(first.job);
        async.flushMicrotasks();

        env.scheduler.register(second.job);
        expect(first.contexts.single.isCurrent, isFalse);
        first.gate!.complete();
        async.flushMicrotasks();
        expect(second.starts, hasLength(1), reason: 'the replacement runs');
        expect(second.contexts.single.isCurrent, isTrue);

        env.scheduler.unregister('a');
        expect(second.contexts.single.isCurrent, isFalse);
        async.elapse(const Duration(hours: 1));
        expect(second.starts, hasLength(1));
        expect(async.pendingTimers, isEmpty);
        env.dispose();
      });
    });

    test('unregistering what is not there does nothing', () {
      _fake((async) {
        final env = _Env();
        env.start(async);
        env.scheduler
          ..unregister('nope')
          ..unregisterPlugin('nope');
        env.dispose();
      });
    });
  });

  group('failures', () {
    test('back off 1, 2, 4 minutes, capped at the interval, and reset on '
        'success', () {
      _fake((async) {
        final env = _Env();
        final probe = _Probe('a', interval: const Duration(minutes: 5))
          ..failWith = StateError('down');
        env.start(async);
        env.scheduler.register(probe.job);
        async.flushMicrotasks();
        final first = probe.starts.single;

        // 1、2、4、再來 8 超過間隔，所以是 5。
        for (final minutes in [1, 2, 4, 5, 5]) {
          final before = probe.starts.length;
          async.elapse(Duration(minutes: minutes) - const Duration(seconds: 1));
          expect(probe.starts, hasLength(before), reason: 'before $minutes');
          async.elapse(const Duration(seconds: 1));
          expect(probe.starts, hasLength(before + 1), reason: 'at $minutes');
        }
        expect(
          probe.starts.last.difference(first),
          const Duration(minutes: 1 + 2 + 4 + 5 + 5),
        );

        // 成功後歸零：下次是成功時間加間隔。
        probe.failWith = null;
        async.elapse(const Duration(minutes: 5));
        final successAt = probe.starts.last;
        probe.failWith = StateError('down again');
        async.elapse(const Duration(minutes: 5));
        expect(
          probe.starts.last.difference(successAt),
          const Duration(minutes: 5),
        );
        // 再失敗一次又從 1 分鐘開始。
        async.elapse(const Duration(minutes: 1));
        expect(
          probe.starts.last.difference(successAt),
          const Duration(minutes: 6),
        );
        env.dispose();
      });
    });

    test('retryAfter wins over the backoff', () {
      _fake((async) {
        final env = _Env();
        final probe = _Probe('a', interval: const Duration(minutes: 60))
          ..failWith = RateLimited(retryAfter: const Duration(minutes: 17));
        env.start(async);
        env.scheduler.register(probe.job);
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 17) - const Duration(seconds: 1));
        expect(probe.starts, hasLength(1));
        async.elapse(const Duration(seconds: 1));
        expect(probe.starts, hasLength(2));
        env.dispose();
      });
    });

    test('reach the error history through report, with the job on the '
        'next line', () {
      _fake((async) {
        final env = _Env();
        final bug = _Probe('a', pluginId: 'p')..failWith = StateError('x');
        final limited = _Probe('b', pluginId: 'q')
          ..failWith = RateLimited(
            pluginId: 'q',
            retryAfter: const Duration(minutes: 3),
          );
        env.start(async);
        env.scheduler
          ..register(bug.job)
          ..register(limited.job);
        async.flushMicrotasks();

        final failed = {
          for (final r in env.log.history)
            if (r.message == 'Background job failed') r.fields['pluginId']: r,
        };
        // `report` 的欄位（型別、音源）讓 Debug 頁能開詳細頁；層級照 AppError.expected。
        expect(failed['p']!.tag, schedulerLogTag);
        expect(failed['p']!.level, LogLevel.error);
        expect(failed['p']!.fields, containsPair('type', 'UnexpectedError'));
        expect(failed['q']!.level, LogLevel.warning);
        expect(failed['q']!.fields, containsPair('type', 'RateLimited'));
        expect(failed['q']!.fields, containsPair('retryAfterMs', 180000));

        final backedOff = [
          for (final r in env.log.history)
            if (r.message == 'Background job backed off') r.fields,
        ];
        expect(backedOff, [
          {'jobId': 'a', 'pluginId': 'p', 'failures': 1, 'retryInMs': 60000},
          {'jobId': 'b', 'pluginId': 'q', 'failures': 1, 'retryInMs': 180000},
        ]);
        env.dispose();
      });
    });

    test('a failed manual run before the job is due does not bring the next '
        'automatic run forward', () {
      _fake((async) {
        final env = _Env();
        final probe = _Probe('a', interval: const Duration(minutes: 30));
        env.start(async);
        env.scheduler.register(probe.job);
        async.flushMicrotasks();
        final successAt = probe.starts.single;

        async.elapse(const Duration(minutes: 10));
        probe.failWith = StateError('down');
        env.scheduler.runNow('a').ignore();
        async.flushMicrotasks();
        expect(probe.starts, hasLength(2));
        probe.failWith = null;

        // 退避是 1 分鐘，但上次成功還沒過期：照常在成功後 30 分鐘才跑。
        async.elapse(const Duration(minutes: 19, seconds: 59));
        expect(probe.starts, hasLength(2));
        async.elapse(const Duration(seconds: 1));
        expect(probe.starts, hasLength(3));
        expect(
          probe.starts.last.difference(successAt),
          const Duration(minutes: 30),
        );
        env.dispose();
      });
    });
  });

  group('last success', () {
    test('is stored and survives a restart', () {
      _fake((async) {
        final database = memoryDatabase();
        final first = _Env(database: database);
        final probe = _Probe('a', interval: const Duration(minutes: 60));
        first.start(async);
        first.scheduler.register(probe.job);
        async.flushMicrotasks();
        expect(probe.starts, hasLength(1));
        final successAt = probe.starts.single;
        expect(await_(SchedulerRunsRepository(database).all(), async), {
          'a': successAt.toUtc(),
        });
        first.dispose();

        // 20 分鐘後重啟：新的排程器讀同一個資料庫，還沒到期，不會馬上跑。
        async.elapse(const Duration(minutes: 20));
        final second = _Env(database: database);
        final again = _Probe('a', interval: const Duration(minutes: 60));
        second.start(async);
        second.scheduler.register(again.job);
        async.flushMicrotasks();
        expect(again.starts, isEmpty);

        async.elapse(const Duration(minutes: 40));
        expect(again.starts, hasLength(1));
        expect(
          again.starts.single.difference(successAt),
          const Duration(minutes: 60),
        );
        second.dispose();
      });
    });

    test('a failed run records nothing', () {
      _fake((async) {
        final database = memoryDatabase();
        final env = _Env(database: database);
        final probe = _Probe('a')..failWith = StateError('x');
        env.start(async);
        env.scheduler.register(probe.job);
        async.flushMicrotasks();

        expect(await_(SchedulerRunsRepository(database).all(), async), isEmpty);
        env.dispose();
      });
    });
  });

  group('concurrency', () {
    test('runs jobs of one plugin one after another', () {
      _fake((async) {
        final env = _Env();
        final a = _Probe('a', pluginId: 'p')..gate = Completer<void>();
        final b = _Probe('b', pluginId: 'p');
        env.start(async);
        env.scheduler
          ..register(a.job)
          ..register(b.job);
        async.flushMicrotasks();
        expect(a.starts, hasLength(1));
        expect(b.starts, isEmpty, reason: 'waits for the same plugin');

        a.gate!.complete();
        async.flushMicrotasks();
        expect(b.starts, hasLength(1));
        env.dispose();
      });
    });

    test('runs at most $maxConcurrentJobs jobs at once', () {
      _fake((async) {
        final env = _Env();
        final gate = Completer<void>();
        final probes = [
          for (var i = 0; i < 5; i++)
            _Probe('j$i', pluginId: 'p$i')..gate = gate,
        ];
        env.start(async);
        for (final probe in probes) {
          env.scheduler.register(probe.job);
        }
        async.flushMicrotasks();
        expect(
          probes.fold<int>(0, (sum, probe) => sum + probe.running),
          maxConcurrentJobs,
        );

        gate.complete();
        async.flushMicrotasks();
        expect(probes.every((probe) => probe.starts.length == 1), isTrue);
        expect(
          probes
              .map((probe) => probe.maxRunning)
              .reduce((a, b) => a > b ? a : b),
          1,
        );
        env.dispose();
      });
    });

    test('a manual run that waits for a slot ends without running when the '
        'job is removed, the network drops or the scheduler is disposed', () {
      _fake((async) {
        final env = _Env();
        final gate = Completer<void>();
        final a = _Probe('a', pluginId: 'p1')..gate = gate;
        final b = _Probe('b', pluginId: 'p2')..gate = gate;
        final removed = _Probe('removed', interval: null);
        final offline = _Probe('offline', interval: null);
        env.start(async);
        env.scheduler
          ..register(a.job)
          ..register(b.job)
          ..register(removed.job)
          ..register(offline.job);
        async.flushMicrotasks();

        final results = <String, RunNowResult>{};
        for (final id in ['removed', 'offline']) {
          env.scheduler.runNow(id).then((value) => results[id] = value);
        }
        async.flushMicrotasks();
        expect(results, isEmpty, reason: 'both wait for a slot');

        env.scheduler.unregister('removed');
        async.flushMicrotasks();
        expect(results, {'removed': RunNowResult.unknown});

        env.network(async, available: false);
        expect(results['offline'], RunNowResult.offline);
        expect([removed, offline].map((p) => p.starts), everyElement(isEmpty));

        // 釋放時還在等的手動刷新也結束，不會永遠等著。
        env.network(async, available: true);
        final last = _Probe('last', interval: null);
        env.scheduler.register(last.job);
        RunNowResult? lastResult;
        env.scheduler.runNow('last').then((value) => lastResult = value);
        async.flushMicrotasks();
        expect(lastResult, isNull);
        env.dispose();
        async.flushMicrotasks();
        expect(lastResult, RunNowResult.unknown);
        expect(last.starts, isEmpty);
        gate.complete();
        async.flushMicrotasks();
      });
    });

    test('a removed job that is still running keeps its plugin busy until it '
        'ends, then the next job of that plugin runs', () {
      _fake((async) {
        final env = _Env();
        final old = _Probe('old', pluginId: 'p')..gate = Completer<void>();
        final next = _Probe('next', pluginId: 'p');
        env.start(async);
        env.scheduler.register(old.job);
        async.flushMicrotasks();

        env.scheduler
          ..unregisterPlugin('p')
          ..register(next.job);
        async.flushMicrotasks();
        expect(next.starts, isEmpty, reason: 'same plugin, still running');

        old.gate!.complete();
        async.flushMicrotasks();
        expect(next.starts, hasLength(1));
        expect(old.starts, hasLength(1));
        env.dispose();
      });
    });

    test('a manual run waits for a free slot', () {
      _fake((async) {
        final env = _Env();
        final gate = Completer<void>();
        final a = _Probe('a', pluginId: 'p1')..gate = gate;
        final b = _Probe('b', pluginId: 'p2')..gate = gate;
        final manual = _Probe('m', pluginId: 'p3', interval: null);
        env.start(async);
        env.scheduler
          ..register(a.job)
          ..register(b.job)
          ..register(manual.job);
        async.flushMicrotasks();

        RunNowResult? result;
        env.scheduler.runNow('m').then((value) => result = value);
        async.flushMicrotasks();
        expect(manual.starts, isEmpty);
        expect(result, isNull);

        gate.complete();
        async.flushMicrotasks();
        expect(manual.starts, hasLength(1));
        expect(result, RunNowResult.completed);
        env.dispose();
      });
    });
  });
}

/// 固定起點的 fakeAsync：時間是整毫秒，和資料庫存的精度一致。
void _fake(void Function(FakeAsync async) body) =>
    fakeAsync(body, initialTime: DateTime.utc(2026, 10, 14, 12));

/// fakeAsync 裡等一個 future 完成並取值（資料庫是記憶體內的，微任務就夠）。
T await_<T>(Future<T> future, FakeAsync async) {
  late T value;
  var done = false;
  future.then((v) {
    value = v;
    done = true;
  });
  async.flushMicrotasks();
  expect(done, isTrue, reason: 'the future did not complete');
  return value;
}
