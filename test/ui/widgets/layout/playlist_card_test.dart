import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/widgets/layout/playlist_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LocaleSettings.setLocale(AppLocale.en));

  testWidgets('large text in a narrow card does not overflow the badge row', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // 首頁「我的歌單」的卡片在手機上約 150dp 寬。實機字級 2.0 時曲目數那一列
    // 溢出 45px。
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 150,
                height: 260,
                child: PlaylistCard(
                  playlist: Playlist()
                    ..name = 'Wind'
                    ..trackIds = List.filled(154, 1),
                  cover: const ColoredBox(color: Colors.grey),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
