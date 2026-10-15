import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/mix_identity.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/live_play.dart';

/// 佇列在播的是什麼（ADR 0018 §決定 4）。`detached` 不做（臨時播放涵蓋了它）。
enum QueueMode {
  /// 播佇列裡的歌。
  queue,

  /// 佇列是一個 Mix（ADR 0031 §決定 9）：隨機、加入、下一首播放被拒絕，已播超過
  /// [QueueModel.maxMixPlayed] 首時刪最舊的已播項目，清空佇列就退出。臨時播放與
  /// 直播進行中時 [QueueState.mode] 是那兩個，[QueueState.mix] 仍在。
  mix,

  /// 播一首不在佇列裡的歌，結束後回到佇列（D1）。
  temporary,

  /// 收聽一個直播間（ADR 0018 §決定 9）；結束後回到佇列。不持久化。
  live,
}

/// 佇列的一個位置。同一首可以出現在兩個位置，以位置區分。
@immutable
final class QueueEntry {
  const QueueEntry(this.track);

  final TrackInfo track;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QueueEntry && other.track == track;

  @override
  int get hashCode => track.hashCode;
}

/// 進入臨時播放時佇列的播放狀態。回到的那一首是當時的
/// [QueueState.currentIndex]：臨時播放期間佇列照常可以編輯，位置跟著調整。
@immutable
final class QueueSnapshot {
  const QueueSnapshot({required this.position, required this.playing});

  static const empty = QueueSnapshot(position: Duration.zero, playing: false);

  /// 那一首當時播到的位置。
  final Duration position;

  /// 當時是不是在播：回到佇列後只有原本在播才自動播。
  final bool playing;

  /// 回到佇列時從哪裡開始：「記住播放位置」開著時從快照位置倒退 [rewind]
  /// （「臨時播放回佇列倒退秒數」），否則從頭。
  Duration resumeAt({
    required bool rememberPosition,
    required Duration rewind,
  }) {
    if (!rememberPosition) return Duration.zero;
    final position = this.position - rewind;
    return position.isNegative ? Duration.zero : position;
  }
}

/// 臨時播放中的曲目與進入時的快照。
@immutable
final class TemporaryPlay {
  const TemporaryPlay({required this.track, required this.snapshot});

  final TrackInfo track;
  final QueueSnapshot snapshot;
}

/// 收聽直播中的直播間與進入時的佇列快照（同臨時播放，ADR 0031 §決定 7）。
@immutable
final class LivePlay {
  const LivePlay({required this.target, required this.snapshot});

  final LiveTarget target;
  final QueueSnapshot snapshot;
}

/// 佇列的一份快照（ADR 0018 §決定 4）。與播放狀態沒有共同欄位：播到哪一首
/// 只在這裡。
@immutable
final class QueueState {
  const QueueState({
    required this.entries,
    required this.currentIndex,
    this.loopMode = LoopMode.off,
    this.shuffleOrder,
    this.temporary,
    this.live,
    this.mix,
  }) : assert(
         currentIndex == null ||
             (currentIndex >= 0 && currentIndex < entries.length),
       ),
       assert(shuffleOrder == null || shuffleOrder.length == entries.length);

  static const empty = QueueState(entries: [], currentIndex: null);

  /// 佇列的位置，依畫面上的順序。
  final List<QueueEntry> entries;

  /// 佇列目前這首的位置；佇列是空的時為 `null`。臨時播放中是回到佇列時的
  /// 那一首。
  final int? currentIndex;

  final LoopMode loopMode;

  /// 隨機開啟時，這一輪播放位置的順序（每個位置恰好一次，目前這首之前的
  /// 是本輪已播的）；關閉時為 `null`。
  final List<int>? shuffleOrder;

  /// 臨時播放中的曲目與快照；不在臨時播放時為 `null`。
  final TemporaryPlay? temporary;

  /// 收聽中的直播間與快照；不在收聽直播時為 `null`。與 [temporary] 不會同時有值。
  final LivePlay? live;

