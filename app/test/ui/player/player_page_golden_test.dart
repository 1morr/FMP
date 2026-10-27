import 'package:alchemist/alchemist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/playback/playback_controller.dart' show OutputDeviceState;
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/layout_state.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// ADR 0035 §如何確認：播放頁寬版（1000×700）、窄版（400×800）、矮版（914×411）的 golden，
// 只守版面結構（封面與控制的位置、頂列），文字畫成色塊（test/flutter_test_config.dart）。更新：
// `flutter test --update-goldens test/ui/player/player_page_golden_test.dart`。
// 沒有真的控制器與封面：播放頁讀的 provider 在這裡 override，背景是沒有封面時的實色。

/// 播放中、在 1:05 的第一首（共三首），只有視窗大小不同。
Widget _page(double width, double height, {required bool desktop}) {
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
          const AsyncData(LayoutState.empty),
        ),
        // 桌面（平台能選輸出裝置）的頂列多輸出裝置與音量。
        outputDeviceSelectionProvider.overrideWithValue(desktop),
        playbackVolumeProvider.overrideWithValue(
          const AsyncData((volume: 0.6, muted: false)),
        ),
        playbackOutputDevicesProvider.overrideWithValue(
          const AsyncData<OutputDeviceState>((
            devices: <OutputDevice>[],
            selected: null,
          )),
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
  // 一個尺寸一個檔案內的 goldenTest、不用 GoldenTestScenario（理由見
  // player_bar_golden_test.dart）。
  for (final (name, width, height, desktop) in [
    ('wide', 1000.0, 700.0, true),
    ('narrow', 400.0, 800.0, false),
    ('short', 914.0, 411.0, false),
  ]) {
    goldenTest(
      'the player page, $name (${width}x$height)',
      fileName: 'player_page_$name',
      builder: () => _page(width, height, desktop: desktop),
    );
  }
}
