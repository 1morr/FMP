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
    this.partIndex,
    this.parentTitle,
    this.viewCount,
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

  /// 分 P 曲目才有（M3 design §11.1）：分 P 的序號（從 1 起）與影片標題；[title] 是
  /// 分 P 的標題。顯示用 [displayTitle]。
  final int? partIndex;
  final String? parentTitle;

  /// 播放數（插件有給才有，ADR 0035 §決定 10）：只是列上的顯示資料，不寫進 `tracks` 表
  /// （佇列、歷史、歌單讀回來沒有），只在搜尋結果與榜單快取裡帶著。
  final int? viewCount;

  /// 分 P 的標籤「P2 分 P 標題」；不是分 P 曲目時是 [title]。分 P 沒有自己的標題時插件
  /// 給的就是 `P<序號>`，這時只顯示一次（不寫成「P3 P3」）。
  String get partLabel => switch (partIndex) {
    final index? when title == 'P$index' => title,
    final index? => 'P$index $title',
    null => title,
  };

  /// 顯示用的標題：分 P 曲目是「影片標題 · P2 分 P 標題」，其他是 [title]。
  String get displayTitle => switch (parentTitle) {
    final parent? when partIndex != null => '$parent · $partLabel',
    _ => title,
  };

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
          listEquals(other.artwork, artwork) &&
          other.partIndex == partIndex &&
          other.parentTitle == parentTitle &&
          other.viewCount == viewCount;

  @override
  int get hashCode => Object.hash(
    sourceTypeId,
    sourceId,
    cid,
    title,
    uploader,
    duration,
    Object.hashAll(artwork),
    partIndex,
    parentTitle,
    viewCount,
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
