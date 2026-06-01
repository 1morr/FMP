import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/widgets/controls/color_palette_button.dart';

const _hexInputKey = ValueKey('color-palette-hex-input');

void main() {
  testWidgets('shows only the current color button before opening the palette',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPaletteButton(
            label: 'Text color',
            color: const Color(0xFFFFD166),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.text('#FFFFD166'), findsOneWidget);
    expect(find.byKey(ColorPaletteButton.paletteKey), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('opens a palette from the current color button', (tester) async {
    final changes = <Color>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPaletteButton(
            label: 'Text color',
            color: const Color(0xFFFFD166),
            onChanged: changes.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    expect(find.byKey(ColorPaletteButton.paletteKey), findsOneWidget);

    await tester.drag(
      find.byKey(ColorPaletteButton.saturationValueKey),
      const Offset(-24, 18),
    );
    await tester.pump();

    expect(changes, isNotEmpty);
  });

  testWidgets('bottom slider changes color brightness instead of opacity',
      (tester) async {
    final changes = <Color>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPaletteButton(
            label: 'Text color',
            color: const Color(0xFFFF0000),
            onChanged: changes.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Slider), const Offset(-96, 0));
    await tester.pump();

    final changedValue = changes.last.toARGB32();
    final changedAlpha = (changedValue >> 24) & 0xff;
    final changedRed = (changedValue >> 16) & 0xff;

    expect(changedAlpha, 0xff);
    expect(changedRed, lessThan(0xff));
  });

  testWidgets('palette accepts manually entered 8 digit hex colors',
      (tester) async {
    final changes = <Color>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPaletteButton(
            label: 'Text color',
            color: const Color(0xFFFFD166),
            onChanged: changes.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(_hexInputKey), '#FF336699');
    await tester.pump();

    expect(changes.last, const Color(0xFF336699));
  });

  testWidgets('palette accepts manually entered 6 digit hex colors',
      (tester) async {
    final changes = <Color>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPaletteButton(
            label: 'Text color',
            color: const Color(0xFFFFD166),
            onChanged: changes.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(_hexInputKey), '336699');
    await tester.pump();

    expect(changes.last, const Color(0xFF336699));
  });

  testWidgets('palette keeps hex input synced with palette changes',
      (tester) async {
    final changes = <Color>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPaletteButton(
            label: 'Text color',
            color: const Color(0xFFFFD166),
            onChanged: changes.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '#FFFFD166'), findsOneWidget);

    await tester.drag(
      find.byKey(ColorPaletteButton.saturationValueKey),
      const Offset(-24, 18),
    );
    await tester.pump();

    expect(
      find.widgetWithText(
        TextFormField,
        ColorPaletteButton.formatColor(changes.last),
      ),
      findsOneWidget,
    );
  });

  testWidgets('palette keeps hex input compact', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPaletteButton(
            label: 'Text color',
            color: const Color(0xFFFFD166),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    final contentWidth =
        tester.getSize(find.byKey(ColorPaletteButton.paletteContentKey)).width;
    final inputWidth = tester.getSize(find.byKey(_hexInputKey)).width;

    expect(inputWidth, lessThan(contentWidth));
    expect(inputWidth, inInclusiveRange(88, 100));
  });

  testWidgets('palette fits within a narrow lyrics window', (tester) async {
    tester.view.physicalSize = const Size(280, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPaletteButton(
            label: 'Text color',
            color: const Color(0xFFFFD166),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    final paletteRect = tester.getRect(
      find.byKey(ColorPaletteButton.paletteKey),
    );
    final contentSize = tester.getSize(
      find.byKey(ColorPaletteButton.paletteContentKey),
    );

    expect(paletteRect.left, greaterThanOrEqualTo(0));
    expect(paletteRect.right, lessThanOrEqualTo(280));
    expect(contentSize.width, lessThanOrEqualTo(224));
  });

  testWidgets('palette fits within a short lyrics window', (tester) async {
    tester.view.physicalSize = const Size(280, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPaletteButton(
            label: 'Text color',
            color: const Color(0xFFFFD166),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final paletteRect = tester.getRect(
      find.byKey(ColorPaletteButton.paletteKey),
    );

    expect(paletteRect.top, greaterThanOrEqualTo(0));
    expect(paletteRect.bottom, lessThanOrEqualTo(300));
  });

  testWidgets('palette shell keeps title content and actions aligned',
      (tester) async {
    tester.view.physicalSize = const Size(360, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPaletteButton(
            label: 'Custom color',
            color: const Color(0xFF6E5A83),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    final paletteWidth =
        tester.getSize(find.byKey(ColorPaletteButton.paletteKey)).width;
    final contentWidth =
        tester.getSize(find.byKey(ColorPaletteButton.paletteContentKey)).width;

    expect(paletteWidth - contentWidth, 32);
  });

  testWidgets('palette uses caller provided close label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPaletteButton(
            label: 'Custom color',
            closeLabel: '關閉',
            color: const Color(0xFF6E5A83),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    expect(find.text('關閉'), findsOneWidget);
    expect(find.text('Close'), findsNothing);
  });
}
