import 'package:flutter/material.dart';

/// 右鍵菜單區域
///
/// 包裹任意 Widget，在右鍵點擊時於滑鼠位置顯示上下文菜單。
/// 菜單項目使用與 [PopupMenuButton] 相同的 [PopupMenuEntry] 類型。
class ContextMenuRegion extends StatelessWidget {
  final Widget child;
  final List<PopupMenuEntry<String>> Function(BuildContext context) menuBuilder;
  final void Function(String value) onSelected;

  const ContextMenuRegion({
    super.key,
    required this.child,
    required this.menuBuilder,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
      child: child,
    );
  }

  void _showContextMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: menuBuilder(context),
    );
    if (result != null) {
      onSelected(result);
    }
  }
}
