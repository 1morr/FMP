import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/theme/app_theme.dart';

void main() {
  test('light theme uses the selected custom primary color directly', () {
    const selectedColor = Color(0xFF330000);

    final theme = AppTheme.lightTheme(primaryColor: selectedColor);

    expect(theme.colorScheme.primary.toARGB32(), selectedColor.toARGB32());
  });

  test('dark theme uses the selected custom primary color directly', () {
    const selectedColor = Color(0xFFFFCCCC);

    final theme = AppTheme.darkTheme(primaryColor: selectedColor);

    expect(theme.colorScheme.primary.toARGB32(), selectedColor.toARGB32());
  });
}
