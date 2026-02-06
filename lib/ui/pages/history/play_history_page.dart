import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../core/services/toast_service.dart';
import '../../../data/models/play_history.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/play_history_repository.dart';
import '../../../providers/play_history_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
import '../../widgets/track_thumbnail.dart';

/// 播放历史页面
class PlayHistoryPage extends ConsumerStatefulWidget {
  const PlayHistoryPage({super.key});

  @override
  ConsumerState<PlayHistoryPage> createState() => _PlayHistoryPageState();
}

class _PlayHistoryPageState extends ConsumerState<PlayHistoryPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageState = ref.watch(playHistoryPageProvider);
    final notifier = ref.read(playHistoryPageProvider.notifier);

    return Scaffold(
      appBar: _buildAppBar(context, pageState, notifier),
      body: Column(
        children: [
          // 统计卡片
          _buildStatsCard(context),
          // 筛选和排序栏
          _buildFilterBar(context, pageState, notifier),
          // 历史列表
          Expanded(
            child: pageState.isMultiSelectMode
                ? _buildMultiSelectList(context)
                : _buildTimelineList(context),
          ),
        ],
      ),
      // 多选模式下的底部操作栏
      bottomNavigationBar: pageState.isMultiSelectMode
          ? _buildMultiSelectBottomBar(context, pageState, notifier)
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    PlayHistoryPageState pageState,
    PlayHistoryPageNotifier notifier,
  ) {
    // 多选模式的 AppBar
    if (pageState.isMultiSelectMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => notifier.exitMultiSelectMode(),
        ),
        title: Text('已選擇 ${pageState.selectedIds.length} 項'),
        actions: [
          TextButton(
            onPressed: () {
              final grouped = ref.read(groupedPlayHistoryProvider).valueOrNull;
              if (grouped != null) {
                final allHistories = grouped.values.expand((e) => e).toList();
                notifier.selectAll(allHistories);
              }
            },
            child: const Text('全選'),
          ),
        ],
      );
    }

    // 搜索模式的 AppBar
    if (pageState.isSearching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            notifier.setSearching(false);
            _searchController.clear();
          },
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '搜索標題或藝術家...',
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      notifier.setSearchKeyword(null);
                    },
                  )
                : null,
          ),
          onChanged: (value) => notifier.setSearchKeyword(value),
        ),
      );
    }

    // 正常模式的 AppBar
    return AppBar(
      title: pageState.selectedDate != null
          ? Text(_formatDateTitle(pageState.selectedDate!))
          : const Text('播放歷史'),
      leading: pageState.selectedDate != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => notifier.setSelectedDate(null),
            )
          : null,
      actions: [
        // 日历按钮
        IconButton(
          icon: const Icon(Icons.calendar_today),
          tooltip: '選擇日期',
          onPressed: () => _showDatePicker(context, notifier),
        ),
        // 搜索按钮
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: '搜索',
          onPressed: () => notifier.setSearching(true),
        ),
        // 更多菜单
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) => _handleAppBarMenuAction(context, value),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'clear_all',
              child: ListTile(
                leading: Icon(Icons.delete_sweep),
                title: Text('清空所有歷史'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statsAsync = ref.watch(playHistoryStatsProvider);

    return statsAsync.when(
      data: (stats) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStatItem(context, '今日', stats.todayCount, stats.formattedTodayDuration),
            _buildStatDivider(colorScheme),
            _buildStatItem(context, '本週', stats.weekCount, stats.formattedWeekDuration),
            _buildStatDivider(colorScheme),
            _buildStatItem(context, '全部', stats.totalCount, stats.formattedTotalDuration),
          ],
        ),
      ),
      loading: () => const SizedBox(height: 56),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatDivider(ColorScheme colorScheme) {
    return Container(width: 1, height: 32, color: colorScheme.outlineVariant);
  }

  Widget _buildStatItem(BuildContext context, String label, int count, String duration) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            children: [
              TextSpan(text: label),
              const TextSpan(text: ' '),
              TextSpan(
                text: '$count',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              const TextSpan(text: ' 首'),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          duration,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
        ),
      ],
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    PlayHistoryPageState pageState,
    PlayHistoryPageNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 单选筛选（可滚动）
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: pageState.selectedSource == null,
                    onSelected: (_) => notifier.setSource(null),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Bilibili'),
                    selected: pageState.selectedSource == SourceType.bilibili,
                    onSelected: (_) => notifier.setSource(SourceType.bilibili),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('YouTube'),
                    selected: pageState.selectedSource == SourceType.youtube,
                    onSelected: (_) => notifier.setSource(SourceType.youtube),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 排序下拉
          PopupMenuButton<HistorySortOrder>(
            initialValue: pageState.sortOrder,
            onSelected: (order) => notifier.setSortOrder(order),
            child: Chip(
              avatar: const Icon(Icons.sort, size: 18),
              label: Text(_getSortOrderLabel(pageState.sortOrder)),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: HistorySortOrder.timeDesc,
                child: Text('時間倒序'),
              ),
              const PopupMenuItem(
                value: HistorySortOrder.timeAsc,
                child: Text('時間正序'),
              ),
              const PopupMenuItem(
                value: HistorySortOrder.playCount,
                child: Text('播放次數'),
              ),
              const PopupMenuItem(
                value: HistorySortOrder.duration,
                child: Text('歌曲時長'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineList(BuildContext context) {
    final groupedAsync = ref.watch(groupedPlayHistoryProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return groupedAsync.when(
      data: (grouped) {
        if (grouped.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: 64,
                  color: colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  '暫無播放記錄',
                  style: TextStyle(color: colorScheme.outline),
                ),
              ],
            ),
          );
        }

        // 按日期排序（最新的在前）
        final sortedDates = grouped.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        return ListView.builder(
          controller: _scrollController,
          itemCount: sortedDates.length,
          itemBuilder: (context, index) {
            final date = sortedDates[index];
            final histories = grouped[date]!;
            return _buildDateGroup(context, date, histories);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('載入失敗: $e'),
          ],
        ),
      ),
    );
  }

  Widget _buildDateGroup(
    BuildContext context,
    DateTime date,
    List<PlayHistory> histories,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 日期标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              // 时间轴圆点
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatDateLabel(date),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(width: 8),
              Text(
                '${histories.length} 首',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
        // 该日期下的歌曲列表
        ...histories.map((history) => _buildTimelineItem(context, history)),
      ],
    );
  }

  Widget _buildTimelineItem(BuildContext context, PlayHistory history) {
    final colorScheme = Theme.of(context).colorScheme;
    final pageState = ref.watch(playHistoryPageProvider);
    final notifier = ref.read(playHistoryPageProvider.notifier);
    final currentTrack = ref.watch(currentTrackProvider);
    
    // 判断是否正在播放
    final isPlaying = currentTrack != null &&
        currentTrack.sourceId == history.sourceId &&
        (history.cid == null || currentTrack.cid == history.cid);

    return InkWell(
      onTap: () {
        if (pageState.isMultiSelectMode) {
          notifier.toggleSelection(history.id);
        } else {
          // 临时播放
          final track = history.toTrack();
          ref.read(audioControllerProvider.notifier).playTemporary(track);
        }
      },
      onLongPress: () {
        if (!pageState.isMultiSelectMode) {
          notifier.enterMultiSelectMode(history.id);
        }
      },
      child: Row(
        children: [
          // 时间轴竖线
          SizedBox(
            width: 40,
            child: Center(
              child: Container(
                width: 2,
                height: 72,
                color: colorScheme.outlineVariant,
              ),
            ),
          ),
          // 内容
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Row(
                children: [
                  // 多选模式下的复选框
                  if (pageState.isMultiSelectMode)
                    Checkbox(
                      value: pageState.selectedIds.contains(history.id),
                      onChanged: (_) => notifier.toggleSelection(history.id),
                    ),
                  // 封面
                  TrackThumbnail(
                    track: history.toTrack(),
                    size: 48,
                    borderRadius: 4,
                    isPlaying: isPlaying,
                  ),
                  const SizedBox(width: 12),
                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          history.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPlaying ? colorScheme.primary : null,
                            fontWeight: isPlaying ? FontWeight.w600 : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            // 音源图标（与搜索页一致）
                            Icon(
                              history.sourceType == SourceType.bilibili
                                  ? SimpleIcons.bilibili
                                  : SimpleIcons.youtube,
                              size: 14,
                              color: colorScheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                history.artist ?? '未知藝術家',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.outline,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatPlayedTime(history.playedAt),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.outline,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 操作菜单
                  if (!pageState.isMultiSelectMode)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) =>
                          _handleItemMenuAction(context, ref, history, value),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'play',
                          child: ListTile(
                            leading: Icon(Icons.play_arrow),
                            title: Text('播放'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'play_next',
                          child: ListTile(
                            leading: Icon(Icons.queue_play_next),
                            title: Text('下一首播放'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'add_to_queue',
                          child: ListTile(
                            leading: Icon(Icons.add_to_queue),
                            title: Text('添加到隊列'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'add_to_playlist',
                          child: ListTile(
                            leading: Icon(Icons.playlist_add),
                            title: Text('添加到歌單'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('刪除此記錄'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete_all',
                          child: ListTile(
                            leading: Icon(Icons.delete_sweep),
                            title: Text('刪除此歌所有記錄'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiSelectList(BuildContext context) {
    // 多选模式使用相同的列表，但禁用菜单
    return _buildTimelineList(context);
  }

  Widget _buildMultiSelectBottomBar(
    BuildContext context,
    PlayHistoryPageState pageState,
    PlayHistoryPageNotifier notifier,
  ) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 删除
            TextButton.icon(
              onPressed: pageState.selectedIds.isEmpty
                  ? null
                  : () => _deleteSelected(context, notifier),
              icon: const Icon(Icons.delete_outline),
              label: const Text('刪除'),
            ),
            // 添加到队列
            TextButton.icon(
              onPressed: pageState.selectedIds.isEmpty
                  ? null
                  : () => _addSelectedToQueue(context),
              icon: const Icon(Icons.add_to_queue),
              label: const Text('加入隊列'),
            ),
            // 添加到歌单
            TextButton.icon(
              onPressed: pageState.selectedIds.isEmpty
                  ? null
                  : () => _addSelectedToPlaylist(context),
              icon: const Icon(Icons.playlist_add),
              label: const Text('加入歌單'),
            ),
          ],
        ),
      ),
    );
  }

  // === Helper methods ===

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) {
      return '今天';
    } else if (date == yesterday) {
      return '昨天';
    } else if (date.year == now.year) {
      return '${date.month}月${date.day}日';
    } else {
      return '${date.year}年${date.month}月${date.day}日';
    }
  }

  String _formatDateTitle(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year) {
      return '${date.month}月${date.day}日';
    }
    return '${date.year}年${date.month}月${date.day}日';
  }

  String _formatPlayedTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final playedDate = DateTime(time.year, time.month, time.day);

    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    if (playedDate == today) {
      return timeStr;
    } else if (time.year == now.year) {
      return '${time.month}月${time.day}日 $timeStr';
    } else {
      return '${time.year}年${time.month}月${time.day}日';
    }
  }

  String _getSortOrderLabel(HistorySortOrder order) {
    switch (order) {
      case HistorySortOrder.timeDesc:
        return '時間倒序';
      case HistorySortOrder.timeAsc:
        return '時間正序';
      case HistorySortOrder.playCount:
        return '播放次數';
      case HistorySortOrder.duration:
        return '歌曲時長';
    }
  }

  Future<void> _showDatePicker(
    BuildContext context,
    PlayHistoryPageNotifier notifier,
  ) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: '選擇日期查看歷史',
    );
    if (date != null) {
      notifier.setSelectedDate(date);
    }
  }

  void _handleAppBarMenuAction(BuildContext context, String action) async {
    switch (action) {
      case 'clear_all':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('清空所有歷史'),
            content: const Text('確定要清空所有播放歷史記錄嗎？此操作無法撤銷。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清空'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await ref.read(playHistoryActionsProvider).clearAll();
          if (context.mounted) {
            ToastService.show(context, '已清空所有歷史');
          }
        }
        break;
    }
  }

  void _handleItemMenuAction(
    BuildContext context,
    WidgetRef ref,
    PlayHistory history,
    String action,
  ) async {
    final controller = ref.read(audioControllerProvider.notifier);
    final track = history.toTrack();

    switch (action) {
      case 'play':
        controller.playTemporary(track);
        break;
      case 'play_next':
        final added = await controller.addNext(track);
        if (added && context.mounted) {
          ToastService.show(context, '已添加到下一首');
        }
        break;
      case 'add_to_queue':
        final added = await controller.addToQueue(track);
        if (added && context.mounted) {
          ToastService.show(context, '已添加到播放隊列');
        }
        break;
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, track: track);
        break;
      case 'delete':
        await ref.read(playHistoryActionsProvider).delete(history.id);
        if (context.mounted) {
          ToastService.show(context, '已刪除記錄');
        }
        break;
      case 'delete_all':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('刪除所有記錄'),
            content: Text('確定要刪除「${history.title}」的所有播放記錄嗎？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('刪除'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          final count = await ref
              .read(playHistoryPageProvider.notifier)
              .deleteAllForTrack(history.trackKey);
          if (context.mounted) {
            ToastService.show(context, '已刪除 $count 條記錄');
          }
        }
        break;
    }
  }

  Future<void> _deleteSelected(
    BuildContext context,
    PlayHistoryPageNotifier notifier,
  ) async {
    final count = await notifier.deleteSelected();
    if (context.mounted) {
      ToastService.show(context, '已刪除 $count 條記錄');
    }
  }

  Future<void> _addSelectedToQueue(BuildContext context) async {
    final pageState = ref.read(playHistoryPageProvider);
    final grouped = ref.read(groupedPlayHistoryProvider).valueOrNull;
    if (grouped == null) return;

    final allHistories = grouped.values.expand((e) => e).toList();
    final selectedHistories =
        allHistories.where((h) => pageState.selectedIds.contains(h.id)).toList();

    final controller = ref.read(audioControllerProvider.notifier);
    int addedCount = 0;
    for (final history in selectedHistories) {
      final added = await controller.addToQueue(history.toTrack());
      if (added) addedCount++;
    }

    ref.read(playHistoryPageProvider.notifier).exitMultiSelectMode();

    if (context.mounted) {
      ToastService.show(context, '已添加 $addedCount 首到隊列');
    }
  }

  Future<void> _addSelectedToPlaylist(BuildContext context) async {
    final pageState = ref.read(playHistoryPageProvider);
    final grouped = ref.read(groupedPlayHistoryProvider).valueOrNull;
    if (grouped == null) return;

    final allHistories = grouped.values.expand((e) => e).toList();
    final selectedHistories =
        allHistories.where((h) => pageState.selectedIds.contains(h.id)).toList();

    final tracks = selectedHistories.map((h) => h.toTrack()).toList();

    ref.read(playHistoryPageProvider.notifier).exitMultiSelectMode();

    if (tracks.length == 1) {
      showAddToPlaylistDialog(context: context, track: tracks.first);
    } else {
      showAddToPlaylistDialog(context: context, tracks: tracks);
    }
  }
}
