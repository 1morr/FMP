import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/import/legacy_imports_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/legacy_import/legacy_converter.dart';
import 'package:fmp/legacy_import/legacy_settings_converter.dart';
import 'package:fmp/legacy_import/skip_reason.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/plugins/plugin_onboarding.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../support/plugin_page_harness.dart';

// 首次啟動匯入之後的結果對話框（M5 design §7.3）：有未看過的紀錄才出現、
// 「知道了」與「安裝音源」都標成看過了、只在有插件還沒裝時給「安裝音源」。

ImportSummary _summary({
  List<String> relogin = const ['netease'],
}) => ImportSummary(
  collections: {
    SummaryCollection.playlists: const CollectionSummary(
      read: 4,
      written: 3,
      skipped: {'mixWithoutSeed': 1},
      notes: {'remoteNotRecognized': 2, 'duplicateRemote': 1},
    ),
    SummaryCollection.tracks: const CollectionSummary(read: 12, written: 11),
    SummaryCollection.history: const CollectionSummary(read: 5, written: 5),
    SummaryCollection.radioStations: const CollectionSummary(
      read: 2,
      written: 2,
    ),
    SummaryCollection.accounts: const CollectionSummary(read: 1, written: 1),
  },
  unimportedSettings: const [UnimportedSetting.cacheLimit, 'future'],
  reloginPlatforms: relogin,
);

void main() {
  test('the keys the dialog reads are the converter\'s identifiers', () {
    // 對話框（lib/ui）不能 import 封住的轉換器，字面值寫在自己的檔案裡：這裡對照。
    expect(SummaryCollection.tracks, 'tracks');
    expect(SummaryCollection.playlists, 'playlists');
    expect(SummaryCollection.history, 'history');
    expect(SummaryCollection.radioStations, 'radioStations');
    expect(SummaryCollection.accounts, 'accounts');
    expect(SkipReason.remoteNotRecognized.name, 'remoteNotRecognized');
    expect(SkipReason.duplicateRemote.name, 'duplicateRemote');
    expect(UnimportedSetting.streamPriority, 'streamPriority');
    expect(UnimportedSetting.cacheLimit, 'cacheLimit');
    expect(UnimportedSetting.homeRanking, 'homeRanking');
    expect(UnimportedSetting.railExpanded, 'railExpanded');
    expect(UnimportedSetting.searchHistory, 'searchHistory');
  });

  Future<PluginPageHarness> open(
    WidgetTester tester, {
    ImportSummary? summary,
    String trackSource = 'bilibili',
    List<String> installed = const [],
  }) async {
    final h = await PluginPageHarness.create(tester, registrySources: true);
    await tester.runAsync(() async {
      for (final id in installed) {
        await h.plugins.install(id);
      }
      if (summary != null) {
        await h.plugins.database.customStatement(
          'INSERT INTO legacy_imports (source, imported_at, summary_json) '
          "VALUES ('database', 1790000000000, '${summary.encode()}')",
        );
      }
      await TracksRepository(h.plugins.database).upsert([
        TrackInfo(
          sourceTypeId: trackSource,
          sourceId: 'x',
          title: 'Song',
          uploader: 'Uploader',
        ),
      ]);
    });
    await h.shell.pumpShell(tester, at: ShellDestination.home);
    await h.settle(tester);
    return h;
  }

  testWidgets('shows nothing without an unseen record', (tester) async {
    await open(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('lists what was imported and what was not, and "Got it" marks it '
      'seen', (tester) async {
    final h = await open(tester, summary: _summary());

    expect(find.text('Data imported from the old version'), findsOneWidget);
    expect(find.text('Playlists: 3'), findsOneWidget);
    expect(find.text('Tracks: 11'), findsOneWidget);
    expect(find.text('Play history: 5'), findsOneWidget);
    expect(find.text('Radio stations: 2'), findsOneWidget);
    expect(find.text('Accounts: 1'), findsOneWidget);
    expect(find.text('Sign in again: netease'), findsOneWidget);
    expect(find.textContaining('3 platform playlists'), findsOneWidget);
    expect(find.text("Settings that weren't imported"), findsOneWidget);
    expect(find.text('· Cache limit'), findsOneWidget);
    // 不認得的識別字原樣顯示，不吞掉。
    expect(find.text('· future'), findsOneWidget);
    // bilibili 還沒裝：提示並給「安裝音源」。
    expect(find.text('Install sources'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Got it'));
    await h.settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      await tester.runAsync(
        () =>
            LegacyImportsRepository(h.plugins.database).latestUnacknowledged(),
      ),
      isNull,
    );
  });

  testWidgets('"Install sources" marks it seen and reopens the onboarding', (
    tester,
  ) async {
    final h = await open(tester, summary: _summary());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    container.read(onboardingProvider.notifier).dismiss();
    expect(container.read(onboardingProvider).dismissed, isTrue);

    await tester.tap(find.widgetWithText(TextButton, 'Install sources'));
    await h.settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(container.read(onboardingProvider).dismissed, isFalse);
    expect(find.byType(HomePage).hitTestable(), findsOneWidget);
    expect(
      await tester.runAsync(
        () =>
            LegacyImportsRepository(h.plugins.database).latestUnacknowledged(),
      ),
      isNull,
    );
  });

  testWidgets('has no "Install sources" when every referenced plugin is '
      'installed', (tester) async {
    await open(
      tester,
      summary: _summary(relogin: const []),
      trackSource: 'plugin-a',
      installed: ['plugin-a'],
    );
    expect(find.text('Data imported from the old version'), findsOneWidget);
    expect(find.text('Install sources'), findsNothing);
    expect(find.textContaining('Sign in again'), findsNothing);
  });
}
