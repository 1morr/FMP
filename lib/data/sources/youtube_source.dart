import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../core/utils/http_client_factory.dart';
import '../models/settings.dart';
import '../models/track.dart';
import '../models/video_detail.dart';
import 'base_source.dart';
import 'source_exception.dart';
import 'youtube_exception.dart';

/// YouTube 音源实现
class YouTubeSource extends BaseSource with Logging {
  late final yt.YoutubeExplode _youtube;
  late final Dio _dio;

  // InnerTube API 配置
  static const String _innerTubeApiBase = 'https://www.youtube.com/youtubei/v1';
  static const String _innerTubeApiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const String _innerTubeClientName = 'WEB';
  static const String _innerTubeClientVersion = '2.20260128.05.00';

  // YouTube Music 頻道 "New This Week" 播放列表 ID
  // https://www.youtube.com/playlist?list=OLPPnm121Qlcoo7kKykmswKG0IepmDUVpag
  static const String _newThisWeekPlaylistId = 'OLPPnm121Qlcoo7kKykmswKG0IepmDUVpag';

  YouTubeSource() {
    _youtube = yt.YoutubeExplode();
    _dio = HttpClientFactory.create(
      headers: {
        'Content-Type': 'application/json',
      },
    );
  }

  /// 构建带认证的 InnerTube 请求 Options
  ///
  /// InnerTube 认证需要 Origin + Referer 头，否则 SAPISIDHASH 验证失败
  Options _innerTubeAuthOptions(Map<String, String> authHeaders) {
    return Options(headers: {
      'Origin': 'https://www.youtube.com',
      'Referer': 'https://www.youtube.com/',
      ...authHeaders,
    });
  }

  /// Parse Dio response data to Map (handles both String and Map responses).
  Map<String, dynamic> _parseJsonResponse(dynamic responseData) {
    return responseData is String
        ? jsonDecode(responseData) as Map<String, dynamic>
        : responseData as Map<String, dynamic>;
  }

  /// Validate InnerTube playability status, throws on error.
  void _checkPlayability(Map<String, dynamic> data) {
    final playabilityStatus = data['playabilityStatus'];
    final status = playabilityStatus?['status'] as String?;
    if (status != 'OK') {
      throw YouTubeApiException(
        code: status?.toLowerCase() ?? 'error',
        message: playabilityStatus?['reason'] as String? ?? 'Video unavailable',
      );
    }
  }

  /// Call InnerTube /player endpoint and return parsed + validated response.
  Future<Map<String, dynamic>> _innerTubePlayerRequest(
    String videoId,
    Map<String, String> authHeaders, {
    String? clientName,
    String? clientVersion,
    int? androidSdkVersion,
  }) async {
    final clientContext = <String, dynamic>{
      'clientName': clientName ?? _innerTubeClientName,
      'clientVersion': clientVersion ?? _innerTubeClientVersion,
      'hl': 'en',
      'gl': 'US',
    };
    if (androidSdkVersion != null) {
      clientContext['androidSdkVersion'] = androidSdkVersion;
    }

    final response = await _dio.post(
      '$_innerTubeApiBase/player?key=$_innerTubeApiKey',
      data: jsonEncode({
        'videoId': videoId,
        'context': {'client': clientContext},
      }),
      options: _innerTubeAuthOptions(authHeaders),
    );

    final data = _parseJsonResponse(response.data);
    _checkPlayability(data);
    return data;
  }

