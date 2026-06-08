import 'package:dio/dio.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../../core/logger.dart';
import '../models/live_room.dart';
import '../models/track.dart';
import 'bilibili_exception.dart';
import 'source_http_policy.dart';

class BilibiliLiveUrlParseResult {
  final String roomId;
  final String normalizedUrl;

  const BilibiliLiveUrlParseResult({
    required this.roomId,
    required this.normalizedUrl,
  });
}

class BilibiliLiveStream {
  final String url;
  final Map<String, String>? headers;
  final DateTime? expiresAt;

  const BilibiliLiveStream({
    required this.url,
    this.headers,
    this.expiresAt,
  });
}

class BilibiliLiveRoomDetails {
  final String roomId;
  final String title;
  final String? thumbnailUrl;
  final String? hostName;
  final String? hostAvatarUrl;
  final int? hostUid;
  final int? viewerCount;
  final DateTime? liveStartTime;
  final LiveStatus liveStatus;
  final bool isLive;
  final String? description;
  final String? tags;
  final String? announcement;
  final String? areaName;
  final String? parentAreaName;

  const BilibiliLiveRoomDetails({
    required this.roomId,
    required this.title,
    this.thumbnailUrl,
    this.hostName,
    this.hostAvatarUrl,
    this.hostUid,
    this.viewerCount,
    this.liveStartTime,
    LiveStatus? liveStatus,
    bool? isLive,
    this.description,
    this.tags,
    this.announcement,
    this.areaName,
    this.parentAreaName,
  })  : liveStatus = liveStatus ??
            (isLive == true ? LiveStatus.live : LiveStatus.offline),
        isLive = (liveStatus ??
                (isLive == true ? LiveStatus.live : LiveStatus.offline)) ==
            LiveStatus.live;

  LiveRoom toLiveRoom() {
    return LiveRoom(
      roomId: int.tryParse(roomId) ?? 0,
      uid: hostUid ?? 0,
      uname: hostName ?? '',
      title: title,
      cover: thumbnailUrl,
      face: hostAvatarUrl,
      isLive: isLive,
      online: viewerCount,
      areaName: areaName,
      tags: tags,
      liveStatus: liveStatus,
    );
  }
}

class BilibiliMedalWallRoom {
  final String roomId;
  final String name;
  final String? avatarUrl;
  final int uid;
  final int liveStatus;
  final String link;

  const BilibiliMedalWallRoom({
    required this.roomId,
    required this.name,
    this.avatarUrl,
    required this.uid,
    required this.liveStatus,
    required this.link,
  });
}

class BilibiliLiveClient with Logging {
  static const String defaultApiBase = 'https://api.bilibili.com';
  static const String defaultLiveApiBase = 'https://api.live.bilibili.com';
  static const String _searchApi = '/x/web-interface/search/type';

  final Dio apiDio;
  final Dio liveDio;
  final Options searchOptions;
  final Options Function() _searchOptionsProvider;
  final String apiBase;
  final String liveApiBase;
  final bool _ownsApiDio;
  final bool _ownsLiveDio;

  BilibiliLiveClient({
    Dio? apiDio,
    Dio? liveDio,
    Options? searchOptions,
    Options Function()? searchOptionsProvider,
    this.apiBase = defaultApiBase,
    this.liveApiBase = defaultLiveApiBase,
  })  : _ownsApiDio = apiDio == null,
        _ownsLiveDio = liveDio == null,
        apiDio = apiDio ?? SourceHttpPolicy.createApiDio(SourceType.bilibili),
        liveDio = liveDio ?? SourceHttpPolicy.createBilibiliLiveDio(),
        searchOptions = searchOptions ?? Options(),
        _searchOptionsProvider =
            searchOptionsProvider ?? (() => searchOptions ?? Options());

  BilibiliLiveUrlParseResult? parseLiveUrl(String url) {
    final match = RegExp(
      r'(^|[^\w.-])(?:https?://)?live\.bilibili\.com/(?:h5/)?(\d+)(?=$|[/?#\s])',
      caseSensitive: false,
    ).firstMatch(url);
    final roomId = match?.group(2);
    if (roomId == null || !_isRoomId(roomId)) {
      return null;
    }

    return BilibiliLiveUrlParseResult(
      roomId: roomId,
      normalizedUrl: 'https://live.bilibili.com/$roomId',
    );
  }

