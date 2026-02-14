import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/i18n/strings.g.dart';
import '../../core/constants/ui_constants.dart';
import '../../providers/download_path_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/download/file_exists_cache.dart';
import '../../providers/download/download_providers.dart' show downloadedCategoriesProvider, downloadServiceProvider;
import '../../providers/playlist_provider.dart' show allPlaylistsProvider, playlistDetailProvider;

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
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: _buildIcon(colorScheme),
      title: Text(_getTitle()),
      content: _buildContent(colorScheme),
      actions: _buildActions(colorScheme),
    );
  }

  Widget? _buildIcon(ColorScheme colorScheme) {
    return switch (_state) {
      _DialogState.confirmation => Icon(
          Icons.folder_copy_outlined,
          color: colorScheme.primary,
          size: 32,
        ),
      _DialogState.selecting || _DialogState.processing => null,
      _DialogState.error => Icon(
          Icons.error_outline,
          color: colorScheme.error,
          size: 32,
        ),
    };
  }

  String _getTitle() {
    switch (_state) {
      case _DialogState.confirmation:
        return t.changeDownloadPathDialog.changeDownloadPath;
      case _DialogState.selecting:
        return t.changeDownloadPathDialog.selectFolder;
      case _DialogState.processing:
        return t.changeDownloadPathDialog.updating;
      case _DialogState.error:
        return t.changeDownloadPathDialog.operationFailed;
    }
  }

  Widget _buildContent(ColorScheme colorScheme) {
    switch (_state) {
      case _DialogState.confirmation:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.changeDownloadPathDialog.changeWarning),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.borderRadiusLg,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.changeDownloadPathDialog.filesNotDeleted,
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
        );
      case _DialogState.selecting:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 16),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(t.changeDownloadPathDialog.selectNewFolder),
            SizedBox(height: 8),
          ],
        );
      case _DialogState.processing:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 16),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(t.changeDownloadPathDialog.updatingSettings),
            SizedBox(height: 8),
          ],
        );
      case _DialogState.error:
        return Text(_error ?? t.changeDownloadPathDialog.unknownError);
    }
  }

  List<Widget> _buildActions(ColorScheme colorScheme) {
    switch (_state) {
      case _DialogState.confirmation:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.general.cancel),
          ),
          FilledButton(
            onPressed: _onContinue,
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
            ),
            child: Text(t.changeDownloadPathDialog.continueButton),
          ),
        ];
      case _DialogState.selecting:
      case _DialogState.processing:
        return [
          TextButton(
            onPressed: null,
            child: Text(t.general.cancel),
          ),
          FilledButton(
            onPressed: null,
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onPrimary,
              ),
            ),
          ),
        ];
      case _DialogState.error:
        return [
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.changeDownloadPathDialog.closeButton),
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

      // A1: 清空所有下载路径
      debugPrint('[ChangeDownloadPath] Clearing all download paths...');
      await trackRepo.clearAllDownloadPaths();
      debugPrint('[ChangeDownloadPath] Download paths cleared');

      // A1: 清除已完成和失败的下载任务
      debugPrint('[ChangeDownloadPath] Getting download service...');
      final downloadService = ref.read(downloadServiceProvider);
      debugPrint('[ChangeDownloadPath] Clearing completed/error tasks...');
      await downloadService.clearCompletedAndErrorTasks();
      debugPrint('[ChangeDownloadPath] Completed/error tasks cleared');

      // 保存新路径
      await pathManager.saveDownloadPath(newPath);

      // 刷新相关 Provider
      ref.invalidate(fileExistsCacheProvider);
      ref.invalidate(downloadedCategoriesProvider);
      ref.invalidate(downloadPathProvider);

      // 刷新所有歌单详情（因为下载路径被清空了）
      final playlists = await ref.read(allPlaylistsProvider.future);
      for (final playlist in playlists) {
        ref.invalidate(playlistDetailProvider(playlist.id));
      }

      if (mounted) {
        // 保存 messenger 引用，避免跨异步间隙使用 context
        final messenger = ScaffoldMessenger.maybeOf(context);
        Navigator.pop(context, true);
        // 延迟显示 toast，确保对话框已关闭
        if (messenger != null) {
          Future.delayed(AnimationDurations.fastest, () {
            messenger.showSnackBar(
              SnackBar(content: Text(t.changeDownloadPathDialog.pathChanged)),
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
