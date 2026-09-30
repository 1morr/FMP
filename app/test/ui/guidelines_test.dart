import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:material_ui/material_ui.dart';

import '../support/memory_database.dart';
import 'support/shell_harness.dart';

// ADR 0024 §如何確認：淺色與深色主題下通過點擊區與對比度 guideline。示範畫面
// 驗證主題本身（M3 元件、token 的語意色、四種提示）；外殼裡的搜尋頁、設定頁與
// 播放列在窄與寬兩種視窗各驗一次。

/// 示範畫面：文字角色、常見按鈕、外觀設定控制項。
class _Demo extends StatelessWidget {
  const _Demo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('示範')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('標題', style: theme.textTheme.titleLarge),
            Text('內文', style: theme.textTheme.bodyMedium),
            Text('說明', style: theme.textTheme.bodySmall),
            Wrap(
              spacing: tokens.spacing.x2,
              children: [
                FilledButton(onPressed: () {}, child: const Text('確定')),
                OutlinedButton(onPressed: () {}, child: const Text('取消')),
                TextButton(onPressed: () {}, child: const Text('更多')),
                IconButton(
                  tooltip: '播放',
                  onPressed: () {},
                  icon: const Icon(Icons.play_arrow),
                ),
              ],
            ),
            const AppearanceControls(),
          ],
        ),
      ),
    );
  }
}

void main() {
  for (final brightness in Brightness.values) {
    group('$brightness', () {
      late Toaster toaster;

      Future<void> pumpDemo(WidgetTester tester) async {
        toaster = Toaster(
          log: Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
          translations: AppLocale.zhTw.buildSync,
          sourceName: (_) => null,
        );
        addTearDown(toaster.dispose);
        final database = memoryDatabase();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(database),
              toasterProvider.overrideWithValue(toaster),
            ],
            child: MaterialApp(
              theme: buildAppTheme(
                Brightness.light,
                fontFamilyFallback: const [],
                textLocale: _hant,
              ),
              darkTheme: buildAppTheme(
                Brightness.dark,
                fontFamilyFallback: const [],
                textLocale: _hant,
              ),
              themeMode: themeModeOf(switch (brightness) {
                Brightness.light => ThemeModeSetting.light,
                Brightness.dark => ThemeModeSetting.dark,
              }),
              builder: (context, navigator) => ToastHost(child: navigator!),
              home: const _Demo(),
            ),
          ),
        );
        // 外觀設定從記憶體資料庫讀出來（drift 的串流要真的事件迴圈）。
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RadioListTile<LocaleSetting?>), findsNWidgets(4));
      }

      Future<void> expectGuidelines(WidgetTester tester) async {
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }

      testWidgets('the demo screen meets the guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpDemo(tester);

        await expectGuidelines(tester);
        handle.dispose();
      });

      for (final kind in ToastKind.values) {
        testWidgets('a ${kind.name} toast meets the guidelines', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await pumpDemo(tester);
          final action = ToastAction(label: '復原', onPressed: () {});
          switch (kind) {
            case ToastKind.success:
              toaster.success('已加入歌單', action: action);
            case ToastKind.info:
              toaster.info('已複製連結', action: action);
            case ToastKind.warning:
              toaster.warning('儲存空間不足', action: action);
            case ToastKind.error:
              toaster.error(
                RateLimited(pluginId: 'bilibili'),
                operation: 'Search failed',
                tag: 'test',
                action: action,
              );
          }
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsOneWidget);

          await expectGuidelines(tester);
          handle.dispose();
        });
      }

      for (final size in const [Size(400, 800), Size(1000, 700)]) {
        final width = size.width;

        testWidgets('search, before searching, at $width', (tester) async {
          final handle = tester.ensureSemantics();
          await ShellHarness().pumpShell(
            tester,
            size: size,
            brightness: brightness,
          );

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('search results and the player bar at $width', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.enterText(find.byType(TextField), 'song');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump();
          await tester.tap(find.text('Song a'));
          await tester.pump(const Duration(milliseconds: 200));
          // 輸入框沒有焦點：游標閃爍會讓對比度的取樣時好時壞。
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();

          await expectGuidelines(tester);
          handle.dispose();
        });

        testWidgets('settings at $width', (tester) async {
          final handle = tester.ensureSemantics();
          final h = ShellHarness();
          await h.pumpShell(tester, size: size, brightness: brightness);
          await tester.tap(find.text('Settings').first);
          await h.loadSettings(tester);
          await tester.pumpAndSettle();

          await expectGuidelines(tester);
          handle.dispose();
        });
      }
    });
  }
}

const _hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
