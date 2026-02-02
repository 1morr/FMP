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
import '../../../providers/database_provider.dart';
import '../../../core/services/network_image_cache_service.dart';
import '../../../providers/playback_settings_provider.dart';
import '../../router.dart';
import '../debug/youtube_stream_test_page.dart';

/// 开发者选项页面
class DeveloperOptionsPage extends ConsumerWidget {
  const DeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('开发者选项'),
      ),
      body: ListView(
        children: [
          // 调试工具
          _SettingsSection(
            title: '调试工具',
            children: [
              const _MemoryInfoTile(),
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('实时日志'),
                subtitle: const Text('查看应用运行日志'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(RouteNames.logViewer),
              ),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('数据库查看器'),
                subtitle: const Text('查看和浏览 Isar 数据库内容'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(RouteNames.databaseViewer),
              ),
              ListTile(
                leading: const Icon(Icons.music_note_outlined),
                title: const Text('YouTube 流测试'),
                subtitle: const Text('测试 Audio-only / Muxed / HLS 流播放'),
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
            title: '数据管理',
            children: [
              _DatabaseInfoTile(),
              _ResetDataTile(),
            ],
          ),
          const Divider(),
          // 实验性功能
          _SettingsSection(
            title: '实验性功能',
            children: [
              _AutoScrollListTile(),
            ],
          ),
          const Divider(),
          // 信息
          _SettingsSection(
            title: '开发信息',
            children: [
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('调试模式'),
                subtitle: const Text('已启用'),
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
      loading: () => const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('数据库信息'),
        subtitle: Text('加载中...'),
      ),
      error: (e, _) => ListTile(
        leading: const Icon(Icons.error_outline),
        title: const Text('数据库信息'),
        subtitle: Text('错误: $e'),
      ),
      data: (isar) => FutureBuilder<_DatabaseInfo>(
        future: _getDatabaseInfo(isar),
        builder: (context, snapshot) {
          final info = snapshot.data;
          return ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('数据库信息'),
            subtitle: Text(
              info != null
                  ? '路径: ${info.path}\n'
                    '大小: ${_formatSize(info.size)}\n'
                    '歌曲: ${info.trackCount} | 歌单: ${info.playlistCount}'
                  : '加载中...',
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
      return const ListTile(
        leading: Icon(Icons.memory),
        title: Text('内存使用'),
        subtitle: Text('加载中...'),
      );
    }

    final info = _memoryInfo;
    if (info == null) {
      return ListTile(
        leading: const Icon(Icons.memory),
        title: const Text('内存使用'),
        subtitle: const Text('无法获取内存信息'),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadMemoryInfo,
        ),
      );
    }

    final subtitleParts = <String>[];

    // 图片缓存
    subtitleParts.add(
      '图片缓存: ${info.imageCacheMB.toStringAsFixed(1)} / ${info.maxImageCacheMB} MB',
    );

    // 进程内存（如果可用）
    if (info.rssBytes != null) {
      subtitleParts.add('进程内存 (RSS): ${_formatBytes(info.rssBytes!)}');
    }

    return ListTile(
      leading: const Icon(Icons.memory),
      title: const Text('内存使用'),
      subtitle: Text(subtitleParts.join('\n')),
      isThreeLine: info.rssBytes != null,
      trailing: IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: _loadMemoryInfo,
        tooltip: '刷新',
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
        '重置所有数据',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      subtitle: const Text('删除所有歌单、播放队列和设置（不可恢复）'),
      onTap: () => _showResetConfirmDialog(context, ref),
    );
  }

  void _showResetConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认重置'),
        content: const Text(
          '此操作将删除所有数据，包括：\n'
          '• 所有歌单\n'
          '• 播放队列\n'
          '• 搜索历史\n'
          '• 应用设置\n\n'
          '此操作不可恢复！',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(context).pop();
              await _resetAllData(context, ref);
            },
            child: const Text('确认重置'),
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
        const SnackBar(content: Text('正在重置数据...')),
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
        const SnackBar(
          content: Text('数据已重置，请重启应用'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('重置失败: $e')),
      );
    }
  }
}

/// 自动跳转到当前播放设置（从主设置页移动过来）
class _AutoScrollListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackSettings = ref.watch(playbackSettingsProvider);

    return SwitchListTile(
      secondary: const Icon(Icons.my_location_outlined),
      title: const Text('切歌时自动定位'),
      subtitle: const Text('切换歌曲时自动跳转到队列页面并定位当前播放'),
      value: playbackSettings.autoScrollToCurrentTrack,
      onChanged: playbackSettings.isLoading
          ? null
          : (value) {
              ref.read(playbackSettingsProvider.notifier).setAutoScrollToCurrentTrack(value);
            },
    );
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
