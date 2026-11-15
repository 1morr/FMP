import 'package:fmp/platform/form_factor.dart';
import 'package:material_ui/material_ui.dart';

/// 間距的 4pt 格（`docs/design/DESIGN.md`〈間距〉），名稱照設計稿的
/// `--s1`…`--s14`（數字 × 4）。
abstract final class FmpSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s14 = 56;
}

/// 圓角（`docs/design/DESIGN.md`〈圓角〉）：控制是膠囊，容器與裝它的東西同心。
@immutable
class FmpRadii {
  const FmpRadii._({
    required this.coverCard,
    required this.group,
    required this.dialog,
    required this.menu,
    required this.field,
  });

  factory FmpRadii.of(Density density) => density == Density.touch
      ? const FmpRadii._(
          coverCard: 12,
          group: 16,
          dialog: 26,
          menu: 22,
          field: 12,
        )
      : const FmpRadii._(
          coverCard: 10,
          group: 12,
          dialog: 16,
          menu: 14,
          field: 8,
        );

  /// 按鈕、chip、toggle、dock 膠囊。
  final double capsule = 999;

  /// 列表縮圖。
  final double thumbnail = 6;
  final double coverCard;
  final double coverLarge = 14;

  /// 群組列表。
  final double group;
  final double dialog;

  /// 實心 sheet；浮動玻璃 sheet 是 [glassSheet]，離邊 [glassSheetInset]。
  final double sheet = 30;
  final double glassSheet = 34;
  final double glassSheetInset = 8;
  final double menu;

  /// 桌面視窗；側欄內縮 8 後是 [sidebar]（同心）。
  final double window = 16;
  final double sidebar = 12;

  /// 輸入欄位。
  final double field;
}

/// 跟密度走的尺寸：圓角、內容邊距、最小點擊目標、列表縮圖。
@immutable
class FmpMetrics extends ThemeExtension<FmpMetrics> {
  const FmpMetrics._({
    required this.radii,
    required this.pagePadding,
    required this.minTarget,
    required this.thumbnailSize,
  });

  factory FmpMetrics.of(Density density) {
    final touch = density == Density.touch;
    return FmpMetrics._(
      radii: FmpRadii.of(density),
      pagePadding: touch ? FmpSpace.s4 : FmpSpace.s8,
      minTarget: touch ? 44 : 28,
      thumbnailSize: touch ? 48 : 36,
    );
  }

  final FmpRadii radii;

  /// 內容的左右邊距：手機 16（設計稿 16–20，取下限），桌面 32。
  final double pagePadding;

  /// 最小點擊目標：觸控 44、滑鼠 28；視覺比它小的控制四周補透明點擊區。
  final double minTarget;

  /// 曲目列縮圖的邊長。
  final double thumbnailSize;

  /// token 只由 [FmpMetrics.of] 產生，不逐欄覆寫。
  @override
  FmpMetrics copyWith() => this;

  /// 密度在執行期不變，不做過場。
  @override
  FmpMetrics lerp(FmpMetrics? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
