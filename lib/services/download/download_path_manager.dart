import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/services/download/download_path_utils.dart';
import 'package:fmp/services/platform/storage_permission_service.dart';
import 'package:fmp/i18n/strings.g.dart';

/// 下载路径管理器
///
/// 负责：
/// - 用户选择下载目录
/// - 验证写入权限
/// - 持久化路径配置
class DownloadPathManager {
  final SettingsRepository _settingsRepo;

  DownloadPathManager(this._settingsRepo);

  /// 使用者是否親自選過下載目錄。
  ///
  /// 只用來決定下載前要不要先跳目錄選擇對話框（Android 要在那裡取得檔案
  /// 權限）。讀寫下載檔案一律用 [getEffectiveBaseDir]：未選過時它回平台預設，
  /// 舊版下載到預設目錄的檔案仍在那裡。
  Future<bool> hasConfiguredPath() async {
    final settings = await _settingsRepo.get();
    return settings.customDownloadDir != null &&
        settings.customDownloadDir!.isNotEmpty;
  }

  /// 选择下载目录
  ///
  /// 返回选择的路径，如果用户取消或权限不足返回 null
  Future<String?> selectDirectory(BuildContext context) async {
    // Android 11+ 需要先请求存储权限
    if (Platform.isAndroid) {
      final hasPermission =
          await StoragePermissionService.requestStoragePermission(context);
      if (!hasPermission) {
        return null;
      }
    }

    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory == null) return null;

    // 验证写入权限（所有平台）
    if (!await _verifyWritePermission(selectedDirectory)) {
      if (context.mounted) {
        _showPermissionError(context);
      }
      return null;
    }

    return selectedDirectory;
  }

  /// 验证目录写入权限（仅用于桌面平台）
  Future<bool> _verifyWritePermission(String path) async {
    try {
      final testFile = File('$path/.fmp_test');
      await testFile.create();
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 保存下载路径
  Future<void> saveDownloadPath(String path) async {
    await _settingsRepo.update((settings) {
      settings.customDownloadDir = path;
    });
  }

  /// 使用者選的下載目錄；沒選過回 null（設定頁據此顯示「未設定」）。
  Future<String?> getCurrentDownloadPath() async {
    final settings = await _settingsRepo.get();
    return settings.customDownloadDir;
  }

  /// 取得目前有效的下載根目錄（使用者自選目錄，否則平台預設）。
  ///
  /// 寫檔、掃描、同步、刪除都以它為準。刪除路徑的 containment guard 也拿它
  /// 當基準：認不出基準就無法確定要刪的是 FMP 自己的下載目錄。
  Future<String> getEffectiveBaseDir() =>
      DownloadPathUtils.getDefaultBaseDir(_settingsRepo);

  /// 清除下载路径配置
  Future<void> clearDownloadPath() async {
    await _settingsRepo.update((settings) {
      settings.customDownloadDir = null;
    });
  }

  /// 显示权限错误对话框
  void _showPermissionError(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.folder_off_outlined,
          color: colorScheme.error,
          size: 32,
        ),
        title: Text(t.permission.insufficientPermission),
        content: Text(t.permission.cannotWriteDirectory),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.confirm),
          ),
        ],
      ),
    );
  }
}
