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
              sections: [
                _DataSection(
                  title: '基本信息',
                  data: {
                    'id': track.id.toString(),
                    'sourceId': track.sourceId,
                    'sourceType': track.sourceType.name,
                    'title': track.title,
                    'artist': track.artist ?? 'null',
                    'durationMs': track.durationMs?.toString() ?? 'null',
                  },
                ),
                _DataSection(
                  title: '媒体信息',
                  data: {
                    'thumbnailUrl': _truncate(track.thumbnailUrl, 60),
                    'audioUrl': _truncate(track.audioUrl, 60),
                    'audioUrlExpiry': track.audioUrlExpiry?.toIso8601String() ?? 'null',
                    'hasValidAudioUrl': track.hasValidAudioUrl.toString(),
                  },
                ),
                _DataSection(
                  title: '可用性',
                  data: {
                    'isAvailable': track.isAvailable.toString(),
                    'unavailableReason': track.unavailableReason ?? 'null',
                  },
                ),
                _DataSection(
                  title: '缓存与下载',
                  data: {
                    'cachedPath': _truncate(track.cachedPath, 60),
                    'playlistIds': track.playlistIds.isEmpty
                        ? '[]'
                        : track.playlistIds.join(', '),
                    'downloadPaths': track.downloadPaths.isEmpty
                        ? '[]'
                        : track.downloadPaths.map((p) => _truncate(p, 40)).join('\n'),
                  },
                ),
                _DataSection(
                  title: '分P信息',
                  data: {
                    'cid': track.cid?.toString() ?? 'null',
                    'pageNum': track.pageNum?.toString() ?? 'null',
                    'parentTitle': track.parentTitle ?? 'null',
                    'isPartOfMultiPage': track.isPartOfMultiPage.toString(),
                  },
                ),
                _DataSection(
                  title: '时间戳',
                  data: {
                    'createdAt': track.createdAt.toIso8601String(),
                    'updatedAt': track.updatedAt?.toIso8601String() ?? 'null',
                  },
                ),
              ],
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
              sections: [
                _DataSection(
                  title: '基本信息',
                  data: {
                    'id': playlist.id.toString(),
                    'name': playlist.name,
                    'description': playlist.description ?? 'null',
                  },
                ),
                _DataSection(
                  title: '封面',
                  data: {
                    'coverUrl': _truncate(playlist.coverUrl, 60),
                    'coverLocalPath': _truncate(playlist.coverLocalPath, 60),
                  },
                ),
                _DataSection(
                  title: '导入设置',
                  data: {
                    'isImported': playlist.isImported.toString(),
                    'sourceUrl': _truncate(playlist.sourceUrl, 60),
                    'importSourceType': playlist.importSourceType?.name ?? 'null',
                    'refreshIntervalHours': playlist.refreshIntervalHours?.toString() ?? 'null',
                    'lastRefreshed': playlist.lastRefreshed?.toIso8601String() ?? 'null',
                    'notifyOnUpdate': playlist.notifyOnUpdate.toString(),
                    'needsRefresh': playlist.needsRefresh.toString(),
                  },
                ),
                _DataSection(
                  title: '歌曲列表',
                  data: {
                    'trackCount': playlist.trackIds.length.toString(),
                    'trackIds': playlist.trackIds.isEmpty
                        ? '[]'
                        : '${playlist.trackIds.take(10).join(', ')}${playlist.trackIds.length > 10 ? '... (${playlist.trackIds.length} total)' : ''}',
                  },
                ),
                _DataSection(
                  title: '时间戳',
                  data: {
                    'createdAt': playlist.createdAt.toIso8601String(),
                    'updatedAt': playlist.updatedAt?.toIso8601String() ?? 'null',
                  },
                ),
              ],
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
              subtitle: '${queue.length} 首歌曲',
              sections: [
                _DataSection(
                  title: '基本信息',
                  data: {
                    'id': queue.id.toString(),
                    'length': queue.length.toString(),
                    'isEmpty': queue.isEmpty.toString(),
                  },
                ),
                _DataSection(
                  title: '播放状态',
                  data: {
                    'currentIndex': queue.currentIndex.toString(),
                    'currentTrackId': queue.currentTrackId?.toString() ?? 'null',
                    'lastPositionMs': queue.lastPositionMs.toString(),
                    'lastVolume': queue.lastVolume.toStringAsFixed(2),
                    'hasNext': queue.hasNext.toString(),
                    'hasPrevious': queue.hasPrevious.toString(),
                  },
                ),
                _DataSection(
                  title: '播放模式',
                  data: {
                    'isShuffleEnabled': queue.isShuffleEnabled.toString(),
                    'loopMode': queue.loopMode.name,
                    'originalOrder': queue.originalOrder == null
                        ? 'null'
                        : '${queue.originalOrder!.take(10).join(', ')}${queue.originalOrder!.length > 10 ? '...' : ''}',
                  },
                ),
                _DataSection(
                  title: '队列内容',
                  data: {
                    'trackIds': queue.trackIds.isEmpty
                        ? '[]'
                        : '${queue.trackIds.take(10).join(', ')}${queue.trackIds.length > 10 ? '... (${queue.trackIds.length} total)' : ''}',
                  },
                ),
                _DataSection(
                  title: '时间戳',
                  data: {
                    'lastUpdated': queue.lastUpdated?.toIso8601String() ?? 'null',
                  },
                ),
              ],
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
              subtitle: '主题: ${setting.themeMode.name}',
              sections: [
                _DataSection(
                  title: '主题设置',
                  data: {
                    'id': setting.id.toString(),
                    'themeModeIndex': setting.themeModeIndex.toString(),
                    'themeMode': setting.themeMode.name,
                  },
                ),
                _DataSection(
                  title: '颜色设置',
                  data: {
                    'primaryColor': setting.primaryColor != null
                        ? '#${setting.primaryColor!.toRadixString(16).padLeft(8, '0').toUpperCase()}'
                        : 'null',
                    'secondaryColor': setting.secondaryColor != null
                        ? '#${setting.secondaryColor!.toRadixString(16).padLeft(8, '0').toUpperCase()}'
                        : 'null',
                    'backgroundColor': setting.backgroundColor != null
                        ? '#${setting.backgroundColor!.toRadixString(16).padLeft(8, '0').toUpperCase()}'
                        : 'null',
                    'surfaceColor': setting.surfaceColor != null
                        ? '#${setting.surfaceColor!.toRadixString(16).padLeft(8, '0').toUpperCase()}'
                        : 'null',
                    'textColor': setting.textColor != null
                        ? '#${setting.textColor!.toRadixString(16).padLeft(8, '0').toUpperCase()}'
                        : 'null',
                    'cardColor': setting.cardColor != null
                        ? '#${setting.cardColor!.toRadixString(16).padLeft(8, '0').toUpperCase()}'
                        : 'null',
                  },
                ),
                _DataSection(
                  title: '存储设置',
                  data: {
                    'customCacheDir': setting.customCacheDir ?? 'null',
                    'maxCacheSizeMB': setting.maxCacheSizeMB.toString(),
                    'customDownloadDir': setting.customDownloadDir ?? 'null',
                  },
                ),
                _DataSection(
                  title: '导入设置',
                  data: {
                    'autoRefreshImports': setting.autoRefreshImports.toString(),
                    'defaultRefreshIntervalHours': setting.defaultRefreshIntervalHours.toString(),
                  },
                ),
                _DataSection(
                  title: '下载设置',
                  data: {
                    'maxConcurrentDownloads': setting.maxConcurrentDownloads.toString(),
                    'downloadImageOptionIndex': setting.downloadImageOptionIndex.toString(),
                    'downloadImageOption': setting.downloadImageOption.name,
                  },
                ),
                _DataSection(
                  title: '其他设置',
                  data: {
                    'autoScrollToCurrentTrack': setting.autoScrollToCurrentTrack.toString(),
                    'enabledSources': setting.enabledSources.join(', '),
                    'hotkeyConfig': setting.hotkeyConfig ?? 'null',
                  },
                ),
              ],
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
      future: isar.searchHistorys.where().sortByTimestampDesc().findAll(),
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
              sections: [
                _DataSection(
                  title: '搜索记录',
                  data: {
                    'id': history.id.toString(),
                    'query': history.query,
                    'timestamp': history.timestamp.toIso8601String(),
                  },
                ),
              ],
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
              subtitle: 'TrackID: ${task.trackId} | ${task.status.name}',
              sections: [
                _DataSection(
                  title: '基本信息',
                  data: {
                    'id': task.id.toString(),
                    'trackId': task.trackId.toString(),
                    'playlistId': task.playlistId?.toString() ?? 'null',
                    'playlistName': task.playlistName ?? 'null',
                    'order': task.order?.toString() ?? 'null',
                    'priority': task.priority.toString(),
                  },
                ),
                _DataSection(
                  title: '下载状态',
                  data: {
                    'status': task.status.name,
                    'progress': '${(task.progress * 100).toStringAsFixed(1)}%',
                    'downloadedBytes': _formatBytes(task.downloadedBytes),
                    'totalBytes': task.totalBytes != null ? _formatBytes(task.totalBytes!) : 'null',
                  },
                ),
                _DataSection(
                  title: '文件信息',
                  data: {
                    'tempFilePath': _truncate(task.tempFilePath, 60),
                    'canResume': task.canResume.toString(),
                  },
                ),
                _DataSection(
                  title: '错误信息',
                  data: {
                    'errorMessage': task.errorMessage ?? 'null',
                  },
                ),
                _DataSection(
                  title: '时间戳',
                  data: {
                    'createdAt': task.createdAt.toIso8601String(),
                    'completedAt': task.completedAt?.toIso8601String() ?? 'null',
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// 截断字符串
String _truncate(String? value, int maxLength) {
  if (value == null) return 'null';
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}...';
}

/// 格式化字节数
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
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

/// 数据分组
class _DataSection {
  final String title;
  final Map<String, String> data;

  const _DataSection({required this.title, required this.data});
}

/// 数据卡片
class _DataCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_DataSection> sections;

  const _DataCard({
    required this.title,
    required this.subtitle,
    required this.sections,
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
              children: sections.map((section) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 标题
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        section.title,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    // Section 数据
                    ...section.data.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 180,
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
                              child: SelectableText(
                                entry.value,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
