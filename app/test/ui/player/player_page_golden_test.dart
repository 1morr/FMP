import 'package:alchemist/alchemist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/player_tab.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// ADR 0024 §如何確認：播放頁 B 在 1000、1400、1800 寬的 golden，只守版面結構（兩欄與
// 三欄、控制的位置、右欄的分頁），文字畫成色塊（test/flutter_test_config.dart）。更新：
// `flutter test --update-goldens test/ui/player/player_page_golden_test.dart`。
// 沒有真的控制器與封面：播放頁讀的 provider 在這裡 override，背景是沒有封面時的實色。

/// 播放中、在 1:05 的第一首（共三首），只有寬度與記住的分頁不同。
Widget _page(double width, double height, {PlayerTab? tab}) {
  return SizedBox(
    width: width,
    height: height,
    child: ProviderScope(
      overrides: [
        translationsProvider.overrideWithValue(AppLocale.zhTw.buildSync()),
        playbackQueueProvider.overrideWithValue(
          AsyncData(
            QueueState(
              entries: [
                for (final id in ['a', 'b', 'c'])
                  QueueEntry(summary(id).toTrackInfo()),
              ],
              currentIndex: 0,
            ),
          ),
        ),
        playbackStateProvider.overrideWithValue(const AsyncData(Playing())),
        playbackPreviewProvider.overrideWithValue(const AsyncData(false)),
        playbackSpeedProvider.overrideWithValue(const AsyncData(1.0)),
        playbackProgressProvider.overrideWithValue(
          const AsyncData(
            PlaybackProgress(
              position: Duration(minutes: 1, seconds: 5),
              duration: Duration(minutes: 3, seconds: 5),
            ),
          ),
        ),
        layoutStateProvider.overrideWithValue(
          AsyncData(LayoutState(playerTab: tab)),
        ),
        pluginNameProvider.overrideWith((ref, pluginId) => 'Test Source'),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(
          Brightness.light,
          fontFamilyFallback: const [],
          textLocale: textLocaleOf(LocaleSetting.zhTw),
        ),
        locale: flutterLocaleOf(LocaleSetting.zhTw),
        supportedLocales: supportedFlutterLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const WindowClassScope(child: PlayerPage()),
      ),
    ),
  );
}

void main() {
  // 一個寬度一個檔案內的 goldenTest、不用 GoldenTestScenario（理由見
  // player_bar_golden_test.dart）。
  for (final (name, width, height, tab) in [
    ('expanded', 1000.0, 700.0, null),
    ('large', 1400.0, 800.0, PlayerTab.queue),
    ('extra_large', 1800.0, 900.0, null),
  ]) {
    goldenTest(
      'the player page, $name ($width wide)',
      fileName: 'player_page_$name',
      builder: () => _page(width, height, tab: tab),
    );
  }
}
