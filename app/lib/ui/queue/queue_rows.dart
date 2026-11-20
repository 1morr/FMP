import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/equalizer.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/common/table_focus.dart';
import 'package:fmp/ui/now_playing/play_modes.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 「n 首」或「n 首 · 4 小時 37 分」；不知道任何時長時只寫首數。
String queueTotalText(Translations t, int count, Duration duration) {
  final tracks = t.queue.tracks(count: count);
  if (duration == Duration.zero) return tracks;
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final text = hours > 0
      ? t.queue.duration.hoursMinutes(hours: hours, minutes: minutes)
      : t.queue.duration.minutes(minutes: minutes);
  return '$tracks · $text';
}

const _dimOpacity = .45;

/// 作者，臨時播放時要回去的那一列再接「 · 回來時從 1:26 繼續」（`.qu-ret`：
/// 強調色、600）。
InlineSpan _authorWithNote(BuildContext context, String author, String? note) =>
    TextSpan(
      text: author,
      children: [
        if (note != null) ...[
          const TextSpan(text: ' · '),
          TextSpan(
            text: note,
            style: TextStyle(
              color: context.fmpColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );

/// 觸控列表的一列（`.row`＋`quRow`）：封面、曲名、音源符號與作者、時長、
/// ×、拖動把手。點整列從這首開始播；長按整列（除了 ×）也能拖。
class QueueTouchRow extends StatelessWidget {
  const QueueTouchRow({
    super.key,
    required this.entry,
    required this.flatIndex,
    required this.isCurrent,
    required this.dimmed,
    required this.separator,
    required this.playing,
    required this.onPlay,
    required this.onRemove,
    this.returnNote,
  });

  final QueueEntry entry;

  /// 臨時播放時要回去的那一列，副標在作者後面寫「回來時從 1:26 繼續」。
  final String? returnNote;

  /// 在列表裡的位置，拖動排序用。
  final int flatIndex;
  final bool isCurrent;

  /// 播過的：45% 透明。
  final bool dimmed;

  /// 上緣畫 0.5 的分隔線。
  final bool separator;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final text = context.fmpText;
    final track = entry.track;
    final dim = dimmed ? _dimOpacity : 1.0;
    final titleStyle = text.callout.copyWith(
      color: isCurrent ? colors.accent : colors.label,
      fontWeight: isCurrent ? FontWeight.w600 : null,
    );
    return ShellButton(
      onTap: onPlay,
      focusRadius: 10,
      focusInset: true,
      builder: (context, _) => Container(
        color: isCurrent ? colors.accentSoft : null,
        child: Stack(
          children: [
            if (separator)
              Positioned(
                top: 0,
                left: 76,
                right: 0,
                height: .5,
                child: ColoredBox(color: colors.sep),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 10),
              child: Row(
                children: [
                  Expanded(
                    child: ReorderableDelayedDragStartListener(
                      index: flatIndex,
                      child: Row(
                        children: [
                          Opacity(
                            opacity: dim,
                            child: Cover(
                              url: track.coverUrl,
                              size: context.fmpMetrics.thumbnailSize,
                              radius: context.fmpMetrics.radii.thumbnail,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Opacity(
                              opacity: dim,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (isCurrent) ...[
                                        Equalizer(
                                          playing: playing,
                                          label: context.t.queue.nowPlaying,
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Expanded(
                                        child: Text(
                                          track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: titleStyle,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      SourceMarkIcon(
                                        pluginId: track.ref.pluginId,
                                        size: 15,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text.rich(
                                          _authorWithNote(
                                            context,
                                            track.author,
                                            returnNote,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: text.foot.copyWith(
                                            color: colors.label2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (track.duration case final duration?)
                            Text(
                              formatDuration(duration),
                              style: text.foot.tabular.copyWith(
                                color: colors.label3,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  ShellButton(
                    key: const Key('queue-remove'),
                    onTap: onRemove,
                    label: context.t.queue.remove,
                    focusRadius: 999,
                    // 稿是 40 寬，點擊區補到 44（`DESIGN.md`〈無障礙〉）。
                    builder: (context, hovered) => SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: FmpIcon(
                          FmpIcons.close,
                          size: 18,
                          color: hovered ? colors.label : colors.label3,
                        ),
                      ),
                    ),
                  ),
                  QueueDragHandle(
                    flatIndex: flatIndex,
                    width: 28,
                    iconSize: 20,
                    color: colors.label3,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 拖動把手（`drag` 圖示）：按住就能拖，螢幕閱讀器讀「拖動調整順序」。
class QueueDragHandle extends StatelessWidget {
  const QueueDragHandle({
    super.key,
    required this.flatIndex,
    required this.width,
    required this.iconSize,
    required this.color,
  });

  final int flatIndex;
  final double width;
  final double iconSize;
  final Color color;

  @override
  Widget build(BuildContext context) => ReorderableDragStartListener(
    index: flatIndex,
    child: MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Semantics(
        label: context.t.queue.dragHandle,
        child: SizedBox(
          width: width,
          height: 44,
          child: Center(
            child: FmpIcon(FmpIcons.drag, size: iconSize, color: color),
          ),
        ),
      ),
    ),
  );
}

/// 表格的欄寬（`.qu-tr`）：`26 36 1fr 112 48 66`，欄距 10。
class _TableGrid extends StatelessWidget {
  const _TableGrid({
    required this.number,
    required this.cover,
    required this.meta,
    required this.source,
    required this.duration,
    required this.actions,
  });

  final Widget number;
  final Widget cover;
  final Widget meta;
  final Widget source;
  final Widget duration;
  final Widget actions;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 26, child: number),
      const SizedBox(width: 10),
      SizedBox(width: 36, child: cover),
      const SizedBox(width: 10),
      Expanded(child: meta),
      const SizedBox(width: 10),
      SizedBox(width: 112, child: source),
      const SizedBox(width: 10),
      SizedBox(width: 48, child: duration),
      const SizedBox(width: 10),
      SizedBox(width: 66, child: actions),
    ],
  );
}

/// 表頭列（`.qu-th-row`）：`# ｜（縮圖）｜曲目｜音源｜時長｜（動作）`。
class QueueTableHeader extends StatelessWidget {
  const QueueTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final t = context.t.queue;
    final style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: colors.label3,
      letterSpacing: 0,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.sep, width: .5)),
      ),
      child: DefaultTextStyle(
        style: style,
        child: _TableGrid(
          number: const Text('#', textAlign: TextAlign.right),
          cover: const SizedBox.shrink(),
          meta: Text(t.columns.track),
          source: Text(t.columns.source),
          duration: Text(t.columns.duration, textAlign: TextAlign.right),
          actions: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// 表格的一列（`.qu-tr`）。單擊選取、雙擊播放、右鍵開選單；滑過時才出現
/// × 與拖動把手。
class QueueTableRow extends ConsumerStatefulWidget {
  const QueueTableRow({
    super.key,
    required this.entry,
    required this.index,
    required this.flatIndex,
    required this.isCurrent,
    required this.dimmed,
    required this.selected,
    required this.playing,
    required this.onSelect,
    required this.onPlay,
    required this.onRemove,
    required this.onMenu,
    this.focused = false,
    this.menuAnchor,
    this.returnNote,
  });

  /// 表格有鍵盤焦點、選取的是這列：畫焦點外框（`table_focus.dart`）。
  final bool focused;

  /// 鍵盤開選單時從這列的左下角長出來。
  final GlobalKey? menuAnchor;

  final QueueEntry entry;

  /// 臨時播放時要回去的那一列，副標在作者後面寫「回來時從 1:26 繼續」。
  final String? returnNote;

  /// 在佇列裡的位置（編號是它加 1）。
  final int index;
  final int flatIndex;
  final bool isCurrent;
  final bool dimmed;
  final bool selected;
  final bool playing;
  final VoidCallback onSelect;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  /// 右鍵，帶螢幕座標。
  final void Function(Offset position) onMenu;

  @override
  ConsumerState<QueueTableRow> createState() => _QueueTableRowState();
}

class _QueueTableRowState extends ConsumerState<QueueTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final track = widget.entry.track;
    final dim = widget.dimmed ? _dimOpacity : 1.0;
    final sourceName = ref
        .watch(pluginManifestProvider(track.ref.pluginId))
        ?.name;
    final background = widget.isCurrent || widget.selected
        ? colors.accentSoft
        : _hovered
        ? colors.cellHover
        : null;
    // 選取的列一直露出操作，不必滑鼠移上去。
    final showActions = _hovered || widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        // 按下就選取：不等雙擊的判定。
        onPointerDown: (event) {
          if (event.buttons & kPrimaryButton != 0 ||
              event.buttons & kSecondaryButton != 0) {
            widget.onSelect();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 右鍵的偵測不給螢幕閱讀器一個點了沒反應的動作。
          excludeFromSemantics: true,
          onDoubleTap: widget.onPlay,
          onSecondaryTapDown: (details) =>
              widget.onMenu(details.globalPosition),
          child: FocusableTableRow(
            focused: widget.focused,
            radius: 8,
            anchorKey: widget.menuAnchor,
            onActivate: widget.onPlay,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
              ),
              foregroundDecoration: widget.selected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.accent, width: 1.5),
                    )
                  : null,
              child: _TableGrid(
                number: Align(
                  alignment: Alignment.centerRight,
                  child: widget.isCurrent
                      ? Equalizer(
                          playing: widget.playing,
                          label: context.t.queue.nowPlaying,
                        )
                      : Text(
                          '${widget.index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.label3,
                            letterSpacing: 0,
                          ).tabular,
                        ),
                ),
                cover: Opacity(
                  opacity: dim,
                  child: Cover(
                    url: track.coverUrl,
                    size: 36,
                    radius: context.fmpMetrics.radii.thumbnail,
                  ),
                ),
                meta: Opacity(
                  opacity: dim,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 17 / 13,
                          letterSpacing: 0,
                          color: widget.isCurrent
                              ? colors.accent
                              : colors.label,
                          fontWeight: widget.isCurrent ? FontWeight.w600 : null,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text.rich(
                        _authorWithNote(
                          context,
                          track.author,
                          widget.returnNote,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 15 / 12,
                          letterSpacing: 0,
                          color: colors.label2,
                        ),
                      ),
                    ],
                  ),
                ),
                source: Opacity(
                  opacity: dim,
                  child: Row(
                    children: [
                      SourceMarkIcon(pluginId: track.ref.pluginId, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          sourceName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0,
                            color: colors.label2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                duration: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    track.duration == null
                        ? ''
                        : formatDuration(track.duration!),
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0,
                      color: colors.label3,
                    ).tabular,
                  ),
                ),
                actions: AnimatedOpacity(
                  opacity: showActions ? 1 : 0,
                  duration: FmpMotion.fast,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PlainIconButton(
                        icon: FmpIcons.close,
                        tooltip: context.t.queue.remove,
                        onTap: widget.onRemove,
                        size: 28,
                      ),
                      const SizedBox(width: 2),
                      QueueDragHandle(
                        flatIndex: widget.flatIndex,
                        width: 26,
                        iconSize: 16,
                        color: colors.label3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「已播放 n 首」。
class QueueCaption extends StatelessWidget {
  const QueueCaption({super.key, required this.count, required this.table});

  final int count;
  final bool table;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final text = context.t.queue.played(count: count);
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: table
            ? const EdgeInsets.fromLTRB(10, 10, 10, 0)
            : const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Text(
          text,
          style: table
              ? TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.label3,
                  letterSpacing: 0,
                )
              : context.fmpText.foot.copyWith(color: colors.label2),
        ),
      ),
    );
  }
}

/// 摺線與「接下來　n 首 · 時長」（`.qu-fold`）：上緣 1px `--sep-strong`。
class QueueFold extends StatelessWidget {
  const QueueFold({
    super.key,
    required this.count,
    required this.duration,
    required this.shuffled,
    required this.table,
  });

  final int count;
  final Duration duration;

  /// 隨機時寫「隨機順序 · n 首 · 時長」。
  final bool shuffled;
  final bool table;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final t = context.t;
    final size = table ? 12.0 : 13.0;
    return Padding(
      padding: EdgeInsets.only(top: table ? 6 : 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.sepStrong)),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: table
                ? const EdgeInsets.fromLTRB(10, 14, 10, 0)
                : const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  t.queue.upNext,
                  style: TextStyle(
                    fontSize: size,
                    height: 18 / 13,
                    fontWeight: FontWeight.w700,
                    color: colors.label,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  [
                    if (shuffled) t.queue.shuffledOrder,
                    queueTotalText(t, count, duration),
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: size,
                    height: 18 / 13,
                    color: colors.label2,
                    letterSpacing: 0,
                  ).tabular,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 空佇列（`.qu-empty`）：圖示、說明、「去搜尋」與「打開音樂庫」。
class QueueEmpty extends StatelessWidget {
  const QueueEmpty({
    super.key,
    required this.onSearch,
    required this.onLibrary,
  });

  final VoidCallback onSearch;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final text = context.fmpText;
    final t = context.t.queue.empty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: colors.fill,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: FmpIcon(
              FmpIcons.queue,
              size: 34,
              strokeWidth: 1.6,
              color: colors.label2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.title,
            textAlign: TextAlign.center,
            style: text.title3.copyWith(color: colors.label),
          ),
          const SizedBox(height: 8),
          Text(
            t.body,
            textAlign: TextAlign.center,
            style: text.sub.copyWith(color: colors.label2),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FmpButton(
                  label: t.search,
                  icon: FmpIcons.search,
                  variant: FmpButtonVariant.primary,
                  onTap: onSearch,
                ),
                const SizedBox(height: 10),
                FmpButton(label: t.library, onTap: onLibrary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 拖起來的列（`.qu-lift`）：左右縮 8、圓角 14、`--cell-2` 底、浮起的陰影、
/// 放大 1.02。
Widget queueLift(BuildContext context, Widget child) {
  final colors = context.fmpColors;
  return Material(
    type: MaterialType.transparency,
    child: Transform.scale(
      scale: 1.02,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colors.cell2,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, .25),
              blurRadius: 30,
              offset: Offset(0, 10),
            ),
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, .15),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

/// 表格頭上的快捷鍵提示（`.qu-keys`）：「拖動或 ⌥↑ ⌥↓ 調整順序 · Delete 移除
/// · ⏎ 播放」。修飾鍵的寫法由 `platform/` 給。
class QueueKeyHints extends StatelessWidget {
  const QueueKeyHints({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final hints = context.t.queue.hints;
    final alt = WindowChrome.altKeyLabel;
    final style = TextStyle(
      fontSize: 11.5,
      color: colors.label3,
      letterSpacing: 0,
    );
    Widget kbd(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: colors.label2,
          letterSpacing: 0,
        ),
      ),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Text(hints.dragOr, style: style),
        kbd('$alt↑'),
        kbd('$alt↓'),
        Text('${hints.reorder} ·', style: style),
        kbd('Delete'),
        Text('${hints.remove} ·', style: style),
        kbd(WindowChrome.enterKeyLabel),
        Text(hints.play, style: style),
      ],
    );
  }
}

/// 列表最後一行（`.qu-end`）：照循環說最後一首播完會怎樣。
class QueueEndNote extends StatelessWidget {
  const QueueEndNote({
    super.key,
    required this.repeat,
    required this.shuffled,
    required this.table,
  });

  final Repeat repeat;
  final bool shuffled;
  final bool table;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final end = context.t.queue.end;
    final text = switch (repeat) {
      Repeat.off => end.off,
      Repeat.all => shuffled ? end.allShuffled : end.all,
      Repeat.one => end.one,
    };
    return Padding(
      padding: table
          ? const EdgeInsets.fromLTRB(10, 16, 10, 0)
          : const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        children: [
          FmpIcon(repeatIcon(repeat), size: 16, color: colors.label3),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 18 / 13,
                color: colors.label3,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
