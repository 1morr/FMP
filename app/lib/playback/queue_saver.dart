import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/queue_store.dart';
import 'package:fmp/domain/queue.dart';

/// 上次關 App 時的佇列與進度，`main` 啟動時讀回再 override 進來；沒有就是
/// null。`queueProvider` 從它的佇列開始，`playbackProvider` 停在它的目前那首、
/// 不自動播（brief〈播放〉）。
final savedQueueProvider = Provider<SavedQueue?>((ref) => null);

/// 把佇列與進度寫進 [QueueStore]；沒有資料庫時是 null。由 `QueueController`
/// 呼叫。
final queueSaverProvider = Provider<QueueSaver?>((ref) {
  final store = ref.watch(queueStoreProvider);
  if (store == null) return null;
  return QueueSaver(store, ref.read(logProvider), ref.read(savedQueueProvider));
});

/// 決定什麼時候寫：佇列一變就寫；進度在呼叫的人說要馬上寫（換曲、暫停、
/// 狀態改變）時寫，播放中只在和上次寫的差到 [positionStep] 時寫，被硬關時
/// 最多少這麼多。寫入依序進行，失敗寫 log、不影響播放。
class QueueSaver {
  QueueSaver(this._store, this._log, SavedQueue? saved)
    : _savedQueue = saved?.queue,
      _savedPosition = saved?.position;

  final QueueStore _store;
  final Log _log;
  Queue? _savedQueue;
  Duration? _savedPosition;
  Future<void> _last = Future.value();

  static const positionStep = Duration(seconds: 5);

  /// 目前排著的寫入都做完。
  Future<void> get idle => _last;

  /// 佇列變了：存整個佇列與 [position]（null 是沿用上次存的）。位置的順序
  /// 沒變時只存目前那首、播放模式與進度。
  void queueChanged(Queue queue, Duration? position) {
    final previous = _savedQueue;
    final entriesChanged =
        previous == null ||
        !identical(previous.entries, queue.entries) ||
        !identical(previous.originalOrder, queue.originalOrder);
    final at = position ?? _savedPosition ?? Duration.zero;
    _savedQueue = queue;
    _savedPosition = at;
    _enqueue(() => _store.save(queue, at, entriesChanged: entriesChanged));
  }

  /// 目前那首播到 [position]。[now] 時一有不同就寫，否則差到
  /// [positionStep] 才寫。
  void positionChanged(Duration position, {required bool now}) {
    final last = _savedPosition;
    if (last == position) return;
    if (!now && last != null && (position - last).abs() < positionStep) {
      return;
    }
    _savedPosition = position;
    _enqueue(() => _store.savePosition(position));
  }

  void _enqueue(Future<void> Function() write) {
    _last = _last.then((_) => write()).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _log.error(
        'Saving the queue failed',
        error: error,
        stackTrace: stackTrace,
      );
    });
  }
}
