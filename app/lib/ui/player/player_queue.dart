import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/equalizer.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/now_playing/play_modes.dart';
import 'package:fmp/ui/queue/queue_rows.dart';
import 'package:material_ui/material_ui.dart';

/// 播放頁的佇列（`player.html` 的 `.pl-pq` 與 `.pl-dq`）：只列接下來的（佇列
/// 目前那首之後的，臨時播放時是要回去的那首之後的），順序和佇列頁一樣，可以
/// 拖動排序，點一首從它開始播；隨機與循環的文字切換鈕在標題列。移除、清空
/// 與播過的在佇列頁。[column] 是兩欄的右欄（`.pl-dq`）：多一列正在播放、
/// 「接下來」的摺線與底下的說明；否則是手機與平板直向左右滑的那一頁（`.pl-pq`）。
/// [touch] 是觸控的列（56 高、封面 48），否則是滑鼠的（48 高、封面 36）。
class PlayerQueue extends ConsumerWidget {
  const PlayerQueue({
    super.key,
    required this.column,
    required this.touch,
    this.bottomPadding = 0,
  });

  final bool column;
  final bool touch;

  /// 列表底下留白：手機的畫面下緣淡出（`mask`），最後一首要能捲上來。
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final colors = context.fmpColors;
    final queue = ref.watch(queueProvider);
    final controller = ref.read(queueProvider.notifier);
    final current = queue.currentIndex;
    // 沒有目前那首時（臨時播放回不去）剩下的都算播過。
    final base = current == null ? queue.entries.length : current + 1;
    final upcoming = queue.entries.sublist(base);
    final total = upcoming.fold(
      Duration.zero,
      (sum, entry) => sum + (entry.track.duration ?? Duration.zero),
    );
    final title = TextStyle(
      fontSize: column ? 12 : 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: colors.label,
    );
    final count = TextStyle(
      fontSize: column ? 12 : 13,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      color: colors.label2,
    );
    final head = Padding(
      padding: column
          ? const EdgeInsets.fromLTRB(12, 14, 12, 8)
          : const EdgeInsets.fromLTRB(24, 6, 20, 8),
      child: Row(
        children: [
          Text(column ? t.player.queue : t.queue.upNext, style: title),
          if (!column) ...[
            const SizedBox(width: 8),
            Text(t.queue.tracks(count: upcoming.length), style: count),
          ],
          const Spacer(),
          const PlayModeToggles(glass: false),
        ],
      ),
    );
    final now = queue.current;
    final header = !column
        ? head
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              head,
              if (ref.watch(temporaryPlayProvider) case final temporary?)
                _Row(track: temporary.track, touch: touch, playing: true)
              else if (now != null)
                _Row(track: now.track, touch: touch, playing: true),
              // `.qn`：上緣一條細線、「接下來 58 首 · 3 小時 58 分」。
              Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.sep, width: .5)),
                ),
                child: Row(
                  children: [
                    Text(t.queue.upNext, style: title),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        queueTotalText(t, upcoming.length, total),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: count,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: header),
        if (upcoming.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(column ? 12 : 24, 12, 12, 12),
              child: Text(
                t.player.nothingNext,
                style: TextStyle(
                  fontSize: column ? 12 : 14,
                  letterSpacing: 0,
                  color: colors.label3,
                ),
              ),
            ),
          )
        else
          SliverReorderableList(
            itemCount: upcoming.length,
            itemExtent: touch ? 56 : 48,
            proxyDecorator: (child, index, animation) =>
                queueLift(context, child),
            onReorderItem: (from, to) {
              if (from != to) controller.move(base + from, base + to);
            },
            itemBuilder: (context, i) => _Row(
              key: ValueKey(upcoming[i].id),
              track: upcoming[i].track,
              touch: touch,
              index: i,
              separator: !column && i > 0,
              inset: !column,
              onTap: () => controller.playAt(base + i),
            ),
          ),
        if (column)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                t.player.queueNote,
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0,
                  color: colors.label3,
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
      ],
    );
  }
}

/// 一首（`FMP.trackRow`，`more: false, drag: true`）：封面、曲名、音源符號
/// 與作者、時長、拖動把手。[playing] 是兩欄右欄頂端正在播放的那列（`.row.playing`：
/// 填色底、副標接「正在播放」，不能拖）。
class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.track,
    required this.touch,
    this.index,
    this.playing = false,
    this.separator = false,
    this.inset = false,
    this.onTap,
  });

  final Track track;
  final bool touch;

  /// 在可拖動的列表裡的位置；正在播放那列是 null。
  final int? index;
  final bool playing;
  final bool separator;

  /// 左右滑那一頁的列（`.pl-pq .row`）：左 24、右 20，沒有圓角。
  final bool inset;
  final VoidCallback? onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final touch = widget.touch;
    final track = widget.track;
    final index = widget.index;
    final cover = touch ? 48.0 : 36.0;
    final t1 = TextStyle(
      fontSize: touch ? 16 : 13,
      height: touch ? 21 / 16 : 17 / 13,
      letterSpacing: 0,
      fontWeight: widget.playing ? FontWeight.w600 : FontWeight.w400,
      color: colors.label,
    );
    final t2 = TextStyle(
      fontSize: touch ? 13 : 12,
      height: touch ? 17 / 13 : 15 / 12,
      letterSpacing: 0,
      color: colors.label2,
    );
    final author = widget.playing
        ? '${track.author} · ${t.queue.nowPlaying}'
        : track.author;
    Widget row = Row(
      children: [
        Cover(
          url: track.coverUrl,
          size: cover,
          radius: context.fmpMetrics.radii.thumbnail,
        ),
        SizedBox(width: touch ? 12 : 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.playing) ...[
                    Consumer(
                      builder: (context, ref, _) => Equalizer(
                        playing: ref.watch(
                          playbackProvider.select(
                            (state) => state?.playing ?? false,
                          ),
                        ),
                        label: t.queue.nowPlaying,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  SourceMarkIcon(
                    pluginId: track.ref.pluginId,
                    size: touch ? 15 : 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (track.duration case final duration?) ...[
          SizedBox(width: touch ? 12 : 10),
          Text(formatDuration(duration), style: t2.copyWith(height: 1).tabular),
        ],
        // 把手一直在（`player.html` 的 `drag: true`）。
        if (index != null)
          QueueDragHandle(
            flatIndex: index,
            width: touch ? 36 : 28,
            iconSize: touch ? 20 : 16,
            color: colors.label3,
          ),
      ],
    );
    if (index != null && touch) {
      row = ReorderableDelayedDragStartListener(index: index, child: row);
    }
    final background = widget.playing
        ? colors.fill
        : _hovered && !touch
        ? colors.cellHover
        : null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      child: Semantics(
        button: widget.onTap != null,
        label: widget.onTap == null ? null : t.queue.playFromHere,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: touch ? 56 : 48,
            padding: widget.inset
                ? const EdgeInsets.only(left: 24, right: 14)
                : const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(
              color: background,
              borderRadius: widget.inset ? null : BorderRadius.circular(8),
              border: widget.separator
                  ? Border(top: BorderSide(color: colors.sep, width: .5))
                  : null,
            ),
            child: row,
          ),
        ),
      ),
    );
  }
}
