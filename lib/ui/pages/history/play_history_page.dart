import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../core/services/toast_service.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../data/models/play_history.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/play_history_repository.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/play_history_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
import '../../widgets/context_menu_region.dart';
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

  /// 已收起的日期分組
  final Set<DateTime> _collapsedGroups = {};

  void _toggleGroupCollapse(DateTime date) {
    setState(() {
      if (_collapsedGroups.contains(date)) {
        _collapsedGroups.remove(date);
      } else {
        _collapsedGroups.add(date);
      }
    });
  }

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
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    PlayHistoryPageState pageState,
    PlayHistoryPageNotifier notifier,
  ) {
    // 多选模式的 AppBar
    if (pageState.isMultiSelectMode) {
      final grouped = ref.read(groupedPlayHistoryProvider).valueOrNull;
      final allHistories = grouped?.values.expand((e) => e).toList() ?? [];
      final isAllSelected =
          pageState.selectedIds.length == allHistories.length &&
              allHistories.isNotEmpty;
      final hasSelection = pageState.selectedIds.isNotEmpty;

      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: t.playHistoryPage.exitSelectMode,
          onPressed: () => notifier.exitMultiSelectMode(),
        ),
        title: Text(t.playHistoryPage.selectedCount(n: pageState.selectedIds.length)),
        actions: [
          // 全選按鈕（圖標）
          IconButton(
            icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all),
            tooltip: isAllSelected ? t.playHistoryPage.deselectAll : t.playHistoryPage.selectAll,
            onPressed: () {
              if (isAllSelected) {
                notifier.deselectAll();
              } else {
                notifier.selectAll(allHistories);
              }
            },
          ),
          // 更多操作菜單
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            enabled: hasSelection,
            onSelected: (value) => _handleMultiSelectMenuAction(context, value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'add_to_queue',
                child: ListTile(
                  leading: const Icon(Icons.add_to_queue),
                  title: Text(t.playHistoryPage.addToQueue),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'play_next',
                child: ListTile(
                  leading: const Icon(Icons.queue_play_next),
                  title: Text(t.playHistoryPage.playNext),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'add_to_playlist',
                child: ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: Text(t.playHistoryPage.addToPlaylist),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error),
                  title: Text(t.playHistoryPage.deleteRecord,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
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
            hintText: t.playHistoryPage.searchHint,
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
          : Text(t.playHistoryPage.title),
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
          tooltip: t.playHistoryPage.selectDate,
          onPressed: () => _showDatePicker(context, notifier),
        ),
        // 搜索按钮
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: t.playHistoryPage.search,
          onPressed: () => notifier.setSearching(true),
        ),
        // 更多菜单
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) => _handleAppBarMenuAction(context, value),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'clear_all',
              child: ListTile(
                leading: const Icon(Icons.delete_sweep),
                title: Text(t.playHistoryPage.clearAllHistory),
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
            _buildStatItem(
                context, t.playHistoryPage.statsToday, stats.todayCount, stats.formattedTodayDuration),
            _buildStatDivider(colorScheme),
            _buildStatItem(
                context, t.playHistoryPage.statsThisWeek, stats.weekCount, stats.formattedWeekDuration),
            _buildStatDivider(colorScheme),
            _buildStatItem(
                context, t.playHistoryPage.statsAll, stats.totalCount, stats.formattedTotalDuration),
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

  Widget _buildStatItem(
      BuildContext context, String label, int count, String duration) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
            children: [
              TextSpan(text: label),
              const TextSpan(text: ' '),
              TextSpan(
                text: '$count',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              TextSpan(text: ' ${t.playHistoryPage.trackCount(n: count).replaceFirst('$count ', '')}'),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          duration,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colorScheme.outline),
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
                    label: Text(t.playHistoryPage.filterAll),
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
              PopupMenuItem(
                value: HistorySortOrder.timeDesc,
                child: Text(t.playHistoryPage.sortTimeDesc),
              ),
              PopupMenuItem(
                value: HistorySortOrder.timeAsc,
                child: Text(t.playHistoryPage.sortTimeAsc),
              ),
              PopupMenuItem(
                value: HistorySortOrder.playCount,
                child: Text(t.playHistoryPage.sortPlayCount),
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
      skipLoadingOnReload: true,
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
                  t.playHistoryPage.noRecords,
                  style: TextStyle(color: colorScheme.outline),
                ),
              ],
            ),
          );
        }

        // 按日期排序（最新的在前）
        final sortedDates = grouped.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        final pageState = ref.watch(playHistoryPageProvider);
        final notifier = ref.read(playHistoryPageProvider.notifier);

        return ListView.builder(
          controller: _scrollController,
          itemCount: sortedDates.length,
          itemBuilder: (context, index) {
            final date = sortedDates[index];
            final histories = grouped[date]!;
            return _buildDateGroup(
                context, date, histories, pageState, notifier);
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
            Text(t.playHistoryPage.loadFailed(error: e.toString())),
          ],
        ),
      ),
    );
  }

  Widget _buildDateGroup(
    BuildContext context,
    DateTime date,
    List<PlayHistory> histories,
    PlayHistoryPageState pageState,
    PlayHistoryPageNotifier notifier,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCollapsed = _collapsedGroups.contains(date);

    // 計算分組選擇狀態
    final groupIds = histories.map((h) => h.id).toSet();
    final selectedInGroup = pageState.selectedIds.intersection(groupIds);
    final isGroupFullySelected = selectedInGroup.length == histories.length;
    final isGroupPartiallySelected =
        selectedInGroup.isNotEmpty && !isGroupFullySelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 日期标题（可點擊）
        InkWell(
          onTap: () => _toggleGroupCollapse(date),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                // 多選模式下的分組勾選框
                if (pageState.isMultiSelectMode) ...[
                  _GroupSelectionCheckbox(
                    isFullySelected: isGroupFullySelected,
                    isPartiallySelected: isGroupPartiallySelected,
                    onTap: () => _toggleGroupSelection(
                        notifier, histories, isGroupFullySelected),
                  ),
                  const SizedBox(width: 8),
                ],
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
                // 日期文字
                Text(
                  _formatDateLabel(date),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 8),
                Text(
                  t.playHistoryPage.trackCount(n: histories.length),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
                const Spacer(),
                // 展開/收起圖標
                Icon(
                  isCollapsed ? Icons.expand_more : Icons.expand_less,
                  color: colorScheme.outline,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        // 该日期下的歌曲列表（可收起）
        if (!isCollapsed)
          ...histories.map((history) => _buildTimelineItem(
                context,
                history,
                isMultiSelectMode: pageState.isMultiSelectMode,
                isSelected: pageState.selectedIds.contains(history.id),
                onToggleSelection: () => notifier.toggleSelection(history.id),
                onEnterMultiSelect: () =>
                    notifier.enterMultiSelectMode(history.id),
              )),
      ],
    );
  }

  /// 切換分組選擇狀態
  void _toggleGroupSelection(
    PlayHistoryPageNotifier notifier,
    List<PlayHistory> histories,
    bool isCurrentlyFullySelected,
  ) {
    if (isCurrentlyFullySelected) {
      // 取消選擇該分組的所有項目
      for (final history in histories) {
        if (ref
            .read(playHistoryPageProvider)
            .selectedIds
            .contains(history.id)) {
          notifier.toggleSelection(history.id);
        }
      }
    } else {
      // 選擇該分組的所有項目
      for (final history in histories) {
        if (!ref
            .read(playHistoryPageProvider)
            .selectedIds
            .contains(history.id)) {
          notifier.toggleSelection(history.id);
        }
      }
    }
  }

  Widget _buildTimelineItem(
    BuildContext context,
    PlayHistory history, {
    required bool isMultiSelectMode,
    required bool isSelected,
    required VoidCallback onToggleSelection,
    required VoidCallback onEnterMultiSelect,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);

    // 判断是否正在播放
    final isPlaying = currentTrack != null &&
        currentTrack.sourceId == history.sourceId &&
        (history.cid == null || currentTrack.cid == history.cid);

    return ContextMenuRegion(
      menuBuilder: (_) => _buildHistoryItemMenuItems(),
      onSelected: (value) =>
          _handleItemMenuAction(context, ref, history, value),
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
          // 内容（使用 ListTile 樣式，與搜索頁一致）
          Expanded(
            child: ListTile(
              onTap: () {
                if (isMultiSelectMode) {
                  onToggleSelection();
                } else {
                  final track = history.toTrack();
                  ref
                      .read(audioControllerProvider.notifier)
                      .playTemporary(track);
                }
              },
              onLongPress: () {
                if (!isMultiSelectMode) {
                  onEnterMultiSelect();
                }
              },
              leading: TrackThumbnail(
                track: history.toTrack(),
                size: 48,
                borderRadius: 4,
                isPlaying: isPlaying,
              ),
              title: Text(
                history.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isPlaying ? colorScheme.primary : null,
                  fontWeight: isPlaying ? FontWeight.w600 : null,
                ),
              ),
              subtitle: Row(
                children: [
                  Flexible(
                    child: Text(
                      history.artist ?? t.general.unknownArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 播放時間（帶時鐘圖標）
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _formatPlayedTime(history.playedAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                  ),
                  const SizedBox(width: 8),
                  // 音源標識
                  Icon(
                    history.sourceType == SourceType.bilibili
                        ? SimpleIcons.bilibili
                        : SimpleIcons.youtube,
                    size: 14,
                    color: colorScheme.outline,
                  ),
                ],
              ),
              trailing: _buildTrailing(context, history, isMultiSelectMode,
                  isSelected, onToggleSelection),
            ),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildHistoryItemMenuItems() => [
        PopupMenuItem(
          value: 'play',
          child: ListTile(
            leading: const Icon(Icons.play_arrow),
            title: Text(t.playHistoryPage.play),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'play_next',
          child: ListTile(
            leading: const Icon(Icons.queue_play_next),
            title: Text(t.playHistoryPage.playNext),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'add_to_queue',
          child: ListTile(
            leading: const Icon(Icons.add_to_queue),
            title: Text(t.playHistoryPage.addToQueue),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'add_to_playlist',
          child: ListTile(
            leading: const Icon(Icons.playlist_add),
            title: Text(t.playHistoryPage.addToPlaylist),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(t.playHistoryPage.deleteThisRecord),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'delete_all',
          child: ListTile(
            leading: const Icon(Icons.delete_sweep),
            title: Text(t.playHistoryPage.deleteAllForTrack),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ];

  Widget _buildTrailing(
    BuildContext context,
    PlayHistory history,
    bool isMultiSelectMode,
    bool isSelected,
    VoidCallback onToggleSelection,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 時長
        if (history.durationMs != null)
          SizedBox(
            width: 48,
            child: Text(
              DurationFormatter.formatMs(history.durationMs!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        // 選擇勾選框或菜單
        if (isMultiSelectMode)
          _SelectionCheckbox(
            isSelected: isSelected,
            onTap: onToggleSelection,
          )
        else
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) =>
                _handleItemMenuAction(context, ref, history, value),
            itemBuilder: (_) => _buildHistoryItemMenuItems(),
          ),
      ],
    );
  }

  Widget _buildMultiSelectList(BuildContext context) {
    // 多选模式使用相同的列表，但禁用菜单
    return _buildTimelineList(context);
  }

  // === Helper methods ===

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) {
      return t.playHistoryPage.dateToday;
    } else if (date == yesterday) {
      return t.playHistoryPage.dateYesterday;
    } else if (date.year == now.year) {
      return t.playHistoryPage.dateFormat(month: '${date.month}', day: '${date.day}');
    } else {
      return t.playHistoryPage.dateFormatWithYear(year: '${date.year}', month: '${date.month}', day: '${date.day}');
    }
  }

  String _formatDateTitle(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year) {
      return t.playHistoryPage.dateFormat(month: '${date.month}', day: '${date.day}');
    }
    return t.playHistoryPage.dateFormatWithYear(year: '${date.year}', month: '${date.month}', day: '${date.day}');
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
      return t.playHistoryPage.dateTimeFormat(month: '${time.month}', day: '${time.day}', time: timeStr);
    } else {
      return t.playHistoryPage.dateFormatWithYear(year: '${time.year}', month: '${time.month}', day: '${time.day}');
    }
  }

  String _getSortOrderLabel(HistorySortOrder order) {
    switch (order) {
      case HistorySortOrder.timeDesc:
        return t.playHistoryPage.sortTimeDesc;
      case HistorySortOrder.timeAsc:
        return t.playHistoryPage.sortTimeAsc;
      case HistorySortOrder.playCount:
        return t.playHistoryPage.sortPlayCount;
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
      helpText: t.playHistoryPage.selectDateHelp,
    );
    if (date != null) {
      notifier.setSelectedDate(date);
    }
  }

  /// 處理多選菜單操作
  Future<void> _handleMultiSelectMenuAction(
      BuildContext context, String action) async {
    switch (action) {
      case 'add_to_queue':
        await _addSelectedToQueue(context);
        break;
      case 'play_next':
        await _playNextSelected(context);
        break;
      case 'add_to_playlist':
        await _addSelectedToPlaylist(context);
        break;
      case 'delete':
        await _deleteSelected(
            context, ref.read(playHistoryPageProvider.notifier));
        break;
    }
  }

  /// 下一首播放選中的歌曲
  Future<void> _playNextSelected(BuildContext context) async {
    final pageState = ref.read(playHistoryPageProvider);
    final grouped = ref.read(groupedPlayHistoryProvider).valueOrNull;
    if (grouped == null) return;

    final allHistories = grouped.values.expand((e) => e).toList();
    final selectedHistories = allHistories
        .where((h) => pageState.selectedIds.contains(h.id))
        .toList();

    final controller = ref.read(audioControllerProvider.notifier);
    int addedCount = 0;
    for (final history in selectedHistories.reversed) {
      final added = await controller.addNext(history.toTrack());
      if (added) addedCount++;
    }

    ref.read(playHistoryPageProvider.notifier).exitMultiSelectMode();

    if (context.mounted) {
      ToastService.success(context, t.playHistoryPage.toastAddedNextCount(n: addedCount));
    }
  }

  void _handleAppBarMenuAction(BuildContext context, String action) async {
    switch (action) {
      case 'clear_all':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.playHistoryPage.clearAllHistory),
            content: Text(t.playHistoryPage.clearAllConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.general.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.playHistoryPage.clearButton),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await ref.read(playHistoryActionsProvider).clearAll();
          if (context.mounted) {
            ToastService.success(context, t.playHistoryPage.toastCleared);
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
          ToastService.success(context, t.playHistoryPage.toastAddedToNext);
        }
        break;
      case 'add_to_queue':
        final added = await controller.addToQueue(track);
        if (added && context.mounted) {
          ToastService.success(context, t.playHistoryPage.toastAddedToQueue);
        }
        break;
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, track: track);
        break;
      case 'delete':
        await ref.read(playHistoryActionsProvider).delete(history.id);
        if (context.mounted) {
          ToastService.success(context, t.playHistoryPage.toastDeletedRecord);
        }
        break;
      case 'delete_all':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.playHistoryPage.deleteAllTitle),
            content: Text(t.playHistoryPage.deleteAllConfirm(title: history.title)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.general.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.playHistoryPage.deleteButton),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          final count = await ref
              .read(playHistoryPageProvider.notifier)
              .deleteAllForTrack(history.trackKey);
          if (context.mounted) {
            ToastService.success(context, t.playHistoryPage.toastDeletedCount(n: count));
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
      ToastService.success(context, t.playHistoryPage.toastDeletedCount(n: count));
    }
  }

  Future<void> _addSelectedToQueue(BuildContext context) async {
    final pageState = ref.read(playHistoryPageProvider);
    final grouped = ref.read(groupedPlayHistoryProvider).valueOrNull;
    if (grouped == null) return;

    final allHistories = grouped.values.expand((e) => e).toList();
    final selectedHistories = allHistories
        .where((h) => pageState.selectedIds.contains(h.id))
        .toList();

    final controller = ref.read(audioControllerProvider.notifier);
    int addedCount = 0;
    for (final history in selectedHistories) {
      final added = await controller.addToQueue(history.toTrack());
      if (added) addedCount++;
    }

    ref.read(playHistoryPageProvider.notifier).exitMultiSelectMode();

    if (context.mounted) {
      ToastService.success(context, t.playHistoryPage.toastAddedQueueCount(n: addedCount));
    }
  }

  Future<void> _addSelectedToPlaylist(BuildContext context) async {
    final pageState = ref.read(playHistoryPageProvider);
    final grouped = ref.read(groupedPlayHistoryProvider).valueOrNull;
    if (grouped == null) return;

    final allHistories = grouped.values.expand((e) => e).toList();
    final selectedHistories = allHistories
        .where((h) => pageState.selectedIds.contains(h.id))
        .toList();

    final tracks = selectedHistories.map((h) => h.toTrack()).toList();

    ref.read(playHistoryPageProvider.notifier).exitMultiSelectMode();

    if (tracks.length == 1) {
      showAddToPlaylistDialog(context: context, track: tracks.first);
    } else {
      showAddToPlaylistDialog(context: context, tracks: tracks);
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

/// 分組選擇勾選框（支持三態：未選、部分選、全選）
class _GroupSelectionCheckbox extends StatelessWidget {
  final bool isFullySelected;
  final bool isPartiallySelected;
  final VoidCallback? onTap;

  const _GroupSelectionCheckbox({
    required this.isFullySelected,
    required this.isPartiallySelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    IconData icon;
    Color color;

    if (isFullySelected) {
      icon = Icons.check_circle;
      color = colorScheme.primary;
    } else if (isPartiallySelected) {
      icon = Icons.remove_circle;
      color = colorScheme.primary;
    } else {
      icon = Icons.radio_button_unchecked;
      color = colorScheme.outline;
    }

    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: color, size: 24),
    );
  }
}