  /// 佇列是 Mix 時的身分（含補歌用的 cursor）；一般佇列為 `null`。臨時播放與直播
  /// 期間照舊有值：它們結束後回到的是 Mix 佇列。
  final MixIdentity? mix;

  QueueMode get mode => live != null
      ? QueueMode.live
      : temporary != null
      ? QueueMode.temporary
      : mix != null
      ? QueueMode.mix
      : QueueMode.queue;

  bool get shuffleEnabled => shuffleOrder != null;

  /// 在播的是佇列以外的東西（臨時播放或直播）：資料庫停在進入時的佇列那一首與
  /// [returnSnapshot]，不跟著寫。
  bool get isOutsideQueue => temporary != null || live != null;

  /// 在播的是佇列裡的歌（含 Mix），不是臨時播放或直播。
  bool get inQueue => !isOutsideQueue;

  /// 離開臨時播放或直播、回到佇列時的快照；在佇列裡為 `null`。
  QueueSnapshot? get returnSnapshot => temporary?.snapshot ?? live?.snapshot;

  /// 正在播（或要播）的曲目：臨時播放中是臨時的那首，否則是佇列目前這首。收聽
  /// 直播時不是曲目，為 `null`（直播的內容看 [live]，佇列照舊在 [entries]）。
  TrackInfo? get current => live != null
      ? null
      : temporary?.track ??
            switch (currentIndex) {
              final index? => entries[index].track,
              null => null,
            };

  /// [QueueModel.moveNext] 會不會換曲目。臨時播放中一律是（回到佇列）；收聽直播
  /// 時上一首、下一首都停用。
  bool get hasNext {
    if (live != null) return false;
    if (temporary != null) return true;
    final index = currentIndex;
    if (index == null) return false;
    if (loopMode == LoopMode.all) return true;
    final order = shuffleOrder;
    if (order != null) return order.indexOf(index) < order.length - 1;
    return index < entries.length - 1;
  }
}

/// [QueueModel.moveNext]、[QueueModel.movePrevious] 之後呼叫端要做什麼。
sealed class QueueStep {
  const QueueStep();
}

/// 目前這首換了：從開頭播 [QueueState.current]。
final class MovedToTrack extends QueueStep {
  const MovedToTrack();
}

/// 留在目前這首、回到開頭：上一首時已經播超過 3 秒，或前面沒有歌。
final class RestartTrack extends QueueStep {
  const RestartTrack();
}

/// 臨時播放結束、回到佇列的 [QueueState.current]，從
/// `snapshot.resumeAt(...)` 開始，`snapshot.playing` 才自動播。佇列是空的
/// （`current` 為 `null`）時停下。
final class ReturnedToQueue extends QueueStep {
  const ReturnedToQueue(this.snapshot);

  final QueueSnapshot snapshot;
}

/// 什麼都沒變：沒有下一首，或佇列是空的。
final class QueueUnchanged extends QueueStep {
  const QueueUnchanged();
}

/// 佇列的真相（ADR 0018 §決定 4、5）：純 Dart，不碰資料庫與後端；播放位置與
/// 設定值由呼叫端傳入。只由 `PlaybackController` 呼叫。
///
/// 隨機以「位置」為單位：開啟時產生位置的排列（[QueueState.shuffleOrder]），
/// 之後的編輯只動排列裡受影響的位置，其他未播位置的相對順序不變：
///
/// - 拖曳（[move]）只移動歌，不動位置的排列；拖進本輪已播的位置，本輪就不再
///   播。目前這首被移到別的位置時，它的新舊位置交換排序，目前這首仍在本輪的
///   進度上。
/// - 下一首播放（[playNext]）排在目前這首之後，連續加入依加入順序；目前這首
///   換了，或佇列被拖曳、整份取代之後，重新從目前這首之後排。
/// - 附加（[append]）的位置加在最後；隨機時排序插在剩下未播（下一首播放的
///   之後）的隨機一處。
/// - 跳到某首（[jumpTo]）把那個位置的排序移到目前這首之後再往下。
/// - 一輪播完：循環 [LoopMode.all] 時產生新的排列，剛播完的那個位置不排第一；
///   否則停下。
final class QueueModel {
  /// [random] 決定隨機的排列；測試以固定種子注入。
  QueueModel({Random? random}) : _random = random ?? Random();

