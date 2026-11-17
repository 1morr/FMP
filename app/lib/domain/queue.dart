import 'package:fmp/domain/track.dart';

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
/// 不變式：空佇列沒有目前那首；不空時 [currentIndex] 指向其中一個位置，
/// 它以前是播過的，以後是接下來的。這裡只有不隨機、不循環的規則；播放
/// 由 `playback/` 依目前那首去做。
class Queue {
  const Queue._(this.entries, this.currentIndex, this._nextId);

  static const empty = Queue._([], null, 0);

  /// 播放順序，不能從外面改。
  final List<QueueEntry> entries;

  /// 目前那首在 [entries] 的位置；空佇列是 null。
  final int? currentIndex;

  /// 下一個加入的位置用的 [QueueEntry.id]。
  final int _nextId;

  bool get isEmpty => entries.isEmpty;

  QueueEntry? get current => switch (currentIndex) {
    final index? => entries[index],
    null => null,
  };

  bool get hasNext => switch (currentIndex) {
    final index? => index < entries.length - 1,
    null => false,
  };

  bool get hasPrevious => switch (currentIndex) {
    final index? => index > 0,
    null => false,
  };

  /// 加入佇列：排在最後。空佇列時第一首成為目前那首。
  Queue add(List<Track> tracks) => _insert(entries.length, tracks);

  /// 下一首播放：依序插在目前那首後面。空佇列時第一首成為目前那首。
  Queue playNext(List<Track> tracks) =>
      _insert(currentIndex == null ? 0 : currentIndex! + 1, tracks);

  /// 下一首；沒有下一首時是 null。
  Queue? next() => hasNext ? jumpTo(currentIndex! + 1) : null;

  /// 上一首；沒有上一首時是 null。
  Queue? previous() => hasPrevious ? jumpTo(currentIndex! - 1) : null;

  /// 讓 [index] 那個位置成為目前那首。
  Queue jumpTo(int index) {
    RangeError.checkValidIndex(index, entries, 'index');
    return Queue._(entries, index, _nextId);
  }

  /// 拖動排序：把 [from] 的位置移到 [to]（移完之後的位置）。目前那首跟著
  /// 它的位置走；拖到目前那首上面的就算播過了。
  Queue move(int from, int to) {
    RangeError.checkValidIndex(from, entries, 'from');
    RangeError.checkValidIndex(to, entries, 'to');
    final current = this.current;
    final moved = [...entries];
    moved.insert(to, moved.removeAt(from));
    return Queue._(
      List.unmodifiable(moved),
      current == null ? null : moved.indexOf(current),
      _nextId,
    );
  }

  /// 移除 [index] 的位置。移除的是目前那首時，原本的下一首成為目前那首；
  /// 它已是最後一首時，新的最後一首成為目前那首。
  Queue remove(int index) {
    RangeError.checkValidIndex(index, entries, 'index');
    final remaining = [...entries]..removeAt(index);
    if (remaining.isEmpty) return Queue._(const [], null, _nextId);
    final current = currentIndex!;
    final newCurrent = index < current
        ? current - 1
        : current.clamp(0, remaining.length - 1);
    return Queue._(List.unmodifiable(remaining), newCurrent, _nextId);
  }

  /// 清空佇列。
  Queue clear() => Queue._(const [], null, _nextId);

  Queue _insert(int at, List<Track> tracks) {
    if (tracks.isEmpty) return this;
    final added = [
      for (var i = 0; i < tracks.length; i++)
        QueueEntry(_nextId + i, tracks[i]),
    ];
    final current = currentIndex;
    return Queue._(
      List.unmodifiable([...entries]..insertAll(at, added)),
      current == null ? at : (at <= current ? current + added.length : current),
      _nextId + added.length,
    );
  }

  @override
  String toString() => 'Queue($entries, current: $currentIndex)';
}
