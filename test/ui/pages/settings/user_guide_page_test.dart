import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/pages/settings/user_guide_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserGuidePage', () {
    setUp(() {
      LocaleSettings.setLocale(AppLocale.en);
    });

    testWidgets('uses expandable sections and hides detailed tips initially',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        TranslationProvider(
          child: const MaterialApp(home: UserGuidePage()),
        ),
      );

      final tiles =
          tester.widgetList<ExpansionTile>(find.byType(ExpansionTile));
      expect(tiles.length, greaterThanOrEqualTo(6));
      expect(find.text(t.userGuide.quickStart.importPlaylist), findsOneWidget);
      expect(find.text('YouTube Mix shortcut'), findsNothing);

      await tester.tap(find.text(t.userGuide.externalImport.title));
      await tester.pumpAndSettle();

      expect(find.text('YouTube Mix shortcut'), findsOneWidget);
      expect(find.textContaining('mix:dvgZkm1xWPE'), findsOneWidget);
    });
  });
}
