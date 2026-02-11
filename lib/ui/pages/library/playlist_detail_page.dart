import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/image_loading_service.dart';
import '../../router.dart';
import '../../../core/services/toast_service.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../data/models/track.dart';
import '../../../providers/playlist_provider.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/download/file_exists_cache.dart';
import '../../../providers/download_path_provider.dart';
import '../../../providers/selection_provider.dart';
import '../../widgets/download_path_setup_dialog.dart';
import '../../../services/audio/audio_provider.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
import '../../widgets/now_playing_indicator.dart';
import '../../widgets/selection_mode_app_bar.dart';
import '../../widgets/context_menu_region.dart';
import '../../widgets/track_group/track_group.dart';
import '../../widgets/track_thumbnail.dart';

/// 歌单详情页
class PlaylistDetailPage extends ConsumerStatefulWidget {
  final int playlistId;

  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  // 展开状态：key是groupKey
  final Set<String> _expandedGroups = {};

  // 缓存分组结果，避免每次 build 重新计算
  List<Track>? _cachedTracks;
  List<TrackGroup>? _cachedGroups;

  // 上次刷新缓存时的 tracks 长度，用于检测变化
  int _lastRefreshedTracksLength = -1;

  // 滚动控制器，用于跟踪 AppBar 收起状态
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  // AppBar 收起阈值（expandedHeight - kToolbarHeight）
  static const double _collapseThreshold = 280 - kToolbarHeight;

