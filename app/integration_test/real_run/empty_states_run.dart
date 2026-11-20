import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/search/search.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/search/search_query.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 19c 的空狀態並排截圖（和 `docs/design/library.html`、`queue.html`、
/// `search.html` 的空狀態比對，看三頁圖示同高）：搜尋換成假的「找不到」，不
/// 打插件（App 打包的 bilibili 插件只用來畫音源標識；首頁照常抓一次榜），深淺
/// 色用測試綁定切。
/// macOS 截寬版（1280×800）與中寬度（960×720），手機平台截窄版：
///
///     dart run tool/real_run.dart -d macos --out build/real_run-empty integration_test/real_run/empty_states_run.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('library, queue and search empty states line up', (tester) async {
    final run = RealRun.attach(tester);
    final logDir = Directory.systemTemp.createTempSync('fmp_empty_states_');
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

    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final widths = mac ? ['wide', 'medium'] : ['narrow'];
    for (final width in widths) {
      if (mac) {
        await run.system('resize-$width', 'resize', [
          width == 'wide' ? '1280x800' : '960x720',
        ]);
        await settle();
      }
      for (final b in [Brightness.light, Brightness.dark]) {
        binding.platformDispatcher.platformBrightnessTestValue = b;
        await settle();
        final tag = '$width-${b.name}';
        await openDestination(tester, Destination.library);
        await run.step('$tag-library');
        await openDestination(tester, Destination.queue);
        await run.step('$tag-queue');
        await openSearch(tester);
        const query = '夜行列車 鋼琴四手聯彈 2019';
        search.show(
          SearchState(
            query: query,
            sources: [
              SourceResults(manifest: manifest, pages: const [[]], isEnd: true),
            ],
          ),
        );
        container.read(searchQueryProvider).text = query;
        await settle();
        await run.step('$tag-search');
        // 下一輪從分頁開始：清掉欄位，手機的搜尋圓鈕才回到分頁列。
        search.show(null);
        container.read(searchQueryProvider).text = '';
        await openDestination(tester, Destination.home);
        await settle();
      }
    }
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
    await tester.runAsync(() async {
      await host.close();
      await log.close();
    });
    logDir.deleteSync(recursive: true);
  });
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
