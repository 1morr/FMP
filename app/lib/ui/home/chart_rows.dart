import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/search/parts.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/equalizer.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/search/search_rows.dart' show PartBadge;
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:fmp/ui/common/table_focus.dart';
import 'package:material_ui/material_ui.dart';

/// 首頁觸控列表的一列（`docs/design/home.html` 的 `.row`）：名次（[rank]，
/// 不是排行榜的列給 null）、封面 48、曲名、音源符號＋分 P 數＋作者、時長、
/// ⋮。點一下由 [onTap] 決定（排行榜是臨時播放，繼續聽是從那首播）。
///
/// 多 P 影片標分 P 數、不放展開箭頭（2026-11-20 擁有者同意）。
class HomeTouchRow extends ConsumerWidget {
  const HomeTouchRow({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.playing,
    required this.separator,
    required this.onTap,
    required this.onMore,
    this.rank,
    this.showDuration = true,
  });

  final Track track;

  /// 排行榜的名次（從 1 起）；有名次時左邊多一欄，分隔線左縮 108。
  final int? rank;

  /// 這首是目前的曲目；[playing] 是它正在出聲。
  final bool isCurrent;
  final bool playing;

  /// 上緣畫 0.5 的分隔線。
  final bool separator;

  /// 平板直向兩欄時不放時長，讓曲名有位置（設計稿〈待確認〉34）。
  final bool showDuration;
  final VoidCallback onTap;

  /// ⋮，帶按鈕的位置（全域座標，選單從那裡長出來）。
  final void Function(Offset at) onMore;

  /// 有名次時的分隔線左縮：16 + 名次 20 + 12 + 封面 48 + 12。
  static const rankedInset = 108.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.fmpColors;
    final t = context.t;
    final manifest = ref.watch(pluginManifestProvider(track.ref.pluginId));
    final parts = hasParts(track, manifest) ? track.partCount : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        children: [
          if (separator)
            Positioned(
              top: 0,
              left: rank == null ? 76 : rankedInset,
              right: 0,
              height: .5,
              child: ColoredBox(color: colors.sep),
            ),
          Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.only(left: 16, right: 6),
            child: Row(
              children: [
                if (rank case final rank?) ...[
                  SizedBox(
                    width: 20,
                    child: Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                        color: colors.label2,
                      ).tabular,
                    ),
                  ),
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
                                color: isCurrent ? colors.accent : colors.label,
                                fontWeight: isCurrent ? FontWeight.w600 : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      TrackSubLine(track: track, parts: parts, desk: false),
                    ],
                  ),
                ),
                if (showDuration && track.duration != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    formatDuration(track.duration!),
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 0,
                      color: colors.label3,
                    ).tabular,
                  ),
                ],
                Builder(
                  builder: (context) => PlainIconButton(
                    icon: FmpIcons.more,
                    tooltip: t.queue.more,
                    size: 44,
                    focusable: true,
                    onTap: () => onMore(anchorOf(context)),
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

/// 曲目列的第二行：音源符號、分 P 數（[parts]，不是多 P 影片時 null）、作者。
class TrackSubLine extends StatelessWidget {
  const TrackSubLine({
    super.key,
    required this.track,
    required this.parts,
    required this.desk,
  });

  final Track track;
  final int? parts;
  final bool desk;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Row(
      children: [
        SourceMarkIcon(pluginId: track.ref.pluginId, size: desk ? 14 : 15),
        SizedBox(width: desk ? 5 : 6),
        if (parts case final count?) ...[
          PartBadge(count: count),
          SizedBox(width: desk ? 5 : 6),
        ],
        Expanded(
          child: Text(
            track.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: desk ? 12 : 13,
              height: desk ? 15 / 12 : 17 / 13,
              letterSpacing: 0,
              color: colors.label2,
            ),
          ),
        ),
      ],
    );
  }
}

