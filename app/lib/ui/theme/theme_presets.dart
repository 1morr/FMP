import 'dart:ui' show Color;

import 'package:fmp/domain/appearance.dart';

/// 一個主題色 preset：[id] 是固定的識別字（翻譯 key 與測試用，不存進資料庫，
/// 資料庫存的是色值），[color] 抄自舊版 `lib/ui/theme/theme_preset_colors.dart`。
final class ThemePreset {
  const ThemePreset(this.id, this.color);

  final String id;
  final Color color;
}

/// 預設加舊版的 8 個 preset，依設定頁顯示的順序（第一個是預設）。
const themePresets = <ThemePreset>[
  ThemePreset('defaultPurple', appSeedColor),
  ThemePreset('indigo', Color(0xFF3F51B5)),
  ThemePreset('blue', Color(0xFF0061A4)),
  ThemePreset('teal', Color(0xFF006A6A)),
  ThemePreset('green', Color(0xFF006E1C)),
  ThemePreset('yellow', Color(0xFFF9A825)),
  ThemePreset('orange', Color(0xFF7C5800)),
  ThemePreset('red', Color(0xFFBA1A1A)),
  ThemePreset('pink', Color(0xFF984061)),
];

/// [color] 對到的 preset；自訂色為 `null`。只比 RGB：alpha 不影響 seed。
ThemePreset? themePresetOf(Color color) {
  for (final preset in themePresets) {
    if (preset.color.toARGB32() & 0xFFFFFF == color.toARGB32() & 0xFFFFFF) {
      return preset;
    }
  }
  return null;
}
