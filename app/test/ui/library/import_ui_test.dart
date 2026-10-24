import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/library/playlist_importer.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/library/import_preview_page.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/library/manual_refresh.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../../library/fake_import_plugin.dart';
import '../support/shell_harness.dart';

// 匯入對話框、手動刷新、詳情的狀態列、已失效標記與匯入歌單的編輯（M4 PR 8b，design §5.1、
// §5.3、§10.3–§10.5、§10.8）。插件是 `FakeImportPlugin`（id `fmp-test`，外殼的 harness 把介面上的名稱固定為 `Test Source`），
// 它就是插件清單；網址 `https://fmp.test/<id>` 認成歌單 `<id>`。

FakeImportPlugin _plugin({
  bool resolveStream = true,
  FutureOr<PlaylistPage> Function(PlaylistPageQuery query)? onPage,
}) => FakeImportPlugin(
  resolveStream: resolveStream,
  onPage: onPage ?? (_) => page(['a', 'b', 'c']),
  onUrl: (query) {
    final uri = Uri.tryParse(query.url);
    return uri != null && uri.host == 'fmp.test' && uri.pathSegments.length == 1
        ? PlaylistIdRef(uri.pathSegments.single)
        : null;
  },
);

Future<ShellHarness> _open(
  WidgetTester tester,
  FakeImportPlugin plugin, {
  Size size = const Size(400, 800),
  String? Function(Ref ref, String pluginId)? sourceUnavailable,
}) async {
  final h = ShellHarness(
    registryOfSources: true,
    sources: [plugin],
    sourceUnavailable: sourceUnavailable ?? (ref, pluginId) => null,
  );
  await h.pumpShell(tester, size: size, at: ShellDestination.library);
  await _settle(tester, h);
  return h;
}

/// 資料庫的寫入與重讀跑完。
Future<void> _settle(WidgetTester tester, ShellHarness h) async {
  for (var i = 0; i < 3; i++) {
    await h.loadSettings(tester);
  }
  await tester.pumpAndSettle();
}

PlaylistRepository _repository(WidgetTester tester, ShellHarness h) =>
    h.container(tester).read(playlistRepositoryProvider);

/// 以匯入器匯入 `https://fmp.test/<id>`，回傳歌單 id。
Future<int> _import(WidgetTester tester, ShellHarness h, String id) async {
  final result = await tester.runAsync(
    () => h
        .container(tester)
        .read(playlistImporterProvider)
        .importUrl('https://fmp.test/$id'),
  );
  await _settle(tester, h);
  return (result! as ImportedPlaylist).playlistId;
}

Future<RefreshOutcome> _refresh(
  WidgetTester tester,
  ShellHarness h,
  int id,
) async {
  final outcome = (await tester.runAsync(
    () => h.container(tester).read(playlistRefresherProvider).refresh(id),
  ))!;
  await _settle(tester, h);
  return outcome;
}

Future<PlaylistRemote> _remote(
  WidgetTester tester,
  ShellHarness h,
  int id,
) async => (await tester.runAsync(() => _repository(tester, h).remote(id)))!;

Future<Playlist> _playlist(WidgetTester tester, ShellHarness h, int id) async =>
    (await tester.runAsync(() => _repository(tester, h).find(id)))!;

Future<List<String>> _songs(
  WidgetTester tester,
  ShellHarness h,
  int id,
) async => [
  for (final entry in (await tester.runAsync(
    () => _repository(tester, h).entries(id),
  ))!)
    entry.track.sourceId,
];

Future<void> _openDetail(
  WidgetTester tester,
  ShellHarness h,
  String name,
) async {
  await tester.tap(find.text(name));
  await _settle(tester, h);
  expect(find.byType(PlaylistDetailPage), findsOneWidget);
}

/// 讓真的非同步（資料庫、匯入）往前跑一下，再重畫。[settle] 為假時不等動畫停（進度條會一直轉）。
Future<void> _advance(
  WidgetTester tester,
  ShellHarness h, {
  bool settle = true,
}) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pump();
  if (settle) {
    await _settle(tester, h);
  } else {
    await h.loadSettings(tester);
  }
}

Future<void> _openImportDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Import a playlist'));
  await tester.pumpAndSettle();
  expect(find.widgetWithText(AlertDialog, 'Import a playlist'), findsOneWidget);
}

Future<void> _enterUrl(WidgetTester tester, String url) async {
  await tester.enterText(find.widgetWithText(TextField, 'Link'), url);
  await tester.pump();
}

VoidCallback? _importButton(WidgetTester tester) => tester
    .widget<FilledButton>(find.widgetWithText(FilledButton, 'Import'))
    .onPressed;

ButtonStyleButton _button(WidgetTester tester, String label) => tester.widget(
  find.ancestor(
    of: find.text(label),
    matching: find.bySubtype<ButtonStyleButton>(),
  ),
);

