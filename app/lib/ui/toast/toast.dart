import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/storage_notice.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';

/// 一則提示（`.toast`，brief〈錯誤、log 與診斷〉）：一句話、可選的圖示，
/// 最多一個動作。錯誤與成功都用它。
class ToastMessage {
  const ToastMessage(this.text, {this.icon, this.action});

  final String text;
  final FmpIcons? icon;
  final ToastAction? action;
}

/// 提示上的動作，例如「重試」；按了提示就收起。
class ToastAction {
  const ToastAction(this.label, this.onTap);

  final String label;
  final void Function() onTap;
}

/// App 唯一的提示入口：同時只有一則，新的取代舊的。沒有動作的 4 秒後收起，
/// 有動作的留 8 秒讓人來得及按。啟動時資料庫出了狀況（[storageNoticeProvider]），
/// 第一則就是它。
final toastProvider = NotifierProvider<Toasts, ToastMessage?>(Toasts.new);

class Toasts extends Notifier<ToastMessage?> {
  Timer? _timer;

  static const plainDuration = Duration(seconds: 4);
  static const actionDuration = Duration(seconds: 8);

  @override
  ToastMessage? build() {
    ref.onDispose(() => _timer?.cancel());
    final notice = ref.read(storageNoticeProvider);
    if (notice == null) return null;
    _timer = Timer(plainDuration, dismiss);
    return ToastMessage(switch (notice) {
      StorageNotice.databaseUnavailable => t.toast.databaseUnavailable,
      StorageNotice.queueUnreadable => t.toast.queueUnreadable,
    }, icon: FmpIcons.warn);
  }

  void show(ToastMessage message) {
    _timer?.cancel();
    state = message;
    _timer = Timer(
      message.action == null ? plainDuration : actionDuration,
      dismiss,
    );
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }
}