  @override
  SourceType get sourceType => SourceType.youtube;

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
    // - https://music.youtube.com/playlist?list=PLAYLIST_ID
    // 必须先确认是 YouTube 域名，避免误匹配其他平台含 /playlist 的 URL（如 Spotify）
    final isYouTubeDomain = url.contains('youtube.com') ||
        url.contains('youtu.be') ||
        url.contains('music.youtube.com');
    if (!isYouTubeDomain) return false;
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
  Future<Track> getTrackInfo(String videoId, {Map<String, String>? authHeaders}) async {
    // If auth headers provided, use InnerTube API path
    if (authHeaders != null) {
      return _getTrackInfoViaInnerTube(videoId, authHeaders);
    }

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
      track.audioUrlExpiry = DateTime.now().add(Duration(hours: AppConstants.youtubeAudioUrlExpiryHours));
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
      if (e is YouTubeApiException) rethrow;
      if (_isRateLimitError(e)) {
        logWarning('YouTube rate limited for video: $videoId');
        throw YouTubeApiException(
          code: 'rate_limited',
          message: t.error.rateLimited,
        );
      }
      logError('Failed to get YouTube video info: $videoId, error: $e');
      throw YouTubeApiException(
        code: 'error',
        message: 'Failed to get video info: $e',
      );
    }
  }

  /// 获取 YouTube 视频详情（用于详情面板显示）
  Future<VideoDetail> getVideoDetail(String videoId, {Map<String, String>? authHeaders}) async {
    logDebug('Getting video detail for YouTube video: $videoId');

    // Always try youtube_explode first (has full metadata: avatar, likes, publish date)
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
      if (e is YouTubeApiException) rethrow;
      if (_isRateLimitError(e)) {
        logWarning('YouTube rate limited for video detail: $videoId');
        throw YouTubeApiException(
          code: 'rate_limited',
          message: t.error.rateLimited,
        );
      }
      // youtube_explode failed — fall back to InnerTube with auth if available
      if (authHeaders != null) {
        logDebug('youtube_explode failed for video detail $videoId, trying InnerTube with auth');
        return _getVideoDetailViaInnerTube(videoId, authHeaders);
      }
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

      // 取前几条评论
      return comments.take(AppConstants.commentsPreviewCount).map((c) => VideoComment(
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
  Future<AudioStreamResult> getAudioStream(
    String videoId, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
    Map<String, String>? authHeaders,
  }) async {
    logDebug('Getting audio stream for YouTube video: $videoId with config: qualityLevel=${config.qualityLevel}, streamPriority=${config.streamPriority}');

    // Always try youtube_explode first (most reliable)
    for (final streamType in config.streamPriority) {
      try {
        final result = await _tryGetStream(videoId, streamType, config);
        if (result != null) {
          return result;
        }
      } catch (e) {
        if (_isRateLimitError(e)) {
          logWarning('YouTube rate limited when getting stream for $videoId');
          throw YouTubeApiException(
            code: 'rate_limited',
            message: t.error.rateLimited,
          );
        }
        logDebug('Stream type $streamType failed for $videoId: $e');
      }
    }

    // youtube_explode failed — fall back to InnerTube with auth if available
    if (authHeaders != null) {
      logDebug('youtube_explode failed for $videoId, trying InnerTube with auth');
      return _getAudioStreamViaInnerTube(videoId, authHeaders, config);
    }

    logError('No audio stream available for YouTube video: $videoId');
    throw YouTubeApiException(
      code: 'no_stream',
      message: 'No audio stream available',
    );
  }

  /// 尝试获取指定类型的流
  Future<AudioStreamResult?> _tryGetStream(
    String videoId,
    StreamType streamType,
    AudioStreamConfig config,
  ) async {
    switch (streamType) {
      case StreamType.audioOnly:
        return _tryGetAudioOnlyStream(videoId, config);
      case StreamType.muxed:
        return _tryGetMuxedStream(videoId, config);
      case StreamType.hls:
        return _tryGetHlsStream(videoId, config);
    }
  }

  /// 尝试获取 audio-only 流（androidVr 客户端）
  Future<AudioStreamResult?> _tryGetAudioOnlyStream(
    String videoId,
    AudioStreamConfig config,
  ) async {
    try {
      final vrManifest = await _youtube.videos.streams.getManifest(
        videoId,
        ytClients: [yt.YoutubeApiClient.androidVr],
      );

      if (vrManifest.audioOnly.isEmpty) return null;

      final audioStreams = vrManifest.audioOnly.toList();
      final selected = _selectBestStream(audioStreams, config);
      
      if (selected != null) {
        logDebug('Got audio-only stream for $videoId: ${selected.bitrate}, ${selected.container.name}');
        return AudioStreamResult(
          url: selected.url.toString(),
          bitrate: selected.bitrate.bitsPerSecond,
          container: selected.container.name,
          codec: selected.audioCodec,
          streamType: StreamType.audioOnly,
        );
      }
    } catch (e) {
      logDebug('Audio-only stream failed for $videoId: $e');
    }
    return null;
  }

  /// 尝试获取 muxed 流
  Future<AudioStreamResult?> _tryGetMuxedStream(
    String videoId,
    AudioStreamConfig config,
  ) async {
    try {
      final manifest = await _youtube.videos.streams.getManifest(
        videoId,
        ytClients: [
          yt.YoutubeApiClient.ios,
          yt.YoutubeApiClient.safari,
          yt.YoutubeApiClient.android,
        ],
      );

      if (manifest.muxed.isEmpty) return null;

      // muxed 流按码率排序选择
      final muxedStreams = manifest.muxed.toList();
      muxedStreams.sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      
      final selected = _selectByQualityLevel(muxedStreams, config.qualityLevel);
      
      if (selected != null) {
        logDebug('Got muxed stream for $videoId: ${selected.bitrate}, ${selected.container.name}');
        return AudioStreamResult(
          url: selected.url.toString(),
          bitrate: selected.bitrate.bitsPerSecond,
          container: selected.container.name,
          codec: selected.audioCodec,
          streamType: StreamType.muxed,
        );
      }
    } catch (e) {
      logDebug('Muxed stream failed for $videoId: $e');
    }
    return null;
  }

  /// 尝试获取 HLS 流
  Future<AudioStreamResult?> _tryGetHlsStream(
    String videoId,
    AudioStreamConfig config,
  ) async {
    try {
      final manifest = await _youtube.videos.streams.getManifest(
        videoId,
        ytClients: [yt.YoutubeApiClient.safari],
      );

      if (manifest.hls.isEmpty) return null;

      final hlsStream = manifest.hls.first;
      logDebug('Got HLS stream for $videoId');
      return AudioStreamResult(
        url: hlsStream.url.toString(),
        bitrate: null, // HLS 不提供准确码率
        container: 'm3u8',
        codec: null,
        streamType: StreamType.hls,
      );
    } catch (e) {
      logDebug('HLS stream failed for $videoId: $e');
    }
    return null;
  }

  /// 根据配置选择最佳 audio-only 流
  yt.AudioOnlyStreamInfo? _selectBestStream(
    List<yt.AudioOnlyStreamInfo> streams,
    AudioStreamConfig config,
  ) {
    if (streams.isEmpty) return null;

    // 按码率排序
    streams.sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));

    // 按格式优先级筛选
    for (final format in config.formatPriority) {
      final matching = streams.where((s) => _matchesFormat(s, format)).toList();
      if (matching.isNotEmpty) {
        return _selectByQualityLevel(matching, config.qualityLevel);
      }
    }

    // 如果没有匹配的格式，按码率选择
    return _selectByQualityLevel(streams, config.qualityLevel);
  }

  /// 检查流是否匹配指定格式
  bool _matchesFormat(yt.AudioOnlyStreamInfo stream, AudioFormat format) {
    final container = stream.container.name.toLowerCase();
    final codec = stream.audioCodec.toLowerCase();
    
    switch (format) {
      case AudioFormat.opus:
        // Opus 编码通常在 WebM 容器中
        return codec.contains('opus') || container == 'webm';
      case AudioFormat.aac:
        // AAC 编码通常在 MP4/M4A 容器中
        return container == 'mp4' || container == 'm4a' || 
               codec.contains('aac') || codec.contains('mp4a');
    }
  }

  /// 根据音质等级选择流
  T? _selectByQualityLevel<T>(List<T> sortedStreams, AudioQualityLevel level) {
    if (sortedStreams.isEmpty) return null;

    switch (level) {
      case AudioQualityLevel.high:
        return sortedStreams.first; // 最高码率
      case AudioQualityLevel.medium:
        return sortedStreams[sortedStreams.length ~/ 2]; // 中间
      case AudioQualityLevel.low:
        return sortedStreams.last; // 最低码率
    }
  }

  /// 获取备选音频流（尝试不同类型的流）
  /// 当主流无法播放时使用
  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    String videoId, {
    String? failedUrl,
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  }) async {
    logDebug('Getting alternative audio stream for YouTube video: $videoId');
    try {
      // 按流类型优先级尝试，跳过已失败的 URL
      for (final streamType in config.streamPriority) {
        try {
          final result = await _tryGetAlternativeStream(videoId, streamType, config, failedUrl);
          if (result != null) {
            return result;
          }
        } catch (e) {
          logDebug('Alternative stream type $streamType failed for $videoId: $e');
        }
      }

      logWarning('No alternative audio stream available for: $videoId');
      return null;
    } catch (e) {
      logError('Failed to get alternative audio stream for $videoId: $e');
      return null;
    }
  }

  /// 尝试获取指定类型的备选流（排除已失败的 URL）
  Future<AudioStreamResult?> _tryGetAlternativeStream(
    String videoId,
    StreamType streamType,
    AudioStreamConfig config,
    String? failedUrl,
  ) async {
    switch (streamType) {
      case StreamType.audioOnly:
        return _tryGetAlternativeAudioOnlyStream(videoId, config, failedUrl);
      case StreamType.muxed:
        return _tryGetAlternativeMuxedStream(videoId, config, failedUrl);
      case StreamType.hls:
        return _tryGetAlternativeHlsStream(videoId, config, failedUrl);
    }
  }

  Future<AudioStreamResult?> _tryGetAlternativeAudioOnlyStream(
    String videoId,
    AudioStreamConfig config,
    String? failedUrl,
  ) async {
    try {
      final vrManifest = await _youtube.videos.streams.getManifest(
        videoId,
        ytClients: [yt.YoutubeApiClient.androidVr],
      );

      if (vrManifest.audioOnly.isEmpty) return null;

      final audioStreams = vrManifest.audioOnly.toList();
      audioStreams.sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));

      // 找一个不同于 failedUrl 的流
      for (final stream in audioStreams) {
        final url = stream.url.toString();
        if (url != failedUrl) {
          logDebug('Got alternative audio-only stream for $videoId');
          return AudioStreamResult(
            url: url,
            bitrate: stream.bitrate.bitsPerSecond,
            container: stream.container.name,
            codec: stream.audioCodec,
            streamType: StreamType.audioOnly,
          );
        }
      }
    } catch (e) {
      logDebug('Alternative audio-only stream failed for $videoId: $e');
    }
    return null;
  }

  Future<AudioStreamResult?> _tryGetAlternativeMuxedStream(
    String videoId,
    AudioStreamConfig config,
    String? failedUrl,
  ) async {
    try {
      final manifest = await _youtube.videos.streams.getManifest(
        videoId,
        ytClients: [
          yt.YoutubeApiClient.ios,
          yt.YoutubeApiClient.safari,
          yt.YoutubeApiClient.android,
        ],
      );

      if (manifest.muxed.isEmpty) return null;

      final muxedStreams = manifest.muxed.toList();
      muxedStreams.sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));

      for (final stream in muxedStreams) {
        final url = stream.url.toString();
        if (url != failedUrl) {
          logDebug('Got alternative muxed stream for $videoId');
          return AudioStreamResult(
            url: url,
            bitrate: stream.bitrate.bitsPerSecond,
            container: stream.container.name,
            codec: stream.audioCodec,
            streamType: StreamType.muxed,
          );
        }
      }
    } catch (e) {
      logDebug('Alternative muxed stream failed for $videoId: $e');
    }
    return null;
  }

  Future<AudioStreamResult?> _tryGetAlternativeHlsStream(
    String videoId,
    AudioStreamConfig config,
    String? failedUrl,
  ) async {
    try {
      final manifest = await _youtube.videos.streams.getManifest(
        videoId,
        ytClients: [yt.YoutubeApiClient.safari],
      );

      if (manifest.hls.isEmpty) return null;

      for (final hlsStream in manifest.hls) {
        final url = hlsStream.url.toString();
        if (url != failedUrl) {
          logDebug('Got alternative HLS stream for $videoId');
          return AudioStreamResult(
            url: url,
            bitrate: null,
            container: 'm3u8',
            codec: null,
            streamType: StreamType.hls,
          );
        }
      }
    } catch (e) {
      logDebug('Alternative HLS stream failed for $videoId: $e');
    }
    return null;
  }

  @override
  Future<Track> refreshAudioUrl(Track track, {Map<String, String>? authHeaders}) async {
    if (track.sourceType != SourceType.youtube) {
      throw YouTubeApiException(code: 'invalid_source', message: 'Invalid source type for YouTubeSource');
    }

    final audioUrl = await getAudioUrl(track.sourceId, authHeaders: authHeaders);
    track.audioUrl = audioUrl;
    track.audioUrlExpiry = DateTime.now().add(Duration(hours: AppConstants.youtubeAudioUrlExpiryHours));
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
    } catch (e, st) {
      // 检查是否是限流错误
      if (_isRateLimitError(e)) {
        logWarning('YouTube rate limited for query: "$query", error: $e');
        throw YouTubeApiException(
          code: 'rate_limited',
          message: t.error.rateLimited,
        );
      }
      logError('YouTube search failed for query: "$query"', e, st);
      throw YouTubeApiException(
        code: 'search_error',
        message: 'Search failed: $e',
      );
    }
  }

  // ==================== Mix/Radio 播放列表支持 ====================

  /// 判斷播放列表 ID 是否為 YouTube 自動生成的 Mix/Radio 播放列表
  /// Mix 播放列表 ID 以 "RD" 開頭，後跟種子影片 ID
  static bool isMixPlaylistId(String playlistId) {
    return playlistId.startsWith('RD');
  }

  /// 判斷 URL 是否為 Mix/Radio 播放列表
  static bool isMixPlaylistUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final listParam = uri.queryParameters['list'];
    if (listParam == null) return false;
    return isMixPlaylistId(listParam);
  }

  /// 從 URL 中提取 Mix 播放列表相關資訊
  static ({String? playlistId, String? seedVideoId}) extractMixInfo(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return (playlistId: null, seedVideoId: null);

    final playlistId = uri.queryParameters['list'];
    final videoId = uri.queryParameters['v'];

    // 如果沒有 v= 參數，嘗試從 playlistId 提取種子 ID
    final seedVideoId = videoId ??
        (playlistId != null && playlistId.length > 2 ? playlistId.substring(2) : null);

    return (playlistId: playlistId, seedVideoId: seedVideoId);
  }

  /// 獲取 Mix 播放列表基本信息（用於導入時只存元數據）
  /// 這是一個輕量級方法，只獲取標題和封面，不保存 tracks
  Future<MixPlaylistInfo> getMixPlaylistInfo(String url) async {
    final mixInfo = extractMixInfo(url);
    final playlistId = mixInfo.playlistId;
    final seedVideoId = mixInfo.seedVideoId;

    if (playlistId == null || seedVideoId == null) {
      throw YouTubeApiException(
        code: 'invalid_url',
        message: 'Cannot extract Mix playlist info from URL',
      );
    }

    logDebug('Getting Mix playlist info: $playlistId (seed: $seedVideoId)');

    // 調用 fetchMixTracks 獲取數據，但只返回元數據
    final result = await fetchMixTracks(
      playlistId: playlistId,
      currentVideoId: seedVideoId,
    );

    // 使用第一個影片的縮圖作為封面
    final coverUrl = result.tracks.isNotEmpty ? result.tracks.first.thumbnailUrl : null;

    return MixPlaylistInfo(
      title: result.title,
      playlistId: playlistId,
      seedVideoId: seedVideoId,
      coverUrl: coverUrl,
    );
  }

  /// 獲取 Mix 播放列表的 tracks（用於加載和加載更多）
  /// [playlistId] Mix 播放列表 ID（以 RD 開頭）
  /// [currentVideoId] 當前/種子影片 ID（首次加載用種子 ID，加載更多用最後一首的 ID）
  Future<MixFetchResult> fetchMixTracks({
    required String playlistId,
    required String currentVideoId,
  }) async {
    logDebug('Fetching Mix tracks: $playlistId (current: $currentVideoId)');

    try {
      final response = await _dio.post(
        '$_innerTubeApiBase/next?key=$_innerTubeApiKey',
        data: jsonEncode({
          'videoId': currentVideoId,
          'playlistId': playlistId,
          'context': {
            'client': {
              'clientName': _innerTubeClientName,
              'clientVersion': _innerTubeClientVersion,
              'hl': 'zh-TW',
              'gl': 'TW',
            },
          },
        }),
      );

      if (response.statusCode != 200) {
        if (response.statusCode == 429) {
          logWarning('YouTube rate limited (HTTP 429) for Mix playlist');
          throw YouTubeApiException(
            code: 'rate_limited',
            message: t.error.rateLimited,
          );
        }
        throw YouTubeApiException(
          code: 'api_error',
          message: 'InnerTube API returned status ${response.statusCode}',
        );
      }

      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      // 解析播放列表數據
      final twoColumn = data['contents']?['twoColumnWatchNextResults'];
      final playlistData = twoColumn?['playlist']?['playlist'];

      if (playlistData == null) {
        throw YouTubeApiException(
          code: 'parse_error',
          message: 'Mix playlist data not found in API response',
        );
      }

      final title = playlistData['title'] as String? ?? 'Mix';
      final contents = playlistData['contents'] as List? ?? [];

      final tracks = <Track>[];
      for (final item in contents) {
        final renderer = item['playlistPanelVideoRenderer'] as Map<String, dynamic>?;
        if (renderer == null) continue;

        final videoId = renderer['videoId'] as String?;
        if (videoId == null) continue;

        // 解析標題
        final titleObj = renderer['title'];
        final trackTitle = titleObj?['simpleText'] as String? ??
            (titleObj?['runs'] as List?)?.firstOrNull?['text'] as String? ??
            'Unknown';

        // 解析頻道名（作為 artist）
        final bylineRuns = renderer['shortBylineText']?['runs'] as List?;
        final artist = bylineRuns?.firstOrNull?['text'] as String? ?? '';

        // 解析時長
        final lengthText = renderer['lengthText']?['simpleText'] as String?;
        final durationMs = _parseDurationText(lengthText);

        // 解析縮圖
        final thumbnails = renderer['thumbnail']?['thumbnails'] as List?;
        final thumbnailUrl = thumbnails?.isNotEmpty == true
            ? thumbnails!.last['url'] as String?
            : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

        tracks.add(Track()
          ..sourceId = videoId
          ..sourceType = SourceType.youtube
          ..title = trackTitle
          ..artist = artist
          ..durationMs = durationMs
          ..thumbnailUrl = thumbnailUrl);
      }

      logDebug('Fetched Mix tracks: $title, ${tracks.length} tracks');

      return MixFetchResult(title: title, tracks: tracks);
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is YouTubeApiException) rethrow;
      logError('Unexpected error in fetchMixTracks: $e');
      throw YouTubeApiException(code: 'error', message: e.toString());
    }
  }

  /// 從 URL 中提取 list= 參數值
  String? _extractListParam(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return uri.queryParameters['list'];
  }

  /// 從 URL 中提取 v= 參數值（影片 ID）
  String? _extractVideoIdParam(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return uri.queryParameters['v'];
  }

  /// 使用 InnerTube /next API 解析 Mix/Radio 播放列表
  /// 內部使用 fetchMixTracks 獲取數據
  Future<PlaylistParseResult> _parseMixPlaylist(
    String playlistUrl,
    String playlistId,
  ) async {
    // 從 URL 或 playlistId 提取種子影片 ID
    final seedVideoId = _extractVideoIdParam(playlistUrl) ??
        (playlistId.length > 2 ? playlistId.substring(2) : null);

    if (seedVideoId == null || seedVideoId.isEmpty) {
      throw YouTubeApiException(
        code: 'invalid_url',
        message: 'Cannot extract seed video ID from Mix playlist URL',
      );
    }

    // 使用公共方法獲取 tracks
    final result = await fetchMixTracks(
      playlistId: playlistId,
      currentVideoId: seedVideoId,
    );

    // 使用第一個影片的縮圖作為封面
    final coverUrl = result.tracks.isNotEmpty ? result.tracks.first.thumbnailUrl : null;

    return PlaylistParseResult(
      title: result.title,
      description: 'YouTube Mix playlist',
      coverUrl: coverUrl,
      tracks: result.tracks,
      totalCount: result.tracks.length,
      sourceUrl: playlistUrl,
    );
  }

  /// 解析時長字串（如 "4:39" 或 "1:23:45"）為毫秒
  int _parseDurationText(String? text) {
    if (text == null || text.isEmpty) return 0;
    try {
      final parts = text.split(':').map(int.parse).toList();
      if (parts.length == 2) {
        return (parts[0] * 60 + parts[1]) * 1000;
      } else if (parts.length == 3) {
        return (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
      }
    } catch (_) {}
    return 0;
  }

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) async {
    logDebug('Parsing YouTube playlist: $playlistUrl');
    try {
      // 先嘗試從 URL 中提取 list= 參數
      final listParam = _extractListParam(playlistUrl);
      final playlistId = listParam ?? _parsePlaylistId(playlistUrl);

      if (playlistId == null) {
        throw YouTubeApiException(
          code: 'invalid_url',
          message: 'Invalid playlist URL',
        );
      }

      // Mix/Radio 播放列表使用 InnerTube API
      if (isMixPlaylistId(playlistId)) {
        return _parseMixPlaylist(playlistUrl, playlistId);
      }

      // If auth headers provided, use InnerTube API path
      if (authHeaders != null) {
        return _parsePlaylistViaInnerTube(playlistId, authHeaders, playlistUrl: playlistUrl);
      }

      // 普通播放列表使用 youtube_explode_dart
      final playlist = await _youtube.playlists.get(playlistId);

      // 檢測私人或無法訪問的播放列表
      // youtube_explode_dart 對於私人播放列表可能返回空標題或拋出異常
      final playlistTitle = playlist.title.trim();
      if (playlistTitle.isEmpty) {
        logWarning('YouTube playlist appears to be private or inaccessible: $playlistId');
        throw YouTubeApiException(
          code: 'private_or_inaccessible',
          message: t.importSource.playlistEmptyOrInaccessible,
        );
      }

      // 获取所有视频
      final allTracks = <Track>[];
      await for (final video in _youtube.playlists.getVideos(playlistId)) {
        // 使用 mqdefault (320x180, 16:9) 避免 highResUrl 可能返回的
        // hqdefault (480x360, 4:3) 带黑边问题
        final thumbnailUrl = 'https://i.ytimg.com/vi/${video.id.value}/mqdefault.jpg';
        allTracks.add(Track()
          ..sourceId = video.id.value
          ..sourceType = SourceType.youtube
          ..title = video.title
          ..artist = video.author
          ..channelId = video.channelId.value
          ..durationMs = video.duration?.inMilliseconds ?? 0
          ..thumbnailUrl = thumbnailUrl);
      }

      logDebug(
          'Parsed YouTube playlist: ${playlist.title}, ${allTracks.length} tracks');

      // 檢測空播放列表（可能是私人播放列表，元數據可見但內容不可訪問）
      if (allTracks.isEmpty) {
        logWarning('YouTube playlist is empty or private: $playlistId');
        throw YouTubeApiException(
          code: 'private_or_inaccessible',
          message: t.importSource.playlistEmptyOrInaccessible,
        );
      }

      // 使用第一个视频的缩略图作为歌单封面
      final coverUrl = allTracks.isNotEmpty ? allTracks.first.thumbnailUrl : null;

      // youtube_explode_dart doesn't provide channel ID, try InnerTube browse to get it
      String? ownerUserId;
      try {
        final browseId = 'VL$playlistId';
        final response = await _dio.post(
          '$_innerTubeApiBase/browse?key=$_innerTubeApiKey',
          data: jsonEncode({
            'browseId': browseId,
            'context': {
              'client': {
                'clientName': _innerTubeClientName,
                'clientVersion': _innerTubeClientVersion,
                'hl': 'en',
                'gl': 'US',
              },
            },
          }),
          options: Options(headers: {
            'Origin': 'https://www.youtube.com',
            'Referer': 'https://www.youtube.com/',
          }),
        );
        final browseData = _parseJsonResponse(response.data);
        final header = browseData['header'] as Map<String, dynamic>?;
        final playlistHeaderRenderer =
            header?['playlistHeaderRenderer'] as Map<String, dynamic>?;
        if (playlistHeaderRenderer != null) {
          final ownerRuns =
              playlistHeaderRenderer['ownerText']?['runs'] as List?;
          final firstRun = ownerRuns?.firstOrNull as Map<String, dynamic>?;
          ownerUserId = firstRun?['navigationEndpoint']?['browseEndpoint']
              ?['browseId'] as String?;
        }
        // Fallback: sidebar
        if (ownerUserId == null) {
          final sidebar = browseData['sidebar']?['playlistSidebarRenderer']
              ?['items'] as List?;
          if (sidebar != null && sidebar.length > 1) {
            final secondaryInfo = sidebar[1]
                ?['playlistSidebarSecondaryInfoRenderer'] as Map<String, dynamic>?;
            final videoOwner = secondaryInfo?['videoOwner']
                ?['videoOwnerRenderer'] as Map<String, dynamic>?;
            if (videoOwner != null) {
              final ownerRuns = videoOwner['title']?['runs'] as List?;
              final firstRun = ownerRuns?.firstOrNull as Map<String, dynamic>?;
              ownerUserId = firstRun?['navigationEndpoint']
                  ?['browseEndpoint']?['browseId'] as String?;
              ownerUserId ??= videoOwner['navigationEndpoint']
                  ?['browseEndpoint']?['browseId'] as String?;
            }
          }
        }
      } catch (e) {
        logDebug('Failed to get owner ID via InnerTube for playlist: $playlistId, error: $e');
      }

      return PlaylistParseResult(
        title: playlist.title,
        description: playlist.description,
        coverUrl: coverUrl,
        tracks: allTracks,
        totalCount: allTracks.length,
        sourceUrl: playlistUrl,
        ownerName: playlist.author,
        ownerUserId: ownerUserId,
      );
    } catch (e) {
      if (e is YouTubeApiException) rethrow;
      if (_isRateLimitError(e)) {
        logWarning('YouTube rate limited for playlist: $playlistUrl');
        throw YouTubeApiException(
          code: 'rate_limited',
          message: t.error.rateLimited,
        );
      }
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

  // ==================== YouTube Music "New This Week" 排行榜 ====================

  /// 解析觀看次數文字為數字（如 "14M views" → 14000000, "2.2M views" → 2200000）
  int _parseViewCountText(String? text) {
    if (text == null || text.isEmpty) return 0;
    try {
      // 去除 " views" 後綴和逗號
      var cleaned = text
          .replaceAll(RegExp(r'\s*views?\s*', caseSensitive: false), '')
          .replaceAll(',', '')
          .trim();
      if (cleaned.isEmpty) return 0;

      double multiplier = 1;
      if (cleaned.endsWith('B') || cleaned.endsWith('b')) {
        multiplier = 1e9;
        cleaned = cleaned.substring(0, cleaned.length - 1);
      } else if (cleaned.endsWith('M') || cleaned.endsWith('m')) {
        multiplier = 1e6;
        cleaned = cleaned.substring(0, cleaned.length - 1);
      } else if (cleaned.endsWith('K') || cleaned.endsWith('k')) {
        multiplier = 1e3;
        cleaned = cleaned.substring(0, cleaned.length - 1);
      }

      final number = double.tryParse(cleaned.trim());
      return number != null ? (number * multiplier).round() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// 獲取 YouTube Music "New This Week" 播放列表作為熱門排行
  ///
  /// 使用 InnerTube Browse API 獲取 YouTube Music 頻道
  /// (UC-9-kyTW8ZkZNDHQJ6FgpwQ) 的 "New This Week" 官方策劃播放列表。
  /// 播放列表每週更新，包含本週最熱門的新 MV。
  Future<List<Track>> getTrendingVideos({String category = 'music'}) async {
    logDebug('Getting YouTube trending videos via New This Week playlist');
    final tracks = await _fetchNewThisWeekPlaylist();
    logDebug('Got ${tracks.length} tracks from New This Week playlist');
    return tracks;
  }

  /// 使用 InnerTube Browse API 獲取 "New This Week" 播放列表
  Future<List<Track>> _fetchNewThisWeekPlaylist() async {
    final browseId = 'VL$_newThisWeekPlaylistId';
    logDebug('Fetching New This Week playlist via InnerTube browse: $browseId');

    try {
    final response = await _dio.post(
      '$_innerTubeApiBase/browse?key=$_innerTubeApiKey',
      data: jsonEncode({
        'browseId': browseId,
        'context': {
          'client': {
            'clientName': _innerTubeClientName,
            'clientVersion': _innerTubeClientVersion,
            'hl': 'en',
            'gl': 'US',
          },
        },
      }),
    );

    if (response.statusCode != 200) {
      if (response.statusCode == 429) {
        logWarning('YouTube rate limited (HTTP 429) for trending');
        throw YouTubeApiException(
          code: 'rate_limited',
          message: t.error.rateLimited,
        );
      }
      throw YouTubeApiException(
        code: 'api_error',
        message: 'InnerTube browse API returned status ${response.statusCode}',
      );
    }

    final data = response.data is String
        ? jsonDecode(response.data as String) as Map<String, dynamic>
        : response.data as Map<String, dynamic>;

    // 解析路徑:
    // contents.twoColumnBrowseResultsRenderer.tabs[0].tabRenderer.content
    //   .sectionListRenderer.contents[0].itemSectionRenderer.contents[0]
    //   .playlistVideoListRenderer.contents
    final tabs =
        data['contents']?['twoColumnBrowseResultsRenderer']?['tabs'] as List?;
    final tabContent = tabs?.firstOrNull?['tabRenderer']?['content'];
    final sectionContents =
        tabContent?['sectionListRenderer']?['contents'] as List?;
    final itemContents =
        sectionContents?.firstOrNull?['itemSectionRenderer']?['contents']
            as List?;
    final videoList = itemContents
        ?.firstOrNull?['playlistVideoListRenderer']?['contents'] as List?;

    if (videoList == null || videoList.isEmpty) {
      throw YouTubeApiException(
        code: 'parse_error',
        message: 'New This Week playlist data not found in API response',
      );
    }

    final tracks = <Track>[];
    for (final item in videoList) {
      final renderer = item['playlistVideoRenderer'] as Map<String, dynamic>?;
      if (renderer == null) continue;

      final videoId = renderer['videoId'] as String?;
      if (videoId == null) continue;

      // 標題
      final titleRuns = renderer['title']?['runs'] as List?;
      final title = titleRuns?.firstOrNull?['text'] as String? ?? 'Unknown';

      // 藝人/頻道名
      final bylineRuns = renderer['shortBylineText']?['runs'] as List?;
      final artist = bylineRuns?.firstOrNull?['text'] as String? ?? '';

      // 時長
      final lengthText = renderer['lengthText']?['simpleText'] as String?;
      final durationMs = _parseDurationText(lengthText);

      // 觀看次數
      final videoInfoRuns = renderer['videoInfo']?['runs'] as List?;
      final viewCountText = videoInfoRuns?.firstOrNull?['text'] as String?;
      final viewCount = _parseViewCountText(viewCountText);

      // 縮圖
      final thumbnails = renderer['thumbnail']?['thumbnails'] as List?;
      final thumbnailUrl = thumbnails?.isNotEmpty == true
          ? thumbnails!.last['url'] as String?
          : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

      tracks.add(Track()
        ..sourceId = videoId
        ..sourceType = SourceType.youtube
        ..title = title
        ..artist = artist
        ..durationMs = durationMs
        ..thumbnailUrl = thumbnailUrl
        ..viewCount = viewCount);
    }

    logDebug('Parsed New This Week playlist: ${tracks.length} tracks');
    return tracks;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is YouTubeApiException) rethrow;
      logError('Unexpected error in _fetchNewThisWeekPlaylist: $e');
      throw YouTubeApiException(code: 'error', message: e.toString());
    }
  }

  /// 通过 InnerTube /player API 获取音频流（认证路径，androidVr 客户端）
  Future<AudioStreamResult> _getAudioStreamViaInnerTube(
    String videoId,
    Map<String, String> authHeaders,
    AudioStreamConfig config,
  ) async {
    logDebug('Getting audio stream via InnerTube for: $videoId');
    try {
      // Use WEB client with auth headers directly.
      // ANDROID_VR + web cookies causes 400 errors (client/auth mismatch),
      // and this path is only reached as fallback for restricted content.
      final data = await _innerTubePlayerRequest(videoId, authHeaders);

      final streamingData = data['streamingData'] as Map<String, dynamic>?;
      if (streamingData == null) {
        throw YouTubeApiException(code: 'no_stream', message: 'No streaming data from InnerTube');
      }

      // Parse adaptiveFormats for audio-only streams
      final adaptiveFormats = streamingData['adaptiveFormats'] as List? ?? [];
      final audioFormats = adaptiveFormats.where((f) {
        final mimeType = f['mimeType'] as String? ?? '';
        return mimeType.startsWith('audio/');
      }).toList();

      if (audioFormats.isNotEmpty) {
        // Sort by bitrate descending
        audioFormats.sort((a, b) {
          final bitrateA = a['bitrate'] as int? ?? 0;
          final bitrateB = b['bitrate'] as int? ?? 0;
          return bitrateB.compareTo(bitrateA);
        });

        // Select by quality level
        final selectedIndex = switch (config.qualityLevel) {
          AudioQualityLevel.high => 0,
          AudioQualityLevel.medium => audioFormats.length ~/ 2,
          AudioQualityLevel.low => audioFormats.length - 1,
        };
        final selected = audioFormats[selectedIndex];
        final url = selected['url'] as String?;

        if (url != null) {
          final mimeType = selected['mimeType'] as String? ?? '';
          final codec = RegExp(r'codecs="([^"]+)"').firstMatch(mimeType)?.group(1);
          final container = mimeType.contains('webm') ? 'webm' : 'mp4';

          logDebug('Got audio-only stream via InnerTube for $videoId');
          return AudioStreamResult(
            url: url,
            bitrate: selected['bitrate'] as int?,
            container: container,
            codec: codec,
            streamType: StreamType.audioOnly,
          );
        }
      }

      // Fallback to muxed formats
      final formats = streamingData['formats'] as List? ?? [];
      if (formats.isNotEmpty) {
        final muxed = formats.first;
        final url = muxed['url'] as String?;
        if (url != null) {
          logDebug('Got muxed stream via InnerTube for $videoId');
          return AudioStreamResult(
            url: url,
            bitrate: muxed['bitrate'] as int?,
            container: 'mp4',
            codec: null,
            streamType: StreamType.muxed,
          );
        }
      }

      throw YouTubeApiException(code: 'no_stream', message: 'No audio stream available via InnerTube');
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is YouTubeApiException) rethrow;
      logError('Failed to get audio stream via InnerTube: $videoId, error: $e');
      throw YouTubeApiException(code: 'error', message: 'Failed to get audio stream: $e');
    }
  }

  /// 通过 InnerTube /browse API 解析播放列表（认证路径）
  Future<PlaylistParseResult> _parsePlaylistViaInnerTube(
    String playlistId,
    Map<String, String> authHeaders, {
    String? playlistUrl,
  }) async {
    logDebug('Parsing playlist via InnerTube for: $playlistId');
    try {
      final browseId = 'VL$playlistId';
      final response = await _dio.post(
        '$_innerTubeApiBase/browse?key=$_innerTubeApiKey',
        data: jsonEncode({
          'browseId': browseId,
          'context': {
            'client': {
              'clientName': _innerTubeClientName,
              'clientVersion': _innerTubeClientVersion,
              'hl': 'en',
              'gl': 'US',
            },
          },
        }),
        options: _innerTubeAuthOptions(authHeaders),
      );

      final data = _parseJsonResponse(response.data);

      // Parse playlist title from header
      // InnerTube may use playlistHeaderRenderer (old) or pageHeaderRenderer (new)
      final header = data['header'] as Map<String, dynamic>?;
      String playlistTitle = 'Playlist';
      String? ownerName;
      String? ownerUserId;
      final playlistHeaderRenderer = header?['playlistHeaderRenderer'] as Map<String, dynamic>?;
      if (playlistHeaderRenderer != null) {
        playlistTitle = playlistHeaderRenderer['title']?['simpleText'] as String? ?? playlistTitle;
        // Extract owner name and channel ID from ownerText.runs[0]
        final ownerRuns = playlistHeaderRenderer['ownerText']?['runs'] as List?;
        final firstRun = ownerRuns?.firstOrNull as Map<String, dynamic>?;
        ownerName = firstRun?['text'] as String?;
        ownerUserId = firstRun?['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
      } else {
        final pageHeaderRenderer = header?['pageHeaderRenderer'] as Map<String, dynamic>?;
        // pageHeaderRenderer.pageTitle is the simplest path
        playlistTitle = pageHeaderRenderer?['pageTitle'] as String?
            // Fallback: content.pageHeaderViewModel.title.dynamicTextViewModel.text.content
            ?? (pageHeaderRenderer?['content']?['pageHeaderViewModel']?['title']
                ?['dynamicTextViewModel']?['text']?['content'] as String?)
            ?? playlistTitle;

        // Extract owner info from pageHeaderViewModel metadata
        final metadata = pageHeaderRenderer?['content']?['pageHeaderViewModel']
            ?['metadata']?['contentMetadataViewModel'] as Map<String, dynamic>?;
        final metadataRows = metadata?['metadataRows'] as List?;
        if (metadataRows != null && metadataRows.isNotEmpty) {
          final firstRow = metadataRows.first as Map<String, dynamic>?;
          final metadataParts = firstRow?['metadataParts'] as List?;
          if (metadataParts != null && metadataParts.isNotEmpty) {
            final firstPart = metadataParts.first as Map<String, dynamic>?;
            final text = firstPart?['text'] as Map<String, dynamic>?;
            ownerName = text?['content'] as String?;
            // Extract channel ID from commandRuns
            final commandRuns = text?['commandRuns'] as List?;
            if (commandRuns != null && commandRuns.isNotEmpty) {
              final firstCommand = commandRuns.first as Map<String, dynamic>?;
              ownerUserId = firstCommand?['onTap']?['innertubeCommand']
                  ?['browseEndpoint']?['browseId'] as String?;
            }
          }
        }
      }

      // Fallback: extract owner info from sidebar if not found in header
      if (ownerName == null || ownerUserId == null) {
        final sidebar = data['sidebar']?['playlistSidebarRenderer']?['items'] as List?;
        if (sidebar != null && sidebar.length > 1) {
          final secondaryInfo = sidebar[1]
              ?['playlistSidebarSecondaryInfoRenderer'] as Map<String, dynamic>?;
          final videoOwner = secondaryInfo?['videoOwner']
              ?['videoOwnerRenderer'] as Map<String, dynamic>?;
          if (videoOwner != null) {
            final ownerRuns = videoOwner['title']?['runs'] as List?;
            final firstRun = ownerRuns?.firstOrNull as Map<String, dynamic>?;
            ownerName ??= firstRun?['text'] as String?;
            ownerUserId ??= firstRun?['navigationEndpoint']
                ?['browseEndpoint']?['browseId'] as String?;
            // Also try videoOwnerRenderer's own navigationEndpoint
            ownerUserId ??= videoOwner['navigationEndpoint']
                ?['browseEndpoint']?['browseId'] as String?;
          }
        }
      }

      if (ownerName == null && ownerUserId == null) {
        logDebug('Could not extract owner info from InnerTube response for playlist: $playlistId');
      }

      // Parse video items
      final tabs = data['contents']?['twoColumnBrowseResultsRenderer']?['tabs'] as List?;
      final tabContent = tabs?.firstOrNull?['tabRenderer']?['content'];
      final sectionContents = tabContent?['sectionListRenderer']?['contents'] as List?;
      final itemContents = sectionContents?.firstOrNull?['itemSectionRenderer']?['contents'] as List?;
      final videoList = itemContents?.firstOrNull?['playlistVideoListRenderer']?['contents'] as List?;

      final tracks = <Track>[];
      var skippedPrivate = 0;
      if (videoList != null) {
        for (final item in videoList) {
          final renderer = item['playlistVideoRenderer'] as Map<String, dynamic>?;
          if (renderer == null) continue;

          final videoId = renderer['videoId'] as String?;
          if (videoId == null) continue;

          // Skip private/unavailable videos (no duration = not playable)
          final isPlayable = renderer['isPlayable'] as bool? ?? true;
          final lengthText = renderer['lengthText']?['simpleText'] as String?;
          if (!isPlayable || lengthText == null) {
            skippedPrivate++;
            continue;
          }

          final titleRuns = renderer['title']?['runs'] as List?;
          final title = titleRuns?.firstOrNull?['text'] as String? ?? 'Unknown';

          final bylineRuns = renderer['shortBylineText']?['runs'] as List?;
          final artist = bylineRuns?.firstOrNull?['text'] as String? ?? '';

          final durationMs = _parseDurationText(lengthText);

          final thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';

          tracks.add(Track()
            ..sourceId = videoId
            ..sourceType = SourceType.youtube
            ..title = title
            ..artist = artist
            ..durationMs = durationMs
            ..thumbnailUrl = thumbnailUrl);
        }
      }

      if (skippedPrivate > 0) {
        logInfo('Skipped $skippedPrivate private/unavailable videos in playlist $playlistId');
      }

      if (tracks.isEmpty) {
        throw YouTubeApiException(
          code: 'private_or_inaccessible',
          message: t.importSource.playlistEmptyOrInaccessible,
        );
      }

      final coverUrl = tracks.isNotEmpty ? tracks.first.thumbnailUrl : null;

      logDebug('Parsed playlist via InnerTube: $playlistTitle, ${tracks.length} tracks');
      return PlaylistParseResult(
        title: playlistTitle,
        description: null,
        coverUrl: coverUrl,
        tracks: tracks,
        totalCount: tracks.length,
        sourceUrl: playlistUrl ?? 'https://www.youtube.com/playlist?list=$playlistId',
        ownerName: ownerName,
        ownerUserId: ownerUserId,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is YouTubeApiException) rethrow;
      logError('Failed to parse playlist via InnerTube: $playlistId, error: $e');
      throw YouTubeApiException(code: 'error', message: 'Failed to parse playlist: $e');
    }
  }

  // ==================== 错误处理 ====================

  /// 通过 InnerTube /player API 获取视频信息（认证路径）
  Future<Track> _getTrackInfoViaInnerTube(
    String videoId,
    Map<String, String> authHeaders,
  ) async {
    logDebug('Getting track info via InnerTube for: $videoId');
    try {
      final data = await _innerTubePlayerRequest(videoId, authHeaders);

      final videoDetails = data['videoDetails'] as Map<String, dynamic>?;
      if (videoDetails == null) {
        throw YouTubeApiException(code: 'parse_error', message: 'No videoDetails in response');
      }

      final lengthSeconds = int.tryParse(videoDetails['lengthSeconds']?.toString() ?? '0') ?? 0;
      final viewCount = int.tryParse(videoDetails['viewCount']?.toString() ?? '0') ?? 0;
      final thumbnails = videoDetails['thumbnail']?['thumbnails'] as List?;
      final thumbnailUrl = thumbnails?.isNotEmpty == true
          ? thumbnails!.last['url'] as String?
          : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

      final track = Track()
        ..sourceId = videoId
        ..sourceType = SourceType.youtube
        ..title = videoDetails['title'] as String? ?? 'Unknown'
        ..artist = videoDetails['author'] as String? ?? ''
        ..channelId = videoDetails['channelId'] as String? ?? ''
        ..durationMs = lengthSeconds * 1000
        ..thumbnailUrl = thumbnailUrl
        ..viewCount = viewCount
        ..createdAt = DateTime.now();

      logDebug('Got track info via InnerTube for $videoId: ${track.title}');
      return track;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is YouTubeApiException) rethrow;
      logError('Failed to get track info via InnerTube: $videoId, error: $e');
      throw YouTubeApiException(code: 'error', message: 'Failed to get video info: $e');
    }
  }

  /// 通过 InnerTube /player API 获取视频详情（认证路径）
  Future<VideoDetail> _getVideoDetailViaInnerTube(
    String videoId,
    Map<String, String> authHeaders,
  ) async {
    logDebug('Getting video detail via InnerTube for: $videoId');
    try {
      final data = await _innerTubePlayerRequest(videoId, authHeaders);

      final videoDetails = data['videoDetails'] as Map<String, dynamic>?;
      if (videoDetails == null) {
        throw YouTubeApiException(code: 'parse_error', message: 'No videoDetails in response');
      }

      final lengthSeconds = int.tryParse(videoDetails['lengthSeconds']?.toString() ?? '0') ?? 0;
      final viewCount = int.tryParse(videoDetails['viewCount']?.toString() ?? '0') ?? 0;
      final thumbnails = videoDetails['thumbnail']?['thumbnails'] as List?;
      final thumbnailUrl = thumbnails?.isNotEmpty == true
          ? thumbnails!.last['url'] as String?
          : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

      return VideoDetail.fromYouTube(
        videoId: videoId,
        title: videoDetails['title'] as String? ?? 'Unknown',
        description: videoDetails['shortDescription'] as String? ?? '',
        author: videoDetails['author'] as String? ?? '',
        authorAvatarUrl: null,
        thumbnailUrl: thumbnailUrl,
        channelId: videoDetails['channelId'] as String? ?? '',
        durationMs: lengthSeconds * 1000,
        viewCount: viewCount,
        likeCount: 0,
        publishDate: null,
        comments: [],
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is YouTubeApiException) rethrow;
      logError('Failed to get video detail via InnerTube: $videoId, error: $e');
      throw YouTubeApiException(code: 'error', message: 'Failed to get video detail: $e');
    }
  }

  // ==================== 错误处理 ====================

  /// 检查错误是否为限流错误
  bool _isRateLimitError(dynamic e) {
    final errorStr = e.toString().toLowerCase();
    return errorStr.contains('429') ||
        errorStr.contains('rate') ||
        errorStr.contains('quota') ||
        errorStr.contains('too many');
  }

  /// 处理 Dio 错误（用于 InnerTube API 调用）
    YouTubeApiException _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    logError('YouTube Dio error: type=${e.type}, statusCode=$statusCode');

    final classified = SourceApiException.classifyDioError(e);
    return YouTubeApiException(code: classified.code, message: classified.message);
  }

  @override
  void dispose() {
    _youtube.close();
    _dio.close();
  }
}

/// Mix 播放列表基本信息（用於導入時只存元數據）
class MixPlaylistInfo {
  final String title;
  final String playlistId;
  final String seedVideoId;
  final String? coverUrl;

  const MixPlaylistInfo({
    required this.title,
    required this.playlistId,
    required this.seedVideoId,
    this.coverUrl,
  });
}

/// Mix 播放列表獲取結果（用於加載 tracks）
class MixFetchResult {
  final String title;
  final List<Track> tracks;

  const MixFetchResult({
    required this.title,
    required this.tracks,
  });
}


