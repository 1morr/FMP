import 'dart:async';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/ui_constants.dart';

/// Toast 消息类型
enum ToastType {
  info,
  success,
  warning,
  error,
}

/// Toast 消息（用于 Stream 传递）
class ToastMessage {
  final String message;
  final ToastType type;
  final DateTime timestamp;

  ToastMessage({
    required this.message,
    this.type = ToastType.info,
  }) : timestamp = DateTime.now();
}

/// 统一的消息提示服务
///
/// 提供两种使用方式：
/// 1. 静态方法（需要 BuildContext）- 用于 UI 直接调用
/// 2. Provider 实例（通过 Stream）- 用于后台任务
///
/// UI 直接调用示例：
/// ```dart
/// ToastService.show(context, '消息内容');
/// ToastService.success(context, '操作成功');
/// ToastService.error(context, '操作失败');
/// ```
///
/// 后台任务调用示例：
/// ```dart
/// final toastService = ref.read(toastServiceProvider);
/// toastService.showMessage('消息内容');
/// ```
class ToastService {
  static const Duration _defaultDuration = ToastDurations.short;

  final _messageController = StreamController<ToastMessage>.broadcast();

  /// 消息流（供 UI 层监听）
  Stream<ToastMessage> get messageStream => _messageController.stream;

  // ==================== 实例方法（通过 Provider 使用）====================

  /// 发送普通消息到流
  void showInfo(String message) {
    _messageController.add(ToastMessage(message: message, type: ToastType.info));
  }

  /// 发送成功消息到流
  void showSuccess(String message) {
    _messageController.add(ToastMessage(message: message, type: ToastType.success));
  }

  /// 发送警告消息到流
  void showWarning(String message) {
    _messageController.add(ToastMessage(message: message, type: ToastType.warning));
  }

  /// 发送错误消息到流
  void showError(String message) {
    _messageController.add(ToastMessage(message: message, type: ToastType.error));
  }

  void dispose() {
    _messageController.close();
  }

  // ==================== 静态方法（需要 BuildContext）====================

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
        persist: false,
        duration: _defaultDuration,
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
      SnackBar(content: content, duration: _defaultDuration),
    );
  }
}

/// Toast 服务 Provider
final toastServiceProvider = Provider<ToastService>((ref) {
  final service = ToastService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Toast 消息流 Provider
final toastStreamProvider = StreamProvider<ToastMessage>((ref) {
  return ref.watch(toastServiceProvider).messageStream;
});
