import 'radio_station.dart';
import 'track.dart';

/// 直播间状态筛选
enum LiveRoomFilter {
  all,      // 全部直播间
  offline,  // 未开播
  online,   // 已开播
}

/// 直播状态
enum LiveStatus {
  offline,  // 未开播 (0)
  live,     // 直播中 (1)
  replay,   // 轮播中 (2)
}

/// 直播间信息
class LiveRoom {
  final int roomId;
  final int uid;
  final String uname;
  final String title;
  final String? cover;
  final String? face;
  final bool isLive;
  final int? online;
  final String? areaName;
  final String? tags;
  final LiveStatus liveStatus;

  const LiveRoom({
    required this.roomId,
    required this.uid,
    required this.uname,
    required this.title,
    this.cover,
    this.face,
    this.isLive = false,
    this.online,
    this.areaName,
    this.tags,
    this.liveStatus = LiveStatus.offline,
  });

  /// 从 live_room 搜索结果创建
  factory LiveRoom.fromLiveRoomSearch(Map<String, dynamic> json) {
    return LiveRoom(
      roomId: json['roomid'] as int? ?? 0,
      uid: json['uid'] as int? ?? 0,
      uname: _cleanHtmlTags(json['uname'] as String? ?? ''),
      title: _cleanHtmlTags(json['title'] as String? ?? ''),
      cover: _fixImageUrl(json['user_cover'] as String?),
      face: _fixImageUrl(json['uface'] as String?),
      isLive: true, // live_room 搜索结果都是正在直播的
      online: json['online'] as int?,
      areaName: (json['cate_name'] as String?) != null ? _cleanHtmlTags(json['cate_name'] as String) : null,
      tags: (json['tags'] as String?) != null ? _cleanHtmlTags(json['tags'] as String) : null,
      liveStatus: LiveStatus.live,
    );
  }

  /// 从 bili_user 搜索结果创建
  factory LiveRoom.fromBiliUserSearch(Map<String, dynamic> json) {
    final roomId = json['room_id'] as int? ?? 0;
    return LiveRoom(
      roomId: roomId,
      uid: json['mid'] as int? ?? 0,
      uname: _cleanHtmlTags(json['uname'] as String? ?? ''),
      title: '', // bili_user 搜索不返回直播间标题
      cover: null,
      face: _fixImageUrl(json['upic'] as String?),
      isLive: false, // 需要额外查询直播状态
      online: null,
      areaName: null,
      tags: null,
      liveStatus: LiveStatus.offline,
    );
  }

  /// 从 live_user 搜索结果创建
  factory LiveRoom.fromLiveUserSearch(Map<String, dynamic> json) {
    final isLive = json['is_live'] == true;
    return LiveRoom(
      roomId: json['roomid'] as int? ?? 0,
      uid: json['uid'] as int? ?? 0,
      uname: _cleanHtmlTags(json['uname'] as String? ?? ''),
      title: _cleanHtmlTags(json['title'] as String? ?? ''),
      cover: _fixImageUrl(json['user_cover'] as String?),
      face: _fixImageUrl(json['uface'] as String?),
      isLive: isLive,
      online: json['online'] as int?,
      areaName: (json['cate_name'] as String?) != null ? _cleanHtmlTags(json['cate_name'] as String) : null,
      tags: (json['tags'] as String?) != null ? _cleanHtmlTags(json['tags'] as String) : null,
      liveStatus: isLive ? LiveStatus.live : LiveStatus.offline,
    );
  }

  /// 从直播间详情 API 创建
  factory LiveRoom.fromRoomInfo(Map<String, dynamic> json, {String? uname, String? face}) {
    final statusCode = json['live_status'] as int? ?? 0;
    final liveStatus = switch (statusCode) {
      1 => LiveStatus.live,
      2 => LiveStatus.replay,
      _ => LiveStatus.offline,
    };
    return LiveRoom(
      roomId: json['room_id'] as int? ?? 0,
      uid: json['uid'] as int? ?? 0,
      uname: uname ?? '',
      title: json['title'] as String? ?? '',
      cover: _fixImageUrl(json['user_cover'] as String?),
      face: face,
      isLive: liveStatus == LiveStatus.live,
      online: json['online'] as int?,
      areaName: json['area_name'] as String?,
      tags: json['tags'] as String?,
      liveStatus: liveStatus,
    );
  }

