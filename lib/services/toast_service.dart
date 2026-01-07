import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Toast 消息类型
enum ToastType {
  info,
  success,
  warning,
  error,
}

/// Toast 消息
class ToastMessage {
  final String message;
  final ToastType type;
  final DateTime timestamp;

  ToastMessage({
    required this.message,
    this.type = ToastType.info,
  }) : timestamp = DateTime.now();
}

/// Toast 服务 - 全局消息通知
class ToastService {
  final _messageController = StreamController<ToastMessage>.broadcast();

  /// 消息流
  Stream<ToastMessage> get messageStream => _messageController.stream;

  /// 显示普通消息
  void show(String message) {
    _messageController.add(ToastMessage(message: message, type: ToastType.info));
  }

  /// 显示成功消息
  void showSuccess(String message) {
    _messageController.add(ToastMessage(message: message, type: ToastType.success));
  }

  /// 显示警告消息
  void showWarning(String message) {
    _messageController.add(ToastMessage(message: message, type: ToastType.warning));
  }

  /// 显示错误消息
  void showError(String message) {
    _messageController.add(ToastMessage(message: message, type: ToastType.error));
  }

  void dispose() {
    _messageController.close();
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