  /// 佇列最多幾首（ADR 0018 §決定 4）。
  static const maxLength = 10000;

  /// Mix 佇列最多留幾首已播的（ADR 0018 §決定 4）：超過就刪最舊的。
  static const maxMixPlayed = 100;

  /// 上一首時播放超過這個長度就回到開頭。
  static const restartThreshold = Duration(seconds: 3);

  final Random _random;

  List<QueueEntry> _entries = [];
  int? _current;
  LoopMode _loop = LoopMode.off;

  /// 隨機開啟時本輪的位置排列，目前這首在 `_order.indexOf(_current)`。
  List<int>? _order;
  TemporaryPlay? _temporary;
  LivePlay? _live;
  MixIdentity? _mix;

  /// 目前這首之後有幾個位置是「下一首播放」連續加入的（清單與排列上都緊接在
  /// 目前這首之後）。
  int _playNextRun = 0;

  /// 一輪的最後一首時，下一輪的排列：[next] 先決定，[moveNext] 照用，兩者才
  /// 會一致。任何編輯都作廢它。
  List<int>? _nextRound;

  QueueState _state = QueueState.empty;

  QueueState get state => _state;

  /// [moveNext] 之後的目前這首；不會換曲目時為 `null`。臨時播放中是回到佇列
  /// 的那一首（從快照的位置開始，不是開頭）。
  ({int index, TrackInfo track})? get next {
    if (_live != null) return null;
    final index = _temporary != null ? _current : _following();
    if (index == null) return null;
    return (index: index, track: _entries[index].track);
  }

  // ---- 換曲目 ---------------------------------------------------------------

  /// 往下一首（播完、按下一首、被跳過都是它）。臨時播放中是回到佇列。
  QueueStep moveNext() {
    if (_live != null) return const QueueUnchanged();
    if (_temporary != null) return _returnToQueue();
    if (!_advance()) return const QueueUnchanged();
    _publish();
    return const MovedToTrack();
  }

  /// 上一首：[position]（目前這首播到的位置）超過 [restartThreshold] 就回到
  /// 開頭，否則往排列的前一個；前面沒有歌時回到開頭。臨時播放中是回到佇列。
  QueueStep movePrevious({required Duration position}) {
    if (_live != null) return const QueueUnchanged();
    if (_temporary != null) return _returnToQueue();
    final current = _current;
    if (current == null) return const QueueUnchanged();
    if (position > restartThreshold) return const RestartTrack();
    final int? target;
    if (_order case final order?) {
      final cursor = order.indexOf(current);
      // 隨機時一輪的開頭不往回繞：上一輪的排列已經不在了。
      target = cursor > 0 ? order[cursor - 1] : null;
    } else if (current > 0) {
      target = current - 1;
    } else {
      target = _loop == LoopMode.all ? _entries.length - 1 : null;
    }
    if (target == null || target == current) return const RestartTrack();
    _current = target;
    _playNextRun = 0;
    _publish();
    return const MovedToTrack();
  }

  /// 跳到位置 [index]（在佇列中點選）。臨時播放就此結束、快照丟掉。
  void jumpTo(int index) {
    RangeError.checkValidIndex(index, _entries, 'index');
    _temporary = null;
    _live = null;
    final current = _current!;
    if (_order case final order? when index != current) {
      order.remove(index);
      order.insert(order.indexOf(current) + 1, index);
    }
    _current = index;
    _playNextRun = 0;
    _publish();
  }

