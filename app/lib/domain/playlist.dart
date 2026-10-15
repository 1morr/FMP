import 'package:flutter/foundation.dart';

import 'package:fmp/domain/track_info.dart';

/// `playlists.kind` 存的歌單種類（ADR 0033 §決定 1）。
///
/// 放在 `domain/`：字串寫死在資料層的轉換裡，不用 [name]。
enum PlaylistKind {
  /// 使用者自建。
  local,

  /// 從網址匯入。
  imported,

  /// Mix 歌單。
  mix,
}

/// `playlist_remote.status`：遠端歌單現在讀不讀得到（ADR 0033 §決定 1）。
///
/// 字串寫死在資料層的轉換裡，不用 [name]。
enum PlaylistRemoteStatus {
  /// 正常。
  active,

  /// 遠端歌單已刪除或沒有權限（`NotFound`）：停止自動刷新，保留內容。
  sourceGone,

  /// 要登入才讀得到而沒有登入（`AuthRequired`）：停止自動刷新，保留內容。
  authRequired,
}

/// `playlist_remote.last_result`：上一次刷新的結果（ADR 0033 §決定 1）；空＝還沒刷新完過。
enum PlaylistRefreshResult {
  /// 完整套用。
  complete,

  /// 只新增與更新，沒有移除與重排（ADR 0032 §決定 2 的「不完整」）。
  partial,

  /// 這次沒讀到任何東西。
  failed,
}

/// 遠端歌單本身的資料（`playlists` 與 `playlist_remote` 要跟著遠端的欄位）。
///
/// 插件的 `RemotePlaylist` 由 `lib/library/` 轉過來，資料層不認得插件的 DTO。
@immutable
final class RemotePlaylistInfo {
  const RemotePlaylistInfo({
    required this.name,
    this.description,
    this.artwork = const [],
    this.ownerName,
    this.writable,
  });

  final String name;
  final String? description;
  final List<TrackArtwork> artwork;
  final String? ownerName;

  /// `null` 是這次不知道，保留上次的值（ADR 0032 §決定 2）。
  final bool? writable;

  @override
  bool operator ==(Object other) =>
      other is RemotePlaylistInfo &&
      other.name == name &&
      other.description == description &&
      listEquals(other.artwork, artwork) &&
      other.ownerName == ownerName &&
      other.writable == writable;

  @override
  int get hashCode => Object.hash(
    name,
    description,
    Object.hashAll(artwork),
    ownerName,
    writable,
  );
}

/// 遠端歌單的一個項目：曲目的顯示資料加上遠端項目 id 與失效旗標。
@immutable
final class RemoteEntry {
  const RemoteEntry({
    required this.track,
    this.remoteItemId,
    this.unavailable = false,
  });

  final TrackInfo track;
  final String? remoteItemId;
  final bool unavailable;
}
