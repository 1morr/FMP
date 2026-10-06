import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';

/// 重啟恢復時要的兩個「播放」設定值：「記住播放位置」與「重啟恢復時倒退秒數」。
typedef RestartSettings = ({bool rememberPosition, Duration rewind});

/// 佇列與播放狀態的持久化（ADR 0018 §決定 10、design §7.7）：跟著
/// [PlaybackController] 的佇列、狀態與音量，把變動轉成 [QueueRepository] 的差量
/// 寫入；啟動時把上次的狀態交給控制器（[PlaybackController.restore]）。
///
/// 存檔時機：佇列操作當下；播放中每 [checkpointInterval]（一次性的週期計時器，
/// 只在 [Playing] 時開，ADR 0018 §決定 11 允許的播放模組）；暫停、seek、App 進入
/// `hidden`／`paused`；音量與靜音改變。臨時播放不持久化：它期間資料庫停在進入時的
/// 佇列那一首與快照位置，位置存檔不覆寫。
///
/// 寫入一個接一個、同時只有一個在跑，連續的觸發合併成一次：每次寫的是當下想要的
/// 狀態與資料庫已有的狀態之差（前綴與後綴相同的列不動，其後的列平移）。沒有恢復
/// 完成前不寫，免得空佇列蓋掉上次的資料。
final class QueueStore {
  QueueStore({required this._repository, required this._log});

  /// 播放中多久存一次位置。
  static const checkpointInterval = Duration(seconds: 10);

  static const _tag = 'queue-store';

  final QueueRepository _repository;
  final Log _log;

  PlaybackController? _controller;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _timer;
  bool _disposed = false;

  // 想要存成什麼樣子。
  QueueState _queue = QueueState.empty;
  List<String> _queueKeys = const [];
  int _positionMs = 0;

  /// 恢復後、恢復的那一首還沒真的播出來：存的位置是使用者真正的位置，控制器那邊的是
  /// 倒退過的起點，不能存回去（否則下次重啟再倒退一次）。到 [Playing]（佇列自己的
  /// 那一首）、目前這首換了時結束。
  bool _holdingRestored = false;
  double _volume = 1;
  bool _muted = false;

  // 資料庫已有的樣子（寫入成功之後才更新）。
  List<String> _storedKeys = const [];
  List<int?> _storedRanks = const [];
  PlayerState? _storedPlayer;

  bool _dirty = false;
  Future<void>? _draining;

  /// 啟動時重啟恢復的位置：「記住播放位置」開著時從存的位置倒退 [rewind]（不低於
  /// 0），關著時從頭。
  static Duration restoredPosition(
    Duration stored, {
    required bool rememberPosition,
    required Duration rewind,
  }) {
    if (!rememberPosition) return Duration.zero;
    final position = stored - rewind;
    return position.isNegative ? Duration.zero : position;
  }

