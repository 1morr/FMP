import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// list-detail 頁（設定頁、Debug 頁，M3 canonical layout）的窄版：點進去的那一組是推在頁面所在
/// Navigator 上的 route，所以返回鈕、系統返回鍵、Esc 與 iOS 的右滑返回都是 Navigator 的（擁有者決定
/// 2026-11-04）。寬版兩欄在同一頁，不推 route。
///
/// 選了哪一組記在 [selected]（寬版 `null` 是預設的第一組，窄版 `null` 是清單）。視窗跨過斷點時
/// （[syncNarrow]，每次 build 呼叫）：變寬拿掉 route、留著選的組；變窄時有選的組就推它。這兩種都沒有
/// 轉場，在這一幀之後做（build 中不能動 Navigator）。使用者退出那一組（返回、右滑、再點導覽項）時
/// [selected] 回到 `null`。
mixin ListDetailRoutes<W extends StatefulWidget, T extends Object> on State<W> {
  /// 使用者選的那一組。
  T? selected;

  /// 窄版推上去、還開著的那一組的 route。
  Route<void>? _detail;

  /// 上一次 build 的版面。
  bool? _narrow;

  /// 窄版那一組的 route 還在。變寬的那一幀它還蓋在頁面上（這一幀之後才拿掉），頁面那時照窄版只畫
  /// 清單：被蓋住的頁面這一幀不會重新排版，先畫兩欄的話右欄是用窄版的寬度排的。
  bool get detailOpen => _detail != null;

  /// 窄版那一組的整頁（含頁頂與返回鈕）。
  Widget buildDetailPage(BuildContext context, T item);

  /// 選 [item]（清單的一列，或別處要它顯示某一組）。窄版推它的 route：已經有一組開著時換掉它
  /// （連同它上面的頁），返回仍是回到清單。
  void select(T item) {
    setState(() => selected = item);
    if (_narrow ?? false) _push(item, animate: true);
  }

  /// 以這一次 build 的版面呼叫。
  void syncNarrow({required bool narrow}) {
    final previous = _narrow;
    _narrow = narrow;
    if (previous == narrow) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _narrow != narrow) return;
      final item = selected;
      if (!narrow) {
        // 拿掉之後才畫兩欄（見 [detailOpen]）。
        setState(removeDetail);
      } else if (item != null &&
          _detail == null &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        // 頁面上面已經有別的頁（寬版從某一組開的內頁）時不推：route 只能疊在最上面。那一頁
        // 關掉之後是清單。
        _push(item, animate: false);
      }
    });
  }

  /// 拿掉窄版那一組的 route（沒有轉場），[selected] 不變。頁面自己要關掉時（Debug 頁）先呼叫。
  void removeDetail() {
    final route = _detail;
    _detail = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  void _push(T item, {required bool animate}) {
    final navigator = Navigator.of(context);
    final page = ModalRoute.of(context);
    final route = _DetailRoute(
      animate: animate,
      builder: (context) => buildDetailPage(context, item),
    );
    final previous = _detail;
    _detail = route;
    unawaited(route.popped.then((_) => _closed(route)));
    if (previous != null && previous.isActive && page != null) {
      unawaited(navigator.pushAndRemoveUntil(route, (r) => identical(r, page)));
    } else {
      unawaited(navigator.push(route));
    }
  }

  void _closed(Route<void> route) {
    if (!identical(_detail, route)) return;
    _detail = null;
    if (mounted) setState(() => selected = null);
  }
}

/// 窄版那一組的 route：一般的 `MaterialPageRoute`（iOS 是 Cupertino 轉場與右滑返回）；跨斷點補推時
/// 沒有進場轉場，退出時照常（退出用 `reverseTransitionDuration`）。
final class _DetailRoute extends MaterialPageRoute<void> {
  _DetailRoute({required this.animate, required super.builder});

  final bool animate;

  @override
  Duration get transitionDuration =>
      animate ? super.transitionDuration : Duration.zero;
}
