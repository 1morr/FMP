import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/settings/desktop_settings_provider.dart';
import 'package:fmp/ui/pages/settings/settings_page.dart';

/// 可攜版的開機自啟開關多一行提示（#39）。
///
/// 殘餘缺口修不掉 —— 搬完資料夾之後、下一次開機之前 app 沒有跑過，就沒有機會
/// 改寫自己的登錄檔項目。所以這條的驗收對象是「使用者看不看得到那句話」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, {required bool portable}) async {
    LocaleSettings.setLocale(AppLocale.en);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [
            launchAtStartupProvider.overrideWith(_StubLaunchAtStartup.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LaunchAtStartupTile(isPortableBuild: portable),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a portable build explains the one-time open', (tester) async {
    await pump(tester, portable: true);

    expect(find.text(t.settings.launchAtStartup.portableHint), findsOneWidget);
    // 原本的副標題沒有被換掉，只是多了一行。
    expect(find.text(t.settings.launchAtStartup.subtitle), findsOneWidget);
  });

  testWidgets('an installed build keeps the current subtitle', (tester) async {
    await pump(tester, portable: false);

    expect(find.text(t.settings.launchAtStartup.portableHint), findsNothing);
    expect(find.text(t.settings.launchAtStartup.subtitle), findsOneWidget);
  });
}

/// 不碰外掛也不碰資料庫的 [LaunchAtStartupNotifier]。
///
/// 真的那一個在 `build()` 裡就會跑 `_load()` → `PackageInfo.fromPlatform()` 與
/// `launch_at_startup` 的登錄檔呼叫，在 widget test 裡全都是
/// `MissingPluginException`，而且是沒有人接的非同步錯誤。
class _StubLaunchAtStartup extends LaunchAtStartupNotifier {
  @override
  LaunchAtStartupState build() => const LaunchAtStartupState();
}
