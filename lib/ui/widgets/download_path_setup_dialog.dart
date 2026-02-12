import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/i18n/strings.g.dart';
import '../../providers/download_path_provider.dart';

/// 下载路径配置引导对话框
///
/// 首次下载时弹出，引导用户选择下载保存位置。
/// 使用 ConsumerStatefulWidget 以便在异步操作期间管理状态。
class DownloadPathSetupDialog extends ConsumerStatefulWidget {
  const DownloadPathSetupDialog({super.key});

  /// 显示对话框并等待用户选择
  ///
  /// 返回 true 表示用户成功配置了路径
  /// 返回 false 或 null 表示用户取消了配置
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const DownloadPathSetupDialog(),
    );
  }

  @override
  ConsumerState<DownloadPathSetupDialog> createState() =>
      _DownloadPathSetupDialogState();
}

class _DownloadPathSetupDialogState
    extends ConsumerState<DownloadPathSetupDialog> {
  bool _isSelecting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.downloadPathSetup.title),
      content: _isSelecting
          ? const SizedBox(
              height: 50,
              child: Center(child: CircularProgressIndicator()),
            )
          : Text(t.downloadPathSetup.description),
      actions: _isSelecting
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.general.cancel),
              ),
              FilledButton(
                onPressed: _selectPath,
                child: Text(t.downloadPathSetup.selectFolder),
              ),
            ],
    );
  }

  Future<void> _selectPath() async {
    final pathManager = ref.read(downloadPathManagerProvider);

    setState(() => _isSelecting = true);

    try {
      final path = await pathManager.selectDirectory(context);

      if (!mounted) return;

      if (path != null) {
        await pathManager.saveDownloadPath(path);
        ref.invalidate(downloadPathProvider);
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        // 用户取消选择，恢复按钮状态允许重新选择
        setState(() => _isSelecting = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSelecting = false);
      }
    }
  }
}
