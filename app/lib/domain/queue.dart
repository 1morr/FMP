import 'dart:math';

import 'package:fmp/domain/track.dart';

/// 循環（brief〈播放〉）：不循環、列表循環、單曲循環。
enum Repeat {
  off,
  all,
  one;

  /// 切換鈕依序切到的下一個：不循環 → 列表 → 單曲 → 不循環。
  Repeat get cycled => values[(index + 1) % values.length];
}

/// 佇列裡的一個位置。同一首曲目可以排好幾次，靠 [id] 分開；[id] 在同一個
/// 佇列裡不重複，畫面拿它當列的鍵。
class QueueEntry {
  const QueueEntry(this.id, this.track);

  final int id;
  final Track track;

  @override
  bool operator ==(Object other) =>
      other is QueueEntry && other.id == id && other.track == track;

  @override
  int get hashCode => Object.hash(id, track);

  @override
  String toString() => 'QueueEntry($id, ${track.ref.logId})';
}

/// 佇列（`GLOSSARY.md`）：要播放的曲目序列，含播過的與接下來的，
/// [entries] 永遠是播放順序。不可變：每個動作回傳新的佇列。
///
/// 目前那首（[currentIndex]）以前是播過的，以後是接下來的。空佇列沒有目前
/// 那首；不空時也可能沒有：移除正在播的最後一首後，剩下的都是播過的。
///
/// 播放模式（隨機與循環）也在這裡：隨機時 [entries] 是打亂後的播放順序，
/// 原順序另外留著，關掉隨機時恢復。播放由 `playback/` 依目前那首去做。
class Queue {
  const Queue._(
    this.entries,
    this.currentIndex,
    this._nextId, {
    this.repeat = Repeat.off,
    this._original,
    this._pinned = const {},
  });

  static const empty = Queue._([], null, 0);

  /// 播放順序，不能從外面改。
  final List<QueueEntry> entries;

  /// 目前那首在 [entries] 的位置；沒有目前那首時是 null。
  final int? currentIndex;

  /// 下一個加入的位置用的 [QueueEntry.id]。
  final int _nextId;

  /// 隨機時的原順序（[QueueEntry.id]），不含 [_pinned] 的；不隨機時是 null。
  final List<int>? _original;

  /// 隨機時拖動過或用「下一首播放」插進來的位置：關掉隨機後排在正在播的
  /// 那首後面，不回原位。
  final Set<int> _pinned;

  /// 循環。單曲循環只管一首自然播完後重播（由 `playback/` 做），手動的
  /// 上一首、下一首照不循環走。
  final Repeat repeat;

  /// 隨機開著。
  bool get shuffled => _original != null;

  bool get isEmpty => entries.isEmpty;

  QueueEntry? get current => switch (currentIndex) {
    final index? => entries[index],
    null => null,
  };

  /// 有下一首可以切：還沒到最後一首，或列表循環會繞回去。
  bool get hasNext => switch (currentIndex) {
    final index? => index < entries.length - 1 || repeat == Repeat.all,
    null => false,
  };

  /// 有上一首可以切：不在第一首，或列表循環會繞到最後一首。
  bool get hasPrevious => switch (currentIndex) {
    final index? => index > 0 || repeat == Repeat.all,
    null => false,
  };

  /// 加入佇列：排在最後。沒有目前那首時，加入的第一首成為目前那首。隨機時
  /// 也排在播放順序最後，原順序裡同樣在最後。
  Queue add(List<Track> tracks) => _insert(entries.length, tracks, pin: false);

  /// 下一首播放：依序插在目前那首後面。沒有目前那首時排在最後，插入的
  /// 第一首成為目前那首。隨機時一樣是下一首，關掉隨機後排在正在播的那首
  /// 後面。
  Queue playNext(List<Track> tracks) => _insert(
    currentIndex == null ? entries.length : currentIndex! + 1,
    tracks,
    pin: true,
  );

  /// 下一首；沒有下一首時是 null。列表循環時最後一首的下一首是第一首；
  /// 隨機加列表循環時整串重新打亂（用 [random]）再播一輪。
  Queue? next([Random? random]) {
    if (!hasNext) return null;
    final index = currentIndex!;
    if (index < entries.length - 1) return jumpTo(index + 1);
    return shuffled ? _reshuffled(random) : jumpTo(0);
  }

  /// 上一首；沒有上一首時是 null。列表循環時第一首的上一首是最後一首。
  Queue? previous() {
    if (!hasPrevious) return null;
    final index = currentIndex!;
    return jumpTo(index > 0 ? index - 1 : entries.length - 1);
  }

  /// 換循環。
  Queue withRepeat(Repeat mode) => Queue._(
    entries,
    currentIndex,
    _nextId,
    repeat: mode,
    original: _original,
    pinned: _pinned,
  );

  /// 讓 [index] 那個位置成為目前那首。
  Queue jumpTo(int index) {
    RangeError.checkValidIndex(index, entries, 'index');
    return _with(entries, index);
  }

  /// 拖動排序：把 [from] 的位置移到 [to]（移完之後的位置）。目前那首跟著
  /// 它的位置走；拖到目前那首上面的就算播過了。
  Queue move(int from, int to) {
    RangeError.checkValidIndex(from, entries, 'from');
    RangeError.checkValidIndex(to, entries, 'to');
    final current = this.current;
    final moved = [...entries];
    final entry = moved.removeAt(from);
    moved.insert(to, entry);
    // 隨機時拖動過的不回原位；目前那首例外，它在原順序裡的位置是關掉隨機
    // 時接著播的地方。
    final pin = shuffled && entry != current;
    return _with(
      List.unmodifiable(moved),
      current == null ? null : moved.indexOf(current),
      original: pin ? _withoutId(_original!, entry.id) : null,
      pinned: pin ? {..._pinned, entry.id} : null,
    );
  }

