import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/equalizer.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/common/table_focus.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fmp/ui/common/motion.dart';

/// 播放數的短寫法，照目前的語言（萬、億或 K、M）。
String playCountText(BuildContext context, int count) {
  final units = switch (context.t.$meta.locale) {
    AppLocale.zhTw => ('萬', '億'),
    AppLocale.zhCn => ('万', '亿'),
    AppLocale.en => null,
  };
  return formatCount(count, chineseUnits: units);
}

/// 觸控列表的一列（`.row`，`docs/design/DESIGN.md`〈曲目列〉）：封面 48、
/// 曲名、音源符號＋簡稱 · 作者 · 播放數、時長、⋮。點一下臨時播放，長按進
/// 多選；多選時左邊是勾選圈，點一下加減選取。
///
/// 多 P 影片（[partCount] 不是 null）在簡稱後面標分 P 數，時長後面是展開
/// 箭頭（`search.html`〈B 站多 P 展開〉）；展開時整列帶淺底。
class SearchTouchRow extends ConsumerWidget {
  const SearchTouchRow({
    super.key,
    required this.track,
    required this.separator,
    required this.playing,
    required this.isCurrent,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    this.partCount,
    this.expanded = false,
    this.loadingParts = false,
    this.onToggleParts,
  });

  final Track track;

  /// 多 P 影片的分 P 數；不是多 P 影片時是 null。
  final int? partCount;
  final bool expanded;

  /// 展開了、分 P 還在列（箭頭換成轉圈）。
  final bool loadingParts;
  final VoidCallback? onToggleParts;

  /// 上緣畫 0.5 的分隔線（左縮 76）。
  final bool separator;

