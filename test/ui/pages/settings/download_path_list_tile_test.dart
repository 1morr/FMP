import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/download/download_path_provider.dart';
import 'package:fmp/ui/pages/settings/settings_page.dart';

/// 還沒選下載路徑是正常的初始狀態，不是錯誤。
///
/// 以錯誤色顯示「未設定」會讓剛裝好的使用者以為哪裡壞了；真正要提醒的時機是
/// 第一次下載，那裡有 `DownloadPathSetupDialog` 負責。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an unset download path is not painted in the error color', (
    tester,
  ) async {
    LocaleSettings.setLocale(AppLocale.en);
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [downloadPathProvider.overrideWith((ref) async => null)],
          child: MaterialApp(
            theme: theme,
            home: const Scaffold(body: DownloadPathListTile()),
          ),
        ),
      ),
    );
    // FutureProvider 的結果在下一個 frame 才從 loading 變成 data。
    await tester.pump();

    final subtitle = find.text(t.general.notSet);
    expect(subtitle, findsOneWidget);

    final paragraph = tester.renderObject<RenderParagraph>(subtitle);
    final color = paragraph.text.style?.color;
    expect(color, isNotNull);
    expect(color, isNot(theme.colorScheme.error));
  });
}
