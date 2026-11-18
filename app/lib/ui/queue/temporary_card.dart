import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/temporary_play.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/equalizer.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/now_playing/now_playing.dart';
import 'package:material_ui/material_ui.dart';

/// 佇列頁的「臨時播放」卡片（`docs/design/queue.html`：觸控 `.qu-temp`、表格
/// `.qu-dtemp`）：插在要回去的那首上方，寫明回到哪裡、從哪裡繼續，兩個動作
/// 「現在回到佇列」「下一首播放」。佇列沒有目前那首（回不去）時不寫回去的
/// 地方、沒有「現在回到佇列」。
///
/// 列表的每一項都是定高（捲動位置靠加總算），所以卡片的高由 [extent] 依寬度
/// 量出回去那行字的行數算出來。
class QueueTemporaryCard extends ConsumerWidget {
  const QueueTemporaryCard({
    super.key,
    required this.temporary,
    required this.returnTo,
    required this.returnIndex,
    required this.table,
  });

  final TemporaryPlay temporary;

  /// 要回去的佇列位置；沒有時是 null。
  final QueueEntry? returnTo;

  /// [returnTo] 在佇列裡的位置（第幾首是它加 1）。
  final int? returnIndex;
  final bool table;

  /// 回去那行字最多幾行。
  static const _maxLines = 4;

  /// 卡片（含上下外距）的高。[width] 是列表的寬。卡片裡可變高的部分（標頭、
  /// 回去那行字）畫的時候也照這裡的數字包成固定高，真字型的行高和量的差一點
  /// 也不會溢出。
  static double extent(
    BuildContext context, {
    required bool table,
    required double width,
    required InlineSpan? returnText,
  }) {
    final lines = returnText == null
        ? 0
        : _lines(context, returnText, _textWidth(width, table: table), table);
    final returnBlock = lines == 0
        ? 0.0
        : _returnGap(table) + _lineHeight(table) * lines;
    if (table) {
      // 外距 6/8、內距 10/12；標頭＋6、曲目 44、回去那行。
      return 6 +
          10 +
          _headerHeight(context, table) +
          6 +
          44 +
          returnBlock +
          12 +
          8;
    }
    // 外距 10/12、內距 12/12；標頭＋4、曲目 60、回去那行、動作 10＋按鈕。
    return 10 +
        12 +
        _headerHeight(context, table) +
        4 +
        60 +
        returnBlock +
        10 +
        _buttonHeight(context) +
        12 +
        12;
  }

  /// `.btn-sm` 的高：觸控 32、滑鼠 28（[FmpButton]）。
  static double _buttonHeight(BuildContext context) =>
      FormFactor.of(context).density == Density.touch ? 32 : 28;

  /// 標頭那一列的高：表格版和按鈕同一列。
  static double _headerHeight(BuildContext context, bool table) =>
      table ? math.max(_buttonHeight(context), 18) : 18;

  static double _lineHeight(bool table) => table ? 16 : 18;

  /// 回去那行字上面的間距。
  static double _returnGap(bool table) => table ? 8 : 4;

  /// 回去那行字可用的寬：扣掉外距、內距、箭頭與間距。
  static double _textWidth(double width, {required bool table}) =>
      table ? width - 24 - 14 - 6 : width - 24 - 28 - 16 - 10;

