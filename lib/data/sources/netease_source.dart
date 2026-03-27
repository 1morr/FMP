import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../core/utils/netease_crypto.dart';
import '../models/settings.dart';
import '../models/track.dart';
import '../models/video_detail.dart';
import 'base_source.dart';
import 'netease_exception.dart';
import 'source_exception.dart';

/// 網易雲音樂音源實現
///
/// 使用三種 API 模式:
/// - `/api/*` — 明文 form-encoded（搜索、歌曲詳情）
/// - `/eapi/*` — eapi 加密（音頻流獲取，需登入）
/// - 短連結解析用 HEAD/GET
class NeteaseSource extends BaseSource with Logging {
  late final Dio _dio;

  static const String _musicBase = 'https://music.163.com';
  static const String _interfaceBase = 'https://interface3.music.163.com';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 '
      'NeteaseMusicDesktop/3.0.18.203152';
  static const Duration _audioUrlExpiry = Duration(minutes: 16);

  NeteaseSource({Dio? dio}) {
    _dio = dio ??
        Dio(BaseOptions(
          headers: {
            'User-Agent': _userAgent,
            'Referer': '$_musicBase/',
            'Origin': _musicBase,
            'Accept': 'application/json, text/plain, */*',
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

      try {
        final audioUrl = await getAudioUrl(sourceId, authHeaders: authHeaders);
        track.audioUrl = audioUrl;
        track.audioUrlExpiry = DateTime.now().add(_audioUrlExpiry);
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

  // ========== 音頻流（eapi 加密） ==========

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
      final payload = {
        'ids': [int.parse(sourceId)],
        'level': level,
        'encodeType': 'flac',
      };

      final eapiParams = NeteaseCrypto.eapi(
          '/api/song/enhance/player/url/v1', payload);

      final response = await _dio.post(
        '$_interfaceBase/eapi/song/enhance/player/url/v1',
        data: {'params': eapiParams},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: _withAuth(authHeaders),
        ),
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
        final fee = streamInfo['fee'] as int?;
        if (fee == 1 || fee == 4) {
          throw NeteaseApiException(
              numericCode: -10, message: 'VIP song, payment required');
        }
        throw NeteaseApiException(
            numericCode: -200, message: 'No stream URL available');
      }

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

  // ========== 搜索（明文 /api/） ==========

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

      final response = await _dio.post(
        '$_musicBase/api/cloudsearch/pc',
        data: {
          's': query,
          'type': 1,
          'limit': pageSize,
          'offset': offset,
          'total': true,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );

      final respData = _ensureMap(response.data);
      _checkResponse(respData);

      final result = respData['result'] as Map<String, dynamic>?;
      final songs = result?['songs'] as List? ?? [];
      final songCount = result?['songCount'] as int? ?? 0;

      logDebug(
          'Netease search results: ${songs.length} tracks, total: $songCount');

      // 搜尋 API 可能將 privileges 放在 result 頂層（與 song detail API 一致）
      final privileges = result?['privileges'] as List? ?? [];
      final privilegeMap = <int, Map<String, dynamic>>{};
      for (final p in privileges) {
        final pm = p as Map<String, dynamic>;
        final id = pm['id'] as int?;
        if (id != null) privilegeMap[id] = pm;
      }

      final tracks = songs.map((song) {
        final s = song as Map<String, dynamic>;
        // 優先使用歌曲內嵌的 privilege，其次用頂層 privileges 列表
        final songId = s['id'] as int?;
        final privilege = s['privilege'] as Map<String, dynamic>? ??
            (songId != null ? privilegeMap[songId] : null);
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
      final playlistId = await _extractPlaylistId(playlistUrl);
      if (playlistId == null) {
        throw NeteaseApiException(
            numericCode: -3,
            message: 'Invalid playlist URL: $playlistUrl');
      }

      final response = await _dio.post(
        '$_musicBase/api/v6/playlist/detail',
        data: 'id=$playlistId',
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
          headers: _withAuth(authHeaders),
        ),
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

      final trackIds = <int>[];
      final trackIdsList = playlist['trackIds'] as List?;
      if (trackIdsList != null) {
        for (final item in trackIdsList) {
          final id = (item as Map<String, dynamic>)['id'] as int?;
          if (id != null) trackIds.add(id);
        }
      }

      // 分批獲取歌曲詳情（每批 400 個）
      final allTracks = <Track>[];
      const batchSize = 400;

      for (var i = 0; i < trackIds.length; i += batchSize) {
        final batchIds = trackIds.skip(i).take(batchSize).toList();
        final batchTracks =
            await _fetchTrackDetailsBatch(batchIds, authHeaders: authHeaders);
        allTracks.addAll(batchTracks);

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
    track.audioUrlExpiry = DateTime.now().add(_audioUrlExpiry);
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

  // ========== 歌曲詳情（面板展示） ==========

  /// 獲取歌曲詳情（用於右側面板/播放器信息展示）
  /// 同時獲取歌曲元數據、歌手頭像和熱門評論
  Future<VideoDetail> getVideoDetail(String sourceId,
      {Map<String, String>? authHeaders}) async {
    try {
      final songData = await _getSongDetail(sourceId, authHeaders: authHeaders);
      final song = songData['song'] as Map<String, dynamic>;

      final name = song['name'] as String? ?? '';
      final ar = song['ar'] as List? ?? song['artists'] as List?;
      final al = song['al'] as Map<String, dynamic>? ??
          song['album'] as Map<String, dynamic>?;
      final dt = song['dt'] as int? ?? song['duration'] as int? ?? 0;

      final artists = ar
              ?.map((a) => (a as Map<String, dynamic>)['name'] as String?)
              .where((n) => n != null && n.isNotEmpty)
              .join(', ') ??
          '';

      final albumName = al?['name'] as String? ?? '';
      final albumCoverUrl = al?['picUrl'] as String?;
      final albumId = al?['id'] as int?;

      // 從歌曲本身獲取發布時間
      final publishTime = song['publishTime'] as int?;
      DateTime? publishDate = publishTime != null && publishTime > 0
          ? DateTime.fromMillisecondsSinceEpoch(publishTime)
          : null;

      // 獲取第一位歌手的 ID（用於獲取頭像）
      final firstArtistId = ar != null && ar.isNotEmpty
          ? (ar[0] as Map<String, dynamic>)['id'] as int?
          : null;

      // 並行獲取：歌手頭像、專輯發布時間、熱門評論
      String artistAvatar = '';
      List<VideoComment> hotComments = [];
      int commentCount = 0;

      final futures = await Future.wait([
        // 歌手頭像
        if (firstArtistId != null && firstArtistId > 0)
          _getArtistAvatar(firstArtistId).catchError((_) => ''),
        // 專輯發布時間（僅當歌曲本身沒有時才獲取）
        if (publishDate == null && albumId != null && albumId > 0)
          _getAlbumPublishTime(albumId).catchError((_) => null),
        // 熱門評論
        _getHotComments(sourceId).catchError((_) => <String, dynamic>{
              'comments': <VideoComment>[],
              'total': 0,
            }),
      ]);

      int futureIdx = 0;
      if (firstArtistId != null && firstArtistId > 0) {
        artistAvatar = futures[futureIdx] as String? ?? '';
        futureIdx++;
      }
      if (publishDate == null && albumId != null && albumId > 0) {
        final albumDate = futures[futureIdx] as DateTime?;
        if (albumDate != null) publishDate = albumDate;
        futureIdx++;
      }
      final commentResult = futures[futureIdx] as Map<String, dynamic>;
      hotComments = commentResult['comments'] as List<VideoComment>? ?? [];
      commentCount = commentResult['total'] as int? ?? 0;

      return VideoDetail.fromNetease(
        songId: sourceId,
        title: name,
        artists: artists,
        artistAvatar: artistAvatar,
        albumName: albumName,
        albumCoverUrl: albumCoverUrl,
        durationMs: dt,
        publishDate: publishDate,
        commentCount: commentCount,
        comments: hotComments,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is NeteaseApiException) rethrow;
      logError('Unexpected error in getVideoDetail: $e');
      throw NeteaseApiException(numericCode: -999, message: e.toString());
    }
  }

  // ========== 內部方法 ==========

  /// 獲取單首歌曲詳情（明文 /api/，含 privilege）
  Future<Map<String, dynamic>> _getSongDetail(String sourceId,
      {Map<String, String>? authHeaders}) async {
    final response = await _dio.post(
      '$_musicBase/api/v3/song/detail',
      data: 'c=${jsonEncode([
            {'id': int.parse(sourceId)}
          ])}',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
        headers: _withAuth(authHeaders),
      ),
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

  /// 批量獲取歌曲詳情（明文 /api/）
  Future<List<Track>> _fetchTrackDetailsBatch(List<int> trackIds,
      {Map<String, String>? authHeaders}) async {
    if (trackIds.isEmpty) return const [];

    final response = await _dio.post(
      '$_musicBase/api/v3/song/detail',
      data: 'c=${jsonEncode(trackIds.map((id) => {'id': id}).toList())}',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
        headers: _withAuth(authHeaders),
      ),
    );

    final respData = _ensureMap(response.data);
    _checkResponse(respData);

    final songs = respData['songs'] as List? ?? [];
    final privileges = respData['privileges'] as List? ?? [];

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

  /// 獲取歌手頭像 URL
  Future<String> _getArtistAvatar(int artistId) async {
    final response = await _dio.get(
      '$_musicBase/api/artist/head/info/get',
      queryParameters: {'id': artistId},
      options: Options(responseType: ResponseType.json),
    );

    final respData = _ensureMap(response.data);
    _checkResponse(respData);

    final data = respData['data'] as Map<String, dynamic>?;
    final artist = data?['artist'] as Map<String, dynamic>?;
    return artist?['avatar'] as String? ?? '';
  }

  /// 獲取專輯發布時間
  Future<DateTime?> _getAlbumPublishTime(int albumId) async {
    final response = await _dio.get(
      '$_musicBase/api/v1/album/$albumId',
      options: Options(responseType: ResponseType.json),
    );

    final respData = _ensureMap(response.data);
    _checkResponse(respData);

    final album = respData['album'] as Map<String, dynamic>?;
    final publishTime = album?['publishTime'] as int?;
    if (publishTime != null && publishTime > 0) {
      return DateTime.fromMillisecondsSinceEpoch(publishTime);
    }
    return null;
  }

  /// 獲取歌曲熱門評論
  Future<Map<String, dynamic>> _getHotComments(String sourceId) async {
    final response = await _dio.post(
      '$_musicBase/api/v1/resource/comments/R_SO_4_$sourceId',
      data: 'limit=20&offset=0',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
      ),
    );

    final respData = _ensureMap(response.data);
    _checkResponse(respData);

    final total = respData['total'] as int? ?? 0;
    final hotCommentsRaw = respData['hotComments'] as List? ?? [];

    final comments = hotCommentsRaw.map((c) {
      final comment = c as Map<String, dynamic>;
      final user = comment['user'] as Map<String, dynamic>? ?? {};
      final time = comment['time'] as int? ?? 0;

      return VideoComment(
        id: comment['commentId'] as int? ?? 0,
        content: comment['content'] as String? ?? '',
        memberName: user['nickname'] as String? ?? '',
        memberAvatar: user['avatarUrl'] as String? ?? '',
        likeCount: comment['likedCount'] as int? ?? 0,
        createTime: DateTime.fromMillisecondsSinceEpoch(time),
      );
    }).toList();

    return {
      'comments': comments,
      'total': total,
    };
  }

  /// 解析歌曲 JSON 為 Track
  Track _parseSongToTrack(
      Map<String, dynamic> song, Map<String, dynamic>? privilege) {
    final songId = song['id'];
    final name = song['name'] as String? ?? '';
    final ar = song['ar'] as List? ?? song['artists'] as List?;
    final al = song['al'] as Map<String, dynamic>? ??
        song['album'] as Map<String, dynamic>?;
    final dt = song['dt'] as int? ?? song['duration'] as int? ?? 0;

    final artists = ar
            ?.map((a) => (a as Map<String, dynamic>)['name'] as String?)
            .where((n) => n != null && n.isNotEmpty)
            .join(', ') ??
        '';

    final privFee = privilege?['fee'] as int? ?? 0;
    final songFee = song['fee'] as int? ?? 0;
    final st = privilege?['st'] as int? ?? 0;
    // cloudsearch API 的 privilege.fee 可能不準確（VIP 歌曲返回 0），
    // 而 song.fee 是準確的；兩者任一標記為 VIP 即視為 VIP
    final isVip = (privFee == 1 || privFee == 4 ||
        songFee == 1 || songFee == 4);

    return Track()
      ..sourceId = songId.toString()
      ..sourceType = SourceType.netease
      ..title = name
      ..artist = artists.isNotEmpty ? artists : null
      ..durationMs = dt
      ..thumbnailUrl = al?['picUrl'] as String?
      ..isVip = isVip
      ..isAvailable = (st != -200);
  }

  /// 提取歌單 ID（支持標準連結和短連結）
  Future<String?> _extractPlaylistId(String url) async {
    if (url.contains('163cn.tv')) {
      final resolvedUrl = await _resolveShortUrl(url);
      return _parsePlaylistIdFromUrl(resolvedUrl);
    }
    return _parsePlaylistIdFromUrl(url);
  }

  String? _parsePlaylistIdFromUrl(String url) {
    final idMatch = RegExp(r'[?&]id=(\d+)').firstMatch(url);
    if (idMatch != null) return idMatch.group(1);

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
      } catch (_) {}
    }
    return url;
  }

  /// 構建包含認證信息的 headers map
  /// authHeaders 可能只有 Cookie，這裡補充 Origin/Referer/UA
  Map<String, String> _withAuth(Map<String, String>? authHeaders) {
    return {
      if (authHeaders != null) ...authHeaders,
      'Origin': _musicBase,
      'Referer': '$_musicBase/',
      'User-Agent': _userAgent,
    };
  }

  String _mapQualityLevel(AudioQualityLevel level) {
    switch (level) {
      case AudioQualityLevel.high:
        return 'lossless';
      case AudioQualityLevel.medium:
        return 'exhigh';
      case AudioQualityLevel.low:
        return 'standard';
    }
  }

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
        return type;
    }
  }

  /// 確保響應數據是 Map
  Map<String, dynamic> _ensureMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {}
    }
    throw NeteaseApiException(
      numericCode: -999,
      message: 'Unexpected response type: ${data.runtimeType}',
    );
  }

  void _checkResponse(Map<String, dynamic> data) {
    final code = data['code'] as int?;
    if (code == null) return;

    if (code != 200 && code != 0) {
      final message =
          data['message'] as String? ?? data['msg'] as String? ?? 'Unknown error';
      logWarning('Netease API error: code=$code, message=$message');
      throw NeteaseApiException(numericCode: code, message: message);
    }
  }

  NeteaseApiException _handleDioError(DioException e) {
    logError(
        'Netease Dio error: type=${e.type}, statusCode=${e.response?.statusCode}');

    final classified = SourceApiException.classifyDioError(e);

    if (e.type == DioExceptionType.badResponse) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 429 || statusCode == 460 || statusCode == 462) {
        return NeteaseApiException(
            numericCode: -460, message: classified.message);
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
    return NeteaseApiException(
        numericCode: numericCode, message: classified.message);
  }
}
