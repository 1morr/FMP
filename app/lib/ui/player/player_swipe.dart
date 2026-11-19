import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/player/player_controls.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/player/player_queue.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 左右滑的畫面，依序排（`player.html` 的 `PL_PAGES`，歌詞那頁 M4 才有）。
enum PlayerPane { queue, cover }

/// 手機與平板直向的播放頁（`plPhone`、`plMid` 直向）：頂列與音源膠囊之間的
/// 那一塊在「佇列 ← 封面」之間左右滑，打開在封面；音源膠囊、進度、控制列與
/// 底部的頁面點點不動。封面不能左右滑切歌，換歌只靠控制列。往下拉收起。
/// 系統開「減少動態效果」時換畫面改成淡入淡出（`DESIGN.md`〈動態〉）。
class PlayerSwipe extends ConsumerStatefulWidget {
  const PlayerSwipe({
    super.key,
    required this.track,
    required this.tablet,
    required this.topBar,
    required this.onClose,
  });

  final Track track;

  /// 平板直向：手機的版面放進一條置中、最寬 560 的欄（`.pl-mp`）。
  final bool tablet;
  final PlayerTopButtons topBar;
  final VoidCallback onClose;

  @override
  ConsumerState<PlayerSwipe> createState() => _PlayerSwipeState();
}

class _PlayerSwipeState extends ConsumerState<PlayerSwipe> {
  final _pages = PageController(initialPage: PlayerPane.cover.index);

  /// 減少動態效果時（沒有 [PageView]）目前的畫面。
  PlayerPane _pane = PlayerPane.cover;

  /// 往下拉收起：手指拉了多遠；放開時回去或收起。
  double _pull = 0;
  bool _pulling = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(PlayerPane pane, {required bool reduce}) {
    if (reduce) {
      setState(() => _pane = pane);
      return;
    }
    _pages.animateToPage(
      pane.index,
      duration: FmpMotion.morph,
      curve: FmpMotion.morphCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final reduce = MediaQuery.disableAnimationsOf(context);
    const density = PlayerDensity(touch: true);
    final tablet = widget.tablet;
    // 平板：一條置中的欄，寬度上限 560（`.pl-mcol`）。
    final columnWidth = tablet ? math.min(560.0, width - 64) : width;
    final side = (width - columnWidth) / 2;
    final top = media.viewPadding.top;
    // 底部點點下面：手機 34 加 home indicator（稿的 844 高框裡 dots 底在 776），
    // 平板 40。
    final bottom = (tablet ? 40.0 : 34.0) + media.viewPadding.bottom;
    final more = widget.topBar.more(context, ref);
    final topBar = SizedBox(
      height: 52,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tablet ? side : 16),
        child: Row(
          children: [
            widget.topBar.collapse(context),
            const SizedBox(width: 8),
            const Expanded(child: PlayerContext()),
            const SizedBox(width: 8),
            more ?? const SizedBox(width: 44),
          ],
        ),
      ),
    );
    Widget pane(PlayerPane which) => switch (which) {
      PlayerPane.queue => _QueuePane(
        track: widget.track,
        tablet: tablet,
        side: side,
      ),
      PlayerPane.cover => _CoverPane(
        track: widget.track,
        tablet: tablet,
        side: side,
      ),
    };
    final Widget panes;
    if (reduce) {
      panes = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v > 200 && _pane == PlayerPane.cover) {
            _goTo(PlayerPane.queue, reduce: true);
          } else if (v < -200 && _pane == PlayerPane.queue) {
            _goTo(PlayerPane.cover, reduce: true);
          }
        },
        child: AnimatedSwitcher(
          key: const Key('player-panes-fade'),
          duration: FmpMotion.mid,
          child: KeyedSubtree(key: ValueKey(_pane), child: pane(_pane)),
        ),
      );
    } else {
      panes = PageView(
        key: const Key('player-pages'),
        controller: _pages,
        children: [for (final p in PlayerPane.values) pane(p)],
      );
    }
    // 控制列：手機左右 22（`.pl-ctl`），平板比欄寬各多 8（`.pl-mp .pl-ctl`）。
    final controlsInset = tablet ? side - 8 : 22.0;
    final body = Column(
      children: [
        SizedBox(height: top),
        topBar,
        Expanded(child: panes),
        Padding(
          padding: EdgeInsets.only(left: tablet ? side : 26, right: side + 26),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: SignatureCapsule(density: density),
          ),
        ),
        // 條的上緣離音源膠囊上緣 44（稿 536 → 580）。
        SizedBox(
          height:
              44 - density.signatureHeight - PlayerProgress.overhangOf(density),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tablet ? side : 28),
          child: const PlayerProgress(density: density),
        ),
        // 控制列離條的上緣：手機 42（580 → 622），平板接在時間下 4。
        SizedBox(height: tablet ? 4 : 13),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: controlsInset),
          child: const PlayerControls(density: density),
        ),
        // 點點離控制列上緣：手機 130（622 → 752），平板接在下面 8；點點那列
        // 為了點擊區高 44，比看得到的 24 上下各多 10。
        SizedBox(height: (tablet ? 8 : 130 - density.controlsHeight) - 10),
        _PageDots(
          controller: reduce ? null : _pages,
          pane: _pane,
          onSelect: (p) => _goTo(p, reduce: reduce),
        ),
        SizedBox(height: bottom - 10),
      ],
    );
    return GestureDetector(
      onVerticalDragStart: (_) => setState(() => _pulling = true),
      onVerticalDragUpdate: (details) =>
          setState(() => _pull = math.max(0, _pull + details.delta.dy)),
      onVerticalDragEnd: (details) {
        final close = _pull > 120 || (details.primaryVelocity ?? 0) > 800;
        setState(() {
          _pulling = false;
          if (!close) _pull = 0;
        });
        if (close) widget.onClose();
      },
      child: AnimatedContainer(
        duration: _pulling || reduce ? Duration.zero : FmpMotion.mid,
        curve: FmpMotion.outCurve,
        transform: Matrix4.translationValues(0, _pull, 0),
        child: body,
      ),
    );
  }
}

