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

  test('theme color picker exposes two full rows of preset choices', () {
    final ids = themePresetColors.map((preset) => preset.id).toList();

    expect(ids, [
      'defaultPurple',
      'indigo',
      'blue',
      'teal',
      'green',
      'yellow',
      'orange',
      'red',
      'pink',
    ]);
  });

  test('palette-picked colors that are not presets stay custom', () {
    final preset = themePresetColorFor(const Color(0xFF123456));

    expect(preset, isNull);
  });

  test('preset colors plus custom entry fill complete five-column picker rows',
      () {
    const customEntryCount = 1;
    const pickerColumnCount = 5;

    expect(themePresetColors.length, 9);
    expect(
      (themePresetColors.length + customEntryCount) % pickerColumnCount,
      0,
    );
  });
}
