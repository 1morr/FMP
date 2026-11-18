import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/search/search.dart';
import 'package:fmp/search/search_history.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/search/search_query.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 14 的畫面狀態截圖（和 `docs/design/search.html` 並排比對用）：不聯網，
/// 搜尋的結果換成假的（App 打包的 bilibili 插件只用來畫音源標識），深淺色
/// 用測試綁定切，不動裝置的系統設定。每種寬度、深淺色各截搜尋紀錄、結果與
/// ⋮ 選單；載入骨架、單一音源出錯、找不到、多選與右鍵選單每種寬度截一次。
/// macOS 截寬版（1280×800）與中寬度（960×720），手機平台截窄版：
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/search_states_run.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search page states in light and dark', (tester) async {
    final run = RealRun.attach(tester);
    final logDir = Directory.systemTemp.createTempSync('fmp_search_states_');
    final log = await tester.runAsync(
      () => Log.open(logDir, minimumLevel: LogLevel.info),
    );
    final host = PluginHost(
      bundles: (await tester.runAsync(() => loadBundledPlugins(rootBundle)))!,
      log: log!,
    );
    final search = _StaticSearch();
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          logProvider.overrideWithValue(log),
          pluginHostProvider.overrideWith((_) => host),
          searchProvider.overrideWith(() => search),
        ],
      ),
    );
    await run.waitFor(find.byType(HomePage));
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    );
    final manifest = (await container.read(pluginHostProvider.future))
        .plugins
        .first
        .manifest;
    final history = container.read(searchHistoryProvider.notifier);
    for (final q in ['鋼琴 改編', 'lofi study', '夏夜漫遊 live', '夜行列車']) {
      await history.record(q);
    }

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> show(SearchState? state) async {
      search.show(state);
      container.read(searchQueryProvider).text = state?.query ?? '';
      await settle();
    }

    Future<void> brightness(Brightness value) async {
      binding.platformDispatcher.platformBrightnessTestValue = value;
      await settle();
    }

    Future<void> closeOverlay() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle();
    }

    final widths = mac ? ['wide', 'medium'] : ['narrow'];
    for (final width in widths) {
      if (mac) {
        await run.system('resize-$width', 'resize', [
          width == 'wide' ? '1280x800' : '960x720',
        ]);
        await settle();
      }
      if (find.byType(SearchPage).evaluate().isEmpty) await openSearch(tester);
      await settle();
      final pointer =
          FormFactor.of(tester.element(find.byType(SearchPage))).density ==
          Density.pointer;

      for (final b in [Brightness.light, Brightness.dark]) {
        await brightness(b);
        final tag = '$width-${b.name}';
        await show(null);
        await run.step('$tag-history');
        await show(_results(manifest));
        await run.step('$tag-results');
        await tester.tap(
          find.descendant(
            of: searchResultAt(1),
            matching: find.byTooltip(t.queue.more),
          ),
        );
        await settle();
        await run.step('$tag-menu');
        await closeOverlay();
      }

      // 次要的狀態：每種寬度一次（深色）。
      await show(
        SearchState(
          query: '夜',
          sources: [SourceResults(manifest: manifest, loading: true)],
        ),
      );
      await run.step('$width-loading');
      await show(
        SearchState(
          query: '夜',
          sources: [
            SourceResults(manifest: manifest, error: const RateLimited()),
          ],
        ),
      );
      await run.step('$width-error');
      await show(
        SearchState(
          query: '夜行列車 鋼琴四手聯彈 2019',
          sources: [
            SourceResults(manifest: manifest, pages: const [[]], isEnd: true),
          ],
        ),
      );
      await run.step('$width-empty');
      await show(_results(manifest));
      if (pointer) {
        await tester.tap(searchResultAt(1), kind: PointerDeviceKind.mouse);
        final command = mac
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(command);
        await tester.tap(searchResultAt(2), kind: PointerDeviceKind.mouse);
        await tester.tap(searchResultAt(3), kind: PointerDeviceKind.mouse);
        await tester.sendKeyUpEvent(command);
      } else {
        await tester.longPress(searchResultAt(1));
        await settle();
        await tester.tap(searchResultAt(2));
        await tester.tap(searchResultAt(3));
      }
      await settle();
      await run.step('$width-multi-select');
      if (pointer) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle();
        await tester.tap(
          searchResultAt(1),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryButton,
        );
        await settle();
        await run.step('$width-right-click');
        await closeOverlay();
      } else {
        await tester.tap(find.text(t.search.selection.cancel));
        await settle();
      }
      await brightness(Brightness.light);
    }
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
    await tester.runAsync(() async {
      await host.close();
      await log.close();
    });
    logDir.deleteSync(recursive: true);
  });
}

/// 搜「夜」的假結果（照設計稿的示範資料，合成的）：有播放數、網址與時長。
SearchState _results(PluginManifest manifest) {
  Track track(String id, String title, String author, int? plays, int secs) =>
      Track(
        ref: TrackRef(pluginId: manifest.id, trackId: id),
        title: title,
        author: author,
        playCount: plays,
        url: 'https://example.com/$id',
        duration: Duration(seconds: secs),
      );
  return SearchState(
    query: '夜',
    sources: [
      SourceResults(
        manifest: manifest,
        isEnd: true,
        pages: [
          [
            track('o1', '夜行列車（Live at 河岸留言）', '鹿野青', 210000, 280),
            track('o2', '【鋼琴】夜行列車 改編 附琴譜', '琴鍵上的鯨', 84000, 245),
            track('o3', 'Night Train to Nowhere', 'Juno Vale', 47000, 211),
            track('o4', '【合集】深夜電台 夜行 BGM', '安靜的午後', 560000, 4360),
            track('o5', 'Midnight Ferry (lofi)', 'lofi atlas', 120000, 178),
            track('o6', '【翻唱】夜のむこう 女聲版', '栗子Kuri', 315000, 262),
            track('o7', '【中文翻唱】群青の街', '栗子Kuri', 382000, 258),
            track('o8', '夜曲集', '林以澄', null, 238),
          ],
        ],
      ),
    ],
  );
}

/// 狀態由情境直接換的搜尋：不打插件。
class _StaticSearch extends Search {
  @override
  SearchState? build() => null;

  void show(SearchState? value) => state = value;

  @override
  Future<void> search(String query) async {}

  @override
  Future<void> sortBy(SearchSort sort) async {}

  @override
  void loadMore({String? only}) {}

  @override
  void retry(String pluginId) {}
}