  /// 臨時播放 [track]。還不是臨時播放時記下快照：[position] 是佇列目前這首
  /// 播到的位置，[playing] 是它在不在播；已經是臨時播放時只換曲目、快照不變。
  /// 臨時曲目不放進佇列。
  void playTemporary(
    TrackInfo track, {
    required Duration position,
    required bool playing,
  }) {
    final snapshot =
        _temporary?.snapshot ??
        _live?.snapshot ??
        (_current == null
            ? QueueSnapshot.empty
            : QueueSnapshot(position: position, playing: playing));
    _temporary = TemporaryPlay(track: track, snapshot: snapshot);
    _live = null;
    _publish();
  }

  /// 收聽 [target]。還不是臨時播放或直播時記下快照（同 [playTemporary]）；已經是
  /// 其中之一時只換內容、快照維持進入時的那份（換台不會把中途的臨時曲目或上一個
  /// 直播間當成要回去的地方）。
  void playLive(
    LiveTarget target, {
    required Duration position,
    required bool playing,
  }) {
    final snapshot =
        _live?.snapshot ??
        _temporary?.snapshot ??
        (_current == null
            ? QueueSnapshot.empty
            : QueueSnapshot(position: position, playing: playing));
    _live = LivePlay(target: target, snapshot: snapshot);
    _temporary = null;
    _publish();
  }

  /// 停止收聽、回到佇列（直播頁的停止）。不在收聽直播時什麼都不變。
  QueueStep stopLive() {
    final live = _live;
    if (live == null) return const QueueUnchanged();
    _live = null;
    _publish();
    return ReturnedToQueue(live.snapshot);
  }

  // ---- 加入 -----------------------------------------------------------------

  /// 啟動時帶回上次的佇列（design §7.7）：[tracks]、目前這首的位置、循環與隨機。
  /// [shuffle] 為真而 [shuffleOrder] 是 `null`（沒存或不完整）時重新排一份，目前
  /// 這首排第一；[shuffleOrder] 必須是 [tracks] 全部位置的排列。不在臨時播放，
  /// 「下一首播放」的連續計數也不帶回來。
  void restore({
    required List<TrackInfo> tracks,
    required int? currentIndex,
    required LoopMode loopMode,
    required bool shuffle,
    List<int>? shuffleOrder,
    MixIdentity? mix,
  }) {
    assert(
      shuffleOrder == null ||
          (shuffleOrder.length == tracks.length &&
              shuffleOrder.toSet().length == tracks.length &&
              shuffleOrder.every((i) => i >= 0 && i < tracks.length)),
      'shuffleOrder must be a permutation of the positions',
    );
    _entries = [for (final track in tracks) QueueEntry(track)];
    _current = tracks.isEmpty
        ? null
        : (currentIndex ?? 0).clamp(0, tracks.length - 1);
    // Mix 沒有「全部」（ADR 0031 §決定 9）：舊資料存著 all 時改成關。
    _loop = mix != null && loopMode == LoopMode.all ? LoopMode.off : loopMode;
    _temporary = null;
    _live = null;
    _mix = mix;
    _playNextRun = 0;
    // Mix 不能隨機：存的資料有 Mix 又開了隨機（不該發生）時以 Mix 為準。
    _order = switch ((shuffle && mix == null, _current)) {
      (false, _) => null,
      (true, null) => [],
      (true, final current?) => shuffleOrder ?? _orderStartingAt(current),
    };
    _publish();
  }

  /// 以 [tracks] 取代佇列，從 [startIndex] 開始（臨時播放就此結束）。會超過
  /// [maxLength] 就整批不加、回傳 `false`。
  bool replace(List<TrackInfo> tracks, {int startIndex = 0}) {
    if (tracks.length > maxLength) return false;
    if (tracks.isEmpty) {
      clear();
      return true;
    }
    RangeError.checkValidIndex(startIndex, tracks, 'startIndex');
    _entries = [for (final track in tracks) QueueEntry(track)];
    _current = startIndex;
    _temporary = null;
    _live = null;
    _mix = null;
    _playNextRun = 0;
    if (_order != null) _order = _orderStartingAt(startIndex);
    _publish();
    return true;
  }

