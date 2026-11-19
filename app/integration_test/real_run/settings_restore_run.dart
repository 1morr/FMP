import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/glass/glass_effect.dart';
import 'package:fmp/app/i18n/language.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/theme/appearance.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 19 的實跑情境，後半：接著 `settings_run.dart` 留下的資料重開 App，
/// 第一個畫面就是深色、English、青綠、玻璃關閉；打開設定讀回。跑法見
/// `settings_run.dart`。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('after a restart the settings are kept', (tester) async {
    final run = await RealRun.launch(tester, keepData: true);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FmpApp)),
    );
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(container.read(accentProvider), Accent.teal);
    expect(container.read(glassEffectProvider), GlassTier.minimal);
    expect(container.read(languageProvider), AppLocale.en);
    expect(LocaleSettings.currentLocale, AppLocale.en);

    await openDestination(tester, Destination.settings);
    await run.waitFor(find.byType(SettingsPage));
    await run.step('settings');
    expect(find.text('Appearance'), findsWidgets);
  });
}
