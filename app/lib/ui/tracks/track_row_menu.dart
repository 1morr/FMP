import 'package:material_ui/material_ui.dart';

/// 一列曲目的選單（搜尋結果、播放歷史、佇列共用）：右鍵、長按與尾端「⋯」是同一份
/// [menuChildren]。
///
/// - 右鍵在點的位置開；長按與「⋯」在「⋯」下方開。右鍵的辨識器排除在語意樹外
///   （`excludeFromSemantics`）：它會多一個沒有名稱的點擊動作，同一份選單由「⋯」
///   提供給輔助技術。
/// - 「⋯」的 `FocusNode` 同時是 `MenuAnchor` 的 `childFocusNode`：選單打開時焦點移到
///   這裡（選單的快捷鍵之內），以滑鼠、右鍵或長按打開的也能以 Esc 關掉、以方向鍵
///   進入選單。
///
/// 列的內容由 [builder] 畫：把給的 `moreButton` 放在尾端、`openMenu` 接到長按。
class TrackRowMenu extends StatefulWidget {
  const TrackRowMenu({
    super.key,
    required this.menuChildren,
    required this.moreTooltip,
    required this.builder,
  });

  /// 選單項目，由呼叫端決定。
  final List<Widget> menuChildren;

  /// 「⋯」的 tooltip（也是它的語意名稱）。
  final String moreTooltip;

  final Widget Function(
    BuildContext context,
    Widget moreButton,
    VoidCallback openMenu,
  )
  builder;

  @override
  State<TrackRowMenu> createState() => _TrackRowMenuState();
}

class _TrackRowMenuState extends State<TrackRowMenu> {
  final _menu = MenuController();

  /// 「⋯」的位置，選單從它下方開。
  final _moreKey = GlobalKey();
  final _moreFocus = FocusNode(debugLabel: 'more');

  @override
  void dispose() {
    _moreFocus.dispose();
    super.dispose();
  }

  /// 在列內的 [position]（沒給就是「⋯」下方）開選單。
  void _openMenu([Offset? position]) {
    if (position == null) {
      final tile = context.findRenderObject() as RenderBox?;
      final more = _moreKey.currentContext?.findRenderObject() as RenderBox?;
      if (tile != null && more != null) {
        position = more.localToGlobal(
          Offset(0, more.size.height),
          ancestor: tile,
        );
      }
    }
    _menu.open(position: position);
  }

  @override
  Widget build(BuildContext context) {
    final more = IconButton(
      key: _moreKey,
      focusNode: _moreFocus,
      tooltip: widget.moreTooltip,
      icon: const Icon(Icons.more_vert),
      onPressed: _openMenu,
    );
    return MenuAnchor(
      controller: _menu,
      childFocusNode: _moreFocus,
      menuChildren: widget.menuChildren,
      child: GestureDetector(
        onSecondaryTapUp: (details) => _openMenu(details.localPosition),
        excludeFromSemantics: true,
        child: widget.builder(context, more, _openMenu),
      ),
    );
  }
}
