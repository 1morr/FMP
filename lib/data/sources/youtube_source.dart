import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../core/logger.dart';
import '../models/track.dart';
import '../models/video_detail.dart';
import 'base_source.dart';

/// YouTube 音源实现
class YouTubeSource extends BaseSource with Logging {
  late final yt.YoutubeExplode _youtube;

  // 熱門搜索關鍵字
  static const List<String> _trendingMusicQueries = [
    'Music Video',
    'Official Music Video',
    'MV',
    'Official MV',
    'VOCALOID',
  ];

  YouTubeSource() {
    _youtube = yt.YoutubeExplode();
  }

  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  String get sourceName => 'YouTube';

  @override
  String? parseId(String url) {
    // 支持多种 URL 格式:
    // - https://www.youtube.com/watch?v=VIDEO_ID
    // - https://youtu.be/VIDEO_ID
    // - https://www.youtube.com/embed/VIDEO_ID
    // - https://www.youtube.com/v/VIDEO_ID
    // - https://youtube.com/shorts/VIDEO_ID
    // - https://www.youtube.com/watch?v=VIDEO_ID&list=PLAYLIST_ID
    // - https://m.youtube.com/watch?v=VIDEO_ID
    try {
      final videoId = yt.VideoId.parseVideoId(url);
      return videoId;
    } catch (_) {
      // 尝试直接作为 video ID
      if (isValidId(url)) {
        return url;
      }
      return null;
    }
  }

