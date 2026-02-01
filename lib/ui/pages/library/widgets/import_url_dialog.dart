import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/toast_service.dart';
import '../../../../data/sources/source_provider.dart';
import '../../../../providers/database_provider.dart';
import '../../../../providers/playlist_provider.dart';
import '../../../../providers/repository_providers.dart';
import '../../../../services/import/import_service.dart';

/// 从 URL 导入歌单对话框
class ImportUrlDialog extends ConsumerStatefulWidget {
  const ImportUrlDialog({super.key});

  @override
  ConsumerState<ImportUrlDialog> createState() => _ImportUrlDialogState();
}

class _ImportUrlDialogState extends ConsumerState<ImportUrlDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  ImportProgress _progress = const ImportProgress();
  StreamSubscription<ImportProgress>? _progressSubscription;
  bool _isImporting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _progressSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('从 URL 导入'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '支持导入 B站收藏夹、YouTube 播放列表和 Mix',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: '粘贴收藏夹链接',
                  prefixIcon: Icon(Icons.link),
                ),
                enabled: !_isImporting,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入 URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '歌单名称（可选）',
                  hintText: '留空则使用原名称',
                  prefixIcon: Icon(Icons.edit),
                ),
                enabled: !_isImporting,
              ),

              // 进度显示
              if (_isImporting) ...[
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: _progress.total > 0 ? _progress.percentage : null,
                ),
                const SizedBox(height: 8),
                // 固定高度避免因标题长度不同导致弹窗抖动
                SizedBox(
                  height: 20,
                  child: Text(
                    _progress.currentItem ?? '正在处理...',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_progress.total > 0)
                  Text(
                    '${_progress.current} / ${_progress.total}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                  ),
              ],

              // 错误显示
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: colorScheme.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isImporting ? null : _startImport,
          child: _isImporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('导入'),
        ),
      ],
    );
  }

  Future<void> _startImport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final sourceManager = ref.read(sourceManagerProvider);
      final playlistRepo = ref.read(playlistRepositoryProvider);
      final trackRepo = ref.read(trackRepositoryProvider);
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final isar = await ref.read(databaseProvider.future);
      
      final importService = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepo,
        trackRepository: trackRepo,
        settingsRepository: settingsRepo,
        isar: isar,
      );

      // 监听进度
      _progressSubscription = importService.progressStream.listen((progress) {
        if (mounted) {
          setState(() => _progress = progress);
        }
      });

      final url = _urlController.text.trim();
      final customName = _nameController.text.trim();

      final result = await importService.importFromUrl(
        url,
        customName: customName.isEmpty ? null : customName,
      );

      // 刷新歌单列表
      ref.read(playlistListProvider.notifier).loadPlaylists();
      // 同步刷新 allPlaylistsProvider，确保首页"我的歌单"显示最新列表
      ref.invalidate(allPlaylistsProvider);

      if (mounted) {
        Navigator.pop(context);
        ToastService.success(
          context,
          '导入成功！添加了 ${result.addedCount} 首歌曲'
          '${result.skippedCount > 0 ? '，跳过 ${result.skippedCount} 首' : ''}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _errorMessage = e.toString();
        });
      }
    } finally {
      _progressSubscription?.cancel();
    }
  }
}
