import 'dart:math';

import 'package:dio/dio.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../models/live_room.dart';
import '../models/settings.dart';
import '../models/track.dart';
import '../models/video_detail.dart';
import 'base_source.dart';
import 'bilibili_exception.dart';
import 'bilibili_live_client.dart';
import 'source_capabilities.dart';
import 'source_exception.dart';
import 'source_http_policy.dart';
import 'source_url_policy.dart';

/// Bilibili API 参数常量
class _BilibiliApiParams {
  /// DASH 格式参数值
  static const int dashFormatValue = 16;

  /// durl 格式参数值（混合流）
  static const int durlFormatValue = 0;

  /// 默认音质参数
  static const int qualityDefault = 0;

  /// 高音质参数
  static const int qualityHigh = 120;

  /// 4K 标志
  static const int fourKFlag = 1;
}

/// Bilibili 音源实现
class BilibiliSource
    with Logging
    implements
        DisposableSource,
        TrackInfoSource,
        AudioStreamSource,
        SearchSource,
        PlaylistParsingSource,
        AvailabilitySource,
        TrackDetailSource,
        PagedVideoSource,
        RankingSource,
        LiveSource {
  late final Dio _dio;
  late final Dio _liveDio;
  late Options _searchOptions;
  late final String _viewApi;
  late final String _playUrlApi;
  late final String _searchApi;
  late final String _favListApi;
  late final String _replyApi;
  late final String _rankingApi;
  late final String _fingerprintApi;
  late final BilibiliLiveClient _liveClient;
  late final bool _ownsLiveClient;
  late String _browserCookie;

  // API 端点
  static const String _defaultApiBase = 'https://api.bilibili.com';
  static const String _defaultLiveApiBase = 'https://api.live.bilibili.com';

  BilibiliSource({
    Dio? dio,
    Dio? liveDio,
    BilibiliLiveClient? liveClient,
    String apiBase = _defaultApiBase,
    String liveApiBase = _defaultLiveApiBase,
  }) {
    _viewApi = '$apiBase/x/web-interface/view';
    _playUrlApi = '$apiBase/x/player/playurl';
    _searchApi = '$apiBase/x/web-interface/search/type';
    _favListApi = '$apiBase/x/v3/fav/resource/list';
    _replyApi = '$apiBase/x/v2/reply';
    _rankingApi = '$apiBase/x/web-interface/ranking/v2';
    _fingerprintApi = '$apiBase/x/frontend/finger/spi';

    _browserCookie = _buildBrowserCookie(
      buvid3: _generateBuvid3(),
      buvid4: _generateBuvid4(),
    );

    _dio = dio ??
        SourceHttpPolicy.createApiDio(
          SourceType.bilibili,
          extraHeaders: {'Cookie': _browserCookie},
        );
    _dio.options.headers.putIfAbsent('Cookie', () => _browserCookie);
    _searchOptions = Options(
      headers: SourceHttpPolicy.bilibiliSearchApiHeaders(
        cookie: _browserCookie,
      ),
    );
    _liveDio = liveDio ?? SourceHttpPolicy.createBilibiliLiveDio();
    _liveClient = liveClient ??
        BilibiliLiveClient(
          apiDio: _dio,
          liveDio: _liveDio,
          searchOptionsProvider: () => _searchOptions,
          apiBase: apiBase,
          liveApiBase: liveApiBase,
        );
    _ownsLiveClient = liveClient == null;
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

  /// 生成 buvid4 Cookie
  String _generateBuvid4() {
    final random = Random();
    String randomHex(int length) {
      const chars = '0123456789ABCDEF';
      return List.generate(length, (_) => chars[random.nextInt(16)]).join();
    }

    return '${randomHex(8)}-${randomHex(4)}-${randomHex(4)}-${randomHex(4)}-${randomHex(12)}';
  }

  String _buildBrowserCookie({
    required String buvid3,
    required String buvid4,
  }) {
    final bNut = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return 'buvid3=$buvid3; buvid4=$buvid4; b_nut=$bNut; _uuid=$buvid3; buvid_fp=$buvid3';
  }

  void _setBrowserCookie(String cookie) {
    _browserCookie = cookie;
    _dio.options.headers['Cookie'] = cookie;
    _searchOptions = Options(
      headers: SourceHttpPolicy.bilibiliSearchApiHeaders(cookie: cookie),
    );
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

  /// Helper: create Options that merge auth headers with base Dio headers.
  /// Dio's Options.headers override BaseOptions.headers per-key,
  /// so we need to manually merge the Cookie header.
  Options _withAuth(Map<String, String> authHeaders) {
    final baseCookie = _dio.options.headers['Cookie'] as String? ?? '';
    final authCookie = authHeaders['Cookie'] ?? '';
    final mergedCookie =
        authCookie.isNotEmpty ? '$baseCookie; $authCookie' : baseCookie;
    return Options(headers: {'Cookie': mergedCookie});
  }

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
  bool canHandle(String url) => parseId(url) != null;

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
  Future<Track> getTrackInfo(String bvid,
      {Map<String, String>? authHeaders}) async {
    try {
      final response = await _dio.get(
        _viewApi,
        queryParameters: {'bvid': bvid},
        options: authHeaders != null ? _withAuth(authHeaders) : null,
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
      final audioUrl = await getAudioUrl(
        AudioStreamRequest(
          sourceId: bvid,
          authHeaders: authHeaders,
        ),
      );
      track.audioUrl = audioUrl;
      track.audioUrlExpiry = DateTime.now()
          .add(const Duration(hours: AppConstants.bilibiliAudioUrlExpiryHours));
      track.createdAt = DateTime.now();

      return track;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is BilibiliApiException) rethrow;
      logError('Unexpected error in getTrackInfo: $e');
      throw BilibiliApiException(numericCode: -999, message: e.toString());
    }
  }

  @override
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    final bvid = request.sourceId;
    logDebug(
      'Getting audio stream for bvid: $bvid with config: '
      'qualityLevel=${request.config.qualityLevel}',
    );
    try {
      final cid = request.cid ??
          await _getCid(
            bvid,
            authHeaders: request.authHeaders,
          );
      logDebug('Got cid: $cid for bvid: $bvid');

      return _resolveAudioStreamForCid(
        bvid,
        cid,
        request.config,
        authHeaders: request.authHeaders,
      );
    } on BilibiliApiException catch (e) {
      logError(
          'Bilibili API error for $bvid: code=${e.code}, message=${e.message}');
      rethrow;
    } on DioException catch (e) {
      logError(
          'Network error getting audio URL for $bvid: ${e.type}, ${e.message}');
      throw _handleDioError(e);
    }
  }

  /// 使用指定 cid 获取音频流
  Future<AudioStreamResult> _resolveAudioStreamForCid(
    String bvid,
    int cid,
    AudioStreamConfig config, {
    Map<String, String>? authHeaders,
  }) async {
    SourceApiException? lastFallbackableError;

    // 按流类型优先级尝试
    for (final streamType in config.streamPriority) {
      try {
        final result = await _tryGetStreamByType(bvid, cid, streamType, config,
            authHeaders: authHeaders);
        if (result != null) {
          return result;
        }
      } catch (e) {
        final sourceError = e is DioException ? _handleDioError(e) : e;
        if (_shouldAbortStreamFallback(sourceError)) {
          logWarning(
              'Stream type $streamType hit non-fallbackable error for $bvid:$cid: $sourceError');
          throw sourceError;
        }
        if (sourceError is SourceApiException) {
          lastFallbackableError = sourceError;
        }
        logDebug('Stream type $streamType failed for $bvid:$cid: $sourceError');
      }
    }

    if (lastFallbackableError != null) {
      throw lastFallbackableError;
    }

    logError('No audio stream available for $bvid:$cid');
    throw const BilibiliApiException(
      numericCode: -404,
      message: 'No audio stream available',
    );
  }

  bool _shouldAbortStreamFallback(Object error) {
    return error is SourceApiException &&
        !error.kind.canFallbackToLowerAudioQuality;
  }

  /// 根据流类型获取对应的流
  Future<AudioStreamResult?> _tryGetStreamByType(
    String bvid,
    int cid,
    StreamType streamType,
    AudioStreamConfig config, {
    Map<String, String>? authHeaders,
    String? failedUrl,
  }) async {
    switch (streamType) {
      case StreamType.audioOnly:
        return _tryGetDashStream(
          bvid,
          cid,
          config,
          authHeaders: authHeaders,
          failedUrl: failedUrl,
        );
      case StreamType.muxed:
        return _tryGetDurlStream(
          bvid,
          cid,
          authHeaders: authHeaders,
          failedUrl: failedUrl,
        );
      case StreamType.hls:
        return null; // Bilibili 不支持 HLS
    }
  }

  /// 尝试获取 DASH 音频流（需要 fnval=16）
  Future<AudioStreamResult?> _tryGetDashStream(
    String bvid,
    int cid,
    AudioStreamConfig config, {
    Map<String, String>? authHeaders,
    String? failedUrl,
  }) async {
    final response = await _dio.get(
      _playUrlApi,
      queryParameters: {
        'bvid': bvid,
        'cid': cid,
        'fnval': _BilibiliApiParams.dashFormatValue, // DASH 格式
        'qn': _BilibiliApiParams.qualityDefault,
        'fourk': _BilibiliApiParams.fourKFlag,
      },
      options: authHeaders != null ? _withAuth(authHeaders) : null,
    );

    _checkResponse(response.data);
    final data = response.data['data'];

    final dash = data['dash'];
    if (dash == null) return null;

    final audios = dash['audio'] as List?;
    if (audios == null || audios.isEmpty) return null;

    // 按带宽排序
    final sortedAudios = List<Map<String, dynamic>>.from(audios);
    sortedAudios.sort(
        (a, b) => (b['bandwidth'] as int).compareTo(a['bandwidth'] as int));

    // 根据音质等级选择
    final selected = _selectByQualityLevel(sortedAudios, config.qualityLevel);
    if (selected == null) return null;

    final audioUrl =
        _dashAudioUrls(selected).where((url) => url != failedUrl).firstOrNull;
    if (audioUrl == null) return null;

    final bandwidth = selected['bandwidth'] as int;
    logDebug('Got DASH audio stream for $bvid:$cid, bandwidth: $bandwidth');

    return AudioStreamResult(
      url: audioUrl,
      bitrate: bandwidth,
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
      expiry: const Duration(hours: AppConstants.bilibiliAudioUrlExpiryHours),
    );
  }

  /// 尝试获取 durl 流（混合流，需要 fnval=0）
  Future<AudioStreamResult?> _tryGetDurlStream(
    String bvid,
    int cid, {
    Map<String, String>? authHeaders,
    String? failedUrl,
  }) async {
    final response = await _dio.get(
      _playUrlApi,
      queryParameters: {
        'bvid': bvid,
        'cid': cid,
        'fnval': _BilibiliApiParams.durlFormatValue, // durl 格式（混合流）
        'qn': _BilibiliApiParams.qualityHigh, // 请求高画质
      },
      options: authHeaders != null ? _withAuth(authHeaders) : null,
    );

    _checkResponse(response.data);
    final data = response.data['data'];

    final durl = data['durl'];
    if (durl == null || durl is! List || durl.isEmpty) return null;

    final url = durl
        .whereType<Map>()
        .map((entry) => entry['url'] as String?)
        .whereType<String>()
        .where((url) => url != failedUrl)
        .firstOrNull;
    if (url == null) return null;

    logDebug('Got durl (muxed) stream for $bvid:$cid');
    return AudioStreamResult(
      url: url,
      bitrate: null, // durl 格式不提供准确的音频码率
      container: 'flv',
      codec: null,
      streamType: StreamType.muxed,
      expiry: const Duration(hours: AppConstants.bilibiliAudioUrlExpiryHours),
    );
  }

  List<String> _dashAudioUrls(Map<String, dynamic> audio) {
    return [
      audio['baseUrl'] as String?,
      audio['base_url'] as String?,
      ...(audio['backupUrl'] as List? ?? const []),
      ...(audio['backup_url'] as List? ?? const []),
    ].whereType<String>().where((url) => url.isNotEmpty).toList();
  }

  Future<int> _getCid(String bvid, {Map<String, String>? authHeaders}) async {
    final viewResponse = await _dio.get(
      _viewApi,
      queryParameters: {'bvid': bvid},
      options: authHeaders != null ? _withAuth(authHeaders) : null,
    );

    _checkResponse(viewResponse.data);

    final cid = viewResponse.data['data']['cid'];
    if (cid == null) {
      throw BilibiliApiException(
          numericCode: -404, message: 'Failed to get cid for $bvid');
    }
    return cid as int;
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
  Future<Track> refreshAudioUrl(Track track,
      {Map<String, String>? authHeaders}) async {
    if (track.sourceType != SourceType.bilibili) {
      throw const BilibiliApiException(
          numericCode: -3, message: 'Invalid source type for BilibiliSource');
    }

    final audioUrl = await getAudioUrl(
      AudioStreamRequest(
        sourceId: track.sourceId,
        cid: track.cid,
        pageNum: track.pageNum,
        authHeaders: authHeaders,
      ),
    );
    track.audioUrl = audioUrl;
    track.audioUrlExpiry = DateTime.now()
        .add(const Duration(hours: AppConstants.bilibiliAudioUrlExpiryHours));
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
    logDebug('Searching Bilibili for: "$query", page: $page, order: $order');
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
        options: _searchOptions,
      );

      _checkResponse(response.data);

      final data = response.data['data'];
      final results = data['result'] as List? ?? [];
      final numResults = data['numResults'] as int? ?? 0;

      logDebug(
          'Bilibili search results: ${results.length} tracks, total: $numResults');

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
      logError('Bilibili search failed for "$query"', e);
      throw _handleDioError(e);
    } catch (e, st) {
      logError('Bilibili search error for "$query"', e, st);
      rethrow;
    }
  }

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) async {
    try {
      // 解析收藏夹 ID
      final fid = parseFavoritesId(playlistUrl);
      if (fid == null) {
        throw BilibiliApiException(
            numericCode: -3, message: 'Invalid favorites URL: $playlistUrl');
      }

      final authOpts = authHeaders != null ? _withAuth(authHeaders) : null;

      // 获取第一页，同时获取总数和元信息
      final firstResponse = await _dio.get(
        _favListApi,
        queryParameters: {
          'media_id': fid,
          'pn': 1,
          'ps': pageSize,
          'platform': 'web',
        },
        options: authOpts,
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
          options: authOpts,
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
        await Future.delayed(AppConstants.networkRetryDelay);
      }

      return PlaylistParseResult(
        title: info?['title'] ?? 'Favorites',
        description: info?['intro'],
        coverUrl: info?['cover'],
        tracks: allTracks,
        totalCount: totalCount,
        sourceUrl: playlistUrl,
        ownerName: info?['upper']?['name'] as String?,
        ownerUserId: (info?['upper']?['mid'] as int?)?.toString(),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is BilibiliApiException) rethrow;
      logError('Unexpected error in parsePlaylist: $e');
      throw BilibiliApiException(numericCode: -999, message: e.toString());
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
  @override
  Future<List<VideoPage>> getVideoPages(String bvid,
      {Map<String, String>? authHeaders}) async {
    try {
      final response = await _dio.get(
        _viewApi,
        queryParameters: {'bvid': bvid},
        options: authHeaders != null ? _withAuth(authHeaders) : null,
      );

      _checkResponse(response.data);

      final pages = response.data['data']['pages'] as List? ?? [];
      return pages
          .map((p) => VideoPage(
                cid: p['cid'] as int,
                page: p['page'] as int,
                part: p['part'] as String? ?? 'P${p['page']}',
                duration: p['duration'] as int? ?? 0,
              ))
          .toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is BilibiliApiException) rethrow;
      logError('Unexpected error in getVideoPages: $e');
      throw BilibiliApiException(numericCode: -999, message: e.toString());
    }
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    AudioStreamRequest request,
  ) async {
    final bvid = request.sourceId;
    try {
      final cid = request.cid ??
          await _getCid(
            bvid,
            authHeaders: request.authHeaders,
          );
      return _resolveAlternativeAudioStreamForCid(
        bvid,
        cid,
        failedUrl: request.failedUrl,
        config: request.config,
        authHeaders: request.authHeaders,
      );
    } on BilibiliApiException {
      rethrow;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<AudioStreamResult?> _resolveAlternativeAudioStreamForCid(
    String bvid,
    int cid, {
    String? failedUrl,
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
    Map<String, String>? authHeaders,
  }) async {
    SourceApiException? lastFallbackableError;
    for (final streamType in config.streamPriority) {
      try {
        final result = await _tryGetStreamByType(
          bvid,
          cid,
          streamType,
          config,
          authHeaders: authHeaders,
          failedUrl: failedUrl,
        );
        if (result != null) return result;
      } catch (e) {
        final sourceError = e is DioException ? _handleDioError(e) : e;
        if (_shouldAbortStreamFallback(sourceError)) throw sourceError;
        if (sourceError is SourceApiException) {
          lastFallbackableError = sourceError;
        }
        logDebug(
            'Alternative stream type $streamType failed for $bvid:$cid: $sourceError');
      }
    }

    if (lastFallbackableError != null &&
        !lastFallbackableError.kind.canFallbackToLowerAudioQuality) {
      throw lastFallbackableError;
    }
    return null;
  }

  /// 获取视频详细信息（包括统计数据和UP主信息）
  @override
  Future<VideoDetail> getVideoDetail(String bvid,
      {Map<String, String>? authHeaders}) async {
    try {
      // 获取视频信息
      final viewResponse = await _dio.get(
        _viewApi,
        queryParameters: {'bvid': bvid},
        options: authHeaders != null ? _withAuth(authHeaders) : null,
      );

      _checkResponse(viewResponse.data);

      final data = viewResponse.data['data'];
      final stat = data['stat'];
      final owner = data['owner'];

      // 解析分P信息
      final pagesData = data['pages'] as List? ?? [];
      final pages = pagesData
          .map((p) => VideoPage(
                cid: p['cid'] as int,
                page: p['page'] as int,
                part: p['part'] as String? ?? 'P${p['page']}',
                duration: p['duration'] as int? ?? 0,
              ))
          .toList();

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
    } catch (e) {
      if (e is BilibiliApiException) rethrow;
      logError('Unexpected error in getVideoDetail: $e');
      throw BilibiliApiException(numericCode: -999, message: e.toString());
    }
  }

  /// 获取热门评论
  Future<List<VideoComment>> getHotComments(String bvid,
      {int limit = 5}) async {
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
      var response = await _fetchRankingVideosResponse(rid);
      if (_isBilibiliRiskControlResponse(response.data)) {
        logWarning(
            'Bilibili ranking hit risk control; refreshing fingerprint and retrying');
        await _refreshBrowserFingerprintCookie();
        response = await _fetchRankingVideosResponse(rid);
      }

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
    } catch (e) {
      if (e is BilibiliApiException) rethrow;
      logError('Unexpected error in getRankingVideos: $e');
      throw BilibiliApiException(numericCode: -999, message: e.toString());
    }
  }

  @override
  Future<List<Track>> getRankingTracks(SourceRankingRequest request) {
    return getRankingVideos(rid: request.regionId ?? 0);
  }

  Future<Response<dynamic>> _fetchRankingVideosResponse(int rid) {
    return _dio.get(
      _rankingApi,
      queryParameters: {
        'rid': rid,
        'type': 'all',
      },
    );
  }

  bool _isBilibiliRiskControlResponse(Object? data) {
    return data is Map && data['code'] == -352;
  }

  Future<void> _refreshBrowserFingerprintCookie() async {
    final response = await _dio.get(_fingerprintApi);
    _checkResponse(response.data);

    final data = response.data['data'];
    final buvid3 = data is Map ? data['b_3'] as String? : null;
    final buvid4 = data is Map ? data['b_4'] as String? : null;

    if (buvid3 == null || buvid3.isEmpty || buvid4 == null || buvid4.isEmpty) {
      throw const BilibiliApiException(
        numericCode: -352,
        message: 'Failed to refresh Bilibili browser fingerprint',
      );
    }

    _setBrowserCookie(
      _buildBrowserCookie(
        buvid3: buvid3,
        buvid4: buvid4,
      ),
    );
  }

  // ========== 辅助方法 ==========

  /// 检查 API 响应
  void _checkResponse(Map<String, dynamic> data) {
    final code = data['code'];
    if (code != 0) {
      final message = data['message'] ?? 'Unknown error';
      // 记录API错误，特别关注限流相关错误
      if (code == -352 || code == -412 || code == -509 || code == -799) {
        logWarning('Bilibili rate limited: code=$code, message=$message');
        throw BilibiliApiException(
            numericCode: code, message: t.error.rateLimited);
      } else {
        logWarning('Bilibili API error: code=$code, message=$message');
      }
      throw BilibiliApiException(numericCode: code, message: message);
    }
  }

  /// 处理 Dio 错误
  BilibiliApiException _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    final responseData = e.response?.data;

    // 记录详细错误信息
    logError(
        'Bilibili Dio error: type=${e.type}, statusCode=$statusCode, response=$responseData');

    // 使用基类的通用分类
    final classified = SourceApiException.classifyDioError(e);

    // Bilibili 特殊处理：badResponse 时保留原始 HTTP 状态码作为 numericCode
    if (e.type == DioExceptionType.badResponse) {
      if (statusCode == 412 || statusCode == 429) {
        logWarning('Bilibili rate limited (HTTP $statusCode)');
        return BilibiliApiException(
            numericCode: -429, message: classified.message);
      }
      return BilibiliApiException(
        numericCode: -(statusCode ?? 500),
        message: t.error.serverError(code: statusCode ?? 500),
      );
    }

    // 其他情况使用通用分类的 code 映射回 numericCode
    final numericCode = switch (classified.code) {
      'timeout' => -1,
      'network_error' => -2,
      _ => -3,
    };
    return BilibiliApiException(
        numericCode: numericCode, message: classified.message);
  }

  /// 解析收藏夹 ID（公開靜態方法，供遠程收藏夾操作使用）
  static String? parseFavoritesId(String url) {
    return SourceUrlPolicy.parseBilibiliFavoritesId(url);
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
  @override
  Future<LiveSearchResult> searchLiveRooms(
    String query, {
    int page = 1,
    int pageSize = 20,
    LiveRoomFilter filter = LiveRoomFilter.all,
  }) async {
    try {
      return await _liveClient.searchRooms(
        query,
        page: page,
        pageSize: pageSize,
        filter: filter,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is BilibiliApiException) rethrow;
      logError('Unexpected error in searchLiveRooms: $e');
      throw BilibiliApiException(numericCode: -999, message: e.toString());
    }
  }

  /// 获取直播间详情
  Future<LiveRoom?> getLiveRoomInfo(int roomId) async {
    final details = await _liveClient.getRoomInfo(roomId.toString());
    return details?.toLiveRoom();
  }

  /// 获取直播流地址
  @override
  Future<String?> getLiveStreamUrl(int roomId) async {
    return _liveClient.getSearchStreamUrl(roomId);
  }

  @override
  void dispose() {
    if (_ownsLiveClient) {
      _liveClient.dispose();
    }
    _dio.close();
    if (!identical(_liveDio, _dio)) {
      _liveDio.close();
    }
  }
}
