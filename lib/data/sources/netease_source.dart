import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../core/utils/netease_crypto.dart';
import '../models/settings.dart';
import '../models/track.dart';
import 'base_source.dart';
import 'netease_exception.dart';
import 'source_exception.dart';

/// 網易雲音樂音源實現
class NeteaseSource extends BaseSource with Logging {
  late final Dio _dio;

  static const String _apiBase = 'https://music.163.com';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
  static const Duration _audioUrlExpiry = Duration(minutes: 16); // 20min * 0.8

  NeteaseSource({Dio? dio}) {
    _dio = dio ??
        Dio(BaseOptions(
          baseUrl: _apiBase,
          headers: {
            'User-Agent': _userAgent,
            'Referer': 'https://music.163.com',
            'Origin': 'https://music.163.com',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          connectTimeout: AppConstants.networkConnectTimeout,
          receiveTimeout: AppConstants.networkReceiveTimeout,
        ));
  }

  @override
  SourceType get sourceType => SourceType.netease;

  // ========== URL 解析 ==========

  @override
  String? parseId(String url) {
    // 匹配 music.163.com/song?id=xxx 或 music.163.com/#/song?id=xxx
    // 或 music.163.com/song/xxx
    final match =
        RegExp(r'music\.163\.com.*?(?:song[?/]|[?&]id=)(\d+)').firstMatch(url);
    return match?.group(1);
  }

  @override
  bool isValidId(String id) => RegExp(r'^\d+$').hasMatch(id);

  @override
  bool isPlaylistUrl(String url) {
    return (url.contains('music.163.com') &&
            RegExp(r'playlist[?/]').hasMatch(url)) ||
        url.contains('163cn.tv');
  }

  @override
  bool canHandle(String url) {
    // 匹配所有 music.163.com 的歌曲 URL
    if (url.contains('music.163.com') && url.contains('song')) {
      return parseId(url) != null;
    }
    return false;
  }

  // ========== 歌曲信息 ==========

  @override
  Future<Track> getTrackInfo(String sourceId,
      {Map<String, String>? authHeaders}) async {
    try {
      final songData = await _getSongDetail(sourceId, authHeaders: authHeaders);
      final song = songData['song'] as Map<String, dynamic>;
      final privilege = songData['privilege'] as Map<String, dynamic>?;

      final track = _parseSongToTrack(song, privilege);

      // 嘗試獲取音頻 URL
      try {
        final audioUrl = await getAudioUrl(sourceId, authHeaders: authHeaders);
        track.audioUrl = audioUrl;
        track.audioUrlExpiry =
            DateTime.now().add(_audioUrlExpiry);
      } catch (_) {
        // 音頻 URL 獲取失敗不影響歌曲信息
      }

      track.createdAt = DateTime.now();
      return track;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is NeteaseApiException) rethrow;
      logError('Unexpected error in getTrackInfo: $e');
      throw NeteaseApiException(numericCode: -999, message: e.toString());
    }
  }

  // ========== 音頻流 ==========

