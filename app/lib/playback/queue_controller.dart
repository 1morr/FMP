import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';

/// 佇列與它的動作。畫面只經這裡改佇列；要播哪首由佇列的目前那首決定，
/// 實際播放交給 [playbackProvider]。
final queueProvider = NotifierProvider<QueueController, Queue>(
  QueueController.new,
);

/// 把佇列（[Queue]）接上播放：目前那首換了就播它，播完自動接下一首，
/// 清空或移除後沒有可播的就停止（brief〈播放〉）。不隨機、不循環。
class QueueController extends Notifier<Queue> {
  @override
  Queue build() {
    ref.listen(playbackProvider, (previous, next) {
      if (next?.status == PlaybackStatus.completed &&
          previous?.status != PlaybackStatus.completed) {
        unawaited(this.next());
      }
    });
    return Queue.empty;
  }

  Playback get _playback => ref.read(playbackProvider.notifier);

  /// 加入佇列：排在最後。沒在播時（佇列是空的，或移除最後一首後停了）
  /// 開始播加入的第一首。
  Future<void> add(List<Track> tracks) =>
      _insert(state.entries.length, (queue) => queue.add(tracks));

  /// 下一首播放：插在目前那首後面。沒在播時開始播插入的第一首。
  Future<void> playNext(List<Track> tracks) => _insert(
    state.currentIndex == null ? 0 : state.currentIndex! + 1,
    (queue) => queue.playNext(tracks),
  );

  /// 馬上播 [track]：插在目前那首後面並播它，原本接下來的照舊。
  Future<void> playNow(Track track) {
    final inserted = state.playNext([track]);
    state = state.isEmpty ? inserted : inserted.next()!;
    return _playCurrent();
  }

  /// 從 [index] 那首開始播。
  Future<void> playAt(int index) {
    state = state.jumpTo(index);
    return _playCurrent();
  }

  /// 下一首；沒有下一首時什麼都不做。
  Future<void> next() async {
    if (state.next() case final queue?) {
      state = queue;
      await _playCurrent();
    }
  }

  /// 上一首；沒有上一首時什麼都不做。
  Future<void> previous() async {
    if (state.previous() case final queue?) {
      state = queue;
      await _playCurrent();
    }
  }

  /// 拖動排序，不打斷播放。
  void move(int from, int to) => state = state.move(from, to);

  /// 把 [index] 那首移到目前那首後面，不打斷播放。
  void moveToNext(int index) => state = state.moveToNext(index);

  /// 移除 [index] 那首。移除的是正在播的那首時接著播下一首；它已是最後
  /// 一首就停止。
  Future<void> remove(int index) async {
    final wasCurrent = index == state.currentIndex;
    final hadNext = state.hasNext;
    state = state.remove(index);
    if (!wasCurrent) return;
    if (hadNext) {
      await _playCurrent();
    } else {
      await _playback.stop();
    }
  }

  /// 清空佇列並停止播放。
  Future<void> clear() async {
    state = state.clear();
    await _playback.stop();
  }

  /// [insert] 把曲目放在 [at] 起的位置；沒在播就從 [at] 開始播。
  Future<void> _insert(int at, Queue Function(Queue) insert) async {
    final before = state.entries.length;
    final idle = ref.read(playbackProvider) == null;
    state = insert(state);
    if (!idle || state.entries.length == before) return;
    state = state.jumpTo(at);
    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    if (state.current case final entry?) await _playback.play(entry.track);
  }
}
