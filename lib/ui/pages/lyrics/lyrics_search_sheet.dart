import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/lyrics_provider.dart';
import '../../../services/lyrics/lyrics_result.dart';
import '../../widgets/track_thumbnail.dart';

/// 显示歌词搜索匹配 BottomSheet
void showLyricsSearchSheet({
  required BuildContext context,
  required Track track,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
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
    // 预填完整标题到搜索框
    _searchController.text = widget.track.title;
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

  void _setFilter(LyricsSourceFilter filter) {
    setState(() => _selectedFilter = filter);
    if (_hasAutoSearched) _doSearch();
  }

  Future<void> _selectResult(LyricsResult result) async {
    final notifier = ref.read(lyricsSearchProvider.notifier);
    await notifier.saveMatch(
      trackUniqueKey: widget.track.uniqueKey,
      result: result,
    );
    // invalidate 相关 providers，确保歌词内容也重新加载
    ref.invalidate(currentLyricsMatchProvider);
    ref.invalidate(currentLyricsContentProvider);
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
    ref.invalidate(currentLyricsContentProvider);
    ref.invalidate(lyricsMatchForTrackProvider(widget.track.uniqueKey));

    if (mounted) {
      Navigator.of(context).pop();
      ToastService.success(context, t.lyrics.lyricsRemoved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final searchState = ref.watch(lyricsSearchProvider);
    final existingMatch =
        ref.watch(lyricsMatchForTrackProvider(widget.track.uniqueKey));

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.0,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.0, 0.75, 0.95],
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 顶部固定区域（手柄 + 标题 + 搜索框 + 筛选）
              Column(
                children: [
                  // 拖动手柄
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: AppRadius.borderRadiusXs,
                    ),
                  ),
                  // 标题栏
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lyrics_outlined,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          t.lyrics.searchLyrics,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Track 信息
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _buildTrackInfo(
                      colorScheme,
                      hasMatch: existingMatch.valueOrNull != null,
                    ),
                  ),

                  // 搜索框
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
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
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    height: 40,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text(t.lyrics.sourceAll),
                              selected: _selectedFilter == LyricsSourceFilter.all,
                              onSelected: (_) => _setFilter(LyricsSourceFilter.all),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text(t.lyrics.sourceNetease),
                              selected: _selectedFilter == LyricsSourceFilter.netease,
                              onSelected: (_) => _setFilter(LyricsSourceFilter.netease),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text(t.lyrics.sourceQQMusic),
                              selected: _selectedFilter == LyricsSourceFilter.qqmusic,
                              onSelected: (_) => _setFilter(LyricsSourceFilter.qqmusic),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text(t.lyrics.sourceLrclib),
                              selected: _selectedFilter == LyricsSourceFilter.lrclib,
                              onSelected: (_) => _setFilter(LyricsSourceFilter.lrclib),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // 结果列表（可滚动区域）
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  child: _buildResults(searchState, scrollController, colorScheme),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrackInfo(ColorScheme colorScheme, {required bool hasMatch}) {
    final track = widget.track;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        // 封面缩略图
        TrackThumbnail(
          track: track,
          size: 48,
          showPlayingIndicator: false,
          borderRadius: 8,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (track.artist != null) ...[
                const SizedBox(height: 2),
                Text(
                  track.artist!,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (track.durationMs != null)
          Text(
            track.formattedDuration,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        // 移除匹配按钮
        if (hasMatch) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton.filledTonal(
              onPressed: _removeMatch,
              icon: const Icon(Icons.close, size: 14),
              padding: EdgeInsets.zero,
              tooltip: t.lyrics.removeMatch,
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.errorContainer,
                foregroundColor: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ],
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

    if (searchState.results.isEmpty && !_hasAutoSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 48, color: colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              t.lyrics.searchPrompt,
              style: TextStyle(color: colorScheme.outline),
            ),
          ],
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

    // 过滤掉纯音乐（instrumental）结果，因为没有歌词
    final filtered = searchState.results
        .where((r) => !r.instrumental)
        .toList(growable: false);

    if (filtered.isEmpty) {
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
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final result = filtered[index];
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
    if (diff <= 3) return Colors.green;
    if (diff <= 10) return Colors.orange;
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
