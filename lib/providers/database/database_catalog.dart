import 'package:isar/isar.dart';

import '../../data/models/models.dart';
import '../../i18n/strings.g.dart';

class DatabaseViewerSection {
  const DatabaseViewerSection({
    required this.title,
    required this.data,
  });

  final String title;
  final Map<String, String> data;
}

class FmpDatabaseCollection {
  const FmpDatabaseCollection({
    required this.name,
    required this.schema,
    required this.query,
    required this.title,
    required this.subtitle,
    required this.sections,
  });

  final String name;
  final CollectionSchema<dynamic> schema;
  final Future<List<Object>> Function(Isar isar) query;
  final String Function(Object item) title;
  final String Function(Object item) subtitle;
  final List<DatabaseViewerSection> Function(Object item) sections;
}

FmpDatabaseCollection _collection<T extends Object>({
  required String name,
  required CollectionSchema<dynamic> schema,
  required Future<List<T>> Function(Isar isar) query,
  required String Function(T item) title,
  required String Function(T item) subtitle,
  required List<DatabaseViewerSection> Function(T item) sections,
}) {
  return FmpDatabaseCollection(
    name: name,
    schema: schema,
    query: (isar) async => List<Object>.unmodifiable(await query(isar)),
    title: (item) => title(item as T),
    subtitle: (item) => subtitle(item as T),
    sections: (item) => sections(item as T),
  );
}

final List<FmpDatabaseCollection> fmpDatabaseCollections = [
  _collection<Track>(
    name: 'Track',
    schema: TrackSchema,
    query: (isar) => isar.tracks.where().findAll(),
    title: (track) => track.title,
    subtitle: (track) => 'ID: ${track.id}',
    sections: _trackSections,
  ),
  _collection<Playlist>(
    name: 'Playlist',
    schema: PlaylistSchema,
    query: (isar) => isar.playlists.where().findAll(),
    title: (playlist) => playlist.name,
    subtitle: (playlist) => 'ID: ${playlist.id}',
    sections: _playlistSections,
  ),
  _collection<PlayQueue>(
    name: 'PlayQueue',
    schema: PlayQueueSchema,
    query: (isar) => isar.playQueues.where().findAll(),
    title: (queue) => '${t.databaseViewer.playQueue} #${queue.id}',
    subtitle: (queue) => '${queue.length} tracks',
    sections: _playQueueSections,
  ),
  _collection<PlayHistory>(
    name: 'PlayHistory',
    schema: PlayHistorySchema,
    query: (isar) => isar.playHistorys.where().sortByPlayedAtDesc().findAll(),
    title: (history) => history.title,
    subtitle: (history) =>
        'ID: ${history.id} | ${_formatDateTime(history.playedAt)}',
    sections: _playHistorySections,
  ),
  _collection<Settings>(
    name: 'Settings',
    schema: SettingsSchema,
    query: (isar) => isar.settings.where().findAll(),
    title: (setting) => t.databaseViewer.setting(id: setting.id.toString()),
    subtitle: (setting) => t.databaseViewer.theme(name: setting.themeMode.name),
    sections: _settingsSections,
  ),
  _collection<SearchHistory>(
    name: 'SearchHistory',
    schema: SearchHistorySchema,
    query: (isar) =>
        isar.searchHistorys.where().sortByTimestampDesc().findAll(),
    title: (history) => history.query,
    subtitle: (history) => 'ID: ${history.id}',
    sections: _searchHistorySections,
  ),
  _collection<DownloadTask>(
    name: 'DownloadTask',
    schema: DownloadTaskSchema,
    query: (isar) => isar.downloadTasks.where().findAll(),
    title: (task) => '${t.databaseViewer.downloadTask} #${task.id}',
    subtitle: (task) => 'TrackID: ${task.trackId} | ${task.status.name}',
    sections: _downloadTaskSections,
  ),
  _collection<RadioStation>(
    name: 'RadioStation',
    schema: RadioStationSchema,
    query: (isar) => isar.radioStations.where().findAll(),
    title: (station) => station.title,
    subtitle: (station) => 'ID: ${station.id} | ${station.sourceType.name}',
    sections: _radioStationSections,
  ),
  _collection<LyricsMatch>(
    name: 'LyricsMatch',
    schema: LyricsMatchSchema,
    query: (isar) => isar.lyricsMatchs.where().findAll(),
    title: (match) => '${t.databaseViewer.lyricsMatch} #${match.id}',
    subtitle: (match) => match.trackUniqueKey,
    sections: _lyricsMatchSections,
  ),
  _collection<LyricsTitleParseCache>(
    name: 'LyricsTitleParseCache',
    schema: LyricsTitleParseCacheSchema,
    query: (isar) => isar.lyricsTitleParseCaches.where().findAll(),
    title: (cache) => cache.parsedTrackName,
    subtitle: (cache) => 'ID: ${cache.id} | ${cache.trackUniqueKey}',
    sections: _lyricsTitleParseCacheSections,
  ),
  _collection<Account>(
    name: 'Account',
    schema: AccountSchema,
    query: (isar) => isar.accounts.where().findAll(),
    title: (account) => account.userName ?? account.platform.name,
    subtitle: (account) => 'ID: ${account.id} | ${account.platform.name}',
    sections: _accountSections,
  ),
];

