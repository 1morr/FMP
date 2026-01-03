import 'package:isar/isar.dart';
import 'track.dart';

part 'playlist.g.dart';

/// 歌单实体
@collection
class Playlist {
  Id id = Isar.autoIncrement;

  /// 歌单名称
  @Index(unique: true)
  late String name;

  /// 歌单描述
  String? description;

  /// 自定义封面 URL
  String? coverUrl;

  /// 本地封面路径
  String? coverLocalPath;

  /// 导入源 URL（B站收藏夹/YouTube播放列表 URL）
  String? sourceUrl;

  /// 导入源类型
  @Enumerated(EnumType.name)
  SourceType? importSourceType;

  /// 刷新间隔（小时）
  int? refreshIntervalHours;

  /// 上次刷新时间
  DateTime? lastRefreshed;

  /// 是否在更新时通知
  bool notifyOnUpdate = true;

  /// 关联的歌曲ID列表（有序）
  List<int> trackIds = [];

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 更新时间
  DateTime? updatedAt;

  /// 是否是导入的歌单
  bool get isImported => sourceUrl != null;

  /// 歌曲数量
  int get trackCount => trackIds.length;

  /// 是否需要刷新
  bool get needsRefresh {
    if (!isImported || refreshIntervalHours == null) return false;
    if (lastRefreshed == null) return true;
    final nextRefresh = lastRefreshed!.add(Duration(hours: refreshIntervalHours!));
    return DateTime.now().isAfter(nextRefresh);
  }

  @override
  String toString() => 'Playlist(id: $id, name: $name, trackCount: $trackCount)';
}
