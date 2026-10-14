import 'package:flutter/foundation.dart';

import 'package:fmp/domain/track_info.dart';

/// 要收聽的直播間（ADR 0018 §決定 9）：`PlaybackController.playLive` 的輸入，也是
/// 進入直播後 [LiveInfo] 的起點。顯示資料取自電台清單或搜尋結果，進入後由收聽中
/// 的 `live-info` 工作更新（[LiveInfo]）。
@immutable
final class LiveTarget {
  const LiveTarget({
    required this.pluginId,
    required this.roomId,
    required this.title,
    this.hostName,
    this.artwork = const [],
  });

  final String pluginId;

  /// 音源內的直播間 id。
  final String roomId;
  final String title;
  final String? hostName;
  final List<TrackArtwork> artwork;

  @override
  bool operator ==(Object other) =>
      other is LiveTarget &&
      other.pluginId == pluginId &&
      other.roomId == roomId &&
      other.title == title &&
      other.hostName == hostName &&
      listEquals(other.artwork, artwork);

  @override
  int get hashCode =>
      Object.hash(pluginId, roomId, title, hostName, Object.hashAll(artwork));
}

/// 收聽直播的進度（ADR 0031 §決定 7）。
enum LivePhase {
  /// 收聽中：包含載入、緩衝、暫停（暫停就是停止串流）與重連。細節看播放狀態
  /// （`Loading`、`Retrying`、`Playing`、`Paused`）。
  listening,

  /// 直播已結束：提前結束後 `liveStatus` 說沒有在直播，或重連用完仍連不上。
  ended,

  /// 提前結束後問 `liveStatus` 失敗：顯示「查詢失敗」並停下，不當成未開播（D10）。
  statusFailed,
}

/// 目前收聽的直播間的即時資訊，只由 `PlaybackController` 改（`QueueState.live` 是
/// 進入時的快照，這個會被 `live-info` 工作更新）。已收聽時間是播放進度的位置。
@immutable
final class LiveInfo {
  const LiveInfo({
    required this.target,
    required this.title,
    required this.hostName,
    required this.artwork,
    this.online,
    this.phase = LivePhase.listening,
  });

  factory LiveInfo.of(LiveTarget target) => LiveInfo(
    target: target,
    title: target.title,
    hostName: target.hostName,
    artwork: target.artwork,
  );

  final LiveTarget target;

  /// 直播標題，最新的。
  final String title;
  final String? hostName;
  final List<TrackArtwork> artwork;

  /// 觀看人數；不知道就是 `null`。
  final int? online;
  final LivePhase phase;

  LiveInfo copyWith({
    String? title,
    String? hostName,
    List<TrackArtwork>? artwork,
    int? online,
    LivePhase? phase,
  }) => LiveInfo(
    target: target,
    title: title ?? this.title,
    hostName: hostName ?? this.hostName,
    artwork: artwork ?? this.artwork,
    online: online ?? this.online,
    phase: phase ?? this.phase,
  );

  /// 給系統媒體控制取封面用的曲目形狀（標題、主播、封面）。
  TrackInfo toTrackInfo() => TrackInfo(
    sourceTypeId: target.pluginId,
    sourceId: target.roomId,
    title: title,
    uploader: hostName,
    artwork: artwork,
  );

  @override
  bool operator ==(Object other) =>
      other is LiveInfo &&
      other.target == target &&
      other.title == title &&
      other.hostName == hostName &&
      listEquals(other.artwork, artwork) &&
      other.online == online &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(
    target,
    title,
    hostName,
    Object.hashAll(artwork),
    online,
    phase,
  );
}