Future<void> _openMenu(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(
      of: find
          .ancestor(of: find.text(name), matching: find.byType(ListTile))
          .first,
      matching: find.byTooltip('More options'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the import dialog', () {
    testWidgets('a known link imports the playlist and opens its details '
        'inside Library', (tester) async {
      final plugin = _plugin(
        onPage: (_) => page(['a', 'b'], title: 'Road mix', ownerName: 'Alice'),
      );
      final h = await _open(tester, plugin);

      await _openImportDialog(tester);
      expect(_importButton(tester), isNull, reason: 'nothing typed yet');
      await _enterUrl(tester, 'https://fmp.test/p1');
      expect(_importButton(tester), isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pump();
      await _advance(tester, h);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(PlaylistDetailPage), findsOneWidget);
      expect(find.byType(LibraryPage).hitTestable(), findsNothing);
      expect(find.text('Road mix'), findsOneWidget);
      expect(find.text('Imported · 2 songs'), findsOneWidget);
      // 擁有者與音源。
      expect(find.text('Test Source · Alice'), findsOneWidget);
      expect(find.text('Playlist imported'), findsOneWidget);
      final remote = await _remote(tester, h, 1);
      expect(remote.remoteId, 'p1');
      expect(await _songs(tester, h, 1), ['a', 'b']);
      // 匯入歌單沒有重排的把手與移除（ADR 0019 §決定 4）。
      expect(find.byIcon(Icons.drag_handle), findsNothing);
      await tester.tap(find.byTooltip('More options').last);
      await tester.pumpAndSettle();
      expect(find.text('Remove from playlist'), findsNothing);
    });

    testWidgets('the progress is determinate with a total, shows the '
        'current title and can be cancelled', (tester) async {
      final second = Completer<PlaylistPage>();
      final plugin = _plugin(
        onPage: (query) => query.cursor == null
            ? page(['a', 'b'], cursor: 'c2', total: 3)
            : second.future,
      );
      final h = await _open(tester, plugin);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/p1');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h, settle: false);

      expect(find.text('Imported 2 of 3'), findsOneWidget);
      expect(find.text('Song b'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(2 / 3, 0.001),
      );
      // 進行中不能關、不能再送，只能取消。
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNotNull,
      );
      expect(_importButton(tester), isNull);

      second.complete(page(['c'], total: 3));
      await _advance(tester, h);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Imported · 3 songs'), findsOneWidget);
    });

    testWidgets('without a total the bar is indeterminate and says how many '
        'songs were read', (tester) async {
      final second = Completer<PlaylistPage>();
      final plugin = _plugin(
        onPage: (query) => query.cursor == null
            ? page(['a', 'b'], cursor: 'c2')
            : second.future,
      );
      final h = await _open(tester, plugin);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/p1');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h, settle: false);

      expect(find.text('Songs read: 2'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );

      second.complete(page(['c']));
      await _advance(tester, h);
    });

    testWidgets('cancelling after a page keeps what was written and says so', (
      tester,
    ) async {
      final second = Completer<PlaylistPage>();
      final plugin = _plugin(
        onPage: (query) => query.cursor == null
            ? page(['a', 'b'], cursor: 'c2', total: 5)
            : second.future,
      );
      final h = await _open(tester, plugin);
      final toasts = <String>[];
      final subscription = h.toaster.toasts.listen(
        (t) => toasts.add(t.message),
      );
      addTearDown(subscription.cancel);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/p1');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h, settle: false);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      second.complete(page(['c', 'd', 'e'], total: 5));
      await _advance(tester, h);

      expect(find.byType(AlertDialog), findsNothing);
      expect(toasts, ['Cancelled; kept 2']);
      expect(await _songs(tester, h, 1), ['a', 'b']);
      expect(
        (await _remote(tester, h, 1)).lastResult,
        PlaylistRefreshResult.partial,
      );
    });

    testWidgets('cancelling before the first page leaves no playlist', (
      tester,
    ) async {
      final first = Completer<PlaylistPage>();
      final plugin = _plugin(onPage: (_) => first.future);
      final h = await _open(tester, plugin);
      final toasts = <String>[];
      final subscription = h.toaster.toasts.listen(
        (t) => toasts.add(t.message),
      );
      addTearDown(subscription.cancel);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/p1');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h, settle: false);
      expect(find.text('Looking up the link…'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      first.complete(page(['a', 'b'], total: 2));
      await _advance(tester, h);

      expect(find.byType(AlertDialog), findsNothing);
      expect(toasts, ['Import cancelled']);
      final all = await tester.runAsync(
        () => _repository(tester, h).watchAll().first,
      );
      expect(all, isEmpty);
    });

    testWidgets('a link no source knows says so and creates nothing', (
      tester,
    ) async {
      final plugin = _plugin();
      final h = await _open(tester, plugin);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://elsewhere.test/x/y');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h);

      expect(
        find.text("This link isn't recognized by any installed source"),
        findsOneWidget,
      );
      // 對話框留著、輸入留著，可以改了再送。
      expect(find.widgetWithText(AlertDialog, 'Import a playlist'), findsOne);
      expect(find.text('https://elsewhere.test/x/y'), findsOneWidget);
      expect(_importButton(tester), isNotNull);
      expect(
        await tester.runAsync(() => _repository(tester, h).watchAll().first),
        isEmpty,
      );
    });

    testWidgets('a failing first page shows the error and creates nothing', (
      tester,
    ) async {
      final plugin = _plugin(
        onPage: (_) => throw NotFound(pluginId: 'fmp-test'),
      );
      final h = await _open(tester, plugin);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/gone');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h);

      expect(find.textContaining("Couldn't import: "), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        await tester.runAsync(() => _repository(tester, h).watchAll().first),
        isEmpty,
      );
    });

    testWidgets('a failing first page offline says offline', (tester) async {
      final plugin = _plugin(onPage: (_) => throw NetworkError());
      final h = await _open(tester, plugin);
      await h.setNetwork(tester, NetworkStatus.noInterface);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/p1');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h);

      expect(
        find.text("Couldn't import: No network connection"),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(() => _repository(tester, h).watchAll().first),
        isEmpty,
      );
    });

    // Mix 網址（PR 11）：問插件的 `mix` 一次，建一張 Mix 歌單並開詳情；不存曲目。
    testWidgets('a Mix link creates a Mix playlist and opens its details', (
      tester,
    ) async {
      final plugin = FakeImportPlugin(
        mix: true,
        onUrl: (_) => PlaylistMixSeedRef(MixSeedQuery(sourceId: 'seed')),
        onMix: (_) => const MixBatch(
          mixId: 'm1',
          title: 'Chill',
          tracks: [
            TrackSummary(sourceTypeId: 'fmp-test', sourceId: 'x', title: 'X'),
          ],
        ),
      );
      final h = await _open(tester, plugin);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/m');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h);

      expect(plugin.mixQueries, hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(PlaylistDetailPage), findsOneWidget);
      expect(find.text('Chill'), findsOneWidget);
      final stored = (await _playlist(tester, h, 1));
      expect(stored.kind, PlaylistKind.mix);
      expect(stored.name, 'Chill');
      expect(stored.mixPluginId, 'fmp-test');
      expect(stored.mixSeedSourceId, 'seed');
    });

    testWidgets('a failing mix shows the error and creates nothing', (
      tester,
    ) async {
      final plugin = FakeImportPlugin(
        mix: true,
        onUrl: (_) => PlaylistMixSeedRef(MixSeedQuery(sourceId: 'seed')),
        onMix: (_) => throw NotFound(pluginId: 'fmp-test'),
      );
      final h = await _open(tester, plugin);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/m');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h);

      expect(find.textContaining("Couldn't import: "), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        await tester.runAsync(() => _repository(tester, h).watchAll().first),
        isEmpty,
      );
    });

    testWidgets('a failing mix offline says offline', (tester) async {
      final plugin = FakeImportPlugin(
        mix: true,
        onUrl: (_) => PlaylistMixSeedRef(MixSeedQuery(sourceId: 'seed')),
        onMix: (_) => throw NetworkError(),
      );
      final h = await _open(tester, plugin);
      await h.setNetwork(tester, NetworkStatus.noInterface);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/m');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h);

      expect(
        find.text("Couldn't import: No network connection"),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(() => _repository(tester, h).watchAll().first),
        isEmpty,
      );
    });

    // 僅元資料來源（M4 PR 19，design §10.8）：關閉對話框、在音樂庫的巢狀導覽裡開匯入預覽，
    // 不建任何歌單。
    testWidgets('a metadata-only source opens the import preview inside '
        'Library', (tester) async {
      final h = await _open(tester, _plugin(resolveStream: false));

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/p1');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ImportPreviewPage), findsOneWidget);
      expect(find.byType(LibraryPage).hitTestable(), findsNothing);
      expect(find.text('Remote title'), findsOneWidget);
      expect(
        await tester.runAsync(() => _repository(tester, h).watchAll().first),
        isEmpty,
      );
    });

    // 能播的插件的歌單（§17 第 19 條）：認出網址後多一個選擇，預設是匯入為平台歌單。
    testWidgets('a playable source offers matching, with the platform '
        'playlist as the default', (tester) async {
      final plugin = _plugin();
      final h = await _open(tester, plugin);

      await _openImportDialog(tester);
      expect(find.byType(RadioListTile<bool>), findsNothing);
      await _enterUrl(tester, 'https://fmp.test/p1');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('Import as a platform playlist'), findsOneWidget);
      expect(
        find.text('Refreshes from the playlist on Test Source'),
        findsOneWidget,
      );
      expect(find.text('Match to other sources'), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>))
            .groupValue,
        isFalse,
      );
      expect(plugin.pageQueries, isEmpty, reason: 'only recognised');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h);

      expect(find.byType(PlaylistDetailPage), findsOneWidget);
      expect(find.byType(ImportPreviewPage), findsNothing);
      expect((await _remote(tester, h, 1)).remoteId, 'p1');
      expect(plugin.urlQueries, hasLength(1), reason: 'recognised once');
    });

    testWidgets('choosing to match opens the preview and imports no platform '
        'playlist', (tester) async {
      final plugin = _plugin();
      final h = await _open(tester, plugin);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/p1');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.tap(find.text('Match to other sources'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ImportPreviewPage), findsOneWidget);
      expect(find.byType(PlaylistDetailPage), findsNothing);
      expect(
        await tester.runAsync(() => _repository(tester, h).watchAll().first),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => _repository(tester, h).findRemote('fmp-test', 'p1'),
        ),
        isNull,
      );
    });

    testWidgets('a Mix link and a link nobody knows offer no choice', (
      tester,
    ) async {
      final plugin = FakeImportPlugin(
        mix: true,
        onUrl: (query) => query.url.endsWith('/m')
            ? PlaylistMixSeedRef(MixSeedQuery(sourceId: 'seed'))
            : null,
      );
      await _open(tester, plugin);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/m');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(RadioListTile<bool>), findsNothing);
      await _enterUrl(tester, 'https://example.com/x');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(RadioListTile<bool>), findsNothing);
      expect(plugin.urlQueries.map((q) => q.url), [
        'https://fmp.test/m',
        'https://example.com/x',
      ]);
    });

    // 辨識還在進行時按「匯入」：那次辨識的結果被丟掉；匯入失敗之後，同一段輸入照樣會再辨識（審查）。
    testWidgets('a recognition dropped by a failed import runs again for the '
        'same link', (tester) async {
      final recognising = Completer<PlaylistRef?>();
      final importing = Completer<PlaylistRef?>();
      var calls = 0;
      final plugin = FakeImportPlugin(
        onUrl: (_) => switch (++calls) {
          1 => recognising.future,
          2 => importing.future,
          _ => PlaylistIdRef('p1'),
        },
      );
      final h = await _open(tester, plugin);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/p1');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pump();
      recognising.complete(PlaylistIdRef('p1'));
      await tester.pump();
      importing.completeError(NetworkError(pluginId: 'fmp-test'));
      await _advance(tester, h);
      expect(find.textContaining("Couldn't import"), findsOneWidget);
      expect(find.byType(RadioListTile<bool>), findsNothing);

      // 點一下欄位（只改了游標）：同一段輸入再辨識一次。
      await tester.tap(find.widgetWithText(TextField, 'Link'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(calls, 3);
      expect(find.text('Match to other sources'), findsOneWidget);
    });

    testWidgets('editing the link drops the choice until it is recognised '
        'again', (tester) async {
      final plugin = _plugin();
      await _open(tester, plugin);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/p1');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.tap(find.text('Match to other sources'));
      await tester.pump();

      await _enterUrl(tester, 'https://fmp.test/p2');
      expect(find.byType(RadioListTile<bool>), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(
        tester
            .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>))
            .groupValue,
        isFalse,
        reason: 'back to the default for a new link',
      );
    });

    testWidgets('importing a link already in the library refreshes that '
        'playlist and opens it', (tester) async {
      final plugin = _plugin(onPage: (_) => page(['a'], title: 'Same'));
      final h = await _open(tester, plugin);
      await _import(tester, h, 'p1');
      await _settle(tester, h);

      await _openImportDialog(tester);
      await _enterUrl(tester, 'https://fmp.test/p1');
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await _advance(tester, h);

      expect(find.byType(PlaylistDetailPage), findsOneWidget);
      expect(find.text('Playlist refreshed'), findsOneWidget);
      expect(
        await tester.runAsync(() => _repository(tester, h).watchAll().first),
        hasLength(1),
      );
    });
  });

  group('refreshing', () {
    testWidgets('the Refresh button reads the playlist again and tells '
        'the result', (tester) async {
      var ids = ['a', 'b'];
      final plugin = _plugin(onPage: (_) => page(ids));
      final h = await _open(tester, plugin);
      final id = await _import(tester, h, 'p1');
      await _openDetail(tester, h, 'Remote title');
      expect(await _songs(tester, h, id), ['a', 'b']);

      ids = ['b', 'c', 'd'];
      await tester.tap(find.widgetWithText(OutlinedButton, 'Refresh'));
      await _advance(tester, h);

      expect(await _songs(tester, h, id), ['b', 'c', 'd']);
      expect(find.text('Playlist refreshed'), findsOneWidget);
      expect(find.text('Imported · 3 songs'), findsOneWidget);
    });

    testWidgets('while refreshing the button shows progress and a second '
        'press does nothing', (tester) async {
      final gate = Completer<PlaylistPage>();
      var slow = false;
      final plugin = _plugin(onPage: (_) => slow ? gate.future : page(['a']));
      final h = await _open(tester, plugin);
      await _import(tester, h, 'p1');
      await _openDetail(tester, h, 'Remote title');
      final before = plugin.pageQueries.length;

      slow = true;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Refresh'));
      await _advance(tester, h, settle: false);

      expect(find.text('Refreshing…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_button(tester, 'Refreshing…').onPressed, isNull);
      expect(plugin.pageQueries.length, before + 1);

      gate.complete(page(['a']));
      await _advance(tester, h);

      expect(find.text('Refresh'), findsOneWidget);
      expect(_button(tester, 'Refresh').onPressed, isNotNull);
      expect(plugin.pageQueries.length, before + 1);
    });

    testWidgets('the card shows how many songs were '
        'updated', (tester) async {
      final gate = Completer<PlaylistPage>();
      var slow = false;
      final plugin = _plugin(
        onPage: (query) => !slow
            ? page(['a'])
            : query.cursor == null
            ? page(['a', 'b'], cursor: 'c2', total: 4)
            : gate.future,
      );
      final h = await _open(tester, plugin);
      final id = await _import(tester, h, 'p1');
      final manual = h.container(tester).read(manualRefreshProvider.notifier);

      slow = true;
      unawaited(manual(id));
      await _advance(tester, h, settle: false);

      // The card on the library page.
      expect(find.text('2 of 4 updated'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete(page(['c', 'd'], total: 4));
      await _advance(tester, h);
      await _advance(tester, h);

      expect(find.textContaining('updated'), findsNothing);
    });

    testWidgets('a second request for the same playlist while one runs is '
        'dropped', (tester) async {
      final gate = Completer<PlaylistPage>();
      var slow = false;
      final plugin = _plugin(onPage: (_) => slow ? gate.future : page(['a']));
      final h = await _open(tester, plugin);
      final id = await _import(tester, h, 'p1');
      final before = plugin.pageQueries.length;
      final manual = h.container(tester).read(manualRefreshProvider.notifier);

      slow = true;
      // 卡片選單、詳情與「重試」都經這裡：不靠按鈕停用。
      unawaited(manual(id));
      unawaited(manual(id));
      await _advance(tester, h, settle: false);
      gate.complete(page(['a']));
      await _advance(tester, h);
      await _advance(tester, h);

      expect(plugin.pageQueries.length, before + 1);
    });

    testWidgets('the card menu has Refresh for an imported playlist only', (
      tester,
    ) async {
      final plugin = _plugin();
      final h = await _open(tester, plugin);
      await tester.runAsync(() => _repository(tester, h).create(name: 'Mine'));
      final id = await _import(tester, h, 'p1');

      await _openMenu(tester, 'Mine');
      expect(find.widgetWithText(MenuItemButton, 'Refresh'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await _openMenu(tester, 'Remote title');
      expect(find.widgetWithText(MenuItemButton, 'Refresh'), findsOneWidget);
      // 匯入歌單的卡片寫「匯入」。
      expect(find.text('Imported · 3 songs'), findsOneWidget);
      final before = plugin.pageQueries.length;
      await tester.tap(find.widgetWithText(MenuItemButton, 'Refresh'));
      await _advance(tester, h);

      expect(plugin.pageQueries.length, before + 1);
      expect(find.text('Playlist refreshed'), findsOneWidget);
      expect((await _remote(tester, h, id)).lastResult, isNotNull);
    });

    testWidgets('a failed manual refresh says why', (tester) async {
      var fail = false;
      final plugin = _plugin(
        onPage: (_) => fail ? throw NetworkError() : page(['a']),
      );
      final h = await _open(tester, plugin);
      await _import(tester, h, 'p1');
      await _openDetail(tester, h, 'Remote title');

      fail = true;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Refresh'));
      await _advance(tester, h);

      expect(find.textContaining("Couldn't refresh the playlist: "), findsOne);
      // 本機的資料照常。
      expect(find.text('Imported · 1 song'), findsOneWidget);
    });

    testWidgets('a failed manual refresh while offline says offline', (
      tester,
    ) async {
      var fail = false;
      final plugin = _plugin(
        onPage: (_) => fail ? throw NetworkError() : page(['a']),
      );
      final h = await _open(tester, plugin);
      await _import(tester, h, 'p1');
      await _openDetail(tester, h, 'Remote title');
      await h.setNetwork(tester, NetworkStatus.unreachable);

      fail = true;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Refresh'));
      await _advance(tester, h);

      expect(find.text("Offline, couldn't refresh the playlist"), findsOne);
      expect(
        find.textContaining("Couldn't refresh the playlist: "),
        findsNothing,
      );
    });

    testWidgets('a source that is gone says so, and refresh is unavailable', (
      tester,
    ) async {
      final plugin = _plugin();
      final h = await _open(
        tester,
        plugin,
        sourceUnavailable: (ref, pluginId) =>
            pluginId == 'gone' ? 'Source not installed' : null,
      );
      await tester.runAsync(
        () => _repository(tester, h).createImported(
          pluginId: 'gone',
          remoteId: 'r',
          info: const RemotePlaylistInfo(name: 'Orphan'),
        ),
      );
      await _settle(tester, h);
      await _openDetail(tester, h, 'Orphan');

      // 狀態列是 `sourceUnavailableProvider` 的字樣；「刷新」停用。
      expect(find.text('Source not installed'), findsOneWidget);
      expect(_button(tester, 'Refresh').onPressed, isNull);
    });
  });

  group('the status bar', () {
    /// 開在音樂庫、已匯入一張；回傳的函式切換測試插件的行為（'ok'、'partial'、'failed'、
    /// 'gone'、'auth'）。
    Future<(ShellHarness, int, FakeImportPlugin, void Function(String))>
    openWith(WidgetTester tester) async {
      var mode = 'ok';
      final plugin = _plugin();
      plugin.onPage = (query) => switch (mode) {
        'ok' => page(['a', 'b']),
        'partial' when query.cursor == null => page(['a', 'b'], cursor: 'c2'),
        'partial' => throw NetworkError(),
        'failed' => throw NetworkError(),
        'gone' => throw NotFound(pluginId: 'fmp-test'),
        'auth' => throw AuthRequired(pluginId: 'fmp-test'),
        _ => throw StateError(mode),
      };
      final h = await _open(tester, plugin);
      final id = await _import(tester, h, 'p1');
      return (h, id, plugin, (String value) => mode = value);
    }

    testWidgets('normal: the time of the last refresh', (tester) async {
      final (h, _, _, _) = await openWith(tester);
      await _openDetail(tester, h, 'Remote title');

      expect(find.textContaining('Last refreshed: '), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('partial: says so and keeps every song', (tester) async {
      final (h, id, _, setMode) = await openWith(tester);
      setMode('partial');
      await _refresh(tester, h, id);
      await _openDetail(tester, h, 'Remote title');

      expect(find.textContaining('Last refreshed: partial · '), findsOne);
      expect(find.text('Retry'), findsNothing);
      expect(await _songs(tester, h, id), ['a', 'b']);
    });

    testWidgets('failed: says so, and Retry is a manual refresh', (
      tester,
    ) async {
      final (h, id, plugin, setMode) = await openWith(tester);
      setMode('failed');
      await _refresh(tester, h, id);
      await _openDetail(tester, h, 'Remote title');

      expect(find.text('Refresh failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // 不經手動刷新（自動刷新那條）的失敗只更新狀態列，不跳提示（ADR 0013 §決定 5）。
      expect(
        find.textContaining("Couldn't refresh the playlist"),
        findsNothing,
      );
      // 失敗不碰項目。
      expect(await _songs(tester, h, id), ['a', 'b']);

      setMode('ok');
      final before = plugin.pageQueries.length;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await _advance(tester, h);

      expect(plugin.pageQueries.length, before + 1);
      expect(find.text('Refresh failed'), findsNothing);
      expect(find.textContaining('Last refreshed: '), findsOneWidget);
      expect(find.text('Playlist refreshed'), findsOneWidget);
    });

    testWidgets('source gone: says so, and Retry refreshes again', (
      tester,
    ) async {
      final (h, id, plugin, setMode) = await openWith(tester);
      setMode('gone');
      await _refresh(tester, h, id);
      await _openDetail(tester, h, 'Remote title');

      expect(
        find.text(
          'Source gone: the remote playlist was deleted or is no longer '
          'accessible',
        ),
        findsOneWidget,
      );
      expect(
        (await _remote(tester, h, id)).status,
        PlaylistRemoteStatus.sourceGone,
      );
      // 本機的副本照常。
      expect(await _songs(tester, h, id), ['a', 'b']);

      setMode('ok');
      final before = plugin.pageQueries.length;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await _advance(tester, h);

      expect(plugin.pageQueries.length, before + 1);
      expect(find.textContaining('Source gone'), findsNothing);
      expect(
        (await _remote(tester, h, id)).status,
        PlaylistRemoteStatus.active,
      );
    });

    // `status` 與 `last_result` 各自寫入（失敗不動 `last_result`）：兩者交叉時 `status` 優先。
    testWidgets('source gone outranks an earlier partial result', (
      tester,
    ) async {
      final (h, id, _, setMode) = await openWith(tester);
      setMode('partial');
      await _refresh(tester, h, id);
      setMode('gone');
      await _refresh(tester, h, id);
      final remote = await _remote(tester, h, id);
      expect(remote.status, PlaylistRemoteStatus.sourceGone);
      expect(remote.lastResult, PlaylistRefreshResult.partial);
      await _openDetail(tester, h, 'Remote title');

      expect(find.textContaining('Source gone'), findsOneWidget);
      expect(find.textContaining('partial'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('sign-in needed outranks an earlier failure', (tester) async {
      final (h, id, _, setMode) = await openWith(tester);
      setMode('failed');
      await _refresh(tester, h, id);
      setMode('auth');
      await _refresh(tester, h, id);
      final remote = await _remote(tester, h, id);
      expect(remote.status, PlaylistRemoteStatus.authRequired);
      expect(remote.lastResult, PlaylistRefreshResult.failed);
      await _openDetail(tester, h, 'Remote title');

      expect(find.text('Sign in to refresh this playlist'), findsOneWidget);
      expect(find.text('Refresh failed'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a playlist never refreshed says so', (tester) async {
      final h = await _open(tester, _plugin());
      await tester.runAsync(
        () => _repository(tester, h).createImported(
          pluginId: 'fmp-test',
          remoteId: 'r',
          info: const RemotePlaylistInfo(name: 'Fresh'),
        ),
      );
      await _settle(tester, h);
      await _openDetail(tester, h, 'Fresh');

      expect(find.text('Not refreshed yet'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('sign-in needed: Sign in opens the accounts', (tester) async {
      final (h, id, _, setMode) = await openWith(tester);
      setMode('auth');
      await _refresh(tester, h, id);
      await _openDetail(tester, h, 'Remote title');

      expect(find.text('Sign in to refresh this playlist'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(SettingsPage).hitTestable(), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Sign in'));
      await tester.pumpAndSettle();

      // 換到設定頁的「帳號」區塊。
      expect(find.byType(SettingsPage).hitTestable(), findsOneWidget);
      expect(find.byType(PlaylistDetailPage).hitTestable(), findsNothing);
    });
  });

  group('the songs', () {
    testWidgets('an unavailable item is marked and still plays', (
      tester,
    ) async {
      final plugin = _plugin(onPage: (_) => page(['a', 'b'], unavailable: {1}));
      final h = await _open(tester, plugin);
      await _import(tester, h, 'p1');
      await _openDetail(tester, h, 'Remote title');

      final marked = find.ancestor(
        of: find.text('Song b', findRichText: true),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: marked, matching: find.text('Unavailable')),
        findsOneWidget,
      );
      final other = find.ancestor(
        of: find.text('Song a'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: other, matching: find.text('Unavailable')),
        findsNothing,
      );

      await tester.tap(find.text('Song b'));
      await tester.pump();

      expect(h.controller.queue.mode, QueueMode.temporary);
      expect(h.controller.queue.current?.sourceId, 'b');
    });
  });

  group('editing an imported playlist', () {
    Future<(ShellHarness, int, FakeImportPlugin)> openImported(
      WidgetTester tester,
    ) async {
      final plugin = _plugin(
        onPage: (_) =>
            page(['a'], title: 'Remote name', description: 'Remote text'),
      );
      final h = await _open(tester, plugin);
      final id = await _import(tester, h, 'p1');
      return (h, id, plugin);
    }

    Future<void> openEdit(WidgetTester tester, String name) async {
      await _openMenu(tester, name);
      await tester.tap(find.widgetWithText(MenuItemButton, 'Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit playlist'), findsOneWidget);
    }

    Future<void> save(WidgetTester tester, ShellHarness h) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _advance(tester, h);
    }

    testWidgets('saving without a change overrides nothing', (tester) async {
      final (h, id, _) = await openImported(tester);

      await openEdit(tester, 'Remote name');
      expect(find.text("Use the remote's"), findsNothing);
      await save(tester, h);

      final remote = await _remote(tester, h, id);
      expect(remote.nameOverridden, isFalse);
      expect(remote.descriptionOverridden, isFalse);
      expect(remote.artworkOverridden, isFalse);
    });

    testWidgets('a changed name is kept by the next refresh; the other '
        'fields still follow the remote', (tester) async {
      final (h, id, plugin) = await openImported(tester);

      await openEdit(tester, 'Remote name');
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mine');
      await tester.pump();
      await save(tester, h);

      var remote = await _remote(tester, h, id);
      expect(remote.nameOverridden, isTrue);
      expect(remote.descriptionOverridden, isFalse);
      expect(remote.artworkOverridden, isFalse);

      plugin.onPage = (_) =>
          page(['a'], title: 'Remote renamed', description: 'Remote text 2');
      await _refresh(tester, h, id);

      final playlist = await _playlist(tester, h, id);
      expect(playlist.name, 'Mine');
      expect(playlist.description, 'Remote text 2');
    });

    testWidgets('a changed description and a custom cover set their own '
        'flags', (tester) async {
      final (h, id, _) = await openImported(tester);

      await openEdit(tester, 'Remote name');
      await tester.enterText(
        find.widgetWithText(TextField, 'Description (optional)'),
        'Mine',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Custom'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Image URL'),
        'https://img.fmp.test/c.jpg',
      );
      await tester.pump();
      await save(tester, h);

      final remote = await _remote(tester, h, id);
      expect(remote.nameOverridden, isFalse);
      expect(remote.descriptionOverridden, isTrue);
      expect(remote.artworkOverridden, isTrue);
    });

    testWidgets('"Use the remote\'s" clears the flag and the next refresh '
        'writes the remote value back', (tester) async {
      final (h, id, plugin) = await openImported(tester);
      await openEdit(tester, 'Remote name');
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mine');
      await tester.pump();
      await save(tester, h);
      expect((await _remote(tester, h, id)).nameOverridden, isTrue);

      await openEdit(tester, 'Mine');
      // 被覆寫的欄位才有這顆鈕。
      expect(find.text("Use the remote's"), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, "Use the remote's"));
      await tester.pump();
      expect(
        find.text("Takes the remote's value on the next refresh"),
        findsOneWidget,
      );
      await save(tester, h);

      expect((await _remote(tester, h, id)).nameOverridden, isFalse);
      // 值先留著，下一次刷新才寫回。
      expect((await _playlist(tester, h, id)).name, 'Mine');
      plugin.onPage = (_) => page(['a'], title: 'Remote name');
      await _refresh(tester, h, id);
      expect((await _playlist(tester, h, id)).name, 'Remote name');
    });

    testWidgets('editing the field again after "Use the remote\'s" keeps '
        'the override', (tester) async {
      final (h, id, _) = await openImported(tester);
      await openEdit(tester, 'Remote name');
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mine');
      await tester.pump();
      await save(tester, h);

      await openEdit(tester, 'Mine');
      await tester.tap(find.widgetWithText(TextButton, "Use the remote's"));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mine 2');
      await tester.pump();
      expect(find.text("Use the remote's"), findsOneWidget);
      await save(tester, h);

      expect((await _remote(tester, h, id)).nameOverridden, isTrue);
      expect((await _playlist(tester, h, id)).name, 'Mine 2');
    });

    testWidgets('the auto refresh interval starts at 24 hours and can be '
        'changed, then switched off', (tester) async {
      final (h, id, _) = await openImported(tester);
      expect((await _remote(tester, h, id)).refreshIntervalHours, 24);

      await openEdit(tester, 'Remote name');
      expect(find.text('Auto refresh'), findsOneWidget);
      expect(find.text('Every day'), findsOneWidget);
      await tester.tap(find.text('Every day'));
      await tester.pumpAndSettle();
      for (final label in [
        'Off',
        'Every hour',
        'Every 6 hours',
        'Every 12 hours',
        'Every day',
        'Every 2 days',
        'Every 3 days',
        'Every 7 days',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tester.tap(find.text('Every 7 days').last);
      await tester.pumpAndSettle();
      await save(tester, h);
      expect((await _remote(tester, h, id)).refreshIntervalHours, 168);

      await openEdit(tester, 'Remote name');
      await tester.tap(find.text('Every 7 days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off').last);
      await tester.pumpAndSettle();
      await save(tester, h);
      expect((await _remote(tester, h, id)).refreshIntervalHours, isNull);

      // 不啟用的歌單，打開時顯示「Off」。
      await openEdit(tester, 'Remote name');
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('saving without touching the interval keeps it', (
      tester,
    ) async {
      final (h, id, _) = await openImported(tester);
      await tester.runAsync(
        () => _repository(tester, h).setRefreshInterval(id, 12),
      );
      await _settle(tester, h);

      await openEdit(tester, 'Remote name');
      expect(find.text('Every 12 hours'), findsOneWidget);
      await save(tester, h);

      expect((await _remote(tester, h, id)).refreshIntervalHours, 12);
    });

    testWidgets('an interval that is not one of the choices is shown, listed '
        'in order and kept', (tester) async {
      final (h, id, _) = await openImported(tester);
      await tester.runAsync(
        () => _repository(tester, h).setRefreshInterval(id, 36),
      );
      await _settle(tester, h);

      await openEdit(tester, 'Remote name');
      expect(find.text('Every 36 hours'), findsOneWidget);
      await tester.tap(find.text('Every 36 hours'));
      await tester.pumpAndSettle();
      // 選單裡的那一列（按鈕上也有一個）。
      double top(String label) => tester.getTopLeft(find.text(label).last).dy;
      expect(top('Every day'), lessThan(top('Every 36 hours')));
      expect(top('Every 36 hours'), lessThan(top('Every 2 days')));
      await tester.tap(find.text('Every 36 hours').last);
      await tester.pumpAndSettle();
      await save(tester, h);

      expect((await _remote(tester, h, id)).refreshIntervalHours, 36);
    });

    testWidgets('a local playlist has no interval field', (tester) async {
      final h = await _open(tester, _plugin());
      await tester.runAsync(() => _repository(tester, h).create(name: 'Mine'));
      await _settle(tester, h);

      await openEdit(tester, 'Mine');

      expect(find.text('Auto refresh'), findsNothing);
    });

    testWidgets('a local playlist has no such button', (tester) async {
      final h = await _open(tester, _plugin());
      await tester.runAsync(() => _repository(tester, h).create(name: 'Mine'));
      await _settle(tester, h);

      await openEdit(tester, 'Mine');

      expect(find.text("Use the remote's"), findsNothing);
    });
  });
}
