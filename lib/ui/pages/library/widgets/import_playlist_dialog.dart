import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../../core/constants/ui_constants.dart';
import '../../../../core/services/toast_service.dart';
import '../../../../data/models/track.dart';
import '../../../../data/sources/source_provider.dart';
import '../../../../providers/database_provider.dart';
import '../../../../providers/playlist_import_provider.dart';
import '../../../../providers/playlist_provider.dart';
import '../../../../providers/repository_providers.dart';
import '../../../../services/import/import_service.dart' as url_import;
import '../../../../services/import/playlist_import_service.dart';
import '../../../../data/sources/playlist_import/playlist_import_source.dart';
import '../../../../i18n/strings.g.dart';
import '../import_preview_page.dart';

/// URL 导入类型
enum _UrlType {
  /// 内部来源（B站/YouTube），直接导入
  internal,

  /// 外部来源（网易云/QQ音乐/Spotify），需要搜索匹配
  external,
}

/// 来源平台（统一标识，用于图标匹配等）
enum _SourcePlatform { bilibili, youtube, netease, qqMusic, spotify }

/// 检测到的 URL 信息
class _DetectedUrl {
  final _UrlType type;
  final _SourcePlatform platform;

  const _DetectedUrl({required this.type, required this.platform});
}

/// 统一的歌单导入对话框
///
/// 自动识别 URL 类型：
/// - 内部来源（B站/YouTube）：直接导入，不显示搜索来源选项
/// - 外部来源（网易云/QQ音乐/Spotify）：搜索匹配，显示搜索来源选项
class ImportPlaylistDialog extends ConsumerStatefulWidget {
  const ImportPlaylistDialog({super.key});

  @override
  ConsumerState<ImportPlaylistDialog> createState() =>
      _ImportPlaylistDialogState();
}

