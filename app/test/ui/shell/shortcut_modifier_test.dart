import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/platform/shortcut_modifier/shortcut_modifier.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/shell/playback_shortcuts.dart';
import 'package:fmp/ui/shell/shell_shortcuts.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// U PR 15（ADR 0035 §決定 7）：快捷鍵的主修飾鍵來自平台宣告。Apple 平台的 Ctrl 換成 ⌘，開佇列是
// ⌥⌘U；平台層的假宣告跑兩組。

/// 表裡每個帶修飾鍵的 `SingleActivator`。
Iterable<SingleActivator> _chords(Map<ShortcutActivator, Intent> table) =>
    table.keys.whereType<SingleActivator>();

void main() {
  group('the tables', () {
    final tables = {
      for (final modifier in ShortcutModifier.values)
        modifier: {
          ...navigationShortcuts(modifier),
          ...playbackShortcuts(modifier),
        },
    };

    test('with Ctrl no key uses the meta key', () {
      for (final chord in _chords(tables[ShortcutModifier.control]!)) {
        expect(chord.meta, isFalse, reason: '$chord');
      }
    });

    test('with ⌘ no key uses Ctrl, and every Ctrl key of the Windows table '
        'has its ⌘ twin', () {
      final control = tables[ShortcutModifier.control]!;
      final meta = tables[ShortcutModifier.meta]!;
      for (final chord in _chords(meta)) {
        expect(chord.control, isFalse, reason: '$chord');
      }
      // 同樣多個鍵，同樣的 Intent；只有修飾鍵不同。
      expect(
        meta.values.map((intent) => intent.runtimeType).toSet(),
        control.values.map((intent) => intent.runtimeType).toSet(),
      );
      for (final chord in _chords(control)) {
        if (chord.control && chord.trigger != LogicalKeyboardKey.keyQ) {
          expect(
            _chords(meta)
                .any((m) => m.trigger == chord.trigger && m.meta && !m.alt),
            isTrue,
            reason: 'no ⌘ twin for $chord',
          );
        }
      }
    });

    test('opening the queue is Ctrl+Q, or ⌥⌘U on Apple platforms', () {
      final control = queueChord(ShortcutModifier.control);
      expect(control.trigger, LogicalKeyboardKey.keyQ);
      expect(
        [control.control, control.meta, control.alt],
        [true, false, false],
      );

      final meta = queueChord(ShortcutModifier.meta);
      expect(meta.trigger, LogicalKeyboardKey.keyU);
      expect([meta.control, meta.meta, meta.alt], [false, true, true]);
    });

    test('⌘Q is never a shortcut (it quits the app)', () {
      for (final chord in _chords(tables[ShortcutModifier.meta]!)) {
        expect(chord.trigger == LogicalKeyboardKey.keyQ && chord.meta, isFalse);
      }
    });

    test('Ctrl+L / ⌘L are not shortcuts before the lyrics exist', () {
      for (final table in tables.values) {
        for (final chord in _chords(table)) {
          expect(chord.trigger, isNot(LogicalKeyboardKey.keyL));
        }
      }
    });
  });

  group('with the Ctrl modifier', () {
    testWidgets('Ctrl+F focuses the search field, ⌘F does not', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);

      await _chord(
        tester,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.metaLeft,
      );
      expect(find.byType(SearchPage).hitTestable(), findsNothing);

      await _chord(
        tester,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.controlLeft,
      );
      expect(find.byType(SearchPage).hitTestable(), findsOneWidget);
    });
  });

  group('with the ⌘ modifier', () {
    final control = LogicalKeyboardKey.controlLeft;
    final meta = LogicalKeyboardKey.metaLeft;

    testWidgets('⌘F focuses the search field, Ctrl+F does not', (tester) async {
      final h = ShellHarness(shortcutModifier: ShortcutModifier.meta);
      await h.pumpShell(tester, at: ShellDestination.home);

      await _chord(tester, LogicalKeyboardKey.keyF, control);
      expect(find.byType(SearchPage).hitTestable(), findsNothing);

      await _chord(tester, LogicalKeyboardKey.keyF, meta);
      expect(find.byType(SearchPage).hitTestable(), findsOneWidget);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasPrimaryFocus, isTrue);
    });

    testWidgets('⌘, opens the settings', (tester) async {
      final h = ShellHarness(shortcutModifier: ShortcutModifier.meta);
      await h.pumpShell(tester, at: ShellDestination.home);

      await _chord(tester, LogicalKeyboardKey.comma, control);
      expect(find.byType(SettingsPage).hitTestable(), findsNothing);

      await _chord(tester, LogicalKeyboardKey.comma, meta);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage).hitTestable(), findsOneWidget);
    });

    testWidgets('⌥⌘U selects the queue; ⌘Q and Ctrl+Q do nothing', (
      tester,
    ) async {
      final h = ShellHarness(shortcutModifier: ShortcutModifier.meta);
      await h.pumpShell(tester, at: ShellDestination.home);

      await _chord(tester, LogicalKeyboardKey.keyQ, meta);
      await _chord(tester, LogicalKeyboardKey.keyQ, control);
      expect(find.byType(QueuePage).hitTestable(), findsNothing);

      await tester.sendKeyDownEvent(meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(meta);
      await tester.pumpAndSettle();

      expect(find.byType(QueuePage).hitTestable(), findsOneWidget);
    });

    testWidgets('⌥⌘U works while typing in the search field', (tester) async {
      final h = ShellHarness(shortcutModifier: ShortcutModifier.meta);
      await h.pumpShell(tester);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'lofi');
      await tester.pump();

      await tester.sendKeyDownEvent(meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(meta);
      await tester.pumpAndSettle();

      expect(find.byType(QueuePage).hitTestable(), findsOneWidget);
    });

    testWidgets('⌘S, ⌘R and ⌘→ drive playback, Ctrl+S does not', (
      tester,
    ) async {
      final h = ShellHarness(shortcutModifier: ShortcutModifier.meta);
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.play(tester, [summary('a'), summary('b'), summary('c')]);
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.controller.state, isA<Playing>());

      await _chord(tester, LogicalKeyboardKey.keyS, control);
      expect(h.controller.queue.shuffleEnabled, isFalse);
      await _chord(tester, LogicalKeyboardKey.keyS, meta);
      expect(h.controller.queue.shuffleEnabled, isTrue);

      await _chord(tester, LogicalKeyboardKey.keyR, meta);
      expect(h.controller.queue.loopMode, LoopMode.all);

      final before = h.controller.queue.currentIndex;
      await _chord(tester, LogicalKeyboardKey.arrowRight, meta);
      await tester.pump();
      expect(h.controller.queue.currentIndex, isNot(before));
    });

    testWidgets('⌘L does nothing', (tester) async {
      final h = ShellHarness(shortcutModifier: ShortcutModifier.meta);
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.play(tester, [summary('a'), summary('b')]);

      await _chord(tester, LogicalKeyboardKey.keyL, meta);
      await tester.pumpAndSettle();

      expect(find.byType(SearchPage).hitTestable(), findsNothing);
      expect(h.controller.state, isA<Playing>());
    });
  });
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key,
  LogicalKeyboardKey modifier,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}
