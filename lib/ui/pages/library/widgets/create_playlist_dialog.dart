import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/image_loading_service.dart';
import '../../../../core/services/toast_service.dart';
import '../../../../data/models/playlist.dart';
import '../../../../providers/playlist_provider.dart';
import '../../../../services/library/playlist_service.dart';
import '../../../../i18n/strings.g.dart';
import 'cover_picker_dialog.dart';

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

  /// 自定義封面 URL（null 表示使用默認）
  String? _customCoverUrl;

  /// 是否清除了自定義封面（用於區分「未修改」和「清除」）
  bool _coverCleared = false;

  bool get isEditing => widget.playlist != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playlist?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.playlist?.description ?? '');
    _customCoverUrl = widget.playlist?.coverUrl;
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
      title: Text(isEditing ? t.library.createPlaylist.editTitle : t.library.createPlaylist.createTitle),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 封面選擇區域（僅編輯模式顯示）
              if (isEditing) ...[
                _buildCoverSection(context),
                const SizedBox(height: 16),
              ],

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: t.library.createPlaylist.nameLabel,
                  hintText: t.library.createPlaylist.nameHint,
                ),
                autofocus: !isEditing,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return t.library.createPlaylist.nameRequired;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: t.library.createPlaylist.descLabel,
                  hintText: t.library.createPlaylist.descHint,
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(t.general.cancel),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? t.library.createPlaylist.save : t.library.createPlaylist.create),
        ),
      ],
    );
  }

  /// 構建封面選擇區域
  Widget _buildCoverSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 獲取當前顯示的封面
    final displayCoverUrl = _customCoverUrl;
    final coverAsync = ref.watch(playlistCoverProvider(widget.playlist!.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.library.createPlaylist.cover,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _showCoverPicker(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                // 封面預覽
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(7),
                    ),
                    child: _buildCoverPreview(displayCoverUrl, coverAsync),
                  ),
                ),
                // 提示文字
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.edit,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              t.library.createPlaylist.clickToChangeCover,
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _customCoverUrl != null ? t.library.createPlaylist.usingCustomCover : t.library.createPlaylist.usingDefaultCover,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 構建封面預覽
  Widget _buildCoverPreview(
    String? customUrl,
    AsyncValue<PlaylistCoverData> coverAsync,
  ) {
    // 如果有自定義封面，優先顯示
    if (customUrl != null && customUrl.isNotEmpty) {
      return ImageLoadingService.loadImage(
        networkUrl: customUrl,
        placeholder: const ImagePlaceholder.track(),
        fit: BoxFit.cover,
      );
    }

    // 否則顯示默認封面（從 provider 獲取）
    return coverAsync.when(
      skipLoadingOnReload: true,
      data: (coverData) => coverData.hasCover
          ? ImageLoadingService.loadImage(
              localPath: coverData.localPath,
              networkUrl: coverData.networkUrl,
              placeholder: const ImagePlaceholder.track(),
              fit: BoxFit.cover,
            )
          : const ImagePlaceholder.track(),
      loading: () => const ImagePlaceholder.track(),
      error: (_, __) => const ImagePlaceholder.track(),
    );
  }

  /// 顯示封面選擇器
  Future<void> _showCoverPicker(BuildContext context) async {
    final result = await showDialog<CoverPickerResult>(
      context: context,
      builder: (context) => CoverPickerDialog(
        playlistId: widget.playlist!.id,
        currentCoverUrl: _customCoverUrl,
      ),
    );

    if (result != null) {
      setState(() {
        if (result.useDefault) {
          _customCoverUrl = null;
          _coverCleared = true;
        } else {
          _customCoverUrl = result.coverUrl;
          _coverCleared = false;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(playlistListProvider.notifier);
      final name = _nameController.text.trim();
      final description = _descriptionController.text.trim();

      if (isEditing) {
        // 確定封面 URL：
        // - 如果用戶清除了封面，傳空字符串（表示清除）
        // - 如果用戶選擇了新封面，傳新 URL
        // - 如果用戶沒有修改，傳 null（表示不更新）
        String? coverUrl;
        if (_coverCleared) {
          coverUrl = ''; // 空字符串表示清除
        } else if (_customCoverUrl != widget.playlist?.coverUrl) {
          coverUrl = _customCoverUrl; // 有變更時傳新值
        }
        // 否則 coverUrl 保持 null，表示不更新

        final result = await notifier.updatePlaylist(
          playlistId: widget.playlist!.id,
          name: name,
          description: description.isEmpty ? null : description,
          coverUrl: coverUrl,
        );

        if (mounted) {
          if (result != null) {
            Navigator.pop(context);
            ToastService.success(context, t.library.createPlaylist.playlistUpdated);

            // 如果有需要手动移动的下载文件，显示提示
            if (result.needsManualFileMigration) {
              _showFileMigrationWarning(
                result.oldDownloadFolder!,
                result.newDownloadFolder!,
              );
            }
          } else {
            final error = ref.read(playlistListProvider).error;
            ToastService.error(context, error ?? t.library.createPlaylist.operationFailed);
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
            ToastService.success(context, t.library.createPlaylist.playlistCreated);
          } else {
            final error = ref.read(playlistListProvider).error;
            ToastService.error(context, error ?? t.library.createPlaylist.operationFailed);
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
        title: Text(t.library.createPlaylist.downloadFileNotice),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.library.createPlaylist.playlistRenamedNotice),
            const SizedBox(height: 12),
            Text(t.library.createPlaylist.manualMoveHint),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                t.library.createPlaylist.oldNewPath(oldPath: oldFolder, newPath: newFolder),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
            ),
            const SizedBox(height: 12),
            Text(t.library.createPlaylist.syncAfterMove),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.library.createPlaylist.gotIt),
          ),
        ],
      ),
    );
  }
}