class _ImportPlaylistDialogState extends ConsumerState<ImportPlaylistDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isImporting = false;
  String? _errorMessage;

  /// 检测到的 URL 信息
  _DetectedUrl? _detected;

  /// 外部歌单搜索来源
  SearchSourceConfig _searchSource = SearchSourceConfig.all;

  // 内部导入
  url_import.ImportService? _internalImportService;
  url_import.ImportProgress? _internalProgress;
  StreamSubscription<url_import.ImportProgress>? _internalProgressSub;

  // 外部导入进度
  ImportProgress? _externalProgress;
  StreamSubscription<ImportProgress>? _externalProgressSub;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _internalProgressSub?.cancel();
    _externalProgressSub?.cancel();
    super.dispose();
  }

  /// 根据来源平台返回对应图标
  IconData _getSourceIcon(_SourcePlatform platform) {
    switch (platform) {
      case _SourcePlatform.bilibili:
        return SimpleIcons.bilibili;
      case _SourcePlatform.youtube:
        return SimpleIcons.youtube;
      case _SourcePlatform.netease:
        return SimpleIcons.neteasecloudmusic;
      case _SourcePlatform.qqMusic:
        return SimpleIcons.qq;
      case _SourcePlatform.spotify:
        return SimpleIcons.spotify;
    }
  }

  /// 检测 URL 类型
  void _onUrlChanged(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      if (_detected != null) setState(() => _detected = null);
      return;
    }

    // 1. 先检查外部来源（网易云/QQ音乐/Spotify）
    //    外部来源使用域名匹配，更精确；内部来源的 isPlaylistUrl 可能过于宽泛
    //    （如 YouTube 的 url.contains('/playlist') 会误匹配 QQ音乐/网易云链接）
    final notifier = ref.read(playlistImportProvider.notifier);
    final externalSource = notifier.detectSource(trimmed);
    if (externalSource != null) {
      final platform = switch (externalSource) {
        PlaylistSource.netease => _SourcePlatform.netease,
        PlaylistSource.qqMusic => _SourcePlatform.qqMusic,
        PlaylistSource.spotify => _SourcePlatform.spotify,
      };
      final newDetected = _DetectedUrl(type: _UrlType.external, platform: platform);
      if (_detected?.type != newDetected.type ||
          _detected?.platform != newDetected.platform) {
        setState(() => _detected = newDetected);
      }
      return;
    }

    // 2. 再检查内部来源（B站/YouTube）
    final sourceManager = ref.read(sourceManagerProvider);
    final internalSource = sourceManager.getSourceForUrl(trimmed);
    if (internalSource != null) {
      final platform = switch (internalSource.sourceType) {
        SourceType.bilibili => _SourcePlatform.bilibili,
        SourceType.youtube => _SourcePlatform.youtube,
      };
      final newDetected = _DetectedUrl(type: _UrlType.internal, platform: platform);
      if (_detected?.type != newDetected.type ||
          _detected?.platform != newDetected.platform) {
        setState(() => _detected = newDetected);
      }
      return;
    }

    // 3. 无法识别
    if (_detected != null) setState(() => _detected = null);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isExternal = _detected?.type == _UrlType.external;

    // 进度信息
    final progressText = _getProgressText();
    final progressValue = _getProgressValue();
    final progressCount = _getProgressCount();

    return AlertDialog(
      title: Text(t.library.importPlaylist.title),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.library.importPlaylist.supportedPlatforms,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 16),

              // URL 输入
              TextFormField(
                controller: _urlController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'URL',
                  hintText: t.library.importPlaylist.urlHint,
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: _detected != null
                      ? Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Icon(
                            _getSourceIcon(_detected!.platform),
                            size: 18,
                            color: colorScheme.outline,
                          ),
                        )
                      : null,
                ),
                enabled: !_isImporting,
                onChanged: _onUrlChanged,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return t.library.importPlaylist.urlRequired;
                  }
                  final trimmed = value.trim();
                  // 检查是否能被任一来源识别（外部优先）
                  final notifier =
                      ref.read(playlistImportProvider.notifier);
                  final sourceManager = ref.read(sourceManagerProvider);
                  if (notifier.detectSource(trimmed) == null &&
                      sourceManager.getSourceForUrl(trimmed) == null) {
                    return t.library.importPlaylist.unsupportedFormat;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 歌单名称
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: t.library.importPlaylist.nameLabel,
                  hintText: t.library.importPlaylist.nameHint,
                  prefixIcon: const Icon(Icons.edit),
                ),
                enabled: !_isImporting,
              ),

              // 搜索来源选择（仅外部歌单显示）
              if (isExternal && !_isImporting) ...[
                const SizedBox(height: 16),
                Text(
                  t.library.importPlaylist.searchSource,
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
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _searchSource = source);
                        }
                      },
                    );
                  }).toList(),
                ),
              ],

              // 进度显示
              if (_isImporting) ...[
                const SizedBox(height: 24),
                LinearProgressIndicator(value: progressValue),
                const SizedBox(height: 8),
                SizedBox(
                  height: 20,
                  child: Text(
                    progressText,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (progressCount != null)
                  Text(
                    progressCount,
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
                    borderRadius: AppRadius.borderRadiusLg,
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
          onPressed: () {
            if (_isImporting) {
              _cancelImport();
            }
            Navigator.pop(context);
          },
          child: Text(t.general.cancel),
        ),
        FilledButton(
          onPressed: _isImporting ? null : _startImport,
          child: _isImporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t.library.importPlaylist.import),
        ),
      ],
    );
  }

  String _getProgressText() {
    if (_detected?.type == _UrlType.internal) {
      return _internalProgress?.currentItem ?? t.library.importPlaylist.processing;
    } else {
      return _externalProgress?.currentItem ??
          _getPhaseText(_externalProgress?.phase ?? ImportPhase.idle);
    }
  }

  double? _getProgressValue() {
    if (_detected?.type == _UrlType.internal) {
      final p = _internalProgress;
      return p != null && p.total > 0 ? p.percentage : null;
    } else {
      final p = _externalProgress;
      return p != null && p.total > 0 ? p.percentage : null;
    }
  }

  String? _getProgressCount() {
    if (_detected?.type == _UrlType.internal) {
      final p = _internalProgress;
      return p != null && p.total > 0 ? '${p.current} / ${p.total}' : null;
    } else {
      final p = _externalProgress;
      return p != null && p.total > 0 ? '${p.current} / ${p.total}' : null;
    }
  }

  String _getPhaseText(ImportPhase phase) {
    switch (phase) {
      case ImportPhase.idle:
        return t.library.importPlaylist.preparing;
      case ImportPhase.fetching:
        return t.library.importPlaylist.fetchingInfo;
      case ImportPhase.matching:
        return t.library.importPlaylist.matching;
      case ImportPhase.completed:
        return t.library.importPlaylist.completed;
      case ImportPhase.error:
        return t.library.importPlaylist.error;
    }
  }

  /// 取消导入
  void _cancelImport() {
    if (_detected?.type == _UrlType.external) {
      ref.read(playlistImportProvider.notifier).cancelImport();
    }
    _internalImportService?.cancelImport();
    _internalProgressSub?.cancel();
    _externalProgressSub?.cancel();
  }

  Future<void> _startImport() async {
    if (!_formKey.currentState!.validate()) return;

    // 重新检测以确保类型准确
    _onUrlChanged(_urlController.text);

    if (_detected == null) return;

    if (_detected!.type == _UrlType.internal) {
      await _startInternalImport();
    } else {
      await _startExternalImport();
    }
  }

  /// 内部来源导入（B站/YouTube）
  Future<void> _startInternalImport() async {
    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final sourceManager = ref.read(sourceManagerProvider);
      final playlistRepo = ref.read(playlistRepositoryProvider);
      final trackRepo = ref.read(trackRepositoryProvider);
      final isar = await ref.read(databaseProvider.future);

      final importService = url_import.ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepo,
        trackRepository: trackRepo,
        isar: isar,
      );
      _internalImportService = importService;

      _internalProgressSub = importService.progressStream.listen((progress) {
        if (mounted) {
          setState(() => _internalProgress = progress);
        }
      });

      final url = _urlController.text.trim();
      final customName = _nameController.text.trim();

      final result = await importService.importFromUrl(
        url,
        customName: customName.isEmpty ? null : customName,
      );

      // 刷新相关 providers
      ref.invalidate(allPlaylistsProvider);
      ref.invalidate(playlistDetailProvider(result.playlist.id));
      ref.invalidate(playlistCoverProvider(result.playlist.id));

      if (mounted) {
        Navigator.pop(context);
        ToastService.success(
          context,
          '${t.library.importPlaylist.importSuccess(n: result.addedCount)}'
          '${result.skippedCount > 0 ? ', ${t.library.importPlaylist.skipped(n: result.skippedCount)}' : ''}',
        );
      }
    } catch (e) {
      if (mounted && !e.toString().contains('导入已取消')) {
        setState(() {
          _isImporting = false;
          _errorMessage = e.toString();
        });
      }
    } finally {
      _internalProgressSub?.cancel();
      // 导入完全停止后清理残留的部分歌单（此时无 Isar 写入冲突）
      await _internalImportService?.cleanupCancelledImport();
      _internalImportService = null;
    }
  }

  /// 外部来源导入（网易云/QQ音乐/Spotify）
  Future<void> _startExternalImport() async {
    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(playlistImportServiceProvider);
      final notifier = ref.read(playlistImportProvider.notifier);

      notifier.setSearchSource(_searchSource);

      _externalProgressSub = service.progressStream.listen((progress) {
        if (mounted) {
          setState(() => _externalProgress = progress);
        }
      });

      final url = _urlController.text.trim();
      final customName = _nameController.text.trim();

      await notifier.importAndMatch(url);

      final state = ref.read(playlistImportProvider);

      if (state.phase == ImportPhase.error) {
        throw Exception(state.errorMessage ?? t.library.importPlaylist.importFailed);
      }

      if (mounted) {
        Navigator.pop(context);
        await showImportPreviewDialog(
          context,
          customName: customName.isEmpty ? null : customName,
        );
        ref.read(playlistImportProvider.notifier).reset();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _errorMessage = e.toString();
        });
      }
    } finally {
      _externalProgressSub?.cancel();
    }
  }
}
