import 'dart:math' as math;

/// 版面尺寸 token。
///
/// 這些值以前是散在 `responsive_scaffold.dart` 與 `player_page.dart` 裡的字面值。
/// 集中的理由不是「以後可能要換」，而是**同一個數字現在有兩個以上的消費者**：
/// 面板寬度的界限同時被拖曳邏輯與資料庫不變式讀取，rail 寬度被三個版面讀取。
class AppLayout {
  AppLayout._();

  /// 收起的導覽軌寬度（平板與桌面收起態共用）
  static const double railCollapsed = 72.0;

  /// 展開的導覽軌寬度
  static const double railExpanded = 256.0;

  /// Detail Panel 的像素下限。低於這個寬度面板裡的封面與資訊列會擠在一起。
  static const double detailPanelMin = 320.0;

  /// Detail Panel 的預設寬度。M3 fixed pane 的建議值。
  static const double detailPanelDefault = 412.0;

  /// Detail Panel 的比例上限。
  ///
  /// 取代原本的絕對值 500dp —— 絕對上限的方向和需求相反：1200dp 視窗上 500dp
  /// 吃掉 41.7% 的主內容，3440dp 上卻只剩 14.5%，螢幕越大面板越像一條細邊。
  /// 840（`WindowClass.expanded` 的下界）× 0.4 = 336 ≥ [detailPanelMin]，
  /// 所以模型在下界剛好自洽。
  static const double detailPanelMaxFraction = 0.4;

  /// 存進資料庫的面板寬度上限。
  ///
  /// 真正的上限是視窗寬的 [detailPanelMaxFraction]，而資料庫層看不到視窗，
  /// 所以這個值只用來擋掉手改資料庫或壞掉的備份帶進來的垃圾值。
  static const double detailPanelStoredMax = 1600.0;

  /// 兩個 pane 之間的間隔。M3 規定 large / extra-large 版面是 24dp，
  /// 且「pane 可以調整大小時 spacer 內要放一個 drag handle」。
  static const double paneSpacer = 24.0;

  /// 收起的 Detail Panel 條寬度
  static const double collapsedStrip = 36.0;

  /// 收起的 Detail Panel 條在滑鼠停留時的寬度
  static const double collapsedStripHovered = 54.0;

  /// 播放頁封面的寬度上限。
  ///
  /// 寬版一直有這個上限，窄版沒有 —— 於是 800dp 的直向平板上封面撐到 752dp。
  static const double playerCoverMax = 420.0;

  /// 播放頁切到雙欄所需的最小高度。
  ///
  /// 只看寬度會讓橫向手機（寬但矮）拿到雙欄版面。抄 Auxio 的 `layout-h520dp`。
  static const double playerWideMinHeight = 520.0;

  /// [windowWidth] 這個視窗上面板的寬度上限。
  ///
  /// 視窗窄到連 [detailPanelMin] 都放不下時下限優先 —— 面板寧可超出比例也不能
  /// 擠成看不了。**拖曳與渲染必須共用這一個上限**，否則拖得動的寬度渲染不出來。
  static double detailPanelMaxFor(double windowWidth) =>
      math.max(detailPanelMin, windowWidth * detailPanelMaxFraction);

  /// 存下來的面板寬度在 [windowWidth] 這個視窗上實際該用多寬。
  ///
  /// 存下來的值只有相對於視窗才有意義，所以比例上限在渲染期算，不在資料庫算。
  static double detailPanelWidthFor(double stored, double windowWidth) {
    final upper = detailPanelMaxFor(windowWidth);
    if (!stored.isFinite) return detailPanelDefault.clamp(detailPanelMin, upper);
    return stored.clamp(detailPanelMin, upper);
  }
}
