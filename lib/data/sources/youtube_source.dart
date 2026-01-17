import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../core/logger.dart';
import '../models/track.dart';
import 'base_source.dart';

/// YouTube 音源实现
class YouTubeSource extends BaseSource with Logging {
  late final yt.YoutubeExplode _youtube;

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

      // 优先尝试 HLS 流（m3u8 格式，兼容性最好）
      if (manifest.hls.isNotEmpty) {
        final hlsStream = manifest.hls.first;
        logDebug('Got HLS stream for $videoId');
        return hlsStream.url.toString();
      }

      // 其次尝试 muxed 流（包含视频和音频，兼容性较好）
      if (manifest.muxed.isNotEmpty) {
        final muxedStream = manifest.muxed.withHighestBitrate();
        logDebug(
            'Using muxed stream for $videoId, bitrate: ${muxedStream.bitrate}');
        return muxedStream.url.toString();
      }

      // 最后尝试 audio-only 流
      if (manifest.audioOnly.isNotEmpty) {
        final audioStream = manifest.audioOnly.withHighestBitrate();
        logDebug(
            'Got audio-only stream for $videoId, bitrate: ${audioStream.bitrate}');
        return audioStream.url.toString();
      }

      logError('No audio stream available for YouTube video: $videoId');
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

  @override
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    logDebug('Searching YouTube for: $query, page: $page');
    try {
      // 获取搜索结果列表
      final searchList = await _youtube.search.search(query);

      // 计算跳过的数量
      final skip = (page - 1) * pageSize;
      final tracks = <Track>[];

      // 遍历搜索结果
      var index = 0;
      for (final video in searchList) {
        // 跳过前面的结果
        if (index < skip) {
          index++;
          continue;
        }

        tracks.add(Track()
          ..sourceId = video.id.value
          ..sourceType = SourceType.youtube
          ..title = video.title
          ..artist = video.author
          ..durationMs = video.duration?.inMilliseconds ?? 0
          ..thumbnailUrl = video.thumbnails.highResUrl
          ..viewCount = video.engagement.viewCount);

        if (tracks.length >= pageSize) break;
        index++;
      }

      // 如果结果不够，尝试获取更多页
      if (tracks.length < pageSize && searchList.length >= skip + pageSize) {
        final nextPage = await searchList.nextPage();
        if (nextPage != null) {
          for (final video in nextPage) {
            tracks.add(Track()
              ..sourceId = video.id.value
              ..sourceType = SourceType.youtube
              ..title = video.title
              ..artist = video.author
              ..durationMs = video.duration?.inMilliseconds ?? 0
              ..thumbnailUrl = video.thumbnails.highResUrl
              ..viewCount = video.engagement.viewCount);
            if (tracks.length >= pageSize) break;
          }
        }
      }

      logDebug('YouTube search returned ${tracks.length} results for: $query');

      return SearchResult(
        tracks: tracks,
        // YouTube 搜索不返回精确总数，估算一个值
        totalCount: skip + tracks.length + (tracks.length == pageSize ? 100 : 0),
        page: page,
        pageSize: pageSize,
        hasMore: tracks.length == pageSize,
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
