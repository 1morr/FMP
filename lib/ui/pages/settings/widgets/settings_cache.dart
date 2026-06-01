part of '../settings_page.dart';

/// 图片缓存设置。
class _ImageCacheSizeListTile extends StatefulWidget {
  @override
  State<_ImageCacheSizeListTile> createState() =>
      _ImageCacheSizeListTileState();
}

class _ImageCacheSizeListTileState extends State<_ImageCacheSizeListTile> {
  double? _cacheSizeMB;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final sizeMB = await NetworkImageCacheService.getCacheSizeMB();
    if (mounted) {
      setState(() => _cacheSizeMB = sizeMB);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(downloadSettingsProvider);
        final cacheSizeMB = settings.maxCacheSizeMB;
        final maxSizeText = t.settings.imageCache.maxSize(
          size: _formatLimit(cacheSizeMB),
        );

        return ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: Text(t.settings.imageCache.title),
          subtitle: Text(maxSizeText),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showImageCacheDialog(context, ref, cacheSizeMB),
        );
      },
    );
  }

  String _formatLimit(int sizeMB) {
    if (sizeMB >= 1024) {
      return '${(sizeMB / 1024).toStringAsFixed(1)} GB';
    }
    return '$sizeMB MB';
  }

  String _formatSize(double mb) {
    if (mb < 1) {
      return '${(mb * 1024).toStringAsFixed(1)} KB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  void _showImageCacheDialog(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) {
    final options = [16, 32, 48, 64];
    final currentCacheText = _cacheSizeMB != null
        ? t.settings.imageCache.currentCacheSize(
            size: _formatSize(_cacheSizeMB!),
          )
        : t.settings.imageCache.calculating;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.imageCache.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioGroup<int>(
                groupValue: current,
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(downloadSettingsProvider.notifier)
                        .setMaxCacheSizeMB(value);
                  }
                  Navigator.pop(dialogContext);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: options.map((sizeMB) {
                    return RadioListTile<int>(
                      title: Text(_formatLimit(sizeMB)),
                      value: sizeMB,
                    );
                  }).toList(),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline),
                title: Text(t.settings.imageCache.clearTitle),
                subtitle: Text(currentCacheText),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  await ImageLoadingService.clearNetworkCache();
                  await _loadCacheSize();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t.settings.imageCache.cacheCleared),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 歌词缓存设置。
class _LyricsCacheSizeListTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_LyricsCacheSizeListTile> createState() =>
      _LyricsCacheSizeListTileState();
}

class _LyricsCacheSizeListTileState
    extends ConsumerState<_LyricsCacheSizeListTile> {
  CacheStats? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final cache = ref.read(lyricsCacheServiceProvider);
    final stats = await cache.getStats();
    if (mounted) setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    final maxFiles = ref.watch(downloadSettingsProvider).maxLyricsCacheFiles;
    final maxFilesText = t.settings.lyricsCache.maxFiles(count: maxFiles);

    return ListTile(
      leading: const Icon(Icons.lyrics_outlined),
      title: Text(t.settings.lyricsCache.title),
      subtitle: Text(maxFilesText),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showLyricsCacheDialog(context, ref, maxFiles),
    );
  }

  void _showLyricsCacheDialog(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) {
    final options = [10, 30, 50, 100, 200];
    final currentCacheText = _stats != null
        ? t.settings.lyricsCache.currentCache(
            count: _stats!.fileCount,
            size: _stats!.formattedSize,
          )
        : t.settings.lyricsCache.calculating;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.lyricsCache.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioGroup<int>(
                groupValue: current,
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(downloadSettingsProvider.notifier)
                        .setMaxLyricsCacheFiles(value);
                  }
                  Navigator.pop(dialogContext);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: options.map((count) {
                    return RadioListTile<int>(
                      title: Text(
                        t.settings.lyricsCache.maxFiles(count: count),
                      ),
                      value: count,
                    );
                  }).toList(),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline),
                title: Text(t.settings.lyricsCache.clearTitle),
                subtitle: Text(currentCacheText),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final cache = ref.read(lyricsCacheServiceProvider);
                  await cache.clear();
                  await _loadStats();
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(t.settings.lyricsCache.cacheCleared),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 排行榜刷新间隔设置。
class _RankingRefreshIntervalListTile extends ConsumerWidget {
  // 选项: 30分钟, 1小时, 2小时, 4小时
  static const _options = [30, 60, 120, 240];

  String _formatInterval(int minutes) {
    if (minutes >= 60) {
      return t.settings.refreshInterval.hours(n: minutes ~/ 60);
    }
    return t.settings.refreshInterval.minutes(n: minutes);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(refreshSettingsProvider);
    final current = settings.rankingRefreshIntervalMinutes;

    return ListTile(
      leading: const Icon(Icons.leaderboard_outlined),
      title: Text(t.settings.refreshInterval.rankingTitle),
      subtitle: Text(t.settings.refreshInterval
          .rankingSubtitle(interval: _formatInterval(current))),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showDialog(context, ref, current),
    );
  }

  void _showDialog(BuildContext context, WidgetRef ref, int current) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.refreshInterval.rankingTitle),
        content: RadioGroup<int>(
          groupValue: current,
          onChanged: (value) {
            if (value != null) {
              ref
                  .read(refreshSettingsProvider.notifier)
                  .setRankingRefreshInterval(value);
            }
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _options.map((minutes) {
              return RadioListTile<int>(
                title: Text(_formatInterval(minutes)),
                value: minutes,
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 电台状态刷新间隔设置。
class _RadioRefreshIntervalListTile extends ConsumerWidget {
  // 选项: 1分钟, 3分钟, 5分钟, 10分钟
  static const _options = [1, 3, 5, 10];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(refreshSettingsProvider);
    final current = settings.radioRefreshIntervalMinutes;

    return ListTile(
      leading: const Icon(Icons.radio_outlined),
      title: Text(t.settings.refreshInterval.radioTitle),
      subtitle: Text(t.settings.refreshInterval.radioSubtitle(
        interval: t.settings.refreshInterval.minutes(n: current),
      )),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showDialog(context, ref, current),
    );
  }

  void _showDialog(BuildContext context, WidgetRef ref, int current) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.refreshInterval.radioTitle),
        content: RadioGroup<int>(
          groupValue: current,
          onChanged: (value) {
            if (value != null) {
              ref
                  .read(refreshSettingsProvider.notifier)
                  .setRadioRefreshInterval(value);
            }
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _options.map((minutes) {
              return RadioListTile<int>(
                title: Text(t.settings.refreshInterval.minutes(n: minutes)),
                value: minutes,
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}
