import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Tooltip;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/shortcut_modifier/shortcut_modifier.dart';
import 'package:fmp/ui/shell/playback_shortcuts.dart';
import 'package:fmp/ui/shell/shell_shortcuts.dart';
import 'package:fmp/ui/shell/shortcut_label.dart';

import '../support/shell_harness.dart';

// ADR 0035 §決定 7：提示文字裡的快捷鍵從表實際用的 `SingleActivator` 產生，Apple 平台
// 寫 ⌘ ⌥ ⇧ 符號，Windows、Android 寫 Ctrl+ 之類。Windows 的字串必須和改用佔位之前一模一樣。

typedef _Chord = SingleActivator Function(ShortcutModifier);

void main() {
  const control = ShortcutModifier.control;
  const meta = ShortcutModifier.meta;

  group('shortcutLabel', () {
    // 每個提示文字用到的鍵：(名稱, 組合鍵, Windows 寫法, Apple 寫法)。
    final chords = <(String, _Chord, String, String)>[
      ('search', searchChord, 'Ctrl+F', '⌘F'),
      ('settings', settingsChord, 'Ctrl+,', '⌘,'),
      ('queue', queueChord, 'Ctrl+Q', '⌥⌘U'),
      ('select all', selectAllChord, 'Ctrl+A', '⌘A'),
      ('previous', previousChord, 'Ctrl+←', '⌘←'),
      ('next', nextChord, 'Ctrl+→', '⌘→'),
      ('volume up', volumeUpChord, 'Ctrl+↑', '⌘↑'),
      ('volume down', volumeDownChord, 'Ctrl+↓', '⌘↓'),
      ('shuffle', shuffleChord, 'Ctrl+S', '⌘S'),
      ('loop', loopChord, 'Ctrl+R', '⌘R'),
    ];
    for (final (name, chord, windows, apple) in chords) {
      test(name, () {
        expect(shortcutLabel(chord(control), control), windows);
        expect(shortcutLabel(chord(meta), meta), apple);
      });
    }

    test('shift-only chords follow the platform style, not the meta flag', () {
      const seek = SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true);
      expect(shortcutLabel(seek, control), 'Shift+←');
      expect(shortcutLabel(seek, meta), '⇧←');
    });

    test('Apple modifiers come in the order ⌃⌥⇧⌘', () {
      const all = SingleActivator(
        LogicalKeyboardKey.keyU,
        control: true,
        alt: true,
        shift: true,
        meta: true,
      );
      expect(shortcutLabel(all, meta), '⌃⌥⇧⌘U');
    });

    test('the volume tooltip keeps the last key bare', () {
      expect(shortcutKeyLabel(LogicalKeyboardKey.arrowDown), '↓');
    });
  });

  // 導覽提示只在窄版的底部導覽列（compact）；播放鍵在寬版的播放列；音量圖示在中寬度。
  // Windows 的字串必須和改用佔位之前一模一樣。
  final cases = <(String, ShortcutModifier, Size, List<String>)>[
    for (final (
          name,
          modifier,
          search,
          queue,
          settings,
          previous,
          next,
          shuffle,
          loop,
          volume,
        )
        in [
          (
            'Ctrl',
            control,
            'Ctrl+F',
            'Ctrl+Q',
            'Ctrl+,',
            'Ctrl+←',
            'Ctrl+→',
            'Ctrl+S',
            'Ctrl+R',
            'Ctrl+↑/↓',
          ),
          ('⌘', meta, '⌘F', '⌥⌘U', '⌘,', '⌘←', '⌘→', '⌘S', '⌘R', '⌘↑/↓'),
        ]) ...[
      (
        name,
        modifier,
        const Size(400, 800),
        ['Search ($search)', 'Queue ($queue)', 'Settings ($settings)'],
      ),
      (
        name,
        modifier,
        const Size(1000, 700),
        [
          'Previous ($previous)',
          'Next ($next)',
          'Shuffle ($shuffle)',
          'Repeat: off ($loop)',
        ],
      ),
      (name, modifier, const Size(720, 700), ['Volume ($volume)']),
    ],
  ];

  group('tooltips follow the platform modifier', () {
    for (final (name, modifier, size, expected) in cases) {
      testWidgets('$name at ${size.width.toInt()}: $expected', (tester) async {
        final h = ShellHarness(shortcutModifier: modifier);
        await h.pumpShell(tester, size: size);
        await h.play(tester, [summary('a')]);
        for (final tooltip in expected) {
          // 底部導覽列的提示是 material_ui 的 Tooltip，`byTooltip` 只認 Flutter 自己的。
          final found =
              find.byTooltip(tooltip).evaluate().isNotEmpty ||
              find
                  .byWidgetPredicate(
                    (w) => w is Tooltip && w.message == tooltip,
                  )
                  .evaluate()
                  .isNotEmpty;
          expect(found, isTrue, reason: tooltip);
        }
      });
    }
  });
}
