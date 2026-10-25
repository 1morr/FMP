import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/library/playlist_importer.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/accounts/account_import_page.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:material_ui/material_ui.dart';

import '../../library/fake_import_plugin.dart';
import '../support/shell_harness.dart';

// 帳號匯入的全頁進度（ADR 0035 §決定 11、L-01 B）：總進度、每張歌單的「已匯入 n／M 首」與狀態、
// 取消、失敗、完成。插件是 `FakeImportPlugin`（`fmp-test`），第二頁用 Completer 卡住。

const _pluginId = 'fmp-test';

const _road = LibraryPlaylist(
  playlistId: 'p1',
  title: 'Road trip',
  trackCount: 5,
  writable: false,
);
const _study = LibraryPlaylist(
  playlistId: 'p2',
  title: 'Study',
  trackCount: 2,
  writable: false,
);

/// 開一個按鈕，按了就開 [playlists] 的帳號匯入頁（像帳號歌單頁那樣推在 Navigator 上）。
Future<(ShellHarness, AccountImportRun)> _open(
  WidgetTester tester,
  FakeImportPlugin plugin,
  List<LibraryPlaylist> playlists, {
  Size size = const Size(400, 800),
  List<String>? toasts,
}) async {
  final h = ShellHarness(registryOfSources: true, sources: [plugin]);
  late AccountImportRun run;
  await h.pumpApp(
    tester,
    Builder(
      builder: (context) => Material(
        child: TextButton(
          onPressed: () => unawaited(openAccountImport(context, run)),
          child: const Text('open'),
        ),
      ),
    ),
    size: size,
  );
  final container = h.container(tester);
  run = AccountImportRun(
    pluginId: _pluginId,
    playlists: playlists,
    importer: container.read(playlistImporterProvider),
    log: container.read(logProvider),
    toaster: h.toaster,
    translations: container.read(translationsProvider),
    failureReason: (error) => 'reason',
  );
  if (toasts != null) {
    final subscription = h.toaster.toasts.listen((t) => toasts.add(t.message));
    addTearDown(subscription.cancel);
  }
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return (h, run);
}