  Future<String> resolveRealRoomId(String roomId) async {
    try {
      final response = await liveDio.get(
        '$liveApiBase/room/v1/Room/room_init',
        queryParameters: {'id': roomId},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        final roomIdValue = data['data']?['room_id'];
        if (roomIdValue != null) return roomIdValue.toString();
      }
      logWarning('Failed to resolve Bilibili live room ID $roomId: $data');
    } catch (e) {
      logWarning('Failed to resolve Bilibili live room ID $roomId: $e');
    }
    return roomId;
  }

  Future<BilibiliLiveRoomDetails?> getRoomInfo(String roomId) async {
    final realRoomId = await resolveRealRoomId(roomId);

    Map<dynamic, dynamic> roomData;
    try {
      final response = await liveDio.get(
        '$liveApiBase/room/v1/Room/get_info',
        queryParameters: {'room_id': realRoomId},
      );
      final data = response.data;
      if (data is! Map || data['code'] != 0 || data['data'] is! Map) {
        logWarning('Failed to get Bilibili live room info $realRoomId: $data');
        return null;
      }
      roomData = data['data'] as Map<dynamic, dynamic>;
    } on DioException catch (e) {
      logWarning('Failed to get Bilibili live room info $realRoomId: $e');
      return null;
    }

    final anchorData = await _getAnchorInfo(realRoomId);
    final announcement = await _getRoomAnnouncement(realRoomId);
    final roomUid = _asInt(roomData['uid']);
    final hostUid = _asInt(anchorData?['uid']) ?? roomUid;
    final liveStatus = _liveStatusFromCode(_asInt(roomData['live_status']));

    return BilibiliLiveRoomDetails(
      roomId: (roomData['room_id'] ?? realRoomId).toString(),
      title: roomData['title']?.toString() ?? '',
      thumbnailUrl: _fixUrl(
        _nonEmptyString(roomData['user_cover']) ??
            _nonEmptyString(roomData['keyframe']),
      ),
      hostName: _nonEmptyString(anchorData?['uname']),
      hostAvatarUrl: _fixUrl(_nonEmptyString(anchorData?['face'])),
      hostUid: hostUid,
      viewerCount: _asInt(roomData['online']),
      liveStartTime: _parseLiveStartTime(roomData['live_time']),
      liveStatus: liveStatus,
      description: _nonEmptyString(roomData['description']),
      tags: _nonEmptyString(roomData['tags']),
      announcement: announcement,
      areaName: _nonEmptyString(roomData['area_name']),
      parentAreaName: _nonEmptyString(roomData['parent_area_name']),
    );
  }

  Future<int?> getHighEnergyUserCount(String roomId) async {
    try {
      final realRoomId = await resolveRealRoomId(roomId);
      final response = await liveDio.get(
        '$liveApiBase/room/v1/Room/get_info',
        queryParameters: {'room_id': realRoomId},
      );
      final roomResponseData = response.data;
      if (roomResponseData is! Map ||
          roomResponseData['code'] != 0 ||
          roomResponseData['data'] is! Map) {
        return null;
      }
      final uid = _asInt(roomResponseData['data']['uid']);
      if (uid == null) return null;

      final rankResponse = await liveDio.get(
        '$liveApiBase/xlive/general-interface/v1/rank/getOnlineGoldRank',
        queryParameters: {
          'ruid': uid,
          'roomId': realRoomId,
          'page': 1,
          'pageSize': 1,
        },
      );
      final rankData = rankResponse.data;
      if (rankData is Map && rankData['code'] == 0) {
        return _asInt(rankData['data']?['onlineNum']);
      }
    } catch (e) {
      logWarning('Failed to get Bilibili live high energy count $roomId: $e');
    }
    return null;
  }

  Future<BilibiliLiveStream> getRadioStream(String roomId) async {
    final realRoomId = await resolveRealRoomId(roomId);
    final response = await liveDio.get(
      '$liveApiBase/room/v1/Room/playUrl',
      queryParameters: {
        'cid': realRoomId,
        'platform': 'web',
        'quality': 2,
        'qn': 80,
      },
    );

    final responseData = response.data;
    if (responseData is! Map || responseData['code'] != 0) {
      throw Exception(
        'Failed to get stream URL: ${responseData is Map ? responseData['message'] : null}',
      );
    }

    final data = responseData['data'];
    final streamUrl = _firstDurlUrl(data is Map ? data['durl'] : null);
    if (streamUrl == null) {
      throw Exception('No stream URL available');
    }

    return BilibiliLiveStream(
      url: streamUrl,
      headers: SourceHttpPolicy.bilibiliLiveHeaders(),
    );
  }

