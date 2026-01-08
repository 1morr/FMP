import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/models/track.dart';
import '../../../providers/search_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';

/// 搜索页
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  bool _showHistory = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    setState(() {
      _showHistory = _searchController.text.isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);

    return Scaffold(
      appBar: AppBar(
        title: _buildSearchField(context),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchController.clear();
                ref.read(searchProvider.notifier).clear();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // 音源筛选
          _buildSourceFilter(context, searchState),

          // 内容区域
          Expanded(
            child: _showHistory && searchState.query.isEmpty
                ? _buildSearchHistory(context)
                : _buildSearchResults(context, searchState),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _searchController,
      focusNode: _focusNode,
      decoration: const InputDecoration(
        hintText: '搜索歌曲、艺术家...',
        border: InputBorder.none,
        prefixIcon: Icon(Icons.search),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: _performSearch,
    );
  }

  Widget _buildSourceFilter(BuildContext context, SearchState state) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            '音源:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
          const SizedBox(width: 8),
          _buildSourceChip(
            context,
            SourceType.bilibili,
            'Bilibili',
            state.enabledSources.contains(SourceType.bilibili),
          ),
          // 可以添加更多音源
        ],
      ),
    );
  }

  Widget _buildSourceChip(
    BuildContext context,
    SourceType sourceType,
    String label,
    bool isSelected,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          ref.read(searchProvider.notifier).toggleSource(sourceType);
        },
      ),
    );
  }

  Widget _buildSearchHistory(BuildContext context) {
    final history = ref.watch(searchHistoryManagerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '搜索你喜欢的音乐',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                '搜索历史',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref.read(searchHistoryManagerProvider.notifier).clearAll();
                },
                child: const Text('清空'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(item.query),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    ref
                        .read(searchHistoryManagerProvider.notifier)
                        .deleteItem(item.id);
                  },
                ),
                onTap: () {
                  _searchController.text = item.query;
                  _performSearch(item.query);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(BuildContext context, SearchState state) {
    if (state.isLoading && state.allOnlineTracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.allOnlineTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(state.error!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _performSearch(state.query),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // 本地结果
        if (state.localResults.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '本地 (${state.localResults.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _SearchResultTile(
                track: state.localResults[index],
                isLocal: true,
              ),
              childCount: state.localResults.length,
            ),
          ),
        ],

        // 在线结果（按音源分组）
        for (final entry in state.onlineResults.entries) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    '${_getSourceName(entry.key)} (${entry.value.totalCount})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  if (entry.value.hasMore)
                    TextButton(
                      onPressed: () {
                        ref.read(searchProvider.notifier).loadMore(entry.key);
                      },
                      child: const Text('加载更多'),
                    ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _SearchResultTile(
                track: entry.value.tracks[index],
                isLocal: false,
              ),
              childCount: entry.value.tracks.length,
            ),
          ),
        ],

        // 加载更多指示器
        if (state.isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),

        // 无结果
        if (!state.hasResults && !state.isLoading)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '未找到 "${state.query}" 相关结果',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _getSourceName(SourceType type) {
    switch (type) {
      case SourceType.bilibili:
        return 'Bilibili';
      case SourceType.youtube:
        return 'YouTube';
    }
  }

  void _performSearch(String query) {
    if (query.trim().isEmpty) return;
    _focusNode.unfocus();
    ref.read(searchProvider.notifier).search(query);
  }
}

/// 搜索结果列表项
class _SearchResultTile extends ConsumerWidget {
  final Track track;
  final bool isLocal;

  const _SearchResultTile({
    required this.track,
    required this.isLocal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 48,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: colorScheme.surfaceContainerHighest,
          ),
          clipBehavior: Clip.antiAlias,
          child: track.thumbnailUrl != null
              ? CachedNetworkImage(
                  imageUrl: track.thumbnailUrl!,
                  fit: BoxFit.cover,
                )
              : Icon(
                  Icons.music_note,
                  color: colorScheme.outline,
                ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          if (isLocal) ...[
            Icon(
              Icons.check_circle,
              size: 14,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              track.artist ?? '未知艺术家',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (track.viewCount != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.play_arrow,
              size: 14,
              color: colorScheme.outline,
            ),
            const SizedBox(width: 2),
            Text(
              _formatViewCount(track.viewCount!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (track.durationMs != null)
            Text(
              _formatDuration(track.durationMs!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleMenuAction(context, ref, value),
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
                  title: Text('添加到队列'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'add_to_playlist',
                child: ListTile(
                  leading: Icon(Icons.playlist_add),
                  title: Text('添加到歌单'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () => _handleMenuAction(context, ref, 'play'),
    );
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatViewCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    } else if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    } else {
      return count.toString();
    }
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) {
    switch (action) {
      case 'play':
        ref.read(audioControllerProvider.notifier).playTemporary(track);
        break;
      case 'play_next':
        ref.read(audioControllerProvider.notifier).addNext(track);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到下一首')),
        );
        break;
      case 'add_to_queue':
        ref.read(audioControllerProvider.notifier).addToQueue(track);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到播放队列')),
        );
        break;
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, track: track);
        break;
    }
  }
}
