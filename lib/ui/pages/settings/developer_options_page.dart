import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/models/play_queue.dart';
import '../../../data/models/playlist.dart';
import '../../../data/models/settings.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/lyrics_provider.dart';
import '../../../core/services/network_image_cache_service.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/cache/ranking_cache_service.dart';
import '../../router.dart';
import '../debug/youtube_stream_test_page.dart';

/// 开发者选项页面
class DeveloperOptionsPage extends ConsumerWidget {
  const DeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t.settings.developerOptions.title),
      ),
      body: ListView(
        children: [
          // 调试工具
          _SettingsSection(
            title: t.settings.developerOptions.debugTools,
            children: [
              const _MemoryInfoTile(),
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(t.settings.developerOptions.liveLog),
                subtitle: Text(t.settings.developerOptions.liveLogSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(RouteNames.logViewer),
              ),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: Text(t.settings.developerOptions.dbViewer),
                subtitle: Text(t.settings.developerOptions.dbViewerSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(RouteNames.databaseViewer),
              ),
              ListTile(
                leading: const Icon(Icons.music_note_outlined),
                title: Text(t.settings.developerOptions.ytStreamTest),
                subtitle: Text(t.settings.developerOptions.ytStreamTestSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const YouTubeStreamTestPage(),
                  ),
                ),
              ),
            ],
          ),
          const Divider(),
          // 数据管理
          _SettingsSection(
            title: t.settings.developerOptions.dataManagement,
            children: [
              _DatabaseInfoTile(),
              _ResetDataTile(),
            ],
          ),
          const Divider(),
          // 信息
          _SettingsSection(
            title: t.settings.developerOptions.devInfo,
            children: [
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: Text(t.settings.developerOptions.debugMode),
                subtitle: Text(t.general.enabled),
                trailing: Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 数据库信息显示
class _DatabaseInfoTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(databaseProvider);

    return dbAsync.when(
      loading: () => ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(t.settings.developerOptions.dbInfo),
        subtitle: Text(t.general.loading),
      ),
      error: (e, _) => ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(t.settings.developerOptions.dbInfo),
        subtitle: Text(t.settings.developerOptions.dbInfoError(error: '$e')),
      ),
      data: (isar) => FutureBuilder<_DatabaseInfo>(
        future: _getDatabaseInfo(isar),
        builder: (context, snapshot) {
          final info = snapshot.data;
          return ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(t.settings.developerOptions.dbInfo),
            subtitle: Text(
              info != null
                  ? t.settings.developerOptions.dbInfoDetail(
                      path: info.path,
                      size: _formatSize(info.size),
                      tracks: info.trackCount.toString(),
                      playlists: info.playlistCount.toString(),
                    )
                  : t.general.loading,
            ),
            isThreeLine: true,
          );
        },
      ),
    );
  }

  Future<_DatabaseInfo> _getDatabaseInfo(Isar isar) async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/fmp_database.isar';
    final file = File(dbPath);
    final size = await file.exists() ? await file.length() : 0;

    final trackCount = await isar.tracks.count();
    final playlistCount = await isar.playlists.count();

    return _DatabaseInfo(
      path: dir.path,
      size: size,
      trackCount: trackCount,
      playlistCount: playlistCount,
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _DatabaseInfo {
  final String path;
  final int size;
  final int trackCount;
  final int playlistCount;

  _DatabaseInfo({
    required this.path,
    required this.size,
    required this.trackCount,
    required this.playlistCount,
  });
}

/// 内存信息显示（增强版）
class _MemoryInfoTile extends ConsumerStatefulWidget {
  const _MemoryInfoTile();

  @override
  ConsumerState<_MemoryInfoTile> createState() => _MemoryInfoTileState();
}

class _MemoryInfoTileState extends ConsumerState<_MemoryInfoTile> {
  _MemoryInfo? _memoryInfo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMemoryInfo();
  }

  Future<void> _loadMemoryInfo() async {
    setState(() => _isLoading = true);

    try {
      // Flutter 图片内存缓存
      final imageCache = PaintingBinding.instance.imageCache;
      final imageCacheCount = imageCache.currentSize;
      final imageCacheMaxCount = imageCache.maximumSize;
      final imageCacheSizeBytes = imageCache.currentSizeBytes;
      final imageCacheMaxSizeBytes = imageCache.maximumSizeBytes;

      // 网络图片磁盘缓存
      final diskCacheMB = await NetworkImageCacheService.getCacheSizeMB();
      final diskCacheMaxMB = NetworkImageCacheService.maxCacheSizeMB;

      // 进程 RSS
      int? rssBytes;
      if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
        rssBytes = ProcessInfo.currentRss;
      }

      // Dart VM 内存 - 暂无直接 API，通过 RSS 减去已知缓存估算

      // 数据缓存统计
      final queueTrackCount = ref.read(queueProvider).length;
      final rankingCache = RankingCacheService.instance;
      final bilibiliCacheCount = rankingCache.bilibiliTracks.length;
      final youtubeCacheCount = rankingCache.youtubeTracks.length;

      // 歌词缓存
      int lyricsCacheCount = 0;
      try {
        final lyricsCache = ref.read(lyricsCacheServiceProvider);
        final stats = await lyricsCache.getStats();
        lyricsCacheCount = stats.fileCount;
      } catch (_) {}

      setState(() {
        _memoryInfo = _MemoryInfo(
          // Flutter 图片内存缓存
          imageCacheCount: imageCacheCount,
          imageCacheMaxCount: imageCacheMaxCount,
          imageCacheSizeBytes: imageCacheSizeBytes,
          imageCacheMaxSizeBytes: imageCacheMaxSizeBytes,
          // 磁盘缓存
          diskCacheMB: diskCacheMB,
          diskCacheMaxMB: diskCacheMaxMB,
          // 进程
          rssBytes: rssBytes,
          // 数据缓存
          queueTrackCount: queueTrackCount,
          bilibiliCacheCount: bilibiliCacheCount,
          youtubeCacheCount: youtubeCacheCount,
          lyricsCacheCount: lyricsCacheCount,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  void _clearImageMemoryCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.settings.developerOptions.clearImageMemoryCacheDone),
        duration: const Duration(seconds: 2),
      ),
    );
    _loadMemoryInfo();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return ListTile(
        leading: const Icon(Icons.memory),
        title: Text(t.settings.developerOptions.memoryUsage),
        subtitle: Text(t.general.loading),
      );
    }

    final info = _memoryInfo;
    if (info == null) {
      return ListTile(
        leading: const Icon(Icons.memory),
        title: Text(t.settings.developerOptions.memoryUsage),
        subtitle: Text(t.settings.developerOptions.memoryUnavailable),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadMemoryInfo,
        ),
      );
    }

    // 摘要行：RSS 总量
    final summaryParts = <String>[];
    if (info.rssBytes != null) {
      summaryParts.add('RSS: ${_formatBytes(info.rssBytes!)}');
    }
    summaryParts.add(
      'Flutter 图片: ${_formatBytes(info.imageCacheSizeBytes)}',
    );

    return ExpansionTile(
      leading: const Icon(Icons.memory),
      title: Text(t.settings.developerOptions.memoryUsage),
      subtitle: Text(summaryParts.join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadMemoryInfo,
            tooltip: t.settings.developerOptions.refresh,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      childrenPadding: const EdgeInsets.only(
        left: 16, right: 16, bottom: 12,
      ),
      children: [
        // 进程总内存
        if (info.rssBytes != null)
          _buildInfoRow(
            Icons.pie_chart_outline,
            t.settings.developerOptions.processMemory(
              size: _formatBytes(info.rssBytes!),
            ),
            colorScheme,
          ),

        // Flutter 图片内存缓存（通常是最大头）
        _buildInfoRow(
          Icons.image_outlined,
          t.settings.developerOptions.flutterImageCacheDetail(
            count: info.imageCacheCount.toString(),
            maxCount: info.imageCacheMaxCount.toString(),
            size: (info.imageCacheSizeBytes / (1024 * 1024)).toStringAsFixed(1),
            maxSize: (info.imageCacheMaxSizeBytes / (1024 * 1024)).toStringAsFixed(0),
          ),
          colorScheme,
          label: t.settings.developerOptions.flutterImageCache,
          // 超过 70% 显示警告色
          isWarning: info.imageCacheSizeBytes > info.imageCacheMaxSizeBytes * 0.7,
        ),

        // Native 内存估算
        if (info.rssBytes != null)
          _buildInfoRow(
            Icons.developer_board_outlined,
            t.settings.developerOptions.nativeMemoryDetail(
              size: _formatBytes(
                (info.rssBytes! - info.imageCacheSizeBytes).clamp(0, info.rssBytes!),
              ),
            ),
            colorScheme,
            label: t.settings.developerOptions.nativeMemory,
          ),

        // 磁盘图片缓存
        _buildInfoRow(
          Icons.sd_storage_outlined,
          t.settings.developerOptions.imageCacheInfo(
            current: info.diskCacheMB.toStringAsFixed(1),
            max: info.diskCacheMaxMB.toString(),
          ),
          colorScheme,
        ),

        const Divider(height: 16),

        // 数据缓存
        _buildInfoRow(
          Icons.queue_music,
          t.settings.developerOptions.queueTracks(
            count: info.queueTrackCount.toString(),
          ),
          colorScheme,
          label: t.settings.developerOptions.dataCaches,
        ),
        _buildInfoRow(
          Icons.trending_up,
          t.settings.developerOptions.rankingCache(
            bilibili: info.bilibiliCacheCount.toString(),
            youtube: info.youtubeCacheCount.toString(),
          ),
          colorScheme,
        ),
        _buildInfoRow(
          Icons.lyrics_outlined,
          t.settings.developerOptions.lyricsCacheCount(
            count: info.lyricsCacheCount.toString(),
          ),
          colorScheme,
        ),

        const SizedBox(height: 8),

        // 清除图片内存缓存按钮
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _clearImageMemoryCache,
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            label: Text(t.settings.developerOptions.clearImageMemoryCache),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String text,
    ColorScheme colorScheme, {
    String? label,
    bool isWarning = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2, top: 4),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isWarning
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: isWarning
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemoryInfo {
  // Flutter 图片内存缓存
  final int imageCacheCount;
  final int imageCacheMaxCount;
  final int imageCacheSizeBytes;
  final int imageCacheMaxSizeBytes;
  // 磁盘缓存
  final double diskCacheMB;
  final int diskCacheMaxMB;
  // 进程
  final int? rssBytes;
  // 数据缓存
  final int queueTrackCount;
  final int bilibiliCacheCount;
  final int youtubeCacheCount;
  final int lyricsCacheCount;

  _MemoryInfo({
    required this.imageCacheCount,
    required this.imageCacheMaxCount,
    required this.imageCacheSizeBytes,
    required this.imageCacheMaxSizeBytes,
    required this.diskCacheMB,
    required this.diskCacheMaxMB,
    this.rssBytes,
    required this.queueTrackCount,
    required this.bilibiliCacheCount,
    required this.youtubeCacheCount,
    required this.lyricsCacheCount,
  });
}

/// 重置数据按钮
class _ResetDataTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(
        Icons.delete_forever,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        t.settings.developerOptions.resetAllData,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      subtitle: Text(t.settings.developerOptions.resetSubtitle),
      onTap: () => _showResetConfirmDialog(context, ref),
    );
  }

  void _showResetConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.developerOptions.confirmReset),
        content: Text(t.settings.developerOptions.resetWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.general.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(context).pop();
              await _resetAllData(context, ref);
            },
            child: Text(t.settings.developerOptions.confirmReset),
          ),
        ],
      ),
    );
  }

  Future<void> _resetAllData(BuildContext context, WidgetRef ref) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // 显示进度
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(t.settings.developerOptions.resetting)),
      );

      final isar = await ref.read(databaseProvider.future);

      // 清空所有集合
      await isar.writeTxn(() async {
        await isar.clear();
      });

      // 重新创建默认数据
      await isar.writeTxn(() async {
        // 创建默认设置
        await isar.settings.put(Settings());
        // 创建默认播放队列
        await isar.playQueues.put(PlayQueue());
      });

      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(t.settings.developerOptions.resetDone),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(t.settings.developerOptions.resetFailed(error: '$e'))),
      );
    }
  }
}

/// 设置区块（复用）
class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ...children,
      ],
    );
  }
}