/// 封面那頁：封面、曲名與作者。手機封面離頂列 12、寬 300（左右各 45），矮的
/// 螢幕縮小；平板在這一塊裡置中、最大 520。
class _CoverPane extends StatelessWidget {
  const _CoverPane({
    required this.track,
    required this.tablet,
    required this.side,
  });

  final Track track;
  final bool tablet;
  final double side;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final title = PlayerTitle(
          track: track,
          titleSize: tablet ? 26 : 22,
          titleHeight: tablet ? 32 / 26 : 28 / 22,
          artistSize: tablet ? 18 : 17,
          artistHeight: tablet ? 23 / 18 : 22 / 17,
        );
        if (tablet) {
          final cover = math.max(
            120.0,
            math.min(math.min(520.0, width - 2 * side), box.maxHeight - 120),
          );
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PlayerCover(track: track, size: cover),
                const SizedBox(height: 26),
                Align(alignment: Alignment.centerLeft, child: title),
                const SizedBox(height: 14),
              ],
            ),
          );
        }
        // 封面 12 → 曲名 24 → 曲名與作者約 51 → 離音源膠囊 43（稿 106 → 536）。
        final cover = math.max(
          120.0,
          math.min(width - 90, box.maxHeight - 12 - 24 - 51 - 43),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: PlayerCover(track: track, size: cover),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: title,
            ),
          ],
        );
      },
    );
  }
}

/// 佇列那頁（`.pl-mini`＋`.pl-pq`）：上面是正在播的小卡（封面 56、曲名、音源
/// 符號與作者），下面是接下來的曲目，下緣淡出。
class _QueuePane extends StatelessWidget {
  const _QueuePane({
    required this.track,
    required this.tablet,
    required this.side,
  });

  final Track track;
  final bool tablet;
  final double side;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final mini = Row(
      children: [
        Cover(url: track.coverUrl, size: tablet ? 64 : 56, radius: 9),
        const SizedBox(width: 12),
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
                  fontSize: tablet ? 20 : 17,
                  height: tablet ? 26 / 20 : 22 / 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  color: colors.label,
                ),
              ),
              Row(
                children: [
                  SourceMarkIcon(pluginId: track.ref.pluginId, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      track.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: tablet ? 15 : 14,
                        height: tablet ? 20 / 15 : 19 / 14,
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
      ],
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tablet ? side - 24 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: tablet ? 28 : 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: mini,
          ),
          SizedBox(height: tablet ? 18 : 10),
          Expanded(
            child: Padding(
              // 列表離音源膠囊 26（稿到 510）。
              padding: const EdgeInsets.only(bottom: 26),
              child: ShaderMask(
                // `mask: linear-gradient(#000 82%, transparent)`
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [.82, 1],
                  colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: const PlayerQueue(
                  column: false,
                  touch: true,
                  bottomPadding: 60,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 頁面點點（`.pl-dots`）：目前那頁拉長成 20 的白膠囊，其他 7 的半透明圓點；
/// 滑動時寬度跟著手指在兩頁之間變。不是玻璃。點一個點換到那頁；螢幕閱讀器
/// 讀「封面，第 2 頁，共 2 頁」。
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.controller,
    required this.pane,
    required this.onSelect,
  });

  /// 有 [PageView] 時跟著它的位置；減少動態效果時是 null，看 [pane]。
  final PageController? controller;
  final PlayerPane pane;
  final ValueChanged<PlayerPane> onSelect;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) return _dots(context, pane.index.toDouble());
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final position =
            controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? pane.index.toDouble()
            : PlayerPane.cover.index.toDouble();
        return _dots(context, position);
      },
    );
  }

  Widget _dots(BuildContext context, double position) {
    final t = context.t;
    final names = {
      PlayerPane.queue: t.player.pages.queue,
      PlayerPane.cover: t.player.pages.cover,
    };
    final current = position.round();
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in PlayerPane.values)
            _dot(
              context,
              p,
              // 1 是在這頁，0 是離它一頁以上。
              1 - (position - p.index).abs().clamp(0.0, 1.0),
              label: t.player.pages.label(
                page: names[p]!,
                number: p.index + 1,
                total: PlayerPane.values.length,
              ),
              selected: current == p.index,
            ),
        ],
      ),
    );
  }

  Widget _dot(
    BuildContext context,
    PlayerPane p,
    double on, {
    required String label,
    required bool selected,
  }) {
    final width = 7 + 13 * on;
    // 每個點的點擊區 44×44（`DESIGN.md`〈無障礙〉）；看得到的點照稿 7 高、點之間
    // 7（`.pl-dots` 的 gap），所以點靠在點擊區朝向另一個點的那一邊。
    final first = p == PlayerPane.values.first;
    final last = p == PlayerPane.values.last;
    return ShellButton(
      key: Key('player-dot-${p.name}'),
      onTap: () => onSelect(p),
      label: label,
      selected: selected,
      focusRadius: 999,
      builder: (context, _) => Container(
        width: 44,
        height: 44,
        alignment: first
            ? Alignment.centerRight
            : last
            ? Alignment.centerLeft
            : Alignment.center,
        padding: EdgeInsets.only(left: first ? 0 : 3.5, right: last ? 0 : 3.5),
        child: Container(
          width: width,
          height: 7,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF).withValues(alpha: .38 + .62 * on),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
