import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 存储权限服务
///
/// 处理 Android 11+ 的 MANAGE_EXTERNAL_STORAGE 权限
class StoragePermissionService {
  /// 检查是否有外部存储管理权限
  ///
  /// - Android 11+: 检查 MANAGE_EXTERNAL_STORAGE
  /// - Android 10 及以下: 检查 WRITE_EXTERNAL_STORAGE
  /// - 非 Android 平台: 返回 true
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Android 11+ (API 30+)
    if (await _isAndroid11OrHigher()) {
      return await Permission.manageExternalStorage.isGranted;
    }

    // Android 10 及以下
    return await Permission.storage.isGranted;
  }

  /// 请求存储权限
  ///
  /// 返回是否获得了权限
  static Future<bool> requestStoragePermission(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    // Android 11+ (API 30+)
    if (await _isAndroid11OrHigher()) {
      final status = await Permission.manageExternalStorage.status;

      if (status.isGranted) return true;

      if (status.isDenied) {
        // 显示解释对话框
        if (context.mounted) {
          final shouldRequest = await _showPermissionExplanationDialog(context);
          if (!shouldRequest) return false;
        }

        // 请求权限（会打开系统设置页面）
        final result = await Permission.manageExternalStorage.request();
        return result.isGranted;
      }

      if (status.isPermanentlyDenied) {
        // 引导用户去设置页面
        if (context.mounted) {
          await _showGoToSettingsDialog(context);
        }
        return false;
      }

      return false;
    }

    // Android 10 及以下
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  /// 检查是否为 Android 11 或更高版本
  static Future<bool> _isAndroid11OrHigher() async {
    // permission_handler 内部会处理版本检查
    // 这里简单通过检查 manageExternalStorage 权限状态来判断
    try {
      await Permission.manageExternalStorage.status;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 显示权限解释对话框
  static Future<bool> _showPermissionExplanationDialog(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: Icon(
              Icons.folder_outlined,
              color: colorScheme.primary,
              size: 32,
            ),
            title: const Text('需要存储权限'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('为了将音乐下载到您选择的文件夹，应用需要访问设备存储的权限。'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '点击「继续」后，请在系统设置中允许 FMP 访问所有文件。',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// 显示引导用户去设置的对话框
  static Future<void> _showGoToSettingsDialog(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    
    final goToSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.block_outlined,
          color: colorScheme.error,
          size: 32,
        ),
        title: const Text('权限被拒绝'),
        content: const Text(
          '存储权限已被拒绝。如果您想使用自定义下载路径，请在设置中手动授予权限。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('打开设置'),
          ),
        ],
      ),
    );

    if (goToSettings == true) {
      await openAppSettings();
    }
  }
}
