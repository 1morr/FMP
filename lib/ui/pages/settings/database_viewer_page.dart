import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../../providers/database_provider.dart';
import '../../../data/models/track.dart';
import '../../../data/models/playlist.dart';
import '../../../data/models/play_queue.dart';
import '../../../data/models/settings.dart';
import '../../../data/models/search_history.dart';
import '../../../data/models/download_task.dart';
import '../../../data/models/playlist_download_task.dart';

/// 数据库查看页面
class DatabaseViewerPage extends ConsumerStatefulWidget {
  const DatabaseViewerPage({super.key});

  @override
  ConsumerState<DatabaseViewerPage> createState() => _DatabaseViewerPageState();
}

class _DatabaseViewerPageState extends ConsumerState<DatabaseViewerPage> {
  String _selectedCollection = 'Track';

  final List<String> _collections = [
    'Track',
    'Playlist',
    'PlayQueue',
    'Settings',
    'SearchHistory',
    'DownloadTask',
    'PlaylistDownloadTask',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据库查看器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          // 集合选择器
          _buildCollectionSelector(),
          const Divider(height: 1),
          // 数据列表
          Expanded(
            child: _buildDataView(),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ScrollConfiguration(
        // 允许鼠标拖拽滚动（桌面端支持）
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
            children: _collections.map((collection) {
              final isSelected = collection == _selectedCollection;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(collection),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedCollection = collection);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildDataView() {
    final dbAsync = ref.watch(databaseProvider);

    return dbAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('数据库加载失败: $e')),
      data: (isar) => _buildCollectionData(isar),
    );
  }

  Widget _buildCollectionData(Isar isar) {
    return switch (_selectedCollection) {
      'Track' => _TrackListView(isar: isar),
      'Playlist' => _PlaylistListView(isar: isar),
      'PlayQueue' => _PlayQueueListView(isar: isar),
      'Settings' => _SettingsListView(isar: isar),
      'SearchHistory' => _SearchHistoryListView(isar: isar),
      'DownloadTask' => _DownloadTaskListView(isar: isar),
      'PlaylistDownloadTask' => _PlaylistDownloadTaskListView(isar: isar),
      _ => const Center(child: Text('未知集合')),
    };
  }
}

/// Track 列表视图
class _TrackListView extends StatelessWidget {
  final Isar isar;

  const _TrackListView({required this.isar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Track>>(
      future: isar.tracks.where().findAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final tracks = snapshot.data ?? [];
        return _buildList(
          context,
          itemCount: tracks.length,
          headerText: '共 ${tracks.length} 条记录',
          itemBuilder: (index) {
            final track = tracks[index];
            return _DataCard(
              title: track.title,
              subtitle: 'ID: ${track.id}',
              data: {
                'artist': track.artist ?? 'null',
                'sourceId': track.sourceId,
                'sourceType': track.sourceType.name,
                'cid': track.cid?.toString() ?? 'null',
                'durationMs': '${track.durationMs}ms',
                'isDownloaded': track.isDownloaded.toString(),
                'downloadedPath': track.downloadedPath ?? 'null',
                'createdAt': track.createdAt.toIso8601String(),
              },
            );
          },
        );
      },
    );
  }
}

/// Playlist 列表视图
class _PlaylistListView extends StatelessWidget {
  final Isar isar;

  const _PlaylistListView({required this.isar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Playlist>>(
      future: isar.playlists.where().findAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final playlists = snapshot.data ?? [];
        return _buildList(
          context,
          itemCount: playlists.length,
          headerText: '共 ${playlists.length} 条记录',
          itemBuilder: (index) {
            final playlist = playlists[index];
            return _DataCard(
              title: playlist.name,
              subtitle: 'ID: ${playlist.id}',
              data: {
                'description': playlist.description ?? 'null',
                'trackCount': playlist.trackIds.length.toString(),
                'trackIds': playlist.trackIds.take(5).join(', ') +
                    (playlist.trackIds.length > 5 ? '...' : ''),
                'coverUrl': playlist.coverUrl ?? 'null',
                'createdAt': playlist.createdAt.toIso8601String(),
              },
            );
          },
        );
      },
    );
  }
}

/// PlayQueue 列表视图
class _PlayQueueListView extends StatelessWidget {
  final Isar isar;

  const _PlayQueueListView({required this.isar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlayQueue>>(
      future: isar.playQueues.where().findAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final queues = snapshot.data ?? [];
        return _buildList(
          context,
          itemCount: queues.length,
          headerText: '共 ${queues.length} 条记录',
          itemBuilder: (index) {
            final queue = queues[index];
            return _DataCard(
              title: '播放队列 #${queue.id}',
              subtitle: 'ID: ${queue.id}',
              data: {
                'trackCount': queue.trackIds.length.toString(),
                'trackIds': queue.trackIds.take(5).join(', ') +
                    (queue.trackIds.length > 5 ? '...' : ''),
                'currentIndex': queue.currentIndex.toString(),
                'isShuffleEnabled': queue.isShuffleEnabled.toString(),
                'loopMode': queue.loopMode.name,
              },
            );
          },
        );
      },
    );
  }
}

/// Settings 列表视图
class _SettingsListView extends StatelessWidget {
  final Isar isar;

  const _SettingsListView({required this.isar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Settings>>(
      future: isar.settings.where().findAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final settings = snapshot.data ?? [];
        return _buildList(
          context,
          itemCount: settings.length,
          headerText: '共 ${settings.length} 条记录',
          itemBuilder: (index) {
            final setting = settings[index];
            return _DataCard(
              title: '设置 #${setting.id}',
              subtitle: 'ID: ${setting.id}',
              data: {
                'themeMode': setting.themeMode.toString(),
                'primaryColor': setting.primaryColor?.toString() ?? 'null',
                'autoScrollToCurrentTrack':
                    setting.autoScrollToCurrentTrack.toString(),
                'maxConcurrentDownloads':
                    setting.maxConcurrentDownloads.toString(),
                'downloadImageOption': setting.downloadImageOption.toString(),
              },
            );
          },
        );
      },
    );
  }
}

/// SearchHistory 列表视图
class _SearchHistoryListView extends StatelessWidget {
  final Isar isar;

  const _SearchHistoryListView({required this.isar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SearchHistory>>(
      future: isar.searchHistorys.where().findAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final histories = snapshot.data ?? [];
        return _buildList(
          context,
          itemCount: histories.length,
          headerText: '共 ${histories.length} 条记录',
          itemBuilder: (index) {
            final history = histories[index];
            return _DataCard(
              title: history.query,
              subtitle: 'ID: ${history.id}',
              data: {
                'timestamp': history.timestamp.toIso8601String(),
              },
            );
          },
        );
      },
    );
  }
}

/// DownloadTask 列表视图
class _DownloadTaskListView extends StatelessWidget {
  final Isar isar;

  const _DownloadTaskListView({required this.isar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DownloadTask>>(
      future: isar.downloadTasks.where().findAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final tasks = snapshot.data ?? [];
        return _buildList(
          context,
          itemCount: tasks.length,
          headerText: '共 ${tasks.length} 条记录',
          itemBuilder: (index) {
            final task = tasks[index];
            return _DataCard(
              title: '下载任务 #${task.id}',
              subtitle: 'TrackID: ${task.trackId}',
              data: {
                'trackId': task.trackId.toString(),
                'playlistDownloadTaskId': task.playlistDownloadTaskId?.toString() ?? 'null',
                'status': task.status.name,
                'progress': '${(task.progress * 100).toStringAsFixed(1)}%',
                'downloadedBytes': task.downloadedBytes.toString(),
                'totalBytes': task.totalBytes.toString(),
                'tempFilePath': task.tempFilePath ?? 'null',
                'errorMessage': task.errorMessage ?? 'null',
                'createdAt': task.createdAt.toIso8601String(),
              },
            );
          },
        );
      },
    );
  }
}

/// PlaylistDownloadTask 列表视图
class _PlaylistDownloadTaskListView extends StatelessWidget {
  final Isar isar;

  const _PlaylistDownloadTaskListView({required this.isar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlaylistDownloadTask>>(
      future: isar.playlistDownloadTasks.where().findAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final tasks = snapshot.data ?? [];
        return _buildList(
          context,
          itemCount: tasks.length,
          headerText: '共 ${tasks.length} 条记录',
          itemBuilder: (index) {
            final task = tasks[index];
            return _DataCard(
              title: task.playlistName,
              subtitle: 'ID: ${task.id}',
              data: {
                'playlistId': task.playlistId.toString(),
                'totalTracks': task.totalTracks.toString(),
                'trackIds': task.trackIds.take(5).join(', ') +
                    (task.trackIds.length > 5 ? '...' : ''),
                'status': task.status.name,
                'createdAt': task.createdAt.toIso8601String(),
              },
            );
          },
        );
      },
    );
  }
}

/// 构建列表
Widget _buildList(
  BuildContext context, {
  required int itemCount,
  required String headerText,
  required Widget Function(int index) itemBuilder,
}) {
  if (itemCount == 0) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无数据',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }

  return Column(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
          headerText,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: itemCount,
          itemBuilder: (context, index) => itemBuilder(index),
        ),
      ),
    ],
  );
}

/// 数据卡片
class _DataCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Map<String, String> data;

  const _DataCard({
    required this.title,
    required this.subtitle,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: colorScheme.outline,
            fontSize: 12,
          ),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: data.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 160,
                        child: Text(
                          '${entry.key}:',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