  @override
  Future<AudioStreamResult> getAudioStream(
    String sourceId, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
    Map<String, String>? authHeaders,
  }) async {
    logDebug(
        'Getting audio stream for netease song: $sourceId, quality: ${config.qualityLevel}');
    try {
      final level = _mapQualityLevel(config.qualityLevel);
      final csrfToken = _extractCsrf(authHeaders);

      final data = {
        'ids': '[$sourceId]',
        'level': level,
        'encodeType': 'aac',
        if (csrfToken != null) 'csrf_token': csrfToken,
      };
      final encrypted = NeteaseCrypto.weapi(data);

      final response = await _dio.post(
        '/weapi/song/enhance/player/url/v1',
        data: _encodeFormData(encrypted),
        options: authHeaders != null
            ? Options(headers: {'Cookie': authHeaders['Cookie'] ?? ''})
            : null,
      );

      final respData = _ensureMap(response.data);
      _checkResponse(respData);

      final dataList = respData['data'] as List?;
      if (dataList == null || dataList.isEmpty) {
        throw NeteaseApiException(
            numericCode: -1, message: 'No stream data returned');
      }

      final streamInfo = dataList[0] as Map<String, dynamic>;
      final url = streamInfo['url'] as String?;
      final br = streamInfo['br'] as int?;
      final type = streamInfo['type'] as String?;
      final expi = streamInfo['expi'] as int?;
      final freeTrialInfo = streamInfo['freeTrialInfo'];

      if (url == null || url.isEmpty) {
        // 判斷失敗原因
        final fee = streamInfo['fee'] as int?;
        if (fee == 1 || fee == 4) {
          throw NeteaseApiException(
              numericCode: -10, message: 'VIP song, payment required');
        }
        throw NeteaseApiException(
            numericCode: -200, message: 'No stream URL available');
      }

      // 判斷是否為試聽片段
      final isTrial = freeTrialInfo != null;

      logDebug(
          'Got audio stream for $sourceId: ${br != null ? "${(br / 1000).round()}kbps" : "unknown"}, '
          'type: $type, expi: ${expi}s${isTrial ? " (trial)" : ""}');

      return AudioStreamResult(
        url: url,
        bitrate: br,
        container: type ?? 'mp3',
        codec: _mapCodec(type),
        streamType: StreamType.audioOnly,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is NeteaseApiException) rethrow;
      logError('Unexpected error in getAudioStream: $e');
      throw NeteaseApiException(numericCode: -999, message: e.toString());
    }
  }

  // ========== 搜索 ==========

  @override
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    logDebug('Searching Netease for: "$query", page: $page');
    try {
      final offset = (page - 1) * pageSize;
      final data = {
        's': query,
        'type': 1, // 歌曲
        'limit': pageSize,
        'offset': offset,
      };
      final encrypted = NeteaseCrypto.weapi(data);

      final response = await _dio.post(
        '/weapi/cloudsearch/get/web',
        data: _encodeFormData(encrypted),
      );

      final respData = _ensureMap(response.data);
      _checkResponse(respData);

      final result = respData['result'] as Map<String, dynamic>?;
      final songs = result?['songs'] as List? ?? [];
      final songCount = result?['songCount'] as int? ?? 0;

      logDebug('Netease search results: ${songs.length} tracks, total: $songCount');

      final tracks = songs.map((song) {
        final s = song as Map<String, dynamic>;
        final privilege = s['privilege'] as Map<String, dynamic>?;
        return _parseSongToTrack(s, privilege);
      }).toList();

      return SearchResult(
        tracks: tracks,
        totalCount: songCount,
        page: page,
        pageSize: pageSize,
        hasMore: page * pageSize < songCount,
      );
    } on DioException catch (e) {
      logError('Netease search failed for "$query"', e);
      throw _handleDioError(e);
    } catch (e) {
      if (e is NeteaseApiException) rethrow;
      logError('Netease search error for "$query"', e);
      throw NeteaseApiException(numericCode: -999, message: e.toString());
    }
  }

  // ========== 歌單解析 ==========

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) async {
    try {
      // 1. 提取歌單 ID
      final playlistId = await _extractPlaylistId(playlistUrl);
      if (playlistId == null) {
        throw NeteaseApiException(
            numericCode: -3,
            message: 'Invalid playlist URL: $playlistUrl');
      }

      // 2. 獲取歌單詳情 + trackIds
      final encrypted = NeteaseCrypto.weapi({'id': playlistId, 'n': 0});
      final response = await _dio.post(
        '/weapi/v3/playlist/detail',
        data: _encodeFormData(encrypted),
        options: authHeaders != null
            ? Options(headers: {'Cookie': authHeaders['Cookie'] ?? ''})
            : null,
      );

      final respData = _ensureMap(response.data);
      _checkResponse(respData);

      final playlist = respData['playlist'] as Map<String, dynamic>?;
      if (playlist == null) {
        throw NeteaseApiException(
            numericCode: -3, message: 'Playlist data not found');
      }

      final title = playlist['name'] as String? ?? 'Unknown Playlist';
      final description = playlist['description'] as String?;
      final coverUrl = playlist['coverImgUrl'] as String?;
      final creator = playlist['creator'] as Map<String, dynamic>?;
      final ownerName = creator?['nickname'] as String?;
      final ownerUserId = creator?['userId']?.toString();
      final trackCount = playlist['trackCount'] as int? ?? 0;

      // 3. 提取 trackIds
      final trackIds = <int>[];
      final trackIdsList = playlist['trackIds'] as List?;
      if (trackIdsList != null) {
        for (final item in trackIdsList) {
          final id = (item as Map<String, dynamic>)['id'] as int?;
          if (id != null) trackIds.add(id);
        }
      }

      // 4. 分批獲取歌曲詳情（每批 400 個）
      final allTracks = <Track>[];
      const batchSize = 400;

      for (var i = 0; i < trackIds.length; i += batchSize) {
        final batchIds = trackIds.skip(i).take(batchSize).toList();
        final batchTracks =
            await _fetchTrackDetailsBatch(batchIds, authHeaders: authHeaders);
        allTracks.addAll(batchTracks);

        // 避免請求過快
        if (i + batchSize < trackIds.length) {
          await Future.delayed(AppConstants.networkRetryDelay);
        }
      }

      return PlaylistParseResult(
        title: title,
        description: description,
        coverUrl: coverUrl,
        tracks: allTracks,
        totalCount: trackCount,
        sourceUrl: playlistUrl,
        ownerName: ownerName,
        ownerUserId: ownerUserId,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is NeteaseApiException) rethrow;
      logError('Unexpected error in parsePlaylist: $e');
      throw NeteaseApiException(numericCode: -999, message: e.toString());
    }
  }

  // ========== 刷新 / 可用性 ==========

  @override
  Future<Track> refreshAudioUrl(Track track,
      {Map<String, String>? authHeaders}) async {
    if (track.sourceType != SourceType.netease) {
      throw NeteaseApiException(
          numericCode: -3,
          message: 'Invalid source type for NeteaseSource');
    }

    final result =
        await getAudioStream(track.sourceId, authHeaders: authHeaders);
    track.audioUrl = result.url;
    track.audioUrlExpiry =
        DateTime.now().add(_audioUrlExpiry);
    track.updatedAt = DateTime.now();
    return track;
  }

  @override
  Future<bool> checkAvailability(String sourceId) async {
    try {
      final songData = await _getSongDetail(sourceId);
      final privilege = songData['privilege'] as Map<String, dynamic>?;
      final st = privilege?['st'] as int?;
      return st != -200;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _dio.close();
  }

  // ========== 內部方法 ==========

  /// 獲取單首歌曲詳情（含 privilege）
  Future<Map<String, dynamic>> _getSongDetail(String sourceId,
      {Map<String, String>? authHeaders}) async {
    final data = {
      'c': '[{"id":"$sourceId"}]',
      'ids': '[$sourceId]',
    };
    final encrypted = NeteaseCrypto.weapi(data);

    final response = await _dio.post(
      '/weapi/v3/song/detail',
      data: _encodeFormData(encrypted),
      options: authHeaders != null
          ? Options(headers: {'Cookie': authHeaders['Cookie'] ?? ''})
          : null,
    );

    final respData = _ensureMap(response.data);
    _checkResponse(respData);

    final songs = respData['songs'] as List?;
    if (songs == null || songs.isEmpty) {
      throw NeteaseApiException(
          numericCode: -404, message: 'Song not found: $sourceId');
    }

    final privileges = respData['privileges'] as List?;
    final privilege = (privileges != null && privileges.isNotEmpty)
        ? privileges[0] as Map<String, dynamic>
        : null;

    return {
      'song': songs[0] as Map<String, dynamic>,
      'privilege': privilege,
    };
  }

  /// 批量獲取歌曲詳情
  Future<List<Track>> _fetchTrackDetailsBatch(List<int> trackIds,
      {Map<String, String>? authHeaders}) async {
    final songIds = trackIds.map((id) => '{"id":"$id"}').join(',');
    final data = {
      'c': '[$songIds]',
      'ids': '[${trackIds.join(",")}]',
    };
    final encrypted = NeteaseCrypto.weapi(data);

    final response = await _dio.post(
      '/weapi/v3/song/detail',
      data: _encodeFormData(encrypted),
      options: authHeaders != null
          ? Options(headers: {'Cookie': authHeaders['Cookie'] ?? ''})
          : null,
    );

    final respData = _ensureMap(response.data);
    _checkResponse(respData);

    final songs = respData['songs'] as List? ?? [];
    final privileges = respData['privileges'] as List? ?? [];

    // 建立 privilege 查找表
    final privilegeMap = <int, Map<String, dynamic>>{};
    for (final p in privileges) {
      final pm = p as Map<String, dynamic>;
      final id = pm['id'] as int?;
      if (id != null) privilegeMap[id] = pm;
    }

    return songs.map((song) {
      final s = song as Map<String, dynamic>;
      final songId = s['id'] as int?;
      final privilege = songId != null ? privilegeMap[songId] : null;
      return _parseSongToTrack(s, privilege);
    }).toList();
  }

  /// 解析歌曲 JSON 為 Track
  Track _parseSongToTrack(
      Map<String, dynamic> song, Map<String, dynamic>? privilege) {
    final songId = song['id'];
    final name = song['name'] as String? ?? '';
    final ar = song['ar'] as List?;
    final al = song['al'] as Map<String, dynamic>?;
    final dt = song['dt'] as int? ?? 0;

    // 歌手名拼接
    final artists = ar
            ?.map((a) => (a as Map<String, dynamic>)['name'] as String?)
            .where((n) => n != null && n.isNotEmpty)
            .join(', ') ??
        '';

    // VIP 判斷
    final fee = privilege?['fee'] as int? ?? song['fee'] as int? ?? 0;
    final st = privilege?['st'] as int? ?? 0;

    return Track()
      ..sourceId = songId.toString()
      ..sourceType = SourceType.netease
      ..title = name
      ..artist = artists.isNotEmpty ? artists : null
      ..durationMs = dt
      ..thumbnailUrl = al?['picUrl'] as String?
      ..isVip = (fee == 1 || fee == 4)
      ..isAvailable = (st != -200);
  }

  /// 提取歌單 ID（支持標準連結和短連結）
  Future<String?> _extractPlaylistId(String url) async {
    // 短連結需要重定向
    if (url.contains('163cn.tv')) {
      final resolvedUrl = await _resolveShortUrl(url);
      return _parsePlaylistIdFromUrl(resolvedUrl);
    }
    return _parsePlaylistIdFromUrl(url);
  }

  String? _parsePlaylistIdFromUrl(String url) {
    // 標準: music.163.com/#/playlist?id=xxx 或 music.163.com/playlist?id=xxx
    final idMatch = RegExp(r'[?&]id=(\d+)').firstMatch(url);
    if (idMatch != null) return idMatch.group(1);

    // 移動端: /playlist/xxx
    final pathMatch = RegExp(r'/playlist[?/].*?(\d{5,})').firstMatch(url);
    if (pathMatch != null) return pathMatch.group(1);

    return null;
  }

  Future<String> _resolveShortUrl(String url) async {
    try {
      final response = await _dio.head(
        url,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final location = response.headers.value('location');
      if (location != null) return location;
    } catch (_) {
      try {
        final response = await _dio.get(
          url,
          options: Options(followRedirects: true, maxRedirects: 5),
        );
        return response.realUri.toString();
      } catch (_) {
        // 返回原始 URL
      }
    }
    return url;
  }

  /// 音質等級映射
  String _mapQualityLevel(AudioQualityLevel level) {
    switch (level) {
      case AudioQualityLevel.high:
        return 'exhigh'; // 320kbps
      case AudioQualityLevel.medium:
        return 'higher'; // 192kbps
      case AudioQualityLevel.low:
        return 'standard'; // 128kbps
    }
  }

  /// 格式到編碼映射
  String? _mapCodec(String? type) {
    if (type == null) return null;
    switch (type.toLowerCase()) {
      case 'mp3':
        return 'mp3';
      case 'm4a':
      case 'aac':
        return 'aac';
      case 'flac':
        return 'flac';
      case 'ogg':
        return 'vorbis';
      default:
        return 'aac';
    }
  }

  /// 從 authHeaders Cookie 中提取 csrf token
  String? _extractCsrf(Map<String, String>? authHeaders) {
    final cookie = authHeaders?['Cookie'];
    if (cookie == null) return null;
    final match = RegExp(r'__csrf=([^;]+)').firstMatch(cookie);
    return match?.group(1);
  }

  /// 編碼 weapi 加密結果為 form data
  String _encodeFormData(Map<String, String> encrypted) {
    return 'params=${Uri.encodeComponent(encrypted['params']!)}'
        '&encSecKey=${Uri.encodeComponent(encrypted['encSecKey']!)}';
  }

  /// 確保響應數據是 Map
  Map<String, dynamic> _ensureMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        // 解析失敗
      }
    }
    throw NeteaseApiException(
      numericCode: -999,
      message: 'Unexpected response type: ${data.runtimeType}',
    );
  }

  /// 檢查 API 響應
  void _checkResponse(Map<String, dynamic> data) {
    final code = data['code'] as int?;
    if (code == null) return; // 某些 API 不返回 code

    if (code != 200 && code != 0) {
      final message = data['message'] as String? ?? data['msg'] as String? ?? 'Unknown error';
      logWarning('Netease API error: code=$code, message=$message');
      throw NeteaseApiException(numericCode: code, message: message);
    }
  }

  /// 處理 Dio 錯誤
  NeteaseApiException _handleDioError(DioException e) {
    logError('Netease Dio error: type=${e.type}, statusCode=${e.response?.statusCode}');

    final classified = SourceApiException.classifyDioError(e);

    if (e.type == DioExceptionType.badResponse) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 429 || statusCode == 460 || statusCode == 462) {
        return NeteaseApiException(numericCode: -460, message: classified.message);
      }
      return NeteaseApiException(
        numericCode: -(statusCode ?? 500),
        message: classified.message,
      );
    }

    final numericCode = switch (classified.code) {
      'timeout' => -997,
      'network_error' => -998,
      _ => -999,
    };
    return NeteaseApiException(numericCode: numericCode, message: classified.message);
  }
}
