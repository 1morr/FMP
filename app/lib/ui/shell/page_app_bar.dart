import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/i18n/ui_locale.dart';

/// 巢狀導覽裡每一頁（外殼的根頁與推上來的內頁）的底：
///
/// - 透明的 `Material`：頁面轉場在頁外包一層有底色的 `ColoredBox`，`ListTile` 的水波與底色若畫在
///   外殼的 Material 上會被它蓋住（除錯版另有斷言）；
/// - 自己的 `ScrollNotificationObserver`：頁面不在自己的 `Scaffold` 裡，[PageAppBar] 找到的會是
///   外殼 `Scaffold` 的那一個，側欄、右側面板或別的目的地的清單一捲，這一頁的頁頂就跟著變色。
class PageSurface extends StatelessWidget {
  const PageSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ScrollNotificationObserver(child: child),
  );
}

/// 頁頂的返回鈕（下面還有頁時才有，同 [PageAppBar] 的判斷）；沒有要回的頁是 `null`。
/// 不用 [PageAppBar] 而自己畫頁頂的頁面（歌單詳情的頂圖）用它，返回鈕的 tooltip 與行為一致。
Widget? pageBackButton(BuildContext context, WidgetRef ref, {Color? color}) {
  if (!(ModalRoute.of(context)?.impliesAppBarDismissal ?? false)) return null;
  return IconButton(
    tooltip: ref.watch(translationsProvider).shell.backTooltip,
    icon: const BackButtonIcon(),
    color: color,
    onPressed: () => unawaited(Navigator.of(context).maybePop()),
  );
}

/// 每一頁的頁頂（ADR 0035 §決定 2）：舊版的置中標題 AppBar，主題的 `appBarTheme` 已經是置中、
/// 無陰影。巢狀導覽裡的內頁（下面還有頁）在標題前自動放返回鈕。
///
/// 標題給 [title]（一般文字）或 [titleWidget]（歷史頁搜尋時的輸入框）。多選時頁面用
/// `TrackSelectionBar(child: PageAppBar(...))` 把整條換成選取列。
class PageAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const PageAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.centerTitle,
    this.toolbarHeight = kToolbarHeight,
  }) : assert(
         (title == null) != (titleWidget == null),
         'give either title or titleWidget',
       );

  final String? title;
  final Widget? titleWidget;

  /// 取代自動的返回鈕（設定頁窄版從一組回到分組清單，那不是 route 的 pop）。
  final Widget? leading;
  final List<Widget> actions;

  /// 標題列下面的一格（搜尋頁的搜尋框、篩選列）。
  final PreferredSizeWidget? bottom;

  /// 預設跟主題（置中）；搜尋頁的搜尋框當標題，靠左（舊版也是）。
  final bool? centerTitle;

  /// 搜尋頁的搜尋框比一般標題高（舊版 `kToolbarHeight + 16`）。
  final double toolbarHeight;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 下面還有頁時才有返回鈕，同 AppBar 自己的判斷。
    final canGoBack = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return AppBar(
      automaticallyImplyLeading: false,
      leading:
          leading ??
          (canGoBack
              ? IconButton(
                  tooltip: ref.watch(translationsProvider).shell.backTooltip,
                  icon: const BackButtonIcon(),
                  onPressed: () => unawaited(Navigator.of(context).maybePop()),
                )
              : null),
      toolbarHeight: toolbarHeight,
      centerTitle: centerTitle,
      title:
          titleWidget ??
          Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: actions,
      bottom: bottom,
    );
  }
}
