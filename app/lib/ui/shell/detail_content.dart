import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 換歌後停在同一首這麼久才查曲目資訊：連按下一首快速跳過時不每首都查。
const trackInfoSettleDelay = Duration(seconds: 1);

/// 詳情面板的內容（`FMP.detailPanel` 的 `.dbody`）：目前曲目的封面、曲名與
/// 作者、音源 chip、播放數與評論數等、下一首（佇列接下來的 3 首）、簡介。
/// 沒有目前曲目時只寫一句（擁有者 2026-11-20 同意）。
///
/// 播放數、評論數、專輯與簡介來自插件能力 `trackInfo`：面板看得到時才查，
/// 換歌後停 [trackInfoSettleDelay] 還是同一首才發請求；同一首這次開 App
/// 期間只查一次（`trackInfoProvider` 留在記憶體）。[touch] 是平板浮出的大號
/// 面板（`.detail.touch`）。
class DetailContent extends ConsumerStatefulWidget {
  const DetailContent({super.key, required this.touch});

  final bool touch;

  @override
  ConsumerState<DetailContent> createState() => _DetailContentState();
}

class _DetailContentState extends ConsumerState<DetailContent> {
  /// 停夠久、可以查曲目資訊的那首。
  TrackRef? _settled;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      playbackProvider.select((state) => state?.track.ref),
      (_, track) => _settle(track),
      fireImmediately: true,
    );
  }

  void _settle(TrackRef? track) {
    _timer?.cancel();
    if (track == null || track == _settled) return;
    // 查過的直接用快取，不用等。
    // 棄用訊息指向的 `provider.exist` 在 riverpod 3.5.0 還沒有，先用 exists。
    // ignore: deprecated_member_use
    if (ref.exists(trackInfoProvider(track))) {
      _settled = track;
      return;
    }
    _timer = Timer(trackInfoSettleDelay, () {
      if (mounted) setState(() => _settled = track);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final touch = widget.touch;
    final track = ref.watch(playbackProvider.select((state) => state?.track));
    if (track == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
        child: Center(
          child: Text(
            t.shell.detail.empty,
            key: const Key('detail-empty'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: touch ? 15 : 13,
              letterSpacing: 0,
              color: colors.label3,
            ),
          ),
        ),
      );
    }
    final info = track.ref == _settled
        ? ref.watch(trackInfoProvider(track.ref))
        : null;
    final z = touch
        ? (title: 20.0, titleHeight: 25.0, sub: 15.0, small: 13.0, body: 15.0)
        : (title: 17.0, titleHeight: 22.0, sub: 13.0, small: 12.0, body: 12.5);
    final heading = TextStyle(
      fontSize: z.small,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: colors.label2,
    );
    return SingleChildScrollView(
      padding: touch
          ? const EdgeInsets.fromLTRB(20, 8, 20, 100)
          : const EdgeInsets.fromLTRB(18, 6, 18, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, .25),
                    offset: Offset(0, 12),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: Cover(
                url: track.largestCoverUrl,
                size: box.maxWidth,
                radius: 12,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            track.title,
            style: TextStyle(
              fontSize: z.title,
              height: z.titleHeight / z.title,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: colors.label,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            track.author,
            style: TextStyle(
              fontSize: z.sub,
              letterSpacing: 0,
              color: colors.label2,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: SourceChip(pluginId: track.ref.pluginId, large: touch),
          ),
          if (info?.value case final value?)
            _Stats(info: value, small: z.small, number: z.sub),
          const SizedBox(height: 22),
          Text(t.shell.detail.next, style: heading),
          const SizedBox(height: 4),
          _UpNext(touch: touch),
          const SizedBox(height: 20),
          Text(t.shell.detail.description, style: heading),
          const SizedBox(height: 6),
          _Description(
            track: track,
            info: info,
            size: z.body,
            onRetry: () => ref.invalidate(trackInfoProvider(track.ref)),
          ),
        ],
      ),
    );
  }
}

/// 封面下的一行數字（稿：「8,214 則評論」「專輯《夜行》」「12,345 次播放」）：
/// 播放數、評論數、專輯，給了才有。數字粗體主文字色、其餘次要色。
class _Stats extends StatelessWidget {
  const _Stats({required this.info, required this.small, required this.number});

