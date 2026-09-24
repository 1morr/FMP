import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/audio/audio_player_selectors.dart';
import 'package:fmp/providers/settings/layout_settings_provider.dart';
import 'package:fmp/services/radio/radio_controller.dart';
import 'package:fmp/ui/layouts/responsive_scaffold.dart';

/// 側欄要讀屏看得到。
///
/// 側欄和 shell 的內層 Navigator 是同一個 Row 的兄弟，而且畫在它前面。路由的
/// ModalBarrier 帶 `BlockSemantics`，同一個語意容器裡先畫的節點會被整段丟掉：
/// 畫面上完全正常，只有讀屏聽不到。所以這裡在真的 Navigator 底下量。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  final en = AppLocale.en.translations;

  Future<void> pumpShell(
    WidgetTester tester, {
    required double width,
    bool railExpanded = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [
            showRadioPlaybackUiProvider.overrideWithValue(false),
            currentTrackProvider.overrideWithValue(null),
            layoutSettingsProvider.overrideWith(
              () => _FixedLayoutSettings(railExpanded: railExpanded),
            ),
          ],
          child: MaterialApp(
            home: ResponsiveScaffold(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('page')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectRailInSemantics(WidgetTester tester) {
    // 內層路由本身照常讀得到。
    expect(find.bySemanticsLabel('page'), findsOneWidget);
    for (final label in [en.nav.home, en.nav.settings]) {
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(label))),
        findsWidgets,
        reason: label,
      );
    }
  }

  testWidgets('the tablet rail is in the semantics tree', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpShell(tester, width: 700);

    expectRailInSemantics(tester);
    semantics.dispose();
  });

  testWidgets('the collapsed desktop rail is in the semantics tree', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpShell(tester, width: 1400);

    expectRailInSemantics(tester);
    semantics.dispose();
  });

  testWidgets('the expanded desktop rail is in the semantics tree', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpShell(tester, width: 1400, railExpanded: true);

    expectRailInSemantics(tester);
    semantics.dispose();
  });
}

/// 固定的版面狀態：不讀資料庫。
class _FixedLayoutSettings extends LayoutSettingsNotifier {
  _FixedLayoutSettings({required this.railExpanded});

  final bool railExpanded;

  @override
  LayoutSettingsState build() => LayoutSettingsState(
    railExpanded: railExpanded,
    detailPanelExpanded: false,
    detailPanelWidth: const LayoutSettingsState.initial().detailPanelWidth,
  );
}
