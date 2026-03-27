import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/ui_constants.dart';
import '../../../../core/services/image_loading_service.dart';
import '../../../../core/services/toast_service.dart';
import '../../../../data/models/track.dart';
import '../../../../data/sources/bilibili_source.dart';
import '../../../../data/sources/source_provider.dart';
import '../../../../i18n/strings.g.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/database_provider.dart';
import '../../../../providers/playlist_provider.dart';
import '../../../../providers/repository_providers.dart';
import '../../../../services/import/import_service.dart';

/// 帳號歌單列表項
class _PlaylistItem {
  final String id;
  final String title;
  final int trackCount;
  final String? thumbnailUrl;
  final String importUrl;
  final bool isImported;

  const _PlaylistItem({
    required this.id,
    required this.title,
    required this.trackCount,
    this.thumbnailUrl,
    required this.importUrl,
    this.isImported = false,
  });
}

/// 帳號歌單導入 BottomSheet
class AccountPlaylistsSheet extends ConsumerStatefulWidget {
  final SourceType platform;

  const AccountPlaylistsSheet({super.key, required this.platform});

  @override
  ConsumerState<AccountPlaylistsSheet> createState() =>
      _AccountPlaylistsSheetState();
}

class _AccountPlaylistsSheetState
    extends ConsumerState<AccountPlaylistsSheet> {
  List<_PlaylistItem>? _playlists;
  final Set<String> _selectedIds = {};
  bool _isLoading = true;
  bool _isImporting = false;
  String? _error;

  // 批量導入進度
  int _importCurrent = 0;
  int _importTotal = 0;
  String? _currentPlaylistName; // 當前正在導入的歌單名稱
  String? _importError; // 導入錯誤信息

  // 單個歌單內的曲目進度
  ImportProgress? _trackProgress;
  StreamSubscription<ImportProgress>? _trackProgressSub;
  ImportService? _currentImportService;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  @override
  void dispose() {
    _trackProgressSub?.cancel();
    _currentImportService?.cancelImport();
    super.dispose();
  }

  void _cancelImport() {
    _isCancelled = true;
    _currentImportService?.cancelImport();
    _trackProgressSub?.cancel();
  }

  Future<void> _loadPlaylists() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 並行獲取歌單列表和已導入 ID
      final results = await Future.wait([
        _fetchPlaylists(),
        _getImportedIds(),
      ]);
      final items = results[0] as List<_PlaylistItem>;
      final importedIds = results[1] as Set<String>;

      if (!mounted) return;
      setState(() {
        _playlists = items.map((item) {
          final imported = importedIds.contains(item.id);
          return imported ? _PlaylistItem(
            id: item.id,
            title: item.title,
            trackCount: item.trackCount,
            thumbnailUrl: item.thumbnailUrl,
            importUrl: item.importUrl,
            isImported: true,
          ) : item;
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = t.remote.error.unknown(code: 'LOAD');
        _isLoading = false;
      });
    }
  }

  Future<List<_PlaylistItem>> _fetchPlaylists() async {
    switch (widget.platform) {
      case SourceType.bilibili:
        final service = ref.read(bilibiliFavoritesServiceProvider);
        final folders = await service.getFavFolders();
        return folders.map((f) => _PlaylistItem(
          id: f.id.toString(),
          title: f.title,
          trackCount: f.mediaCount,
          thumbnailUrl: f.coverUrl,
          importUrl: 'https://space.bilibili.com/0/favlist?fid=${f.id}',
        )).toList();
      case SourceType.youtube:
        final service = ref.read(youtubePlaylistServiceProvider);
        final playlists = await service.getPlaylists();
        return playlists.map((p) => _PlaylistItem(
          id: p.playlistId,
          title: p.title,
          trackCount: p.videoCount,
          thumbnailUrl: p.thumbnailUrl,
          importUrl:
              'https://www.youtube.com/playlist?list=${p.playlistId}',
        )).toList();
      case SourceType.netease:
        final service = ref.read(neteaseAccountServiceProvider);
        final playlists = await service.getUserPlaylists();
        return playlists.map((p) => _PlaylistItem(
          id: p.id,
          title: p.name,
          trackCount: p.trackCount,
          thumbnailUrl: p.coverUrl,
          importUrl: 'https://music.163.com/playlist?id=${p.id}',
        )).toList();
    }
  }

  /// 獲取已導入歌單的平台 ID 集合（從 sourceUrl 中提取）
  Future<Set<String>> _getImportedIds() async {
    final repo = ref.read(playlistRepositoryProvider);
    final imported = await repo.getImported();
    final ids = <String>{};
    for (final p in imported) {
      final url = p.sourceUrl;
      if (url == null) continue;
      switch (widget.platform) {
        case SourceType.bilibili:
          final fid = BilibiliSource.parseFavoritesId(url);
          if (fid != null) ids.add(fid);
        case SourceType.youtube:
          // YouTube playlist URL 中的 list= 參數
          final uri = Uri.tryParse(url);
          final listId = uri?.queryParameters['list'];
          if (listId != null) ids.add(listId);
        case SourceType.netease:
          // 網易雲歌單 URL 中的 id= 參數
          final uri = Uri.tryParse(url);
          final id = uri?.queryParameters['id'];
          if (id != null) ids.add(id);
      }
    }
    return ids;
  }

  /// 輕量刷新已導入狀態（不重新請求 API）
  Future<void> _refreshImportStatus() async {
    final importedIds = await _getImportedIds();
    if (!mounted || _playlists == null) return;
    setState(() {
      _playlists = _playlists!.map((item) {
        final imported = importedIds.contains(item.id);
        return imported != item.isImported
            ? _PlaylistItem(
                id: item.id,
                title: item.title,
                trackCount: item.trackCount,
                thumbnailUrl: item.thumbnailUrl,
                importUrl: item.importUrl,
                isImported: imported,
              )
            : item;
      }).toList();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _importSelected() async {
    final selected = _playlists!
        .where((p) => _selectedIds.contains(p.id) && !p.isImported)
        .toList();
    if (selected.isEmpty) return;

    setState(() {
      _isImporting = true;
      _isCancelled = false;
      _importCurrent = 0;
      _importTotal = selected.length;
      _trackProgress = null;
      _importError = null;
    });

    final sourceManager = ref.read(sourceManagerProvider);
    final playlistRepo = ref.read(playlistRepositoryProvider);
    final trackRepo = ref.read(trackRepositoryProvider);
    final isar = await ref.read(databaseProvider.future);

    int successCount = 0;
    String? importError;

    for (final item in selected) {
      if (!mounted || _isCancelled) break;
      setState(() {
        _importCurrent++;
        _currentPlaylistName = item.title;
        _trackProgress = null;
      });

      try {
        final importService = ImportService(
          sourceManager: sourceManager,
          playlistRepository: playlistRepo,
          trackRepository: trackRepo,
          isar: isar,
          bilibiliAccountService: ref.read(bilibiliAccountServiceProvider),
          youtubeAccountService: ref.read(youtubeAccountServiceProvider),
          neteaseAccountService: ref.read(neteaseAccountServiceProvider),
        );
        _currentImportService = importService;

        _trackProgressSub?.cancel();
        _trackProgressSub = importService.progressStream.listen((progress) {
          if (mounted) {
            setState(() => _trackProgress = progress);
          }
        });

        await importService.importFromUrl(
          item.importUrl,
          useAuth: true,
        );
        successCount++;
      } catch (e) {
        if (_isCancelled) break;
        // 非取消錯誤：停止導入，顯示錯誤
        importError = t.remote.error.unknown(code: 'IMPORT');
        break;
      } finally {
        _trackProgressSub?.cancel();
        _trackProgressSub = null;
        await _currentImportService?.cleanupCancelledImport();
        _currentImportService = null;
      }
    }

    if (!mounted) return;
    ref.invalidate(allPlaylistsProvider);

    if (importError != null) {
      // 有錯誤：留在 sheet，顯示錯誤信息
      setState(() {
        _isImporting = false;
        _importError = importError;
        _selectedIds.clear();
      });
      // 輕量刷新已導入狀態（不重新請求 API）
      _refreshImportStatus();
    } else {
      if (!mounted) return;
      Navigator.pop(context);
      if (successCount > 0) {
        ToastService.success(
          context,
          t.account.importComplete(count: successCount.toString()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final importedIds = _playlists == null
        ? <String>{}
        : {for (final p in _playlists!) if (p.isImported) p.id};
    final selectedCount =
        _selectedIds.where((id) => !importedIds.contains(id)).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 拖拽指示條
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outline.withValues(alpha: 0.3),
              borderRadius: AppRadius.borderRadiusXs,
            ),
          ),
          // 標題
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  t.account.selectPlaylists,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(),
          // Content
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              clipBehavior: Clip.hardEdge,
              child: _buildContent(scrollController),
            ),
          ),
          // Bottom action bar
          if (!_isLoading && _error == null && (_playlists?.isNotEmpty ?? false))
            _buildBottomBar(selectedCount),
        ],
      ),
    );
  }

  Widget _buildContent(ScrollController scrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_playlists == null || _playlists!.isEmpty) {
      return Center(child: Text(t.account.noPlaylists));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _playlists!.length,
      itemBuilder: (context, index) {
        final item = _playlists![index];
        return _buildPlaylistTile(item);
      },
    );
  }

  Widget _buildPlaylistTile(_PlaylistItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedIds.contains(item.id);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: AppRadius.borderRadiusMd,
          color: colorScheme.surfaceContainerHighest,
        ),
        clipBehavior: Clip.antiAlias,
        child: item.thumbnailUrl != null
            ? ImageLoadingService.loadImage(
                networkUrl: item.thumbnailUrl,
                placeholder: Icon(Icons.playlist_play,
                    color: colorScheme.outline),
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                targetDisplaySize: 40,
              )
            : Icon(Icons.playlist_play, color: colorScheme.outline),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(t.account.trackCount(count: item.trackCount.toString())),
      trailing: item.isImported
          ? Icon(Icons.check_circle, color: colorScheme.outline)
          : isSelected
              ? Icon(Icons.check_circle, color: colorScheme.primary)
              : Icon(Icons.circle_outlined, color: colorScheme.outline),
      selected: isSelected,
      selectedTileColor:
          colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusLg),
      onTap: item.isImported || _isImporting
          ? null
          : () => _toggleSelection(item.id),
    );
  }

  Widget _buildBottomBar(int selectedCount) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isImporting) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _currentPlaylistName ?? '',
                      style: textStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$_importCurrent/$_importTotal',
                    style: textStyle,
                  ),
                ],
              ),
              if (_trackProgress != null) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        // 分P階段 currentItem 自帶進度數字，提取純文字部分
                        _trackProgress!.currentItem
                                ?.replaceFirst(RegExp(r'\s*\(\d+/\d+\)$'), '') ??
                            t.account.importing,
                        style: textStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_trackProgress!.total > 0)
                      Text(
                        '${_trackProgress!.current}/${_trackProgress!.total}',
                        style: textStyle,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
            ],
            // 導入錯誤信息
            if (_importError != null) ...[
              Text(
                _importError!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.error,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: _isImporting
                  ? OutlinedButton(
                      onPressed: () {
                        _cancelImport();
                        Navigator.pop(context);
                      },
                      child: Text(t.general.cancel),
                    )
                  : FilledButton(
                      onPressed:
                          selectedCount > 0 ? _importSelected : null,
                      child: Text(
                        t.account.importSelected(
                            count: selectedCount.toString()),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
