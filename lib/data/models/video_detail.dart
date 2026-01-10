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
    ..durationMs = duration * 1000
    ..thumbnailUrl = parent.thumbnailUrl
    ..cid = cid
    ..pageNum = page
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

  /// 格式化数字（万/亿）
  static String _formatCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    } else if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

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
      return '${diff.inDays ~/ 365}年前';
    } else if (diff.inDays > 30) {
      return '${diff.inDays ~/ 30}个月前';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    }
    return '刚刚';
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
      return '${diff.inDays ~/ 365}年前';
    } else if (diff.inDays > 30) {
      return '${diff.inDays ~/ 30}个月前';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    }
    return '刚刚';
  }
}
