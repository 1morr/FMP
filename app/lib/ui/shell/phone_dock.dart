import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/search/search_field.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 手機 dock 的高度（`docs/design/DESIGN.md`〈手機〉）：迷你播放器、導覽膠囊與
/// 搜尋圓鈕都在這 160 裡，底部漸層淡出底色。
const double phoneDockHeight = 160;

/// 手機底部的 dock：上面是迷你播放器（沒有目前曲目時不出現，導覽留在
/// 原位），下面左邊是導覽膠囊，右邊是搜尋圓鈕。捲動時不收合。
///
/// 在搜尋頁時（[current] 是搜尋）換成搜尋模式：導覽收成左邊的圓鈕（顯示
/// 進搜尋前的分頁 [lastTab]，點了回去），搜尋圓鈕展開成欄位。欄位聚焦（鍵盤
/// 升起）時貼在鍵盤上方、撐滿寬度，圓鈕與迷你播放器暫時藏起來。
class PhoneDock extends StatefulWidget {
  const PhoneDock({
    super.key,
    required this.current,
    required this.lastTab,
    required this.onTab,
    required this.onSearch,
    required this.onLeaveSearch,
  });

  final Destination current;
  final Destination lastTab;
  final ValueChanged<Destination> onTab;
  final VoidCallback onSearch;
  final VoidCallback onLeaveSearch;

  @override
  State<PhoneDock> createState() => _PhoneDockState();
}

class _PhoneDockState extends State<PhoneDock> {
  bool _fieldFocused = false;

