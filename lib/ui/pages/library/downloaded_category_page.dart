import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../data/models/track.dart';
import '../../../providers/download_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../widgets/now_playing_indicator.dart';
import '../../widgets/track_group/track_group.dart';
import '../../widgets/track_thumbnail.dart';
import '../../../i18n/strings.g.dart';

/// 已下载分类详情页面
class DownloadedCategoryPage extends ConsumerStatefulWidget {
  final DownloadedCategory category;

  const DownloadedCategoryPage({super.key, required this.category});

  @override
  ConsumerState<DownloadedCategoryPage> createState() => _DownloadedCategoryPageState();
}

class _DownloadedCategoryPageState extends ConsumerState<DownloadedCategoryPage> {
  // 展开状态：key是groupKey
  final Set<String> _expandedGroups = {};

  // 缓存分组结果，避免每次 build 重新计算
  List<Track>? _cachedTracks;
  List<TrackGroup>? _cachedGroups;

  // 滚动控制器，用于跟踪 AppBar 收起状态
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  // AppBar 收起阈值（expandedHeight - kToolbarHeight）
  static const double _collapseThreshold = AppSizes.collapseThreshold;

  @override
  void initState() {
    super.initState();
    // 监听滚动位置
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    // 只在跨越阈值时更新状态，避免频繁 rebuild
    final wasCollapsed = _scrollOffset >= _collapseThreshold;
    final isCollapsed = offset >= _collapseThreshold;
    if (wasCollapsed != isCollapsed) {
      setState(() {
        _scrollOffset = offset;
      });
    } else {
      _scrollOffset = offset;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 刷新数据
  Future<void> _refresh() async {
    // 清除缓存
    setState(() {
      _cachedTracks = null;
      _cachedGroups = null;
    });
    // 使 provider 失效并等待重新加载
    ref.invalidate(downloadedCategoryTracksProvider(widget.category.folderPath));
    await ref.read(downloadedCategoryTracksProvider(widget.category.folderPath).future);
  }

  /// 获取分组后的 tracks，使用缓存避免重复计算
  List<TrackGroup> _getGroupedTracks(List<Track> tracks) {
    // 检查是否需要重新计算
    if (_cachedTracks != tracks || _cachedGroups == null) {
      _cachedTracks = tracks;
      _cachedGroups = groupTracks(tracks);
    }
    return _cachedGroups!;
  }

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(downloadedCategoryTracksProvider(widget.category.folderPath));
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: tracksAsync.when(
        loading: () => CustomScrollView(
          controller: _scrollController,
          slivers: [
            _buildSliverAppBar(context, []),
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
        error: (error, stack) => CustomScrollView(
          controller: _scrollController,
          slivers: [
            _buildSliverAppBar(context, []),
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text(t.library.loadFailedWithError(error: error.toString())),
                  ],
                ),
              ),
            ),
          ],
        ),
        data: (tracks) {
          // 使用缓存的分组结果，避免每次 build 重新计算
          final groupedTracks = _getGroupedTracks(tracks);

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              // 折叠式应用栏
              _buildSliverAppBar(context, tracks),

              // 操作按钮
              SliverToBoxAdapter(
                child: _buildActionButtons(context, tracks),
              ),

              // 歌曲列表
              if (tracks.isEmpty)
                SliverFillRemaining(
                  child: _buildEmptyState(context),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final group = groupedTracks[index];
                      return _buildGroupItem(context, group);
                    },
                    childCount: groupedTracks.length,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, List<Track> tracks) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalDuration = _calculateTotalDuration(tracks);

    // 根据滚动位置决定图标颜色：展开时白色，收起时使用主题色
    final isCollapsed = _scrollOffset >= _collapseThreshold;
    final iconColor = isCollapsed ? colorScheme.onSurface : Colors.white;

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: iconColor),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.refresh, color: iconColor),
          onPressed: _refresh,
          tooltip: t.library.refresh,
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // 封面背景
            _buildCoverBackground(colorScheme),

            // 渐变遮罩
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    colorScheme.surface.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),

            // 分类信息
            Positioned(
              left: 16,
              right: 16,
              bottom: 70,
              child: Row(
                children: [
                  // 封面
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.borderRadiusLg,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildCover(colorScheme),
                  ),
                  const SizedBox(width: 16),

                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 分类名称
                        Text(
                          widget.category.displayName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.library.downloadedCategory.trackCountDuration(count: tracks.length, duration: DurationFormatter.formatLong(totalDuration)),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white60,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: AppRadius.borderRadiusXl,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.download_done,
                                size: 14,
                                color: colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                t.library.downloaded,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverBackground(ColorScheme colorScheme) {
    final gradientPlaceholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.tertiaryContainer,
          ],
        ),
      ),
    );

    if (widget.category.coverPath != null) {
      return ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Colors.black54,
          BlendMode.darken,
        ),
        child: ImageLoadingService.loadImage(
          localPath: widget.category.coverPath,
          networkUrl: null,
          placeholder: gradientPlaceholder,
          fit: BoxFit.cover,
        ),
      );
    }
    return gradientPlaceholder;
  }

  Widget _buildCover(ColorScheme colorScheme) {
    final placeholder = Container(
      color: colorScheme.primaryContainer,
      child: Icon(
        Icons.folder,
        size: 48,
        color: colorScheme.primary,
      ),
    );

    if (widget.category.coverPath != null) {
      return ImageLoadingService.loadImage(
        localPath: widget.category.coverPath,
        networkUrl: null,
        placeholder: placeholder,
        fit: BoxFit.cover,
      );
    }
    return placeholder;
  }

  Widget _buildActionButtons(BuildContext context, List<Track> tracks) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: tracks.isEmpty ? null : () => _playAll(tracks),
              icon: const Icon(Icons.play_arrow),
              label: Text(t.library.addAll),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: tracks.isEmpty ? null : () => _shufflePlay(tracks),
              icon: const Icon(Icons.shuffle),
              label: Text(t.library.shuffleAdd),
            ),
          ),
        ],
      ),
    );
  }

  Duration _calculateTotalDuration(List<Track> tracks) {
    int totalMs = 0;
    for (final track in tracks) {
      totalMs += track.durationMs ?? 0;
    }
    return Duration(milliseconds: totalMs);
  }

  void _playAll(List<Track> tracks) {
    final controller = ref.read(audioControllerProvider.notifier);
    controller.addAllToQueue(tracks);
    ToastService.success(context, t.library.addedToQueue(n: tracks.length));
  }

  void _shufflePlay(List<Track> tracks) {
    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(tracks)..shuffle();
    controller.addAllToQueue(shuffled);
    ToastService.success(context, t.library.shuffledAddedToQueue(n: tracks.length));
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_done,
            size: 64,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            t.library.downloadedCategory.noCategoryTracks,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  /// 构建分组项
  Widget _buildGroupItem(BuildContext context, TrackGroup group) {
    // 如果组只有一个track，显示普通样式
    if (group.tracks.length == 1) {
      return _DownloadedTrackTile(
        track: group.tracks.first,
        onTap: () => _playTrack(group.tracks.first),
        isPartOfMultiPage: false,
        folderPath: widget.category.folderPath,
      );
    }

    // 多P视频，显示可展开样式
    final isExpanded = _expandedGroups.contains(group.groupKey);

    return Column(
      children: [
        // 父视频标题行
        _GroupHeader(
          group: group,
          isExpanded: isExpanded,
          folderPath: widget.category.folderPath,
          onToggle: () => _toggleGroup(group.groupKey),
          onPlayFirst: () => _playTrack(group.tracks.first),
          onAddAllToQueue: () => _addAllToQueue(context, group.tracks),
        ),
        // 展开的分P列表
        if (isExpanded)
          ...group.tracks.map((track) => _DownloadedTrackTile(
                track: track,
                onTap: () => _playTrack(track),
                isPartOfMultiPage: true,
                indent: true,
                folderPath: widget.category.folderPath,
              )),
      ],
    );
  }

  void _toggleGroup(String groupKey) {
    setState(() {
      if (_expandedGroups.contains(groupKey)) {
        _expandedGroups.remove(groupKey);
      } else {
        _expandedGroups.add(groupKey);
      }
    });
  }

  void _addAllToQueue(BuildContext context, List<Track> tracks) async {
    final controller = ref.read(audioControllerProvider.notifier);
    final added = await controller.addAllToQueue(tracks);
    if (added && context.mounted) {
      ToastService.success(context, t.library.downloadedCategory.addedPartsToQueue(n: tracks.length));
    }
  }

  void _playTrack(Track track) {
    final controller = ref.read(audioControllerProvider.notifier);
    controller.playTemporary(track);
  }
}

