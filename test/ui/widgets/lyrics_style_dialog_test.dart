import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/lyrics_window_style.dart';
import 'package:fmp/ui/widgets/color_palette_button.dart';
import 'package:fmp/ui/widgets/lyrics_style_dialog.dart';

const _strings = LyricsStyleDialogStrings(
  styleSettings: 'Lyrics style',
  textColor: 'Text color',
  secondaryTextColor: 'Secondary color',
  inactiveOpacity: 'Inactive opacity',
  outline: 'Outline',
  outlineColor: 'Outline color',
  outlineWidth: 'Outline width',
  shadow: 'Shadow',
  shadowColor: 'Shadow color',
  shadowBlur: 'Shadow blur',
  shadowOffsetX: 'Shadow X',
  shadowOffsetY: 'Shadow Y',
  resetStyle: 'Reset style',
  close: 'Close',
);

const _longStrings = LyricsStyleDialogStrings(
  styleSettings: 'Lyrics style settings with a very long localized title',
  textColor: 'Primary lyric text color with extra words',
  secondaryTextColor: 'Secondary lyric translation color with extra words',
  inactiveOpacity: 'Inactive lyric opacity percentage with extra words',
  outline: 'Outline effect controls with a long label',
  outlineColor: 'Outline stroke color with extra localized words',
  outlineWidth: 'Outline stroke width with extra localized words',
  shadow: 'Shadow effect controls with a long label',
  shadowColor: 'Shadow color with extra localized words',
  shadowBlur: 'Shadow blur radius with extra localized words',
  shadowOffsetX: 'Shadow horizontal offset with extra localized words',
  shadowOffsetY: 'Shadow vertical offset with extra localized words',
  resetStyle: 'Reset',
  close: 'Close',
);

void main() {
  testWidgets('renders compactly within a lyrics-sized window', (tester) async {
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDialog(tester);

    final dialogRect = tester.getRect(find.byKey(LyricsStyleDialog.dialogKey));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opacity slider reports style changes', (tester) async {
    final changes = <LyricsWindowStyle>[];
    await _pumpDialog(tester, onChanged: changes.add);

    await tester.drag(
      find.byKey(LyricsStyleDialog.inactiveOpacitySliderKey),
      const Offset(80, 0),
    );
    await tester.pump();

    expect(changes, isNotEmpty);
    expect(changes.last.inactiveOpacity, isNot(0.5));
  });

  testWidgets('reset button invokes reset callback', (tester) async {
    var resetCount = 0;
    await _pumpDialog(tester, onReset: () => resetCount++);

    await tester.tap(find.byKey(LyricsStyleDialog.resetButtonKey));
    await tester.pump();

    expect(resetCount, 1);
  });

  testWidgets('expands disabled outline controls with their content',
      (tester) async {
    await _pumpDialog(
      tester,
      initialStyle: LyricsWindowStyle.defaults.copyWith(
        outlineEnabled: false,
      ),
    );

    expect(find.text('Outline color'), findsNothing);

    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();

    expect(find.text('Outline color'), findsOneWidget);
    expect(find.text('Outline width'), findsOneWidget);
  });

  testWidgets('opens nested color palette with the dialog close label',
      (tester) async {
    await _pumpDialog(tester);

    await tester.tap(find.text('#FFFFFFFF'));
    await tester.pumpAndSettle();

    expect(find.byKey(ColorPaletteButton.paletteKey), findsOneWidget);
    expect(find.text('Close'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expands disabled shadow controls with their content',
      (tester) async {
    await _pumpDialog(
      tester,
      initialStyle: LyricsWindowStyle.defaults.copyWith(
        shadowEnabled: false,
      ),
    );

    expect(find.text('Shadow color'), findsNothing);

    await tester.tap(find.text('Shadow'));
    await tester.pumpAndSettle();

    expect(find.text('Shadow color'), findsOneWidget);
    expect(find.text('Shadow blur'), findsOneWidget);
  });

  testWidgets('minimum lyrics window size keeps expanded controls usable',
      (tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDialog(tester, strings: _longStrings);

    await tester.ensureVisible(find.text(_longStrings.outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_longStrings.outline));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(_longStrings.shadow));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_longStrings.shadow));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text(_longStrings.close));
    await tester.pumpAndSettle();

    expect(find.text(_longStrings.close), findsOneWidget);

    await tester.ensureVisible(find.text('#FFFFFFFF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#FFFFFFFF'));
    await tester.pumpAndSettle();

    expect(find.byKey(ColorPaletteButton.paletteKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  LyricsWindowStyle initialStyle = LyricsWindowStyle.defaults,
  LyricsStyleDialogStrings strings = _strings,
  ValueChanged<LyricsWindowStyle>? onChanged,
  VoidCallback? onReset,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (context) => LyricsStyleDialog(
                    initialStyle: initialStyle,
                    strings: strings,
                    onChanged: onChanged ?? (_) {},
                    onReset: onReset ?? () {},
                  ),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
