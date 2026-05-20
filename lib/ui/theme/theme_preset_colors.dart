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
  ThemePresetColor(id: 'blue', color: Color(0xFF0061A4)),
  ThemePresetColor(id: 'green', color: Color(0xFF006E1C)),
  ThemePresetColor(id: 'red', color: Color(0xFFBA1A1A)),
  ThemePresetColor(id: 'pink', color: Color(0xFF984061)),
  ThemePresetColor(id: 'orange', color: Color(0xFF7C5800)),
  ThemePresetColor(id: 'teal', color: Color(0xFF006A6A)),
  ThemePresetColor(id: 'indigo', color: Color(0xFF4758A9)),
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
