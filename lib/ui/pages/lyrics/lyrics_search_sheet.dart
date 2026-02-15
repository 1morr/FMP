import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/lyrics_provider.dart';
import '../../../services/lyrics/lyrics_result.dart';

/// 显示歌词搜索匹配 BottomSheet
void showLyricsSearchSheet({
  required BuildContext context,
  required Track track,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => LyricsSearchSheet(track: track),
  );
}

/// 歌词搜索匹配 BottomSheet
class LyricsSearchSheet extends ConsumerStatefulWidget {
  final Track track;

  const LyricsSearchSheet({super.key, required this.track});

  @override
  ConsumerState<LyricsSearchSheet> createState() => _LyricsSearchSheetState();
}

class _LyricsSearchSheetState extends ConsumerState<LyricsSearchSheet> {
  final _searchController = TextEditingController();
  bool _hasAutoSearched = false;
  LyricsSourceFilter _selectedFilter = LyricsSourceFilter.all;

  @override
  void initState() {
    super.initState();
    // 用 TitleParser 解析标题，预填搜索框
    final parser = ref.read(titleParserProvider);
    final parsed = parser.parse(
      widget.track.title,
      uploader: widget.track.artist,
    );
    _searchController.text = parsed.trackName;

    // 自动搜索
    Future.microtask(() => _doSearch());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _doSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    _hasAutoSearched = true;
    final notifier = ref.read(lyricsSearchProvider.notifier);
    notifier.setFilter(_selectedFilter);
    notifier.search(query: query);
  }

  Future<void> _selectResult(LyricsResult result) async {
    final notifier = ref.read(lyricsSearchProvider.notifier);
    await notifier.saveMatch(
      trackUniqueKey: widget.track.uniqueKey,
      result: result,
    );
    // invalidate 相关 providers
    ref.invalidate(currentLyricsMatchProvider);
    ref.invalidate(lyricsMatchForTrackProvider(widget.track.uniqueKey));

    if (mounted) {
      Navigator.of(context).pop();
      ToastService.success(context, t.lyrics.lyricsMatched);
    }
  }

  Future<void> _removeMatch() async {
    final notifier = ref.read(lyricsSearchProvider.notifier);
    await notifier.removeMatch(widget.track.uniqueKey);
    ref.invalidate(currentLyricsMatchProvider);
    ref.invalidate(lyricsMatchForTrackProvider(widget.track.uniqueKey));

    if (mounted) {
      Navigator.of(context).pop();
      ToastService.success(context, t.lyrics.lyricsRemoved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final searchState = ref.watch(lyricsSearchProvider);
    final existingMatch =
        ref.watch(lyricsMatchForTrackProvider(widget.track.uniqueKey));

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 拖拽手柄
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
              ),
            ),

            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                t.lyrics.searchLyrics,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),

            // Track 信息
            _buildTrackInfo(colorScheme),
            const SizedBox(height: 8),

            // 已有匹配提示
            if (existingMatch.valueOrNull != null)
              _buildExistingMatch(colorScheme),

