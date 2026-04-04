import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../core/logger.dart';
import '../services/update/update_service.dart';

const _tag = 'UpdateProvider';

/// 更新状态
enum UpdateStatus {
  idle,
  checking,
  updateAvailable,
  downloading,
  readyToInstall, // 文件已下载，可以安装
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
  final String? downloadedFilePath; // 已下载文件路径

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.updateInfo,
    this.downloadProgress = 0,
    this.errorMessage,
    this.downloadedFilePath,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? updateInfo,
    double? downloadProgress,
    String? errorMessage,
    String? downloadedFilePath,
  }) {
    return UpdateState(
      status: status ?? this.status,
      updateInfo: updateInfo ?? this.updateInfo,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: errorMessage,
      downloadedFilePath: downloadedFilePath ?? this.downloadedFilePath,
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

    // 检查是否已有下载好的文件
    final existingPath = await _service.getExistingDownloadPath(info);
    if (existingPath != null) {
      AppLogger.info('Reusing existing download: $existingPath', _tag);
      state = state.copyWith(
        status: UpdateStatus.readyToInstall,
        downloadedFilePath: existingPath,
      );
      await _triggerInstall(existingPath);
      return;
    }

    // 需要下载
    state = state.copyWith(
      status: UpdateStatus.downloading,
      downloadProgress: 0,
    );

    try {
      final filePath = await _service.downloadAndInstall(
        info,
        onProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            // 仅在进度变化 ≥ 1% 或下载完成时更新，避免过多的 UI 重建
            if (progress >= 1.0 ||
                progress - state.downloadProgress >= 0.01) {
              state = state.copyWith(downloadProgress: progress);
            }
          }
        },
      );

      if (Platform.isAndroid) {
        state = state.copyWith(
          status: UpdateStatus.readyToInstall,
          downloadedFilePath: filePath,
        );
        await _triggerInstall(filePath);
      } else {
        // Windows: 已经退出应用，不会到这里
        state = state.copyWith(status: UpdateStatus.installing);
      }
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: '${t.updateProvider.downloadFailed}: $e',
      );
    }
  }

  /// 触发安装（Android）
  Future<void> _triggerInstall(String filePath) async {
    state = state.copyWith(status: UpdateStatus.installing);
    try {
      await _service.installApk(filePath);
      // OpenFilex.open() 返回了 — 用户取消安装或安装完成后回到 App
      // 恢复为 readyToInstall，用户可以再次点击安装
      if (mounted) {
        state = state.copyWith(status: UpdateStatus.readyToInstall);
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: '${t.updateProvider.installFailed}: $e',
        );
      }
    }
  }

  /// 重新触发安装（已下载的文件）
  Future<void> retryInstall() async {
    if (state.status == UpdateStatus.installing) return;
    final filePath = state.downloadedFilePath;
    if (filePath == null) return;
    await _triggerInstall(filePath);
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
