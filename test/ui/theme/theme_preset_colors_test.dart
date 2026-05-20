import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/theme/theme_preset_colors.dart';

void main() {
  test('null theme color resolves to the default preset', () {
    final preset = themePresetColorFor(null);

    expect(preset?.id, 'defaultPurple');
    expect(preset?.storesAsDefault, isTrue);
  });

  test('known preset colors resolve to stable ids', () {
    final preset = themePresetColorFor(const Color(0xFF0061A4));

    expect(preset?.id, 'blue');
    expect(preset?.storesAsDefault, isFalse);
  });

  test('palette-picked colors that are not presets stay custom', () {
    final preset = themePresetColorFor(const Color(0xFF123456));

    expect(preset, isNull);
  });

  test('preset colors plus custom entry fill complete picker rows', () {
    const customEntryCount = 1;

    expect((themePresetColors.length + customEntryCount) % 4, 0);
  });
}