            // 搜索框
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: t.lyrics.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _doSearch,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.borderRadiusXl,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _doSearch(),
              ),
            ),

            // 歌词源筛选
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SegmentedButton<LyricsSourceFilter>(
                segments: [
                  ButtonSegment(
                    value: LyricsSourceFilter.all,
                    label: Text(t.lyrics.sourceAll),
                  ),
                  ButtonSegment(
                    value: LyricsSourceFilter.netease,
                    label: Text(t.lyrics.sourceNetease),
                  ),
                  ButtonSegment(
                    value: LyricsSourceFilter.qqmusic,
                    label: Text(t.lyrics.sourceQQMusic),
                  ),
                  ButtonSegment(
                    value: LyricsSourceFilter.lrclib,
                    label: Text(t.lyrics.sourceLrclib),
                  ),
                ],
                selected: {_selectedFilter},
                onSelectionChanged: (selected) {
                  setState(() => _selectedFilter = selected.first);
                  if (_hasAutoSearched) _doSearch();
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),

            // 结果列表
            Expanded(
              child: _buildResults(searchState, scrollController, colorScheme),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrackInfo(ColorScheme colorScheme) {
    final track = widget.track;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.music_note, size: 20, color: colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (track.artist != null)
                  Text(
                    track.artist!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (track.durationMs != null)
            Text(
              track.formattedDuration,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _buildExistingMatch(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            t.lyrics.currentMatch,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _removeMatch,
            icon: const Icon(Icons.close, size: 16),
            label: Text(t.lyrics.removeMatch),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.error,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(
    LyricsSearchState searchState,
    ScrollController scrollController,
    ColorScheme colorScheme,
  ) {
    if (searchState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 8),
            Text(searchState.error!,
                style: TextStyle(color: colorScheme.error)),
          ],
        ),
      );
    }

    if (!_hasAutoSearched) {
      return Center(
        child: Text(
          t.lyrics.autoSearching,
          style: TextStyle(color: colorScheme.outline),
        ),
      );
    }

    if (searchState.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lyrics_outlined, size: 48, color: colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              t.lyrics.noLyricsFound,
              style: TextStyle(color: colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: searchState.results.length,
      itemBuilder: (context, index) {
        final result = searchState.results[index];
        return _LyricsResultTile(
          result: result,
          trackDurationMs: widget.track.durationMs,
          onTap: () => _selectResult(result),
        );
      },
    );
  }
}

/// 歌词搜索结果项
class _LyricsResultTile extends StatelessWidget {
  final LyricsResult result;
  final int? trackDurationMs;
  final VoidCallback onTap;

  const _LyricsResultTile({
    required this.result,
    this.trackDurationMs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 时长匹配度指示
    final durationMatch = _getDurationMatch();

    return ListTile(
      onTap: onTap,
      leading: Icon(
        result.hasSyncedLyrics
            ? Icons.lyrics
            : result.hasPlainLyrics
                ? Icons.text_snippet
                : Icons.music_off,
        color: result.hasSyncedLyrics
            ? colorScheme.primary
            : colorScheme.outline,
      ),
      title: Text(
        result.trackName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${result.artistName}'
        '${result.albumName.isNotEmpty ? ' · ${result.albumName}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colorScheme.outline),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 来源标签
          _buildSourceChip(colorScheme),
          const SizedBox(width: 4),
          // 同步/纯文本标签
          _buildTypeChip(context, colorScheme),
          // 翻译/罗马音标签
          if (result.hasTranslatedLyrics) ...[
            const SizedBox(width: 4),
            _Chip(label: t.lyrics.translated, color: colorScheme.secondary),
          ],
          if (result.hasRomajiLyrics) ...[
            const SizedBox(width: 4),
            _Chip(label: t.lyrics.romaji, color: colorScheme.tertiary),
          ],
          const SizedBox(width: 8),
          // 时长
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatDuration(result.duration),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: durationMatch ?? colorScheme.outline,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceChip(ColorScheme colorScheme) {
    switch (result.source) {
      case 'netease':
        return _Chip(
          label: t.lyrics.sourceNetease,
          color: colorScheme.error,
        );
      case 'qqmusic':
        return _Chip(
          label: t.lyrics.sourceQQMusic,
          color: colorScheme.tertiary,
        );
      default:
        return _Chip(
          label: t.lyrics.sourceLrclib,
          color: colorScheme.outline,
        );
    }
  }

  Widget _buildTypeChip(BuildContext context, ColorScheme colorScheme) {
    if (result.instrumental) {
      return _Chip(
        label: t.lyrics.instrumental,
        color: colorScheme.tertiary,
      );
    }
    if (result.hasSyncedLyrics) {
      return _Chip(
        label: t.lyrics.synced,
        color: colorScheme.primary,
      );
    }
    if (result.hasPlainLyrics) {
      return _Chip(
        label: t.lyrics.plain,
        color: colorScheme.outline,
      );
    }
    return const SizedBox.shrink();
  }

  /// 格式化秒数为 mm:ss 或 h:mm:ss
  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${secs.toString().padLeft(2, '0')}';
    }
  }

  /// 返回时长匹配颜色，null 表示无法比较
  Color? _getDurationMatch() {
    if (trackDurationMs == null || result.duration == 0) return null;
    final trackSeconds = trackDurationMs! ~/ 1000;
    final diff = (trackSeconds - result.duration).abs();
    if (diff <= 2) return Colors.green;
    if (diff <= 5) return Colors.orange;
    return Colors.red;
  }
}

/// 小标签
class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
