import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/sources/playlist_import/playlist_import_source.dart';
import '../../../../providers/playlist_import_provider.dart';
import '../../../../services/import/playlist_import_service.dart';
import '../import_preview_page.dart';

/// 导入外部歌单对话框
class ExternalPlaylistImportDialog extends ConsumerStatefulWidget {
  const ExternalPlaylistImportDialog({super.key});

  @override
  ConsumerState<ExternalPlaylistImportDialog> createState() =>
      _ExternalPlaylistImportDialogState();
}

class _ExternalPlaylistImportDialogState
    extends ConsumerState<ExternalPlaylistImportDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isImporting = false;
  String? _errorMessage;
  PlaylistSource? _detectedSource;
  SearchSourceConfig _searchSource = SearchSourceConfig.all;

  StreamSubscription<ImportProgress>? _progressSubscription;
  ImportProgress _progress = const ImportProgress();

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _progressSubscription?.cancel();
    super.dispose();
  }

  void _onUrlChanged(String url) {
    final notifier = ref.read(playlistImportProvider.notifier);
    final detected = notifier.detectSource(url.trim());
    if (detected != _detectedSource) {
      setState(() => _detectedSource = detected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('导入外部歌单'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '支持导入网易云音乐、QQ音乐歌单',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 16),

              // URL 输入
              TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'URL',
                  hintText: '粘贴歌单链接',
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: _detectedSource != null
                      ? Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Chip(
                            label: Text(
                              _detectedSource!.displayName,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        )
                      : null,
                ),
                enabled: !_isImporting,
                onChanged: _onUrlChanged,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入 URL';
                  }
                  final notifier = ref.read(playlistImportProvider.notifier);
                  if (notifier.detectSource(value.trim()) == null) {
                    return '不支持的链接格式';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 歌单名称
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '歌单名称（可选）',
                  hintText: '留空则使用原名称',
                  prefixIcon: Icon(Icons.edit),
                ),
                enabled: !_isImporting,
              ),
              const SizedBox(height: 16),

              // 搜索来源选择
              Text(
                '搜索来源',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: SearchSourceConfig.values.map((source) {
                  return ChoiceChip(
                    label: Text(source.displayName),
                    selected: _searchSource == source,
                    onSelected: _isImporting
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(() => _searchSource = source);
                            }
                          },
                  );
                }).toList(),
              ),

              // 进度显示
              if (_isImporting) ...[
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: _progress.total > 0 ? _progress.percentage : null,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 20,
                  child: Text(
                    _progress.currentItem ?? _getPhaseText(_progress.phase),
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

  String _getPhaseText(ImportPhase phase) {
    switch (phase) {
      case ImportPhase.idle:
        return '准备中...';
      case ImportPhase.fetching:
        return '正在获取歌单信息...';
      case ImportPhase.matching:
        return '正在搜索匹配...';
      case ImportPhase.completed:
        return '完成';
      case ImportPhase.error:
        return '出错';
    }
  }

  Future<void> _startImport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(playlistImportServiceProvider);
      final notifier = ref.read(playlistImportProvider.notifier);

      // 设置搜索来源
      notifier.setSearchSource(_searchSource);

      // 监听进度
      _progressSubscription = service.progressStream.listen((progress) {
        if (mounted) {
          setState(() => _progress = progress);
        }
      });

      final url = _urlController.text.trim();
      final customName = _nameController.text.trim();

      // 执行导入和匹配
      await notifier.importAndMatch(url);

      final state = ref.read(playlistImportProvider);

      if (state.phase == ImportPhase.error) {
        throw Exception(state.errorMessage ?? '导入失败');
      }

      if (mounted) {
        Navigator.pop(context);

        // 显示预览弹窗
        showImportPreviewDialog(
          context,
          customName: customName.isEmpty ? null : customName,
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
