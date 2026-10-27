import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/empty_state/loading_state.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

// 共用的狀態元件（ADR 0035，R6.10）：EmptyState 的 error 與 compact 樣式、LoadingState。

const _hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');

Future<ThemeData> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
}) async {
  final theme = buildAppTheme(
    brightness,
    fontFamilyFallback: const [],
    textLocale: _hant,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: child),
    ),
  );
  return theme;
}

Color _iconColor(WidgetTester tester, IconData icon) =>
    tester.widget<Icon>(find.byIcon(icon)).color!;

void main() {
  group('EmptyState', () {
    testWidgets('a plain one has a muted icon, an error one an error icon', (
      tester,
    ) async {
      final theme = await _pump(
        tester,
        const EmptyState(icon: Icons.inbox, title: 'Nothing here'),
      );
      expect(
        _iconColor(tester, Icons.inbox),
        theme.colorScheme.onSurfaceVariant,
      );

      await _pump(
        tester,
        const EmptyState(
          icon: Icons.error_outline,
          title: 'Broke',
          error: true,
        ),
      );
      expect(_iconColor(tester, Icons.error_outline), theme.colorScheme.error);
      expect(
        _iconColor(tester, Icons.error_outline),
        isNot(theme.colorScheme.onSurfaceVariant),
      );
    });

    testWidgets('compact is an inline banner, not a centred page', (
      tester,
    ) async {
      var retried = false;
      final theme = await _pump(
        tester,
        Column(
          children: [
            EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load',
              body: 'Try again later',
              error: true,
              compact: true,
              action: TextButton(
                onPressed: () => retried = true,
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      );
      // 只佔橫條的高度，不撐滿父層、不捲動。
      expect(tester.getSize(find.byType(EmptyState)).height, lessThan(120));
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.text('Try again later'), findsOneWidget);
      expect(
        _iconColor(tester, Icons.error_outline),
        theme.colorScheme.onErrorContainer,
      );
      final banner = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(EmptyState),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (banner.decoration as BoxDecoration).color,
        theme.colorScheme.errorContainer,
      );

      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('a compact one that is not an error is a neutral banner', (
      tester,
    ) async {
      final theme = await _pump(
        tester,
        const Column(
          children: [
            EmptyState(
              icon: Icons.update_disabled,
              title: 'Off',
              compact: true,
            ),
          ],
        ),
      );
      final banner = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(EmptyState),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (banner.decoration as BoxDecoration).color,
        theme.colorScheme.surfaceContainerHighest,
      );
    });
  });

  group('LoadingState', () {
    testWidgets('a spinner with one line of visible text', (tester) async {
      await _pump(tester, const LoadingState(message: 'Loading charts'));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading charts'), findsOneWidget);
    });

    testWidgets('the text is the only thing a screen reader hears', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const LoadingState(message: 'Loading charts'));
      expect(find.bySemanticsLabel('Loading charts'), findsOneWidget);
      handle.dispose();
    });
  });
}
