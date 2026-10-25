import 'dart:ui' show Color;

/// 元件的固定尺寸（ADR 0024 §決定 1）。和 `AppTokens` 的間距不同，這些是某個
/// 元件自己的上限或寬度，隨元件出現時加。
abstract final class AppLayout {
  /// 桌面上提示（Toast）的最大寬度（ADR 0023 §決定 2）。
  static const double toastMaxWidth = 560;

  /// 錯誤詳細頁內容的最大寬度（寬螢幕上不拉成一整行，stack trace 才好讀）。
  static const double errorDetailMaxWidth = 720;

  /// 列表與播放列上的小封面（M3 list item 的 leading 圖片尺寸）。
  static const double artworkThumbnail = 48;

  /// 首頁區塊裡橫向一排的卡片（封面）邊長。
  static const double shelfCardWidth = 144;

  /// 首頁排行區塊一欄（一個榜單的前幾首）的最小寬度：內容區放得下幾欄就並排幾欄。
  static const double chartColumnMinWidth = 360;

  /// 排行曲目列的名次欄寬（放得下三位數）。
  static const double chartRankWidth = 32;

  /// 音樂庫格狀版面（expanded 以上）一張歌單卡的最大寬度。
  static const double playlistCardMaxWidth = 200;

  /// 格狀清單拖曳排序時：被拖的卡在原位置的不透明度，與拖著走的那張的陰影高度（同
  /// `ReorderableListView` 預設的 6）。
  static const double draggedOpacity = 0.3;
  static const double dragElevation = 6;

  /// 歌單對話框裡封面預覽的邊長。
  static const double playlistCoverPreview = 64;

  /// 歌單詳情頁標頭的封面邊長（400 寬的視窗裡旁邊還放得下描述）。
  static const double playlistHeaderCover = 144;

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

  /// 佇列頁每一列的高度（固定高度讓一萬首的清單不必逐項量測）。
  static const double queueItemHeight = 72;

  /// Mix 佇列列尾（續取轉圈）的高度，與轉圈的邊長。
  static const double queueFooterHeight = 48;
  static const double queueFooterSpinner = 20;

  /// 佇列頁離頂端不到這麼遠算在頂端（跳頂／跳底鈕的方向）。
  static const double queueNearTop = 200;

  /// 「正在播放第 n 首」橫幅底色（primaryContainer）的不透明度。
  static const double queueBanner = 0.3;

  /// 橫幅可以點，高度至少一個點擊區。
  static const double queueBannerHeight = 48;

  /// 正在播放的封面遮罩：主色的不透明度、指示器對封面邊長的比例與一個循環的時間。
  static const double nowPlayingScrim = 0.8;
  static const double nowPlayingIndicatorRatio = 0.32;
  static const Duration nowPlayingLoop = Duration(milliseconds: 1200);

  /// 歷史頁的時間軸（舊版）：左欄寬度、貫穿的線寬與日期標頭的圓點，以及日期標頭的高度。
  static const double timelineColumn = 40;
  static const double timelineLine = 2;
  static const double timelineDot = 12;
  static const double timelineHeaderHeight = 48;

  /// 歷史列尾端的時長欄（固定寬度，右對齊）與音源徽章。
  static const double historyDurationColumn = 56;
  static const double sourceBadge = 20;

  /// 佇列切歌時捲到目前這首的動畫時間。
  static const Duration queueScrollDuration = Duration(milliseconds: 250);

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

  /// 左側導覽側欄（ADR 0035 §決定 2，舊版 `AppLayout.railCollapsed／railExpanded`）：收合與展開的寬度，
  /// 展開、收合的動畫時間。
  static const double railCollapsed = 72;
  static const double railExpanded = 256;
  static const Duration railDuration = Duration(milliseconds: 250);

  /// 展開的側欄裡相鄰兩項的間隔（舊版每項上下各 2dp）。
  static const double railItemGap = 4;

  /// 搜尋結果列取分 P 時取代展開鈕的轉圈尺寸（鈕本身是 [kMinInteractiveDimension]）。
  static const double partsSpinner = 20;

  /// 按鈕內的小轉圈（歌單詳情的「刷新」進行中）。
  static const double buttonSpinner = 18;

  /// 帳號頁的頭像（M3 list item 的 leading avatar）。
  static const double accountAvatar = 40;

  /// QR 登入畫面的 QR 碼邊長（舊版也是 200）。
  static const double qrCodeSize = 200;

  /// QR 碼一律白底黑點、不跟主題：深色主題下反色的 QR 碼不少掃描器讀不了。過期時蓋在
  /// QR 碼上的白色遮罩的不透明度。
  static const Color qrBackground = Color(0xFFFFFFFF);
  static const Color qrForeground = Color(0xFF000000);
  static const double qrExpiredScrimOpacity = 0.9;

  /// Debug 頁 Log、網路區塊工具列上篩選控制項（搜尋框、下拉）的寬度。
  static const double debugFilterWidth = 200;

  /// Debug 頁資料庫表格一格的最大寬度。
  static const double debugCellWidth = 240;

  /// 外觀設定的主題色色塊（圓形）直徑與一格的寬度（含底下的名稱，點擊區夠 48dp）。
  static const double themeSwatch = 40;
  static const double themeSwatchCell = 72;

  /// 自訂主題色對話框的色彩預覽圓直徑。
  static const double colorPreview = 48;
}
