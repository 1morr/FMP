import 'package:isar/isar.dart';

part 'play_queue.g.dart';

/// 循环模式枚举
enum LoopMode {
  /// 不循环（播放到队列末尾停止）
  none,

  /// 列表循环
  all,

  /// 单曲循环
  one,
}

/// 播放队列实体
@collection
class PlayQueue {
  Id id = Isar.autoIncrement;

  /// 队列中的歌曲ID列表（有序）
  List<int> trackIds = [];

  /// 当前播放索引
  int currentIndex = 0;

  /// 上次播放位置（毫秒）
  int lastPositionMs = 0;

  /// 是否启用随机播放
  bool isShuffleEnabled = false;

  /// 循环模式
  @Enumerated(EnumType.name)
  LoopMode loopMode = LoopMode.none;

  /// 原始顺序（用于取消随机时恢复）
  List<int>? originalOrder;

  /// 上次音量 (0.0 - 1.0)
  double lastVolume = 1.0;

  /// 上次更新时间
  DateTime? lastUpdated;

  // ========== Mix 播放列表狀態 ==========

  /// 是否為 Mix 播放模式
  bool isMixMode = false;

  /// Mix 播放列表 ID（如 RDTbFSpvlaugc）
  String? mixPlaylistId;

  /// Mix 種子視頻 ID（用於首次加載）
  String? mixSeedVideoId;

  /// Mix 播放列表標題
  String? mixTitle;

  /// 队列长度
  int get length => trackIds.length;

  /// 队列是否为空
  bool get isEmpty => trackIds.isEmpty;

  /// 队列是否不为空
  bool get isNotEmpty => trackIds.isNotEmpty;

  /// 是否有下一首
  bool get hasNext => currentIndex < trackIds.length - 1;

  /// 是否有上一首
  bool get hasPrevious => currentIndex > 0;

  /// 当前歌曲ID
  int? get currentTrackId {
    if (trackIds.isEmpty || currentIndex >= trackIds.length) return null;
    return trackIds[currentIndex];
  }

  @override
  String toString() =>
      'PlayQueue(id: $id, length: $length, currentIndex: $currentIndex, shuffle: $isShuffleEnabled, loop: $loopMode)';
}
