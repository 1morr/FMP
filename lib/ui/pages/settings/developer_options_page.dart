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
import '../../../providers/playback_settings_provider.dart';
import '../../../core/services/network_image_cache_service.dart';
import '../../router.dart';

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
            ],
          ),
          const Divider(),
          // 数据管理
          _SettingsSection(
            title: '数据管理',
            children: [
              _DatabaseInfoTile(),
              _ImageCacheSizeInfoTile(),
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

/// 图片缓存大小信息显示
class _ImageCacheSizeInfoTile extends StatefulWidget {
  @override
  State<_ImageCacheSizeInfoTile> createState() => _ImageCacheSizeInfoTileState();
}

class _ImageCacheSizeInfoTileState extends State<_ImageCacheSizeInfoTile> {
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

  String _formatSize(double mb) {
    if (mb < 1) {
      return '${(mb * 1024).toStringAsFixed(1)} KB';
    }
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final sizeText = _cacheSizeMB != null
        ? _formatSize(_cacheSizeMB!)
        : '加载中...';

    return ListTile(
      leading: const Icon(Icons.image_outlined),
      title: const Text('图片缓存'),
      subtitle: Text('当前大小: $sizeText'),
      trailing: IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: _loadCacheSize,
        tooltip: '刷新',
      ),
    );
  }
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
