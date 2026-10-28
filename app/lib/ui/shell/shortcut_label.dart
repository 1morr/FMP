import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:fmp/platform/shortcut_modifier/shortcut_modifier.dart';

// 提示文字裡的快捷鍵寫法（ADR 0035 §決定 7）。標籤從快捷鍵表實際用的 `SingleActivator`
// 產生，所以提示不會和綁定不一致；翻譯檔只放 `{shortcut}` 佔位。

/// [activator] 的顯示寫法。
///
/// 寫法跟平台宣告的主修飾鍵 [modifier] 走，而不是看 [activator] 有沒有 ⌘：只有 Shift 的
/// 組合鍵（seek 的 Shift+←）在 Apple 平台也要寫成 `⇧←`。
/// - [ShortcutModifier.meta]（Apple）：修飾鍵符號依 Apple 的順序 ⌃⌥⇧⌘，後接按鍵，
///   沒有分隔：`⌘F`、`⌥⌘U`、`⇧←`。
/// - [ShortcutModifier.control]：`Ctrl+`、`Alt+`、`Shift+` 前綴以 `+` 連接：`Ctrl+F`、
///   `Shift+←`。
String shortcutLabel(SingleActivator activator, ShortcutModifier modifier) {
  final key = shortcutKeyLabel(activator.trigger);
  switch (modifier) {
    case ShortcutModifier.meta:
      return '${activator.control ? '⌃' : ''}'
          '${activator.alt ? '⌥' : ''}'
          '${activator.shift ? '⇧' : ''}'
          '${activator.meta ? '⌘' : ''}'
          '$key';
    case ShortcutModifier.control:
      assert(!activator.meta, 'no ⌘ chords on the control platforms');
      return [
        if (activator.control) 'Ctrl',
        if (activator.alt) 'Alt',
        if (activator.shift) 'Shift',
        key,
      ].join('+');
  }
}

/// 只有按鍵的部分（音量提示的「↑／↓」用）。
String shortcutKeyLabel(LogicalKeyboardKey key) {
  final glyph = switch (key) {
    LogicalKeyboardKey.arrowLeft => '←',
    LogicalKeyboardKey.arrowRight => '→',
    LogicalKeyboardKey.arrowUp => '↑',
    LogicalKeyboardKey.arrowDown => '↓',
    _ => key.keyLabel.toUpperCase(),
  };
  assert(
    glyph.isNotEmpty,
    'no label for ${key.debugName}; add it to shortcutKeyLabel',
  );
  return glyph;
}
