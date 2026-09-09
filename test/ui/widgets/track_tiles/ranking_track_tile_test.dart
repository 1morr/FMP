import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/audio/audio_player_selectors.dart';
import 'package:fmp/ui/widgets/track_tiles/ranking_track_tile.dart';

/// 排行榜列在窄容器裡的行為（#85）。
///
/// 側欄展開加右側面板的橫向手機，中間內容欄只剩約 268dp。那一列的第二行以前是
/// 「可縮的藝人名 + 完全不可縮的播放數群組」，可用寬度一低於群組的固有寬就整列
/// 溢出 —— 版面層沒有做錯什麼，是這個元件自己不會縮。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LocaleSettings.setLocale(AppLocale.en));

  Future<void> pumpTile(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [currentTrackProvider.overrideWithValue(null)],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: width,
                child: RankingTrackTile(track: _track(), rank: 1),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the narrowest real column does not overflow', (tester) async {
    // 236dp 是算出來的最窄情境：914dp 寬的橫向手機扣掉展開側欄 256、分隔線 1、
    // 面板 366 + pane spacer 24，內容欄剩約 268dp，再扣首頁排行榜區塊的 32dp
    // 左右外距。
    await pumpTile(tester, 236);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the artist survives while the play count steps aside', (
    tester,
  ) async {
    await pumpTile(tester, 236);

    expect(find.text('Tester'), findsOneWidget);
    // 播放數是次要資訊，藝人名不是 —— 窄的時候先讓播放數走。
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('the title gets twice the width it used to', (tester) async {
    await pumpTile(tester, 236);

    final titleWidth = tester.getSize(find.text(_longTitle)).width;
    // 修之前是 48dp —— 一列 236dp 裡有 148dp 是固定開銷（外距 32、名次 28、封面
    // 48、選單按鈕 48）。收窄外距、間隔、名次欄與封面之後是 96dp，六個全形字。
    // 再往上只剩「拿掉封面」或「拿掉選單按鈕」兩條路，兩條都會少掉功能。
    expect(titleWidth, greaterThanOrEqualTo(96));
  });

  testWidgets('a wide column still shows the play count', (tester) async {
    await pumpTile(tester, 600);

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('Tester'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the play count cannot overflow just above the threshold', (
    tester,
  ) async {
    // 門檻上緣：播放數還在，但空間只剛好夠。整組現在包在 Flexible 裡，所以
    // 它會 ellipsis 而不是把整列撐破。
    await pumpTile(tester, 321);

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _longTitle = '晴天雨天陰天多雲時晴的那一個下午';

Track _track() {
  return Track()
    ..sourceId = 'ne-1'
    ..sourceType = SourceIds.netease
    ..title = _longTitle
    ..artist = 'Tester'
    ..viewCount = 12345678;
}
