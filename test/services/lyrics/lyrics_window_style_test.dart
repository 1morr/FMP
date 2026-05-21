import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/services/lyrics/lyrics_window_style.dart';

void main() {
  group('LyricsWindowLayout', () {
    test('transparent title bar keeps a stable reserved content position', () {
      expect(
        LyricsWindowLayout.contentTopInset(
          transparentMode: true,
          titleBarVisible: false,
          offsetControlsVisible: false,
        ),
        LyricsWindowLayout.titleBarHeight,
      );
      expect(
        LyricsWindowLayout.contentTopInset(
          transparentMode: true,
          titleBarVisible: true,
          offsetControlsVisible: false,
        ),
        LyricsWindowLayout.titleBarHeight,
      );
    });

    test('normal mode reserves title bar space above lyrics content', () {
      expect(
        LyricsWindowLayout.contentTopInset(
          transparentMode: false,
          titleBarVisible: true,
          offsetControlsVisible: false,
        ),
        LyricsWindowLayout.titleBarHeight,
      );
    });
  });

  group('LyricsWindowStyle', () {
    test('keeps current transparent lyric defaults', () {
      const style = LyricsWindowStyle.defaults;

      expect(style.textColor, Colors.white);
      expect(style.secondaryTextColor, const Color(0xB3FFFFFF));
      expect(style.inactiveOpacity, 0.5);
      expect(style.outlineEnabled, isTrue);
      expect(style.outlineColor, Colors.black);
      expect(style.outlineWidth, 1.5);
      expect(style.shadowEnabled, isTrue);
      expect(style.shadowColor, Colors.black);
      expect(style.shadowBlurRadius, 3);
      expect(style.shadowOffset, Offset.zero);
    });

    test('round-trips through Settings nullable persisted fields', () {
      const custom = LyricsWindowStyle(
        textColor: Color(0xFF88CCFF),
        textColorCustomized: true,
        secondaryTextColor: Color(0xCCFFE680),
        secondaryTextColorCustomized: true,
        inactiveOpacity: 0.42,
        outlineEnabled: false,
        outlineColor: Color(0xFF102030),
        outlineWidth: 2.25,
        shadowEnabled: true,
        shadowColor: Color(0xAA000000),
        shadowBlurRadius: 8,
        shadowOffset: Offset(1, 2),
      );
      final settings = Settings();

      custom.applyToSettings(settings);

      expect(LyricsWindowStyle.fromSettings(settings), custom);
    });

    test('round-trips through json payload', () {
      const custom = LyricsWindowStyle(
        textColor: Color(0xFFFFD166),
        textColorCustomized: true,
        secondaryTextColor: Color(0xFF7FDBFF),
        secondaryTextColorCustomized: true,
        inactiveOpacity: 0.35,
        outlineEnabled: true,
        outlineColor: Color(0xFF111111),
        outlineWidth: 3,
        shadowEnabled: false,
        shadowColor: Color(0x66000000),
        shadowBlurRadius: 6,
        shadowOffset: Offset(-1, 2),
      );

      final decoded = LyricsWindowStyle.fromJson(custom.toJson());

      expect(decoded, custom);
    });

    test(
        'applies default style only in transparent mode and custom style everywhere',
        () {
      const custom = LyricsWindowStyle(
        textColor: Color(0xFFFFD166),
        textColorCustomized: true,
        secondaryTextColor: Color(0xFF7FDBFF),
        secondaryTextColorCustomized: true,
        inactiveOpacity: 0.35,
        outlineEnabled: true,
        outlineColor: Color(0xFF111111),
        outlineWidth: 3,
        shadowEnabled: false,
        shadowColor: Color(0x66000000),
        shadowBlurRadius: 6,
        shadowOffset: Offset(-1, 2),
      );

      expect(
        LyricsWindowStyle.defaults.shouldApplyToText(transparentMode: true),
        isTrue,
      );
      expect(
        LyricsWindowStyle.defaults.shouldApplyToText(transparentMode: false),
        isFalse,
      );
      expect(
        custom.shouldApplyToText(transparentMode: false),
        isTrue,
      );
      expect(
        custom.shouldApplyToText(transparentMode: true),
        isTrue,
      );
    });

    test('does not apply text effects for opacity-only normal mode changes',
        () {
      final style = LyricsWindowStyle.defaults.copyWith(
        inactiveOpacity: 0.35,
      );

      expect(
        style.shouldApplyToText(transparentMode: false),
        isFalse,
      );
      expect(
        style.shouldApplyToText(transparentMode: true),
        isTrue,
      );
    });

    test('transparent mode does not force disabled text effects', () {
      final style = LyricsWindowStyle.defaults.copyWith(
        outlineEnabled: false,
        shadowEnabled: false,
      );

      expect(
        style.shouldApplyToText(transparentMode: true),
        isFalse,
      );
      expect(
        style.shouldApplyToText(transparentMode: false),
        isFalse,
      );
    });

    test('normal mode keeps fallback colors for non-color custom styles', () {
      final style = LyricsWindowStyle.defaults.copyWith(
        outlineWidth: 3,
        shadowBlurRadius: 8,
      );

      expect(
        style.resolveMainColor(
          isCurrent: true,
          transparentMode: false,
          fallbackCurrentColor: Colors.black,
          fallbackInactiveColor: Colors.black54,
        ),
        Colors.black,
      );
      expect(
        style.resolveMainColor(
          isCurrent: false,
          transparentMode: false,
          fallbackCurrentColor: Colors.black,
          fallbackInactiveColor: Colors.black54,
        ),
        Colors.black54,
      );
      expect(
        style.resolveSecondaryColor(
          isCurrent: true,
          transparentMode: false,
          fallbackCurrentColor: Colors.black87,
          fallbackInactiveColor: Colors.black38,
        ),
        Colors.black87,
      );
      expect(
        style.resolveSecondaryColor(
          isCurrent: false,
          transparentMode: false,
          fallbackCurrentColor: Colors.black87,
          fallbackInactiveColor: Colors.black38,
        ),
        Colors.black38,
      );
    });

    test('inactive lyric color preserves selected text alpha proportionally',
        () {
      const style = LyricsWindowStyle(
        textColor: Color(0x80FF0000),
        textColorCustomized: true,
        secondaryTextColor: Color(0x8000FF00),
        secondaryTextColorCustomized: true,
        inactiveOpacity: 0.5,
        outlineEnabled: true,
        outlineColor: Colors.black,
        outlineWidth: 1.5,
        shadowEnabled: true,
        shadowColor: Colors.black,
        shadowBlurRadius: 3,
        shadowOffset: Offset.zero,
      );

      expect(style.mainColor(isCurrent: false).toARGB32(), 0x40FF0000);
      expect(style.secondaryColor(isCurrent: false).toARGB32(), 0x3300FF00);
    });

    test('debounces style commits and keeps only the latest pending style',
        () async {
      final committed = <LyricsWindowStyle>[];
      final debouncer = LyricsWindowStyleCommitDebouncer(
        delay: const Duration(milliseconds: 20),
        commit: committed.add,
      );
      const first = LyricsWindowStyle.defaults;
      final second = LyricsWindowStyle.defaults.copyWith(
        textColor: Colors.amber,
      );

      debouncer.schedule(first);
      debouncer.schedule(second);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(committed, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(committed, [second]);

      debouncer.dispose();
    });
  });
}