  Future<String?> getSearchStreamUrl(int roomId) async {
    try {
      final response = await liveDio.get(
        '$liveApiBase/room/v1/Room/playUrl',
        queryParameters: {
          'cid': roomId,
          'platform': 'h5',
          'quality': 4,
        },
      );

      final responseData = response.data;
      if (responseData is! Map || responseData['code'] != 0) return null;
      final data = responseData['data'];
      return _firstDurlUrl(data is Map ? data['durl'] : null);
    } on DioException catch (e) {
      logWarning('Failed to get Bilibili live search stream URL $roomId: $e');
      return null;
    }
  }

  Future<LiveSearchResult> searchRooms(
    String query, {
    int page = 1,
    int pageSize = 20,
    LiveRoomFilter filter = LiveRoomFilter.all,
  }) async {
    if (filter == LiveRoomFilter.offline) {
      final result = await _searchBiliUserApi(query, page, pageSize);
      return result.filter(filter);
    }

    final results = await Future.wait([
      _searchLiveRoomApi(query, page, pageSize),
      _searchBiliUserApi(query, page, pageSize),
    ]);
    final result = results[0].merge(results[1]);
    return result.filter(filter);
  }

  Future<List<BilibiliMedalWallRoom>> getMedalWallRooms({
    required String targetId,
    required String cookie,
  }) async {
    final response = await liveDio.get(
      '$liveApiBase/xlive/web-ucenter/user/MedalWall',
      queryParameters: {'target_id': targetId},
      options: Options(headers: {'Cookie': cookie}),
    );

    final responseData = response.data;
    if (responseData is! Map || responseData['code'] != 0) {
      throw Exception(
        'MedalWall API error: ${responseData is Map ? responseData['message'] : null}',
      );
    }

    final list = responseData['data']?['list'];
    if (list is! List) return const [];

    final futures = list.map((item) async {
      if (item is! Map) return null;
      final medalInfo = item['medal_info'];
      if (medalInfo is! Map) return null;

      final uid = _asInt(medalInfo['target_id']) ?? 0;
      if (uid == 0) return null;

      try {
        final roomResponse = await liveDio.get(
          '$liveApiBase/room/v1/Room/getRoomInfoOld',
          queryParameters: {'mid': uid},
        );
        final roomResponseData = roomResponse.data;
        if (roomResponseData is! Map || roomResponseData['code'] != 0) {
          return null;
        }

        final roomId = roomResponseData['data']?['roomid']?.toString();
        if (roomId == null || roomId == '0') return null;

        return BilibiliMedalWallRoom(
          roomId: roomId,
          name: item['target_name'] as String? ?? '',
          avatarUrl: item['target_icon'] as String?,
          uid: uid,
          liveStatus: _asInt(item['live_status']) ?? 0,
          link: 'https://live.bilibili.com/$roomId',
        );
      } catch (e) {
        logWarning('Failed to get Bilibili medal wall room for uid $uid: $e');
        return null;
      }
    }).toList();

    final rooms = await Future.wait(futures);
    return rooms.whereType<BilibiliMedalWallRoom>().toList();
  }

  void dispose() {
    if (_ownsApiDio) apiDio.close();
    if (_ownsLiveDio) liveDio.close();
  }

  Future<LiveSearchResult> _searchLiveRoomApi(
    String query,
    int page,
    int pageSize,
  ) async {
    final response = await apiDio.get(
      '$apiBase$_searchApi',
      queryParameters: {
        'keyword': query,
        'search_type': 'live_room',
        'page': page,
        'page_size': pageSize,
      },
      options: _searchOptionsProvider(),
    );

    final data = _searchData(response.data);
    final results = data['result'] as List? ?? const [];
    final numResults = _asInt(data['numResults']) ?? 0;

    return LiveSearchResult(
      rooms: results
          .whereType<Map>()
          .map((item) => LiveRoom.fromLiveRoomSearch(
                Map<String, dynamic>.from(item),
              ))
          .toList(),
      totalCount: numResults,
      page: page,
      pageSize: pageSize,
      hasMore: page * pageSize < numResults,
    );
  }

