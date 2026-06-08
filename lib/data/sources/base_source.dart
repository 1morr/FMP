import '../models/settings.dart';
import '../models/track.dart';

/// 音频流配置
class AudioStreamConfig {
  /// 音质等级
  final AudioQualityLevel qualityLevel;

  /// 格式优先级（按顺序尝试，使用第一个可用格式）
  final List<AudioFormat> formatPriority;

  /// 流类型优先级（按顺序尝试）
  final List<StreamType> streamPriority;

  const AudioStreamConfig({
    this.qualityLevel = AudioQualityLevel.high,
    this.formatPriority = const [
      AudioFormat.opus,
      AudioFormat.aac,
    ],
    this.streamPriority = const [
      StreamType.audioOnly,
      StreamType.muxed,
      StreamType.hls,
    ],
  });

  /// 默认配置（高音质、Opus 优先）
  static const defaultConfig = AudioStreamConfig();

  AudioStreamConfig copyWith({
    AudioQualityLevel? qualityLevel,
    List<AudioFormat>? formatPriority,
    List<StreamType>? streamPriority,
  }) {
    return AudioStreamConfig(
      qualityLevel: qualityLevel ?? this.qualityLevel,
      formatPriority: formatPriority ?? this.formatPriority,
      streamPriority: streamPriority ?? this.streamPriority,
    );
  }

  /// 从 Settings 构建指定音源的配置
  factory AudioStreamConfig.fromSettings(
      Settings settings, SourceType sourceType) {
    final streamPriority = switch (sourceType) {
      SourceType.youtube => settings.youtubeStreamPriorityList,
      SourceType.bilibili => settings.bilibiliStreamPriorityList,
      SourceType.netease => settings.neteaseStreamPriorityList,
    };
    return AudioStreamConfig(
      qualityLevel: settings.audioQualityLevel,
      formatPriority: settings.audioFormatPriorityList,
      streamPriority: streamPriority,
    );
  }
}

/// Audio stream resolution request.
class AudioStreamRequest {
  final String sourceId;
  final int? cid;
  final int? pageNum;
  final AudioStreamConfig config;
  final Map<String, String>? authHeaders;
  final String? failedUrl;

  const AudioStreamRequest({
    required this.sourceId,
    this.cid,
    this.pageNum,
    this.config = AudioStreamConfig.defaultConfig,
    this.authHeaders,
    this.failedUrl,
  });

  AudioStreamRequest copyWith({
    String? sourceId,
    int? cid,
    bool clearCid = false,
    int? pageNum,
    bool clearPageNum = false,
    AudioStreamConfig? config,
    Map<String, String>? authHeaders,
    bool clearAuthHeaders = false,
    String? failedUrl,
    bool clearFailedUrl = false,
  }) {
    return AudioStreamRequest(
      sourceId: sourceId ?? this.sourceId,
      cid: clearCid ? null : (cid ?? this.cid),
      pageNum: clearPageNum ? null : (pageNum ?? this.pageNum),
      config: config ?? this.config,
      authHeaders: clearAuthHeaders ? null : (authHeaders ?? this.authHeaders),
      failedUrl: clearFailedUrl ? null : (failedUrl ?? this.failedUrl),
    );
  }
}

/// 音频流结果（包含元信息）
class AudioStreamResult {
  /// 音频流 URL
  final String url;

  /// 码率 (bps)
  final int? bitrate;

  /// 容器格式 (mp4, webm, m4a)
  final String? container;

  /// 编码 (aac, opus)
  final String? codec;

  /// 流类型
  final StreamType streamType;

  /// URL 有效期
  final Duration? expiry;

  const AudioStreamResult({
    required this.url,
    this.bitrate,
    this.container,
    this.codec,
    required this.streamType,
    this.expiry,
  });

  @override
  String toString() =>
      'AudioStreamResult(bitrate: ${bitrate != null ? "${(bitrate! / 1000).round()}kbps" : "unknown"}, '
      'container: $container, codec: $codec, streamType: $streamType)';
}

/// 搜索排序方式
enum SearchOrder {
  /// 综合排序（默认）
  relevance,

  /// 按播放量排序
  playCount,

  /// 按发布时间排序
  publishDate,
}

/// 搜索结果
class SearchResult {
  final List<Track> tracks;
  final int totalCount;
  final int page;
  final int pageSize;
  final bool hasMore;

  const SearchResult({
    required this.tracks,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  /// 空结果
  factory SearchResult.empty() => const SearchResult(
        tracks: [],
        totalCount: 0,
        page: 1,
        pageSize: 0,
        hasMore: false,
      );
}

/// 播放列表解析结果
class PlaylistParseResult {
  final String title;
  final String? description;
  final String? coverUrl;
  final List<Track> tracks;
  final int totalCount;
  final String sourceUrl;
  final String? ownerName;
  final String? ownerUserId;

  const PlaylistParseResult({
    required this.title,
    this.description,
    this.coverUrl,
    required this.tracks,
    required this.totalCount,
    required this.sourceUrl,
    this.ownerName,
    this.ownerUserId,
  });
}
