import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../services/update/update_service.dart';

/// 更新状态
enum UpdateStatus {
  idle,
  checking,
  updateAvailable,
  downloading,
  installing,
  error,
  upToDate,
}

/// 更新状态
class UpdateState {
  final UpdateStatus status;
  final UpdateInfo? updateInfo;
  final double downloadProgress; // 0.0 - 1.0
  final String? errorMessage;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.updateInfo,
    this.downloadProgress = 0,
    this.errorMessage,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? updateInfo,
    double? downloadProgress,
    String? errorMessage,
  }) {
    return UpdateState(
      status: status ?? this.status,
      updateInfo: updateInfo ?? this.updateInfo,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: errorMessage,
    );
  }
}

/// 更新状态管理器
class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _service;

  UpdateNotifier() : _service = UpdateService(), super(const UpdateState());

  /// 检查更新
  Future<void> checkForUpdate() async {
    state = state.copyWith(status: UpdateStatus.checking, errorMessage: null);

    try {
      final info = await _service.checkForUpdate();
      if (info != null) {
        state = state.copyWith(
          status: UpdateStatus.updateAvailable,
          updateInfo: info,
        );
      } else {
        state = state.copyWith(status: UpdateStatus.upToDate);
      }
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: '${t.updateProvider.checkFailed}: $e',
      );
    }
  }

  /// 下载并安装更新
  Future<void> downloadAndInstall() async {
    final info = state.updateInfo;
    if (info == null) return;

    state = state.copyWith(
      status: UpdateStatus.downloading,
      downloadProgress: 0,
    );

    try {
      await _service.downloadAndInstall(
        info,
        onProgress: (received, total) {
          if (total > 0) {
            state = state.copyWith(
              downloadProgress: received / total,
            );
          }
        },
      );

      state = state.copyWith(status: UpdateStatus.installing);
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: '${t.updateProvider.downloadFailed}: $e',
      );
    }
  }

  /// 重置状态
  void reset() {
    state = const UpdateState();
  }
}

/// 更新 Provider
final updateProvider = StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  return UpdateNotifier();
});
