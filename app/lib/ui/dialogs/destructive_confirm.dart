import 'package:material_ui/material_ui.dart';

/// 紅色確認鈕的確認框；確認回 `true`。
Future<bool> showDestructiveConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// 選單裡會刪除或移除東西的項目（ADR 0035，R7.9，舊版 L-34）：圖示與文字用 error 色，
/// 停用時照一般的停用色。破壞性的選單項目一律用它，不各自上色。
class DestructiveMenuItem extends StatelessWidget {
  const DestructiveMenuItem({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.child,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    WidgetStateProperty<Color?> tint() =>
        WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.disabled) ? null : error,
        );
    return MenuItemButton(
      leadingIcon: Icon(icon),
      onPressed: onPressed,
      style: ButtonStyle(foregroundColor: tint(), iconColor: tint()),
      child: child,
    );
  }
}
