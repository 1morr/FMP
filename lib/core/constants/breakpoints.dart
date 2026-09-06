/// 視窗尺寸級距。
///
/// 值取自 Material 3 breakpoints 與 `androidx.window` 的 `WindowSizeClass`
/// （`WIDTH_DP_EXPANDED_LOWER_BOUND = 840`、`WIDTH_DP_EXTRA_LARGE_LOWER_BOUND
/// = 1600`）。FMP 以前只有 600 / 1200 兩刀，於是 840–1199 這個在桌面上非常
/// 常見的區間（1920 螢幕貼半邊 = 960dp）拿不到任何兩欄版面。
///
/// **這個型別回答的是「視窗骨架長什麼樣」**：底部導覽還是導覽軌、要不要給
/// Detail Panel。一個 pane 內部放幾欄是另一個問題，那是 [columnsFor] ——
/// 兩者不可以互相代用，混用正是 P0-1（拖寬面板讓首頁掉一個音源）的成因。
///
/// 舊的 `LayoutType { mobile, tablet, desktop }` 用硬體名稱回答尺寸問題，
/// 違反 Flutter 官方 adaptive design 指南的 *Avoid checking for hardware
/// types*；一個 600dp 的桌面視窗不是平板。
enum WindowClass {
  /// `< 600dp` —— 底部導覽，單欄。
  compact(0),

  /// `600–839dp` —— 導覽軌，單欄。
  medium(600),

  /// `840–1199dp` —— 導覽軌，可以開始給第二欄。
  expanded(840),

  /// `1200–1599dp` —— 可收合導覽軌 + fixed pane。
  large(1200),

  /// `>= 1600dp`。
  extraLarge(1600);

  const WindowClass(this.minWidth);

  /// 這一級的寬度下界（含）。
  final double minWidth;

  static WindowClass of(double width) {
    if (width >= extraLarge.minWidth) return extraLarge;
    if (width >= large.minWidth) return large;
    if (width >= expanded.minWidth) return expanded;
    if (width >= medium.minWidth) return medium;
    return compact;
  }

  /// 這一級是否不小於 [other]。級距是有序的，比較用宣告順序。
  bool atLeast(WindowClass other) => index >= other.index;
}

/// 一個容器裡放得下幾欄。
const double _idealColumnWidth = 400;

/// 欄數上限。超過三欄之後每一欄都太窄，內容比排版重要。
const int _maxColumns = 3;

/// [containerWidth] 這個**容器**放得下幾欄。
///
/// 與 [WindowClass] 是不同的問題：容器拿到的寬度已經扣掉導覽軌與 Detail
/// Panel，所以 1280dp 的視窗可能只給內容區 868dp。用視窗級的門檻去問容器級
/// 的問題，就會出現「開個面板首頁就少一個音源」。
///
/// 先 `clamp` 再 `floor`：容器寬度在無界約束下會是 `double.infinity`，
/// 對它 `floor()` 會拋 `UnsupportedError`，先夾住就自然落在上限。
int columnsFor(double containerWidth) =>
    (containerWidth / _idealColumnWidth).clamp(1, _maxColumns).floor();
