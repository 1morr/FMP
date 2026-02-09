import 'dart:math';

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../models/live_room.dart';
import '../models/settings.dart';
import '../models/track.dart';
import '../models/video_detail.dart';
import 'base_source.dart';

/// Bilibili 音源实现
class BilibiliSource extends BaseSource with Logging {
  late final Dio _dio;

  // API 端点
  static const String _apiBase = 'https://api.bilibili.com';
  static const String _liveApiBase = 'https://api.live.bilibili.com';
  static const String _viewApi = '$_apiBase/x/web-interface/view';
  static const String _playUrlApi = '$_apiBase/x/player/playurl';
  static const String _searchApi = '$_apiBase/x/web-interface/search/type';
  static const String _favListApi = '$_apiBase/x/v3/fav/resource/list';
  static const String _replyApi = '$_apiBase/x/v2/reply';
  static const String _rankingApi = '$_apiBase/x/web-interface/ranking/v2';
  // 直播相关 API
  static const String _liveRoomInfoApi = '$_liveApiBase/room/v1/Room/get_info';
  static const String _livePlayUrlApi = '$_liveApiBase/room/v1/Room/playUrl';
  static const String _liveAnchorInfoApi = '$_liveApiBase/live_user/v1/UserInfo/get_anchor_in_room';

