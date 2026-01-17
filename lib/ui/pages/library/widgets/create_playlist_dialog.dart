import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/toast_service.dart';
import '../../../../data/models/playlist.dart';
import '../../../../providers/playlist_provider.dart';

/// 创建/编辑歌单对话框
class CreatePlaylistDialog extends ConsumerStatefulWidget {
  final Playlist? playlist;

  const CreatePlaylistDialog({super.key, this.playlist});

  @override
  ConsumerState<CreatePlaylistDialog> createState() =>
      _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends ConsumerState<CreatePlaylistDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  bool get isEditing => widget.playlist != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playlist?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.playlist?.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEditing ? '编辑歌单' : '新建歌单'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '歌单名称',
                hintText: '请输入歌单名称',
              ),
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入歌单名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '描述（可选）',
                hintText: '添加歌单描述',
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? '保存' : '创建'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(playlistListProvider.notifier);
      final name = _nameController.text.trim();
      final description = _descriptionController.text.trim();

      if (isEditing) {
        final result = await notifier.updatePlaylist(
          playlistId: widget.playlist!.id,
          name: name,
          description: description.isEmpty ? null : description,
        );

        if (mounted) {
          if (result != null) {
            Navigator.pop(context);
            ToastService.success(context, '歌单已更新');

            // 如果有需要手动移动的下载文件，显示提示
            if (result.needsManualFileMigration) {
              _showFileMigrationWarning(
                result.oldDownloadFolder!,
                result.newDownloadFolder!,
              );
            }
          } else {
            final error = ref.read(playlistListProvider).error;
            ToastService.error(context, error ?? '操作失败');
          }
        }
      } else {
        final playlist = await notifier.createPlaylist(
          name: name,
          description: description.isEmpty ? null : description,
        );

        if (mounted) {
          if (playlist != null) {
            Navigator.pop(context);
            ToastService.success(context, '歌单已创建');
          } else {
            final error = ref.read(playlistListProvider).error;
            ToastService.error(context, error ?? '操作失败');
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 显示下载文件需要手动移动的提示
  void _showFileMigrationWarning(String oldFolder, String newFolder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('已下载文件提示'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('歌单已重命名，但已下载的文件未自动移动。'),
            const SizedBox(height: 12),
            const Text('如需继续使用这些文件，请手动将文件夹重命名：'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                '旧: $oldFolder\n新: $newFolder',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }
}
