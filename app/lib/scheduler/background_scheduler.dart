import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/app/app_lifecycle.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';

/// 排程器的 log tag。
const schedulerLogTag = 'scheduler';

/// 全域同時最多幾個工作（ADR 0017 §決定 4）。
const maxConcurrentJobs = 2;

/// 第一次失敗後的退避；之後每次加倍，上限是該工作的間隔。
const firstBackoff = Duration(minutes: 1);

/// 工作的執行函式。[context] 讓它在長時間的工作裡知道自己是不是已經被取消或取代。
typedef SchedulerJobRun = Future<void> Function(JobContext context);

/// 一個週期工作的宣告（ADR 0017 §決定 2）。
@immutable
final class SchedulerJob {
  const SchedulerJob({
    required this.id,
    required this.interval,
    required this.run,
    this.pluginId,
  });

  /// 工作的識別，也是 `scheduler_runs` 的鍵。以同一個 id 再登記就是取代。
  final String id;

  /// 所屬插件；同一個插件的工作依序執行，插件停用或移除時一併移除。
  final String? pluginId;

  /// 兩次成功之間的間隔；`null` 是關閉：不會自動跑，只能 [BackgroundScheduler.runNow]。
  final Duration? interval;

  final SchedulerJobRun run;
}

/// 傳給 [SchedulerJob.run] 的執行環境。
final class JobContext {
  JobContext._(this._isCurrent);

  final bool Function() _isCurrent;

  /// 這次執行還有效嗎：工作被移除、被取代，或排程器已釋放後為假。為假時工作應丟掉結果、
  /// 不寫入任何東西；排程器也不會替它記上次成功時間。
  bool get isCurrent => _isCurrent();
}

/// [BackgroundScheduler.runNow] 的結果。
enum RunNowResult {
  /// 工作跑完了。
  completed,

  /// 網路不在線，沒有發（含等空位的期間斷線）。
  offline,

  /// 沒有這個工作（含等空位的期間被移除，或排程器已釋放）。
  unknown,

  /// 這個工作已經在跑（或已在排隊）；不開第二個。
  alreadyRunning,
}

/// 背景排程器（ADR 0017）：會發網路請求的週期工作的唯一擁有者。
///
/// - **何時跑**：App 可見（`resumed`、`inactive`）而且網路 `online`。其他時候取消計時器，
///   進行中的工作跑完、不開新的。變可見或回到線上時，已到期的工作各跑一次；沒有上次
///   成功時間的工作視為已到期。
/// - **一個計時器**：一次性的 [Timer]，指向最早到期（含退避中）的工作；到期、狀態改變、
///   登記變動時重算。排程器本身不用週期計時器。
/// - **並行**：全域最多 [maxConcurrentJobs] 個，同一個 `pluginId` 依序。
/// - **失敗**：丟錯就經 `log.report` 進錯誤歷史並退避 1、2、4… 分鐘，上限為該工作的
///   間隔；錯誤帶 `retryAfter` 時以它為準。退避不會讓工作比「上次成功加間隔」更早跑。
///   成功後歸零。
/// - **上次成功時間**：寫 `scheduler_runs`，重啟後照算。
/// - **取消**：移除或取代的工作立即不再被排，進行中的那次由工作自己看
///   [JobContext.isCurrent]，排程器也不替它記成功。
final backgroundSchedulerProvider = NotifierProvider<BackgroundScheduler, void>(
  BackgroundScheduler.new,
);

final class BackgroundScheduler extends Notifier<void> {
  /// 目前登記的工作；物件本身就是「代際」：被取代或移除的 [_Entry] 不再是 current。
  final _entries = <String, _Entry>{};

  /// 每個工作 id 的上次成功時間：啟動時從資料庫讀，成功時更新。取代工作時沿用。
  final _lastSuccess = <String, DateTime>{};

  /// 正在跑的（含已被取代、還沒跑完的）。
  final _running = <_Entry>{};

  /// 等空位的手動刷新，依呼叫順序。
  final _waiters = <_Waiter>[];

  Timer? _timer;

  /// 第一次介面檢查與上次成功時間都讀完之前不開新工作。
  bool _loaded = false;

