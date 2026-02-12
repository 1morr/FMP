import 'package:dio/dio.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/radio_station.dart';
import '../../data/models/track.dart'; // for SourceType

/// 直播間資訊
class LiveRoomInfo {
  final String title;
  final String? thumbnailUrl;
  final String? hostName;
  final String? hostAvatarUrl;
  final int? hostUid;
  final int? viewerCount;
  final DateTime? liveStartTime;
  final bool isLive;
  final String? description;
  final String? tags;
  final String? announcement;
  final String? areaName;
  final String? parentAreaName;

  const LiveRoomInfo({
    required this.title,
    this.thumbnailUrl,
    this.hostName,
    this.hostAvatarUrl,
    this.hostUid,
    this.viewerCount,
    this.liveStartTime,
    this.isLive = false,
    this.description,
    this.tags,
    this.announcement,
    this.areaName,
    this.parentAreaName,
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
  final String sourceId;
  final String normalizedUrl;

  const ParseResult({
    required this.sourceId,
    required this.normalizedUrl,
  });
}

/// RadioSource - Bilibili 直播間 URL 解析和流地址獲取
/// 注意：目前只支持 Bilibili 直播，YouTube 直播因技術限制暫不支持
class RadioSource with Logging {
  late final Dio _dio;

  // Bilibili 直播 API
  static const String _biliLiveApiBase = 'https://api.live.bilibili.com';
  // 使用 v1 API，不需要 WBI 簽名
  static const String _biliRoomInfoApi =
      '$_biliLiveApiBase/room/v1/Room/get_info';
  static const String _biliAnchorInfoApi =
      '$_biliLiveApiBase/live_user/v1/UserInfo/get_anchor_in_room';
  static const String _biliPlayUrlApi =
      '$_biliLiveApiBase/room/v1/Room/playUrl';
  static const String _biliRoomInitApi =
      '$_biliLiveApiBase/room/v1/Room/room_init';
  static const String _biliOnlineGoldRankApi =
      '$_biliLiveApiBase/xlive/general-interface/v1/rank/getOnlineGoldRank';
  static const String _biliRoomNewsApi =
      '$_biliLiveApiBase/room_ex/v1/RoomNews/get';

  // YouTube URL 檢測正則（用於提示用戶）
  static final _youtubeRegex = RegExp(
    r'(youtube\.com|youtu\.be)',
    caseSensitive: false,
  );

  RadioSource() {
    _dio = Dio(BaseOptions(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://live.bilibili.com/',
      },
      connectTimeout: AppConstants.networkConnectTimeout,
      receiveTimeout: AppConstants.networkReceiveTimeout,
    ));
  }

  /// 檢查是否為 YouTube URL
  bool isYouTubeUrl(String url) {
    return _youtubeRegex.hasMatch(url);
  }

  /// 解析直播間 URL，返回房間 ID
  /// 目前只支持 Bilibili 直播
  ParseResult? parseUrl(String url) {
    // 檢查是否為 YouTube URL，給出友好提示
    if (isYouTubeUrl(url)) {
      return null; // 返回 null，讓調用者處理提示
    }

    // Bilibili 直播
    // https://live.bilibili.com/12345
    // https://live.bilibili.com/h5/12345
    final biliLiveRegex = RegExp(r'live\.bilibili\.com(?:/h5)?/(\d+)');
    final biliMatch = biliLiveRegex.firstMatch(url);
    if (biliMatch != null) {
      final roomId = biliMatch.group(1)!;
      return ParseResult(
        sourceId: roomId,
        normalizedUrl: 'https://live.bilibili.com/$roomId',
      );
    }

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
  Future<LiveRoomInfo> getLiveInfo(RadioStation station) async {
    final realRoomId = await _getBiliRealRoomId(station.sourceId);

    // 使用 v1 API 獲取房間資訊
    final response = await _dio.get(
      _biliRoomInfoApi,
      queryParameters: {'room_id': realRoomId},
    );

    if (response.data['code'] != 0) {
      throw Exception('Failed to get room info: ${response.data['code']}');
    }

    final data = response.data['data'];

    // 解析開播時間（v1 API 格式：字符串 "2024-01-01 12:00:00" 或時間戳）
    DateTime? liveStartTime;
    final liveTime = data['live_time'];
    if (liveTime != null) {
      if (liveTime is int && liveTime > 0) {
        liveStartTime = DateTime.fromMillisecondsSinceEpoch(liveTime * 1000);
      } else if (liveTime is String && liveTime != '0000-00-00 00:00:00') {
        try {
          liveStartTime = DateTime.parse(liveTime.replaceFirst(' ', 'T'));
        } catch (_) {}
      }
    }

    // 獲取主播名稱、頭像和 UID（需要單獨 API）
    String? hostName;
    String? hostAvatarUrl;
    int? hostUid;
    try {
      final anchorResponse = await _dio.get(
        _biliAnchorInfoApi,
        queryParameters: {'roomid': realRoomId},
      );
      if (anchorResponse.data['code'] == 0) {
        final info = anchorResponse.data['data']?['info'];
        hostName = info?['uname'];
        hostAvatarUrl = info?['face'];
        hostUid = info?['uid'];
      }
    } catch (e) {
      logWarning('Failed to get anchor info: $e');
    }

    // 獲取主播公告
    String? announcement;
    try {
      final newsResponse = await _dio.get(
        _biliRoomNewsApi,
        queryParameters: {'roomid': realRoomId},
      );
      if (newsResponse.data['code'] == 0) {
        announcement = newsResponse.data['data']?['content'];
      }
    } catch (e) {
      logWarning('Failed to get room news: $e');
    }

    return LiveRoomInfo(
      title: data['title'] ?? t.radio.unknownRoom,
      thumbnailUrl: data['user_cover'] ?? data['keyframe'],
      hostName: hostName,
      hostAvatarUrl: hostAvatarUrl,
      hostUid: hostUid,
      viewerCount: data['online'],
      liveStartTime: liveStartTime,
      isLive: data['live_status'] == 1,
      description: data['description']?.toString().isNotEmpty == true
          ? data['description']
          : null,
      tags: data['tags']?.toString().isNotEmpty == true ? data['tags'] : null,
      announcement: announcement,
      areaName: data['area_name'],
      parentAreaName: data['parent_area_name'],
    );
  }

  /// 獲取高能用戶數（更準確的觀眾數據）
  /// 使用 xlive/general-interface/v1/rank/getOnlineGoldRank API
  Future<int?> getHighEnergyUserCount(RadioStation station) async {
    try {
      final realRoomId = await _getBiliRealRoomId(station.sourceId);

      // 先獲取主播 uid
      final roomResponse = await _dio.get(
        _biliRoomInfoApi,
        queryParameters: {'room_id': realRoomId},
      );

      if (roomResponse.data['code'] != 0) {
        return null;
      }

      final uid = roomResponse.data['data']['uid'];

      // 獲取高能用戶排行榜
      final response = await _dio.get(
        _biliOnlineGoldRankApi,
        queryParameters: {
          'ruid': uid,
          'roomId': realRoomId,
          'page': 1,
          'pageSize': 1, // 只需要 onlineNum，不需要完整列表
        },
      );

      if (response.data['code'] == 0) {
        return response.data['data']['onlineNum'] as int?;
      }
    } catch (e) {
      logWarning('Failed to get high energy user count: $e');
    }
    return null;
  }

  /// 獲取 Bilibili 直播流地址
  Future<LiveStreamInfo> getStreamUrl(RadioStation station) async {
    final realRoomId = await _getBiliRealRoomId(station.sourceId);

    final response = await _dio.get(
      _biliPlayUrlApi,
      queryParameters: {
        'cid': realRoomId,
        'platform': 'web',
        'quality': 4, // 原畫質量
        'qn': 10000,
      },
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

  /// 從 URL 創建新的 RadioStation（獲取完整資訊）
  Future<RadioStation> createStationFromUrl(String url) async {
    // 檢查是否為 YouTube URL
    if (isYouTubeUrl(url)) {
      throw Exception(t.radio.youtubeNotSupported);
    }

    final parseResult = parseUrl(url);
    if (parseResult == null) {
      throw Exception(t.radio.bilibiliLinkRequired);
    }

    // 創建基本 station（只支持 Bilibili）
    final station = RadioStation()
      ..url = parseResult.normalizedUrl
      ..sourceType = SourceType.bilibili
      ..sourceId = parseResult.sourceId
      ..title = t.radio.loading
      ..createdAt = DateTime.now();

    // 獲取直播間資訊
    try {
      final info = await getLiveInfo(station);
      station.title = info.title;
      station.thumbnailUrl = info.thumbnailUrl;
      station.hostName = info.hostName;
      station.hostAvatarUrl = info.hostAvatarUrl;
      station.hostUid = info.hostUid;
      logInfo('Station info: title=${info.title}, cover=${info.thumbnailUrl != null}, host=${info.hostName}, uid=${info.hostUid}');

      if (!info.isLive) {
        logWarning('Station ${station.sourceId} is not currently live');
      }
    } catch (e, stack) {
      logWarning('Failed to get station info: $e\n$stack');
      station.title = t.radio.bilibiliRoom(id: parseResult.sourceId);
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
  }
}
