import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/platform/web_links.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/glass_menu.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/toast/toast.dart';
import 'package:material_ui/material_ui.dart';

/// 一首曲目的「更多」能做的事（`docs/design/search.html`〈更多與多選〉）。
/// 還沒有的功能（加入歌單、匹配歌詞）不出現。
enum TrackAction { play, playNext, addToQueue, copyLink, openInBrowser }

/// [track] 的動作：曲目有網址才有複製連結與在瀏覽器開啟（ADR 0039）。
List<TrackAction> trackActionsFor(Track track) => [
  TrackAction.play,
  TrackAction.playNext,
  TrackAction.addToQueue,
  if (track.url != null) ...[TrackAction.copyLink, TrackAction.openInBrowser],
];

/// 打開 [track] 的「更多」，選了就做：手機（窄、觸控）從底部升起 sheet，
/// 平板是從按鈕長出的選單，桌面是右鍵選單（設計稿〈待確認〉20、31）。[at]
/// 是選單的錨點（全域座標）。
Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  required Offset at,
}) async {
  final form = FormFactor.of(context);
  final phone =
      form.widthClass == WidthClass.narrow && form.density == Density.touch;
  // 選單開著時畫面可能換掉（例如新的搜尋），先拿好要用的東西。
  final run = trackActionRunner(context, ref);
  final actions = trackActionsFor(track);
  final TrackAction? chosen;
  if (phone) {
    chosen = await _showSheet(context, track, actions);
  } else {
    chosen = await showGlassMenu<TrackAction>(
      context: context,
      at: at,
      header: TrackSummary(track: track, touch: form.density == Density.touch),
      entries: _menuEntries(context, actions, form.density == Density.pointer),
    );
  }
  if (chosen != null) await run(chosen, [track]);
}

/// 做 [action]。多選時 [tracks] 依畫面上的順序。
typedef TrackActionRunner = Future<void> Function(
  TrackAction action,
  List<Track> tracks,
);

/// 綁好 [ref] 的 [TrackActionRunner]：選單與多選的動作列都用它。
TrackActionRunner trackActionRunner(BuildContext context, WidgetRef ref) {
  final t = context.t;
  final queue = ref.read(queueProvider.notifier);
  final toasts = ref.read(toastProvider.notifier);
  final links = ref.read(webLinksProvider);
  return (action, tracks) async {
    switch (action) {
      case TrackAction.play:
        await queue.playTemporarily(tracks.first);
      case TrackAction.playNext:
        await queue.playNext(tracks);
      case TrackAction.addToQueue:
        await queue.add(tracks);
      case TrackAction.copyLink:
        await Clipboard.setData(ClipboardData(text: tracks.first.url!));
        toasts.show(
          ToastMessage(t.search.actions.linkCopied, icon: FmpIcons.check),
        );
      case TrackAction.openInBrowser:
        if (!await links.open(Uri.parse(tracks.first.url!))) {
          toasts.show(ToastMessage(t.search.actions.openFailed));
        }
    }
  };
}

String _label(Translations t, TrackAction action) => switch (action) {
  TrackAction.play => t.search.actions.play,
  TrackAction.playNext => t.queue.actions.playNext,
  TrackAction.addToQueue => t.queue.actions.addToQueue,
  TrackAction.copyLink => t.search.actions.copyLink,
  TrackAction.openInBrowser => t.search.actions.openInBrowser,
};

FmpIcons _icon(TrackAction action) => switch (action) {
  TrackAction.play => FmpIcons.play,
  TrackAction.playNext => FmpIcons.nextUp,
  TrackAction.addToQueue => FmpIcons.queue,
  TrackAction.copyLink => FmpIcons.link,
  TrackAction.openInBrowser => FmpIcons.external,
};

/// 選單的項目：佇列的動作在上，連結的兩項隔一條細線放在下面（擁有者
/// 2026-11-19 同意三種寬度都放）。桌面的「播放」帶 ↩ 提示。
List<GlassMenuEntry<TrackAction>> _menuEntries(
  BuildContext context,
  List<TrackAction> actions,
  bool pointer,
) {
  final t = context.t;
  GlassMenuItem<TrackAction> item(TrackAction a) => GlassMenuItem(
    value: a,
    label: _label(t, a),
    icon: _icon(a),
    shortcut: pointer && a == TrackAction.play
        ? WindowChrome.enterKeyLabel
        : null,
  );
  final queue = actions.where((a) => !_isLink(a));
  final links = actions.where(_isLink);
  return [
    for (final a in queue) item(a),
    if (links.isNotEmpty) const GlassMenuDivider(),
    for (final a in links) item(a),
  ];
}

