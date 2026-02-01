import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/models/radio_station.dart';

/// 直播間資訊
class LiveRoomInfo {
  final String title;
  final String? thumbnailUrl;
  final String? hostName;
  final int? viewerCount;
  final DateTime? liveStartTime;
  final bool isLive;

  const LiveRoomInfo({
    required this.title,
    this.thumbnailUrl,
    this.hostName,
    this.viewerCount,
    this.liveStartTime,
    this.isLive = false,
  });
}

/// 直播流資訊
class LiveStreamInfo {
  final String url;
  final Map<String, String>? headers;
  final DateTime? expiresAt;

  const LiveStreamInfo({
    required this.url,
    this.headers,
    this.expiresAt,
  });
}

/// 解析結果
class ParseResult {
  final SourceType sourceType;
  final String sourceId;
  final String normalizedUrl;

  const ParseResult({
    required this.sourceType,
    required this.sourceId,
    required this.normalizedUrl,
  });
}

/// RadioSource - 直播間 URL 解析和流地址獲取
class RadioSource with Logging {
  late final Dio _dio;
  late final yt.YoutubeExplode _youtube;

  // Bilibili 直播 API
  static const String _biliLiveApiBase = 'https://api.live.bilibili.com';
  static const String _biliRoomInfoApi = '$_biliLiveApiBase/xlive/web-room/v1/index/getInfoByRoom';
  static const String _biliPlayUrlApi = '$_biliLiveApiBase/room/v1/Room/playUrl';
  static const String _biliRoomInitApi = '$_biliLiveApiBase/room/v1/Room/room_init';

  RadioSource() {
    _dio = Dio(BaseOptions(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
      connectTimeout: AppConstants.networkConnectTimeout,
      receiveTimeout: AppConstants.networkReceiveTimeout,
    ));
    _youtube = yt.YoutubeExplode();
  }

  /// 解析直播間 URL，返回平台類型和房間 ID
  ParseResult? parseUrl(String url) {
    // Bilibili 直播
    // https://live.bilibili.com/12345
    // https://live.bilibili.com/h5/12345
    final biliLiveRegex = RegExp(r'live\.bilibili\.com(?:/h5)?/(\d+)');
    final biliMatch = biliLiveRegex.firstMatch(url);
    if (biliMatch != null) {
      final roomId = biliMatch.group(1)!;
      return ParseResult(
        sourceType: SourceType.bilibili,
        sourceId: roomId,
        normalizedUrl: 'https://live.bilibili.com/$roomId',
      );
    }

    // YouTube 直播
    // https://www.youtube.com/watch?v=VIDEO_ID (live)
    // https://www.youtube.com/live/VIDEO_ID
    // https://youtu.be/VIDEO_ID (live)
    final ytLiveRegex = RegExp(r'youtube\.com/live/([a-zA-Z0-9_-]{11})');
    final ytLiveMatch = ytLiveRegex.firstMatch(url);
    if (ytLiveMatch != null) {
      final videoId = ytLiveMatch.group(1)!;
      return ParseResult(
        sourceType: SourceType.youtube,
        sourceId: videoId,
        normalizedUrl: 'https://www.youtube.com/watch?v=$videoId',
      );
    }

    // 標準 YouTube URL（需要之後驗證是否為直播）
    try {
      final videoId = yt.VideoId.parseVideoId(url);
      if (videoId != null) {
        return ParseResult(
          sourceType: SourceType.youtube,
          sourceId: videoId,
          normalizedUrl: 'https://www.youtube.com/watch?v=$videoId',
        );
      }
    } catch (_) {}

    return null;
  }

  /// 獲取 Bilibili 直播間真實房間號（短號轉長號）
  Future<String> _getBiliRealRoomId(String roomId) async {
    try {
      final response = await _dio.get(
        _biliRoomInitApi,
        queryParameters: {'id': roomId},
      );

      if (response.data['code'] == 0) {
        return response.data['data']['room_id'].toString();
      }
    } catch (e) {
      logWarning('Failed to get real room ID for $roomId: $e');
    }
    return roomId; // 返回原始 ID 作為後備
  }

  /// 獲取 Bilibili 直播間資訊
  Future<LiveRoomInfo> _getBiliLiveInfo(String roomId) async {
    final realRoomId = await _getBiliRealRoomId(roomId);

    final response = await _dio.get(
      _biliRoomInfoApi,
      queryParameters: {'room_id': realRoomId},
    );

    if (response.data['code'] != 0) {
      throw Exception('Failed to get room info: ${response.data['message']}');
    }

    final data = response.data['data'];
    final roomInfo = data['room_info'];
    final anchorInfo = data['anchor_info'];

    // 解析開播時間
    DateTime? liveStartTime;
    final liveTime = roomInfo['live_start_time'];
    if (liveTime != null && liveTime is int && liveTime > 0) {
      liveStartTime = DateTime.fromMillisecondsSinceEpoch(liveTime * 1000);
    }

    return LiveRoomInfo(
      title: roomInfo['title'] ?? '未知直播間',
      thumbnailUrl: roomInfo['cover'] ?? roomInfo['keyframe'],
      hostName: anchorInfo?['base_info']?['uname'],
      viewerCount: roomInfo['online'],
      liveStartTime: liveStartTime,
      isLive: roomInfo['live_status'] == 1,
    );
  }

