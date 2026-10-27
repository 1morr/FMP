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

  /// 首頁橫向一排兩端的漸層寬度與捲動箭頭（桌面滑鼠移入時出現）的鈕寬。
  static const double shelfEdgeFade = 56;

  /// 電台頁網格（expanded 以上）：一格的最大寬度、高度（字級 1.0 時；封面以外的部分跟著字級放大）
  /// 與圓形封面的邊長。高度放得下封面、標題、狀態標記與主播各一行。
  static const double radioCellMaxWidth = 200;
  static const double radioCellHeight = 224;
  static const double radioCover = 128;

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

  /// 播放列頂端的進度細線（ADR 0035 §決定 4）：平時 2dp，滑鼠移入播放列或拖曳時 6dp 並出現把手；
  /// 可點可拖的範圍是頂端 [thinProgressHit]（細線太細，觸控點不到）。它等於播放列上方的留白
  /// （`spacing.x2`）：再高就蓋到下面控制項的點擊區，點按鈕的上緣會變成 seek。
  static const double thinProgressHeight = 2;
  static const double thinProgressHoverHeight = 6;
  static const double thinProgressThumb = 12;
  static const double thinProgressHit = 8;
  static const Duration thinProgressDuration = Duration(milliseconds: 120);

  /// 右側面板「下一首」的縮圖邊長與標題旁的圖示。
  static const double nextUpArtwork = 56;
  static const double nextUpIcon = 18;

  /// 播放列上音量滑桿的寬度（expanded 以上在靜音鈕旁，medium 在彈出的選單裡）。
  static const double volumeSliderWidth = 112;

  /// 播放頁大封面的邊長上限（ADR 0024 §決定 4）。
  static const double playerArtworkMax = 420;

  /// 播放頁的版面門檻（舊版 `resolvePlayerLayout`）：寬 >= [playerWideMinWidth] 且高 >=
  /// [playerWideMinHeight] 是寬版；寬大於高而高 < [playerWideMinHeight]（橫向手機）是矮版。
  static const double playerWideMinWidth = 840;
  static const double playerWideMinHeight = 520;

  /// 寬版沒有歌詞時單欄的內容寬度上限（ADR 0035 §決定 3）。
  static const double playerContentMaxWide = 720;

  /// 播放頁的大播放鍵（外框與圖示）、上一首與下一首的圖示（舊版 `UIConstants`）。
  static const double playerPlayButton = 80;
  static const double playerPlayIcon = 40;
  static const double playerSkipIcon = 40;

  /// 五個控制（隨機、上一首、播放、下一首、循環）的自然寬度；放控制的地方比它窄時整排縮小。
  static const double playerControlsMinWidth = 288;

  /// 播放頁封面的陰影（舊版 `CoverArtContainer`）：模糊、下移與影色不透明度。
  static const double playerCoverShadowBlur = 20;
  static const double playerCoverShadowOffset = 10;
  static const double playerCoverShadowOpacity = 0.2;

  /// 寬版播放頁右側滑入的曲目詳細面板寬度；窄版底部面板的初始、最小與最大高度比例。
  static const double playerDetailsPanelWidth = 400;
  static const double playerDetailsSheetInitial = 0.6;
  static const double playerDetailsSheetMin = 0.3;
  static const double playerDetailsSheetMax = 0.95;

  /// 播放頁開關的轉場長度（舊版 `router.dart`）。
  static const Duration playerTransition = Duration(milliseconds: 300);

  /// 播放頁背景的模糊封面：模糊半徑、遮罩不透明度，以及載入封面時的邊長（只當模糊
  /// 的底圖，不用大）。控制區沒有底板（ADR 0035 §決定 3），文字直接在遮罩上：深色主題配最淺的封面
  /// 時 0.45 的遮罩對比只有 1.8，0.75 才過 guideline 測試（`the player page over …`）。
  static const double playerBackdropBlur = 48;
  static const double playerScrimOpacity = 0.75;
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

  /// 曲目列尾端的時長欄（固定寬度，右對齊）與音源徽章。
  static const double trackDurationColumn = 56;
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

  /// Windows 自繪標題列（ADR 0035 §決定 6，舊版 `CustomTitleBar`）：高度、三顆視窗鈕的寬度與圖示尺寸。
  static const double titleBarHeight = 36;
  static const double titleBarButtonWidth = 46;
  static const double titleBarIcon = 16;

  /// 播放頁頂列後面的視窗拖曳區高度（頂列：48dp 鈕加上下各 8dp 的邊距）。
  static const double playerDragAreaHeight = 64;

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