  /// 把 [index] 的位置移到目前那首的下一個位置；它是目前那首時不動。
  Queue moveToNext(int index) {
    RangeError.checkValidIndex(index, entries, 'index');
    final current = currentIndex;
    if (current == null || index == current) return this;
    // 移走之前在目前那首前面的，目前那首會往前一格，緊接在它後面還是 current。
    final to = index > current ? current + 1 : current;
    return index == to ? this : move(index, to);
  }

  /// 移除 [index] 的位置。移除的是目前那首時，原本的下一首成為目前那首；
  /// 它已是最後一首時，列表循環照 [next] 繞回去（隨機時用 [random] 重新
  /// 打亂），否則就沒有目前那首了，剩下的都是播過的。
  Queue remove(int index, [Random? random]) {
    RangeError.checkValidIndex(index, entries, 'index');
    final remaining = [...entries];
    final removed = remaining.removeAt(index);
    final current = currentIndex;
    final int? newCurrent;
    if (current == null || index > current) {
      newCurrent = current;
    } else if (index < current) {
      newCurrent = current - 1;
    } else {
      newCurrent = index < remaining.length ? index : null;
    }
    final queue = _with(
      List.unmodifiable(remaining),
      newCurrent,
      original: shuffled ? _withoutId(_original!, removed.id) : null,
      pinned: {..._pinned}..remove(removed.id),
    );
    final wrapped =
        index == current &&
        newCurrent == null &&
        remaining.isNotEmpty &&
        repeat == Repeat.all;
    if (!wrapped) return queue;
    return shuffled ? queue._reshuffled(random) : queue.jumpTo(0);
  }

  /// 開隨機：目前那首移到最上方，其餘的（含播過的）打亂排在後面；沒有
  /// 目前那首時全部打亂。原順序留著，關掉隨機時恢復。
  Queue shuffle([Random? random]) {
    if (shuffled) return this;
    final current = this.current;
    final rest = [
      for (final entry in entries)
        if (entry != current) entry,
    ]..shuffle(random);
    return Queue._(
      List.unmodifiable([?current, ...rest]),
      current == null ? null : 0,
      _nextId,
      repeat: repeat,
      original: List.unmodifiable([for (final entry in entries) entry.id]),
    );
  }

  /// 新的一輪：全部重新打亂，從第一首開始；剛播完的那首不排第一。原順序
  /// 與拖動過的照舊。
  Queue _reshuffled(Random? random) {
    final finished = current;
    final round = [...entries]..shuffle(random);
    if (round.length > 1 && round.first == finished) {
      round.add(round.removeAt(0));
    }
    return _with(List.unmodifiable(round), 0);
  }

  /// 關隨機：恢復原順序，目前那首留在它在原順序裡的位置，從那裡繼續。
  /// 隨機時拖動過或用「下一首播放」插進來的，照播放順序排在正在播的那首
  /// 後面；正在播的就是其中一首時，這一組排在它前面最近一首原順序裡的
  /// 曲目後面。
  Queue unshuffle() {
    final original = _original;
    if (original == null) return this;
    final byId = {for (final entry in entries) entry.id: entry};
    final restored = [for (final id in original) byId[id]!];
    final current = this.current;
    final pinned = [
      for (final entry in entries)
        if (_pinned.contains(entry.id)) entry,
    ];
    final int at;
    if (current == null) {
      at = restored.length;
    } else {
      final anchor = entries
          .take(currentIndex! + 1)
          .lastWhere((e) => !_pinned.contains(e.id), orElse: () => current);
      at = _pinned.contains(anchor.id) ? 0 : restored.indexOf(anchor) + 1;
    }
    restored.insertAll(at, pinned);
    return Queue._(
      List.unmodifiable(restored),
      current == null ? null : restored.indexOf(current),
      _nextId,
      repeat: repeat,
    );
  }

  /// 清空佇列。隨機照舊開著。
  Queue clear() => Queue._(
    const [],
    null,
    _nextId,
    repeat: repeat,
    original: shuffled ? const [] : null,
  );

  Queue _insert(int at, List<Track> tracks, {required bool pin}) {
    if (tracks.isEmpty) return this;
    final added = [
      for (var i = 0; i < tracks.length; i++)
        QueueEntry(_nextId + i, tracks[i]),
    ];
    final current = currentIndex;
    final addedIds = [for (final entry in added) entry.id];
    return _with(
      List.unmodifiable([...entries]..insertAll(at, added)),
      current == null ? at : (at <= current ? current + added.length : current),
      nextId: _nextId + added.length,
      original: shuffled && !pin
          ? List.unmodifiable([..._original!, ...addedIds])
          : null,
      pinned: shuffled && pin ? {..._pinned, ...addedIds} : null,
    );
  }

  /// 換掉 [entries] 與目前那首；沒給的（隨機狀態）照舊。
  Queue _with(
    List<QueueEntry> entries,
    int? currentIndex, {
    int? nextId,
    List<int>? original,
    Set<int>? pinned,
  }) => Queue._(
    entries,
    currentIndex,
    nextId ?? _nextId,
    repeat: repeat,
    original: original ?? _original,
    pinned: pinned ?? _pinned,
  );

  static List<int> _withoutId(List<int> ids, int id) =>
      List.unmodifiable([...ids]..remove(id));

  @override
  String toString() => 'Queue($entries, current: $currentIndex)';
}
