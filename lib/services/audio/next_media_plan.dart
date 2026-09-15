/// 前瞻媒體要怎麼改後端的播放清單。
///
/// 兩個後端的清單 API 不同（`removeAudioSourceAt` / `remove`），但要維持的不變
/// 量只有一個：**清單永遠是「當前項目 ＋ 最多一個前瞻」**。把那個不變量算成一
/// 份計畫，後端只負責照著呼叫自己的 API，`flutter test` 裡跑不起來的兩個引擎
/// 就不再各自持有一份「應該相同」的迴圈。
library;

/// 為了讓清單回到「當前項目 ＋ 最多一個前瞻」該做哪些事。
class NextMediaPlan {
  const NextMediaPlan._({
    required this.removeIndices,
    required this.shouldAppend,
  });

  /// 要移除的索引，**已經照套用順序排好**（由尾往前）。
  ///
  /// 順序有意義：每移一個索引就會位移，由尾往前才不必邊移邊重算。
  final List<int> removeIndices;

  /// 移完之後要不要追加新的前瞻項目。
  final bool shouldAppend;

  /// [itemCount] 是目前清單長度，[currentIndex] 是正在播的那一個，
  /// [hasMedia] 是呼叫端有沒有交出新的前瞻媒體（`setNextMedia(null)` 是清除）。
  ///
  /// 清單是空的就什麼都不做：沒有東西在播的話，也就沒有可以接上去的位置。
  factory NextMediaPlan.of({
    required int itemCount,
    required int currentIndex,
    required bool hasMedia,
  }) {
    if (itemCount <= 0) {
      return const NextMediaPlan._(removeIndices: [], shouldAppend: false);
    }
    return NextMediaPlan._(
      removeIndices: [
        for (var index = itemCount - 1; index > currentIndex; index--) index,
      ],
      shouldAppend: hasMedia,
    );
  }

  /// 剛剛播完、留在清單前面的那一個項目要不要移掉。
  ///
  /// 不移的話清單每首歌長一個項目，而兩個後端都設了「第二個項目立刻預備」，
  /// 代表每個留著的項目都是一條已經開著的連線。移完之後當前項目回到 index 0，
  /// 「下一首」永遠是 index 1。
  static bool shouldTrimPlayedEntry(int itemCount) => itemCount > 1;
}
