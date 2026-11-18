import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/temporary_play.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';

/// 佇列與它的動作。畫面只經這裡改佇列；要播哪首由佇列的目前那首決定，
/// 實際播放交給 [playbackProvider]。
final queueProvider = NotifierProvider<QueueController, Queue>(
  QueueController.new,
);

/// 打亂佇列用的亂數；測試換成固定種子的。
final queueRandomProvider = Provider<Random>((_) => Random());

/// 正在臨時播放的那首與離開佇列時的位置；不在臨時播放時是 null。只有
/// [QueueController] 改它，畫面只讀。
final temporaryPlayProvider =
    NotifierProvider<TemporaryPlayHolder, TemporaryPlay?>(
      TemporaryPlayHolder.new,
    );

/// [temporaryPlayProvider] 的持有者；只給 [QueueController] 用。
class TemporaryPlayHolder extends Notifier<TemporaryPlay?> {
  @override
  TemporaryPlay? build() => null;

  void set(TemporaryPlay? value) => state = value;
}

/// 臨時播放結束、回到佇列時倒退多少（brief〈播放〉，預設 10 秒）。設定頁的
/// 入口與保存在設定的票。
final temporaryPlayRewindProvider =
    NotifierProvider<TemporaryPlayRewind, Duration>(TemporaryPlayRewind.new);

class TemporaryPlayRewind extends Notifier<Duration> {
  @override
  Duration build() => const Duration(seconds: 10);

  void set(Duration value) => state = value;
}

/// 上一首、下一首鈕能不能按。臨時播放時兩個都是回到佇列，佇列有目前那首
/// （回得去）就能按。
final skipAvailableProvider = Provider<({bool previous, bool next})>((ref) {
  final queue = ref.watch(queueProvider);
  if (ref.watch(temporaryPlayProvider) != null) {
    final back = queue.current != null;
    return (previous: back, next: back);
  }
  return (previous: queue.hasPrevious, next: queue.hasNext);
});

/// 把佇列（[Queue]）接上播放：目前那首換了就播它，播完自動接下一首（單曲
/// 循環時重播同一首），清空或移除後沒有可播的就停止（brief〈播放〉）。
/// 開關隨機、換循環都不打斷正在播的那首。
///
/// 臨時播放（[temporaryPlayProvider]）時佇列的目前那首是要回去的地方：播完
/// 或按上一首、下一首就回到它，從離開的地方倒退
/// [temporaryPlayRewindProvider] 接著播。臨時播放時改佇列（加入、拖動、
/// 移除）都不打斷正在播的臨時曲目。
class QueueController extends Notifier<Queue> {
  @override
  Queue build() {
    ref.listen(playbackProvider, (previous, next) {
      if (next?.status == PlaybackStatus.completed &&
          previous?.status != PlaybackStatus.completed) {
        unawaited(_onCompleted());
      }
      // 臨時播放的那首播不了：提示（Toast）照常，然後照播完回到佇列。等這一輪
      // 通知送完再回去，其他聽眾才收得到這次失敗。重試與跳過是之後的票。
      if (next?.status == PlaybackStatus.failed &&
          previous?.status != PlaybackStatus.failed &&
          _temporary != null) {
        unawaited(Future.microtask(_endTemporary));
      }
    });
    return Queue.empty;
  }

  Playback get _playback => ref.read(playbackProvider.notifier);

  Random get _random => ref.read(queueRandomProvider);

  TemporaryPlay? get _temporary => ref.read(temporaryPlayProvider);

  set _temporary(TemporaryPlay? value) =>
      ref.read(temporaryPlayProvider.notifier).set(value);

  /// 開關隨機。
  void toggleShuffle() =>
      state = state.shuffled ? state.unshuffle() : state.shuffle(_random);

  /// 循環依序切到下一個：不循環 → 列表 → 單曲 → 不循環。
  void cycleRepeat() => state = state.withRepeat(state.repeat.cycled);

  /// 加入佇列：排在最後。沒有目前那首（佇列是空的，或移除了正在播的最後
  /// 一首）就開始播加入的第一首；有目前那首時（播放中、暫停、播完、重啟後
  /// 還原）不換、不自動播。
  Future<void> add(List<Track> tracks) => _insert((queue) => queue.add(tracks));

