import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/ui_constants.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/ui/widgets/indicators/live_badge.dart';
import 'package:fmp/ui/widgets/indicators/now_playing_indicator.dart';
import 'package:fmp/ui/widgets/radio/radio_station_card.dart';

void main() {
  RadioStation buildStation({String? hostName}) {
    return RadioStation()
      ..id = 1
      ..url = 'https://example.com/1'
      ..title = 'Test Station'
      ..sourceType = SourceType.bilibili
      ..sourceId = '1'
      ..hostName = hostName;
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets(
    'fixed-size dense card renders title, live dot and InkWell when tappable',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 120,
            child: RadioStationCard(
              station: buildStation(),
              isLive: true,
              isPlaying: false,
              isLoading: false,
              coverSize: 100,
              dense: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Test Station'), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);

      // 直播紅點尺寸由封面推導：dotSizeForCover(100) = 14
      final badge = tester.widget<LiveBadge>(find.byType(LiveBadge));
      expect(badge.size, LiveBadge.dotSizeForCover(100));

      await tester.tap(find.byType(RadioStationCard));
      expect(tapped, isTrue);
    },
  );

  testWidgets(
    'sort mode (onTap null) skips InkWell and overlays the drag handle',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 160,
            child: RadioStationCard(
              station: buildStation(),
              isLive: false,
              isPlaying: false,
              isLoading: false,
              showAnchor: true,
              trailing: const RadioStationDragHandle(),
            ),
          ),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(RadioStationDragHandle), findsOneWidget);
      expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    },
  );

  testWidgets(
    'liquid layout derives cover size from width and shows anchor row',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 160,
            child: RadioStationCard(
              station: buildStation(hostName: 'Test Host'),
              isLive: false,
              isPlaying: true,
              isLoading: false,
              showAnchor: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Host'), findsOneWidget);

      // 液態封面 = 160 - 40 = 120；播放中指示器 = 封面 * 0.32
      final indicator =
          tester.widget<NowPlayingIndicator>(find.byType(NowPlayingIndicator));
      expect(indicator.size, 120 * 0.32);

      // 非直播時封面灰階
      final filtered = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
      expect(filtered.colorFilter, kGrayscaleColorFilter);
    },
  );

  testWidgets('anchor row is hidden when showAnchor is false', (tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 120,
          child: RadioStationCard(
            station: buildStation(hostName: 'Test Host'),
            isLive: true,
            isPlaying: false,
            isLoading: false,
            coverSize: 100,
            dense: true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Test Host'), findsNothing);
  });
}
