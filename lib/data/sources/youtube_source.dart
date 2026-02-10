import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../models/settings.dart';
import '../models/track.dart';
import '../models/video_detail.dart';
import 'base_source.dart';

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
    _dio = Dio(BaseOptions(
      headers: {
        'Content-Type': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
      connectTimeout: AppConstants.networkConnectTimeout,
      receiveTimeout: AppConstants.networkReceiveTimeout,
    ));
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
  Future<AudioStreamResult> getAudioStream(
    String videoId, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  }) async {
    logDebug('Getting audio stream for YouTube video: $videoId with config: qualityLevel=${config.qualityLevel}, streamPriority=${config.streamPriority}');
    
    // 按流类型优先级尝试
    for (final streamType in config.streamPriority) {
      try {
        final result = await _tryGetStream(videoId, streamType, config);
        if (result != null) {
          return result;
        }
      } catch (e) {
        logDebug('Stream type $streamType failed for $videoId: $e');
      }
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
    } catch (e, st) {
      // 检查是否是限流错误
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('429') ||
          errorStr.contains('rate') ||
          errorStr.contains('quota') ||
          errorStr.contains('too many')) {
        logWarning('YouTube rate limited for query: "$query", error: $e');
      } else {
        logError('YouTube search failed for query: "$query"', e, st);
      }
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
      logError('InnerTube API request failed: ${e.message}');
      throw YouTubeApiException(
        code: 'network_error',
        message: 'Failed to fetch Mix playlist: ${e.message}',
      );
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

      // 普通播放列表使用 youtube_explode_dart
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
      if (e is YouTubeApiException) rethrow;
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
  }

  /// 释放资源
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
