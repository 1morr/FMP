/// `player_state.mode` 存的模式（ADR 0018 §決定 10）：臨時播放與直播不持久化，所以
/// 只有這兩個。
///
/// 放在 `domain/`：字串寫死在資料層的轉換裡，不用 [name]。
enum PlayerMode {
  /// 播佇列裡的歌。
  queue,

  /// 佇列是一個 Mix（身分在 `mix_*` 欄位）。
  mix,
}
