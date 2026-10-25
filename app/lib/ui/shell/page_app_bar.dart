import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/i18n/ui_locale.dart';

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