  final TrackInfo info;
  final double small;
  final double number;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final base = TextStyle(
      fontSize: small,
      letterSpacing: 0,
      color: colors.label2,
    );
    final strong = TextStyle(
      fontSize: number,
      fontWeight: FontWeight.w700,
      color: colors.label,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    InlineSpan count(int n, String unit) => TextSpan(
      children: [
        TextSpan(text: formatGrouped(n), style: strong),
        TextSpan(text: ' $unit'),
      ],
    );
    final items = <InlineSpan>[
      if (info.playCount case final n?) count(n, t.shell.detail.plays),
      if (info.commentCount case final n?) count(n, t.shell.detail.comments),
      if (info.album case final album?)
        TextSpan(
          children: [
            TextSpan(text: t.shell.detail.albumBefore),
            TextSpan(
              text: album,
              style: TextStyle(color: colors.label),
            ),
            TextSpan(text: t.shell.detail.albumAfter),
          ],
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(
        spacing: 18,
        runSpacing: 4,
        children: [for (final item in items) Text.rich(item, style: base)],
      ),
    );
  }
}

/// 簡介：插件給了就照錄；插件沒有 `trackInfo` 或沒給簡介寫「這個音源沒有
/// 提供簡介。」；還在等或載入中、失敗時寫一句灰字（稿沒畫）。
class _Description extends StatelessWidget {
  const _Description({
    required this.track,
    required this.info,
    required this.size,
    required this.onRetry,
  });

  final Track track;
  final AsyncValue<TrackInfo?>? info;
  final double size;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    TextStyle style(Color color) =>
        TextStyle(fontSize: size, height: 1.55, letterSpacing: 0, color: color);
    final info = this.info;
    if (info == null || info.isLoading) {
      return Text(
        t.trackInfo.loading,
        key: const Key('detail-loading'),
        style: style(colors.label3),
      );
    }
    if (info.hasError) {
      return Row(
        children: [
          Expanded(
            child: Text(t.trackInfo.failed, style: style(colors.label3)),
          ),
          FmpButton(
            key: const Key('detail-retry'),
            label: t.trackInfo.retry,
            size: FmpButtonSize.small,
            onTap: onRetry,
          ),
        ],
      );
    }
    return switch (info.value?.description) {
      final text? => Text(
        text,
        key: const Key('detail-description'),
        style: style(colors.label2),
      ),
      null => Text(t.shell.detail.noDescription, style: style(colors.label3)),
    };
  }
}

/// 下一首：佇列接下來的 3 首（臨時播放時是要回去的那首之後的，同播放頁的
/// 佇列），點一首從它開始播。沒有接下來的寫一句。
class _UpNext extends ConsumerWidget {
  const _UpNext({required this.touch});

  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final colors = context.fmpColors;
    final queue = ref.watch(queueProvider);
    final current = queue.currentIndex;
    final base = current == null ? queue.entries.length : current + 1;
    final upcoming = queue.entries.skip(base).take(3).toList();
    if (upcoming.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          t.player.nothingNext,
          style: TextStyle(
            fontSize: touch ? 13 : 12,
            letterSpacing: 0,
            color: colors.label3,
          ),
        ),
      );
    }
    final controller = ref.read(queueProvider.notifier);
    return Column(
      children: [
        for (final (i, entry) in upcoming.indexed)
          _NextRow(
            key: ValueKey(entry.id),
            track: entry.track,
            touch: touch,
            onTap: () => controller.playAt(base + i),
          ),
      ],
    );
  }
}

/// 一首（`FMP.trackRow`，`more: false`）：封面 32（平板 40）、曲名、音源符號
/// 與作者、時長；高 44（平板 52）。
class _NextRow extends StatelessWidget {
  const _NextRow({
    super.key,
    required this.track,
    required this.touch,
    required this.onTap,
  });

  final Track track;
  final bool touch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final sub = TextStyle(
      fontSize: touch ? 13 : 12,
      height: touch ? 17 / 13 : 15 / 12,
      letterSpacing: 0,
      color: colors.label2,
    );
    return ShellButton(
      onTap: onTap,
      label: '${track.title}，${t.queue.playFromHere}',
      focusRadius: 8,
      builder: (context, hovered) => Container(
        constraints: BoxConstraints(minHeight: touch ? 52 : 44),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: hovered && !touch ? colors.cellHover : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              Cover(
                url: track.coverUrl,
                size: touch ? 40 : 32,
                radius: context.fmpMetrics.radii.thumbnail,
              ),
              SizedBox(width: touch ? 12 : 10),
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
                        fontSize: touch ? 15 : 13,
                        height: touch ? 20 / 15 : 17 / 13,
                        letterSpacing: 0,
                        color: colors.label,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        SourceMarkIcon(pluginId: track.ref.pluginId, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            track.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sub,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (track.duration case final d?) ...[
                const SizedBox(width: 10),
                Text(formatDuration(d), style: sub.copyWith(height: 1).tabular),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