  /// 開始 Mix（ADR 0031 §決定 9）：以 [tracks] **取代整個佇列**（原佇列不另存），
  /// 進入 Mix 模式、從第一首開始；臨時播放與直播就此結束，隨機關掉，循環是「全部」就改成「關」
  /// （Mix 沒有「全部」），其他維持。
  /// [tracks] 是空的或超過 [maxLength] 就什麼都不做、回傳 `false`。
  bool startMix(MixIdentity mix, List<TrackInfo> tracks) {
    if (tracks.isEmpty || tracks.length > maxLength) return false;
    _entries = [for (final track in tracks) QueueEntry(track)];
    _current = 0;
    _temporary = null;
    _live = null;
    _order = null;
    _mix = mix;
    _playNextRun = 0;
    if (_loop == LoopMode.all) _loop = LoopMode.off;
    _publish();
    return true;
  }

  /// 補歌（ADR 0031 §決定 10）：把 [tracks] 附加在 Mix 佇列最後，已在佇列裡的曲目鍵
  /// （含這一批自己重複的）丟掉，Mix 身分換成 [mix]（新的 cursor，或換了種子後新的
  /// `mixId`）。回傳實際附加幾首。不是 Mix 時什麼都不做、回傳 0；會超過 [maxLength]
  /// 的部分不加。
  int extendMix(MixIdentity mix, List<TrackInfo> tracks) {
    if (_mix == null) return 0;
    final seen = {for (final entry in _entries) '${entry.track.key}'};
    final fresh = [
      for (final track in tracks)
        if (seen.add('${track.key}')) track,
    ].take(maxLength - _entries.length).toList();
    _entries.addAll([for (final track in fresh) QueueEntry(track)]);
    _mix = mix;
    _publish();
    return fresh.length;
  }

  /// 加在佇列最後。會超過 [maxLength] 就整批不加、回傳 `false`；Mix 中一律拒絕
  /// （回傳 `false`、不改佇列）。
  bool append(List<TrackInfo> tracks) {
    if (_mix != null) return false;
    if (_entries.length + tracks.length > maxLength) return false;
    if (tracks.isEmpty) return true;
    final start = _entries.length;
    _entries.addAll([for (final track in tracks) QueueEntry(track)]);
    final current = _current;
    if (current == null) {
      _current = 0;
      if (_order != null) _order = _orderStartingAt(0);
    } else if (_order case final order?) {
      final from = order.indexOf(current) + 1 + _playNextRun;
      for (var position = start; position < _entries.length; position++) {
        order.insert(from + _random.nextInt(order.length - from + 1), position);
      }
    }
    _publish();
    return true;
  }

  /// 下一首播放：排在目前這首（臨時播放中是快照的那一首）之後，接在之前
  /// 連續加入的後面。會超過 [maxLength] 就整批不加、回傳 `false`；Mix 中一律拒絕。
  bool playNext(List<TrackInfo> tracks) {
    if (_mix != null) return false;
    if (_entries.length + tracks.length > maxLength) return false;
    if (tracks.isEmpty) return true;
    final added = [for (final track in tracks) QueueEntry(track)];
    final current = _current;
    if (current == null) {
      // 佇列是空的：第一首成為目前這首，其餘依加入順序在它之後。
      _entries = added;
      _current = 0;
      if (_order != null) _order = [for (var i = 0; i < added.length; i++) i];
      _playNextRun = added.length - 1;
      _publish();
      return true;
    }
    final at = current + 1 + _playNextRun;
    _entries.insertAll(at, added);
    if (_order case final order?) {
      final rank = order.indexOf(current) + 1 + _playNextRun;
      for (var i = 0; i < order.length; i++) {
        if (order[i] >= at) order[i] += added.length;
      }
      order.insertAll(rank, [for (var i = 0; i < added.length; i++) at + i]);
    }
    _playNextRun += added.length;
    _publish();
    return true;
  }

  // ---- 編輯 -----------------------------------------------------------------

