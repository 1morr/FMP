import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/settings/settings_sections.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 19 的實跑情境，前半：開 App，在設定頁把主題改深色、強調色改青綠、玻璃
/// 效果改關閉、語言改 English（手機用列尾的選單，macOS 用窗格的預覽圖、色點、
/// 單選列與彈出選單，設定頁由真的 ⌘, 打開），每改一項讀回畫面。後半是 `settings_restore_run.dart`，
/// 接著這裡留下的資料重開。不搜尋、不播放；開 App 時首頁照常抓一次排行榜。
/// 兩段要連著跑、中間不碰裝置：
///
///     dart run tool/device_lock.dart -- bash -c 'dart run tool/real_run.dart -d macos --out <暫存目錄>/settings integration_test/real_run/settings_run.dart && dart run tool/real_run.dart -d macos --out <暫存目錄>/settings-restore integration_test/real_run/settings_restore_run.dart'
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings change at once', (tester) async {
    final run = await RealRun.launch(tester);
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    if (mac) await run.system('resize-wide', 'resize', ['1280x800']);

    Future<void> settle() async {
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// 手機：點列打開選單，選 [choice]。
    Future<void> pick(String row, String choice) async {
      await tester.tap(find.text(row));
      await settle();
      await tester.tap(find.text(choice).last);
      await settle();
    }

    if (mac) {
      // 真的鍵盤事件經過 macOS 的主選單（選單列的 Preferences… 也是 ⌘,），
      // 確認快捷鍵沒被它吃掉、到得了 App。
      await run.system('cmd-comma', 'shortcut', ['comma']);
    } else {
      await openDestination(tester, Destination.settings);
    }
    await run.waitFor(find.byType(SettingsPage));
    await run.step('settings');

    if (mac) {
      await tester.tap(find.bySemanticsLabel(t.settings.themeDark));
      await settle();
      await run.step('dark');
      await tester.tap(find.bySemanticsLabel(t.settings.accentTeal));
      await settle();
      await run.step('teal');
      await tester.tap(find.text(t.settings.glassOff));
      await settle();
      await run.step('glass-off');
      await tester.tap(find.textContaining('${t.settings.languageSystem}（'));
      await settle();
      await tester.tap(find.text(languageName(AppLocale.en)).last);
      await settle();
      await run.step('english');
    } else {
      await pick(t.settings.theme, t.settings.themeDark);
      await run.step('dark');
      await tester.tap(find.bySemanticsLabel(t.settings.accentTeal));
      await settle();
      await run.step('teal');
      await pick(t.settings.glass, t.settings.glassOff);
      await run.step('glass-off');
      await pick(t.settings.language, languageName(AppLocale.en));
      await run.step('english');
    }
    expect(find.text('Appearance'), findsWidgets);
  });
}