/// 按鈕右下角的全域座標：選單從那裡長出來。
Offset anchorOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(box.size.bottomRight(Offset.zero));
}

/// 桌面與窄視窗的排行榜一列（`.hm-dr`）：名次 14、封面 32、曲名＋音源符號
/// ＋作者，欄夠寬（[showDuration]）時尾端有時長。單擊選取、雙擊播放
/// （設計稿〈待確認〉1）；滑過時名次變播放鈕、尾端浮出 ⋮；右鍵與 ⋮ 開同一個
/// 選單。
class ChartDeskRow extends ConsumerStatefulWidget {
  const ChartDeskRow({
    super.key,
    required this.track,
    required this.rank,
    required this.isCurrent,
    required this.playing,
    required this.selected,
    required this.showDuration,
    required this.onSelect,
    required this.onPlay,
    required this.onMenu,
    this.menuAnchor,
    this.focused = false,
  });

  final Track track;
  final int rank;
  final bool isCurrent;
  final bool playing;
  final bool selected;
  final bool showDuration;
  final VoidCallback onSelect;
  final VoidCallback onPlay;
  final void Function(Offset at) onMenu;

  /// 鍵盤開選單（Shift+F10、選單鍵）時從這列的左下角長出來
  /// （`table_focus.dart`）。
  final GlobalKey? menuAnchor;

  /// 榜有鍵盤焦點、選取的是這列：畫焦點外框。
  final bool focused;

  /// 欄寬到這裡才放時長（`.hm-col` 的 container query）。
  static const durationFrom = 280.0;

  @override
  ConsumerState<ChartDeskRow> createState() => _ChartDeskRowState();
}