  /// 把位置 [from] 的歌拖到位置 [to]（見類別說明的隨機規則）。
  void move(int from, int to) {
    RangeError.checkValidIndex(from, _entries, 'from');
    RangeError.checkValidIndex(to, _entries, 'to');
    if (from == to) return;
    _entries.insert(to, _entries.removeAt(from));
    final current = _current!;
    final int moved;
    if (from == current) {
      moved = to;
    } else if (from < current && to >= current) {
      moved = current - 1;
    } else if (from > current && to <= current) {
      moved = current + 1;
    } else {
      moved = current;
    }
    if (moved != current) {
      if (_order case final order?) {
        final rank = order.indexOf(current);
        order[order.indexOf(moved)] = current;
        order[rank] = moved;
      }
      _current = moved;
    }
    _playNextRun = 0;
    _publish();
  }

  /// 把位置 [index] 的歌移到目前這首之後，接在之前連續「下一首播放」的後面（佇列
  /// 選單的「下一首播放」）。等於移除再以 [playNext] 加回，但項目是同一個實例、
  /// 不檢查上限；隨機時它的排序也移到同一處，所以下一首（或接著的那幾首之後）
  /// 一定播它，和 [move] 的「只換歌、不改排列」不同。[index] 是目前這首（臨時播放中
  /// 是快照那首）時不做事；佇列是空的時沒有合法的 [index]，同其他編輯拋 [RangeError]。
  void moveToNext(int index) {
    RangeError.checkValidIndex(index, _entries, 'index');
    final current = _current!;
    if (index == current) return;
    final entry = _entries.removeAt(index);
    var cursor = current;
    var run = _playNextRun;
    if (index < current) {
      cursor--;
    } else if (index <= current + run) {
      run--;
    }
    final at = cursor + 1 + run;
    _entries.insert(at, entry);
    if (_order case final order?) {
      order.remove(index);
      for (var i = 0; i < order.length; i++) {
        if (order[i] > index) order[i]--;
      }
      for (var i = 0; i < order.length; i++) {
        if (order[i] >= at) order[i]++;
      }
      order.insert(order.indexOf(cursor) + 1 + run, at);
    }
    _current = cursor;
    _playNextRun = run + 1;
    _publish();
  }

  /// 移除位置 [index]。移除的是目前這首時往下一首（沒有下一首就往前一首）；
  /// 臨時播放中，回到佇列的那一首因此換了時，從頭開始。
  void remove(int index) {
    RangeError.checkValidIndex(index, _entries, 'index');
    if (_entries.length == 1) {
      _entries = [];
      _current = null;
      _mix = null;
      if (_order != null) _order = [];
      _playNextRun = 0;
      _resetSnapshotPosition();
      _publish();
      return;
    }
    final current = _current!;
    if (index == current) {
      if (!_advance()) {
        _current = switch (_order) {
          final order? => order[order.indexOf(current) - 1],
          null => current - 1,
        };
        _playNextRun = 0;
      }
      _resetSnapshotPosition();
    } else if (index > current && index <= current + _playNextRun) {
      _playNextRun--;
    }
    _entries.removeAt(index);
    if (_current! > index) _current = _current! - 1;
    if (_order case final order?) {
      order.remove(index);
      for (var i = 0; i < order.length; i++) {
        if (order[i] > index) order[i]--;
      }
    }
    _publish();
  }

  /// 清空佇列並結束臨時播放（呼叫端停止播放）。循環與隨機的開關不變；Mix 也就此
  /// 退出（回到空的一般佇列）。
  void clear() {
    _entries = [];
    _current = null;
    if (_order != null) _order = [];
    _temporary = null;
    _live = null;
    _mix = null;
    _playNextRun = 0;
    _publish();
  }

  // ---- 模式 -----------------------------------------------------------------

