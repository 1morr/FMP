import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/platform/window_drag.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:fmp/ui/search/search_query.dart';
import 'package:fmp/ui/shell/caption_buttons.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/detail_panel.dart';
import 'package:fmp/ui/shell/nav_rail.dart';
import 'package:fmp/ui/shell/phone_dock.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:fmp/ui/shell/side_bar.dart';
import 'package:fmp/ui/toast/toast_layer.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 桌面與中寬度內容底部讓給播放膠囊的高度（膠囊 64、離底 16，再留一點）。
const double _transportInset = 120;

/// 提示和它下面的迷你播放器或播放膠囊之間的距離。
const double _toastGap = 12;

/// App 的外殼（`docs/design/DESIGN.md`〈外殼〉）：導覽浮在 [child]（目前路由的頁面）
/// 上面，依寬度分級換版面：窄是底部 dock，中是左側玻璃細欄，寬是左側玻璃
/// 側欄加右側詳情面板。
///
/// 導覽：分頁用 `go` 換掉整疊；搜尋用 `push` 疊在目前的分頁上，返回就回到
/// 那個分頁。非首頁的分頁按系統返回回首頁，首頁再返回才離開 App。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  /// 目前路由的路徑。
  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// 進搜尋前最後在的分頁：手機搜尋模式的左圓鈕顯示它。
  late Destination _lastTab = _tabOrHome(Destination.of(widget.location));

  /// 寬級的詳情面板；設定頁預設收起（`docs/design/DESIGN.md`〈桌面〉）。
  bool _detailOpen = true;
  bool _settingsDetailOpen = false;

  /// 中寬度浮出的詳情面板。
  bool _floatingDetail = false;

  /// 浮出的詳情面板打開時拿焦點，Esc 才關得掉：焦點已經在別處時
  /// `autofocus` 不會搶過來。
  final _floatingDetailFocus = FocusNode(debugLabel: 'floating detail');

  @override
  void dispose() {
    _floatingDetailFocus.dispose();
    super.dispose();
  }

  void _openFloatingDetail() {
    setState(() => _floatingDetail = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _floatingDetail) _floatingDetailFocus.requestFocus();
    });
  }

  Destination get _current => Destination.of(widget.location);

  static Destination _tabOrHome(Destination d) =>
      d == Destination.search ? Destination.home : d;

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    if (_current != Destination.search) _lastTab = _current;
  }

  void _select(Destination d) {
    if (d == Destination.search) return _openSearch();
    if (d == _current) return;
    context.go(d.path);
  }

  void _openSearch() {
    if (_current == Destination.search) return;
    context.push(Destination.search.path);
  }

  void _leaveSearch() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(_lastTab.path);
    }
  }

  void _focusSearch() {
    _openSearch();
    ref.read(searchFocusRequestProvider.notifier).request();
  }

  bool get _detailVisible =>
      _current == Destination.settings ? _settingsDetailOpen : _detailOpen;

  void _setDetail(bool open) => setState(() {
    if (_current == Destination.settings) {
      _settingsDetailOpen = open;
    } else {
      _detailOpen = open;
    }
  });

  @override
  Widget build(BuildContext context) {
    final form = FormFactor.of(context);
    final shell = switch (form.widthClass) {
      WidthClass.narrow => _phone(context),
      WidthClass.medium => _medium(context, form.density == Density.touch),
      WidthClass.wide => _wide(context, form.density == Density.touch),
    };
    return PopScope(
      canPop: _current == Destination.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_current == Destination.search) {
          _leaveSearch();
        } else {
          context.go(Destination.home.path);
        }
      },
      child: CallbackShortcuts(
        bindings: {
          WindowChrome.shortcut(LogicalKeyboardKey.keyK): _focusSearch,
        },
        child: Scaffold(
          backgroundColor: context.fmpColors.bg,
          resizeToAvoidBottomInset: false,
          body: WindowChrome.captionButtons
              ? Stack(
                  children: [
                    Positioned.fill(child: shell),
                    const Positioned(top: 0, right: 0, child: CaptionButtons()),
                  ],
                )
              : shell,
        ),
      ),
    );
  }

  /// 內容區。[dragStrip] 是頂端拖動視窗的區域高；那裡只有頁面頂列的控制項
  /// 收得到點擊（[ShellTopStripGate]）。
  Widget _content(EdgeInsets padding, ShellTopBar topBar, {double? dragStrip}) {
    final content = ShellInsets(
      padding: padding,
      topBar: topBar,
      child: widget.child,
    );
    if (dragStrip == null || !WindowChrome.drawsTitleBar) return content;
    return ShellTopStripGate(height: dragStrip, child: content);
  }

  /// 頂列右端讓給詳情面板鈕（`_detailButton`）：鈕本身、右邊的 16 與鈕前
  /// 的 8；內容區右緣就是視窗右緣時才要（以視窗右緣算 [_captionInset]）。
  static double _detailButtonInset(bool touch) =>
      8 + _captionInset(8) + 16 + (touch ? 44 : 34) + 8;

  Widget _phone(BuildContext context) {
    final media = MediaQuery.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: _content(
            EdgeInsets.fromLTRB(
              20,
              media.viewPadding.top + 62,
              20,
              phoneDockHeight + 20,
            ),
            // `.ptop`：狀態列下方、高 52、左右 16。
            ShellTopBar(
              top: media.viewPadding.top,
              height: 52,
              left: 16,
              right: 16,
            ),
          ),
        ),
        if (!ref.watch(dockHiddenProvider))
          Positioned.fill(
            child: PhoneDock(
              current: _current,
              lastTab: _lastTab,
              onTab: _select,
              onSearch: _openSearch,
              onLeaveSearch: _leaveSearch,
            ),
          ),
        // 稿的 844 高框裡：有迷你播放器時離底 176，沒有時 112；安全區更高
        // 時和 dock 一起上移。
        Positioned.fill(
          child: ToastLayer(
            bottom:
                (_hasTrack ? 176.0 : 112.0) +
                math.max(0.0, media.viewPadding.bottom - 34),
            stretch: true,
            touch: true,
          ),
        ),
      ],
    );
  }

  bool get _hasTrack => ref.watch(playbackProvider.select((s) => s != null));

  /// 播放膠囊（有目前曲目時）。
  List<Widget> _transport({
    required double left,
    required double right,
    required double bottom,
    required bool touch,
  }) => [
    if (_hasTrack)
      Positioned(
        left: left,
        right: right,
        bottom: bottom,
        child: _Transport(touch: touch),
      ),
  ];

  /// 播放膠囊上方的提示，和膠囊同樣的左右範圍、在內容欄置中；疊在最上層，
  /// 浮動面板開著時也按得到。
  Widget _transportToast({
    required double left,
    required double right,
    required double bottom,
    required bool touch,
  }) => Positioned.fill(
    child: ToastLayer(
      bottom: _hasTrack
          ? bottom + TransportBar.heightOf(touch: touch) + _toastGap
          : bottom + 8,
      left: left,
      right: right,
      stretch: false,
      touch: touch,
    ),
  );

  Widget _medium(BuildContext context, bool touch) {
    final media = MediaQuery.of(context);
    final top0 = touch ? media.viewPadding.top : 0.0;
    // 平板的細欄與浮動面板離底 20（讓出 home indicator）。
    final bottom = touch ? math.max(20.0, media.viewPadding.bottom) : 8.0;
    final side = NavRail.widthOf(touch: touch) + 8;
    final panelWidth = DetailPanel.widthOf(touch: touch, floating: true);
    // 頂端 58 是拖動視窗的區域（macOS、Windows）；包在外面，裡面的按鈕先拿到點擊。
    return WindowDragArea(
      height: top0 + 58,
      child: Stack(
        children: [
          Positioned(
            left: side,
            top: 0,
            right: 0,
            bottom: 0,
            child: _content(
              EdgeInsets.fromLTRB(
                24,
                top0 + (touch ? 62 : 66),
                32,
                touch ? 150 : _transportInset,
              ),
              // `.wtop`：離頂 8、高 50（平板 6、52），左 24；右端讓出詳情面板鈕。
              ShellTopBar(
                top: top0 + (touch ? 6 : 8),
                height: touch ? 52 : 50,
                left: 24,
                right: _detailButtonInset(touch),
              ),
              dragStrip: top0 + 58,
            ),
          ),
          Positioned(
            left: 8,
            top: top0 + 8,
            bottom: bottom,
            width: NavRail.widthOf(touch: touch),
            child: NavRail(current: _current, touch: touch, onSelect: _select),
          ),
          // 播放膠囊：離細欄 24（left 104，平板 112），叫出面板時右端讓到
          // 面板左邊 24。
          ..._transport(
            left: side + 24,
            right: _floatingDetail ? 8 + panelWidth + 24 : 24,
            bottom: touch ? bottom : 16,
            touch: touch,
          ),
          if (!_floatingDetail)
            _detailButton(touch, top0, _openFloatingDetail)
          else ...[
            // 點外面關掉。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _floatingDetail = false),
              ),
            ),
            Positioned(
              // Windows 上從視窗鈕下方開始。
              top: top0 + WindowChrome.captionButtonsHeight + 8,
              right: 8,
              bottom: bottom,
              width: panelWidth,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      setState(() => _floatingDetail = false),
                },
                child: Focus(
                  focusNode: _floatingDetailFocus,
                  child: DetailPanel(
                    touch: touch,
                    floating: true,
                    onHide: () => setState(() => _floatingDetail = false),
                  ),
                ),
              ),
            ),
          ],
          _transportToast(
            left: side + 24,
            right: _floatingDetail ? 8 + panelWidth + 24 : 24,
            bottom: touch ? bottom : 16,
            touch: touch,
          ),
        ],
      ),
    );
  }

  Widget _wide(BuildContext context, bool touch) {
    final media = MediaQuery.of(context);
    final top0 = touch ? media.viewPadding.top : 0.0;
    final open = _detailVisible;
    final panelWidth = DetailPanel.widthOf(touch: touch, floating: false);
    final transportBottom = touch
        ? math.max(20.0, media.viewPadding.bottom)
        : 16.0;
    // 頂端 58 是拖動視窗的區域（macOS、Windows）；包在外面，裡面的按鈕先拿到點擊。
    return WindowDragArea(
      height: top0 + 58,
      child: Stack(
        children: [
          Positioned(
            left: SideBar.width + 8,
            top: 0,
            right: open ? panelWidth : 0,
            bottom: 0,
            child: _content(
              EdgeInsets.fromLTRB(24, top0 + 66, 32, _transportInset),
              ShellTopBar(
                top: top0 + (touch ? 6 : 8),
                height: touch ? 52 : 50,
                left: 24,
                right: open ? 16 : _detailButtonInset(touch),
              ),
              dragStrip: top0 + 58,
            ),
          ),
          Positioned(
            left: 8,
            top: top0 + 8,
            bottom: math.max(8.0, media.viewPadding.bottom),
            width: SideBar.width,
            child: SideBar(
              current: _current,
              onSelect: _select,
              onSearch: _focusSearch,
            ),
          ),
          // 播放膠囊：左右各離側欄與詳情面板 24（left 280、right 344）。
          ..._transport(
            left: SideBar.width + 8 + 24,
            right: open ? panelWidth + 24 : 24,
            bottom: transportBottom,
            touch: touch,
          ),
          if (open)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: panelWidth,
              child: DetailPanel(
                touch: touch,
                // Windows 上標頭讓出視窗鈕那一列。
                topInset: top0 + WindowChrome.captionButtonsHeight,
                onHide: () => _setDetail(false),
              ),
            )
          else
            _detailButton(touch, top0, () => _setDetail(true)),
          _transportToast(
            left: SideBar.width + 8 + 24,
            right: open ? panelWidth + 24 : 24,
            bottom: transportBottom,
            touch: touch,
          ),
        ],
      ),
    );
  }

  /// 頂端離視窗右緣 [fromRight] 的東西，右端還要再讓出多少給視窗鈕
  /// （`docs/design/DESIGN.md`〈桌面〉：內容頂列右端讓出 138）。
  static double _captionInset(double fromRight) =>
      math.max(0, WindowChrome.captionButtonsWidth - fromRight);

  /// 頂列右端叫出詳情面板的玻璃鈕（`sidebarR`）。
  Widget _detailButton(bool touch, double top0, VoidCallback onTap) {
    return Positioned(
      // 頂列 `.wtop`：離頂 8（平板 6）、高 50（平板 52），右邊 8 再內縮 16。
      top: top0 + (touch ? 6 + (52 - 44) / 2 : 8 + (50 - 34) / 2),
      right: 8 + _captionInset(8) + 16,
      child: GlassIconButton(
        icon: FmpIcons.sidebarR,
        tooltip: context.t.shell.detail.show,
        onTap: onTap,
        touch: touch,
      ),
    );
  }
}

/// 有目前曲目時的播放膠囊；位置與進度一起變，只有它跟著播放狀態重畫。
class _Transport extends ConsumerWidget {
  const _Transport({required this.touch});

  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackProvider);
    if (state == null) return const SizedBox.shrink();
    return TransportBar(state: state, touch: touch);
  }
}
