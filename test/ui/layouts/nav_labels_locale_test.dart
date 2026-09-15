import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/app_layout.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/audio/audio_player_selectors.dart';
import 'package:fmp/services/radio/radio_controller.dart';
import 'package:fmp/ui/layouts/responsive_scaffold.dart';

/// 導覽標籤必須跟著 locale 走（#112）。
///
/// `LocaleNotifier._loadSettings()` 是非同步的：首幀畫出來時語言還是系統語言，
/// 使用者設定的語言在那之後才 `setLocaleSync`。導覽列以前從 slang 全域 `t` 取
/// 標籤，那條路徑不依賴 `TranslationProvider`，換 locale 不會重建 —— 冷啟動後
/// 標籤停在系統語言，切一次分頁才刷新。
///
/// 這裡刻意讓 `TranslationProvider` 的 child 在整個測試裡是同一個 widget 實例，
/// 跟 `main.dart` 的 `TranslationProvider(child: const FMPApp())` 一樣：父層重建
/// 時 child 相同就不會往下重建，只有登記過依賴的 subtree 收得到通知。少了這一點
/// 就會測成「反正整棵樹都會重建」，紅不起來。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));
  tearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

  final en = AppLocale.en.translations;
  final zhTw = AppLocale.zhTw.translations;

  test('the two locales really do spell the labels differently', () {
    // 沒有這條，下面兩個 testWidgets 在兩邊字串相同時會空過。
    expect(zhTw.nav.home, isNot(en.nav.home));
    expect(zhTw.nav.settings, isNot(en.nav.settings));
  });

  testWidgets('the bottom navigation labels follow a late locale change', (
    tester,
  ) async {
    // compact 版面（手機）走底部導覽列；#112 就是在這裡看到的。
    // `ResponsiveScaffold` 從 `MediaQuery` 挑版面，而 MediaQuery 讀的是
    // `tester.view`，不是 `setSurfaceSize`（後者只改 RenderView 的約束）。
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [
            // 迷你播放器不是本測試的主題。沒有曲目時它是 SizedBox.shrink，
            // 這兩個 override 讓它不必真的建出 AudioController。
            showRadioPlaybackUiProvider.overrideWithValue(false),
            currentTrackProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: ResponsiveScaffold(
              selectedIndex: 0,
              onDestinationSelected: _ignoreIndex,
              child: SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.widgetWithText(NavigationBar, en.nav.home), findsOneWidget);
    expect(find.widgetWithText(NavigationBar, en.nav.settings), findsOneWidget);

    // 首幀之後才套用使用者設定的語言 —— 這正是 LocaleNotifier 做的事。
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(NavigationBar, zhTw.nav.home), findsOneWidget);
    expect(
      find.widgetWithText(NavigationBar, zhTw.nav.settings),
      findsOneWidget,
    );
    expect(find.text(en.nav.home), findsNothing);
  });

  testWidgets('the collapsed rail labels follow a late locale change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(AppLayout.railCollapsed, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TranslationProvider(
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: AppLayout.railCollapsed,
              child: CollapsedNavRail(
                selectedIndex: 0,
                onDestinationSelected: _ignoreIndex,
                onExpand: _ignoreExpand,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(en.nav.home), findsOneWidget);

    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    await tester.pumpAndSettle();

    expect(find.text(zhTw.nav.home), findsOneWidget);
    expect(find.text(en.nav.home), findsNothing);
    // 展開按鈕的 tooltip 與目的地標籤走同一條路徑。
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.menu))
          .tooltip,
      zhTw.nav.expandNav,
    );
  });
}

void _ignoreIndex(int index) {}

void _ignoreExpand() {}
