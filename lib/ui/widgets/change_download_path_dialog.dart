import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/download_path_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/download/file_exists_cache.dart';
import '../../providers/download/download_providers.dart' show downloadedCategoriesProvider;

/// 更改下载路径对话框
///
/// 用于设置页面的下载路径变更流程。
/// 使用 ConsumerStatefulWidget 以便在异步操作期间管理状态。
class ChangeDownloadPathDialog extends ConsumerStatefulWidget {
  const ChangeDownloadPathDialog({super.key});

  /// 显示更改下载路径对话框
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ChangeDownloadPathDialog(),
    );
  }

  @override
  ConsumerState<ChangeDownloadPathDialog> createState() =>
      _ChangeDownloadPathDialogState();
}

class _ChangeDownloadPathDialogState
    extends ConsumerState<ChangeDownloadPathDialog> {
  /// 当前状态
  _DialogState _state = _DialogState.confirmation;

  /// 错误信息
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_getTitle()),
      content: _buildContent(),
      actions: _buildActions(),
    );
  }

  String _getTitle() {
    switch (_state) {
      case _DialogState.confirmation:
        return '更改下载路径';
      case _DialogState.selecting:
        return '选择文件夹';
      case _DialogState.processing:
        return '正在更新';
      case _DialogState.error:
        return '错误';
    }
  }

  Widget _buildContent() {
    switch (_state) {
      case _DialogState.confirmation:
        return const Text(
          '更改下载路径将清空所有已保存的下载路径信息。\n\n'
          '下载的文件不会被删除，但需要重新扫描才能显示。\n\n'
          '是否继续？',
        );
      case _DialogState.selecting:
      case _DialogState.processing:
        return const SizedBox(
          height: 50,
          child: Center(child: CircularProgressIndicator()),
        );
      case _DialogState.error:
        return Text(_error ?? '未知错误');
    }
  }

  List<Widget>? _buildActions() {
    switch (_state) {
      case _DialogState.confirmation:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _onContinue,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('继续'),
          ),
        ];
      case _DialogState.selecting:
      case _DialogState.processing:
        return null; // 隐藏按钮
      case _DialogState.error:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('关闭'),
          ),
        ];
    }
  }

  Future<void> _onContinue() async {
    final pathManager = ref.read(downloadPathManagerProvider);
    final trackRepo = ref.read(trackRepositoryProvider);

    // 显示选择状态
    setState(() => _state = _DialogState.selecting);

    try {
      // 打开文件选择器
      final newPath = await pathManager.selectDirectory(context);

      if (!mounted) return;

      if (newPath == null) {
        // 用户取消，返回确认状态
        setState(() => _state = _DialogState.confirmation);
        return;
      }

      // 显示处理状态
      setState(() => _state = _DialogState.processing);

      // 清空所有下载路径
      await trackRepo.clearAllDownloadPaths();

      // 保存新路径
      await pathManager.saveDownloadPath(newPath);

      // 刷新相关 Provider
      ref.invalidate(fileExistsCacheProvider);
      ref.invalidate(downloadedCategoriesProvider);
      ref.invalidate(downloadPathProvider);

      if (mounted) {
        // 保存 messenger 引用，避免跨异步间隙使用 context
        final messenger = ScaffoldMessenger.maybeOf(context);
        Navigator.pop(context, true);
        // 延迟显示 toast，确保对话框已关闭
        if (messenger != null) {
          Future.delayed(const Duration(milliseconds: 100), () {
            messenger.showSnackBar(
              const SnackBar(content: Text('下载路径已更改，请点击刷新按钮扫描本地文件')),
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _DialogState.error;
          _error = e.toString();
        });
      }
    }
  }
}

/// 对话框状态
enum _DialogState {
  confirmation, // 确认阶段
  selecting,    // 正在选择文件夹
  processing,   // 正在处理
  error,        // 错误
}