  /// 這首是目前的曲目；[playing] 是它正在出聲。
  final bool isCurrent;
  final bool playing;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// ⋮，帶按鈕的位置（全域座標，選單從那裡長出來）。
  final void Function(Offset at) onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.fmpColors;
    final t = context.t;
    final short = ref
        .watch(pluginManifestProvider(track.ref.pluginId))
        ?.mark
        ?.short;
    final rest = [
      track.author,
      if (track.playCount case final count?)
        t.search.plays(count: playCountText(context, count)),
    ];
    final sub = [?short, ...rest];
    final subStyle = TextStyle(
      fontSize: 13,
      height: 17 / 13,
      letterSpacing: 0,
      color: colors.label2,
    );
    return Semantics(
      selected: selecting ? selected : null,
      child: ShellButton(
        onTap: onTap,
        onLongPress: onLongPress,
        focusRadius: 10,
        focusInset: true,
        builder: (context, _) => Stack(
          children: [
            if (separator)
              Positioned(
                top: 0,
                left: selecting ? 112 : 76,
                right: 0,
                height: .5,
                child: ColoredBox(color: colors.sep),
              ),
            Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.only(left: 16, right: 6),
              color: expanded ? colors.fill : null,
              child: Row(
                children: [
                  if (selecting) ...[
                    _Check(on: selected),
                    const SizedBox(width: 12),
                  ],
                  Cover(
                    url: track.coverUrl,
                    size: 48,
                    radius: context.fmpMetrics.radii.thumbnail,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isCurrent) ...[
                              Equalizer(
                                playing: playing,
                                label: t.queue.nowPlaying,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 21 / 16,
                                  letterSpacing: 0,
                                  color: isCurrent
                                      ? colors.accent
                                      : colors.label,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : null,
                                ),
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
                            if (partCount case final count?) ...[
                              if (short != null) ...[
                                Text(short, style: subStyle),
                                const SizedBox(width: 6),
                              ],
                              PartBadge(count: count),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                (partCount == null ? sub : rest).join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: subStyle,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (track.duration case final duration?) ...[
                    const SizedBox(width: 12),
                    Text(
                      formatDuration(duration),
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 0,
                        color: colors.label3,
                      ).tabular,
                    ),
                  ],
                  if (partCount != null && !selecting)
                    PartsToggle(
                      expanded: expanded,
                      loading: loadingParts,
                      onTap: onToggleParts!,
                      touch: true,
                    ),
                  if (selecting)
                    const SizedBox(width: 10)
                  else
                    Builder(
                      builder: (context) => PlainIconButton(
                        icon: FmpIcons.more,
                        tooltip: t.queue.more,
                        size: 44,
                        focusable: true,
                        onTap: () => onMore(_anchorOf(context)),
                      ),
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

/// 按鈕右下角的全域座標：選單從那裡長出來。
Offset _anchorOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(box.size.bottomRight(Offset.zero));
}

/// 勾選圈（`.check`）：24，選了是強調色實心加勾。
class _Check extends StatelessWidget {
  const _Check({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? colors.accentFill : null,
        border: on ? null : Border.all(color: colors.label4, width: 1.6),
      ),
      alignment: Alignment.center,
      child: on
          ? FmpIcon(
              FmpIcons.check,
              size: 14,
              color: colors.accentInk,
              strokeWidth: 2.6,
            )
          : null,
    );
  }
}

/// 表格的欄（`.srh-th`、`.srh-tr`）：`# ｜標題／歌手｜音源｜播放數｜時長｜⋮`。
/// 稿的「存取」欄等存取等級做出來（M2）才加。窄視窗欄寬略減。
class SearchTableGrid extends StatelessWidget {
  const SearchTableGrid({
    super.key,
    required this.narrow,
    required this.number,
    required this.title,
    required this.source,
    required this.plays,
    required this.duration,
    required this.more,
    this.wrapMiddle,
  });

  final bool narrow;

  /// 包住序號與 ⋮ 之間的幾欄（列的雙擊只在這裡，序號的播放鈕與 ⋮ 點下
  /// 立刻反應，不等雙擊逾時）。
  final Widget Function(Widget middle)? wrapMiddle;
  final Widget number;
  final Widget title;
  final Widget source;
  final Widget plays;
  final Widget duration;
  final Widget more;

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(width: narrow ? 10 : 12);
    final middle = Row(
      children: [
        gap,
        Expanded(child: title),
        gap,
        SizedBox(width: narrow ? 80 : 88, child: source),
        gap,
        // 稿是播放數 66（窄 56）、時長 46；B 站有十幾小時的長片（14:23:26），
        // 時長欄挪 8 過來才放得下一行，兩欄總寬不變。
        SizedBox(width: narrow ? 48 : 58, child: plays),
        gap,
        SizedBox(width: 54, child: duration),
        gap,
      ],
    );
    return Row(
      children: [
        SizedBox(width: 26, child: number),
        Expanded(child: wrapMiddle?.call(middle) ?? middle),
        SizedBox(width: 28, child: more),
      ],
    );
  }
}

/// 表頭（`.srh-th`）：高 28，下緣細線。
class SearchTableHeader extends StatelessWidget {
  const SearchTableHeader({super.key, required this.narrow});

  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final t = context.t.search.columns;
    return Container(
      height: 28,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.sep, width: .5)),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: colors.label2,
        ),
        child: SearchTableGrid(
          narrow: narrow,
          number: const Text('#', textAlign: TextAlign.right),
          title: Text(t.titleArtist),
          source: Text(t.source),
          plays: Text(t.plays, textAlign: TextAlign.right),
          duration: Text(t.duration, textAlign: TextAlign.right),
          more: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// 表格的一列（`.srh-tr`）：高 50、圓角 8。按下就選取（⌘ 加減、⇧ 選一段，
/// 由 [onPointerDown] 判斷），雙擊或按序號位置的播放鈕臨時播放，右鍵或 ⋮
/// 開選單。滑過時序號變播放鈕，⋮ 只在滑過或選取時出現。
class SearchTableRow extends ConsumerStatefulWidget {
  const SearchTableRow({
    super.key,
    required this.track,
    required this.index,
    required this.narrow,
    required this.isCurrent,
    required this.playing,
    required this.selected,
    this.focused = false,
    this.menuAnchor,
    required this.joinAbove,
    required this.joinBelow,
    required this.onPointerDown,
    required this.onPlay,
    required this.onMenu,
    this.partCount,
    this.expanded = false,
    this.loadingParts = false,
    this.onToggleParts,
  });

  final Track track;

  /// 多 P 影片的分 P 數（標題前是展開箭頭、後面是分 P 數）；不是多 P 影片
  /// 時是 null。
  final int? partCount;
  final bool expanded;
  final bool loadingParts;
  final VoidCallback? onToggleParts;

  /// 在結果裡的位置（序號是它加 1）。
  final int index;
  final bool narrow;
  final bool isCurrent;
  final bool playing;
  final bool selected;

  /// 表格有鍵盤焦點、這列是選取的起點：畫焦點外框（`table_focus.dart`）。
  final bool focused;

  /// 鍵盤開選單時從這列的左下角長出來。
  final GlobalKey? menuAnchor;

  /// 上下也是選取的列：相接的那邊不圓角。
  final bool joinAbove;
  final bool joinBelow;
  final void Function(PointerDownEvent event) onPointerDown;
  final VoidCallback onPlay;

  /// 右鍵或 ⋮，帶選單的位置（全域座標）。
  final void Function(Offset at) onMenu;

  @override
  ConsumerState<SearchTableRow> createState() => _SearchTableRowState();
}

class _SearchTableRowState extends ConsumerState<SearchTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final t = context.t;
    final track = widget.track;
    final name = ref.watch(pluginManifestProvider(track.ref.pluginId))?.name;
    const r = Radius.circular(8);
    final small = TextStyle(
      fontSize: 12,
      letterSpacing: 0,
      color: colors.label2,
    );
    final Widget number;
    if (widget.isCurrent && !_hovered) {
      number = Equalizer(playing: widget.playing, label: t.queue.nowPlaying);
    } else if (_hovered) {
      number = ShellButton(
        onTap: widget.onPlay,
        tooltip: t.search.actions.play,
        label: t.search.actions.play,
        builder: (context, _) =>
            FmpIcon(FmpIcons.play, size: 15, color: colors.label),
      );
    } else {
      number = Text(
        '${widget.index + 1}',
        style: small.copyWith(color: colors.label3).tabular,
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & (kPrimaryButton | kSecondaryButton) != 0) {
            widget.onPointerDown(event);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 右鍵的偵測不給螢幕閱讀器一個點了沒反應的動作。
          excludeFromSemantics: true,
          onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
          child: FocusableTableRow(
            focused: widget.focused,
            radius: 8,
            anchorKey: widget.menuAnchor,
            onActivate: widget.onPlay,
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: widget.selected
                    ? colors.accentSoft
                    : _hovered
                    ? colors.cellHover
                    : null,
                borderRadius: BorderRadius.vertical(
                  top: widget.joinAbove ? Radius.zero : r,
                  bottom: widget.joinBelow ? Radius.zero : r,
                ),
              ),
              child: SearchTableGrid(
                narrow: widget.narrow,
                wrapMiddle: (middle) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: widget.onPlay,
                  child: middle,
                ),
                number: Align(alignment: Alignment.centerRight, child: number),
                title: Row(
                  children: [
                    Cover(
                      url: track.coverUrl,
                      size: 36,
                      radius: context.fmpMetrics.radii.thumbnail,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (widget.partCount != null) ...[
                                PartsToggle(
                                  expanded: widget.expanded,
                                  loading: widget.loadingParts,
                                  onTap: widget.onToggleParts!,
                                  touch: false,
                                ),
                                // 箭頭的點擊區右邊多 4，和曲名仍隔 6。
                                const SizedBox(width: 2),
                              ],
                              Flexible(
                                child: Text(
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
                                    fontWeight: widget.isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (widget.partCount case final count?) ...[
                                const SizedBox(width: 6),
                                PartBadge(count: count),
                              ],
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(
                            track.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: small.copyWith(height: 15 / 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                source: Row(
                  children: [
                    SourceMarkIcon(pluginId: track.ref.pluginId, size: 15),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        ref
                                .watch(
                                  pluginManifestProvider(track.ref.pluginId),
                                )
                                ?.mark
                                ?.short ??
                            name ??
                            '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small.copyWith(color: colors.label),
                      ),
                    ),
                  ],
                ),
                // 沒有播放數時寫「—」，不留白（`DESIGN.md`〈曲目列〉）。
                plays: Text(
                  track.playCount == null
                      ? '—'
                      : playCountText(context, track.playCount!),
                  textAlign: TextAlign.right,
                  style: small.tabular,
                ),
                duration: Text(
                  track.duration == null ? '' : formatDuration(track.duration!),
                  textAlign: TextAlign.right,
                  style: small.tabular,
                ),
                more: Opacity(
                  opacity: _hovered || widget.selected ? 1 : 0,
                  child: Builder(
                    builder: (context) => PlainIconButton(
                      icon: FmpIcons.more,
                      tooltip: t.queue.more,
                      size: 28,
                      // 選取的列 ⋮ 一直露出，Tab 從表格走得到、Enter 打開。
                      focusable: widget.selected,
                      onTap: () => widget.onMenu(_anchorOf(context)),
                    ),
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

/// 分 P 數（`.part`）：高 17、圓角 5 的灰底小標「3P」。
class PartBadge extends StatelessWidget {
  const PartBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Container(
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.fill2,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        context.t.search.parts.count(count: count),
        style: TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: colors.label2,
        ),
      ),
    );
  }
}

/// 展開、收起分 P 的箭頭：觸控列表在時長後面（`.c3`，20 的 ⌄／⌃），表格在
/// 標題前面（`.xp`，20 見方、圓角 6 的 ›／⌄）。展開後還在列分 P 時轉圈。
class PartsToggle extends StatelessWidget {
  const PartsToggle({
    super.key,
    required this.expanded,
    required this.loading,
    required this.onTap,
    required this.touch,
  });

  final bool expanded;
  final bool loading;
  final VoidCallback onTap;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final t = context.t.search.parts;
    final label = expanded ? t.collapse : t.expand;
    final size = touch ? 20.0 : 14.0;
    final Widget icon = loading
        ? Spinner(
            key: const Key('parts-spinner'),
            size: size - 4,
            strokeWidth: 1.8,
          )
        : FmpIcon(
            touch
                ? (expanded ? FmpIcons.chevU : FmpIcons.chevD)
                : (expanded ? FmpIcons.chevD : FmpIcons.chevR),
            size: size,
            strokeWidth: touch ? 1.8 : 2.2,
            color: touch ? colors.label3 : colors.label2,
          );
    final button = ShellButton(
      onTap: onTap,
      tooltip: label,
      label: label,
      focusRadius: touch ? 999 : 6,
      // 滑鼠的點擊區四周補到 28（`DESIGN.md`〈無障礙〉）。
      hitPadding: touch ? null : const EdgeInsets.all(4),
      builder: (context, hovered) => touch
          // 圖示 20，點擊區 44 見方（稿 32 寬，`DESIGN.md`〈無障礙〉）。
          ? SizedBox(width: 44, height: 44, child: Center(child: icon))
          : Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hovered ? colors.fill : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: icon,
            ),
    );
    if (touch) return button;
    // 表格的箭頭在列的雙擊範圍裡：一般的點擊要等雙擊逾時才算數，這裡按下
    // 就認領，點下立刻展開。鍵盤與螢幕閱讀器照舊走 ShellButton。
    return RawGestureDetector(
      gestures: {
        _EagerTap: GestureRecognizerFactoryWithHandlers<_EagerTap>(
          _EagerTap.new,
          (recognizer) => recognizer.onTap = onTap,
        ),
      },
      child: button,
    );
  }
}

/// 按下就贏得手勢競技場的點擊：和祖先的雙擊辨識器搶時不用等它逾時。
class _EagerTap extends TapGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// 觸控列表展開後的一個分 P（`.srh-part`）：高 48，縮排到標題（左 76），
/// 「P2」、分 P 標題（15）、時長、⋮。點一下只臨時播放這一段；多選時不能
/// 單獨勾選（設計稿〈更多與多選〉），點了沒反應。
class SearchPartTouchRow extends StatelessWidget {
  const SearchPartTouchRow({
    super.key,
    required this.part,
    required this.number,
    required this.isCurrent,
    required this.playing,
    required this.selecting,
    required this.onTap,
    required this.onMore,
  });

  final Track part;

  /// 第幾個分 P，從 1 起。
  final int number;
  final bool isCurrent;
  final bool playing;
  final bool selecting;
  final VoidCallback onTap;
  final void Function(Offset at) onMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final t = context.t;
    return ShellButton(
      onTap: selecting ? null : onTap,
      focusRadius: 10,
      focusInset: true,
      builder: (context, _) => Stack(
        children: [
          Positioned(
            top: 0,
            left: 76,
            right: 0,
            height: .5,
            child: ColoredBox(color: colors.sep),
          ),
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.only(left: 76, right: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    t.search.parts.number(n: number),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: colors.label3,
                    ).tabular,
                  ),
                ),
                const SizedBox(width: 12),
                if (isCurrent) ...[
                  Equalizer(playing: playing, label: t.queue.nowPlaying),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    part.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 21 / 15,
                      letterSpacing: 0,
                      color: isCurrent ? colors.accent : colors.label,
                      fontWeight: isCurrent ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (part.duration case final duration?) ...[
                  const SizedBox(width: 12),
                  Text(
                    formatDuration(duration),
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 0,
                      color: colors.label3,
                    ).tabular,
                  ),
                ],
                if (selecting)
                  const SizedBox(width: 10)
                else
                  Builder(
                    builder: (context) => PlainIconButton(
                      icon: FmpIcons.more,
                      tooltip: t.queue.more,
                      size: 44,
                      focusable: true,
                      onTap: () => onMore(_anchorOf(context)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 表格展開後的一個分 P（`.srh-tr.pt`）：高 34，序號欄空著，「P2」縮排到
/// 父列的展開箭頭下（左 46），再隔 10 是分 P 標題，最後是時長。雙擊只臨時播放這一段，
/// 右鍵或 ⋮ 開它自己的選單；分 P 不參與選取。
class SearchPartTableRow extends StatefulWidget {
  const SearchPartTableRow({
    super.key,
    required this.part,
    required this.number,
    required this.narrow,
    required this.isCurrent,
    required this.onPlay,
    required this.onMenu,
  });

  final Track part;
  final int number;
  final bool narrow;
  final bool isCurrent;
  final VoidCallback onPlay;
  final void Function(Offset at) onMenu;

  @override
  State<SearchPartTableRow> createState() => _SearchPartTableRowState();
}

class _SearchPartTableRowState extends State<SearchPartTableRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final t = context.t;
    final small = TextStyle(
      fontSize: 12,
      letterSpacing: 0,
      color: colors.label2,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered ? colors.cellHover : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SearchTableGrid(
            narrow: widget.narrow,
            wrapMiddle: (middle) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: widget.onPlay,
              child: middle,
            ),
            number: const SizedBox.shrink(),
            title: Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      t.search.parts.number(n: widget.number),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                        color: colors.label3,
                      ).tabular,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.part.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 0,
                        color: widget.isCurrent ? colors.accent : colors.label,
                        fontWeight: widget.isCurrent ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            source: const SizedBox.shrink(),
            plays: const SizedBox.shrink(),
            duration: Text(
              widget.part.duration == null
                  ? ''
                  : formatDuration(widget.part.duration!),
              textAlign: TextAlign.right,
              style: small.tabular,
            ),
            // 分 P 不參與選取，鍵盤靠 Tab 走到它的 ⋮ 開選單；有焦點時也露出。
            more: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              includeSemantics: false,
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: Opacity(
                opacity: _hovered || _focused ? 1 : 0,
                // 看不到時螢幕閱讀器照樣找得到這列的選單。
                alwaysIncludeSemantics: true,
                child: Builder(
                  builder: (context) => PlainIconButton(
                    icon: FmpIcons.more,
                    tooltip: t.queue.more,
                    size: 28,
                    focusable: true,
                    onTap: () => widget.onMenu(_anchorOf(context)),
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