final List<CollectionSchema<dynamic>> fmpDatabaseSchemas = [
  for (final collection in fmpDatabaseCollections) collection.schema,
];

List<DatabaseViewerSection> _trackSections(Track track) {
  return [
    DatabaseViewerSection(
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
    DatabaseViewerSection(
      title: t.databaseViewer.mediaInfo,
      data: {
        'thumbnailUrl': _truncate(track.thumbnailUrl, 60),
        'audioUrl': _truncate(track.audioUrl, 60),
        'audioUrlExpiry': track.audioUrlExpiry?.toIso8601String() ?? 'null',
        'hasValidAudioUrl': track.hasValidAudioUrl.toString(),
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.availability,
      data: {
        'isAvailable': track.isAvailable.toString(),
        'isVip': track.isVip.toString(),
        'unavailableReason': track.unavailableReason ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.cacheAndDownload,
      data: {
        'playlistInfo (${track.playlistInfo.length})': track
                .playlistInfo.isEmpty
            ? '[]'
            : track.playlistInfo
                .asMap()
                .entries
                .map((e) =>
                    '[${e.key}] playlistId=${e.value.playlistId}, name="${e.value.playlistName}"\n    path: ${e.value.downloadPath}')
                .join('\n\n'),
        'allPlaylistIds': track.allPlaylistIds.isEmpty
            ? '[]'
            : track.allPlaylistIds.join(', '),
        'allDownloadPaths (${track.allDownloadPaths.length})':
            track.allDownloadPaths.isEmpty
                ? '[]'
                : track.allDownloadPaths
                    .asMap()
                    .entries
                    .map((e) => '[${e.key}] ${e.value}')
                    .join('\n'),
        'hasAnyDownload': track.hasAnyDownload.toString(),
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.partInfo,
      data: {
        'cid': track.cid?.toString() ?? 'null',
        'bilibiliAid': track.bilibiliAid?.toString() ?? 'null',
        'pageNum': track.pageNum?.toString() ?? 'null',
        'pageCount': track.pageCount?.toString() ?? 'null',
        'parentTitle': track.parentTitle ?? 'null',
        'isPartOfMultiPage': track.isPartOfMultiPage.toString(),
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.importOrigin,
      data: {
        'originalSongId': track.originalSongId ?? 'null',
        'originalSource': track.originalSource ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.timestamps,
      data: {
        'createdAt': track.createdAt.toIso8601String(),
        'updatedAt': track.updatedAt?.toIso8601String() ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: 'Computed',
      data: {
        'uniqueKey': track.uniqueKey,
        'groupKey': track.groupKey,
        'sourceKey': track.sourceKey,
        'sourcePageKey': track.sourcePageKey,
        'formattedDuration': track.formattedDuration,
      },
    ),
  ];
}

List<DatabaseViewerSection> _playlistSections(Playlist playlist) {
  return [
    DatabaseViewerSection(
      title: t.databaseViewer.basicInfo,
      data: {
        'id': playlist.id.toString(),
        'name': playlist.name,
        'description': playlist.description ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.cover,
      data: {
        'coverUrl': _truncate(playlist.coverUrl, 60),
        'hasCustomCover': playlist.hasCustomCover.toString(),
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.importSettings,
      data: {
        'isImported': playlist.isImported.toString(),
        'sourceUrl': _truncate(playlist.sourceUrl, 60),
        'importSourceType': playlist.importSourceType?.name ?? 'null',
        'refreshIntervalHours':
            playlist.refreshIntervalHours?.toString() ?? 'null',
        'lastRefreshed': playlist.lastRefreshed?.toIso8601String() ?? 'null',
        'notifyOnUpdate': playlist.notifyOnUpdate.toString(),
        'needsRefresh': playlist.needsRefresh.toString(),
        'ownerName': playlist.ownerName ?? 'null',
        'ownerUserId': playlist.ownerUserId ?? 'null',
        'useAuthForRefresh': playlist.useAuthForRefresh.toString(),
      },
    ),
    DatabaseViewerSection(
      title: 'Mix 播放列表',
      data: {
        'isMix': playlist.isMix.toString(),
        'mixPlaylistId': playlist.mixPlaylistId ?? 'null',
        'mixSeedVideoId': playlist.mixSeedVideoId ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.trackList,
      data: {
        'trackCount': playlist.trackCount.toString(),
        'trackIds': playlist.trackIds.isEmpty
            ? '[]'
            : '${playlist.trackIds.take(10).join(', ')}${playlist.trackIds.length > 10 ? '... (${playlist.trackIds.length} total)' : ''}',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.sortAndTime,
      data: {
        'sortOrder': playlist.sortOrder.toString(),
        'createdAt': playlist.createdAt.toIso8601String(),
        'updatedAt': playlist.updatedAt?.toIso8601String() ?? 'null',
      },
    ),
  ];
}

List<DatabaseViewerSection> _playQueueSections(PlayQueue queue) {
  return [
    DatabaseViewerSection(
      title: t.databaseViewer.basicInfo,
      data: {
        'id': queue.id.toString(),
        'length': queue.length.toString(),
        'isEmpty': queue.isEmpty.toString(),
        'isNotEmpty': queue.isNotEmpty.toString(),
      },
    ),
    DatabaseViewerSection(
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
    DatabaseViewerSection(
      title: t.databaseViewer.playbackMode,
      data: {
        'isShuffleEnabled': queue.isShuffleEnabled.toString(),
        'loopMode': queue.loopMode.name,
        'originalOrder': queue.originalOrder == null
            ? 'null'
            : '${queue.originalOrder!.take(10).join(', ')}${queue.originalOrder!.length > 10 ? '...' : ''}',
      },
    ),
    DatabaseViewerSection(
      title: 'Mix 模式',
      data: {
        'isMixMode': queue.isMixMode.toString(),
        'mixPlaylistId': queue.mixPlaylistId ?? 'null',
        'mixSeedVideoId': queue.mixSeedVideoId ?? 'null',
        'mixTitle': queue.mixTitle ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.queueContent,
      data: {
        'trackIds': queue.trackIds.isEmpty
            ? '[]'
            : '${queue.trackIds.take(10).join(', ')}${queue.trackIds.length > 10 ? '... (${queue.trackIds.length} total)' : ''}',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.timestamps,
      data: {
        'lastUpdated': queue.lastUpdated?.toIso8601String() ?? 'null',
      },
    ),
  ];
}

List<DatabaseViewerSection> _settingsSections(Settings setting) {
  return [
    DatabaseViewerSection(
      title: t.databaseViewer.themeSettings,
      data: {
        'id': setting.id.toString(),
        'themeModeIndex': setting.themeModeIndex.toString(),
        'themeMode': setting.themeMode.name,
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.colorSettings,
      data: {
        'primaryColor': _formatNullableColor(setting.primaryColor),
        'secondaryColor': _formatNullableColor(setting.secondaryColor),
        'backgroundColor': _formatNullableColor(setting.backgroundColor),
        'surfaceColor': _formatNullableColor(setting.surfaceColor),
        'textColor': _formatNullableColor(setting.textColor),
        'cardColor': _formatNullableColor(setting.cardColor),
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.storageSettings,
      data: {
        'maxCacheSizeMB': setting.maxCacheSizeMB.toString(),
        'customDownloadDir': setting.customDownloadDir ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.downloadSettings,
      data: {
        'maxConcurrentDownloads': setting.maxConcurrentDownloads.toString(),
        'downloadImageOptionIndex': setting.downloadImageOptionIndex.toString(),
        'downloadImageOption': setting.downloadImageOption.name,
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.playbackSettings,
      data: {
        'autoScrollToCurrentTrack': setting.autoScrollToCurrentTrack.toString(),
        'rememberPlaybackPosition': setting.rememberPlaybackPosition.toString(),
        'restartRewindSeconds': '${setting.restartRewindSeconds}s',
        'tempPlayRewindSeconds': '${setting.tempPlayRewindSeconds}s',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.audioQualitySettings,
      data: {
        'audioQualityLevelIndex': setting.audioQualityLevelIndex.toString(),
        'audioQualityLevel': setting.audioQualityLevel.name,
        'audioFormatPriority': setting.audioFormatPriority,
        'audioFormatPriorityList':
            setting.audioFormatPriorityList.map((e) => e.name).join(', '),
        'youtubeStreamPriority': setting.youtubeStreamPriority,
        'youtubeStreamPriorityList':
            setting.youtubeStreamPriorityList.map((e) => e.name).join(', '),
        'bilibiliStreamPriority': setting.bilibiliStreamPriority,
        'bilibiliStreamPriorityList':
            setting.bilibiliStreamPriorityList.map((e) => e.name).join(', '),
        'neteaseStreamPriority': setting.neteaseStreamPriority,
        'neteaseStreamPriorityList':
            setting.neteaseStreamPriorityList.map((e) => e.name).join(', '),
      },
    ),
    DatabaseViewerSection(
      title: 'Auth Settings',
      data: {
        'useBilibiliAuthForPlay': setting.useBilibiliAuthForPlay.toString(),
        'useYoutubeAuthForPlay': setting.useYoutubeAuthForPlay.toString(),
        'useNeteaseAuthForPlay': setting.useNeteaseAuthForPlay.toString(),
      },
    ),
    DatabaseViewerSection(
      title: 'Refresh Settings',
      data: {
        'rankingRefreshIntervalMinutes':
            '${setting.rankingRefreshIntervalMinutes} min',
        'homeRankingSourcePriority': setting.homeRankingSourcePriority,
        'homeRankingSourcePriorityList':
            setting.homeRankingSourcePriorityList.join(', '),
        'disabledHomeRankingSources': setting.disabledHomeRankingSources,
        'disabledHomeRankingSourcesSet':
            setting.disabledHomeRankingSourcesSet.join(', '),
        'radioRefreshIntervalMinutes':
            '${setting.radioRefreshIntervalMinutes} min',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.desktopSettings,
      data: {
        'minimizeToTrayOnClose': setting.minimizeToTrayOnClose.toString(),
        'enableGlobalHotkeys': setting.enableGlobalHotkeys.toString(),
        'launchAtStartup': setting.launchAtStartup.toString(),
        'launchMinimized': setting.launchMinimized.toString(),
        'hotkeyConfig': setting.hotkeyConfig ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.audioDeviceSettings,
      data: {
        'preferredAudioDeviceId': setting.preferredAudioDeviceId ?? 'null',
        'preferredAudioDeviceName': setting.preferredAudioDeviceName ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.lyricsSettings,
      data: {
        'autoMatchLyrics': setting.autoMatchLyrics.toString(),
        'allowPlainLyricsAutoMatch':
            setting.allowPlainLyricsAutoMatch.toString(),
        'maxLyricsCacheFiles': setting.maxLyricsCacheFiles.toString(),
        'lyricsDisplayModeIndex': setting.lyricsDisplayModeIndex.toString(),
        'lyricsDisplayMode': setting.lyricsDisplayMode.name,
        'lyricsSourcePriority': setting.lyricsSourcePriority,
        'lyricsSourcePriorityList': setting.lyricsSourcePriorityList.join(', '),
        'disabledLyricsSources': setting.disabledLyricsSources,
        'disabledLyricsSourcesSet': setting.disabledLyricsSourcesSet.join(', '),
        'lyricsAiTitleParsingModeIndex':
            setting.lyricsAiTitleParsingModeIndex.toString(),
        'lyricsAiTitleParsingMode': setting.lyricsAiTitleParsingMode.name,
        'lyricsAiEndpoint': setting.lyricsAiEndpoint,
        'lyricsAiModel': setting.lyricsAiModel,
        'lyricsAiTimeoutSeconds': '${setting.lyricsAiTimeoutSeconds}s',
        'lyricsWindowTextColor':
            _formatNullableColor(setting.lyricsWindowTextColor),
        'lyricsWindowSecondaryTextColor':
            _formatNullableColor(setting.lyricsWindowSecondaryTextColor),
        'lyricsWindowInactiveTextOpacity':
            setting.lyricsWindowInactiveTextOpacity?.toStringAsFixed(2) ??
                'null',
        'lyricsWindowOutlineEnabled':
            setting.lyricsWindowOutlineEnabled?.toString() ?? 'null',
        'lyricsWindowOutlineColor':
            _formatNullableColor(setting.lyricsWindowOutlineColor),
        'lyricsWindowOutlineWidth':
            setting.lyricsWindowOutlineWidth?.toStringAsFixed(2) ?? 'null',
        'lyricsWindowShadowEnabled':
            setting.lyricsWindowShadowEnabled?.toString() ?? 'null',
        'lyricsWindowShadowColor':
            _formatNullableColor(setting.lyricsWindowShadowColor),
        'lyricsWindowShadowBlurRadius':
            setting.lyricsWindowShadowBlurRadius?.toStringAsFixed(2) ?? 'null',
        'lyricsWindowShadowOffsetX':
            setting.lyricsWindowShadowOffsetX?.toStringAsFixed(2) ?? 'null',
        'lyricsWindowShadowOffsetY':
            setting.lyricsWindowShadowOffsetY?.toStringAsFixed(2) ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.uiSettings,
      data: {
        'fontFamily': setting.fontFamily ?? 'null',
        'locale': setting.locale ?? 'null',
      },
    ),
  ];
}

List<DatabaseViewerSection> _playHistorySections(PlayHistory history) {
  return [
    DatabaseViewerSection(
      title: t.databaseViewer.basicInfo,
      data: {
        'id': history.id.toString(),
        'sourceId': history.sourceId,
        'sourceType': history.sourceType.name,
        'cid': history.cid?.toString() ?? 'null',
        'trackKey': history.trackKey,
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.mediaInfo,
      data: {
        'title': history.title,
        'artist': history.artist ?? 'null',
        'durationMs': history.durationMs?.toString() ?? 'null',
        'formattedDuration': history.formattedDuration,
        'thumbnailUrl': _truncate(history.thumbnailUrl, 60),
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.playbackTime,
      data: {
        'playedAt': history.playedAt.toIso8601String(),
      },
    ),
  ];
}

List<DatabaseViewerSection> _searchHistorySections(SearchHistory history) {
  return [
    DatabaseViewerSection(
      title: t.databaseViewer.searchHistory,
      data: {
        'id': history.id.toString(),
        'query': history.query,
        'timestamp': history.timestamp.toIso8601String(),
      },
    ),
  ];
}

List<DatabaseViewerSection> _downloadTaskSections(DownloadTask task) {
  return [
    DatabaseViewerSection(
      title: t.databaseViewer.basicInfo,
      data: {
        'id': task.id.toString(),
        'trackId': task.trackId.toString(),
        'playlistId': task.playlistId?.toString() ?? 'null',
        'playlistName': task.playlistName ?? 'null',
        'priority': task.priority.toString(),
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.downloadStatus,
      data: {
        'status': task.status.name,
        'progress': '${(task.progress * 100).toStringAsFixed(1)}%',
        'formattedProgress': task.formattedProgress,
        'isDownloading': task.isDownloading.toString(),
        'isCompleted': task.isCompleted.toString(),
        'isFailed': task.isFailed.toString(),
        'isPending': task.isPending.toString(),
        'isPaused': task.isPaused.toString(),
        'downloadedBytes': _formatBytes(task.downloadedBytes),
        'totalBytes':
            task.totalBytes != null ? _formatBytes(task.totalBytes!) : 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.fileInfo,
      data: {
        'savePath': _truncate(task.savePath, 80),
        'tempFilePath': _truncate(task.tempFilePath, 80),
        'canResume': task.canResume.toString(),
        'isPartOfPlaylist': task.isPartOfPlaylist.toString(),
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.errorInfo,
      data: {
        'errorMessage': task.errorMessage ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.timestamps,
      data: {
        'createdAt': task.createdAt.toIso8601String(),
        'completedAt': task.completedAt?.toIso8601String() ?? 'null',
      },
    ),
  ];
}

List<DatabaseViewerSection> _radioStationSections(RadioStation station) {
  return [
    DatabaseViewerSection(
      title: t.databaseViewer.basicInfo,
      data: {
        'id': station.id.toString(),
        'uniqueKey': station.uniqueKey,
        'url': _truncate(station.url, 60),
        'title': station.title,
        'sourceType': station.sourceType.name,
        'sourceId': station.sourceId,
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.streamerInfo,
      data: {
        'hostName': station.hostName ?? 'null',
        'hostUid': station.hostUid?.toString() ?? 'null',
        'hostAvatarUrl': _truncate(station.hostAvatarUrl, 60),
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.mediaInfo,
      data: {
        'thumbnailUrl': _truncate(station.thumbnailUrl, 60),
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.sortAndFavorite,
      data: {
        'sortOrder': station.sortOrder.toString(),
        'isFavorite': station.isFavorite.toString(),
        'note': station.note ?? 'null',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.timestamps,
      data: {
        'createdAt': station.createdAt.toIso8601String(),
        'lastPlayedAt': station.lastPlayedAt?.toIso8601String() ?? 'null',
      },
    ),
  ];
}

List<DatabaseViewerSection> _lyricsMatchSections(LyricsMatch match) {
  return [
    DatabaseViewerSection(
      title: t.databaseViewer.basicInfo,
      data: {
        'id': match.id.toString(),
        'trackUniqueKey': match.trackUniqueKey,
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.lyricsInfo,
      data: {
        'lyricsSource': match.lyricsSource,
        'externalId': match.externalId,
        'offsetMs': '${match.offsetMs}ms',
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.timestamps,
      data: {
        'matchedAt': match.matchedAt.toIso8601String(),
      },
    ),
  ];
}

List<DatabaseViewerSection> _lyricsTitleParseCacheSections(
  LyricsTitleParseCache cache,
) {
  return [
    DatabaseViewerSection(
      title: t.databaseViewer.basicInfo,
      data: {
        'id': cache.id.toString(),
        'trackUniqueKey': cache.trackUniqueKey,
        'sourceType': cache.sourceType,
      },
    ),
    DatabaseViewerSection(
      title: 'Parsed Result',
      data: {
        'parsedTrackName': cache.parsedTrackName,
        'parsedArtistName': cache.parsedArtistName ?? 'null',
        'confidence': cache.confidence.toStringAsFixed(3),
        'provider': cache.provider,
        'model': cache.model,
      },
    ),
    DatabaseViewerSection(
      title: t.databaseViewer.timestamps,
      data: {
        'createdAt': cache.createdAt.toIso8601String(),
        'updatedAt': cache.updatedAt.toIso8601String(),
      },
    ),
  ];
}

List<DatabaseViewerSection> _accountSections(Account account) {
  return [
    DatabaseViewerSection(
      title: t.databaseViewer.basicInfo,
      data: {
        'id': account.id.toString(),
        'platform': account.platform.name,
        'userId': account.userId ?? 'null',
        'userName': account.userName ?? 'null',
        'avatarUrl': _truncate(account.avatarUrl, 60),
      },
    ),
    DatabaseViewerSection(
      title: 'Login State',
      data: {
        'isLoggedIn': account.isLoggedIn.toString(),
        'isVip': account.isVip.toString(),
        'lastRefreshed': account.lastRefreshed?.toIso8601String() ?? 'null',
        'loginAt': account.loginAt?.toIso8601String() ?? 'null',
      },
    ),
  ];
}

String _truncate(String? value, int maxLength) {
  if (value == null) return 'null';
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}...';
}

String _formatNullableColor(int? value) {
  if (value == null) return 'null';
  return '#${value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _formatDateTime(DateTime dt) {
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
