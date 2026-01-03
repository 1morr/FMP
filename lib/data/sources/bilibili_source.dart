import 'package:dio/dio.dart';
import '../models/track.dart';
import 'base_source.dart';

/// Bilibili 音源实现
class BilibiliSource extends BaseSource {
  late final Dio _dio;

  // API 端点
  static const String _apiBase = 'https://api.bilibili.com';
  static const String _viewApi = '$_apiBase/x/web-interface/view';
  static const String _playUrlApi = '$_apiBase/x/player/playurl';
  static const String _searchApi = '$_apiBase/x/web-interface/search/type';
  static const String _favListApi = '$_apiBase/x/v3/fav/resource/list';

  BilibiliSource() {
    _dio = Dio(BaseOptions(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com',
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  @override
  SourceType get sourceType => SourceType.bilibili;

  @override
  String get sourceName => 'Bilibili';

  @override
  String? parseId(String url) {
    // 支持多种 URL 格式:
    // - https://www.bilibili.com/video/BV1xx411c7mD
    // - https://b23.tv/BV1xx411c7mD
    // - https://m.bilibili.com/video/BV1xx411c7mD
    // - BV1xx411c7mD (纯 BV 号)

    // 尝试匹配 BV 号
    final bvRegex = RegExp(r'BV[a-zA-Z0-9]{10}');
    final match = bvRegex.firstMatch(url);
    if (match != null) {
      return match.group(0);
    }

    // 尝试匹配 av 号并转换（暂不实现，保留接口）
    final avRegex = RegExp(r'av(\d+)', caseSensitive: false);
    final avMatch = avRegex.firstMatch(url);
    if (avMatch != null) {
      // TODO: 实现 av 号转 BV 号
      return null;
    }

    return null;
  }

  @override
  bool isValidId(String id) {
    return RegExp(r'^BV[a-zA-Z0-9]{10}$').hasMatch(id);
  }

  @override
  bool isPlaylistUrl(String url) {
    // 收藏夹 URL 格式:
    // - https://space.bilibili.com/xxx/favlist?fid=xxx
    // - https://www.bilibili.com/medialist/detail/mlxxx
    return url.contains('favlist') ||
        url.contains('medialist') ||
        url.contains('/fav/') ||
        RegExp(r'fid=\d+').hasMatch(url) ||
        RegExp(r'ml\d+').hasMatch(url);
  }

  @override
  Future<Track> getTrackInfo(String bvid) async {
    try {
      final response = await _dio.get(
        _viewApi,
        queryParameters: {'bvid': bvid},
      );

      _checkResponse(response.data);

      final data = response.data['data'];
      final track = Track()
        ..sourceId = bvid
        ..sourceType = SourceType.bilibili
        ..title = data['title'] ?? 'Unknown'
        ..artist = data['owner']?['name']
        ..durationMs = ((data['duration'] as int?) ?? 0) * 1000
        ..thumbnailUrl = data['pic'];

      // 获取音频 URL
      final audioUrl = await getAudioUrl(bvid);
      track.audioUrl = audioUrl;
      track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 2));
      track.createdAt = DateTime.now();

      return track;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<String> getAudioUrl(String bvid) async {
    try {
      // 1. 获取视频 cid
      final viewResponse = await _dio.get(
        _viewApi,
        queryParameters: {'bvid': bvid},
      );

      _checkResponse(viewResponse.data);

      final cid = viewResponse.data['data']['cid'];
      if (cid == null) {
        throw Exception('Failed to get cid for $bvid');
      }

      // 2. 获取播放 URL（DASH 格式）
      final playUrlResponse = await _dio.get(
        _playUrlApi,
        queryParameters: {
          'bvid': bvid,
          'cid': cid,
          'fnval': 16, // DASH 格式
          'qn': 0, // 最高画质
          'fourk': 1,
        },
      );

      _checkResponse(playUrlResponse.data);

      final dash = playUrlResponse.data['data']['dash'];
      if (dash == null) {
        // 尝试获取普通格式
        final durl = playUrlResponse.data['data']['durl'];
        if (durl != null && durl is List && durl.isNotEmpty) {
          return durl[0]['url'] as String;
        }
        throw Exception('No audio stream available');
      }

      // 从 DASH 格式中获取音频流
      final audios = dash['audio'] as List?;
      if (audios == null || audios.isEmpty) {
        throw Exception('No audio stream in DASH');
      }

      // 按带宽排序，选择最高音质
      audios.sort(
          (a, b) => (b['bandwidth'] as int).compareTo(a['bandwidth'] as int));

      // 优先使用 baseUrl，备用 backupUrl
      final bestAudio = audios.first;
      return bestAudio['baseUrl'] ?? bestAudio['base_url'] ?? bestAudio['backupUrl']?[0];
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<Track> refreshAudioUrl(Track track) async {
    if (track.sourceType != SourceType.bilibili) {
      throw Exception('Invalid source type for BilibiliSource');
    }

    final audioUrl = await getAudioUrl(track.sourceId);
    track.audioUrl = audioUrl;
    track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 2));
    track.updatedAt = DateTime.now();
    return track;
  }

  @override
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get(
        _searchApi,
        queryParameters: {
          'keyword': query,
          'search_type': 'video',
          'page': page,
          'page_size': pageSize,
          'order': 'totalrank', // 综合排序
        },
      );

      _checkResponse(response.data);

      final data = response.data['data'];
      final results = data['result'] as List? ?? [];
      final numResults = data['numResults'] as int? ?? 0;

      final tracks = results.map((item) {
        return Track()
          ..sourceId = item['bvid'] ?? ''
          ..sourceType = SourceType.bilibili
          ..title = _cleanHtmlTags(item['title'] ?? 'Unknown')
          ..artist = item['author']
          ..durationMs = _parseDuration(item['duration'] ?? '0:00')
          ..thumbnailUrl = _fixImageUrl(item['pic']);
      }).toList();

      return SearchResult(
        tracks: tracks,
        totalCount: numResults,
        page: page,
        pageSize: pageSize,
        hasMore: page * pageSize < numResults,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      // 解析收藏夹 ID
      final fid = _parseFavoritesId(playlistUrl);
      if (fid == null) {
        throw Exception('Invalid favorites URL: $playlistUrl');
      }

      // 获取第一页，同时获取总数和元信息
      final firstResponse = await _dio.get(
        _favListApi,
        queryParameters: {
          'media_id': fid,
          'pn': 1,
          'ps': pageSize,
          'platform': 'web',
        },
      );

      _checkResponse(firstResponse.data);

      final data = firstResponse.data['data'];
      final info = data['info'];
      final totalCount = data['info']?['media_count'] ?? 0;
      final firstMedias = data['medias'] as List? ?? [];

      // 收集所有歌曲
      final allTracks = <Track>[];

      // 添加第一页的歌曲
      for (final item in firstMedias) {
        allTracks.add(Track()
          ..sourceId = item['bvid'] ?? ''
          ..sourceType = SourceType.bilibili
          ..title = item['title'] ?? 'Unknown'
          ..artist = item['upper']?['name']
          ..durationMs = ((item['duration'] as int?) ?? 0) * 1000
          ..thumbnailUrl = item['cover']);
      }

      // 计算总页数并获取剩余页面
      final totalPages = (totalCount / pageSize).ceil();

      for (int currentPage = 2; currentPage <= totalPages; currentPage++) {
        final response = await _dio.get(
          _favListApi,
          queryParameters: {
            'media_id': fid,
            'pn': currentPage,
            'ps': pageSize,
            'platform': 'web',
          },
        );

        _checkResponse(response.data);

        final medias = response.data['data']['medias'] as List? ?? [];
        if (medias.isEmpty) break; // 没有更多数据了

        for (final item in medias) {
          allTracks.add(Track()
            ..sourceId = item['bvid'] ?? ''
            ..sourceType = SourceType.bilibili
            ..title = item['title'] ?? 'Unknown'
            ..artist = item['upper']?['name']
            ..durationMs = ((item['duration'] as int?) ?? 0) * 1000
            ..thumbnailUrl = item['cover']);
        }

        // 添加小延迟避免请求过快
        await Future.delayed(const Duration(milliseconds: 200));
      }

      return PlaylistParseResult(
        title: info?['title'] ?? 'Favorites',
        description: info?['intro'],
        coverUrl: info?['cover'],
        tracks: allTracks,
        totalCount: allTracks.length,
        sourceUrl: playlistUrl,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<bool> checkAvailability(String sourceId) async {
    try {
      final response = await _dio.get(
        _viewApi,
        queryParameters: {'bvid': sourceId},
      );
      return response.data['code'] == 0;
    } catch (_) {
      return false;
    }
  }

  // ========== 辅助方法 ==========

  /// 检查 API 响应
  void _checkResponse(Map<String, dynamic> data) {
    final code = data['code'];
    if (code != 0) {
      final message = data['message'] ?? 'Unknown error';
      throw BilibiliApiException(code: code, message: message);
    }
  }

  /// 处理 Dio 错误
  Exception _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return Exception('Network timeout');
      case DioExceptionType.connectionError:
        return Exception('Network connection error');
      case DioExceptionType.badResponse:
        return Exception('Server error: ${e.response?.statusCode}');
      default:
        return Exception('Network error: ${e.message}');
    }
  }

  /// 解析收藏夹 ID
  String? _parseFavoritesId(String url) {
    // 格式1: fid=123456
    final fidMatch = RegExp(r'fid=(\d+)').firstMatch(url);
    if (fidMatch != null) {
      return fidMatch.group(1);
    }

    // 格式2: ml123456
    final mlMatch = RegExp(r'ml(\d+)').firstMatch(url);
    if (mlMatch != null) {
      return mlMatch.group(1);
    }

    // 格式3: /medialist/detail/ml123456
    final detailMatch = RegExp(r'/detail/ml(\d+)').firstMatch(url);
    if (detailMatch != null) {
      return detailMatch.group(1);
    }

    return null;
  }

  /// 清理 HTML 标签
  String _cleanHtmlTags(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'");
  }

  /// 解析时长字符串为毫秒
  int _parseDuration(String duration) {
    // 格式: "3:45" 或 "1:23:45"
    try {
      final parts = duration.split(':').map(int.parse).toList();
      if (parts.length == 2) {
        return (parts[0] * 60 + parts[1]) * 1000;
      } else if (parts.length == 3) {
        return (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
      }
    } catch (_) {}
    return 0;
  }

  /// 修复图片 URL（添加协议前缀）
  String? _fixImageUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    return url;
  }
}

/// Bilibili API 错误
class BilibiliApiException implements Exception {
  final int code;
  final String message;

  const BilibiliApiException({required this.code, required this.message});

  @override
  String toString() => 'BilibiliApiException($code): $message';

  /// 是否是视频不可用（已删除/下架）
  bool get isUnavailable => code == -404 || code == 62002;

  /// 是否需要登录
  bool get requiresLogin => code == -101;

  /// 是否是地区限制
  bool get isGeoRestricted => code == -10403;
}
