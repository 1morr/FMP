import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/radio/radio_controller.dart';
import 'package:fmp/ui/widgets/radio/radio_mini_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scale in const [1.8, 2.0]) {
    testWidgets('text at ${scale}x grows the bar instead of clipping it', (
      tester,
    ) async {
      // 測試主機是 Windows，會多渲染桌面音量與裝置控制列。
      await tester.binding.setSurfaceSize(const Size(900, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      LocaleSettings.setLocale(AppLocale.en);

      await tester.pumpWidget(
        TranslationProvider(
          child: ProviderScope(
            overrides: [
              radioControllerProvider.overrideWith(_PlayingRadioController.new),
              audioControllerProvider.overrideWith(_IdleAudioController.new),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: RadioMiniPlayer(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 以前是固定 64dp，與音樂的迷你播放器同一個寫法。
      expect(tester.takeException(), isNull);
      expect(find.text('Morning Show'), findsOneWidget);
    });
  }
}

/// 不呼叫 `super.build()`：真的那個會去接電台資料庫與播放器。
class _PlayingRadioController extends RadioController {
  @override
  RadioState build() {
    final station = RadioStation()
      ..id = 1
      ..url = 'https://example.com/1'
      ..title = 'Morning Show'
      ..hostName = 'Someone'
      ..sourceType = SourceIds.bilibili
      ..sourceId = '1';
    return RadioState(
      stations: [station],
      currentStation: station,
      isPlaying: true,
    );
  }
}

/// 桌面控制列只讀音量與輸出裝置。
class _IdleAudioController extends AudioController {
  @override
  PlayerState build() => const PlayerState();
}
