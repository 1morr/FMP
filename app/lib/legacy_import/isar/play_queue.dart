import 'package:isar_community/isar.dart';

part 'play_queue.g.dart';

/// 循環模式；磁碟上存 `name`（字串）。
enum LoopMode { none, all, one }

@collection
class PlayQueue {
  Id id = Isar.autoIncrement;

  List<int> trackIds = [];
  int currentIndex = 0;
  int lastPositionMs = 0;
  bool isShuffleEnabled = false;

  @Enumerated(EnumType.name)
  LoopMode loopMode = LoopMode.none;

  List<int>? originalOrder;
  double lastVolume = 1.0;
  DateTime? lastUpdated;
  bool isMixMode = false;
  String? mixPlaylistId;
  String? mixSeedVideoId;
  String? mixTitle;

  // 下面六個 getter 在舊版沒標 @ignore，被存成欄位（schema 的一部分）；
  // 匯入不讀它們。
  int get length => trackIds.length;
  bool get isEmpty => trackIds.isEmpty;
  bool get isNotEmpty => trackIds.isNotEmpty;
  bool get hasNext => currentIndex < trackIds.length - 1;
  bool get hasPrevious => currentIndex > 0;
  int? get currentTrackId {
    if (trackIds.isEmpty || currentIndex >= trackIds.length) return null;
    return trackIds[currentIndex];
  }
}
