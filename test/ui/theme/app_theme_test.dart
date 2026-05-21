import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/theme/app_theme.dart';

void main() {
  test('light theme uses the selected custom primary color directly', () {
    const selectedColor = Color(0xFF330000);

    final theme = AppTheme.lightTheme(primaryColor: selectedColor);

    expect(theme.colorScheme.primary.toARGB32(), selectedColor.toARGB32());
  });

  test('light theme keeps generated inverse primary for contrast', () {
    const selectedColor = Color(0xFF330000);

    final theme = AppTheme.lightTheme(primaryColor: selectedColor);

    expect(theme.colorScheme.primary.toARGB32(), selectedColor.toARGB32());
    expect(
      theme.colorScheme.inversePrimary.toARGB32(),
      isNot(selectedColor.toARGB32()),
    );
  });

  test('light theme chooses readable foreground for mid-light custom primary',
      () {
    const selectedColor = Color(0xFFAAAAAA);

    final theme = AppTheme.lightTheme(primaryColor: selectedColor);

    expect(theme.colorScheme.onPrimary, Colors.black);
  });

  test('dark theme uses the selected custom primary color directly', () {
    const selectedColor = Color(0xFFFFCCCC);

    final theme = AppTheme.darkTheme(primaryColor: selectedColor);

    expect(theme.colorScheme.primary.toARGB32(), selectedColor.toARGB32());
  });
}