/// 讓真的非同步（資料庫、匯入）往前跑一下，再重畫。
Future<void> _advance(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the overall and per-playlist progress, then Done', (
    tester,
  ) async {
    final second = Completer<PlaylistPage>();
    final plugin = FakeImportPlugin(
      onPage: (query) => switch (query.playlistId) {
        'p1' =>
          query.cursor == null
              ? page(['a', 'b'], cursor: 'c2', total: 5)
              : second.future,
        _ => page(['x', 'y'], total: 2),
      },
    );
    final toasts = <String>[];
    final (_, run) = await _open(tester, plugin, [
      _road,
      _study,
    ], toasts: toasts);
    await _advance(tester);

    expect(find.text('Playlist 0 of 2'), findsOneWidget);
    expect(find.text('Imported 2 of 5'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Done'), findsNothing);

    second.complete(page(['c', 'd', 'e'], total: 5));
    await _advance(tester);
    await _advance(tester);

    expect(run.finished, isTrue);
    expect(find.text('Playlist 2 of 2'), findsOneWidget);
    expect(find.text('Imported 5 of 5'), findsOneWidget);
    expect(find.text('Imported 2 of 2'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    expect(toasts, ['Playlists imported: 2']);
    expect(run.importedIds, {'p1', 'p2'});

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Import playlists'), findsNothing);
  });

  testWidgets('without any total it says how many songs were read', (
    tester,
  ) async {
    final gate = Completer<PlaylistPage>();
    final plugin = FakeImportPlugin(
      onPage: (query) =>
          query.cursor == null ? page(['a', 'b'], cursor: 'c2') : gate.future,
    );
    const noCount = LibraryPlaylist(
      playlistId: 'p1',
      title: 'Mystery',
      writable: false,
    );
    final (_, _) = await _open(tester, plugin, [noCount]);
    await _advance(tester);

    expect(find.text('Read 2'), findsOneWidget);

    gate.complete(page(['c']));
    await _advance(tester);
    await _advance(tester);
  });

  testWidgets('cancel mid-batch keeps the finished playlists and discards the '
      'one being imported', (tester) async {
    final second = Completer<PlaylistPage>();
    final plugin = FakeImportPlugin(
      onPage: (query) => switch (query.playlistId) {
        'p1' => page(['x', 'y'], total: 2),
        'p2' =>
          query.cursor == null
              ? page(['a', 'b'], cursor: 'c2', total: 5)
              : second.future,
        _ => page(['z'], total: 1),
      },
    );
    const third = LibraryPlaylist(
      playlistId: 'p3',
      title: 'Never started',
      writable: false,
    );
    final toasts = <String>[];
    final (h, run) = await _open(tester, plugin, [
      _road,
      _study,
      third,
    ], toasts: toasts);
    await _advance(tester);
    await _advance(tester);
    expect(find.text('Imported 2 of 2'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    second.complete(page(['c', 'd', 'e'], total: 5));
    await _advance(tester);
    await _advance(tester);

    expect(run.finished, isTrue);
    expect(run.importedIds, {'p1'});
    expect(plugin.pageQueries.where((q) => q.playlistId == 'p3'), isEmpty);
    expect(toasts, ['Cancelled: 1 imported']);
    expect(find.text('Done'), findsOneWidget);
    // The one being imported is gone, not kept.
    expect(run.rows[1].libraryId, isNull);
    expect(run.rows[1].status, ImportRowStatus.cancelled);
    expect(run.rows[2].status, ImportRowStatus.cancelled);
    final names = await tester.runAsync(
      () async => [
        for (final p
            in await h
                .container(tester)
                .read(playlistRepositoryProvider)
                .watchAll()
                .first)
          p.name,
      ],
    );
    expect(names, ['Remote title']);
    final tracks = await tester.runAsync(
      () => h
          .container(tester)
          .read(appDatabaseProvider)
          .customSelect('SELECT COUNT(*) AS n FROM tracks')
          .getSingle(),
    );
    expect(tracks!.read<int>('n'), 2);
  });

  testWidgets('cancelling before anything was written says nothing was kept', (
    tester,
  ) async {
    final first = Completer<PlaylistPage>();
    final plugin = FakeImportPlugin(onPage: (_) => first.future);
    final toasts = <String>[];
    final (_, run) = await _open(tester, plugin, [
      _road,
      _study,
    ], toasts: toasts);
    await _advance(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    first.complete(page(['a', 'b'], total: 5));
    await _advance(tester);
    await _advance(tester);

    expect(run.finished, isTrue);
    expect(toasts, ['Cancelled: 0 imported']);
    expect(run.rows.first.libraryId, isNull);
  });

  testWidgets('a failed playlist shows its reason and the rest still import', (
    tester,
  ) async {
    final plugin = FakeImportPlugin(
      onPage: (query) => query.playlistId == 'p1'
          ? throw NetworkError(pluginId: _pluginId)
          : page(['x', 'y'], total: 2),
    );
    final toasts = <String>[];
    final (_, run) = await _open(tester, plugin, [
      _road,
      _study,
    ], toasts: toasts);
    await _advance(tester);
    await _advance(tester);
    await _advance(tester);

    expect(run.finished, isTrue);
    expect(find.text('Import failed: reason'), findsOneWidget);
    expect(find.text('Imported 2 of 2'), findsOneWidget);
    expect(toasts, ['Playlists imported: 1, failed: 1']);
    expect(run.failures, {'p1': 'Import failed: reason'});
    expect(run.importedIds, {'p2'});
  });

  testWidgets('the page cannot be left while importing', (tester) async {
    final gate = Completer<PlaylistPage>();
    final plugin = FakeImportPlugin(onPage: (_) => gate.future);
    final (_, _) = await _open(tester, plugin, [_road]);
    await _advance(tester);

    final navigator = Navigator.of(
      tester.element(find.byType(AccountImportPage)),
    );
    await navigator.maybePop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AccountImportPage), findsOneWidget);

    gate.complete(page(['a'], total: 1));
    await _advance(tester);
    await _advance(tester);
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(AccountImportPage), findsNothing);
  });
}