  /// 下一首播放：插在目前那首後面；沒有目前那首時排在最後並開始播。
  Future<void> playNext(List<Track> tracks) =>
      _insert((queue) => queue.playNext(tracks));

  /// 臨時播放 [track]：在佇列之外播它，佇列不動。已在臨時播放中時只換
  /// 曲目，回去的地方仍是最早離開的那個位置。
  Future<void> playTemporarily(Track track) {
    final playback = ref.read(playbackProvider);
    final leaving = state.current;
    // 正在播的就是佇列的目前那首時，才記下它播到哪裡；失敗、已播完、還沒
    // 播過的回來時從頭。
    final position =
        leaving != null &&
            playback != null &&
            playback.track == leaving.track &&
            playback.status != PlaybackStatus.failed &&
            playback.status != PlaybackStatus.completed
        ? playback.position
        : Duration.zero;
    _temporary = TemporaryPlay.start(
      track,
      previous: _temporary,
      leaving: leaving,
      position: position,
    );
    return _playback.play(track);
  }

  /// 結束臨時播放、回到佇列的目前那首，倒退後接著播。佇列沒有目前那首時
  /// 回不去，照舊臨時播放。
  Future<void> returnToQueue() async {
    final temporary = _temporary;
    final entry = state.current;
    if (temporary == null || entry == null) return;
    _temporary = null;
    await _playback.play(
      entry.track,
      from: temporary.resumeAt(entry, ref.read(temporaryPlayRewindProvider)),
    );
  }

  /// 佇列頁臨時播放卡片的「下一首播放」：把臨時播放的曲目插在目前那首後面
  /// 並成為目前那首，聲音不中斷；原本那首算播過。
  void queueTemporaryNext() {
    final temporary = _temporary;
    if (temporary == null) return;
    _temporary = null;
    final hadCurrent = state.current != null;
    final inserted = state.playNext([temporary.track]);
    state = hadCurrent ? inserted.jumpTo(inserted.currentIndex! + 1) : inserted;
  }

  /// 從 [index] 那首開始播；臨時播放就結束。
  Future<void> playAt(int index) {
    _temporary = null;
    state = state.jumpTo(index);
    return _playCurrent();
  }

  /// 下一首；沒有下一首時什麼都不做。臨時播放時是回到佇列。
  Future<void> next() async {
    if (_temporary != null) return returnToQueue();
    if (state.next(_random) case final queue?) {
      state = queue;
      await _playCurrent();
    }
  }

  /// 上一首；沒有上一首時什麼都不做。臨時播放時是回到佇列。
  Future<void> previous() async {
    if (_temporary != null) return returnToQueue();
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
  /// 一首（列表循環時沒有這回事）就停止。臨時播放時不動播放，回去的地方
  /// 變成換上來的目前那首。
  Future<void> remove(int index) async {
    final wasCurrent = index == state.currentIndex;
    state = state.remove(index, _random);
    if (!wasCurrent || _temporary != null) return;
    if (state.current != null) {
      await _playCurrent();
    } else {
      await _playback.stop();
    }
  }

  /// 清空佇列並停止播放，臨時播放也一起停。
  Future<void> clear() async {
    _temporary = null;
    state = state.clear();
    await _playback.stop();
  }

  /// 重啟後佇列與目前那首還在、不自動播（brief〈播放〉）時，加一首不能讓
  /// 佇列跳離原本那首，所以看有沒有目前那首，不看有沒有在播。臨時播放時
  /// 不打斷它，加入的成為回去的地方。
  Future<void> _insert(Queue Function(Queue) insert) async {
    final hadCurrent = state.current != null;
    state = insert(state);
    if (!hadCurrent && _temporary == null) await _playCurrent();
  }

  /// 臨時播放的那首播完或播不了：回到佇列；佇列沒有目前那首（回不去）就
  /// 結束臨時播放，停在那首，之後加入佇列照常開始播。
  Future<void> _endTemporary() async {
    if (state.current == null) {
      _temporary = null;
      return;
    }
    await returnToQueue();
  }

  /// 一首自然播完：臨時播放的回到佇列（單曲循環也一樣），單曲循環重播
  /// 它，否則接下一首。
  Future<void> _onCompleted() {
    if (_temporary != null) return _endTemporary();
    return state.repeat == Repeat.one ? _playCurrent() : next();
  }

  Future<void> _playCurrent() async {
    if (state.current case final entry?) await _playback.play(entry.track);
  }
}
