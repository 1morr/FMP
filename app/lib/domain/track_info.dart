import 'package:flutter/foundation.dart';

import 'package:fmp/domain/track_key.dart';

/// 一首曲目：曲目鍵與音源給的顯示資料（ADR 0010 §決定 2「只存事實」）。
///
/// 佇列、播放歷史與之後的 `tracks` 表都用它；插件的 `TrackSummary` 經
/// `lib/plugins/` 的 `toTrackInfo` 轉過來，這一層不認得插件的 DTO。
@immutable
final class TrackInfo {
  const TrackInfo({
    required this.sourceTypeId,
    required this.sourceId,
    this.cid,
    required this.title,
    this.uploader,
    this.duration,
    this.artwork = const [],
  });

  /// 曲目鍵的三段（`TrackKey.format`）：音源（插件 id）、音源內的 id、分 P 的 cid。
  final String sourceTypeId;
  final String sourceId;
  final int? cid;

  final String title;
  final String? uploader;
  final Duration? duration;

  /// 多尺寸封面（ADR 0016 §決定 4）。
  final List<TrackArtwork> artwork;

  TrackKeyParts get key =>
      TrackKeyParts(sourceTypeId: sourceTypeId, sourceId: sourceId, cid: cid);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackInfo &&
          other.sourceTypeId == sourceTypeId &&
          other.sourceId == sourceId &&
          other.cid == cid &&
          other.title == title &&
          other.uploader == uploader &&
          other.duration == duration &&
          listEquals(other.artwork, artwork);

  @override
  int get hashCode => Object.hash(
    sourceTypeId,
    sourceId,
    cid,
    title,
    uploader,
    duration,
    Object.hashAll(artwork),
  );
}

/// 封面的一個尺寸。
@immutable
final class TrackArtwork {
  const TrackArtwork({required this.url, this.width});

  final Uri url;

  /// 像素寬度；不知道就是 `null`。
  final int? width;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackArtwork && other.url == url && other.width == width;

  @override
  int get hashCode => Object.hash(url, width);
}

/// 從多尺寸封面（插件給的，ADR 0016 §決定 4）挑一張要顯示 [pixels] 像素的：寬度
/// 不小於 [pixels] 的裡面最小的；都比它小時，先取沒標寬度的（插件多半只給原圖，
/// 例如 B 站），再來才是最大的那張。沒有封面就是 `null`。
///
/// 放在這裡而不是封面元件：播放列的縮圖與系統媒體控制的封面（播放層）都用它。
TrackArtwork? pickArtwork(List<TrackArtwork> artwork, double pixels) {
  TrackArtwork? smallestEnough;
  TrackArtwork? largest;
  TrackArtwork? unknown;
  for (final candidate in artwork) {
    final width = candidate.width;
    if (width == null) {
      unknown ??= candidate;
    } else if (width >= pixels) {
      if (smallestEnough == null || width < smallestEnough.width!) {
        smallestEnough = candidate;
      }
    } else if (largest == null || width > largest.width!) {
      largest = candidate;
    }
  }
  return smallestEnough ?? unknown ?? largest;
}
