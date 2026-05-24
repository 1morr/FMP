import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/hotkey_config.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

void main() {
  group('HotkeyConfig', () {
    test('fromJsonString clears configured system hotkeys without modifiers',
        () {
      final config = HotkeyConfig.fromJsonString(jsonEncode({
        'bindings': [
          {
            'action': HotkeyAction.playPause.name,
            'keyId': LogicalKeyboardKey.keyA.keyId,
            'modifiers': <String>[],
          },
        ],
      }));

      final binding = config.getBinding(HotkeyAction.playPause)!;
      expect(binding.isConfigured, isFalse);
      expect(binding.toHotKey(), isNull);
    });

    test('fromJsonString keeps configured system hotkeys with modifiers', () {
      final config = HotkeyConfig.fromJsonString(jsonEncode({
        'bindings': [
          {
            'action': HotkeyAction.next.name,
            'keyId': LogicalKeyboardKey.arrowRight.keyId,
            'modifiers': ['control'],
          },
        ],
      }));

      final binding = config.getBinding(HotkeyAction.next)!;
      expect(binding.key, LogicalKeyboardKey.arrowRight);
      expect(binding.modifiers, {HotKeyModifier.control});
      expect(binding.toHotKey(), isNotNull);
    });

    test('updateBinding clears invalid modifierless binding', () {
      final config = HotkeyConfig.defaults().updateBinding(
        const HotkeyBinding(
          action: HotkeyAction.stop,
          key: LogicalKeyboardKey.space,
          modifiers: {},
        ),
      );

      expect(config.getBinding(HotkeyAction.stop)!.isConfigured, isFalse);
    });
  });
}