  Future<LiveSearchResult> _searchBiliUserApi(
    String query,
    int page,
    int pageSize,
  ) async {
    final response = await apiDio.get(
      '$apiBase$_searchApi',
      queryParameters: {
        'keyword': query,
        'search_type': 'bili_user',
        'page': page,
        'page_size': pageSize,
      },
      options: _searchOptionsProvider(),
    );

    final data = _searchData(response.data);
    final results = data['result'] as List? ?? const [];
    final numResults = _asInt(data['numResults']) ?? 0;
    final rooms = <LiveRoom>[];

    for (final item in results.whereType<Map>()) {
      final json = Map<String, dynamic>.from(item);
      final roomId = _asInt(json['room_id']) ?? 0;
      if (roomId <= 0) continue;

      final searchUname = LiveRoom.fromBiliUserSearch(json).uname;
      final searchFace = _fixUrl(_nonEmptyString(json['upic']));

      try {
        final details = await getRoomInfo(roomId.toString());
        final room = details?.toLiveRoom();
        if (room != null) {
          rooms.add(
            room.copyWith(
              uname: searchUname.isNotEmpty ? searchUname : room.uname,
              face: searchFace ?? room.face,
            ),
          );
          continue;
        }
      } catch (e) {
        logWarning('Failed to get Bilibili live room info $roomId: $e');
      }

      rooms.add(LiveRoom.fromBiliUserSearch(json));
    }

    return LiveSearchResult(
      rooms: rooms,
      totalCount: numResults,
      page: page,
      pageSize: pageSize,
      hasMore: page * pageSize < numResults,
    );
  }

  Future<Map<dynamic, dynamic>?> _getAnchorInfo(String roomId) async {
    try {
      final response = await liveDio.get(
        '$liveApiBase/live_user/v1/UserInfo/get_anchor_in_room',
        queryParameters: {'roomid': roomId},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final info = data['data']['info'];
        if (info is Map) return info;
      }
    } catch (e) {
      logWarning('Failed to get Bilibili live anchor info $roomId: $e');
    }
    return null;
  }

  Future<String?> _getRoomAnnouncement(String roomId) async {
    try {
      final response = await liveDio.get(
        '$liveApiBase/room_ex/v1/RoomNews/get',
        queryParameters: {'roomid': roomId},
      );
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        return _nonEmptyString(data['data']?['content']);
      }
    } catch (e) {
      logWarning('Failed to get Bilibili live room news $roomId: $e');
    }
    return null;
  }

  static bool _isRoomId(String value) => RegExp(r'^\d+$').hasMatch(value);

  static LiveStatus _liveStatusFromCode(int? code) {
    return switch (code) {
      1 => LiveStatus.live,
      2 => LiveStatus.replay,
      _ => LiveStatus.offline,
    };
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _nonEmptyString(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static String? _fixUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }

  static String? _firstDurlUrl(Object? durl) {
    if (durl is! List || durl.isEmpty) return null;
    final first = durl.first;
    if (first is! Map) return null;
    final url = first['url'];
    return url is String && url.isNotEmpty ? url : null;
  }

  Map<dynamic, dynamic> _searchData(Object? responseData) {
    if (responseData is! Map) {
      throw const BilibiliApiException(
        numericCode: -999,
        message: 'Invalid Bilibili search response',
      );
    }

    final code = _asInt(responseData['code']);
    if (code == null) {
      throw const BilibiliApiException(
        numericCode: -999,
        message: 'Invalid Bilibili search response',
      );
    }

    if (code != 0) {
      final message = responseData['message']?.toString() ?? 'Unknown error';
      if (_isRateLimitCode(code)) {
        logWarning('Bilibili rate limited: code=$code, message=$message');
        throw BilibiliApiException(
          numericCode: code,
          message: t.error.rateLimited,
        );
      }

      logWarning('Bilibili API error: code=$code, message=$message');
      throw BilibiliApiException(numericCode: code, message: message);
    }

    final data = responseData['data'];
    if (data is Map) {
      return data;
    }

    throw const BilibiliApiException(
      numericCode: -999,
      message: 'Invalid Bilibili search response',
    );
  }

  static bool _isRateLimitCode(int code) {
    return code == -352 || code == -412 || code == -509 || code == -799;
  }

  static DateTime? _parseLiveStartTime(Object? value) {
    if (value == null) return null;
    final seconds = _asInt(value);
    if (seconds != null && seconds > 0) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    }
    if (value is String && value != '0000-00-00 00:00:00') {
      return DateTime.tryParse(value.replaceFirst(' ', 'T'));
    }
    return null;
  }
}
