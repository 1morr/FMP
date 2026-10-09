import 'dart:ui' show Color;

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

  /// 播放列上音量滑桿的寬度（expanded 以上在靜音鈕旁，medium 在彈出的選單裡）。
  static const double volumeSliderWidth = 112;

  /// 播放頁大封面的邊長上限（ADR 0024 §決定 4）。
  static const double playerArtworkMax = 420;

  /// 播放頁的毛玻璃（ADR 0024 §決定 1）：右欄、佇列、控制區是約 66% 的 `surface` 加
  /// 一般模糊。高對比時改不透明。
  static const double playerGlassOpacity = 0.66;
  static const double playerGlassBlur = 24;

  /// 播放頁背景的模糊封面：模糊半徑、遮罩不透明度，以及載入封面時的邊長（只當模糊
  /// 的底圖，不用大）。
  static const double playerBackdropBlur = 48;
  static const double playerScrimOpacity = 0.45;
  static const double playerBackdropSource = 256;

  /// 播放頁佇列分頁每一列的高度（固定高度讓一萬首的清單不必逐項量測）。
  static const double queueItemHeight = 64;

  /// 佇列切歌時捲到目前這首的動畫時間，與底部面板（compact、medium）一開始與最小的高度
  /// （占螢幕高度的比例）。
  static const Duration queueScrollDuration = Duration(milliseconds: 250);
  static const double queueSheetInitialSize = 0.6;
  static const double queueSheetMinSize = 0.3;

  /// 詳細分頁（與之後的右側面板）封面的邊長上限。
  static const double trackDetailsArtworkMax = 240;

  /// 右側「正在播放」面板（design §9.4）的寬度：預設（extraLarge 較寬）、下限，與上限占
  /// 視窗寬度的比例。上限低於下限時以下限為準。拖曳把手的可操作寬度與鍵盤一次調的量。
  static const double panelDefaultWidth = 412;
  static const double panelDefaultWidthExtraLarge = 480;
  static const double panelMinWidth = 320;
  static const double panelMaxFraction = 0.4;

  /// 面板寬度的絕對上限：等於 `layout_state.panel_width` 的 CHECK（資料庫只收 <= 1600）。
  /// 視窗超過 4000 時 40% 會超過它，不夾的話寫入會失敗。
  static const double panelMaxWidth = 1600;
  static const double panelHandleWidth = 8;
  static const double panelKeyboardStep = 16;

  /// 帳號頁的頭像（M3 list item 的 leading avatar）。
  static const double accountAvatar = 40;

  /// QR 登入畫面的 QR 碼邊長（舊版也是 200）。
  static const double qrCodeSize = 200;

  /// QR 碼一律白底黑點、不跟主題：深色主題下反色的 QR 碼不少掃描器讀不了。過期時蓋在
  /// QR 碼上的白色遮罩的不透明度。
  static const Color qrBackground = Color(0xFFFFFFFF);
  static const Color qrForeground = Color(0xFF000000);
  static const double qrExpiredScrimOpacity = 0.9;
}
