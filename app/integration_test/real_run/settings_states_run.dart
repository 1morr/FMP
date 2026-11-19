import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/settings/settings_sections.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 19 的設定頁截圖（和 `docs/design/settings.html` 並排比對用）：不聯網
/// （沒有插件、沒有曲目），設定全是預設，深淺色用測試綁定切。手機截首頁、
/// 主題選單、玻璃效果選單；macOS 截寬版（1280×800）與窄視窗（960×720）的
/// 外觀、播放：
///
///     dart run tool/real_run.dart -d macos --out build/real_run-settings-states integration_test/real_run/settings_states_run.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings page in light and dark', (tester) async {
    final run = RealRun.attach(tester);
    final logDir = Directory.systemTemp.createTempSync('fmp_settings_states_');
    final log = await tester.runAsync(
      () => Log.open(logDir, minimumLevel: LogLevel.info),
    );
    final host = PluginHost(bundles: const [], log: log!);
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          logProvider.overrideWithValue(log),
          pluginHostProvider.overrideWith((_) => host),
        ],
      ),
    );
    await run.waitFor(find.byType(Navigator));

    Future<void> settle() async {
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> both(String name, [Future<void> Function()? open]) async {
      for (final b in [Brightness.light, Brightness.dark]) {
        binding.platformDispatcher.platformBrightnessTestValue = b;
        await settle();
        await open?.call();
        await run.step('$name-${b.name}');
        if (open != null) {
          // 收起選單（點外面）。
          await tester.tapAt(const Offset(4, 400));
          await settle();
        }
      }
      binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await settle();
    }

    Future<void> category(SettingsCategory c) async {
      await tester.tap(find.text(c.label(t)).first);
      await settle();
    }

    await openDestination(tester, Destination.settings);
    await run.waitFor(find.byType(SettingsPage));

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      for (final (width, size) in [
        ('wide', '1280x800'),
        ('medium', '960x720'),
      ]) {
        await run.system('resize-$width', 'resize', [size]);
        await settle();
        await category(SettingsCategory.appearance);
        await both('$width-appearance');
        await category(SettingsCategory.playback);
        await both('$width-playback');
      }
      await category(SettingsCategory.appearance);
    } else {
      await both('narrow');
      await both('narrow-theme-menu', () async {
        await tester.tap(find.text(t.settings.theme));
        await settle();
      });
      await both('narrow-glass-menu', () async {
        await tester.tap(find.text(t.settings.glass));
        await settle();
      });
    }
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
    await tester.runAsync(() async {
      await host.close();
      await log.close();
    });
    logDir.deleteSync(recursive: true);
  });
}
