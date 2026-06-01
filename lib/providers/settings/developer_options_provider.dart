import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 开发者选项状态
class DeveloperOptionsState {
  final bool isEnabled;
  final int tapCount;

  const DeveloperOptionsState({
    this.isEnabled = false,
    this.tapCount = 0,
  });

  DeveloperOptionsState copyWith({
    bool? isEnabled,
    int? tapCount,
  }) {
    return DeveloperOptionsState(
      isEnabled: isEnabled ?? this.isEnabled,
      tapCount: tapCount ?? this.tapCount,
    );
  }
}

/// 开发者选项 Notifier
class DeveloperOptionsNotifier extends StateNotifier<DeveloperOptionsState> {
  DeveloperOptionsNotifier() : super(const DeveloperOptionsState());

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
    state = const DeveloperOptionsState();
  }
}

/// 开发者选项 Provider
final developerOptionsProvider =
    StateNotifierProvider<DeveloperOptionsNotifier, DeveloperOptionsState>(
  (ref) => DeveloperOptionsNotifier(),
);
