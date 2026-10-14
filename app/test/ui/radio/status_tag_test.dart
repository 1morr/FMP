import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/radio/radio_service.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/player/live_widgets.dart';
import 'package:fmp/ui/radio/radio_status_tag.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

// 狀態標記的顏色（電台四種、直播三種）在淺色與深色主題下都讀得清楚。guideline 測試的對比度
// 是以整個語意節點的明暗算的：電台列與搜尋結果是 ListTile，標記的字併在那一列的節點裡，
// 標記自己的字再淡也量不出來，所以這裡直接比標記的前景與背景（WCAG 2 的對比度，小字 4.5）。

double _contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  final (high, low) = la > lb ? (la, lb) : (lb, la);
  return (high + 0.05) / (low + 0.05);
}

const _hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('every status tag is readable, $brightness', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(AppLocale.en.buildSync()),
          ],
          child: MaterialApp(
            theme: buildAppTheme(
              brightness,
              fontFamilyFallback: const [],
              textLocale: _hant,
            ),
            home: Scaffold(
              body: Column(
                children: [
                  for (final status in RadioStatus.values)
                    RadioStatusTag(status: status),
                  for (final phase in LivePhase.values) LiveBadge(phase: phase),
                ],
              ),
            ),
          ),
        ),
      );

      final surface = Theme.of(tester.element(find.byType(Scaffold)))
          .colorScheme
          .surface;
      final tags = tester.widgetList<StatusTag>(find.byType(StatusTag));
      expect(
        tags,
        hasLength(RadioStatus.values.length + LivePhase.values.length),
      );
      for (final tag in tags) {
        // 只有邊框的標記畫在列的底色（surface）上。
        final background = tag.border == null ? tag.background : surface;
        expect(
          _contrast(tag.foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: tag.text,
        );
      }
      // 四種電台狀態彼此分得開：沒有兩種同色又同圖示。
      final looks = {
        for (final tag in tags.take(RadioStatus.values.length))
          (tag.icon, tag.background, tag.border),
      };
      expect(looks, hasLength(RadioStatus.values.length));
    });
  }
}
