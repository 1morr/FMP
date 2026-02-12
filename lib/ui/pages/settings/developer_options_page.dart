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
import '../../../core/services/network_image_cache_service.dart';
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

/// 内存信息显示
class _MemoryInfoTile extends StatefulWidget {
  const _MemoryInfoTile();

  @override
  State<_MemoryInfoTile> createState() => _MemoryInfoTileState();
}

class _MemoryInfoTileState extends State<_MemoryInfoTile> {
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
      // 获取图片缓存大小
      final imageCacheMB = await NetworkImageCacheService.getCacheSizeMB();
      final maxImageCacheMB = NetworkImageCacheService.maxCacheSizeMB;

      // 获取进程内存信息（仅限支持的平台）
      int? rssBytes;
      if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
        rssBytes = ProcessInfo.currentRss;
      }

      setState(() {
        _memoryInfo = _MemoryInfo(
          imageCacheMB: imageCacheMB,
          maxImageCacheMB: maxImageCacheMB,
          rssBytes: rssBytes,
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

  @override
  Widget build(BuildContext context) {
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

    final subtitleParts = <String>[];

    // 图片缓存
    subtitleParts.add(
      t.settings.developerOptions.imageCacheInfo(
        current: info.imageCacheMB.toStringAsFixed(1),
        max: info.maxImageCacheMB.toString(),
      ),
    );

    // 进程内存（如果可用）
    if (info.rssBytes != null) {
      subtitleParts.add(
        t.settings.developerOptions.processMemory(size: _formatBytes(info.rssBytes!)),
      );
    }

    return ListTile(
      leading: const Icon(Icons.memory),
      title: Text(t.settings.developerOptions.memoryUsage),
      subtitle: Text(subtitleParts.join('\n')),
      isThreeLine: info.rssBytes != null,
      trailing: IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: _loadMemoryInfo,
        tooltip: t.settings.developerOptions.refresh,
      ),
    );
  }
}

class _MemoryInfo {
  final double imageCacheMB;
  final int maxImageCacheMB;
  final int? rssBytes;

  _MemoryInfo({
    required this.imageCacheMB,
    required this.maxImageCacheMB,
    this.rssBytes,
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
