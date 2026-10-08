import 'package:alchemist/alchemist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/layout_state.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/shell/now_playing_panel.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// 右側「正在播放」面板在外殼右側的位置（M2 PR 19）：頁面區、把手、面板並排，播放列在
// 三者下方橫跨。只守版面結構，文字畫成色塊（test/flutter_test_config.dart）。更新：
// `flutter test --update-goldens test/ui/shell/now_playing_panel_golden_test.dart`。
// 導覽欄與頁面不在這裡（要整個外殼的資料）：頁面區用一塊實色代替。

Widget _shell(double width, double height) {
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
                QueueEntry(summary('a').toTrackInfo()),
                QueueEntry(summary('b').toTrackInfo()),
              ],
              currentIndex: 0,
            ),
          ),
        ),
        playbackStateProvider.overrideWithValue(const AsyncData(Playing())),
        playbackPreviewProvider.overrideWithValue(const AsyncData(false)),
        playbackVolumeProvider.overrideWithValue(
          const AsyncData((volume: 0.7, muted: false)),
        ),
        playbackOutputDevicesProvider.overrideWithValue(
          const AsyncData((devices: <OutputDevice>[], selected: null)),
        ),
        outputDeviceSelectionProvider.overrideWithValue(true),
        playbackProgressProvider.overrideWithValue(
          const AsyncData(
            PlaybackProgress(
              position: Duration(minutes: 1, seconds: 5),
              duration: Duration(minutes: 3, seconds: 5),
            ),
          ),
        ),
        panelExpandedProvider.overrideWithValue(true),
        panelStoredWidthProvider.overrideWithValue(null),
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
        // 面板用視窗寬度夾取：視窗就是這個盒子，不是 golden 的畫布。
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: Size(width, height)),
          child: child!,
        ),
        home: WindowClassScope(
          child: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (context) => ColoredBox(
                            color: Theme.of(context).colorScheme.surface,
                          ),
                        ),
                      ),
                      const NowPlayingPanelSide(),
                    ],
                  ),
                ),
                const WindowClassScope(child: PlayerBar(panelToggle: true)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // 一個寬度一個 goldenTest、不用 GoldenTestScenario（理由見 player_bar_golden_test.dart）。
  for (final (name, width, height) in [
    ('expanded', 1000.0, 520.0),
    ('extra_large', 1800.0, 520.0),
  ]) {
    goldenTest(
      'the now playing panel, $name ($width wide)',
      fileName: 'now_playing_panel_$name',
      builder: () => _shell(width, height),
    );
  }
}