/// 分组标题组件
class _GroupHeader extends ConsumerWidget {
  final TrackGroup group;
  final bool isExpanded;
  final String folderPath;
  final VoidCallback onToggle;
  final VoidCallback onPlayFirst;
  final VoidCallback onAddAllToQueue;

  const _GroupHeader({
    required this.group,
    required this.isExpanded,
    required this.folderPath,
    required this.onToggle,
    required this.onPlayFirst,
    required this.onAddAllToQueue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final firstTrack = group.tracks.first;
    final currentTrack = ref.watch(currentTrackProvider);
    // 检查当前播放的是否是这个组的某个分P
    // 使用 sourceId + pageNum 比较，因为文件扫描的 Track 没有数据库 ID
    final isPlayingThisGroup = currentTrack != null &&
        group.tracks.any((t) =>
            t.sourceId == currentTrack.sourceId &&
            t.pageNum == currentTrack.pageNum);

    return ListTile(
      onTap: onToggle,
      leading: TrackThumbnail(
        track: firstTrack,
        size: 48,
        isPlaying: isPlayingThisGroup,
      ),
      title: Text(
        group.parentTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isPlayingThisGroup ? colorScheme.primary : null,
          fontWeight: isPlayingThisGroup ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Row(
        children: [
          Text(
            firstTrack.artist ?? t.library.unknownUploader,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: AppRadius.borderRadiusSm,
            ),
            child: Text(
              '${group.tracks.length}P',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 展开/折叠按钮
          IconButton(
            icon: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onPressed: onToggle,
          ),
          // 菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleMenuAction(context, ref, value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'play_first',
                child: ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(t.library.downloadedCategory.playFirstPart),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'add_all_to_queue',
                child: ListTile(
                  leading: const Icon(Icons.add_to_queue),
                  title: Text(t.library.downloadedCategory.addAllToQueue),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete_all',
                child: ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(t.library.downloadedCategory.deleteAllDownloads),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'play_first':
        onPlayFirst();
        break;
      case 'add_all_to_queue':
        onAddAllToQueue();
        break;

      case 'delete_all':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.library.deleteDownload),
            content: Text(t.library.downloadedCategory.confirmDeleteParts(n: group.tracks.length)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.general.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.general.delete),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await _deleteAllDownloads(ref);
          if (context.mounted) {
            ToastService.success(context, t.library.downloadedCategory.deletedParts(n: group.tracks.length));
          }
        }
        break;
    }
  }

  Future<void> _deleteAllDownloads(WidgetRef ref) async {
    final trackRepo = ref.read(trackRepositoryProvider);
    for (final track in group.tracks) {
      // 删除所有下载路径对应的文件
      for (final path in track.allDownloadPaths) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      // 清除数据库中的下载路径
      await trackRepo.clearDownloadPath(track.id);
    }
    // 刷新列表
    ref.invalidate(downloadedCategoryTracksProvider(folderPath));
    ref.invalidate(downloadedCategoriesProvider);
  }
}

/// 已下载歌曲列表项
class _DownloadedTrackTile extends ConsumerWidget {
  final Track track;
  final VoidCallback onTap;
  final bool isPartOfMultiPage;
  final bool indent;
  final String folderPath;

  const _DownloadedTrackTile({
    required this.track,
    required this.onTap,
    required this.isPartOfMultiPage,
    required this.folderPath,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    // 使用 sourceId + pageNum 比较，因为文件扫描的 Track 没有数据库 ID
    final isPlaying = currentTrack != null &&
        currentTrack.sourceId == track.sourceId &&
        currentTrack.pageNum == track.pageNum;

    return Padding(
      padding: EdgeInsets.only(left: indent ? 56 : 0),
      child: ListTile(
        leading: isPartOfMultiPage
            // 分P使用与搜索页面相同的样式
            ? (isPlaying
                ? NowPlayingIndicator(
                    size: 24,
                    color: colorScheme.primary,
                  )
                : Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadius.borderRadiusSm,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'P${track.pageNum ?? 1}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                  ))
            : TrackThumbnail(
                track: track,
                size: 48,
                isPlaying: isPlaying,
              ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isPlaying ? colorScheme.primary : null,
            fontWeight: isPlaying ? FontWeight.w600 : null,
          ),
        ),
        subtitle: isPartOfMultiPage
            ? null // 分P不显示副标题，与搜索页面一致
            : Text(
                track.artist ?? t.general.unknownArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (track.durationMs != null)
              SizedBox(
                width: 48, // 与 IconButton 宽度对齐
                child: Text(
                  DurationFormatter.formatMs(track.durationMs!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (value) => _handleMenuAction(context, ref, value),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'play_next',
                  child: ListTile(
                    leading: const Icon(Icons.queue_play_next),
                    title: Text(t.library.playNext),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'add_to_queue',
                  child: ListTile(
                    leading: const Icon(Icons.add_to_queue),
                    title: Text(t.library.addToQueue),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),

                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text(t.library.deleteDownload),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'play_next':
        final added = await ref.read(audioControllerProvider.notifier).addNext(track);
        if (added && context.mounted) {
          ToastService.success(context, t.library.addedToNext);
        }
        break;
      case 'add_to_queue':
        final added = await ref.read(audioControllerProvider.notifier).addToQueue(track);
        if (added && context.mounted) {
          ToastService.success(context, t.library.addedToPlayQueue);
        }
        break;

      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.library.deleteDownload),
            content: Text(t.library.downloadedCategory.confirmDeleteTrack),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.general.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.general.delete),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await _deleteDownload(ref);
          if (context.mounted) {
            ToastService.success(context, t.library.downloadDeleted);
          }
        }
        break;
    }
  }

  Future<void> _deleteDownload(WidgetRef ref) async {
    final trackRepo = ref.read(trackRepositoryProvider);

    // 删除所有下载路径对应的文件
    for (final path in track.allDownloadPaths) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    // 清除数据库中的下载路径
    await trackRepo.clearDownloadPath(track.id);

    // 刷新列表
    ref.invalidate(downloadedCategoryTracksProvider(folderPath));
    ref.invalidate(downloadedCategoriesProvider);
  }
}
