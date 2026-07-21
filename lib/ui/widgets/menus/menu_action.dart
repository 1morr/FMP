import 'package:flutter/material.dart';

/// 右鍵選單（PopupMenuEntry）與長按底部選單（ListTile）共用的動作描述，
/// 讓同一組動作只需定義一次即可雙呈現。
class MenuAction {
  const MenuAction({
    required this.id,
    required this.icon,
    required this.label,
    this.enabled = true,
    this.destructive = false,
    this.showProgress = false,
    this.trailing,
    this.checked = false,
  });

  /// 動作識別碼，作為選單 value 與 onSelected 回傳值。
  final String id;

  final IconData icon;
  final String label;

  /// 停用時 popup 項不可點，sheet 項 `onTap` 為 null。
  final bool enabled;

  /// 破壞性動作（如刪除），呈現時以 destructiveColor 上色。
  final bool destructive;

  /// 進行中動作（如重新整理），兩種呈現皆以 24x24 進度指示器
  /// 取代 leading icon。
  final bool showProgress;

  /// 自訂 trailing widget；優先於 [checked]。
  final Widget? trailing;

  /// 切換型選單項的勾選狀態，以 Icons.check 作為 trailing 呈現。
  final bool checked;
}

/// 進行中動作的共用 leading：popup 與 sheet 皆使用相同的
/// 24x24 進度指示器（而非舊實作的沙漏 icon）。
Widget _buildProgressLeading(BuildContext context) {
  return SizedBox(
    width: 24,
    height: 24,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      valueColor: AlwaysStoppedAnimation<Color>(
        Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

Widget? _buildTrailing(MenuAction action) {
  if (action.trailing != null) {
    return action.trailing;
  }
  if (action.checked) {
    return const Icon(Icons.check);
  }
  return null;
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
        enabled: action.enabled,
        child: ListTile(
          leading: action.showProgress
              ? const Builder(builder: _buildProgressLeading)
              : Icon(
                  action.icon,
                  color: action.destructive ? destructiveColor : null,
                ),
          title: Text(
            action.label,
            style:
                action.destructive ? TextStyle(color: destructiveColor) : null,
          ),
          trailing: _buildTrailing(action),
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
        leading: action.showProgress
            ? _buildProgressLeading(context)
            : Icon(
                action.icon,
                color: action.destructive ? destructiveColor : null,
              ),
        title: Text(
          action.label,
          style:
              action.destructive ? TextStyle(color: destructiveColor) : null,
        ),
        trailing: _buildTrailing(action),
        enabled: action.enabled,
        onTap: action.enabled
            ? () {
                Navigator.pop(context);
                onSelected(action.id);
              }
            : null,
      ),
  ];
}