bool _isLink(TrackAction a) =>
    a == TrackAction.copyLink || a == TrackAction.openInBrowser;

/// 選單與 sheet 頂端的曲目摘要（`.gmenu .mh`、`.tsheet .th`）：封面、曲名、
/// 音源符號＋簡稱 · 作者，讓人確認動作作用在哪一首。
class TrackSummary extends ConsumerWidget {
  const TrackSummary({
    super.key,
    required this.track,
    required this.touch,
    this.large = false,
  });

  final Track track;
  final bool touch;

  /// 手機 sheet 的大號（封面 52、曲名 17）。
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.fmpColors;
    final short = ref
        .watch(pluginManifestProvider(track.ref.pluginId))
        ?.mark
        ?.short;
    final cover = large ? 52.0 : (touch ? 40.0 : 32.0);
    final titleSize = large ? 17.0 : 14.0;
    final subSize = large ? 13.0 : 12.0;
    return Row(
      children: [
        Cover(url: track.coverUrl, size: cover, radius: large ? 8 : 7),
        SizedBox(width: large ? 12 : 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: titleSize,
                  height: (large ? 22 : 18) / titleSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  color: colors.glassInk,
                ),
              ),
              SizedBox(height: large ? 3 : 1),
              Row(
                children: [
                  SourceMarkIcon(pluginId: track.ref.pluginId, size: 14),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      [?short, track.author].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: subSize,
                        height: (large ? 17 : 16) / subSize,
                        letterSpacing: 0,
                        color: colors.glassInk2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 手機的曲目 sheet（`FMP.trackSheet`，`.sheet.lg.tsheet`）：浮動的厚玻璃，
/// 從底部升起，背後 `--scrim`。點外面或往下滑收起。
Future<TrackAction?> _showSheet(
  BuildContext context,
  Track track,
  List<TrackAction> actions,
) => showGeneralDialog<TrackAction>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: context.fmpColors.scrim,
  transitionDuration: FmpMotion.mid,
  transitionBuilder: (context, animation, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: FmpMotion.outCurve)),
    child: child,
  ),
  pageBuilder: (context, _, _) => Align(
    alignment: Alignment.bottomCenter,
    child: _TrackSheet(track: track, actions: actions),
  ),
);

class _TrackSheet extends StatelessWidget {
  const _TrackSheet({required this.track, required this.actions});

  final Track track;
  final List<TrackAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    String? hint(TrackAction a) => switch (a) {
      TrackAction.play => t.search.actions.playHint,
      TrackAction.addToQueue => t.search.actions.addToQueueHint,
      _ => null,
    };
    Widget item(TrackAction a) => _SheetItem(
      icon: _icon(a),
      label: _label(t, a),
      hint: hint(a),
      onTap: () => Navigator.of(context).pop(a),
    );
    final separator = Container(
      height: .5,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      color: colors.glassInk.withValues(alpha: .14),
    );
    final queue = actions.where((a) => !_isLink(a)).toList();
    final links = actions.where(_isLink).toList();
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 200) Navigator.of(context).pop();
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + bottom),
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: track.title,
          child: Glass(
            variant: GlassVariant.thick,
            radius: 34,
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 5,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: colors.label4,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                      child: TrackSummary(
                        track: track,
                        touch: true,
                        large: true,
                      ),
                    ),
                    for (final a in queue) item(a),
                    if (links.isNotEmpty) separator,
                    for (final a in links) item(a),
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

/// sheet 的一列（`.tsheet .ti`）：圖示 22 在左，右邊小字補後果。
class _SheetItem extends StatefulWidget {
  const _SheetItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
  });

  final FmpIcons icon;
  final String label;
  final String? hint;
  final VoidCallback onTap;

  @override
  State<_SheetItem> createState() => _SheetItemState();
}

class _SheetItemState extends State<_SheetItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          color: _pressed ? colors.glassPress : null,
          child: Row(
            children: [
              FmpIcon(widget.icon, size: 22, color: colors.glassInk),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 16,
                    letterSpacing: 0,
                    color: colors.glassInk,
                  ),
                ),
              ),
              if (widget.hint case final hint?)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .4,
                  ),
                  child: Text(
                    hint,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 16 / 12.5,
                      letterSpacing: 0,
                      color: colors.glassInk2,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
