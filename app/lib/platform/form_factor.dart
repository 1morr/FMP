import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 視窗的寬度分級（`docs/design/DESIGN.md`〈中寬度〉）：外殼與各頁的版面
/// 依它切換。邊界看視窗寬度，不看裝置。
enum WidthClass {
  /// < 600：手機。
  narrow,

  /// 600–1199：平板、縮小的桌面視窗。
  medium,

  /// ≥ 1200：桌面、13 吋 iPad 橫向。
  wide;

  static const mediumFrom = 600.0;
  static const wideFrom = 1200.0;

  static WidthClass of(double width) => width < mediumFrom
      ? narrow
      : width < wideFrom
      ? medium
      : wide;
}

/// 密度跟裝置走、不跟寬度（`docs/design/DESIGN.md`〈中寬度〉）：手機與平板是
/// 觸控（手機欄的字級、44pt 目標），桌面是滑鼠（桌面欄的字級、28pt 目標）。
enum Density {
  touch,
  pointer;

  static Density of(TargetPlatform platform) => switch (platform) {
    TargetPlatform.iOS ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => touch,
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => pointer,
  };

  /// 這個 App 跑在的平台的密度。
  static Density get current => of(defaultTargetPlatform);
}

/// 畫面拿寬度分級與密度的地方；畫面不自己判斷平台（architecture〈依賴規則〉）。
@immutable
class FormFactor {
  const FormFactor(this.widthClass, this.density);

  /// 依 [context] 的視窗寬度與目前平台；視窗寬度改變時重建。
  factory FormFactor.of(BuildContext context) => FormFactor(
    WidthClass.of(MediaQuery.sizeOf(context).width),
    Density.current,
  );

  final WidthClass widthClass;
  final Density density;

  @override
  bool operator ==(Object other) =>
      other is FormFactor &&
      other.widthClass == widthClass &&
      other.density == density;

  @override
  int get hashCode => Object.hash(widthClass, density);

  @override
  String toString() => 'FormFactor(${widthClass.name}, ${density.name})';
}
