import 'package:alchemist/alchemist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/queue_tracks.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// ADR 0024 §如何確認：播放列三段寬度的 golden，只守版面結構（控制項的位置、
// 曲名與進度條的排法），文字畫成色塊（test/flutter_test_config.dart）。更新：
// `flutter test --update-goldens test/ui/player/player_bar_golden_test.dart`。

/// 播放中、在 1:05 的一首，只有寬度不同。
Widget _bar(double width) {
  final track = summary('a');
  return SizedBox(
    width: width,
    height: 120,
    child: ProviderScope(
      overrides: [
        translationsProvider.overrideWithValue(AppLocale.zhTw.buildSync()),
        playbackQueueProvider.overrideWithValue(
          AsyncData(
            QueueState(
              entries: [
                QueueEntry(track.toTrackInfo()),
                QueueEntry(summary('b').toTrackInfo()),
              ],
              currentIndex: 0,
            ),
          ),
        ),
        playbackStateProvider.overrideWithValue(const AsyncData(Playing())),
        playbackProgressProvider.overrideWithValue(
          const AsyncData(
            PlaybackProgress(
              position: Duration(minutes: 1, seconds: 5),
              duration: Duration(minutes: 3, seconds: 5),
            ),
          ),
        ),
        queueTracksProvider.overrideWithBuild(
          (ref, notifier) => {trackKeyOf(track): track},
        ),
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
        home: const Align(
          alignment: Alignment.bottomCenter,
          child: WindowClassScope(child: PlayerBar()),
        ),
      ),
    ),
  );
}

void main() {
  // 一個寬度一個檔、不用 GoldenTestScenario：它的名稱標籤由 alchemist 自己
  // 排版，寬度在 Windows 與 Linux 差一個像素（色塊的邊），我們的元件則逐像素
  // 相同（2026-09-30 以 Flutter 3.47.5 在兩個平台比對）。
  for (final (name, width) in [
    ('compact', 360.0),
    ('medium', 720.0),
    ('expanded', 1000.0),
  ]) {
    goldenTest(
      'the player bar, $name ($width wide)',
      fileName: 'player_bar_$name',
      builder: () => _bar(width),
    );
  }
}
