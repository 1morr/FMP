/// 元件的固定尺寸（ADR 0024 §決定 1）。和 `AppTokens` 的間距不同，這些是某個
/// 元件自己的上限或寬度，隨元件出現時加。
abstract final class AppLayout {
  /// 桌面上提示（Toast）的最大寬度（ADR 0023 §決定 2）。
  static const double toastMaxWidth = 560;

  /// 列表與播放列上的小封面（M3 list item 的 leading 圖片尺寸）。
  static const double artworkThumbnail = 48;

  /// 空狀態畫面的圖示。
  static const double emptyStateIcon = 48;

  /// 設定頁 list-detail 版面（expanded 以上）左側分組清單的寬度。
  static const double settingsListWidth = 280;

  /// 播放列上時間文字的最小寬度：位置在播放中變長變短時，進度條不跟著左右跳。
  static const double playerTimeLabel = 48;
}