  @override
  void initState() {
    super.initState();
    // 监听滚动位置
    _scrollController.addListener(_onScroll);
    // 初始刷新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadCoverPaths();
    });
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

  /// 预加载封面图路径缓存
  Future<void> _preloadCoverPaths() async {
    final state = ref.read(playlistDetailProvider(widget.playlistId));
    if (state.tracks.isNotEmpty && state.tracks.length != _lastRefreshedTracksLength) {
      _lastRefreshedTracksLength = state.tracks.length;
      // 预加载封面路径（用于 TrackThumbnail）
      final coverPaths = state.tracks
          .where((t) => t.hasAnyDownload)
              .map((t) => '${t.allDownloadPaths.first.replaceAll(RegExp(r'[/\\][^/\\]+$'), '')}/cover.jpg')
          .toList();
      if (coverPaths.isNotEmpty) {
        await ref.read(fileExistsCacheProvider.notifier).preloadPaths(coverPaths);
      }
    }
  }

  /// 检查并预加载缓存（在 build 中调用，当 tracks 变化时）
  void _checkAndPreloadCache(List<Track> tracks) {
    if (tracks.isNotEmpty && tracks.length != _lastRefreshedTracksLength) {
      // 使用 addPostFrameCallback 避免在 build 期间修改 state
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _lastRefreshedTracksLength = tracks.length;
          // 预加载封面路径
          final coverPaths = tracks
              .where((t) => t.hasAnyDownload)
              .map((t) => '${t.allDownloadPaths.first.replaceAll(RegExp(r'[/\\][^/\\]+$'), '')}/cover.jpg')
              .toList();
          if (coverPaths.isNotEmpty) {
            ref.read(fileExistsCacheProvider.notifier).preloadPaths(coverPaths);
          }
        }
      });
    }
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
    final state = ref.watch(playlistDetailProvider(widget.playlistId));
    final selectionState = ref.watch(playlistDetailSelectionProvider);
    final colorScheme = Theme.of(context).colorScheme;

    if (state.isLoading && state.playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null && state.playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(state.error!),
            ],
          ),
        ),
      );
    }

    final playlist = state.playlist!;
    final tracks = state.tracks;
    final isImported = playlist.isImported;
    final isMix = playlist.isMix;

    // 检查并刷新下载状态缓存（当 tracks 变化时）
    _checkAndPreloadCache(tracks);

    // 使用缓存的分组结果，避免每次 build 重新计算
    final groupedTracks = _getGroupedTracks(tracks);

    // 多選模式下的可用操作
    final availableActions = <SelectionAction>{
      SelectionAction.addToQueue,
      SelectionAction.playNext,
      SelectionAction.addToPlaylist,
      SelectionAction.download,
      if (!isImported && !isMix) SelectionAction.delete,
    };

    // 處理返回鍵退出多選模式
    return PopScope(
      canPop: !selectionState.isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectionState.isSelectionMode) {
          ref.read(playlistDetailSelectionProvider.notifier).exitSelectionMode();
        }
      },
      child: Scaffold(
        body: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // 折叠式应用栏（始終顯示封面）
            _buildSliverAppBar(context, playlist, state, selectionState.isSelectionMode, tracks, availableActions),

            // 操作按钮（始終顯示）
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
        ),
      ),
    );
  }

  /// 刪除選中的歌曲
  Future<void> _deleteSelectedTracks(List<Track> tracks) async {
    final notifier = ref.read(playlistDetailProvider(widget.playlistId).notifier);
    final trackIds = tracks.map((t) => t.id).toList();
    await notifier.removeTracks(trackIds);
  }

  /// 下載選中的歌曲
  Future<void> _downloadSelectedTracks(BuildContext context, List<Track> tracks) async {
    // 检查路径配置
    final pathManager = ref.read(downloadPathManagerProvider);
    if (!await pathManager.hasConfiguredPath()) {
      if (!context.mounted) return;
      final configured = await DownloadPathSetupDialog.show(context);
      if (configured != true) return;
    }

    final downloadService = ref.read(downloadServiceProvider);
    final state = ref.read(playlistDetailProvider(widget.playlistId));
    final playlist = state.playlist;
    if (playlist == null) return;

    int addedCount = 0;
    for (final track in tracks) {
      final result = await downloadService.addTrackDownload(
        track,
        fromPlaylist: playlist,
        skipSchedule: true,
      );
      if (result == DownloadResult.created) addedCount++;
    }

    if (addedCount > 0) {
      downloadService.triggerSchedule();
      if (context.mounted) {
        ToastService.showWithAction(
          context,
          '已添加 $addedCount 首到下載隊列',
          actionLabel: '查看',
          onAction: () => context.pushNamed(RouteNames.downloadManager),
        );
      }
    }
  }

  /// 构建分组项
  Widget _buildGroupItem(BuildContext context, TrackGroup group) {
    final state = ref.read(playlistDetailProvider(widget.playlistId));
    final selectionState = ref.watch(playlistDetailSelectionProvider);
    final selectionNotifier = ref.read(playlistDetailSelectionProvider.notifier);
    final isImported = state.playlist?.isImported ?? false;
    final isMix = state.playlist?.isMix ?? false;

    // 如果组只有一个track，显示普通样式
    if (group.tracks.length == 1) {
      final track = group.tracks.first;
      return _TrackListTile(
        track: track,
        playlistId: widget.playlistId,
        playlistName: state.playlist?.name ?? '',
        onTap: selectionState.isSelectionMode
            ? () => selectionNotifier.toggleSelection(track)
            : () => _playTrack(track),
        onLongPress: selectionState.isSelectionMode
            ? null
            : () => selectionNotifier.enterSelectionMode(track),
        isPartOfMultiPage: false,
        isImported: isImported,
        isMix: isMix,
        isSelectionMode: selectionState.isSelectionMode,
        isSelected: selectionState.isSelected(track),
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
          onToggle: selectionState.isSelectionMode
              ? () => selectionNotifier.toggleGroupSelection(group.tracks)
              : () => _toggleGroup(group.groupKey),
          onLongPress: selectionState.isSelectionMode
              ? null
              : () => selectionNotifier.enterSelectionModeWithTracks(group.tracks),
          onPlayFirst: () => _playTrack(group.tracks.first),
          onAddAllToQueue: () => _addAllToQueue(context, group.tracks),
          playlistId: widget.playlistId,
          playlistName: state.playlist?.name ?? '',
          isImported: isImported,
          isMix: isMix,
          isSelectionMode: selectionState.isSelectionMode,
          isGroupFullySelected: selectionNotifier.isGroupFullySelected(group.tracks),
          isGroupPartiallySelected: selectionNotifier.isGroupPartiallySelected(group.tracks),
        ),
        // 展开的分P列表
        if (isExpanded)
          ...group.tracks.map((track) => _TrackListTile(
                track: track,
                playlistId: widget.playlistId,
                playlistName: state.playlist?.name ?? '',
                onTap: selectionState.isSelectionMode
                    ? () => selectionNotifier.toggleSelection(track)
                    : () => _playTrack(track),
                onLongPress: selectionState.isSelectionMode
                    ? null
                    : () => selectionNotifier.enterSelectionMode(track),
                isPartOfMultiPage: true,
                isImported: isImported,
                indent: true,
                isMix: isMix,
                isSelectionMode: selectionState.isSelectionMode,
                isSelected: selectionState.isSelected(track),
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
      ToastService.show(context, '已添加 ${tracks.length} 个分P到队列');
    }
  }

  /// 構建多選模式下的操作按鈕
  List<Widget> _buildSelectionActions(
    Color iconColor,
    bool isAllSelected,
    bool hasSelection,
    List<Track> allTracks,
    Set<SelectionAction> availableActions,
    SelectionNotifier notifier,
    List<Track> selectedTracks,
  ) {
    return [
      // 全選按鈕
      IconButton(
        icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all, color: iconColor),
        tooltip: isAllSelected ? '取消全選' : '全選',
        onPressed: () {
          if (isAllSelected) {
            notifier.deselectAll();
          } else {
            notifier.selectAll(allTracks);
          }
        },
      ),
      // 更多操作菜單
      PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: iconColor),
        enabled: hasSelection,
        onSelected: (value) => _handleSelectionMenuAction(value, selectedTracks),
        itemBuilder: (context) => _buildSelectionMenuItems(availableActions),
      ),
      const SizedBox(width: 8),
    ];
  }

  /// 構建多選菜單項目
  List<PopupMenuEntry<String>> _buildSelectionMenuItems(Set<SelectionAction> availableActions) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      if (availableActions.contains(SelectionAction.addToQueue))
        const PopupMenuItem(
          value: 'add_to_queue',
          child: ListTile(
            leading: Icon(Icons.add_to_queue),
            title: Text('添加到隊列'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (availableActions.contains(SelectionAction.playNext))
        const PopupMenuItem(
          value: 'play_next',
          child: ListTile(
            leading: Icon(Icons.queue_play_next),
            title: Text('下一首播放'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (availableActions.contains(SelectionAction.addToPlaylist))
        const PopupMenuItem(
          value: 'add_to_playlist',
          child: ListTile(
            leading: Icon(Icons.playlist_add),
            title: Text('添加到歌單'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (availableActions.contains(SelectionAction.download))
        const PopupMenuItem(
          value: 'download',
          child: ListTile(
            leading: Icon(Icons.download),
            title: Text('下載'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (availableActions.contains(SelectionAction.delete))
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: colorScheme.error),
            title: Text('從歌單移除', style: TextStyle(color: colorScheme.error)),
            contentPadding: EdgeInsets.zero,
          ),
        ),
    ];
  }

  /// 處理多選菜單操作
  Future<void> _handleSelectionMenuAction(String action, List<Track> tracks) async {
    final notifier = ref.read(playlistDetailSelectionProvider.notifier);
    final controller = ref.read(audioControllerProvider.notifier);

    switch (action) {
      case 'add_to_queue':
        int addedCount = 0;
        for (final track in tracks) {
          final added = await controller.addToQueue(track);
          if (added) addedCount++;
        }
        notifier.exitSelectionMode();
        if (mounted) {
          ToastService.show(context, '已添加 $addedCount 首到隊列');
        }
        break;
      case 'play_next':
        int addedCount = 0;
        for (final track in tracks.reversed) {
          final added = await controller.addNext(track);
          if (added) addedCount++;
        }
        notifier.exitSelectionMode();
        if (mounted) {
          ToastService.show(context, '已添加 $addedCount 首到下一首播放');
        }
        break;
      case 'add_to_playlist':
        notifier.exitSelectionMode();
        if (tracks.length == 1) {
          showAddToPlaylistDialog(context: context, track: tracks.first);
        } else {
          showAddToPlaylistDialog(context: context, tracks: tracks);
        }
        break;
      case 'download':
        await _downloadSelectedTracks(context, tracks);
        notifier.exitSelectionMode();
        break;
      case 'delete':
        await _confirmAndDeleteTracks(tracks);
        break;
    }
  }

  /// 確認並刪除歌曲
  Future<void> _confirmAndDeleteTracks(List<Track> tracks) async {
    final notifier = ref.read(playlistDetailSelectionProvider.notifier);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認移除'),
        content: Text('確定要從歌單中移除 ${tracks.length} 首歌曲嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteSelectedTracks(tracks);
      notifier.exitSelectionMode();
      if (mounted) {
        ToastService.show(context, '已移除 ${tracks.length} 首歌曲');
      }
    }
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    dynamic playlist,
    PlaylistDetailState state,
    bool isSelectionMode,
    List<Track> allTracks,
    Set<SelectionAction> availableActions,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final coverAsync = ref.watch(playlistCoverProvider(widget.playlistId));

    // 根据滚动位置决定图标颜色：展开时白色，收起时使用主题色
    final isCollapsed = _scrollOffset >= _collapseThreshold;
    final iconColor = isCollapsed ? colorScheme.onSurface : Colors.white;

    // 多選模式相關
    final selectionState = ref.watch(playlistDetailSelectionProvider);
    final selectionNotifier = ref.read(playlistDetailSelectionProvider.notifier);
    final selectedCount = selectionState.selectedCount;
    final hasSelection = selectionState.hasSelection;
    final isAllSelected = selectedCount == allTracks.length && allTracks.isNotEmpty;

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      // 返回/關閉按钮 - 根据收起状态切换颜色
      leading: isSelectionMode
          ? IconButton(
              icon: Icon(Icons.close, color: iconColor),
              tooltip: '退出選擇模式',
              onPressed: () => selectionNotifier.exitSelectionMode(),
            )
          : IconButton(
              icon: Icon(Icons.arrow_back, color: iconColor),
              onPressed: () => Navigator.of(context).pop(),
            ),
      // 標題（多選模式下顯示選擇數量）
      title: isSelectionMode
          ? Text('已選擇 $selectedCount 項', style: TextStyle(color: iconColor))
          : null,
      // 操作按鈕
      actions: isSelectionMode
          ? _buildSelectionActions(iconColor, isAllSelected, hasSelection, allTracks, availableActions, selectionNotifier, selectionState.selectedTracks)
          : [
              if (state.tracks.isNotEmpty && state.playlist != null && !(state.playlist!.isMix))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    icon: Icon(Icons.download_outlined, color: iconColor),
                    onPressed: () => _downloadPlaylist(context, state.playlist!),
                    tooltip: '下载全部',
                  ),
                ),
            ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // 封面背景
            coverAsync.when(
              skipLoadingOnReload: true,
              data: (coverData) => coverData.hasCover
                  ? ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Colors.black54,
                        BlendMode.darken,
                      ),
                      child: ImageLoadingService.loadImage(
                        localPath: coverData.localPath,
                        networkUrl: coverData.networkUrl,
                        placeholder: Container(color: colorScheme.primaryContainer),
                        fit: BoxFit.cover,
                        targetDisplaySize: 480,  // 高清背景
                      ),
                    )
                  : Container(color: colorScheme.primaryContainer),
              loading: () => Container(color: colorScheme.primaryContainer),
              error: (error, stack) =>
                  Container(color: colorScheme.primaryContainer),
            ),

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

            // 歌单信息
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
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: coverAsync.when(
                      skipLoadingOnReload: true,
                      data: (coverData) => coverData.hasCover
                          ? ImageLoadingService.loadImage(
                              localPath: coverData.localPath,
                              networkUrl: coverData.networkUrl,
                              placeholder: Container(
                                color: colorScheme.primaryContainer,
                                child: Center(
                                  child: Icon(
                                    Icons.music_note,
                                    size: 48,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: colorScheme.primaryContainer,
                              child: Center(
                                child: Icon(
                                  Icons.music_note,
                                  size: 48,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                      loading: () => Container(
                          color: colorScheme.surfaceContainerHighest),
                      error: (error, stack) => Container(
                          color: colorScheme.surfaceContainerHighest),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 歌单名称
                        Text(
                          playlist.name,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (playlist.description != null &&
                            playlist.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            playlist.description!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.white70,
                                    ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '${state.tracks.length} 首歌曲 · ${DurationFormatter.formatLong(state.totalDuration)}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white60,
                                  ),
                        ),
                        if (playlist.isImported || playlist.isMix) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: playlist.isMix
                                  ? colorScheme.tertiaryContainer
                                  : colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  playlist.isMix ? Icons.radio : Icons.link,
                                  size: 14,
                                  color: playlist.isMix
                                      ? colorScheme.onTertiaryContainer
                                      : colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  playlist.isMix ? 'Mix' : '已导入',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: playlist.isMix
                                            ? colorScheme.onTertiaryContainer
                                            : colorScheme.onPrimaryContainer,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
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

  Widget _buildActionButtons(
    BuildContext context,
    List<Track> tracks,
  ) {
    final state = ref.read(playlistDetailProvider(widget.playlistId));
    final isMix = state.playlist?.isMix ?? false;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: tracks.isEmpty
                  ? null
                  : isMix
                      ? () => _playMix(tracks, context)
                      : () => _playAll(tracks, context),
              icon: const Icon(Icons.play_arrow),
              label: Text(isMix ? '播放 Mix' : '添加所有'),
            ),
          ),
          if (!isMix) ...[
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    tracks.isEmpty ? null : () => _shufflePlay(tracks, context),
                icon: const Icon(Icons.shuffle),
                label: const Text('随机添加'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note,
            size: 64,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '歌单暂无歌曲',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '去搜索页面添加歌曲吧',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  void _playAll(List<Track> tracks, BuildContext context) async {
    final controller = ref.read(audioControllerProvider.notifier);
    final added = await controller.addAllToQueue(tracks);
    if (added && context.mounted) {
      ToastService.show(context, '已添加 ${tracks.length} 首歌曲到队列');
    }
  }

  void _shufflePlay(List<Track> tracks, BuildContext context) async {
    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(tracks)..shuffle();
    final added = await controller.addAllToQueue(shuffled);
    if (added && context.mounted) {
      ToastService.show(context, '已随机添加 ${tracks.length} 首歌曲到队列');
    }
  }

  void _playMix(List<Track> tracks, BuildContext context) {
    final state = ref.read(playlistDetailProvider(widget.playlistId));
    final playlist = state.playlist;
    if (playlist == null || !playlist.isMix) return;

    final controller = ref.read(audioControllerProvider.notifier);
    controller.playMixPlaylist(
      playlistId: playlist.mixPlaylistId!,
      seedVideoId: playlist.mixSeedVideoId!,
      title: playlist.name,
      tracks: tracks,
    );
  }

  void _playTrack(Track track) {
    final controller = ref.read(audioControllerProvider.notifier);
    // 临时播放点击的歌曲，播放完成后恢复原队列位置
    controller.playTemporary(track);
  }
  
  void _downloadPlaylist(BuildContext context, dynamic playlist) async {
    // 检查路径配置
    final pathManager = ref.read(downloadPathManagerProvider);
    if (!await pathManager.hasConfiguredPath()) {
      if (!context.mounted) return;
      final configured = await DownloadPathSetupDialog.show(context);
      if (configured != true) return;
    }

    final downloadService = ref.read(downloadServiceProvider);
    final addedCount = await downloadService.addPlaylistDownload(playlist);

    // 刷新 playlistCoverProvider 以便下载完成后使用第一首歌的本地封面
    ref.invalidate(playlistCoverProvider(widget.playlistId));

    if (context.mounted) {
      if (addedCount > 0) {
        ToastService.showWithAction(
          context,
          '已添加 $addedCount 首歌曲到下载队列',
          actionLabel: '查看',
          onAction: () => context.pushNamed(RouteNames.downloadManager),
        );
      } else {
        ToastService.showWithAction(
          context,
          '歌单已在下载队列中或歌單为空',
          actionLabel: '查看',
          onAction: () => context.pushNamed(RouteNames.downloadManager),
        );
      }
    }
  }
}

/// 分组标题组件
class _GroupHeader extends ConsumerWidget {
  final TrackGroup group;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onLongPress;
  final VoidCallback onPlayFirst;
  final VoidCallback onAddAllToQueue;
  final int playlistId;
  final String playlistName;
  final bool isImported;
  final bool isMix;
  final bool isSelectionMode;
  final bool isGroupFullySelected;
  final bool isGroupPartiallySelected;

  const _GroupHeader({
    required this.group,
    required this.isExpanded,
    required this.onToggle,
    this.onLongPress,
    required this.onPlayFirst,
    required this.onAddAllToQueue,
    required this.playlistId,
    required this.playlistName,
    required this.isImported,
    this.isMix = false,
    this.isSelectionMode = false,
    this.isGroupFullySelected = false,
    this.isGroupPartiallySelected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final firstTrack = group.tracks.first;
    final currentTrack = ref.watch(currentTrackProvider);
    // 检查当前播放的是否是这个组的某个分P
    // 使用 sourceId + pageNum 比较，因为临时播放的 track 可能没有数据库 ID
    final isPlayingThisGroup = currentTrack != null &&
        group.tracks.any((t) =>
            t.sourceId == currentTrack.sourceId &&
            t.pageNum == currentTrack.pageNum);

    return ContextMenuRegion(
      menuBuilder: (_) => _buildMenuItems(),
      onSelected: (value) => _handleMenuAction(context, ref, value),
      child: ListTile(
      onTap: onToggle,
      onLongPress: onLongPress,
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
            firstTrack.artist ?? '未知UP主',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${group.tracks.length}P',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
            ),
          ),
          // 检查是否所有分P都已下载（使用 playlist-specific 检查）
          if (group.tracks.every((t) => t.isDownloadedForPlaylist(playlistId, playlistName: playlistName))) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.download_done,
              size: 14,
              color: colorScheme.primary,
            ),
          ],
        ],
      ),
      trailing: isSelectionMode
          ? _SelectionGroupCheckbox(
              isFullySelected: isGroupFullySelected,
              isPartiallySelected: isGroupPartiallySelected,
              onTap: onToggle,
            )
          : Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 展开/折叠按钮
          IconButton(
            icon: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onPressed: onToggle,
          ),
          // 菜单（Mix 歌單不會有多P視頻，但保留基本菜單）
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleMenuAction(context, ref, value),
            itemBuilder: (_) => _buildMenuItems(),
          ),
        ],
      ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() => [
    const PopupMenuItem(value: 'play_first', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('播放第一个分P'), contentPadding: EdgeInsets.zero)),
    const PopupMenuItem(value: 'add_all_to_queue', child: ListTile(leading: Icon(Icons.add_to_queue), title: Text('添加全部到队列'), contentPadding: EdgeInsets.zero)),
    const PopupMenuItem(value: 'download_all', child: ListTile(leading: Icon(Icons.download_outlined), title: Text('下载全部分P'), contentPadding: EdgeInsets.zero)),
    const PopupMenuItem(value: 'add_to_playlist', child: ListTile(leading: Icon(Icons.playlist_add), title: Text('添加到其他歌单'), contentPadding: EdgeInsets.zero)),
    if (!isImported)
      const PopupMenuItem(value: 'remove_all', child: ListTile(leading: Icon(Icons.remove_circle_outline), title: Text('从歌单移除全部'), contentPadding: EdgeInsets.zero)),
  ];

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'play_first':
        onPlayFirst();
        break;
      case 'add_all_to_queue':
        onAddAllToQueue();
        break;
      case 'download_all':
        // 检查路径配置
        final pathManager = ref.read(downloadPathManagerProvider);
        if (!await pathManager.hasConfiguredPath()) {
          if (!context.mounted) return;
          final configured = await DownloadPathSetupDialog.show(context);
          if (configured != true) return;
        }

        // 下载所有分P（批量添加后统一触发调度）
        final downloadService = ref.read(downloadServiceProvider);
        final state = ref.read(playlistDetailProvider(playlistId));
        final playlist = state.playlist;
        if (playlist == null) return;

        int addedCount = 0;
        for (final track in group.tracks) {
          final result = await downloadService.addTrackDownload(
            track,
            fromPlaylist: playlist,
            skipSchedule: true,  // 批量添加时跳过调度
          );
          if (result == DownloadResult.created) addedCount++;
        }
        // 所有任务添加完成后统一触发调度
        if (addedCount > 0) {
          downloadService.triggerSchedule();
          if (context.mounted) {
            ToastService.showWithAction(
              context,
              '已添加 $addedCount 个分P到下载队列',
              actionLabel: '查看',
              onAction: () => context.pushNamed(RouteNames.downloadManager),
            );
          }
        }
        break;
      case 'add_to_playlist':
        // 添加所有分P到其他歌单
        showAddToPlaylistDialog(context: context, tracks: group.tracks);
        break;
      case 'remove_all':
        // 移除所有分P
        final notifier = ref.read(playlistDetailProvider(playlistId).notifier);
        final trackIds = group.tracks.map((t) => t.id).toList();
        await notifier.removeTracks(trackIds);
        if (context.mounted) {
          ToastService.show(context, '已从歌单移除 ${group.tracks.length} 个分P');
        }
        break;
    }
  }
}

/// 歌曲列表项
class _TrackListTile extends ConsumerWidget {
  final Track track;
  final int playlistId;
  final String playlistName;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isPartOfMultiPage;
  final bool indent;
  final bool isImported;
  final bool isMix;
  final bool isSelectionMode;
  final bool isSelected;

  const _TrackListTile({
    required this.track,
    required this.playlistId,
    required this.playlistName,
    required this.onTap,
    this.onLongPress,
    required this.isPartOfMultiPage,
    required this.isImported,
    this.indent = false,
    this.isMix = false,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    // 使用 sourceId + pageNum 比较，因为临时播放的 track 可能没有数据库 ID
    final isPlaying = currentTrack != null &&
        currentTrack.sourceId == track.sourceId &&
        currentTrack.pageNum == track.pageNum;

    return ContextMenuRegion(
      menuBuilder: isMix ? (_) => [] : (_) => _buildMenuItems(),
      onSelected: (value) => _handleMenuAction(context, ref, value),
      child: Padding(
      padding: EdgeInsets.only(left: indent ? 56 : 0),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
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
                      borderRadius: BorderRadius.circular(4),
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
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      track.artist ?? '未知艺术家',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 检查歌曲是否已下载到本歌单（使用 playlist-specific 检查）
                  if (track.isDownloadedForPlaylist(playlistId, playlistName: playlistName))
                    Icon(
                      Icons.download_done,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                ],
              ),
        trailing: isSelectionMode
            ? _SelectionCheckbox(
                isSelected: isSelected,
                onTap: onTap,
              )
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 分P子项目单独显示下载状态（主项目在 subtitle 显示）
            if (isPartOfMultiPage && track.isDownloadedForPlaylist(playlistId, playlistName: playlistName))
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.download_done,
                  size: 14,
                  color: colorScheme.primary,
                ),
              ),
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
            // Mix 歌單不顯示菜單（所有操作都不支持）
            if (!isMix)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (value) => _handleMenuAction(context, ref, value),
                itemBuilder: (_) => _buildMenuItems(),
              ),
          ],
        ),
      ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() => [
    const PopupMenuItem(value: 'play_next', child: ListTile(leading: Icon(Icons.queue_play_next), title: Text('下一首播放'), contentPadding: EdgeInsets.zero)),
    const PopupMenuItem(value: 'add_to_queue', child: ListTile(leading: Icon(Icons.add_to_queue), title: Text('添加到队列'), contentPadding: EdgeInsets.zero)),
    const PopupMenuItem(value: 'download', child: ListTile(leading: Icon(Icons.download_outlined), title: Text('下载'), contentPadding: EdgeInsets.zero)),
    if (!isPartOfMultiPage)
      const PopupMenuItem(value: 'add_to_playlist', child: ListTile(leading: Icon(Icons.playlist_add), title: Text('添加到歌单'), contentPadding: EdgeInsets.zero)),
    if (!isImported)
      const PopupMenuItem(value: 'remove', child: ListTile(leading: Icon(Icons.remove_circle_outline), title: Text('从歌单移除'), contentPadding: EdgeInsets.zero)),
  ];

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'play_next':
        final addedNext = await ref.read(audioControllerProvider.notifier).addNext(track);
        if (addedNext && context.mounted) {
          ToastService.show(context, '已添加到下一首');
        }
        break;
      case 'add_to_queue':
        final addedToQueue = await ref.read(audioControllerProvider.notifier).addToQueue(track);
        if (addedToQueue && context.mounted) {
          ToastService.show(context, '已添加到播放队列');
        }
        break;
      case 'download':
        // 检查路径配置
        final pathManager = ref.read(downloadPathManagerProvider);
        if (!await pathManager.hasConfiguredPath()) {
          if (!context.mounted) return;
          final configured = await DownloadPathSetupDialog.show(context);
          if (configured != true) return;
        }

        final downloadService = ref.read(downloadServiceProvider);
        final state = ref.read(playlistDetailProvider(playlistId));
        final playlist = state.playlist;
        if (playlist == null) return;

        final result = await downloadService.addTrackDownload(
          track,
          fromPlaylist: playlist,
        );
        if (context.mounted) {
          switch (result) {
            case DownloadResult.created:
              ToastService.showWithAction(
                context,
                '已添加到下载队列',
                actionLabel: '查看',
                onAction: () => context.pushNamed(RouteNames.downloadManager),
              );
            case DownloadResult.alreadyDownloaded:
              ToastService.show(context, '歌曲已下载');
            case DownloadResult.taskExists:
              ToastService.showWithAction(
                context,
                '下载任务已存在',
                actionLabel: '查看',
                onAction: () => context.pushNamed(RouteNames.downloadManager),
              );
          }
        }
        break;
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, track: track);
        break;
      case 'remove':
        await ref
            .read(playlistDetailProvider(playlistId).notifier)
            .removeTrack(track.id);
        if (context.mounted) {
          ToastService.show(context, '已从歌单移除');
        }
        break;
    }
  }
}

/// 圓形選擇勾選框
class _SelectionCheckbox extends StatelessWidget {
  final bool isSelected;
  final VoidCallback? onTap;

  const _SelectionCheckbox({
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isSelected ? colorScheme.primary : colorScheme.outline,
      ),
      onPressed: onTap,
    );
  }
}

/// 組選擇勾選框（支持部分選擇狀態）
class _SelectionGroupCheckbox extends StatelessWidget {
  final bool isFullySelected;
  final bool isPartiallySelected;
  final VoidCallback? onTap;

  const _SelectionGroupCheckbox({
    required this.isFullySelected,
    required this.isPartiallySelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final IconData icon;
    final Color color;

    if (isFullySelected) {
      icon = Icons.check_circle;
      color = colorScheme.primary;
    } else if (isPartiallySelected) {
      icon = Icons.remove_circle_outline;
      color = colorScheme.primary;
    } else {
      icon = Icons.radio_button_unchecked;
      color = colorScheme.outline;
    }

    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: onTap,
    );
  }
}
