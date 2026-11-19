import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/equalizer.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/common/track_actions.dart';
import 'package:fmp/ui/home/chart_rows.dart';
import 'package:fmp/ui/queue/queue_rows.dart' show queueTotalText;
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 繼續聽有沒有東西：佇列有目前那首（`docs/design/DESIGN.md`〈首頁〉：佇列空時
/// 不出現；播完了、沒有目前那首時也沒有可以接著聽的）。
bool hasContinueListening(Queue queue) => queue.current != null;

/// 首頁的「繼續聽」（`docs/design/home.html`）：一行正在播放與它在佇列的
/// 位置、接下來 3 首、「佇列 ›」切到佇列分頁。不畫大卡（迷你播放器已有）。
/// 點接下來的一首＝從那首開始播，和在佇列頁點它一樣。臨時播放中第一行寫
/// 播完回到佇列第幾首，接下來仍是佇列裡的下 3 首。
///
/// [desk] 是桌面與窄視窗的密度（`.hm-dsh`、`.hm-dnow`、32 的封面）。
class ContinueListening extends ConsumerWidget {
  const ContinueListening({super.key, required this.desk});

  final bool desk;

  /// 接下來列幾首。
  static const upNextCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);
    final current = queue.currentIndex;
    if (current == null) return const SizedBox.shrink();
    final temporary = ref.watch(temporaryPlayProvider) != null;
    final playing = ref.watch(
      playbackProvider.select((state) => state?.playing ?? false),
    );
    final t = context.t;
    final colors = context.fmpColors;
    final upNext = queue.entries.skip(current + 1).toList();
    final shown = upNext.take(upNextCount).toList();
    final controller = ref.read(queueProvider.notifier);

    void playAt(int i) => unawaited(controller.playAt(current + 1 + i));
    void menu(Track track, Offset at) =>
        unawaited(showTrackActions(context, ref, track, at: at));

    final title = queue.current!.track.title;
    final size = desk ? 12.0 : 13.0;
    final style = TextStyle(
      fontSize: size,
      height: desk ? null : 18 / 13,
      letterSpacing: 0,
      color: colors.label2,
    );
    final bold = TextStyle(color: colors.label, fontWeight: FontWeight.w600);
    final nowText = Text.rich(
      temporary
          ? TextSpan(text: t.home.temporary(number: current + 1))
          : TextSpan(
              children: [
                TextSpan(text: '${t.home.nowPlaying} '),
                TextSpan(text: title, style: bold),
                if (desk && shown.isNotEmpty)
                  TextSpan(text: ' · ${t.queue.upNext}'),
              ],
            ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final now = Padding(
      padding: desk
          ? const EdgeInsets.fromLTRB(4, 0, 4, 4)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: desk ? 22 : 26),
        child: Row(
          children: [
            Equalizer(
              playing: playing && !temporary,
              label: t.queue.nowPlaying,
            ),
            SizedBox(width: desk ? 7 : 8),
            Expanded(child: nowText),
            if (!temporary) ...[
              const SizedBox(width: 8),
              Text(
                t.home.position(
                  number: current + 1,
                  total: queue.entries.length,
                ),
                style: style.tabular,
              ),
            ],
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _head(context, t),
        now,
        if (!desk && shown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: t.queue.upNext,
                    style: TextStyle(
                      color: colors.label,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: queueTotalText(
                      t,
                      upNext.length,
                      upNext.fold(
                        Duration.zero,
                        (sum, e) => sum + (e.track.duration ?? Duration.zero),
                      ),
                    ),
                  ),
                ],
              ),
              style: style.tabular,
            ),
          ),
        for (final (i, entry) in shown.indexed)
          if (desk)
            _DeskRow(
              key: ValueKey(('continue', entry.id)),
              track: entry.track,
              onPlay: () => playAt(i),
              onMenu: (at) => menu(entry.track, at),
            )
          else
            HomeTouchRow(
              key: ValueKey(('continue', entry.id)),
              track: entry.track,
              isCurrent: false,
              playing: false,
              separator: i > 0,
              onTap: () => playAt(i),
              onMore: (at) => menu(entry.track, at),
            ),
      ],
    );
  }

  /// 區塊標題「繼續聽」與右邊的「佇列 ›」。
  Widget _head(BuildContext context, Translations t) {
    final colors = context.fmpColors;
    void toQueue() => context.go(Destination.queue.path);
    if (desk) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
        child: Row(
          children: [
            Semantics(
              header: true,
              child: Text(
                t.home.continueListening,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  color: colors.label,
                ),
              ),
            ),
            const Spacer(),
            FmpButton(
              label: t.shell.nav.queue,
              trailingIcon: FmpIcons.chevR,
              variant: FmpButtonVariant.plain,
              size: FmpButtonSize.small,
              onTap: toQueue,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 10, 4),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text(
              t.home.continueListening,
              style: context.fmpText.title3.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          // `.hm-link`：44 高的強調色字鈕。
          ShellButton(
            onTap: toQueue,
            label: t.shell.nav.queue,
            focusRadius: 8,
            builder: (context, _) => SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.shell.nav.queue,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                        color: colors.accent,
                      ),
                    ),
                    const SizedBox(width: 2),
                    FmpIcon(
                      FmpIcons.chevR,
                      size: 16,
                      strokeWidth: 2.2,
                      color: colors.accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 桌面的接下來一列（`FMP.trackRow` 的桌面版，封面 32、沒有 ⋮）：滑過帶底，
/// 雙擊從這首播，右鍵開選單。
class _DeskRow extends StatefulWidget {
  const _DeskRow({
    super.key,
    required this.track,
    required this.onPlay,
    required this.onMenu,
  });

  final Track track;
  final VoidCallback onPlay;
  final void Function(Offset at) onMenu;

  @override
  State<_DeskRow> createState() => _DeskRowState();
}

class _DeskRowState extends State<_DeskRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final track = widget.track;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onPlay,
        onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: _hovered ? colors.cellHover : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Cover(
                url: track.coverUrl,
                size: 32,
                radius: context.fmpMetrics.radii.thumbnail,
              ),
              const SizedBox(width: 10),
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
                            style: TextStyle(
                              fontSize: 12,
                              height: 15 / 12,
                              letterSpacing: 0,
                              color: colors.label2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (track.duration case final duration?) ...[
                const SizedBox(width: 10),
                Text(
                  formatDuration(duration),
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0,
                    color: colors.label3,
                  ).tabular,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
