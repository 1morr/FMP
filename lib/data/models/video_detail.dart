import 'package:fmp/i18n/strings.g.dart';

import '../../core/utils/number_format_utils.dart';
import 'track.dart';

/// 视频分P信息（不存入数据库，用于API响应和临时展示）
class VideoPage {
  final int cid;
  final int page; // 分P序号，从1开始
  final String part; // 分P标题
  final int duration; // 时长（秒）

  const VideoPage({
    required this.cid,
    required this.page,
    required this.part,
    required this.duration,
  });

  /// 格式化时长
  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 转换为Track对象
  Track toTrack(Track parent) => Track()
    ..sourceId = parent.sourceId
    ..sourceType = parent.sourceType
    ..title = part // 只显示分P标题
    ..artist = parent.artist
    ..ownerId = parent.ownerId
    ..durationMs = duration * 1000
    ..thumbnailUrl = parent.thumbnailUrl
    ..cid = cid
    ..pageNum = page
    ..pageCount = parent.pageCount
    ..parentTitle = parent.title
    ..createdAt = DateTime.now();

  @override
  String toString() => 'VideoPage(cid: $cid, page: $page, part: $part)';
}

/// 视频详细信息（用于右侧详情面板显示）
class VideoDetail {
  final String bvid;
  final String title;
  final String description;
  final String coverUrl;
  final String ownerName;
  final String ownerFace;
  final int ownerId;
  final String channelId; // YouTube 頻道 ID
  final int viewCount;
  final int likeCount;
  final int coinCount;
  final int favoriteCount;
  final int shareCount;
  final int danmakuCount;
  final int commentCount;
  final DateTime publishDate;
  final int durationSeconds;
  final List<VideoComment> hotComments;
  final List<VideoPage> pages;

  const VideoDetail({
    required this.bvid,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.ownerName,
    required this.ownerFace,
    required this.ownerId,
    this.channelId = '',
    required this.viewCount,
    required this.likeCount,
    required this.coinCount,
    required this.favoriteCount,
    required this.shareCount,
    required this.danmakuCount,
    required this.commentCount,
    required this.publishDate,
    required this.durationSeconds,
    this.hotComments = const [],
    this.pages = const [],
  });

  /// 从本地 metadata.json 创建 VideoDetail
  factory VideoDetail.fromMetadata(Map<String, dynamic> json, Track track) {
    final hotComments = (json['hotComments'] as List<dynamic>? ?? [])
        .map((c) => VideoComment(
              id: 0,
              content: c['content']?.toString() ?? '',
              memberName: c['memberName']?.toString() ?? '',
              memberAvatar: c['memberAvatar']?.toString() ?? '',
              likeCount: c['likeCount'] as int? ?? 0,
              createTime: DateTime.now(),
            ))
        .toList();

    return VideoDetail(
      bvid: json['sourceId']?.toString() ?? track.sourceId,
      title: json['parentTitle']?.toString() ?? json['title']?.toString() ?? track.title,
      description: json['description']?.toString() ?? '',
      coverUrl: json['thumbnailUrl']?.toString() ?? track.thumbnailUrl ?? '',
      ownerName: json['ownerName']?.toString() ?? json['artist']?.toString() ?? track.artist ?? '',
      ownerFace: json['ownerFace']?.toString() ?? '',
      ownerId: json['ownerId'] as int? ?? 0,
      channelId: json['channelId']?.toString() ?? '',
      viewCount: json['viewCount'] as int? ?? 0,
      likeCount: json['likeCount'] as int? ?? 0,
      coinCount: json['coinCount'] as int? ?? 0,
      favoriteCount: json['favoriteCount'] as int? ?? 0,
      shareCount: json['shareCount'] as int? ?? 0,
      danmakuCount: json['danmakuCount'] as int? ?? 0,
      commentCount: json['commentCount'] as int? ?? 0,
      publishDate: json['publishDate'] != null
          ? DateTime.tryParse(json['publishDate'].toString()) ?? DateTime.now()
          : DateTime.now(),
      durationSeconds: (json['durationMs'] as int? ?? track.durationMs ?? 0) ~/ 1000,
      hotComments: hotComments,
      pages: [],
    );
  }