class _ChartDeskRowState extends ConsumerState<ChartDeskRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final t = context.t;
    final track = widget.track;
    final manifest = ref.watch(pluginManifestProvider(track.ref.pluginId));
    final parts = hasParts(track, manifest) ? track.partCount : null;
    final Widget lead;
    if (_hovered) {
      // 滑鼠目標 28（`DESIGN.md`〈無障礙〉），比名次欄寬，往左凸出。
      lead = ShellButton(
        onTap: widget.onPlay,
        tooltip: t.search.actions.play,
        label: t.search.actions.play,
        focusRadius: 6,
        builder: (context, _) => SizedBox.square(
          dimension: 28,
          child: Align(
            alignment: Alignment.centerRight,
            child: FmpIcon(FmpIcons.play, size: 15, color: colors.label),
          ),
        ),
      );
    } else if (widget.isCurrent) {
      lead = Equalizer(playing: widget.playing, label: t.queue.nowPlaying);
    } else {
      lead = Text(
        '${widget.rank}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: colors.label3,
        ).tabular,
      );
    }
    final background = widget.selected
        ? colors.accentSoft
        : _hovered
        ? colors.cellHover
        : null;
    // ⋮ 底下的實心色：列的底色疊在頁面底色上，半透明的選取色也蓋得住時長。
    final cover = Color.alphaBlend(background ?? colors.cellHover, colors.bg);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & (kPrimaryButton | kSecondaryButton) != 0) {
            widget.onSelect();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: widget.onPlay,
          excludeFromSemantics: true,
          onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
          child: Semantics(
            selected: widget.selected,
            child: FocusableTableRow(
              focused: widget.focused,
              radius: 8,
              anchorKey: widget.menuAnchor,
              onActivate: widget.onPlay,
              child: Container(
                height: 46,
                padding: const EdgeInsets.only(left: 4, right: 6),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    Row(
                      children: [
                        // 名次靠右；兩位數比 14 寬時往左凸出，同稿的 grid。
                        SizedBox(
                          width: 14,
                          child: OverflowBox(
                            maxWidth: 28,
                            maxHeight: 28,
                            alignment: Alignment.centerRight,
                            child: lead,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Cover(
                          url: track.coverUrl,
                          size: 32,
                          radius: context.fmpMetrics.radii.thumbnail,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
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
                                  fontWeight: widget.isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 1),
                              TrackSubLine(
                                track: track,
                                parts: parts,
                                desk: true,
                              ),
                            ],
                          ),
                        ),
                        if (widget.showDuration) ...[
                          const SizedBox(width: 9),
                          SizedBox(
                            width: 36,
                            child: Text(
                              track.duration == null
                                  ? ''
                                  : formatDuration(track.duration!),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 12,
                                letterSpacing: 0,
                                color: colors.label3,
                              ).tabular,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // ⋮ 只在滑過時浮在列尾（蓋住時長），曲名的寬度不變；左邊
                    // 12 漸層接列的底色，時長整個被蓋住。
                    if (_hovered || widget.selected)
                      Positioned(
                        right: -4,
                        top: 9,
                        child: Container(
                          padding: const EdgeInsets.only(left: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [cover.withValues(alpha: 0), cover],
                              stops: const [0, 12 / 40],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Builder(
                            builder: (context) => PlainIconButton(
                              icon: FmpIcons.more,
                              tooltip: t.queue.more,
                              size: 28,
                              focusable: true,
                              onTap: () => widget.onMenu(anchorOf(context)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 載入中的骨架列（`.hm-sk`）：名次先出現，封面與兩行字是灰塊。
class ChartSkeletonRow extends StatelessWidget {
  const ChartSkeletonRow({super.key, required this.rank, required this.desk});

  final int rank;
  final bool desk;

  static const _widths = [.72, .55, .80, .62, .68];

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final w = _widths[(rank - 1) % _widths.length];
    Widget bar(double height, double factor) => FractionallySizedBox(
      widthFactor: factor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
    final cover = desk ? 32.0 : 48.0;
    return Container(
      height: desk ? 46 : 60,
      padding: desk
          ? const EdgeInsets.only(left: 4, right: 6)
          : const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: desk ? 14 : 20,
            child: OverflowBox(
              maxWidth: 30,
              alignment: desk ? Alignment.centerRight : Alignment.center,
              child: Text(
                '$rank',
                textAlign: desk ? TextAlign.right : TextAlign.center,
                style: TextStyle(
                  fontSize: desk ? 12 : 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  color: colors.label4,
                ).tabular,
              ),
            ),
          ),
          SizedBox(width: desk ? 9 : 12),
          Container(
            width: cover,
            height: cover,
            decoration: BoxDecoration(
              color: colors.fill,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          SizedBox(width: desk ? 9 : 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(desk ? 11 : 13, w),
                SizedBox(height: desk ? 6 : 7),
                bar(desk ? 9 : 10, w - .30),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 手機的「顯示第 6–10 名」／「收起」（`.hm-more`）：整列寬、高 48，字從
/// 左縮 108 開始，上緣一條同樣左縮的分隔線。
class ChartMoreRow extends StatelessWidget {
  const ChartMoreRow({
    super.key,
    required this.expanded,
    required this.count,
    required this.onTap,
  });

  final bool expanded;

  /// 榜上有幾名：「顯示第 6–[count] 名」。
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final t = context.t.home;
    final label = expanded ? t.showLess : t.showMore(from: 6, to: count);
    return ShellButton(
      onTap: onTap,
      label: label,
      focusRadius: 0,
      builder: (context, hovered) => Stack(
        children: [
          Positioned(
            top: 0,
            left: HomeTouchRow.rankedInset,
            right: 0,
            height: .5,
            child: ColoredBox(color: colors.sep),
          ),
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            color: hovered ? colors.cellHover : null,
            padding: const EdgeInsets.only(
              left: HomeTouchRow.rankedInset,
              right: 16,
            ),
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    color: colors.label2,
                  ),
                ),
                const SizedBox(width: 4),
                FmpIcon(
                  expanded ? FmpIcons.chevU : FmpIcons.chevD,
                  size: 16,
                  strokeWidth: 2.2,
                  color: colors.label2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