  /// 獲取 Bilibili 直播流地址
  Future<LiveStreamInfo> _getBiliStreamUrl(String roomId) async {
    final realRoomId = await _getBiliRealRoomId(roomId);

    final response = await _dio.get(
      _biliPlayUrlApi,
      queryParameters: {
        'cid': realRoomId,
        'platform': 'web',
        'quality': 4, // 原畫質量
        'qn': 10000,
      },
      options: Options(
        headers: {'Referer': 'https://live.bilibili.com/'},
      ),
    );

    if (response.data['code'] != 0) {
      throw Exception('Failed to get stream URL: ${response.data['message']}');
    }

    final durl = response.data['data']['durl'];
    if (durl == null || (durl as List).isEmpty) {
      throw Exception('No stream URL available');
    }

    // 優先使用 HLS，然後是 FLV
    String streamUrl = durl[0]['url'];

    return LiveStreamInfo(
      url: streamUrl,
      headers: {
        'Referer': 'https://live.bilibili.com/',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );
  }

  /// 獲取 YouTube 直播資訊
  Future<LiveRoomInfo> _getYouTubeLiveInfo(String videoId) async {
    try {
      final video = await _youtube.videos.get(videoId);

      return LiveRoomInfo(
        title: video.title,
        thumbnailUrl: video.thumbnails.highResUrl,
        hostName: video.author,
        viewerCount: video.engagement.viewCount,
        isLive: video.isLive,
        // YouTube API 不直接提供開播時間，需要其他方式獲取
      );
    } catch (e) {
      logWarning('Failed to get YouTube live info: $e');
      throw Exception('Failed to get YouTube live info: $e');
    }
  }

  /// 獲取 YouTube 直播流地址 (HLS)
  Future<LiveStreamInfo> _getYouTubeStreamUrl(String videoId) async {
    try {
      final url = await _youtube.videos.streamsClient.getHttpLiveStreamUrl(
        yt.VideoId(videoId),
      );

      return LiveStreamInfo(
        url: url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );
    } catch (e) {
      logWarning('Failed to get YouTube HLS stream: $e');
      throw Exception('Failed to get YouTube live stream: $e');
    }
  }

  /// 獲取直播間資訊（通用入口）
  Future<LiveRoomInfo> getLiveInfo(RadioStation station) async {
    switch (station.sourceType) {
      case SourceType.bilibili:
        return _getBiliLiveInfo(station.sourceId);
      case SourceType.youtube:
        return _getYouTubeLiveInfo(station.sourceId);
    }
  }

  /// 獲取直播流地址（通用入口）
  Future<LiveStreamInfo> getStreamUrl(RadioStation station) async {
    switch (station.sourceType) {
      case SourceType.bilibili:
        return _getBiliStreamUrl(station.sourceId);
      case SourceType.youtube:
        return _getYouTubeStreamUrl(station.sourceId);
    }
  }

  /// 從 URL 創建新的 RadioStation（獲取完整資訊）
  Future<RadioStation> createStationFromUrl(String url) async {
    final parseResult = parseUrl(url);
    if (parseResult == null) {
      throw Exception('無法解析此 URL，請確認是有效的直播間連結');
    }

    // 創建基本 station
    final station = RadioStation()
      ..url = parseResult.normalizedUrl
      ..sourceType = parseResult.sourceType
      ..sourceId = parseResult.sourceId
      ..title = '載入中...'
      ..createdAt = DateTime.now();

    // 獲取直播間資訊
    try {
      final info = await getLiveInfo(station);
      station.title = info.title;
      station.thumbnailUrl = info.thumbnailUrl;
      station.hostName = info.hostName;

      if (!info.isLive) {
        logWarning('Station ${station.sourceId} is not currently live');
      }
    } catch (e) {
      logWarning('Failed to get station info, using defaults: $e');
      station.title = parseResult.sourceType == SourceType.bilibili
          ? 'Bilibili 直播間 ${parseResult.sourceId}'
          : 'YouTube 直播';
    }

    return station;
  }

  /// 檢查直播是否正在進行
  Future<bool> isLive(RadioStation station) async {
    try {
      final info = await getLiveInfo(station);
      return info.isLive;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _dio.close();
    _youtube.close();
  }
}
