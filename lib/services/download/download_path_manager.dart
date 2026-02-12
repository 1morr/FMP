import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/repositories/settings_repository.dart';
import '../storage_permission_service.dart';
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

  /// 检查是否已配置下载路径
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

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
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
    final settings = await _settingsRepo.get();
    settings.customDownloadDir = path;
    await _settingsRepo.save(settings);
  }

  /// 获取当前下载路径
  Future<String?> getCurrentDownloadPath() async {
    final settings = await _settingsRepo.get();
    return settings.customDownloadDir;
  }

  /// 清除下载路径配置
  Future<void> clearDownloadPath() async {
    final settings = await _settingsRepo.get();
    settings.customDownloadDir = null;
    await _settingsRepo.save(settings);
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