  /// 讀回上次的狀態交給 [controller]，然後開始跟著它存。讀不回來（資料壞了）時
  /// 記 error、清掉存的資料、從空的開始。[lifecycle] 是 App 的生命週期，
  /// [restartSettings] 在恢復時讀一次。
  Future<void> attach(
    PlaybackController controller, {
    required Stream<AppLifecycleState> lifecycle,
    required Future<RestartSettings> Function() restartSettings,
  }) async {
    StoredQueue stored = StoredQueue.empty;
    PlayerState? player;
    try {
      stored = await _repository.readQueue();
      player = await _repository.readPlayerState();
    } on Object catch (error, stackTrace) {
      _log.report(
        'Stored playback could not be read; starting empty',
        AppError.wrap(error, stackTrace),
        tag: _tag,
      );
      stored = StoredQueue.empty;
      player = null;
      try {
        await _repository.reset();
      } on Object catch (error, stackTrace) {
        _log.report(
          'Stored playback could not be cleared',
          AppError.wrap(error, stackTrace),
          tag: _tag,
        );
      }
    }
    if (_disposed) return;

    _storedKeys = [for (final track in stored.entries) '${track.key}'];
    _storedRanks = stored.shuffleRanks;
    _storedPlayer = player;
    _positionMs = player?.position.inMilliseconds ?? 0;

    final hadStored = player != null || stored.entries.isNotEmpty;
    var restored = false;
    if (hadStored) {
      final settings = await _readSettings(restartSettings);
      if (_disposed) return;
      final shuffle = player?.shuffleEnabled ?? false;
      restored = controller.restore(
        tracks: stored.entries,
        currentIndex: player?.currentPosition,
        loopMode: player?.loopMode ?? LoopMode.off,
        shuffle: shuffle,
        shuffleOrder: shuffle ? _orderOf(stored.shuffleRanks) : null,
        position: restoredPosition(
          player?.position ?? Duration.zero,
          rememberPosition: settings.rememberPosition,
          rewind: settings.rewind,
        ),
        volume: player?.volume ?? 1,
        muted: player?.muted ?? false,
      );
    }
    // 沒恢復（恢復前使用者已經動了佇列）時，存的位置屬於上次的那一首。
    if (!restored) _positionMs = 0;
    _holdingRestored = restored && controller.queue.current != null;

    _controller = controller;
    _queue = controller.queue;
    _queueKeys = _keysOf(_queue);
    _volume = controller.volume;
    _muted = controller.muted;
    _subscriptions.addAll([
      controller.queueStates.listen(_onQueue),
      controller.states.listen(_onState),
      controller.seeks.listen(_onSeek),
      controller.volumeChanges.listen(_onVolume),
      lifecycle.listen(_onLifecycle),
    ]);
    // 沒恢復成功（恢復前使用者已經動了佇列）或控制器改了資料庫沒有的東西（排列
    // 重新產生）時，補寫一次讓兩邊一致；什麼都沒存、什麼都沒動就不寫。
    if (hadStored || _queue.entries.isNotEmpty) {
      _schedule();
    }
  }

