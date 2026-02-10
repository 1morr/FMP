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
                      ref.read(playlistImportProvider.notifier).reset();
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
                  if (state.unmatchedCount > 0)
                    _UnmatchedSection(
                      tracks: state.unmatchedOriginalTracks,
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
                      ref.read(playlistImportProvider.notifier).reset();
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

      // 重置导入状态
      ref.read(playlistImportProvider.notifier).reset();

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

/// 未匹配歌曲区域
class _UnmatchedSection extends StatelessWidget {
  final List<ImportedTrack> tracks;

  const _UnmatchedSection({required this.tracks});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (tracks.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(12),
      color: colorScheme.errorContainer.withValues(alpha: 0.3),
      child: ExpansionTile(
        leading: Icon(Icons.warning_amber, color: colorScheme.error),
        title: Text(
          '未匹配 (${tracks.length})',
          style: TextStyle(color: colorScheme.error),
        ),
        initiallyExpanded: false,
        children: tracks
            .map((track) => ListTile(
                  dense: true,
                  leading: Icon(Icons.music_off,
                      size: 20, color: colorScheme.outline),
                  title: Text(
                    '${track.title} - ${track.artists.join(" / ")}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ))
            .toList(),
      ),
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
            // 播放按钮
            IconButton(
              icon: const Icon(Icons.play_circle_outline, size: 20),
              onPressed: () {
                ref.read(audioControllerProvider.notifier).playTemporary(track);
              },
              visualDensity: VisualDensity.compact,
              tooltip: '试听',
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
