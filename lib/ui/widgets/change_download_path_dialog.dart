import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/download_path_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/download/file_exists_cache.dart';
import '../../providers/download/download_providers.dart' show downloadedCategoriesProvider;
import '../../core/services/toast_service.dart';

/// 更改下载路径对话框
///
/// 用于设置页面的下载路径变更流程。
/// 包含两次确认（防止误操作）和加载状态显示。
class ChangeDownloadPathDialog {
  /// 显示更改下载路径对话框
  ///
  /// 流程：
  /// 1. 显示确认对话框，警告用户更改会清空数据库路径
  /// 2. 用户确认后，显示加载状态
  /// 3. 选择新路径
  /// 4. 清空数据库路径并保存新路径
  /// 5. 刷新相关 Provider
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    // 第一次确认
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更改下载路径'),
        content: const Text(
          '更改下载路径将清空所有已保存的下载路径信息。\n\n'
          '下载的文件不会被删除，但需要重新扫描才能显示。\n\n'
          '是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('继续'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // 执行路径变更
    await _executePathChange(context, ref);
  }

  static Future<void> _executePathChange(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final pathManager = ref.read(downloadPathManagerProvider);
    final trackRepo = ref.read(trackRepositoryProvider);

    // 显示加载状态
    BuildContext? loadingContext;
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          loadingContext = ctx;
          return const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在选择文件夹...'),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    try {
      // 选择新路径
      final newPath = await pathManager.selectDirectory(context);

      // 关闭加载对话框
      if (loadingContext != null && loadingContext!.mounted) {
        Navigator.pop(loadingContext!);
      }

      if (newPath == null) return;

      // 显示处理中状态
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            loadingContext = ctx;
            return const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在更新设置...'),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }

      // 清空所有下载路径
      await trackRepo.clearAllDownloadPaths();

      // 保存新路径
      await pathManager.saveDownloadPath(newPath);

      // 关闭加载对话框
      if (loadingContext != null && loadingContext!.mounted) {
        Navigator.pop(loadingContext!);
      }

      // 刷新相关 Provider
      ref.invalidate(fileExistsCacheProvider);
      ref.invalidate(downloadedCategoriesProvider);
      ref.invalidate(downloadPathProvider);

      if (context.mounted) {
        ToastService.show(context, '下载路径已更改，请点击刷新按钮扫描本地文件');
      }
    } catch (e) {
      // 关闭加载对话框
      if (loadingContext != null && loadingContext!.mounted) {
        Navigator.pop(loadingContext!);
      }
      if (context.mounted) {
        ToastService.show(context, '更改路径失败: $e');
      }
    }
  }
}