  /// 等排隊中的寫入都寫完（測試與關閉前用）。
  Future<void> flush() async {
    while (_draining != null) {
      await _draining;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  Future<RestartSettings> _readSettings(
    Future<RestartSettings> Function() read,
  ) async {
    try {
      return await read();
    } on Object catch (error, stackTrace) {
      _log.warning(
        'Failed to read the restart settings; using the defaults',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
      return (rememberPosition: true, rewind: Duration.zero);
    }
  }

  // ---- 觸發 -----------------------------------------------------------------

  void _onQueue(QueueState next) {
    final previous = _queue;
    _queue = next;
    _queueKeys = _keysOf(next);
    final same = _sameCurrent(previous, next);
    if (!same) _holdingRestored = false;
    if (next.temporary case final temporary?) {
      // 臨時播放：資料庫停在佇列那一首與快照位置；快照是倒退過的起點時（還在等
      // 恢復的那一首）維持存的位置。
      if (!_holdingRestored) {
        _positionMs = temporary.snapshot.position.inMilliseconds;
      }
    } else if (!same) {
      // 目前這首換了：從頭，之後的存檔再更新。拖曳只搬動位置、不換目前這首，
      // 所以比的是佇列項目本身，不是位置或曲目鍵（同一首可以出現兩次）。
      _positionMs = 0;
    }
    _schedule();
  }

  void _onState(PlaybackState state) {
    switch (state) {
      case Playing():
        if (_queue.temporary == null) _holdingRestored = false;
        _timer ??= Timer.periodic(checkpointInterval, (_) => _checkpoint());
      case Paused():
        _stopTimer();
        _checkpoint();
      case Idle():
        // 放掉來源（佇列播完、清空、停止）：下次從這首的開頭。
        _stopTimer();
        if (_queue.temporary == null && !_holdingRestored) {
          _positionMs = 0;
          _schedule();
        }
      case Loading() || Buffering() || Retrying() || Failed():
        _stopTimer();
    }
  }

  void _onSeek(Duration position) {
    if (_queue.temporary != null) return;
    _positionMs = position.inMilliseconds;
    _schedule();
  }

  void _onVolume(({double volume, bool muted}) change) {
    _volume = change.volume;
    _muted = change.muted;
    _schedule();
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _checkpoint();
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 把控制器現在的位置記成想要的位置。沒有來源可問（`Idle`、`Failed`）、在臨時
  /// 播放時、或恢復的那一首還沒播出來（[_holdingRestored]）時不動：重啟恢復後還沒按播放時控制器的位置是倒退過的，存回去會越退
  /// 越多。
  void _checkpoint() {
    final controller = _controller;
    if (controller == null || _queue.temporary != null || _holdingRestored) {
      return;
    }
    switch (controller.state) {
      case Idle() || Failed():
        return;
      case Loading() || Playing() || Paused() || Buffering() || Retrying():
        _positionMs = controller.position.inMilliseconds;
        _schedule();
    }
  }

  // ---- 寫入 -----------------------------------------------------------------

  void _schedule() {
    if (_disposed) return;
    _dirty = true;
    _draining ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_dirty && !_disposed) {
        _dirty = false;
        try {
          await _writeOnce();
        } on Object catch (error, stackTrace) {
          // 下一次觸發會以資料庫實際的樣子重算差量，不在這裡重試。
          _log.report(
            'Failed to save the queue',
            AppError.wrap(error, stackTrace),
            tag: _tag,
          );
        }
      }
    } finally {
      _draining = null;
    }
  }

  Future<void> _writeOnce() async {
    final queue = _queue;
    final keys = _queueKeys;
    final ranks = _ranksOf(queue);
    final player = PlayerState(
      currentPosition: queue.currentIndex,
      position: Duration(milliseconds: _positionMs),
      loopMode: queue.loopMode,
      shuffleEnabled: queue.shuffleEnabled,
      volume: _volume,
      muted: _muted,
    );

    final (:prefix, :suffix) = commonEnds(_storedKeys, keys);
    final removed = _storedKeys.length - prefix - suffix;
    final inserted = keys.length - prefix - suffix;
    final edit = removed == 0 && inserted == 0
        ? null
        : QueueRangeEdit(
            from: prefix,
            removed: removed,
            inserted: [
              for (final entry in queue.entries.sublist(
                prefix,
                keys.length - suffix,
              ))
                entry.track,
            ],
          );
    // 套用編輯之後資料庫裡的名次：後綴的列帶著自己的名次，新列沒有。
    final projected = [
      ..._storedRanks.sublist(0, prefix),
      ...List<int?>.filled(inserted, null),
      ..._storedRanks.sublist(_storedRanks.length - suffix),
    ];
    final rankChanges = {
      for (var i = 0; i < ranks.length; i++)
        if (projected[i] != ranks[i]) i: ranks[i],
    };
    if (edit == null && rankChanges.isEmpty && player == _storedPlayer) return;

    await _repository.write(
      edit: edit,
      shuffleRanks: rankChanges,
      player: player,
    );
    _storedKeys = keys;
    _storedRanks = ranks;
    _storedPlayer = player;
  }

  // ---- 純函數 ---------------------------------------------------------------

  /// 兩份曲目鍵清單開頭、結尾各有幾個位置相同（兩段不重疊）：中間才需要寫。
  static ({int prefix, int suffix}) commonEnds(
    List<String> before,
    List<String> after,
  ) {
    var prefix = 0;
    while (prefix < before.length &&
        prefix < after.length &&
        before[prefix] == after[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < after.length - prefix &&
        before[before.length - 1 - suffix] ==
            after[after.length - 1 - suffix]) {
      suffix++;
    }
    return (prefix: prefix, suffix: suffix);
  }

  /// 兩份佇列的目前這首是不是同一個佇列項目（`QueueModel` 編輯時沿用項目的
  /// 實例，換一首或重新載入才是另一個）。
  static bool _sameCurrent(QueueState before, QueueState after) {
    final (from, to) = (before.currentIndex, after.currentIndex);
    if (from == null || to == null) return from == to;
    return identical(before.entries[from], after.entries[to]);
  }

  static List<String> _keysOf(QueueState queue) => [
    for (final entry in queue.entries) '${entry.track.key}',
  ];

  /// 隨機排列的每個位置的名次；沒開隨機時全是 `null`。
  static List<int?> _ranksOf(QueueState queue) {
    final ranks = List<int?>.filled(queue.entries.length, null);
    if (queue.shuffleOrder case final order?) {
      for (final (rank, position) in order.indexed) {
        ranks[position] = rank;
      }
    }
    return ranks;
  }

  /// 依名次排回位置的排列；有位置沒有名次（沒存完整）時為 `null`。
  static List<int>? _orderOf(List<int?> ranks) {
    if (ranks.any((rank) => rank == null)) return null;
    final order = List<int>.generate(ranks.length, (i) => i)
      ..sort((a, b) => ranks[a]!.compareTo(ranks[b]!));
    return order;
  }
}
