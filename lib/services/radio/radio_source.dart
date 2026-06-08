import 'package:fmp/i18n/strings.g.dart';

import '../../core/logger.dart';
import '../../data/models/radio_station.dart';
import '../../data/models/track.dart'; // for SourceType
import '../../data/sources/bilibili_live_client.dart';

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
  final BilibiliLiveClient _liveClient;
  final bool _ownsLiveClient;

  // YouTube URL 檢測正則（用於提示用戶）
  static final _youtubeRegex = RegExp(
    r'(youtube\.com|youtu\.be)',
    caseSensitive: false,
  );

  RadioSource({BilibiliLiveClient? liveClient})
      : _liveClient = liveClient ?? BilibiliLiveClient(),
        _ownsLiveClient = liveClient == null;

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

    final result = _liveClient.parseLiveUrl(url);
    if (result != null) {
      return ParseResult(
        sourceId: result.roomId,
        normalizedUrl: result.normalizedUrl,
      );
    }

    return null;
  }

  /// 獲取 Bilibili 直播間資訊
  Future<LiveRoomInfo> getLiveInfo(RadioStation station) async {
    final info = await _liveClient.getRoomInfo(station.sourceId);
    if (info == null) {
      throw Exception('Failed to get room info');
    }

    return LiveRoomInfo(
      title: info.title.isNotEmpty ? info.title : t.radio.unknownRoom,
      thumbnailUrl: info.thumbnailUrl,
      hostName: info.hostName,
      hostAvatarUrl: info.hostAvatarUrl,
      hostUid: info.hostUid,
      viewerCount: info.viewerCount,
      liveStartTime: info.liveStartTime,
      isLive: info.isLive,
      description: info.description,
      tags: info.tags,
      announcement: info.announcement,
      areaName: info.areaName,
      parentAreaName: info.parentAreaName,
    );
  }

  /// 獲取高能用戶數（更準確的觀眾數據）
  Future<int?> getHighEnergyUserCount(RadioStation station) async {
    return _liveClient.getHighEnergyUserCount(station.sourceId);
  }

  /// 獲取 Bilibili 直播流地址
  Future<LiveStreamInfo> getStreamUrl(RadioStation station) async {
    final stream = await _liveClient.getRadioStream(station.sourceId);

    return LiveStreamInfo(
      url: stream.url,
      headers: stream.headers,
      expiresAt: stream.expiresAt,
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
      logInfo(
        'Station info: title=${info.title}, '
        'cover=${info.thumbnailUrl != null}, '
        'host=${info.hostName}, uid=${info.hostUid}',
      );

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
    if (_ownsLiveClient) {
      _liveClient.dispose();
    }
  }
}
