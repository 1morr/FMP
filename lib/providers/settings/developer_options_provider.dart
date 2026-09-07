import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';

/// 开发者选项状态
class DeveloperOptionsState {
  final bool isEnabled;
  final int tapCount;

  /// 目前的最小日誌級別。
  ///
  /// 跟 [isEnabled] / [tapCount] 一樣是執行期狀態，不落 `Settings` —— 開發者
  /// 選項本來就不持久化，而 log 檔會從啟動的第一筆開始記，所以「調高級別再
  /// 重啟重現」這條路本來就不需要靠持久化的開關。
  final LogLevel logLevel;

  const DeveloperOptionsState({
    this.isEnabled = false,
    this.tapCount = 0,
    this.logLevel = LogLevel.debug,
  });

  DeveloperOptionsState copyWith({
    bool? isEnabled,
    int? tapCount,
    LogLevel? logLevel,
  }) {
    return DeveloperOptionsState(
      isEnabled: isEnabled ?? this.isEnabled,
      tapCount: tapCount ?? this.tapCount,
      logLevel: logLevel ?? this.logLevel,
    );
  }
}

/// 开发者选项 Notifier
class DeveloperOptionsNotifier extends Notifier<DeveloperOptionsState> {
  @override
  DeveloperOptionsState build() =>
      DeveloperOptionsState(logLevel: AppLogger.minLevel);

  /// 調整最小日誌級別。`AppLogger.setMinLevel` 在這之前沒有任何呼叫者。
  void setLogLevel(LogLevel level) {
    AppLogger.setMinLevel(level);
    state = state.copyWith(logLevel: level);
  }

  /// 需要的点击次数
  static const int requiredTaps = 7;

  /// 记录点击版本号
  void onVersionTap() {
    if (state.isEnabled) {
      // 已经启用，无需再点击
      return;
    }

    final newCount = state.tapCount + 1;
    if (newCount >= requiredTaps) {
      state = state.copyWith(isEnabled: true, tapCount: newCount);
    } else {
      state = state.copyWith(tapCount: newCount);
    }
  }

  /// 获取剩余点击次数
  int get remainingTaps => requiredTaps - state.tapCount;

  /// 重置（用于调试）
  void reset() {
    state = DeveloperOptionsState(logLevel: AppLogger.minLevel);
  }
}

/// 开发者选项 Provider
final developerOptionsProvider =
    NotifierProvider<DeveloperOptionsNotifier, DeveloperOptionsState>(
      DeveloperOptionsNotifier.new,
    );