  /// 開啟時產生位置的排列、目前這首排第一（本輪重新開始）；關閉時從目前這首
  /// 依清單往下。
  void setShuffle(bool enabled) {
    if (enabled == (_order != null)) return;
    // Mix 不能隨機（ADR 0031 §決定 9）：拒絕，不改佇列。
    if (enabled && _mix != null) return;
    if (enabled) {
      _order = switch (_current) {
        final current? => _orderStartingAt(current),
        null => [],
      };
      _playNextRun = 0;
    } else {
      // 下一首播放的位置在清單上也緊接在目前這首之後，順序不變。
      _order = null;
    }
    _publish();
  }

  /// 循環依 off → all → one 輪轉，回傳新的模式；Mix 中沒有 all，依 off → one 輪轉。
  LoopMode cycleLoopMode() {
    _loop = switch (_loop) {
      LoopMode.off when _mix != null => LoopMode.one,
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    _publish();
    return _loop;
  }

  // ---- 內部 -----------------------------------------------------------------

  /// 佇列裡目前這首之後的位置（不看臨時播放）。
  int? _following() {
    final current = _current;
    if (current == null) return null;
    if (_order case final order?) {
      final cursor = order.indexOf(current);
      if (cursor + 1 < order.length) return order[cursor + 1];
      if (_loop != LoopMode.all) return null;
      return (_nextRound ??= _newRound(current)).first;
    }
    if (current + 1 < _entries.length) return current + 1;
    return _loop == LoopMode.all ? 0 : null;
  }

  bool _advance() {
    final current = _current;
    final target = _following();
    if (current == null || target == null) return false;
    if (_order case final order?
        when order.indexOf(current) == order.length - 1) {
      _order = _nextRound;
    }
    _current = target;
    _playNextRun = 0;
    return true;
  }

  QueueStep _returnToQueue() {
    final snapshot = _temporary!.snapshot;
    _temporary = null;
    _publish();
    return ReturnedToQueue(snapshot);
  }

  /// 臨時播放或直播中佇列的那一首換了：快照的位置屬於原本那首，改成從頭。
  void _resetSnapshotPosition() {
    final temporary = _temporary;
    if (temporary != null) {
      _temporary = TemporaryPlay(
        track: temporary.track,
        snapshot: QueueSnapshot(
          position: Duration.zero,
          playing: temporary.snapshot.playing,
        ),
      );
    }
    final live = _live;
    if (live != null) {
      _live = LivePlay(
        target: live.target,
        snapshot: QueueSnapshot(
          position: Duration.zero,
          playing: live.snapshot.playing,
        ),
      );
    }
  }

  /// 所有位置的隨機排列，[first] 排第一。
  List<int> _orderStartingAt(int first) => [
    first,
    ...[
      for (var i = 0; i < _entries.length; i++)
        if (i != first) i,
    ]..shuffle(_random),
  ];

  /// 新一輪的排列：[last]（上一輪最後播的）不排第一，免得同一首連播兩次。
  List<int> _newRound(int last) {
    final order = [
      for (var i = 0; i < _entries.length; i++)
        if (i != last) i,
    ]..shuffle(_random);
    order.insert(order.isEmpty ? 0 : 1 + _random.nextInt(order.length), last);
    return order;
  }

  /// Mix 已播超過 [maxMixPlayed] 首時刪最舊的已播項目（排在目前這首之前的）：剛好
  /// 那麼多不刪，目前這首與還沒播的不動。Mix 沒有隨機，所以排列與「下一首播放」
  /// 的連續計數都不受影響。
  void _trimMix() {
    final current = _current;
    if (_mix == null || current == null) return;
    final excess = current - maxMixPlayed;
    if (excess <= 0) return;
    _entries.removeRange(0, excess);
    _current = current - excess;
  }

  void _publish() {
    _trimMix();
    _nextRound = null;
    final order = _order;
    _state = QueueState(
      entries: List.unmodifiable(_entries),
      currentIndex: _current,
      loopMode: _loop,
      shuffleOrder: order == null ? null : List.unmodifiable(order),
      temporary: _temporary,
      live: _live,
      mix: _mix,
    );
  }
}
