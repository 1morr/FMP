/// 元件的固定尺寸（ADR 0024 §決定 1）。和 `AppTokens` 的間距不同，這些是某個
/// 元件自己的上限或寬度，隨元件出現時加。
abstract final class AppLayout {
  /// 桌面上提示（Toast）的最大寬度（ADR 0023 §決定 2）。
  static const double toastMaxWidth = 560;
}
