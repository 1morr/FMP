import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/platform/window_drag.dart';
import 'package:fmp/ui/search/search_query.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/detail_panel.dart';
import 'package:fmp/ui/shell/nav_rail.dart';
import 'package:fmp/ui/shell/phone_dock.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:fmp/ui/shell/side_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 桌面與中寬度內容底部讓給播放膠囊的高度（膠囊 64、離底 16，再留一點）。
const double _transportInset = 120;

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
          body: shell,
        ),
      ),
    );
  }

  Widget _content(EdgeInsets padding) =>
      ShellInsets(padding: padding, child: widget.child);

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
          ),
        ),
        Positioned.fill(
          child: PhoneDock(
            current: _current,
            lastTab: _lastTab,
            onTab: _select,
            onSearch: _openSearch,
            onLeaveSearch: _leaveSearch,
          ),
        ),
      ],
    );
  }

  Widget _medium(BuildContext context, bool touch) {
    final media = MediaQuery.of(context);
    final top0 = touch ? media.viewPadding.top : 0.0;
    // 平板的細欄與浮動面板離底 20（讓出 home indicator）。
    final bottom = touch ? math.max(20.0, media.viewPadding.bottom) : 8.0;
    final side = NavRail.widthOf(touch: touch) + 8;
    final panelWidth = DetailPanel.widthOf(touch: touch, floating: true);
    return Stack(
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
          ),
        ),
        // 頂列的空白處拖動視窗（macOS）。
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: top0 + 58,
          child: const WindowDragArea(),
        ),
        Positioned(
          left: 8,
          top: top0 + 8,
          bottom: bottom,
          width: NavRail.widthOf(touch: touch),
          child: NavRail(current: _current, touch: touch, onSelect: _select),
        ),
        if (!_floatingDetail)
          _detailButton(touch, top0, () {
            setState(() => _floatingDetail = true);
          })
        else ...[
          // 點外面關掉。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _floatingDetail = false),
            ),
          ),
          Positioned(
            top: top0 + 8,
            right: 8,
            bottom: bottom,
            width: panelWidth,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    setState(() => _floatingDetail = false),
              },
              child: Focus(
                autofocus: true,
                child: DetailPanel(
                  touch: touch,
                  floating: true,
                  onHide: () => setState(() => _floatingDetail = false),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _wide(BuildContext context, bool touch) {
    final media = MediaQuery.of(context);
    final top0 = touch ? media.viewPadding.top : 0.0;
    final open = _detailVisible;
    final panelWidth = DetailPanel.widthOf(touch: touch, floating: false);
    return Stack(
      children: [
        Positioned(
          left: SideBar.width + 8,
          top: 0,
          right: open ? panelWidth : 0,
          bottom: 0,
          child: _content(
            EdgeInsets.fromLTRB(8, top0 + 66, 32, _transportInset),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: top0 + 58,
          child: const WindowDragArea(),
        ),
        Positioned(
          left: 8,
          top: top0 + 8,
          bottom: math.max(8.0, media.viewPadding.bottom),
          width: SideBar.width,
          child: SideBar(
            current: _current,
            onSelect: _select,
            onSearch: _openSearch,
          ),
        ),
        if (open)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: panelWidth,
            child: DetailPanel(
              touch: touch,
              topInset: top0,
              onHide: () => _setDetail(false),
            ),
          )
        else
          _detailButton(touch, top0, () => _setDetail(true)),
      ],
    );
  }

  /// 頂列右端叫出詳情面板的玻璃鈕（`sidebarR`）。
  Widget _detailButton(bool touch, double top0, VoidCallback onTap) {
    return Positioned(
      // 頂列 `.wtop`：離頂 8（平板 6）、高 50（平板 52），右邊 8 再內縮 16。
      top: top0 + (touch ? 6 + (52 - 44) / 2 : 8 + (50 - 34) / 2),
      right: 24,
      child: GlassIconButton(
        icon: FmpIcons.sidebarR,
        tooltip: context.t.shell.detail.show,
        onTap: onTap,
        touch: touch,
      ),
    );
  }
}
