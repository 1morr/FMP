import 'package:flutter/material.dart';

class ThemePresetColor {
  final String id;
  final Color color;
  final bool storesAsDefault;

  const ThemePresetColor({
    required this.id,
    required this.color,
    this.storesAsDefault = false,
  });
}

const defaultThemePrimaryColor = Color(0xFF6750A4);

const themePresetColors = <ThemePresetColor>[
  ThemePresetColor(
    id: 'defaultPurple',
    color: defaultThemePrimaryColor,
    storesAsDefault: true,
  ),
  ThemePresetColor(id: 'indigo', color: Color(0xFF3F51B5)),
  ThemePresetColor(id: 'blue', color: Color(0xFF0061A4)),
  ThemePresetColor(id: 'teal', color: Color(0xFF006A6A)),
  ThemePresetColor(id: 'green', color: Color(0xFF006E1C)),
  ThemePresetColor(id: 'yellow', color: Color(0xFFF9A825)),
  ThemePresetColor(id: 'orange', color: Color(0xFF7C5800)),
  ThemePresetColor(id: 'red', color: Color(0xFFBA1A1A)),
  ThemePresetColor(id: 'pink', color: Color(0xFF984061)),
];

ThemePresetColor? themePresetColorFor(Color? color) {
  if (color == null) {
    return themePresetColors.firstWhere((preset) => preset.storesAsDefault);
  }

  final colorValue = color.toARGB32();
  for (final preset in themePresetColors) {
    if (preset.color.toARGB32() == colorValue) {
      return preset;
    }
  }
  return null;
}