  @override
  bool isValidId(String id) {
    // YouTube video ID 是 11 个字符
    return RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id);
  }

  @override
  bool isPlaylistUrl(String url) {
    // 播放列表 URL 格式:
    // - https://www.youtube.com/playlist?list=PLAYLIST_ID
    // - https://www.youtube.com/watch?v=VIDEO_ID&list=PLAYLIST_ID
    return url.contains('list=') || url.contains('/playlist');
  }

  /// 从 URL 解析播放列表 ID
  String? _parsePlaylistId(String url) {
    try {
      return yt.PlaylistId.parsePlaylistId(url);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Track> getTrackInfo(String videoId) async {
    logDebug('Getting track info for YouTube video: $videoId');
    try {
      final video = await _youtube.videos.get(videoId);

      final track = Track()
        ..sourceId = videoId
        ..sourceType = SourceType.youtube
        ..title = video.title
        ..artist = video.author
        ..channelId = video.channelId.value
        ..durationMs = video.duration?.inMilliseconds ?? 0
        ..thumbnailUrl = video.thumbnails.highResUrl
        ..viewCount = video.engagement.viewCount;

      // 获取音频 URL
      final audioUrl = await getAudioUrl(videoId);
      track.audioUrl = audioUrl;
      // YouTube URL 过期较快，使用 1 小时有效期
      track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));
      track.createdAt = DateTime.now();

      logDebug('Got track info for $videoId: ${video.title}');
      return track;
    } on yt.VideoUnplayableException catch (e) {
      logError('YouTube video unplayable: $videoId, reason: $e');
      throw YouTubeApiException(
        code: 'unplayable',
        message: 'Video is unplayable: $e',
      );
    } catch (e) {
      logError('Failed to get YouTube video info: $videoId, error: $e');
      throw YouTubeApiException(
        code: 'error',
        message: 'Failed to get video info: $e',
      );
    }
  }

  /// 获取 YouTube 视频详情（用于详情面板显示）
  Future<VideoDetail> getVideoDetail(String videoId) async {
    logDebug('Getting video detail for YouTube video: $videoId');
    try {
      final video = await _youtube.videos.get(videoId);

      // 并行获取频道信息和评论
      final results = await Future.wait([
        _getChannelLogoUrl(video.channelId.value),
        _getHotComments(videoId, video),
      ]);

      final channelLogoUrl = results[0] as String?;
      final comments = results[1] as List<VideoComment>;

      return VideoDetail.fromYouTube(
        videoId: videoId,
        title: video.title,
        description: video.description,
        author: video.author,
        authorAvatarUrl: channelLogoUrl,
        thumbnailUrl: video.thumbnails.highResUrl,
        channelId: video.channelId.value,
        durationMs: video.duration?.inMilliseconds ?? 0,
        viewCount: video.engagement.viewCount,
        likeCount: video.engagement.likeCount ?? 0,
        publishDate: video.uploadDate ?? video.publishDate,
        comments: comments,
      );
    } on yt.VideoUnplayableException catch (e) {
      logError('YouTube video unplayable: $videoId, reason: $e');
      throw YouTubeApiException(
        code: 'unplayable',
        message: 'Video is unplayable: $e',
      );
    } catch (e) {
      logError('Failed to get YouTube video detail: $videoId, error: $e');
      throw YouTubeApiException(
        code: 'error',
        message: 'Failed to get video detail: $e',
      );
    }
  }

  /// 获取频道头像 URL
  Future<String?> _getChannelLogoUrl(String channelId) async {
    try {
      final channel = await _youtube.channels.get(channelId);
      return channel.logoUrl;
    } catch (e) {
      logDebug('Failed to get channel logo for $channelId: $e');
      return null;
    }
  }

  /// 获取热门评论（最多 3 条）
  Future<List<VideoComment>> _getHotComments(String videoId, [yt.Video? video]) async {
    try {
      // 如果没有传入 video，需要先获取
      final videoObj = video ?? await _youtube.videos.get(videoId);
      final comments = await _youtube.videos.comments.getComments(videoObj);
      
      if (comments == null || comments.isEmpty) {
        return [];
      }

      // 取前 3 条评论
      return comments.take(3).map((c) => VideoComment(
        id: 0,
        content: c.text,
        memberName: c.author,
        memberAvatar: '', // YouTube 评论没有直接提供头像 URL
        likeCount: c.likeCount,
        createTime: DateTime.now(), // publishedTime 是字符串如 "2 years ago"
      )).toList();
    } catch (e) {
      logDebug('Failed to get comments for $videoId: $e');
      return [];
    }
  }

  @override
  Future<String> getAudioUrl(String videoId) async {
    logDebug('Getting audio URL for YouTube video: $videoId');
    try {
      // 使用多个客户端获取流，iOS/Safari 客户端通常有更好的兼容性
      final manifest = await _youtube.videos.streams.getManifest(
        videoId,
        ytClients: [
          yt.YoutubeApiClient.ios,
          yt.YoutubeApiClient.safari,
          yt.YoutubeApiClient.android,
        ],
      );

      // 优先使用 muxed 流（视频+音频单文件）
      // media_kit (libmpv) 在 Windows 上无法打开 audio-only 流（无论 webm/opus 还是 mp4/aac）
      // 错误："Failed to open ..."，只有 muxed 流能正常工作
      if (manifest.muxed.isNotEmpty) {
        final muxedStream = manifest.muxed.withHighestBitrate();
        logDebug(
            'Got muxed stream for $videoId, bitrate: ${muxedStream.bitrate}');
        return muxedStream.url.toString();
      }

      // 备选：HLS 流（m3u8 分段加载）
      if (manifest.hls.isNotEmpty) {
        final hlsStream = manifest.hls.first;
        logDebug('Got HLS stream for $videoId (fallback)');
        return hlsStream.url.toString();
      }

      logError('No muxed or HLS stream available for YouTube video: $videoId');
      throw YouTubeApiException(
        code: 'no_stream',
        message: 'No audio stream available',
      );
    } on yt.VideoUnplayableException catch (e) {
      logError('YouTube video unplayable: $videoId, reason: $e');
      throw YouTubeApiException(
        code: 'unplayable',
        message: 'Video is unplayable: $e',
      );
    } catch (e) {
      logError('Failed to get YouTube audio URL: $videoId, error: $e');
      throw YouTubeApiException(
        code: 'error',
        message: 'Failed to get audio URL: $e',
      );
    }
  }

  /// 获取备选音频 URL（尝试不同类型的流）
  /// 当主流无法播放时使用
  @override
  Future<String?> getAlternativeAudioUrl(String videoId, {String? failedUrl}) async {
    logDebug('Getting alternative audio URL for YouTube video: $videoId');
    try {
      final manifest = await _youtube.videos.streams.getManifest(
        videoId,
        ytClients: [
          yt.YoutubeApiClient.ios,
          yt.YoutubeApiClient.safari,
          yt.YoutubeApiClient.android,
        ],
      );

      // 尝试 muxed 流（单文件，包含视频和音频）
      if (manifest.muxed.isNotEmpty) {
        final muxedStream = manifest.muxed.withHighestBitrate();
        final url = muxedStream.url.toString();
        if (url != failedUrl) {
          logDebug('Got alternative muxed stream for $videoId, bitrate: ${muxedStream.bitrate}');
          return url;
        }
      }

      // 注意：audio-only 流在 Windows 上不可用（media_kit/libmpv 限制）

      // 尝试 HLS 流（m3u8 分段格式）
      if (manifest.hls.isNotEmpty) {
        final hlsStream = manifest.hls.first;
        final url = hlsStream.url.toString();
        if (url != failedUrl) {
          logDebug('Got alternative HLS stream for $videoId');
          return url;
        }
      }

      logWarning('No alternative audio URL available for: $videoId');
      return null;
    } catch (e) {
      logError('Failed to get alternative audio URL for $videoId: $e');
      return null;
    }
  }

  @override
  Future<Track> refreshAudioUrl(Track track) async {
    if (track.sourceType != SourceType.youtube) {
      throw Exception('Invalid source type for YouTubeSource');
    }

    final audioUrl = await getAudioUrl(track.sourceId);
    track.audioUrl = audioUrl;
    track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));
    track.updatedAt = DateTime.now();
    return track;
  }

  /// 将 SearchOrder 转换为 YouTube 搜索过滤器
  yt.SearchFilter _getYouTubeFilter(SearchOrder order) {
    switch (order) {
      case SearchOrder.relevance:
        return yt.SortFilters.relevance;
      case SearchOrder.playCount:
        return yt.SortFilters.viewCount;
      case SearchOrder.publishDate:
        return yt.SortFilters.uploadDate;

    }
  }

  @override
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    logDebug('Searching YouTube for: $query, page: $page, order: $order');
    try {
      // 获取搜索结果列表（带排序过滤器）
      final filter = _getYouTubeFilter(order);
      var searchList = await _youtube.search.search(query, filter: filter);

      // 需要跳过的页数（page 从 1 开始）
      final pagesToSkip = page - 1;

      // 调用 nextPage() 跳过前面的页
      for (var i = 0; i < pagesToSkip; i++) {
        final nextPageResult = await searchList.nextPage();
        if (nextPageResult == null) {
          // 没有更多页了
          logDebug('YouTube search: no more pages at page $i');
          return SearchResult(
            tracks: [],
            totalCount: i * pageSize,
            page: page,
            pageSize: pageSize,
            hasMore: false,
          );
        }
        searchList = nextPageResult;
      }

      // 从当前页收集结果
      final tracks = <Track>[];
      for (final video in searchList) {
        tracks.add(Track()
          ..sourceId = video.id.value
          ..sourceType = SourceType.youtube
          ..title = video.title
          ..artist = video.author
          ..channelId = video.channelId.value
          ..durationMs = video.duration?.inMilliseconds ?? 0
          ..thumbnailUrl = video.thumbnails.highResUrl
          ..viewCount = video.engagement.viewCount);

        if (tracks.length >= pageSize) break;
      }

      // 如果结果不够，尝试获取下一页补充
      if (tracks.length < pageSize) {
        final nextPageResult = await searchList.nextPage();
        if (nextPageResult != null) {
          for (final video in nextPageResult) {
            tracks.add(Track()
              ..sourceId = video.id.value
              ..sourceType = SourceType.youtube
              ..title = video.title
              ..artist = video.author
              ..channelId = video.channelId.value
              ..durationMs = video.duration?.inMilliseconds ?? 0
              ..thumbnailUrl = video.thumbnails.highResUrl
              ..viewCount = video.engagement.viewCount);
            if (tracks.length >= pageSize) break;
          }
        }
      }

      // 检查是否有下一页
      final hasMore = tracks.length >= pageSize;

      logDebug('YouTube search returned ${tracks.length} results for: $query, page: $page, hasMore: $hasMore');

      return SearchResult(
        tracks: tracks,
        totalCount: page * pageSize + (hasMore ? 100 : 0),
        page: page,
        pageSize: pageSize,
        hasMore: hasMore,
      );
    } catch (e) {
      logError('YouTube search failed: $query, error: $e');
      throw YouTubeApiException(
        code: 'search_error',
        message: 'Search failed: $e',
      );
    }
  }

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
  }) async {
    logDebug('Parsing YouTube playlist: $playlistUrl');
    try {
      final playlistId = _parsePlaylistId(playlistUrl);
      if (playlistId == null) {
        throw YouTubeApiException(
          code: 'invalid_url',
          message: 'Invalid playlist URL',
        );
      }

      // 获取播放列表元数据
      final playlist = await _youtube.playlists.get(playlistId);

      // 获取所有视频
      final allTracks = <Track>[];
      await for (final video in _youtube.playlists.getVideos(playlistId)) {
        allTracks.add(Track()
          ..sourceId = video.id.value
          ..sourceType = SourceType.youtube
          ..title = video.title
          ..artist = video.author
          ..channelId = video.channelId.value
          ..durationMs = video.duration?.inMilliseconds ?? 0
          ..thumbnailUrl = video.thumbnails.highResUrl);
      }

      logDebug(
          'Parsed YouTube playlist: ${playlist.title}, ${allTracks.length} tracks');

      // 使用第一个视频的缩略图作为歌单封面
      // (playlist.thumbnails 使用播放列表 ID 生成 URL，对视频缩略图无效)
      final coverUrl = allTracks.isNotEmpty ? allTracks.first.thumbnailUrl : null;

      return PlaylistParseResult(
        title: playlist.title,
        description: playlist.description,
        coverUrl: coverUrl,
        tracks: allTracks,
        totalCount: allTracks.length,
        sourceUrl: playlistUrl,
      );
    } catch (e) {
      logError('Failed to parse YouTube playlist: $playlistUrl, error: $e');
      throw YouTubeApiException(
        code: 'error',
        message: 'Failed to parse playlist: $e',
      );
    }
  }

  @override
  Future<bool> checkAvailability(String sourceId) async {
    try {
      await _youtube.videos.get(sourceId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ==================== InnerTube API 熱門影片 ====================

  /// 獲取熱門音樂影片（使用搜索作為替代方案）
  /// 限制為最近 7 天內上傳的影片，按播放量排序
  /// 搜索多個關鍵字以獲取更多樣的結果
  Future<List<Track>> getTrendingVideos({String category = 'music'}) async {
    logDebug('Getting YouTube trending videos via search');
    try {
      // 用於去重的 Set
      final seenIds = <String>{};
      final allTracks = <Track>[];

      // 搜索所有關鍵字
      final queriesToUse = _trendingMusicQueries;
      const resultsPerQuery = 20;

      for (final query in queriesToUse) {
        try {
          logDebug('Searching YouTube for: $query');

          // 使用 lastWeek 篩選器搜索最近 7 天的影片
          var searchList = await _youtube.search.search(
            query,
            filter: yt.UploadDateFilter.lastWeek,
          );

          var tracksFromQuery = 0;

          // 第一頁結果
          for (final video in searchList) {
            if (seenIds.contains(video.id.value)) continue;
            seenIds.add(video.id.value);

            allTracks.add(Track()
              ..sourceId = video.id.value
              ..sourceType = SourceType.youtube
              ..title = video.title
              ..artist = video.author
              ..channelId = video.channelId.value
              ..durationMs = video.duration?.inMilliseconds ?? 0
              ..thumbnailUrl = video.thumbnails.highResUrl
              ..viewCount = video.engagement.viewCount);

            tracksFromQuery++;
            if (tracksFromQuery >= resultsPerQuery) break;
          }

          // 如果結果不夠，嘗試獲取更多頁
          while (tracksFromQuery < resultsPerQuery) {
            final nextPage = await searchList.nextPage();
            if (nextPage == null) break;
            searchList = nextPage;

            for (final video in searchList) {
              if (seenIds.contains(video.id.value)) continue;
              seenIds.add(video.id.value);

              allTracks.add(Track()
                ..sourceId = video.id.value
                ..sourceType = SourceType.youtube
                ..title = video.title
                ..artist = video.author
                ..channelId = video.channelId.value
                ..durationMs = video.duration?.inMilliseconds ?? 0
                ..thumbnailUrl = video.thumbnails.highResUrl
                ..viewCount = video.engagement.viewCount);

              tracksFromQuery++;
              if (tracksFromQuery >= resultsPerQuery) break;
            }
          }

          logDebug('Got $tracksFromQuery tracks from query: $query');
        } catch (e) {
          // 單個關鍵字搜索失敗，記錄錯誤但繼續搜索其他關鍵字
          logError('Failed to search for "$query": $e');
        }
      }

      // 如果完全沒有結果，拋出異常
      if (allTracks.isEmpty) {
        throw YouTubeApiException(
          code: 'no_results',
          message: 'No trending videos found from any query',
        );
      }

      // 按播放量降序排序
      allTracks.sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));

      // 返回前 100 個結果
      final result = allTracks.take(100).toList();
      logDebug('Got ${result.length} trending videos (from ${allTracks.length} candidates)');
      return result;
    } catch (e) {
      logError('Failed to get YouTube trending videos: $e');
      if (e is YouTubeApiException) rethrow;
      throw YouTubeApiException(
        code: 'error',
        message: 'Failed to get trending videos: $e',
      );
    }
  }

  /// 释放资源
  void dispose() {
    _youtube.close();
  }
}

/// YouTube API 错误
class YouTubeApiException implements Exception {
  final String code;
  final String message;

  const YouTubeApiException({required this.code, required this.message});

  @override
  String toString() => 'YouTubeApiException($code): $message';

  /// 是否是视频不可用
  bool get isUnavailable =>
      code == 'unavailable' || code == 'not_found' || code == 'unplayable';

  /// 是否需要登录（年龄限制等）
  bool get requiresLogin => code == 'age_restricted' || code == 'login_required';

  /// 是否是地区限制
  bool get isGeoRestricted => code == 'geo_restricted';
}
