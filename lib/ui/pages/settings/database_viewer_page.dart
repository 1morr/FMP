import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../../i18n/strings.g.dart';
import '../../../providers/database_provider.dart';
import '../../../data/models/track.dart';
import '../../../data/models/playlist.dart';
import '../../../data/models/play_queue.dart';
import '../../../data/models/settings.dart';
import '../../../data/models/search_history.dart';
import '../../../data/models/download_task.dart';
import '../../../data/models/play_history.dart';
import '../../../data/models/radio_station.dart';

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
    'PlayHistory',
    'Settings',
    'SearchHistory',
    'DownloadTask',
    'RadioStation',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t.databaseViewer.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.databaseViewer.refresh,
            onPressed: () => setState(() {}),
          ),
          const SizedBox(width: 8),
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
      error: (e, _) => Center(child: Text(t.databaseViewer.loadFailed(error: e.toString()))),
      data: (isar) => _buildCollectionData(isar),
    );
  }

  Widget _buildCollectionData(Isar isar) {
    return switch (_selectedCollection) {
      'Track' => _TrackListView(isar: isar),
      'Playlist' => _PlaylistListView(isar: isar),
      'PlayQueue' => _PlayQueueListView(isar: isar),
      'PlayHistory' => _PlayHistoryListView(isar: isar),
      'Settings' => _SettingsListView(isar: isar),
      'SearchHistory' => _SearchHistoryListView(isar: isar),
      'DownloadTask' => _DownloadTaskListView(isar: isar),
      'RadioStation' => _RadioStationListView(isar: isar),
      _ => Center(child: Text(t.databaseViewer.unknownCollection)),
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
          headerText: t.databaseViewer.recordCount(count: tracks.length),
          itemBuilder: (index) {
            final track = tracks[index];
            return _DataCard(
              title: track.title,
              subtitle: 'ID: ${track.id}',
              sections: [
                _DataSection(
                  title: t.databaseViewer.basicInfo,
                  data: {
                    'id': track.id.toString(),
                    'sourceId': track.sourceId,
                    'sourceType': track.sourceType.name,
                    'title': track.title,
                    'artist': track.artist ?? 'null',
                    'ownerId': track.ownerId?.toString() ?? 'null',
                    'channelId': track.channelId ?? 'null',
                    'durationMs': track.durationMs?.toString() ?? 'null',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.mediaInfo,
                  data: {
                    'thumbnailUrl': _truncate(track.thumbnailUrl, 60),
                    'audioUrl': _truncate(track.audioUrl, 60),
                    'audioUrlExpiry': track.audioUrlExpiry?.toIso8601String() ?? 'null',
                    'hasValidAudioUrl': track.hasValidAudioUrl.toString(),
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.availability,
                  data: {
                    'isAvailable': track.isAvailable.toString(),
                    'unavailableReason': track.unavailableReason ?? 'null',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.cacheAndDownload,
                  data: {
                    'playlistInfo': track.playlistInfo.isEmpty
                        ? '[]'
                        : track.playlistInfo.map((i) => 'playlist=${i.playlistId}(${i.playlistName}): ${_truncate(i.downloadPath, 50)}').join('\n'),
                    'allPlaylistIds': track.allPlaylistIds.isEmpty
                        ? '[]'
                        : track.allPlaylistIds.join(', '),
                    'hasAnyDownload': track.hasAnyDownload.toString(),
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.partInfo,
                  data: {
                    'cid': track.cid?.toString() ?? 'null',
                    'pageNum': track.pageNum?.toString() ?? 'null',
                    'pageCount': track.pageCount?.toString() ?? 'null',
                    'parentTitle': track.parentTitle ?? 'null',
                    'isPartOfMultiPage': track.isPartOfMultiPage.toString(),
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.timestamps,
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
          headerText: t.databaseViewer.recordCount(count: playlists.length),
          itemBuilder: (index) {
            final playlist = playlists[index];
            return _DataCard(
              title: playlist.name,
              subtitle: 'ID: ${playlist.id}',
              sections: [
                _DataSection(
                  title: t.databaseViewer.basicInfo,
                  data: {
                    'id': playlist.id.toString(),
                    'name': playlist.name,
                    'description': playlist.description ?? 'null',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.cover,
                  data: {
                    'coverUrl': _truncate(playlist.coverUrl, 60),
                    'hasCustomCover': playlist.hasCustomCover.toString(),
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.importSettings,
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
                  title: 'Mix 播放列表',
                  data: {
                    'isMix': playlist.isMix.toString(),
                    'mixPlaylistId': playlist.mixPlaylistId ?? 'null',
                    'mixSeedVideoId': playlist.mixSeedVideoId ?? 'null',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.trackList,
                  data: {
                    'trackCount': playlist.trackIds.length.toString(),
                    'trackIds': playlist.trackIds.isEmpty
                        ? '[]'
                        : '${playlist.trackIds.take(10).join(', ')}${playlist.trackIds.length > 10 ? '... (${playlist.trackIds.length} total)' : ''}',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.sortAndTime,
                  data: {
                    'sortOrder': playlist.sortOrder.toString(),
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
          headerText: t.databaseViewer.recordCount(count: queues.length),
          itemBuilder: (index) {
            final queue = queues[index];
            return _DataCard(
              title: '${t.databaseViewer.playQueue} #${queue.id}',
              subtitle: '${queue.length} tracks',
              sections: [
                _DataSection(
                  title: t.databaseViewer.basicInfo,
                  data: {
                    'id': queue.id.toString(),
                    'length': queue.length.toString(),
                    'isEmpty': queue.isEmpty.toString(),
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.playbackState,
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
                  title: t.databaseViewer.playbackMode,
                  data: {
                    'isShuffleEnabled': queue.isShuffleEnabled.toString(),
                    'loopMode': queue.loopMode.name,
                    'originalOrder': queue.originalOrder == null
                        ? 'null'
                        : '${queue.originalOrder!.take(10).join(', ')}${queue.originalOrder!.length > 10 ? '...' : ''}',
                  },
                ),
                _DataSection(
                  title: 'Mix 模式',
                  data: {
                    'isMixMode': queue.isMixMode.toString(),
                    'mixPlaylistId': queue.mixPlaylistId ?? 'null',
                    'mixSeedVideoId': queue.mixSeedVideoId ?? 'null',
                    'mixTitle': queue.mixTitle ?? 'null',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.queueContent,
                  data: {
                    'trackIds': queue.trackIds.isEmpty
                        ? '[]'
                        : '${queue.trackIds.take(10).join(', ')}${queue.trackIds.length > 10 ? '... (${queue.trackIds.length} total)' : ''}',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.timestamps,
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
          headerText: t.databaseViewer.recordCount(count: settings.length),
          itemBuilder: (index) {
            final setting = settings[index];
            return _DataCard(
              title: t.databaseViewer.setting(id: setting.id.toString()),
              subtitle: t.databaseViewer.theme(name: setting.themeMode.name),
              sections: [
                _DataSection(
                  title: t.databaseViewer.themeSettings,
                  data: {
                    'id': setting.id.toString(),
                    'themeModeIndex': setting.themeModeIndex.toString(),
                    'themeMode': setting.themeMode.name,
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.colorSettings,
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
                  title: t.databaseViewer.storageSettings,
                  data: {
                    'maxCacheSizeMB': setting.maxCacheSizeMB.toString(),
                    'customDownloadDir': setting.customDownloadDir ?? 'null',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.importSettings,
                  data: {
                    'autoRefreshImports': setting.autoRefreshImports.toString(),
                    'defaultRefreshIntervalHours': setting.defaultRefreshIntervalHours.toString(),
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.downloadSettings,
                  data: {
                    'maxConcurrentDownloads': setting.maxConcurrentDownloads.toString(),
                    'downloadImageOptionIndex': setting.downloadImageOptionIndex.toString(),
                    'downloadImageOption': setting.downloadImageOption.name,
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.playbackSettings,
                  data: {
                    'autoScrollToCurrentTrack': setting.autoScrollToCurrentTrack.toString(),
                    'rememberPlaybackPosition': setting.rememberPlaybackPosition.toString(),
                    'restartRewindSeconds': '${setting.restartRewindSeconds}s',
                    'tempPlayRewindSeconds': '${setting.tempPlayRewindSeconds}s',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.audioQualitySettings,
                  data: {
                    'audioQualityLevelIndex': setting.audioQualityLevelIndex.toString(),
                    'audioQualityLevel': setting.audioQualityLevel.name,
                    'audioFormatPriority': setting.audioFormatPriority,
                    'youtubeStreamPriority': setting.youtubeStreamPriority,
                    'bilibiliStreamPriority': setting.bilibiliStreamPriority,
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.desktopSettings,
                  data: {
                    'minimizeToTrayOnClose': setting.minimizeToTrayOnClose.toString(),
                    'enableGlobalHotkeys': setting.enableGlobalHotkeys.toString(),
                    'hotkeyConfig': setting.hotkeyConfig ?? 'null',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.otherSettings,
                  data: {
                    'enabledSources': setting.enabledSources.join(', '),
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

/// PlayHistory 列表视图
class _PlayHistoryListView extends StatelessWidget {
  final Isar isar;

  const _PlayHistoryListView({required this.isar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlayHistory>>(
      future: isar.playHistorys.where().sortByPlayedAtDesc().findAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final histories = snapshot.data ?? [];
        return _buildList(
          context,
          itemCount: histories.length,
          headerText: t.databaseViewer.recordCount(count: histories.length),
          itemBuilder: (index) {
            final history = histories[index];
            return _DataCard(
              title: history.title,
              subtitle: 'ID: ${history.id} | ${_formatDateTime(history.playedAt)}',
              sections: [
                _DataSection(
                  title: t.databaseViewer.basicInfo,
                  data: {
                    'id': history.id.toString(),
                    'sourceId': history.sourceId,
                    'sourceType': history.sourceType.name,
                    'cid': history.cid?.toString() ?? 'null',
                    'trackKey': history.trackKey,
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.mediaInfo,
                  data: {
                    'title': history.title,
                    'artist': history.artist ?? 'null',
                    'durationMs': history.durationMs?.toString() ?? 'null',
                    'formattedDuration': history.formattedDuration,
                    'thumbnailUrl': _truncate(history.thumbnailUrl, 60),
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.playbackTime,
                  data: {
                    'playedAt': history.playedAt.toIso8601String(),
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
          headerText: t.databaseViewer.recordCount(count: histories.length),
          itemBuilder: (index) {
            final history = histories[index];
            return _DataCard(
              title: history.query,
              subtitle: 'ID: ${history.id}',
              sections: [
                _DataSection(
                  title: t.databaseViewer.searchHistory,
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
          headerText: t.databaseViewer.recordCount(count: tasks.length),
          itemBuilder: (index) {
            final task = tasks[index];
            return _DataCard(
              title: '${t.databaseViewer.downloadTask} #${task.id}',
              subtitle: 'TrackID: ${task.trackId} | ${task.status.name}',
              sections: [
                _DataSection(
                  title: t.databaseViewer.basicInfo,
                  data: {
                    'id': task.id.toString(),
                    'trackId': task.trackId.toString(),
                    'playlistId': task.playlistId?.toString() ?? 'null',
                    'playlistName': task.playlistName ?? 'null',
                    'priority': task.priority.toString(),
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.downloadStatus,
                  data: {
                    'status': task.status.name,
                    'progress': '${(task.progress * 100).toStringAsFixed(1)}%',
                    'downloadedBytes': _formatBytes(task.downloadedBytes),
                    'totalBytes': task.totalBytes != null ? _formatBytes(task.totalBytes!) : 'null',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.fileInfo,
                  data: {
                    'savePath': _truncate(task.savePath, 80),
                    'tempFilePath': _truncate(task.tempFilePath, 80),
                    'canResume': task.canResume.toString(),
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.errorInfo,
                  data: {
                    'errorMessage': task.errorMessage ?? 'null',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.timestamps,
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

/// RadioStation 列表视图
class _RadioStationListView extends StatelessWidget {
  final Isar isar;

  const _RadioStationListView({required this.isar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RadioStation>>(
      future: isar.radioStations.where().findAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final stations = snapshot.data ?? [];
        return _buildList(
          context,
          itemCount: stations.length,
          headerText: t.databaseViewer.recordCount(count: stations.length),
          itemBuilder: (index) {
            final station = stations[index];
            return _DataCard(
              title: station.title,
              subtitle: 'ID: ${station.id} | ${station.sourceType.name}',
              sections: [
                _DataSection(
                  title: t.databaseViewer.basicInfo,
                  data: {
                    'id': station.id.toString(),
                    'url': _truncate(station.url, 60),
                    'title': station.title,
                    'sourceType': station.sourceType.name,
                    'sourceId': station.sourceId,
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.streamerInfo,
                  data: {
                    'hostName': station.hostName ?? 'null',
                    'hostUid': station.hostUid?.toString() ?? 'null',
                    'hostAvatarUrl': _truncate(station.hostAvatarUrl, 60),
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.mediaInfo,
                  data: {
                    'thumbnailUrl': _truncate(station.thumbnailUrl, 60),
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.sortAndFavorite,
                  data: {
                    'sortOrder': station.sortOrder.toString(),
                    'isFavorite': station.isFavorite.toString(),
                    'note': station.note ?? 'null',
                  },
                ),
                _DataSection(
                  title: t.databaseViewer.timestamps,
                  data: {
                    'createdAt': station.createdAt.toIso8601String(),
                    'lastPlayedAt': station.lastPlayedAt?.toIso8601String() ?? 'null',
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
            t.databaseViewer.noData,
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
