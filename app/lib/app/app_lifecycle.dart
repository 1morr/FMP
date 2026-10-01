import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App 的生命週期（前景、背景）。引擎還沒回報時（第一幀之前）當作
/// `resumed`。
final appLifecycleProvider =
    NotifierProvider<AppLifecycleNotifier, AppLifecycleState>(
      AppLifecycleNotifier.new,
    );

/// 以 [AppLifecycleListener] 接 `WidgetsBinding` 的生命週期通知。
final class AppLifecycleNotifier extends Notifier<AppLifecycleState> {
  @override
  AppLifecycleState build() {
    final listener = AppLifecycleListener(
      onStateChange: (lifecycle) => state = lifecycle,
    );
    ref.onDispose(listener.dispose);
    return SchedulerBinding.instance.lifecycleState ??
        AppLifecycleState.resumed;
  }
}