  BilibiliSource() {
    // 生成 buvid3 Cookie（用于绕过 412 风控）
    final buvid3 = _generateBuvid3();
    
    _dio = Dio(BaseOptions(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com',
        'Cookie': 'buvid3=$buvid3',
      },
      connectTimeout: AppConstants.networkConnectTimeout,
      receiveTimeout: AppConstants.networkReceiveTimeout,
    ));
  }

  /// 生成 buvid3 Cookie
  /// 格式: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXXinfoc
  String _generateBuvid3() {
    final random = Random();
    String randomHex(int length) {
      const chars = '0123456789ABCDEF';
      return List.generate(length, (_) => chars[random.nextInt(16)]).join();
    }
    return '${randomHex(8)}-${randomHex(4)}-${randomHex(4)}-${randomHex(4)}-${randomHex(12)}infoc';
  }

  /// 将 SearchOrder 映射到 Bilibili API 的排序参数
  String _mapSearchOrder(SearchOrder order) {
    switch (order) {
      case SearchOrder.relevance:
        return 'totalrank'; // 综合排序
      case SearchOrder.playCount:
        return 'click'; // 按播放量
      case SearchOrder.publishDate:
        return 'pubdate'; // 按发布时间
    }
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

    final bvRegex = RegExp(r'BV[a-zA-Z0-9]{10}');
    final match = bvRegex.firstMatch(url);
    return match?.group(0);
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
        ..ownerId = data['owner']?['mid'] as int?
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
  Future<AudioStreamResult> getAudioStream(
    String bvid, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  }) async {
    logDebug('Getting audio stream for bvid: $bvid with config: qualityLevel=${config.qualityLevel}');
    try {
      // 1. 获取视频 cid
      final viewResponse = await _dio.get(
        _viewApi,
        queryParameters: {'bvid': bvid},
      );

      _checkResponse(viewResponse.data);

      final cid = viewResponse.data['data']['cid'];
      if (cid == null) {
        logError('Failed to get cid for $bvid');
        throw Exception('Failed to get cid for $bvid');
      }
      logDebug('Got cid: $cid for bvid: $bvid');

      return _getAudioStreamWithCid(bvid, cid, config);
    } on BilibiliApiException catch (e) {
      logError('Bilibili API error for $bvid: code=${e.code}, message=${e.message}');
      rethrow;
    } on DioException catch (e) {
      logError('Network error getting audio URL for $bvid: ${e.type}, ${e.message}');
      throw _handleDioError(e);
    }
  }

  /// 使用指定 cid 获取音频流
  Future<AudioStreamResult> _getAudioStreamWithCid(
    String bvid,
    int cid,
    AudioStreamConfig config,
  ) async {
    // 按流类型优先级尝试
    for (final streamType in config.streamPriority) {
      try {
        final result = await _tryGetStreamByType(bvid, cid, streamType, config);
        if (result != null) {
          return result;
        }
      } catch (e) {
        logDebug('Stream type $streamType failed for $bvid:$cid: $e');
      }
    }

    logError('No audio stream available for $bvid:$cid');
    throw Exception('No audio stream available');
  }

  /// 根据流类型获取对应的流
  Future<AudioStreamResult?> _tryGetStreamByType(
    String bvid,
    int cid,
    StreamType streamType,
    AudioStreamConfig config,
  ) async {
    switch (streamType) {
      case StreamType.audioOnly:
        return _tryGetDashStream(bvid, cid, config);
      case StreamType.muxed:
        return _tryGetDurlStream(bvid, cid);
      case StreamType.hls:
        return null; // Bilibili 不支持 HLS
    }
  }

  /// 尝试获取 DASH 音频流（需要 fnval=16）
  Future<AudioStreamResult?> _tryGetDashStream(
    String bvid,
    int cid,
    AudioStreamConfig config,
  ) async {
    final response = await _dio.get(
      _playUrlApi,
      queryParameters: {
        'bvid': bvid,
        'cid': cid,
        'fnval': 16, // DASH 格式
        'qn': 0,
        'fourk': 1,
      },
    );

    _checkResponse(response.data);
    final data = response.data['data'];
    
    final dash = data['dash'];
    if (dash == null) return null;

    final audios = dash['audio'] as List?;
    if (audios == null || audios.isEmpty) return null;

    // 按带宽排序
    final sortedAudios = List<Map<String, dynamic>>.from(audios);
    sortedAudios.sort((a, b) => (b['bandwidth'] as int).compareTo(a['bandwidth'] as int));

    // 根据音质等级选择
    final selected = _selectByQualityLevel(sortedAudios, config.qualityLevel);
    if (selected == null) return null;

    final audioUrl = selected['baseUrl'] ?? selected['base_url'] ?? (selected['backupUrl'] as List?)?[0];
    if (audioUrl == null) return null;

    final bandwidth = selected['bandwidth'] as int;
    logDebug('Got DASH audio stream for $bvid:$cid, bandwidth: $bandwidth');

    return AudioStreamResult(
      url: audioUrl,
      bitrate: bandwidth,
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
    );
  }

  /// 尝试获取 durl 流（混合流，需要 fnval=0）
  Future<AudioStreamResult?> _tryGetDurlStream(
    String bvid,
    int cid,
  ) async {
    final response = await _dio.get(
      _playUrlApi,
      queryParameters: {
        'bvid': bvid,
        'cid': cid,
        'fnval': 0, // durl 格式（混合流）
        'qn': 120, // 请求高画质
      },
    );

    _checkResponse(response.data);
    final data = response.data['data'];

    final durl = data['durl'];
    if (durl == null || durl is! List || durl.isEmpty) return null;

    final url = durl[0]['url'] as String?;
    if (url == null) return null;

    logDebug('Got durl (muxed) stream for $bvid:$cid');
    return AudioStreamResult(
      url: url,
      bitrate: null, // durl 格式不提供准确的音频码率
      container: 'flv',
      codec: null,
      streamType: StreamType.muxed,
    );
  }

  /// 根据音质等级选择
  T? _selectByQualityLevel<T>(List<T> sortedItems, AudioQualityLevel level) {
    if (sortedItems.isEmpty) return null;

    switch (level) {
      case AudioQualityLevel.high:
        return sortedItems.first;
      case AudioQualityLevel.medium:
        return sortedItems[sortedItems.length ~/ 2];
      case AudioQualityLevel.low:
        return sortedItems.last;
    }
  }

  @override
  Future<Track> refreshAudioUrl(Track track) async {
    if (track.sourceType != SourceType.bilibili) {
      throw Exception('Invalid source type for BilibiliSource');
    }

    // 如果有cid，使用指定cid获取音频URL
    final String audioUrl;
    if (track.cid != null) {
      audioUrl = await getAudioUrlWithCid(track.sourceId, track.cid!);
    } else {
      audioUrl = await getAudioUrl(track.sourceId);
    }
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
    SearchOrder order = SearchOrder.relevance,
  }) async {
    try {
      final response = await _dio.get(
        _searchApi,
        queryParameters: {
          'keyword': query,
          'search_type': 'video',
          'page': page,
          'page_size': pageSize,
          'order': _mapSearchOrder(order),
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
          ..ownerId = item['mid'] as int?
          ..durationMs = _parseDuration(item['duration'] ?? '0:00')
          ..thumbnailUrl = _fixImageUrl(item['pic'])
          ..viewCount = item['play'] as int?;
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
          ..ownerId = item['upper']?['mid'] as int?
          ..durationMs = ((item['duration'] as int?) ?? 0) * 1000
          ..thumbnailUrl = item['cover']
          ..pageCount = item['page'] as int? ?? 1);
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
            ..ownerId = item['upper']?['mid'] as int?
            ..durationMs = ((item['duration'] as int?) ?? 0) * 1000
            ..thumbnailUrl = item['cover']
            ..pageCount = item['page'] as int? ?? 1);
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

  /// 获取视频分P列表
  Future<List<VideoPage>> getVideoPages(String bvid) async {
    try {
      final response = await _dio.get(
        _viewApi,
        queryParameters: {'bvid': bvid},
      );

      _checkResponse(response.data);

      final pages = response.data['data']['pages'] as List? ?? [];
      return pages.map((p) => VideoPage(
        cid: p['cid'] as int,
        page: p['page'] as int,
        part: p['part'] as String? ?? 'P${p['page']}',
        duration: p['duration'] as int? ?? 0,
      )).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 获取指定分P的音频流
  Future<AudioStreamResult> getAudioStreamWithCid(
    String bvid,
    int cid, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  }) async {
    logDebug('Getting audio stream for bvid: $bvid, cid: $cid');
    try {
      return _getAudioStreamWithCid(bvid, cid, config);
    } on BilibiliApiException catch (e) {
      logError('Bilibili API error for $bvid:$cid: code=${e.code}, message=${e.message}');
      rethrow;
    } on DioException catch (e) {
      logError('Network error getting audio URL for $bvid:$cid: ${e.type}, ${e.message}');
      throw _handleDioError(e);
    }
  }

  /// 获取指定分P的音频URL（简化版，向后兼容）
  Future<String> getAudioUrlWithCid(String bvid, int cid, {AudioStreamConfig? config}) async {
    final result = await getAudioStreamWithCid(bvid, cid, config: config ?? AudioStreamConfig.defaultConfig);
    return result.url;
  }

  /// 获取视频详细信息（包括统计数据和UP主信息）
  Future<VideoDetail> getVideoDetail(String bvid) async {
    try {
      // 获取视频信息
      final viewResponse = await _dio.get(
        _viewApi,
        queryParameters: {'bvid': bvid},
      );

      _checkResponse(viewResponse.data);

      final data = viewResponse.data['data'];
      final stat = data['stat'];
      final owner = data['owner'];

      // 解析分P信息
      final pagesData = data['pages'] as List? ?? [];
      final pages = pagesData.map((p) => VideoPage(
        cid: p['cid'] as int,
        page: p['page'] as int,
        part: p['part'] as String? ?? 'P${p['page']}',
        duration: p['duration'] as int? ?? 0,
      )).toList();

      // 获取热门评论
      final comments = await getHotComments(bvid, limit: 3);

      return VideoDetail(
        bvid: bvid,
        title: data['title'] ?? '',
        description: data['desc'] ?? '',
        coverUrl: data['pic'] ?? '',
        ownerName: owner?['name'] ?? '',
        ownerFace: owner?['face'] ?? '',
        ownerId: owner?['mid'] ?? 0,
        viewCount: stat?['view'] ?? 0,
        likeCount: stat?['like'] ?? 0,
        coinCount: stat?['coin'] ?? 0,
        favoriteCount: stat?['favorite'] ?? 0,
        shareCount: stat?['share'] ?? 0,
        danmakuCount: stat?['danmaku'] ?? 0,
        commentCount: stat?['reply'] ?? 0,
        publishDate: DateTime.fromMillisecondsSinceEpoch(
          (data['pubdate'] as int? ?? 0) * 1000,
        ),
        durationSeconds: data['duration'] as int? ?? 0,
        hotComments: comments,
        pages: pages,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 获取热门评论
  Future<List<VideoComment>> getHotComments(String bvid, {int limit = 5}) async {
    try {
      // 首先获取视频的 aid
      final viewResponse = await _dio.get(
        _viewApi,
        queryParameters: {'bvid': bvid},
      );

      _checkResponse(viewResponse.data);
      final aid = viewResponse.data['data']['aid'];

      // 获取热门评论
      final replyResponse = await _dio.get(
        _replyApi,
        queryParameters: {
          'type': 1, // 视频类型
          'oid': aid,
          'sort': 1, // 按热度排序
          'ps': limit,
          'pn': 1,
        },
      );

      _checkResponse(replyResponse.data);

      final replies = replyResponse.data['data']['replies'] as List? ?? [];

      return replies.map((reply) {
        final member = reply['member'];
        return VideoComment(
          id: reply['rpid'] as int? ?? 0,
          content: reply['content']?['message'] ?? '',
          memberName: member?['uname'] ?? '',
          memberAvatar: member?['avatar'] ?? '',
          likeCount: reply['like'] as int? ?? 0,
          createTime: DateTime.fromMillisecondsSinceEpoch(
            (reply['ctime'] as int? ?? 0) * 1000,
          ),
        );
      }).toList();
    } on DioException catch (e) {
      logError('Failed to get hot comments for $bvid: ${e.message}');
      return []; // 评论获取失败不影响主要功能
    } catch (e) {
      logError('Failed to get hot comments for $bvid: $e');
      return [];
    }
  }

  // ========== 排行榜视频 API ==========

  /// 获取排行榜视频
  /// [rid] 分区 ID：0=全站，1=动画，3=音乐，4=游戏，5=娱乐，36=科技，119=鬼畜，129=舞蹈，155=时尚，160=生活，181=影视
  Future<List<Track>> getRankingVideos({int rid = 0}) async {
    try {
      final response = await _dio.get(
        _rankingApi,
        queryParameters: {
          'rid': rid,
          'type': 'all',
        },
      );

      _checkResponse(response.data);

      final list = response.data['data']['list'] as List? ?? [];
      
      return list.map((item) {
        final owner = item['owner'] ?? {};
        final stat = item['stat'] ?? {};
        
        return Track()
          ..sourceId = item['bvid'] ?? ''
          ..sourceType = SourceType.bilibili
          ..title = item['title'] ?? ''
          ..artist = owner['name'] ?? ''
          ..ownerId = owner['mid'] as int?
          ..durationMs = ((item['duration'] as int?) ?? 0) * 1000
          ..thumbnailUrl = _fixImageUrl(item['pic'])
          ..viewCount = stat['view'] as int?
          ..createdAt = DateTime.now();
      }).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
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

  // ========== 直播间搜索 API ==========

  /// 搜索直播间（综合搜索）
  /// [filter]: all=全部, offline=未开播, online=已开播
  Future<LiveSearchResult> searchLiveRooms(
    String query, {
    int page = 1,
    int pageSize = 20,
    LiveRoomFilter filter = LiveRoomFilter.all,
  }) async {
    try {
      switch (filter) {
        case LiveRoomFilter.all:
          // 同时搜索 live_room + bili_user，合并去重
          final results = await Future.wait([
            _searchLiveRoomApi(query, page, pageSize),
            _searchBiliUserWithRoomApi(query, page, pageSize),
          ]);
          return results[0].merge(results[1]);

        case LiveRoomFilter.offline:
          // 只搜索 bili_user，筛选有直播间但未开播的
          final userResults = await _searchBiliUserWithRoomApi(query, page, pageSize);
          return userResults.filter(LiveRoomFilter.offline);

        case LiveRoomFilter.online:
          // 搜索 live_room + bili_user，只保留已开播的
          final results = await Future.wait([
            _searchLiveRoomApi(query, page, pageSize),
            _searchBiliUserWithRoomApi(query, page, pageSize),
          ]);
          return results[0].merge(results[1]).filter(LiveRoomFilter.online);
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 搜索正在直播的直播间 (search_type=live_room)
  Future<LiveSearchResult> _searchLiveRoomApi(
    String query,
    int page,
    int pageSize,
  ) async {
    final response = await _dio.get(
      _searchApi,
      queryParameters: {
        'keyword': query,
        'search_type': 'live_room',
        'page': page,
        'page_size': pageSize,
      },
    );

    _checkResponse(response.data);

    final data = response.data['data'];
    final results = data['result'] as List? ?? [];
    final numResults = data['numResults'] as int? ?? 0;

    final rooms = results.map((item) => LiveRoom.fromLiveRoomSearch(item)).toList();

    return LiveSearchResult(
      rooms: rooms,
      totalCount: numResults,
      page: page,
      pageSize: pageSize,
      hasMore: page * pageSize < numResults,
    );
  }

  /// 搜索有直播间的用户 (search_type=bili_user)
  Future<LiveSearchResult> _searchBiliUserWithRoomApi(
    String query,
    int page,
    int pageSize,
  ) async {
    final response = await _dio.get(
      _searchApi,
      queryParameters: {
        'keyword': query,
        'search_type': 'bili_user',
        'page': page,
        'page_size': pageSize,
      },
    );

    _checkResponse(response.data);

    final data = response.data['data'];
    final results = data['result'] as List? ?? [];
    final numResults = data['numResults'] as int? ?? 0;

    // 只保留有直播间的用户 (room_id > 0)
    final usersWithRoom = results.where((item) {
      final roomId = item['room_id'] as int? ?? 0;
      return roomId > 0;
    }).toList();

    // 批量获取直播间详情以获取直播状态
    final rooms = <LiveRoom>[];
    for (final item in usersWithRoom) {
      final roomId = item['room_id'] as int;
      final uname = _cleanHtmlTags(item['uname'] as String? ?? '');
      final face = _fixImageUrl(item['upic'] as String?);

      try {
        final roomInfo = await getLiveRoomInfo(roomId);
        if (roomInfo != null) {
          rooms.add(roomInfo.copyWith(
            uname: uname.isNotEmpty ? uname : roomInfo.uname,
            face: face ?? roomInfo.face,
          ));
        } else {
          // 如果获取详情失败，使用基本信息
          rooms.add(LiveRoom.fromBiliUserSearch(item));
        }
      } catch (e) {
        logDebug('Failed to get room info for $roomId: $e');
        rooms.add(LiveRoom.fromBiliUserSearch(item));
      }
    }

    return LiveSearchResult(
      rooms: rooms,
      totalCount: numResults,
      page: page,
      pageSize: pageSize,
      hasMore: page * pageSize < numResults,
    );
  }

  /// 获取直播间详情
  Future<LiveRoom?> getLiveRoomInfo(int roomId) async {
    try {
      // 获取直播间信息
      final roomResponse = await _dio.get(
        _liveRoomInfoApi,
        queryParameters: {'room_id': roomId},
      );

      if (roomResponse.data['code'] != 0) {
        return null;
      }

      final roomData = roomResponse.data['data'];

      // 获取主播信息
      String? uname;
      String? face;
      try {
        final anchorResponse = await _dio.get(
          _liveAnchorInfoApi,
          queryParameters: {'roomid': roomId},
        );
        if (anchorResponse.data['code'] == 0) {
          final anchorData = anchorResponse.data['data']['info'];
          uname = anchorData['uname'] as String?;
          face = _fixImageUrl(anchorData['face'] as String?);
        }
      } catch (e) {
        logDebug('Failed to get anchor info for room $roomId: $e');
      }

      return LiveRoom.fromRoomInfo(roomData, uname: uname, face: face);
    } on DioException catch (e) {
      logError('Failed to get live room info for $roomId: ${e.message}');
      return null;
    }
  }

  /// 获取直播流地址 (HLS)
  Future<String?> getLiveStreamUrl(int roomId) async {
    try {
      final response = await _dio.get(
        _livePlayUrlApi,
        queryParameters: {
          'cid': roomId,
          'platform': 'h5',
          'quality': 4, // 原画
        },
      );

      if (response.data['code'] != 0) {
        return null;
      }

      final durl = response.data['data']['durl'] as List?;
      if (durl == null || durl.isEmpty) {
        return null;
      }

      return durl[0]['url'] as String?;
    } on DioException catch (e) {
      logError('Failed to get live stream URL for room $roomId: ${e.message}');
      return null;
    }
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
