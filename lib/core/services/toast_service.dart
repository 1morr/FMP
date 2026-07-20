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
  /// ColorScheme 沒有 success / warning 語意色，統一在此集中定義，
  /// 供 Toast 與其他需要語意色的 UI（例如匯入結果對話框）引用。
  static const Color successColor = Colors.green;
  static const Color warningColor = Colors.orange;

  final _messageController = StreamController<ToastMessage>.broadcast();

  /// 消息流（供 UI 层监听）
  Stream<ToastMessage> get messageStream => _messageController.stream;

  // ==================== 实例方法（通过 Provider 使用）====================

  /// 发送普通消息到流
  void showInfo(String message) {
    _messageController
        .add(ToastMessage(message: message, type: ToastType.info));
  }

  /// 发送成功消息到流
  void showSuccess(String message) {
    _messageController
        .add(ToastMessage(message: message, type: ToastType.success));
  }

  /// 发送警告消息到流
  void showWarning(String message) {
    _messageController
        .add(ToastMessage(message: message, type: ToastType.warning));
  }

  /// 发送错误消息到流
  void showError(String message) {
    _messageController
        .add(ToastMessage(message: message, type: ToastType.error));
  }

  void dispose() {
    _messageController.close();
  }

  // ==================== 静态方法（需要 BuildContext）====================

  /// 全 app 唯一的 SnackBar 建构入口。
  ///
  /// 统一外观：floating 行为、整條語意彩底、白字白圖示。
  /// [duration] 未提供時，error / warning 使用 [ToastDurations.long]，
  /// 其他類型使用 [ToastDurations.short]。
  static SnackBar buildSnackBar(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    Duration? duration,
    SnackBarAction? action,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final (backgroundColor, icon) = switch (type) {
      ToastType.info => (colorScheme.primary, Icons.info),
      ToastType.success => (successColor, Icons.check_circle),
      ToastType.warning => (warningColor, Icons.warning),
      ToastType.error => (colorScheme.error, Icons.error),
    };

    return SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: backgroundColor,
      content: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      duration: duration ??
          (type == ToastType.error || type == ToastType.warning
              ? ToastDurations.long
              : ToastDurations.short),
      action: action,
    );
  }

  /// 显示普通消息
  static void show(BuildContext context, String message,
      {Duration? duration}) {
    showSnackBarNow(
      context,
      buildSnackBar(context, message: message, duration: duration),
    );
  }

  /// 显示成功消息
  static void success(BuildContext context, String message,
      {Duration? duration}) {
    showSnackBarNow(
      context,
      buildSnackBar(
        context,
        message: message,
        type: ToastType.success,
        duration: duration,
      ),
    );
  }

  /// 显示错误消息
  static void error(BuildContext context, String message,
      {Duration? duration}) {
    showSnackBarNow(
      context,
      buildSnackBar(
        context,
        message: message,
        type: ToastType.error,
        duration: duration,
      ),
    );
  }

  /// 显示警告消息
  static void warning(BuildContext context, String message,
      {Duration? duration}) {
    showSnackBarNow(
      context,
      buildSnackBar(
        context,
        message: message,
        type: ToastType.warning,
        duration: duration,
      ),
    );
  }

  /// 显示带操作按钮的消息
  static void showWithAction(
    BuildContext context,
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
    Duration? duration,
  }) {
    showSnackBarNow(
      context,
      buildSnackBar(
        context,
        message: message,
        duration: duration,
        action: SnackBarAction(
          label: actionLabel,
          onPressed: onAction,
        ),
      ),
    );
  }

  /// 立即显示 [snackBar]，替换当前可见或排队中的 Toast。
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
      showSnackBarNow(
    BuildContext context,
    SnackBar snackBar,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    return messenger.showSnackBar(snackBar);
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