  static int _lines(
    BuildContext context,
    InlineSpan text,
    double width,
    bool table,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.merge(_returnStyle(table)),
        children: [text],
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: _maxLines,
    )..layout(maxWidth: math.max(1, width));
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines.clamp(1, _maxLines);
  }

  static TextStyle _returnStyle(bool table) => TextStyle(
    fontSize: table ? 12 : 13,
    height: table ? 16 / 12 : 18 / 13,
    letterSpacing: 0,
  );

  /// 「播完或切歌後回到下方第 6 首「夜行列車」，從 1:26 繼續（倒退 10 秒）」；
  /// 第幾首以外的參數粗體。沒有回去的地方是 null。
  static InlineSpan? returnText(
    BuildContext context, {
    required bool table,
    required QueueEntry? returnTo,
    required int? returnIndex,
    required Duration resumeAt,
    required Duration rewind,
  }) {
    if (returnTo == null || returnIndex == null) return null;
    final t = context.t.queue.temporary;
    final bold = TextStyle(
      fontWeight: FontWeight.w600,
      color: context.fmpColors.label,
    );
    final args = (
      number: TextSpan(text: '${returnIndex + 1}'),
      title: TextSpan(text: returnTo.track.title, style: bold),
      position: TextSpan(
        text: formatDuration(resumeAt),
        style: bold.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      seconds: TextSpan(text: '${rewind.inSeconds}'),
    );
    return table
        ? t.returnTable(
            number: args.number,
            title: args.title,
            position: args.position,
            seconds: args.seconds,
          )
        : t.returnTouch(
            number: args.number,
            title: args.title,
            position: args.position,
            seconds: args.seconds,
          );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, box) => _build(context, ref, box.maxWidth),
  );

  Widget _build(BuildContext context, WidgetRef ref, double width) {
    final colors = context.fmpColors;
    final controller = ref.read(queueProvider.notifier);
    final playback = ref.watch(playbackProvider);
    final rewind = ref.watch(temporaryPlayRewindProvider);
    final entry = returnTo;
    final text = entry == null
        ? null
        : returnText(
            context,
            table: table,
            returnTo: entry,
            returnIndex: returnIndex,
            resumeAt: temporary.resumeAt(entry, rewind),
            rewind: rewind,
          );
    final playing =
        playback != null &&
        playback.track == temporary.track &&
        playback.playing;
    final t = context.t.queue;
    final back = entry == null
        ? null
        : FmpButton(
            label: t.temporary.backToQueue,
            icon: FmpIcons.history,
            variant: FmpButtonVariant.tinted,
            size: FmpButtonSize.small,
            onTap: controller.returnToQueue,
          );
    final next = FmpButton(
      label: t.actions.playNext,
      icon: FmpIcons.nextUp,
      size: FmpButtonSize.small,
      onTap: controller.queueTemporaryNext,
    );
    final header = _Header(table: table);
    final lines = text == null
        ? 0
        : _lines(context, text, _textWidth(width, table: table), table);
    final returnLine = text == null
        ? null
        : SizedBox(
            height: _lineHeight(table) * lines,
            child: Row(
              crossAxisAlignment: table
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: table ? 0 : 1),
                  child: FmpIcon(
                    FmpIcons.chevD,
                    size: table ? 14 : 16,
                    color: colors.accent,
                  ),
                ),
                SizedBox(width: table ? 6 : 10),
                Expanded(
                  child: Text.rich(
                    text,
                    maxLines: lines,
                    overflow: TextOverflow.ellipsis,
                    style: _returnStyle(table).copyWith(color: colors.label2),
                  ),
                ),
              ],
            ),
          );

    if (table) {
      return Container(
        key: const Key('queue-temporary'),
        margin: const EdgeInsets.only(top: 6, bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: colors.accentSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _headerHeight(context, table),
              child: Row(
                children: [
                  header,
                  const Spacer(),
                  next,
                  if (back != null) ...[const SizedBox(width: 8), back],
                ],
              ),
            ),
            const SizedBox(height: 6),
            _TableTrack(
              track: temporary.track,
              playing: playing,
              time: playback != null && playback.track == temporary.track
                  ? playbackTime(playback)
                  : null,
            ),
            if (returnLine != null) ...[
              SizedBox(height: _returnGap(table)),
              returnLine,
            ],
          ],
        ),
      );
    }
    return Container(
      key: const Key('queue-temporary'),
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(context.fmpMetrics.radii.group),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: SizedBox(
              height: _headerHeight(context, table),
              child: Align(alignment: Alignment.centerLeft, child: header),
            ),
          ),
          _TouchTrack(track: temporary.track, playing: playing),
          if (returnLine != null)
            Padding(
              padding: EdgeInsets.fromLTRB(14, _returnGap(table), 14, 0),
              child: returnLine,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                if (back != null) ...[back, const SizedBox(width: 8)],
                next,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「⟲ 臨時播放　不在佇列裡」（`.qu-th`）。
class _Header extends StatelessWidget {
  const _Header({required this.table});

  final bool table;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final t = context.t.queue.temporary;
    final size = table ? 12.0 : 13.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FmpIcon(FmpIcons.history, size: 16, color: colors.accent),
        const SizedBox(width: 5),
        Text(
          t.title,
          style: TextStyle(
            fontSize: size,
            height: 18 / 13,
            fontWeight: FontWeight.w700,
            color: colors.accent,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          t.notInQueue,
          style: TextStyle(
            fontSize: size,
            height: 18 / 13,
            color: colors.label2,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

/// 觸控卡片裡的曲目（`FMP.trackRow` 的播放中樣式）：60 高、內距 14。
class _TouchTrack extends StatelessWidget {
  const _TouchTrack({required this.track, required this.playing});

  final Track track;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final text = context.fmpText;
    final metrics = context.fmpMetrics;
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Cover(
              url: track.coverUrl,
              size: metrics.thumbnailSize,
              radius: metrics.radii.thumbnail,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Equalizer(
                        playing: playing,
                        label: context.t.queue.nowPlaying,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.callout.copyWith(
                            color: colors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      SourceMarkIcon(pluginId: track.ref.pluginId, size: 15),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          track.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.foot.copyWith(color: colors.label2),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (track.duration case final duration?)
              Text(
                formatDuration(duration),
                style: text.foot.tabular.copyWith(color: colors.label3),
              ),
          ],
        ),
      ),
    );
  }
}

/// 表格卡片裡的曲目（`.qu-tbody`）：封面 44、曲名（等化器）、音源全名＋
/// 作者，右邊是播放時間。
class _TableTrack extends ConsumerWidget {
  const _TableTrack({
    required this.track,
    required this.playing,
    required this.time,
  });

  final Track track;
  final bool playing;

  /// 「1:12 / 4:05」；還沒在播時是 null。
  final String? time;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.fmpColors;
    final sourceName = ref
        .watch(pluginManifestProvider(track.ref.pluginId))
        ?.name;
    final small = TextStyle(
      fontSize: 12,
      height: 15 / 12,
      letterSpacing: 0,
      color: colors.label2,
    );
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Cover(
            url: track.coverUrl,
            size: 44,
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
                    Equalizer(
                      playing: playing,
                      label: context.t.queue.nowPlaying,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 17 / 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                          color: colors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    SourceMarkIcon(pluginId: track.ref.pluginId, size: 14),
                    const SizedBox(width: 6),
                    if (sourceName != null) ...[
                      Text(sourceName, maxLines: 1, style: small),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        track.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (time != null) ...[
            const SizedBox(width: 12),
            Text(
              time!,
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0,
                color: colors.label3,
              ).tabular,
            ),
          ],
        ],
      ),
    );
  }
}