  /// 从 YouTube 数据创建 VideoDetail
  /// [videoId] YouTube 视频 ID
  /// [title] 视频标题
  /// [description] 视频描述
  /// [author] 频道名称
  /// [authorAvatarUrl] 频道头像 URL
  /// [thumbnailUrl] 缩略图 URL
  /// [durationMs] 时长（毫秒）
  /// [viewCount] 播放数
  /// [likeCount] 点赞数
  /// [publishDate] 发布日期
  /// [comments] 热门评论列表
  factory VideoDetail.fromYouTube({
    required String videoId,
    required String title,
    required String description,
    required String author,
    String? authorAvatarUrl,
    String? thumbnailUrl,
    String channelId = '',
    int durationMs = 0,
    int viewCount = 0,
    int likeCount = 0,
    DateTime? publishDate,
    List<VideoComment> comments = const [],
  }) {
    return VideoDetail(
      bvid: videoId,
      title: title,
      description: description,
      coverUrl: thumbnailUrl ?? '',
      ownerName: author,
      ownerFace: authorAvatarUrl ?? '',
      ownerId: 0,
      channelId: channelId,
      viewCount: viewCount,
      likeCount: likeCount,
      coinCount: 0, // YouTube 没有投币功能
      favoriteCount: 0, // YouTube 无法直接获取收藏数
      shareCount: 0,
      danmakuCount: 0, // YouTube 没有弹幕
      commentCount: 0, // 需要额外 API 获取
      publishDate: publishDate ?? DateTime.now(),
      durationSeconds: durationMs ~/ 1000,
      hotComments: comments,
      pages: [],
    );
  }

  /// 是否有多个分P
  bool get hasMultiplePages => pages.length > 1;

  /// 分P数量
  int get pageCount => pages.length;

  /// 格式化播放数
  String get formattedViewCount => _formatCount(viewCount);

  /// 格式化点赞数
  String get formattedLikeCount => _formatCount(likeCount);

  /// 格式化投币数
  String get formattedCoinCount => _formatCount(coinCount);

  /// 格式化收藏数
  String get formattedFavoriteCount => _formatCount(favoriteCount);

  /// 格式化分享数
  String get formattedShareCount => _formatCount(shareCount);

  /// 格式化弹幕数
  String get formattedDanmakuCount => _formatCount(danmakuCount);

  /// 格式化评论数
  String get formattedCommentCount => _formatCount(commentCount);

  /// 格式化数字
  static String _formatCount(int count) => formatCount(count);

  /// 格式化时长
  String get formattedDuration {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 格式化发布时间
  String get formattedPublishDate {
    final now = DateTime.now();
    final diff = now.difference(publishDate);
    if (diff.inDays > 365) {
      return t.videoDetail.yearsAgo(n: diff.inDays ~/ 365);
    } else if (diff.inDays > 30) {
      return t.videoDetail.monthsAgo(n: diff.inDays ~/ 30);
    } else if (diff.inDays > 0) {
      return t.videoDetail.daysAgo(n: diff.inDays);
    } else if (diff.inHours > 0) {
      return t.videoDetail.hoursAgo(n: diff.inHours);
    } else if (diff.inMinutes > 0) {
      return t.videoDetail.minutesAgo(n: diff.inMinutes);
    }
    return t.videoDetail.justNow;
  }
}

/// 视频评论
class VideoComment {
  final int id;
  final String content;
  final String memberName;
  final String memberAvatar;
  final int likeCount;
  final DateTime createTime;

  const VideoComment({
    required this.id,
    required this.content,
    required this.memberName,
    required this.memberAvatar,
    required this.likeCount,
    required this.createTime,
  });

  /// 格式化点赞数
  String get formattedLikeCount => VideoDetail._formatCount(likeCount);

  /// 格式化时间
  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(createTime);
    if (diff.inDays > 365) {
      return t.videoDetail.yearsAgo(n: diff.inDays ~/ 365);
    } else if (diff.inDays > 30) {
      return t.videoDetail.monthsAgo(n: diff.inDays ~/ 30);
    } else if (diff.inDays > 0) {
      return t.videoDetail.daysAgo(n: diff.inDays);
    } else if (diff.inHours > 0) {
      return t.videoDetail.hoursAgo(n: diff.inHours);
    } else if (diff.inMinutes > 0) {
      return t.videoDetail.minutesAgo(n: diff.inMinutes);
    }
    return t.videoDetail.justNow;
  }
}
