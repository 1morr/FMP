import '../models/track.dart';

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
}

/// 播放列表解析结果
class PlaylistParseResult {
  final String title;
  final String? description;
  final String? coverUrl;
  final List<Track> tracks;
  final int totalCount;
  final String sourceUrl;

  const PlaylistParseResult({
    required this.title,
    this.description,
    this.coverUrl,
    required this.tracks,
    required this.totalCount,
    required this.sourceUrl,
  });
}

/// 音源基类
/// 定义所有音源必须实现的接口
abstract class BaseSource {
  /// 音源类型
  SourceType get sourceType;

  /// 音源名称（用于显示）
  String get sourceName;

  /// 从 URL 解析出源ID
  /// 返回 null 表示不是此音源的有效 URL
  String? parseId(String url);

  /// 验证 ID 格式是否有效
  bool isValidId(String id);

  /// 判断 URL 是否属于此音源
  bool canHandle(String url) => parseId(url) != null;

  /// 获取单首歌曲信息
  /// [sourceId] 音源ID（如 BV号、YouTube视频ID）
  Future<Track> getTrackInfo(String sourceId);

  /// 获取音频流 URL
  /// 返回的 URL 可能会过期，需要定期刷新
  Future<String> getAudioUrl(String sourceId);

  /// 刷新歌曲的音频 URL
  /// 用于 URL 过期时重新获取
  Future<Track> refreshAudioUrl(Track track);

  /// 获取备选音频 URL（当主 URL 播放失败时使用）
  /// [sourceId] 音源 ID
  /// [failedUrl] 之前失败的 URL（用于排除相同流类型）
  /// 返回 null 表示没有可用的备选 URL
  Future<String?> getAlternativeAudioUrl(String sourceId, {String? failedUrl}) async {
    return null; // 默认不支持备选 URL
  }

  /// 搜索歌曲
  /// [query] 搜索关键词
  /// [page] 页码（从1开始）
  /// [pageSize] 每页数量
  /// [order] 排序方式
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  });

  /// 解析播放列表/收藏夹
  /// [playlistUrl] 播放列表 URL
  /// [page] 页码（从1开始，用于分页加载大型列表）
  /// [pageSize] 每页数量
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
  });

  /// 判断 URL 是否是播放列表
  bool isPlaylistUrl(String url);

  /// 检查歌曲是否仍然可用
  Future<bool> checkAvailability(String sourceId);
}
