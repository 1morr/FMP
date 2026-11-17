import 'package:fmp/domain/queue.dart';
import 'package:fmp/platform/form_factor.dart';

/// 佇列頁的四種版面（`docs/design/queue.html`）：手機與平板是觸控列表，
/// 桌面與窄視窗是表格。
enum QueueLayout {
  phone,
  tablet,
  wideTable,
  narrowTable;

  /// 寬度分級與密度對到版面：手機（< 600）與平板（medium＋觸控）用列表，
  /// 桌面（wide）與窄視窗（medium＋滑鼠）用表格。
  static QueueLayout of(FormFactor form) => switch (form.widthClass) {
    WidthClass.narrow => phone,
    WidthClass.medium => form.density == Density.touch ? tablet : narrowTable,
    WidthClass.wide => wideTable,
  };

  bool get isTable => this == wideTable || this == narrowTable;

  /// 列、「已播放」標題、摺線的固定高；列表要靠它算出捲動位置，所以都是定值。
  double get rowExtent => isTable ? 48 : 60;
  double get capExtent => isTable ? 28 : 38;
  double get foldExtent => isTable ? 42 : 44;

  /// 大標題那一塊的高在量到之前的估計，只用在第一個畫面。
  double get headEstimate => switch (this) {
    phone || tablet => 67,
    wideTable => 90,
    narrowTable => 112,
  };
}

/// 佇列頁列表裡的一項。曲目以外的（「已播放」標題、摺線）也在列表裡，
/// 才能讓曲目拖過它們。
sealed class QueueItem {
  const QueueItem();

  /// 目前佇列依播放順序排成的項目：已播放標題、播過的、正在播的、
  /// 摺線、接下來的。沒有播過的就沒有標題，沒有接下來的就沒有摺線；沒有
  /// 目前那首時全部都是播過的。
  static List<QueueItem> of(Queue queue) {
    final entries = queue.entries;
    final current = queue.currentIndex ?? entries.length;
    return [
      if (current > 0) PlayedCaption(current),
      for (var i = 0; i <= current && i < entries.length; i++)
        TrackItem(i, entries[i]),
      if (current < entries.length - 1)
        UpNextFold(
          entries.length - 1 - current,
          _total(entries.skip(current + 1)),
          shuffled: queue.shuffled,
        ),
      for (var i = current + 1; i < entries.length; i++)
        TrackItem(i, entries[i]),
    ];
  }

  static Duration _total(Iterable<QueueEntry> entries) => entries.fold(
    Duration.zero,
    (sum, entry) => sum + (entry.track.duration ?? Duration.zero),
  );

  double extent(QueueLayout layout) => switch (this) {
    PlayedCaption() => layout.capExtent,
    TrackItem() => layout.rowExtent,
    UpNextFold() => layout.foldExtent,
  };

  /// 全部曲目的時長加總；不知道時長的算 0。
  static Duration totalDuration(Queue queue) => _total(queue.entries);

  /// [items] 裡 [from] 的項目拖到 [to]（移走它之後的位置）時，那首曲目在
  /// 佇列裡的新位置：它前面有幾首曲目。
  static int entryIndexAfterReorder(List<QueueItem> items, int from, int to) {
    final moved = [...items];
    moved.insert(to, moved.removeAt(from));
    return moved.take(to).whereType<TrackItem>().length;
  }
}

/// 「已播放 n 首」。
class PlayedCaption extends QueueItem {
  const PlayedCaption(this.count);

  final int count;
}

/// 一首曲目在佇列裡的 [index] 位置。
class TrackItem extends QueueItem {
  const TrackItem(this.index, this.entry);

  final int index;
  final QueueEntry entry;
}

/// 摺線與「接下來」：[count] 首、共 [duration]；隨機時接下來的是隨機順序。
class UpNextFold extends QueueItem {
  const UpNextFold(this.count, this.duration, {required this.shuffled});

  final int count;
  final Duration duration;
  final bool shuffled;
}
