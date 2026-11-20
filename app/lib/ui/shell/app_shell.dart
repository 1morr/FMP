import 'dart:async';
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
import 'package:fmp/ui/common/inert.dart';
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

class _AppShellState extends ConsumerState<AppShell>
    with TickerProviderStateMixin {
  /// 進搜尋前最後在的分頁：手機搜尋模式的左圓鈕顯示它。
  late Destination _lastTab = _tabOrHome(Destination.of(widget.location));

  /// 寬級的詳情面板；設定頁預設收起（`docs/design/DESIGN.md`〈桌面〉）。
  bool _detailOpen = true;
  bool _settingsDetailOpen = false;

  /// 中寬度浮出的詳情面板。
  bool _floatingDetail = false;

  /// 詳情面板叫出與收起的過場（`docs/design/DESIGN.md`〈動態〉的 morph）：0 收起、
  /// 1 打開。寬級的常駐面板一個、中寬度的浮動面板一個。減少動態效果時照樣
  /// 跑完整長度（[AnimationBehavior.preserve]；預設會縮成 1/20，淡入淡出就
  /// 看不到了），只是不位移（[_panelLerp]、[_panelMotion]）。
  late final _dockMotion = AnimationController(
    vsync: this,
    duration: FmpMotion.morph,
    value: _detailVisible ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final _floatMotion = AnimationController(
    vsync: this,
    duration: FmpMotion.morph,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// 收起時曲線反過來用，兩個方向都是先快後慢、停得很輕。
  late final _dock = CurvedAnimation(
    parent: _dockMotion,
    curve: FmpMotion.morphCurve,
    reverseCurve: FmpMotion.morphCurve.flipped,
  );
  late final _float = CurvedAnimation(
    parent: _floatMotion,
    curve: FmpMotion.morphCurve,
    reverseCurve: FmpMotion.morphCurve.flipped,
  );

  /// 浮出的詳情面板打開時拿焦點，Esc 才關得掉：焦點已經在別處時
  /// `autofocus` 不會搶過來。
  final _floatingDetailFocus = FocusNode(debugLabel: 'floating detail');

  @override
  void dispose() {
    _dock.dispose();
    _float.dispose();
    _dockMotion.dispose();
    _floatMotion.dispose();
    _floatingDetailFocus.dispose();
    super.dispose();
  }

  void _openFloatingDetail() {
    setState(() => _floatingDetail = true);
    _floatMotion.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _floatingDetail) _floatingDetailFocus.requestFocus();
    });
  }

  void _closeFloatingDetail() {
    setState(() => _floatingDetail = false);
    _floatMotion.reverse();
  }

  Destination get _current => Destination.of(widget.location);

  static Destination _tabOrHome(Destination d) =>
      d == Destination.search ? Destination.home : d;

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    if (_current != Destination.search) _lastTab = _current;
    // 換分頁直接換（`DESIGN.md`〈狀態變化對照〉刻意不動）：進出設定頁時面板跟著
    // 那一頁記得的開合，不跑過場。
    if (Destination.of(old.location) != _current) {
      _dockMotion.value = _detailVisible ? 1 : 0;
    }
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

  void _setDetail(bool open) {
    setState(() {
      if (_current == Destination.settings) {
        _settingsDetailOpen = open;
      } else {
        _detailOpen = open;
      }
    });
    open ? _dockMotion.forward() : _dockMotion.reverse();
  }

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
        child: Actions(
          actions: {
            NextFocusIntent: _SkipEmptyPage<NextFocusIntent>(forward: true),
            PreviousFocusIntent: _SkipEmptyPage<PreviousFocusIntent>(
              forward: false,
            ),
          },
          child: Scaffold(
            backgroundColor: context.fmpColors.bg,
            resizeToAvoidBottomInset: false,
            body: WindowChrome.captionButtons
                ? Stack(
                    children: [
                      Positioned.fill(child: shell),
                      Positioned(
                        top: 0,
                        right: 0,
                        // 中寬度的「顯示詳情面板」是視窗鈕列的第四顆。
                        child: CaptionButtons(
                          onShowDetail: form.widthClass == WidthClass.medium
                              ? _openFloatingDetail
                              : null,
                          showDetailVisible: !_floatingDetail,
                        ),
                      ),
                    ],
                  )
                : shell,
          ),
        ),
      ),
    );
  }

  /// 內容區。[dragStrip] 是頂端拖動視窗的區域高；那裡只有頁面頂列的控制項
  /// 收得到點擊（[ShellTopStripGate]）。
  Widget _content(
    EdgeInsets padding,
    ShellTopBar topBar, {
    double? dragStrip,
    bool detailPanelOpen = false,
  }) {
    final content = ShellInsets(
      padding: padding,
      topBar: topBar,
      detailPanelOpen: detailPanelOpen,
      child: widget.child,
    );
    if (dragStrip == null || !WindowChrome.drawsTitleBar) return content;
    return ShellTopStripGate(height: dragStrip, child: content);
  }

  /// 頂列右端讓給詳情面板鈕（`_detailButton`）：鈕本身、右邊的 16 與鈕前
  /// 的 8；內容區右緣就是視窗右緣時才要（以視窗右緣算 [_captionInset]）。
  static double _detailButtonInset(bool touch) =>
      8 + _captionInset(8) + 16 + (touch ? 44 : 34) + 8;

  /// 中寬度頂列右端讓出的寬度：Windows 讓給四顆視窗鈕（含詳情面板鈕）與鈕前
  /// 的 8，其他平台讓給玻璃鈕。
  static double _mediumTopBarInset(bool touch) => WindowChrome.captionButtons
      ? WindowChrome.captionButtonsWidth +
            WindowChrome.captionButtonSize.width +
            8
      : _detailButtonInset(touch);

  /// 面板過場的進度 [t] 換成 [closed] 到 [open] 之間的值；減少動態效果時
  /// 版面直接到 [opened] 那一端，只有面板自己淡入淡出。
  double _panelLerp(
    double t,
    double closed,
    double open, {
    required bool opened,
  }) => FmpMotion.reduced(context)
      ? (opened ? open : closed)
      : closed + (open - closed) * t;

  /// 過場中的面板：叫出時到位才收得到點擊與焦點，收起的過場裡已經是不在
  /// 的樣子（點不到、Tab 不到、螢幕閱讀器讀不到）。
  Widget _panelMotion({
    required bool opened,
    required double t,
    required double slide,
    required bool fade,
    required Widget child,
  }) {
    final reduced = FmpMotion.reduced(context);
    return Opacity(
      key: const Key('detail-panel-motion'),
      opacity: reduced || fade ? t.clamp(0.0, 1.0) : 1,
      child: Transform.translate(
        offset: Offset(reduced ? 0 : (1 - t) * slide, 0),
        child: Inert(inert: !opened, child: child),
      ),
    );
  }

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
    return AnimatedBuilder(
      animation: _float,
      builder: (context, _) => _mediumFrame(context, touch, _float.value),
    );
  }

  /// 中寬度的版面，浮動面板過場到 [t]。
  Widget _mediumFrame(BuildContext context, bool touch, double t) {
    final media = MediaQuery.of(context);
    final top0 = touch ? media.viewPadding.top : 0.0;
    // 平板的細欄與浮動面板離底 20（讓出 home indicator）。
    final bottom = touch ? math.max(20.0, media.viewPadding.bottom) : 8.0;
    final side = NavRail.widthOf(touch: touch) + 8;
    final panelWidth = DetailPanel.widthOf(touch: touch, floating: true);
    final opened = _floatingDetail;
    // 播放膠囊：離細欄 24（left 104，平板 112），叫出面板時右端讓到面板
    // 左邊 24，跟著面板的過場。
    final transportRight = _panelLerp(
      t,
      24,
      8 + panelWidth + 24,
      opened: opened,
    );
    final panelShown = !_floatMotion.isDismissed;
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
                right: _mediumTopBarInset(touch),
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
          ..._transport(
            left: side + 24,
            right: transportRight,
            bottom: touch ? bottom : 16,
            touch: touch,
          ),
          // Windows 的叫出鈕在視窗鈕那一列（[CaptionButtons]）。
          if (!WindowChrome.captionButtons && !_floatMotion.isCompleted)
            _detailButton(touch, top0, _openFloatingDetail, inert: opened),
          // 點外面關掉。
          if (opened)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeFloatingDetail,
              ),
            ),
          if (panelShown)
            Positioned(
              // Windows 上從視窗鈕下方開始。
              top: top0 + WindowChrome.captionButtonsHeight + 8,
              right: 8,
              bottom: bottom,
              width: panelWidth,
              // 從視窗右緣外滑進來。
              child: _panelMotion(
                opened: opened,
                t: t,
                slide: panelWidth + 8,
                fade: true,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape):
                        _closeFloatingDetail,
                  },
                  child: Focus(
                    focusNode: _floatingDetailFocus,
                    // 只為了接 Esc；整塊面板對螢幕閱讀器不是一個可聚焦的東西。
                    includeSemantics: false,
                    child: DetailPanel(
                      touch: touch,
                      floating: true,
                      onHide: _closeFloatingDetail,
                    ),
                  ),
                ),
              ),
            ),
          _transportToast(
            left: side + 24,
            right: transportRight,
            bottom: touch ? bottom : 16,
            touch: touch,
          ),
        ],
      ),
    );
  }

  Widget _wide(BuildContext context, bool touch) {
    return AnimatedBuilder(
      animation: _dock,
      builder: (context, _) => _wideFrame(context, touch, _dock.value),
    );
  }

  /// 寬級的版面，常駐面板過場到 [t]：面板寬度跟著動，內容欄與播放膠囊一起讓。
  Widget _wideFrame(BuildContext context, bool touch, double t) {
    final media = MediaQuery.of(context);
    final top0 = touch ? media.viewPadding.top : 0.0;
    final open = _detailVisible;
    final panelWidth = DetailPanel.widthOf(touch: touch, floating: false);
    final transportBottom = touch
        ? math.max(20.0, media.viewPadding.bottom)
        : 16.0;
    // 面板佔掉的寬度：內容欄的右緣、播放膠囊右端都從這裡算。
    final taken = _panelLerp(t, 0, panelWidth, opened: open);
    // 播放膠囊：左右各離側欄與詳情面板 24（left 280、right 344）。
    final transportRight = taken + 24;
    // 頂端 58 是拖動視窗的區域（macOS、Windows）；包在外面，裡面的按鈕先拿到點擊。
    return WindowDragArea(
      height: top0 + 58,
      child: Stack(
        children: [
          Positioned(
            left: SideBar.width + 8,
            top: 0,
            right: taken,
            bottom: 0,
            child: _content(
              EdgeInsets.fromLTRB(24, top0 + 66, 32, _transportInset),
              ShellTopBar(
                top: top0 + (touch ? 6 : 8),
                height: touch ? 52 : 50,
                left: 24,
                right: _panelLerp(
                  t,
                  _detailButtonInset(touch),
                  16,
                  opened: open,
                ),
              ),
              dragStrip: top0 + 58,
              detailPanelOpen: open,
            ),
          ),
          Positioned(
            left: 8,
            top: top0 + 8,
            bottom: math.max(8.0, media.viewPadding.bottom),
            width: SideBar.width,
            child: SideBar(
              current: _current,
              touch: touch,
              onSelect: _select,
              onSearch: _focusSearch,
            ),
          ),
          ..._transport(
            left: SideBar.width + 8 + 24,
            right: transportRight,
            bottom: transportBottom,
            touch: touch,
          ),
          if (!_dockMotion.isCompleted)
            _detailButton(touch, top0, () => _setDetail(true), inert: open),
          if (!_dockMotion.isDismissed)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: panelWidth,
              // 面板跟著讓出的寬度從右緣推進來（寬度不變，內容不重排）。
              child: _panelMotion(
                opened: open,
                t: t,
                slide: panelWidth,
                fade: false,
                child: DetailPanel(
                  touch: touch,
                  // Windows 上標頭讓出視窗鈕那一列。
                  topInset: top0 + WindowChrome.captionButtonsHeight,
                  onHide: () => _setDetail(false),
                ),
              ),
            ),
          _transportToast(
            left: SideBar.width + 8 + 24,
            right: transportRight,
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

  /// 頂列右端叫出詳情面板的玻璃鈕（`sidebarR`）。面板的過場中它還在原位：
  /// 打開時被面板蓋過去，收起時面板滑開就露出來；面板打開時（含過場中，
  /// [inert]）點不到、Tab 不到、螢幕閱讀器讀不到。
  Widget _detailButton(
    bool touch,
    double top0,
    VoidCallback onTap, {
    required bool inert,
  }) {
    return Positioned(
      // 頂列 `.wtop`：離頂 8（平板 6）、高 50（平板 52），右邊 8 再內縮 16。
      top: top0 + (touch ? 6 + (52 - 44) / 2 : 8 + (50 - 34) / 2),
      right: 8 + _captionInset(8) + 16,
      child: Inert(
        inert: inert,
        child: GlassIconButton(
          icon: FmpIcons.sidebarR,
          tooltip: context.t.shell.detail.show,
          onTap: onTap,
          touch: touch,
        ),
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

/// Tab 不停在沒有可聚焦東西的頁面（例如空狀態、還沒搜過的搜尋頁）：頁面在
/// 外殼裡自己的路由，那個焦點範圍是空的時，框架的 Tab 會停在它上面（看不到
/// 外框），從它再按也一直把焦點還給它自己，走不到外殼的導覽與播放控制。這裡
/// 照框架預設（`NextFocusAction`）走一格，落在空的頁面就在外殼那一層再走一
/// 格。一律接手：Actions 找到最近的動作就停，停用的動作不會讓給上層的預設，
/// Tab 會整個失效。
class _SkipEmptyPage<T extends Intent> extends Action<T> {
  _SkipEmptyPage({required this.forward});

  final bool forward;

  static FocusScopeNode? get _emptyPage {
    final focus = FocusManager.instance.primaryFocus;
    return focus is FocusScopeNode &&
            focus.enclosingScope != null &&
            focus.traversalDescendants.isEmpty
        ? focus
        : null;
  }

  bool _step(FocusNode from) =>
      forward ? from.nextFocus() : from.previousFocus();

  @override
  Object? invoke(T intent) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final moved = _step(_emptyPage?.enclosingScope ?? focus);
    // 焦點在 microtask 裡才換過去；換完落在空的頁面上就再走一格。
    scheduleMicrotask(() {
      if (_emptyPage case final page?) _step(page.enclosingScope!);
    });
    return moved;
  }
}
