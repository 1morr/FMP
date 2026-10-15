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
