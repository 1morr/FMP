import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/widgets/controls/switch_expansion_tile.dart';

void main() {
  testWidgets('shows expanded content even when switch is off', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwitchExpansionTile(
            title: 'Outline',
            expanded: true,
            enabled: false,
            onExpanded: (_) {},
            onEnabledChanged: (_) {},
            children: const [
              Text('Outline color'),
              Text('Outline width'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Outline color'), findsOneWidget);
    expect(find.text('Outline width'), findsOneWidget);
  });

  testWidgets('collapses when parent expanded state changes to false',
      (tester) async {
    Widget buildTile({required bool expanded}) {
      return MaterialApp(
        home: Scaffold(
          body: SwitchExpansionTile(
            title: 'Outline',
            expanded: expanded,
            enabled: true,
            onExpanded: (_) {},
            onEnabledChanged: (_) {},
            children: const [
              Text('Outline color'),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(buildTile(expanded: true));
    expect(find.text('Outline color'), findsOneWidget);

    await tester.pumpWidget(buildTile(expanded: false));
    await tester.pumpAndSettle();

    expect(find.text('Outline color'), findsNothing);
  });

  testWidgets('does not use paint-only scaling for the switch', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwitchExpansionTile(
            title: 'Outline',
            expanded: false,
            enabled: true,
            onExpanded: (_) {},
            onEnabledChanged: (_) {},
            children: const [
              Text('Outline color'),
            ],
          ),
        ),
      ),
    );

    final scaledSwitch = find.ancestor(
      of: find.byType(Switch),
      matching: find.byWidgetPredicate((widget) {
        return widget is Transform && widget.transform.storage[0] != 1;
      }),
    );

    expect(scaledSwitch, findsNothing);
  });
}