  /// 复制并更新字段
  LiveRoom copyWith({
    int? roomId,
    int? uid,
    String? uname,
    String? title,
    String? cover,
    String? face,
    bool? isLive,
    int? online,
    String? areaName,
    String? tags,
    LiveStatus? liveStatus,
  }) {
    return LiveRoom(
      roomId: roomId ?? this.roomId,
      uid: uid ?? this.uid,
      uname: uname ?? this.uname,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      face: face ?? this.face,
      isLive: isLive ?? this.isLive,
      online: online ?? this.online,
      areaName: areaName ?? this.areaName,
      tags: tags ?? this.tags,
      liveStatus: liveStatus ?? this.liveStatus,
    );
  }

  /// 获取直播状态文本
  String get liveStatusText => switch (liveStatus) {
    LiveStatus.live => '直播中',
    LiveStatus.replay => '轮播中',
    LiveStatus.offline => '未开播',
  };

  /// 是否可以播放（直播中或轮播中）
  bool get canPlay => liveStatus == LiveStatus.live || liveStatus == LiveStatus.replay;

  /// 转换为 Track 对象（用于播放器显示）
  Track toTrack({String? streamUrl}) {
    return Track()
      ..sourceId = 'live_$roomId'
      ..sourceType = SourceType.bilibili
      ..title = title.isNotEmpty ? title : '$uname的直播间'
      ..artist = uname
      ..ownerId = uid
      ..thumbnailUrl = cover ?? face
      ..audioUrl = streamUrl
      ..durationMs = null // 直播没有时长
      ..isAvailable = isLive;
  }

  /// 转换为 RadioStation 对象（用于电台播放器）
  RadioStation toRadioStation() {
    return RadioStation()
      ..url = 'https://live.bilibili.com/$roomId'
      ..title = title.isNotEmpty ? title : '$uname的直播间'
      ..thumbnailUrl = cover
      ..hostName = uname
      ..hostAvatarUrl = face
      ..hostUid = uid
      ..sourceType = SourceType.bilibili
      ..sourceId = roomId.toString();
  }

  /// 清理 HTML 标签
  static String _cleanHtmlTags(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  /// 修复图片 URL
  static String? _fixImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    return url;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LiveRoom && other.roomId == roomId;
  }

  @override
  int get hashCode => roomId.hashCode;
}

/// 直播间搜索结果
class LiveSearchResult {
  final List<LiveRoom> rooms;
  final int totalCount;
  final int page;
  final int pageSize;
  final bool hasMore;

  const LiveSearchResult({
    required this.rooms,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  const LiveSearchResult.empty()
      : rooms = const [],
        totalCount = 0,
        page = 1,
        pageSize = 20,
        hasMore = false;

  /// 合并两个搜索结果（去重）
  LiveSearchResult merge(LiveSearchResult other) {
    final mergedRooms = <int, LiveRoom>{};
    
    // 先添加当前结果
    for (final room in rooms) {
      mergedRooms[room.roomId] = room;
    }
    
    // 添加其他结果（如果 roomId 相同，优先保留 isLive=true 的）
    for (final room in other.rooms) {
      final existing = mergedRooms[room.roomId];
      if (existing == null) {
        mergedRooms[room.roomId] = room;
      } else if (room.isLive && !existing.isLive) {
        // 优先保留直播中的信息
        mergedRooms[room.roomId] = room;
      } else if (room.title.isNotEmpty && existing.title.isEmpty) {
        // 补充标题信息
        mergedRooms[room.roomId] = existing.copyWith(title: room.title);
      }
    }

    return LiveSearchResult(
      rooms: mergedRooms.values.toList(),
      totalCount: totalCount + other.totalCount,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore || other.hasMore,
    );
  }

  /// 按筛选条件过滤
  LiveSearchResult filter(LiveRoomFilter filterType) {
    if (filterType == LiveRoomFilter.all) return this;
    
    final filteredRooms = rooms.where((room) {
      return switch (filterType) {
        LiveRoomFilter.all => true,
        LiveRoomFilter.offline => !room.isLive,
        LiveRoomFilter.online => room.isLive,
      };
    }).toList();

    return LiveSearchResult(
      rooms: filteredRooms,
      totalCount: filteredRooms.length,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }
}
