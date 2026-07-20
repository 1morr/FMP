import 'package:flutter/material.dart';

/// 右鍵選單（PopupMenuEntry）與長按底部選單（ListTile）共用的動作描述，
/// 讓同一組動作只需定義一次即可雙呈現。
class MenuAction {
  const MenuAction({
    required this.id,
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  /// 動作識別碼，作為選單 value 與 onSelected 回傳值。
  final String id;

  final IconData icon;
  final String label;

  /// 破壞性動作（如刪除），呈現時以 destructiveColor 上色。
  final bool destructive;
}

/// 右鍵選單項目：PopupMenuItem 內嵌 ListTile（contentPadding: EdgeInsets.zero），
/// destructive 項目以 [destructiveColor] 上色。視覺與
/// buildTrackActionPopupMenuEntries 一致。
List<PopupMenuEntry<String>> buildMenuActionPopupEntries(
  List<MenuAction> actions,
  Color destructiveColor,
) {
  return [
    for (final action in actions)
      PopupMenuItem(
        value: action.id,
        child: ListTile(
          leading: Icon(
            action.icon,
            color: action.destructive ? destructiveColor : null,
          ),
          title: Text(
            action.label,
            style:
                action.destructive ? TextStyle(color: destructiveColor) : null,
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
  ];
}

/// 長按底部選單項目：ListTile，點擊後 pop 底部選單並回呼 [onSelected]。
/// [context] 需為底部選單的 context（用於 pop）。
List<Widget> buildMenuActionListTiles(
  BuildContext context,
  List<MenuAction> actions,
  void Function(String id) onSelected,
  Color destructiveColor,
) {
  return [
    for (final action in actions)
      ListTile(
        leading: Icon(
          action.icon,
          color: action.destructive ? destructiveColor : null,
        ),
        title: Text(
          action.label,
          style:
              action.destructive ? TextStyle(color: destructiveColor) : null,
        ),
        onTap: () {
          Navigator.pop(context);
          onSelected(action.id);
        },
      ),
  ];
}
