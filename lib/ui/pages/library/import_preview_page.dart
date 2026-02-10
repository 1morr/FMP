import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../core/services/toast_service.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../data/models/track.dart';
import '../../../data/sources/playlist_import/playlist_import_source.dart';
import '../../../providers/playlist_import_provider.dart';
import '../../../providers/playlist_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../widgets/track_thumbnail.dart';

/// 显示导入预览弹窗
Future<void> showImportPreviewDialog(
  BuildContext context, {
  String? customName,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => ImportPreviewDialog(customName: customName),
  );
}

/// 导入预览弹窗
class ImportPreviewDialog extends ConsumerStatefulWidget {
  final String? customName;

  const ImportPreviewDialog({
    super.key,
    this.customName,
  });

  @override
  ConsumerState<ImportPreviewDialog> createState() =>
      _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends ConsumerState<ImportPreviewDialog> {
  final Set<int> _expandedIndices = {};
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playlistImportProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final playlistName =
        widget.customName ?? state.playlist?.name ?? '导入的歌单';

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 600,
          maxHeight: 700,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
              ),
              child: Row(
                children: [
                  Icon(Icons.playlist_add_check, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '导入预览',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          playlistName,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.outline,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),

            // 统计信息
            _buildStats(context, state),

            const Divider(height: 1),

            // 歌曲列表
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // 未匹配区域
                  if (state.unmatchedMatchedTracks.isNotEmpty)
                    _UnmatchedSection(
                      tracks: state.unmatchedMatchedTracks,
                    ),

                  // 已匹配列表
                  if (state.matchedCount > 0) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        '已匹配 (${state.matchedCount})',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: colorScheme.primary,
                            ),
                      ),
                    ),
                    ...state.matchedTracks.asMap().entries.map((entry) {
                      final index = entry.key;
                      final matched = entry.value;

                      if (matched.status == MatchStatus.noResult) {
                        return const SizedBox.shrink();
                      }

                      return _ImportMatchTile(
                        matchedTrack: matched,
                        isExpanded: _expandedIndices.contains(index),
                        onToggleExpand: () {
                          setState(() {
                            if (_expandedIndices.contains(index)) {
                              _expandedIndices.remove(index);
                            } else {
                              _expandedIndices.add(index);
                            }
                          });
                        },
                        onSelectAlternative: (track) {
                          ref
                              .read(playlistImportProvider.notifier)
                              .selectAlternative(index, track);
                        },
                        onToggleInclude: (isIncluded) {
                          ref
                              .read(playlistImportProvider.notifier)
                              .toggleInclude(index, isIncluded);
                        },
                      );
                    }),
                  ],
                ],
              ),
            ),

            const Divider(height: 1),

            // 底部按钮
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _isCreating || state.selectedTracks.isEmpty
                        ? null
                        : () => _createPlaylist(playlistName),
                    child: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('创建歌单 (${state.selectedTracks.length})'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(BuildContext context, PlaylistImportState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final playlist = state.playlist;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (playlist != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                playlist.source.displayName,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            '共 ${state.matchedTracks.length} 首',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
          const SizedBox(width: 8),
          Text('•', style: TextStyle(color: colorScheme.outline)),
          const SizedBox(width: 8),
          Text(
            '已匹配 ${state.matchedCount}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                ),
          ),
          if (state.unmatchedCount > 0) ...[
            const SizedBox(width: 8),
            Text('•', style: TextStyle(color: colorScheme.outline)),
            const SizedBox(width: 8),
            Text(
              '未匹配 ${state.unmatchedCount}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createPlaylist(String name) async {
    setState(() => _isCreating = true);

    try {
      final state = ref.read(playlistImportProvider);
      final tracks = state.selectedTracks;

      if (tracks.isEmpty) {
        ToastService.warning(context, '没有可导入的歌曲');
        return;
      }

      // 创建歌单
      final notifier = ref.read(playlistListProvider.notifier);
      final playlist = await notifier.createPlaylist(name: name);

      if (playlist == null) {
        throw Exception('创建歌单失败');
      }

      // 添加歌曲
      final service = ref.read(playlistServiceProvider);
      await service.addTracksToPlaylist(playlist.id, tracks);

      // 刷新歌单列表和详情
      ref.read(playlistListProvider.notifier).loadPlaylists();
      ref.invalidate(allPlaylistsProvider);
      ref.invalidate(playlistDetailProvider(playlist.id));
      ref.invalidate(playlistCoverProvider(playlist.id));

      if (mounted) {
        Navigator.pop(context);
        ToastService.success(
          context,
          '创建成功！添加了 ${tracks.length} 首歌曲',
        );
      }
    } catch (e) {
      if (mounted) {
        ToastService.error(context, '创建失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }
}

/// 未匹配歌曲区域 - 支持手动搜索
class _UnmatchedSection extends ConsumerStatefulWidget {
  final List<MatchedTrack> tracks;

  const _UnmatchedSection({required this.tracks});

  @override
  ConsumerState<_UnmatchedSection> createState() => _UnmatchedSectionState();
}

class _UnmatchedSectionState extends ConsumerState<_UnmatchedSection> {
  final Set<int> _expandedIndices = {};
  final Map<int, TextEditingController> _searchControllers = {};
  final Map<int, bool> _isSearching = {};
  final Map<int, List<Track>> _searchResults = {};

  @override
  void dispose() {
    for (final controller in _searchControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _performSearch(int index, MatchedTrack matchedTrack) async {
    final controller = _searchControllers[index];
    final query = controller?.text.trim() ?? '';
    if (query.isEmpty) return;

    setState(() {
      _isSearching[index] = true;
    });

    try {
      final notifier = ref.read(playlistImportProvider.notifier);
      final results = await notifier.searchForUnmatched(query);
      
      setState(() {
        _searchResults[index] = results;
        _isSearching[index] = false;
      });
    } catch (e) {
      setState(() {
        _searchResults[index] = [];
        _isSearching[index] = false;
      });
    }
  }

  void _selectTrack(int unmatchedIndex, Track selectedTrack) {
    final state = ref.read(playlistImportProvider);
    final originalTrack = widget.tracks[unmatchedIndex].original;
    
    int? realIndex;
    for (var i = 0; i < state.matchedTracks.length; i++) {
      final matched = state.matchedTracks[i];
      if (matched.original.title == originalTrack.title &&
          matched.original.artists.join(',') == originalTrack.artists.join(',')) {
        realIndex = i;
        break;
      }
    }

    if (realIndex != null) {
      ref.read(playlistImportProvider.notifier).updateWithManualMatch(
        realIndex,
        selectedTrack,
        _searchResults[unmatchedIndex] ?? [selectedTrack],
      );
      
      // 不再清除展开状态和搜索结果，让用户可以重新选择
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (widget.tracks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '未匹配 (${widget.tracks.length})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.error,
                ),
          ),
        ),
        // 歌曲列表
        ...widget.tracks.asMap().entries.map((entry) {
          final index = entry.key;
          final matchedTrack = entry.value;
          final original = matchedTrack.original;
          
          _searchControllers[index] ??= TextEditingController(
            text: '${original.title} ${original.artists.first}',
          );

          // 如果已有搜索结果（用户选择过），使用保存的结果
          final searchResults = _searchResults[index] ?? 
              (matchedTrack.searchResults.isNotEmpty ? matchedTrack.searchResults : []);

          return _UnmatchedTrackTile(
            matchedTrack: matchedTrack,
            isExpanded: _expandedIndices.contains(index),
            searchController: _searchControllers[index]!,
            isSearching: _isSearching[index] ?? false,
            searchResults: searchResults,
            onToggleExpand: () {
              setState(() {
                if (_expandedIndices.contains(index)) {
                  _expandedIndices.remove(index);
                } else {
                  _expandedIndices.add(index);
                }
              });
            },
            onSearch: () => _performSearch(index, matchedTrack),
            onSelectTrack: (selected) => _selectTrack(index, selected),
          );
        }),
      ],
    );
  }
}

/// 未匹配歌曲项 - 与已匹配样式一致
class _UnmatchedTrackTile extends ConsumerWidget {
  final MatchedTrack matchedTrack;
  final bool isExpanded;
  final TextEditingController searchController;
  final bool isSearching;
  final List<Track> searchResults;
  final VoidCallback onToggleExpand;
  final VoidCallback onSearch;
  final void Function(Track) onSelectTrack;

  const _UnmatchedTrackTile({
    required this.matchedTrack,
    required this.isExpanded,
    required this.searchController,
    required this.isSearching,
    required this.searchResults,
    required this.onToggleExpand,
    required this.onSearch,
    required this.onSelectTrack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final original = matchedTrack.original;
    final selectedTrack = matchedTrack.selectedTrack;
    final hasSelection = selectedTrack != null;

    return Column(
      children: [
        // 主行 - 如果已选择则显示选中的 track，否则显示原始信息
        ListTile(
          dense: true,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 选中状态图标
              SizedBox(
                width: 24,
                height: 24,
                child: hasSelection
                    ? Icon(Icons.check_circle, color: colorScheme.primary, size: 20)
                    : Icon(Icons.radio_button_unchecked, color: colorScheme.outline, size: 20),
              ),
              const SizedBox(width: 8),
              // 封面或音符图标
              if (hasSelection)
                TrackThumbnail(
                  track: selectedTrack,
                  size: 40,
                  borderRadius: 4,
                )
              else
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.music_note,
                    color: colorScheme.outline,
                    size: 20,
                  ),
                ),
            ],
          ),
          title: Text(
            hasSelection ? selectedTrack.title : original.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 艺术家和来源
              Row(
                children: [
                  Flexible(
                    child: Text(
                      hasSelection 
                          ? (selectedTrack.artist ?? '未知艺术家')
                          : original.artists.join(' / '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                  ),
                  if (hasSelection) ...[
                    const SizedBox(width: 8),
                    _SourceBadge(sourceType: selectedTrack.sourceType),
                  ],
                ],
              ),
              // 原曲信息（如果已选择）
              if (hasSelection)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${original.title} - ${original.artists.join(" / ")}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                        ),
                  ),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 时长
              SizedBox(
                width: 48,
                child: Text(
                  hasSelection && selectedTrack.durationMs != null
                      ? DurationFormatter.formatMs(selectedTrack.durationMs!)
                      : (original.duration != null 
                          ? DurationFormatter.formatSeconds(original.duration!.inSeconds)
                          : '--:--'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
              // 展开按钮
              IconButton(
                icon: Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                onPressed: onToggleExpand,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),

        // 展开区域：搜索框 + 搜索结果
        if (isExpanded) ...[
          // 搜索输入框
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 4, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: '输入搜索关键词...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                      onSubmitted: (_) => onSearch(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 32,
                  child: FilledButton.tonal(
                    onPressed: isSearching ? null : onSearch,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: Theme.of(context).textTheme.labelMedium,
                    ),
                    child: isSearching
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('搜索'),
                  ),
                ),
              ],
            ),
          ),

          // 搜索结果列表 - 使用与已匹配相同的样式
          ...searchResults.take(5).map((result) => _AlternativeTrackTile(
                track: result,
                isSelected: matchedTrack.selectedTrack?.sourceId == result.sourceId,
                onSelect: () => onSelectTrack(result),
              )),

          // 无结果提示
          if (!isSearching && searchResults.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Text(
                '输入关键词后点击搜索',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
            ),
        ],

        const Divider(height: 1, indent: 72),
      ],
    );
  }
}

/// 匹配结果项
class _ImportMatchTile extends StatelessWidget {
  final MatchedTrack matchedTrack;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final void Function(Track) onSelectAlternative;
  final void Function(bool) onToggleInclude;

  const _ImportMatchTile({
    required this.matchedTrack,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onSelectAlternative,
    required this.onToggleInclude,
  });

  @override
  Widget build(BuildContext context) {
    final track = matchedTrack.selectedTrack;
    final original = matchedTrack.original;
    final colorScheme = Theme.of(context).colorScheme;

    if (track == null) return const SizedBox.shrink();

    return Column(
      children: [
        // 主行：显示当前选中的搜索结果
        ListTile(
          dense: true,
          // 勾选框放到最左边，然后是封面
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: matchedTrack.isIncluded,
                  onChanged: (v) => onToggleInclude(v ?? false),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              TrackThumbnail(
                track: track,
                size: 40,
                borderRadius: 4,
              ),
            ],
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 第一行：艺术家、播放数、音源图标
              Row(
                children: [
                  // 艺术家
                  Flexible(
                    child: Text(
                      track.artist ?? '未知艺术家',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                  ),
                  // 播放数
                  if (track.viewCount != null) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.play_arrow, size: 14, color: colorScheme.outline),
                    const SizedBox(width: 2),
                    Text(
                      _formatViewCount(track.viewCount!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                  ],
                  // 音源标识（播放数右边，灰色）
                  const SizedBox(width: 8),
                  _SourceBadge(sourceType: track.sourceType),
                ],
              ),
              // 第二行：原曲信息（使用淡色圆形badge）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${original.title} - ${original.artists.join(" / ")}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 时长
              if (track.durationMs != null)
                SizedBox(
                  width: 48,
                  child: Text(
                    DurationFormatter.formatMs(track.durationMs!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              // 展开按钮
              if (matchedTrack.searchResults.length > 1)
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  onPressed: onToggleExpand,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),

        // 展开的其他搜索结果列表
        if (isExpanded)
          ...matchedTrack.searchResults.map((altTrack) => _AlternativeTrackTile(
                track: altTrack,
                isSelected: altTrack.sourceId == track.sourceId,
                onSelect: () => onSelectAlternative(altTrack),
              )),

        const Divider(height: 1, indent: 72),
      ],
    );
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
}

/// 备选搜索结果项
class _AlternativeTrackTile extends ConsumerWidget {
  final Track track;
  final bool isSelected;
  final VoidCallback onSelect;

  const _AlternativeTrackTile({
    required this.track,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(audioControllerProvider);
    final isThisTrackPlaying = playerState.playingTrack?.sourceId == track.sourceId &&
        playerState.playingTrack?.pageNum == track.pageNum;
    final isLoading = isThisTrackPlaying && (playerState.isLoading || playerState.isBuffering);
    final isPlaying = isThisTrackPlaying && playerState.isPlaying && !isLoading;

    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: ListTile(
        dense: true,
        // 选中状态图标 + 小封面
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: isSelected
                  ? Icon(Icons.check_circle, color: colorScheme.primary, size: 18)
                  : Icon(Icons.radio_button_unchecked,
                      color: colorScheme.outline, size: 18),
            ),
            const SizedBox(width: 8),
            TrackThumbnail(
              track: track,
              size: 32,
              borderRadius: 4,
            ),
          ],
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isSelected ? colorScheme.primary : null,
              ),
        ),
        subtitle: Row(
          children: [
            // 艺术家
            Flexible(
              child: Text(
                track.artist ?? '未知艺术家',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
            ),
            // 播放数
            if (track.viewCount != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.play_arrow, size: 12, color: colorScheme.outline),
              const SizedBox(width: 2),
              Text(
                _formatViewCount(track.viewCount!),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
            ],
            // 音源标识（播放数右边，灰色）
            const SizedBox(width: 6),
            _SourceBadge(sourceType: track.sourceType),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 时长（与主项目对齐，宽度48）
            if (track.durationMs != null)
              SizedBox(
                width: 48,
                child: Text(
                  DurationFormatter.formatMs(track.durationMs!),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            // 试听按钮（支持播放/暂停/加载状态）
            IconButton(
              icon: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  : Icon(
                      isPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline,
                      size: 20,
                      color: isThisTrackPlaying ? colorScheme.primary : null,
                    ),
              onPressed: isLoading
                  ? null
                  : () {
                      if (isThisTrackPlaying) {
                        ref.read(audioControllerProvider.notifier).togglePlayPause();
                      } else {
                        ref.read(audioControllerProvider.notifier).playTemporary(track);
                      }
                    },
              visualDensity: VisualDensity.compact,
              tooltip: isLoading ? '加载中' : (isPlaying ? '暂停' : '试听'),
            ),
          ],
        ),
        onTap: onSelect,
      ),
    );
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
}

/// 音源标识 - 使用灰色图标（与搜索页面一致）
class _SourceBadge extends StatelessWidget {
  final SourceType sourceType;

  const _SourceBadge({required this.sourceType});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (sourceType) {
      SourceType.bilibili => SimpleIcons.bilibili,
      SourceType.youtube => SimpleIcons.youtube,
    };

    return Icon(
      icon,
      size: 14,
      color: colorScheme.outline,
    );
  }
}
