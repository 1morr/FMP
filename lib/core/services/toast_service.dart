import 'package:flutter/material.dart';

/// 统一的消息提示服务
///
/// 使用方法：
/// ```dart
/// ToastService.show(context, '消息内容');
/// ToastService.success(context, '操作成功');
/// ToastService.error(context, '操作失败');
/// ```
class ToastService {
  ToastService._();

  /// 显示普通消息
  static void show(BuildContext context, String message) {
    _showSnackBar(context, message);
  }

  /// 显示成功消息（带绿色图标）
  static void success(BuildContext context, String message) {
    _showSnackBar(
      context,
      message,
      icon: Icons.check_circle,
      iconColor: Colors.green,
    );
  }

  /// 显示错误消息（带红色图标）
  static void error(BuildContext context, String message) {
    _showSnackBar(
      context,
      message,
      icon: Icons.error,
      iconColor: Colors.red,
    );
  }

  /// 显示警告消息（带橙色图标）
  static void warning(BuildContext context, String message) {
    _showSnackBar(
      context,
      message,
      icon: Icons.warning,
      iconColor: Colors.orange,
    );
  }

  /// 显示带操作按钮的消息
  static void showWithAction(
    BuildContext context,
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: actionLabel,
          onPressed: onAction,
        ),
      ),
    );
  }

  static void _showSnackBar(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? iconColor,
  }) {
    final content = icon != null
        ? Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          )
        : Text(message);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: content),
    );
  }
}
