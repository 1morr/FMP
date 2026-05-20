import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/widgets/compact_color_picker_button.dart';

void main() {
  testWidgets('shows only the current color button before opening the palette',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactColorPickerButton(
            label: 'Text color',
            color: const Color(0xFFFFD166),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.text('#FFFFD166'), findsOneWidget);
    expect(find.byKey(CompactColorPickerButton.paletteKey), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('opens a palette from the current color button', (tester) async {
    final changes = <Color>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactColorPickerButton(
            label: 'Text color',
            color: const Color(0xFFFFD166),
            onChanged: changes.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    expect(find.byKey(CompactColorPickerButton.paletteKey), findsOneWidget);

    await tester.drag(
      find.byKey(CompactColorPickerButton.saturationValueKey),
      const Offset(-24, 18),
    );
    await tester.pump();

    expect(changes, isNotEmpty);
  });

  testWidgets('palette fits within a narrow lyrics window', (tester) async {
    tester.view.physicalSize = const Size(280, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactColorPickerButton(
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
      find.byKey(CompactColorPickerButton.paletteKey),
    );
    final contentSize = tester.getSize(
      find.byKey(CompactColorPickerButton.paletteContentKey),
    );

    expect(paletteRect.left, greaterThanOrEqualTo(0));
    expect(paletteRect.right, lessThanOrEqualTo(280));
    expect(contentSize.width, lessThanOrEqualTo(224));
  });
}