  @override
  void didUpdateWidget(PhoneDock old) {
    super.didUpdateWidget(old);
    // 欄位帶著焦點被拿掉時收不到失焦的通知。
    if (widget.current != Destination.search) _fieldFocused = false;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final keyboard = media.viewInsets.bottom;
    final searching = widget.current == Destination.search;
    final typing = searching && _fieldFocused && keyboard > 0;
    // 稿上 iPhone（安全區 34）的膠囊離螢幕底 10；安全區更高時跟著上移。
    final lift = typing
        ? keyboard
        : math.max(0.0, media.viewPadding.bottom - 34);
    final colors = context.fmpColors;
    final t = context.t;

    const top = 88.0;
    const side = 14.0;
    const orb = 62.0;
    final wideWidth = width - 100;

    return Stack(
      children: [
        // 底部漸層：從透明淡到 55% 的底色（`.dock::before`）。
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: phoneDockHeight + lift,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: FmpMotion.mid,
              opacity: typing ? 0 : 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.bg.withValues(alpha: 0),
                      colors.bg.withValues(alpha: .55),
                    ],
                    stops: const [0, .7],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: lift,
          height: phoneDockHeight,
          child: Stack(
            children: [
              // 迷你播放器：362×56，left 14、top 24（390 寬時）。
              Positioned(
                left: side,
                right: side,
                top: 24,
                height: 56,
                child: IgnorePointer(
                  ignoring: typing,
                  child: AnimatedOpacity(
                    duration: FmpMotion.mid,
                    opacity: typing ? 0 : 1,
                    child: const _MiniSlot(),
                  ),
                ),
              ),
              // 左：導覽膠囊 ↔ 回到分頁的圓鈕。
              AnimatedPositioned(
                duration: FmpMotion.morph,
                curve: FmpMotion.morphCurve,
                left: side,
                top: top,
                width: searching ? orb : wideWidth,
                height: orb,
                child: AnimatedOpacity(
                  duration: FmpMotion.mid,
                  opacity: typing ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: typing,
                    // 圓鈕包在按鈕裡，焦點外框才畫在玻璃外面、不被裁掉。
                    child: searching
                        ? _BackOrb(
                            tab: widget.lastTab,
                            label: t.shell.nav.backTo(
                              tab: widget.lastTab.label(t),
                            ),
                            onTap: widget.onLeaveSearch,
                          )
                        : Glass(
                            child: _FixedWidth(
                              width: wideWidth,
                              child: _TabBar(
                                current: widget.current,
                                onTab: widget.onTab,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              // 右：搜尋圓鈕 ↔ 搜尋欄。
              AnimatedPositioned(
                duration: FmpMotion.morph,
                curve: FmpMotion.morphCurve,
                left: typing
                    ? side
                    : searching
                    ? side + orb + 10
                    : width - side - orb,
                top: typing ? phoneDockHeight - 76 + 8 : top,
                width: typing
                    ? width - side * 2
                    : searching
                    ? wideWidth
                    : orb,
                height: typing ? 56 : orb,
                child: searching
                    ? Glass(
                        child: _FixedWidth(
                          width: typing ? width - side * 2 : wideWidth,
                          child: SearchField(
                            placement: SearchFieldPlacement.dock,
                            onFocusChanged: (focused) =>
                                setState(() => _fieldFocused = focused),
                          ),
                        ),
                      )
                    : ShellButton(
                        onTap: widget.onSearch,
                        tooltip: t.shell.nav.search,
                        label: t.shell.nav.search,
                        focusRadius: 999,
                        builder: (context, _) => const Glass(
                          child: Center(
                            child: FmpIcon(
                              FmpIcons.search,
                              size: 25,
                              strokeWidth: 1.7,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 有目前曲目時的迷你播放器；出現與消失時淡入淡出、往下滑 20
/// （`.dock.no-mini .mini`）。
class _MiniSlot extends ConsumerWidget {
  const _MiniSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackProvider);
    return AnimatedSwitcher(
      duration: FmpMotion.mid,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 20 / 56),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: state == null
          ? const SizedBox.shrink()
          : MiniPlayer(key: const ValueKey('mini'), state: state),
    );
  }
}

/// 變形途中盒子比內容窄時，內容照最後的寬度排、靠左，多的由玻璃裁掉。
class _FixedWidth extends StatelessWidget {
  const _FixedWidth({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => OverflowBox(
    alignment: Alignment.centerLeft,
    minWidth: width,
    maxWidth: width,
    child: child,
  );
}

class _BackOrb extends StatelessWidget {
  const _BackOrb({required this.tab, required this.label, required this.onTap});

  final Destination tab;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ShellButton(
    onTap: onTap,
    tooltip: label,
    label: label,
    focusRadius: 999,
    builder: (context, _) => Glass(
      child: Center(child: FmpIcon(tab.icon, size: 25, strokeWidth: 1.7)),
    ),
  );
}

/// 導覽膠囊：四項平分，選取的那項有一顆內嵌膠囊（`.tab-ind`），換項目時用
/// spring 滑過去，按下時放大一點。
class _TabBar extends StatefulWidget {
  const _TabBar({required this.current, required this.onTab});

  final Destination current;
  final ValueChanged<Destination> onTab;

  @override
  State<_TabBar> createState() => _TabBarState();
}

class _TabBarState extends State<_TabBar> {
  bool _pressing = false;

  void _press(Destination tab) {
    setState(() => _pressing = true);
    Future<void>.delayed(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _pressing = false);
    });
    widget.onTab(tab);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final selected = Destination.tabs.indexOf(widget.current);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: t.shell.nav.label,
      child: LayoutBuilder(
        builder: (context, box) {
          const pad = 4.0;
          final tabWidth = (box.maxWidth - pad * 2) / Destination.tabs.length;
          return Stack(
            children: [
              if (selected >= 0)
                AnimatedPositioned(
                  duration: FmpMotion.spring,
                  curve: FmpMotion.springCurve,
                  left: pad + tabWidth * selected,
                  top: 4,
                  width: tabWidth,
                  height: 54,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: _pressing ? 1 : 0),
                    duration: const Duration(milliseconds: 220),
                    curve: FmpMotion.outCurve,
                    builder: (context, p, child) => Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(
                        1 + .12 * p,
                        1 + .18 * p,
                        1,
                      ),
                      child: child,
                    ),
                    child: const _Indicator(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: pad),
                child: Row(
                  children: [
                    for (final tab in Destination.tabs)
                      Expanded(
                        child: ShellButton(
                          onTap: () => _press(tab),
                          selected: tab == widget.current,
                          // 同選取膠囊（`.tab-ind`）的圓角。
                          focusRadius: 27,
                          builder: (context, _) => _Tab(
                            icon: tab.icon,
                            label: tab.label(t),
                            color: tab == widget.current
                                ? colors.accent
                                : colors.glassInk,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.fmpColors.glassPress,
      borderRadius: BorderRadius.circular(27),
      border: Border.all(
        color: const Color.fromRGBO(255, 255, 255, .25),
        width: .5,
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.color});

  final FmpIcons icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FmpIcon(icon, size: 25, strokeWidth: 1.7, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: .105,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