  @override
  void build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      // 還在等空位的手動刷新不會再拿到空位：讓它們以 unknown 結束，不要永遠等著。
      for (final waiter in _waiters) {
        waiter.entry.waiting = false;
        waiter
          ..outcome = RunNowResult.unknown
          ..granted.complete();
      }
      _waiters.clear();
    });
    ref.listen(appLifecycleProvider, (_, _) => _pump());
    ref.listen(networkStatusProvider, (_, _) => _pump());
    unawaited(_load());
  }

  Future<void> _load() async {
    // 網路狀態的預設是 online：等第一次介面檢查，離線啟動時才不會先發出去（ADR 0016）。
    await ref.read(networkStatusProvider.notifier).whenFirstChecked();
    if (!ref.mounted) return;
    try {
      final stored = await ref.read(schedulerRunsRepositoryProvider).all();
      if (!ref.mounted) return;
      // 讀的期間成功寫入的比較新，不被舊值蓋掉。
      for (final MapEntry(:key, :value) in stored.entries) {
        _lastSuccess.putIfAbsent(key, () => value);
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      // 讀不到就當作從沒成功過：多跑一次，比永遠不跑好。
      ref
          .read(logProvider)
          .report(
            'Failed to read the last success times of background jobs',
            AppError.wrap(error, stackTrace),
            tag: schedulerLogTag,
          );
    }
    _loaded = true;
    _pump();
  }

  /// 登記 [job]；已有同 id 的就取代（舊的進行中那次視為過期）。
  void register(SchedulerJob job) {
    _entries[job.id] = _Entry(job);
    _pump();
  }

  /// 移除 [id] 的工作。沒有這個工作時什麼都不做。
  void unregister(String id) {
    if (_entries.remove(id) != null) _pump();
  }

  /// 移除 [pluginId] 的所有工作（插件停用或移除）。沒有時什麼都不做。
  void unregisterPlugin(String pluginId) {
    final before = _entries.length;
    _entries.removeWhere((_, entry) => entry.job.pluginId == pluginId);
    if (_entries.length != before) _pump();
  }

  /// 立即執行 [id]，不看間隔也不看 App 是不是可見；離線時不發（[RunNowResult.offline]）。
  /// 一樣受並行限制：沒有空位時等到有。
  ///
  /// 工作丟錯時照常退避並重新丟出，由呼叫端決定要不要提示使用者（手動操作的錯誤
  /// 才顯示，ADR 0013 §決定 5）；排程器不替這種失敗記 log。
  Future<RunNowResult> runNow(String id) async {
    final entry = _entries[id];
    if (entry == null) return RunNowResult.unknown;
    if (entry.running || entry.waiting) return RunNowResult.alreadyRunning;
    if (ref.read(networkStatusProvider) != NetworkStatus.online) {
      return RunNowResult.offline;
    }
    final waiter = _Waiter(entry);
    entry.waiting = true;
    _waiters.add(waiter);
    _pump();
    await waiter.granted.future;
    if (waiter.outcome case final outcome?) return outcome;
    if (!_isCurrent(entry)) {
      // 拿到空位之後、開始之前被移除或取代：把空位還回去。
      _running.remove(entry);
      entry.running = false;
      _pump();
      return RunNowResult.unknown;
    }
    await _execute(entry, manual: true);
    return RunNowResult.completed;
  }

  bool _isCurrent(_Entry entry) =>
      ref.mounted && identical(_entries[entry.job.id], entry);

  bool get _mayStartScheduled {
    final lifecycle = ref.read(appLifecycleProvider);
    final visible =
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
    return visible && ref.read(networkStatusProvider) == NetworkStatus.online;
  }

  /// 有沒有空位給 [entry]：全域上限、同插件依序、同 id 不並行。
  bool _hasRoomFor(_Entry entry) {
    if (_running.length >= maxConcurrentJobs) return false;
    final pluginId = entry.job.pluginId;
    for (final running in _running) {
      if (running.job.id == entry.job.id) return false;
      if (pluginId != null && running.job.pluginId == pluginId) return false;
    }
    return true;
  }

  /// [entry] 下一次該跑的時間；不會自動跑（間隔關閉）是 `null`。
  DateTime? _dueAt(_Entry entry) {
    final interval = entry.job.interval;
    if (interval == null) return null;
    final last = _lastSuccess[entry.job.id];
    // 沒成功過：已到期（App 啟動視同變可見，先跑一次）。
    final regular = last == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : last.add(interval);
    // 退避只往後延：手動刷新在還沒到期時失敗，不會因此提早自動跑。
    return switch (entry.retryAt) {
      final retryAt? when retryAt.isAfter(regular) => retryAt,
      _ => regular,
    };
  }

  /// 唯一的排程點：開得了的就開，再把計時器對準最早到期的下一個。
  void _pump() {
    if (!ref.mounted) return;
    _timer?.cancel();
    _timer = null;
    if (!_loaded) return;

    // 手動刷新優先，不看可見與否；等空位的期間斷線就不發。
    final online = ref.read(networkStatusProvider) == NetworkStatus.online;
    for (final waiter in _waiters.toList()) {
      final entry = waiter.entry;
      final RunNowResult? outcome;
      if (!_isCurrent(entry)) {
        outcome = RunNowResult.unknown;
      } else if (!online) {
        outcome = RunNowResult.offline;
      } else if (_hasRoomFor(entry)) {
        outcome = null;
        entry.running = true;
        _running.add(entry);
      } else {
        continue;
      }
      _waiters.remove(waiter);
      entry.waiting = false;
      waiter
        ..outcome = outcome
        ..granted.complete();
    }

    if (!_mayStartScheduled) return;

    final now = clock.now();
    final due = <(_Entry, DateTime)>[];
    DateTime? nextDue;
    for (final entry in _entries.values) {
      if (entry.running || entry.waiting) continue;
      final at = _dueAt(entry);
      if (at == null) continue;
      if (at.isAfter(now)) {
        if (nextDue == null || at.isBefore(nextDue)) nextDue = at;
      } else {
        due.add((entry, at));
      }
    }
    due.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (entry, _) in due) {
      if (!_hasRoomFor(entry)) continue; // 有工作跑完時會再排一次。
      entry.running = true;
      _running.add(entry);
      unawaited(_execute(entry, manual: false));
    }

    if (nextDue != null) {
      _timer = Timer(nextDue.difference(now), _pump);
    }
  }

  Future<void> _execute(_Entry entry, {required bool manual}) async {
    Object? failure;
    StackTrace? failureTrace;
    try {
      await entry.job.run(JobContext._(() => _isCurrent(entry)));
    } on Object catch (error, stackTrace) {
      failure = error;
      failureTrace = stackTrace;
    }
    _running.remove(entry);
    entry.running = false;
    try {
      if (_isCurrent(entry)) {
        if (failure == null) {
          await _recordSuccess(entry);
        } else {
          _recordFailure(entry, failure, failureTrace!, manual: manual);
        }
      }
    } finally {
      _pump();
    }
    if (manual && failure != null) {
      Error.throwWithStackTrace(failure, failureTrace!);
    }
  }

  Future<void> _recordSuccess(_Entry entry) async {
    // 存的精度是毫秒：記憶體裡的也取毫秒，重啟前後算出同樣的到期時間。
    final at = DateTime.fromMillisecondsSinceEpoch(
      clock.now().millisecondsSinceEpoch,
      isUtc: true,
    );
    entry
      ..failures = 0
      ..retryAt = null;
    _lastSuccess[entry.job.id] = at;
    try {
      await ref.read(schedulerRunsRepositoryProvider).record(entry.job.id, at);
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      // 沒寫進去只影響重啟後的到期時間；記憶體裡的照用。
      ref
          .read(logProvider)
          .report(
            'Failed to record the last success time of a background job',
            AppError.wrap(error, stackTrace),
            tag: schedulerLogTag,
          );
    }
  }

  void _recordFailure(
    _Entry entry,
    Object error,
    StackTrace stackTrace, {
    required bool manual,
  }) {
    final job = entry.job;
    entry.failures++;
    final interval = job.interval;
    Duration? delay;
    // 間隔關閉的工作不會自動重試，不需要退避時間。
    if (interval != null) {
      final retryAfter = error is AppError ? error.retryAfter : null;
      final exponent = math.min(entry.failures - 1, 20);
      final backoff = firstBackoff * (1 << exponent);
      delay = retryAfter ?? (backoff > interval ? interval : backoff);
      entry.retryAt = clock.now().add(delay);
    }
    if (manual) return;
    // 錯誤歷史的那一筆走 `report`（型別、音源、原因與可否重試，ADR 0013 §決定 3）；
    // 哪個工作、第幾次、多久後重試另記一行，比照啟動維護清單。
    final log = ref.read(logProvider)
      ..report(
        'Background job failed',
        AppError.wrap(error, stackTrace, pluginId: job.pluginId),
        tag: schedulerLogTag,
      );
    log.info(
      'Background job backed off',
      tag: schedulerLogTag,
      fields: {
        'jobId': job.id,
        'pluginId': ?job.pluginId,
        'failures': entry.failures,
        'retryInMs': ?delay?.inMilliseconds,
      },
    );
  }
}

final class _Entry {
  _Entry(this.job);

  final SchedulerJob job;
  bool running = false;
  bool waiting = false;
  int failures = 0;
  DateTime? retryAt;
}

final class _Waiter {
  _Waiter(this.entry);

  final _Entry entry;
  final granted = Completer<void>();

  /// 不執行時的結果；`null` 是拿到空位、要執行。
  RunNowResult? outcome;
}
