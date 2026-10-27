import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/charts/chart_parts.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/tracks/track_markers.dart';
import 'package:fmp/ui/tracks/track_selection.dart';
import 'package:fmp/ui/tracks/track_subtitle.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// 曲目列的播放數（ADR 0035 §決定 10，B-05）：有值才顯示、用 CLDR 縮寫、固定寬的時長欄不動、
// 窄版與大字級不溢出；排行列與搜尋結果列共用 TrackSubtitle。

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  LocaleSetting? locale,
  Size size = const Size(1000, 700),
}) => ShellHarness(
  extraOverrides: [
    if (locale != null) uiLocaleProvider.overrideWithValue(locale),
  ],
).pumpApp(tester, Scaffold(body: child), size: size);

Widget _row({String? uploader, int? viewCount}) => ListTile(
  title: const Text('Title'),
  subtitle: uploader == null && viewCount == null
      ? null
      : TrackSubtitle(text: uploader, viewCount: viewCount),
  trailing: const TrackDuration(duration: Duration(minutes: 3, seconds: 5)),
);

void main() {
  group('TrackSubtitle', () {
    testWidgets('shows the count next to the uploader, abbreviated', (
      tester,
    ) async {
      await _pump(tester, _row(uploader: 'Someone', viewCount: 1234));

      expect(find.text('Someone'), findsOneWidget);
      expect(find.text('1.23K'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('a null count draws the uploader only', (tester) async {
      await _pump(tester, _row(uploader: 'Someone'));

      expect(find.text('Someone'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('a zero count is still a count', (tester) async {
      await _pump(tester, _row(uploader: 'Someone', viewCount: 0));

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('the count alone is drawn without an uploader', (tester) async {
      await _pump(tester, _row(viewCount: 46000000));

      expect(find.text('46M'), findsOneWidget);
    });

    testWidgets('the abbreviation follows the interface language', (
      tester,
    ) async {
      await _pump(
        tester,
        _row(uploader: 'Someone', viewCount: 12345),
        locale: LocaleSetting.zhTw,
      );

      expect(find.text('1.23萬'), findsOneWidget);
    });

    testWidgets('the simplified Chinese abbreviation', (tester) async {
      await _pump(
        tester,
        _row(uploader: 'Someone', viewCount: 12345),
        locale: LocaleSetting.zhCn,
      );

      expect(find.text('1.23万'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('does not overflow at 360 wide, text scale $scale, and '
          'leaves the duration column alone', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(
          tester,
          _row(
            uploader: 'A very long uploader name that cannot fit',
            viewCount: 46000000,
          ),
          size: const Size(360, 700),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('3:05'), findsOneWidget);
        expect(
          tester.getSize(find.byType(TrackDuration)).width,
          greaterThan(0),
        );
      });
    }
  });

  group('a chart row', () {
    TrackInfo track({int? viewCount}) => TrackInfo(
      sourceTypeId: 'fmp-test',
      sourceId: 'a',
      title: 'Song a',
      uploader: 'Uploader a',
      viewCount: viewCount,
    );

    Widget tile(TrackInfo track) => ChartTrackTile(
      rank: 1,
      track: track,
      row: TrackRowSlots(
        selecting: false,
        selected: false,
        trailing: const SizedBox.shrink(),
        onTap: null,
        onLongPress: () {},
      ),
    );

    testWidgets('shows the play count when the plugin gave one', (
      tester,
    ) async {
      await _pump(tester, tile(track(viewCount: 4600000)));

      expect(find.text('Uploader a'), findsOneWidget);
      expect(find.text('4.6M'), findsOneWidget);
    });

    testWidgets('hides it when there is none', (tester) async {
      await _pump(tester, tile(track()));

      expect(find.text('Uploader a'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });
  });
}
