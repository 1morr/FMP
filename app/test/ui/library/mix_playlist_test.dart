import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../../library/fake_import_plugin.dart';
import '../support/destructive_support.dart';
import '../support/shell_harness.dart';

// Mix 歌單的卡片選單、詳情與編輯（M4 PR 11，ADR 0033 §決定 1、ADR 0031 §決定 8、9，
// design §5.4）。建立在匯入對話框（import_ui_test）與匯入器（playlist_importer_test）測。

const _more = 'More options';
const _notInstalled = 'Source not installed';
const _noMix = "This source doesn't support Mix";

const _seedTrack = TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: 'seed',
  title: 'Seed song',
  uploader: 'Seed uploader',
);

enum _Source {
  /// 插件在清單上、宣告 `mix`。
  mix,

  /// 在清單上、沒宣告 `mix`。
  noMix,

  /// 不在清單上（停用或移除）。
  gone,
}

ShellHarness _harness(_Source source) {
  final h = switch (source) {
    _Source.mix => ShellHarness(mix: true, registryOfSources: true),
    _Source.noMix => ShellHarness(registryOfSources: true),
    _Source.gone => ShellHarness(
      registryOfSources: true,
      sources: [FakeImportPlugin(id: 'other')],
      sourceUnavailable: (ref, pluginId) => _notInstalled,
    ),
  };
  h.plugin.onMix = (query) => MixBatch(
    mixId: 'm1',
    title: 'Chill',
    tracks: [
      for (final id in ['m1', 'm2'])
        TrackSummary(sourceTypeId: 'fmp-test', sourceId: id, title: id),
    ],
  );
  return h;
}

Future<void> _settle(WidgetTester tester, ShellHarness h) async {
  for (var i = 0; i < 3; i++) {
    await h.loadSettings(tester);
  }
  await tester.pumpAndSettle();
}

/// 外殼開在音樂庫，有一張 Mix 歌單「Chill」（種子 `fmp-test:seed`；[seedStored] 時種子曲目在
/// `tracks` 裡）。
Future<ShellHarness> _open(
  WidgetTester tester, {
  _Source source = _Source.mix,
  bool seedStored = true,
  Size size = const Size(400, 800),
  bool collapsePanel = false,
  bool local = false,
}) async {
  final h = _harness(source);
  await h.pumpShell(
    tester,
    size: size,
    at: ShellDestination.library,
    collapsePanel: collapsePanel,
  );
  await tester.runAsync(() async {
    final repository = h.container(tester).read(playlistRepositoryProvider);
    await repository.createMix(
      name: 'Chill',
      pluginId: 'fmp-test',
      seedSourceId: 'seed',
    );
    if (local) await repository.create(name: 'Road');
    if (seedStored) {
      await h.container(tester).read(tracksRepositoryProvider).upsert([
        _seedTrack,
      ]);
    }
  });
  await _settle(tester, h);
  return h;
}

Finder _card(String name) => find.ancestor(
  of: find.text(name),
  matching: find.byWidgetPredicate(
    (widget) => widget is ListTile || widget is InkWell,
  ),
);

Future<void> _openMenu(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: _card(name).first, matching: find.byTooltip(_more)),
  );
  await tester.pumpAndSettle();
}

MenuItemButton _item(WidgetTester tester, String label) =>
    tester.widget(find.widgetWithText(MenuItemButton, label));

FilledButton _mixPlay(WidgetTester tester) =>
    tester.widget(find.widgetWithText(FilledButton, 'Mix play'));

Future<void> _openDetail(WidgetTester tester, ShellHarness h) async {
  await tester.tap(find.text('Chill'));
  await _settle(tester, h);
  expect(find.byType(PlaylistDetailPage), findsOneWidget);
}

Future<List<Playlist>> _stored(WidgetTester tester, ShellHarness h) async =>
    (await tester.runAsync(
      () =>
          h.container(tester).read(playlistRepositoryProvider).watchAll().first,
    ))!;

/// 讓點擊後的 Mix 播放（插件請求、播放）跑完。
Future<void> _playSettled(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('the card menu', () {
    testWidgets('a Mix playlist has Mix play, Edit and Delete only', (
      tester,
    ) async {
      await _open(tester, local: true);

      await _openMenu(tester, 'Chill');

      expect(find.byType(MenuItemButton), findsNWidgets(3));
      for (final label in ['Mix play', 'Edit', 'Delete']) {
        expect(find.widgetWithText(MenuItemButton, label), findsOneWidget);
      }
    });

    testWidgets('a Mix card says Mix without a song count', (tester) async {
      await _open(tester, local: true);

      expect(
        find.descendant(of: find.byType(InkWell), matching: find.text('Mix')),
        findsOneWidget,
      );
      expect(find.textContaining('Mix ·'), findsNothing);
    });

    testWidgets('a local playlist has no Mix play', (tester) async {
      await _open(tester, local: true);

      await _openMenu(tester, 'Road');

      expect(find.text('Mix play'), findsNothing);
      expect(find.text('Add all to queue'), findsOneWidget);
    });

    testWidgets('the grid card has the same menu', (tester) async {
      await _open(tester, size: const Size(1400, 900), collapsePanel: true);

      await _openMenu(tester, 'Chill');

      expect(find.byType(MenuItemButton), findsNWidgets(3));
      expect(find.widgetWithText(MenuItemButton, 'Mix play'), findsOneWidget);
    });

    testWidgets('Mix play replaces the queue from the stored seed', (
      tester,
    ) async {
      final h = await _open(tester);

      await _openMenu(tester, 'Chill');
      await tester.tap(find.widgetWithText(MenuItemButton, 'Mix play'));
      await _playSettled(tester);

      expect(h.controller.queue.mode, QueueMode.mix);
      expect(h.controller.queue.entries, isNotEmpty);
      final query = h.plugin.mixQueries.first as MixSeedQuery;
      expect(query.sourceId, 'seed');
      expect(query.cid, isNull);
    });

    // 插件一首都沒給（`NotFound`）：提示錯誤，佇列不動（ADR 0031 §決定 9 的取代只在成功時）。
    testWidgets('a Mix play that gets nothing shows the error and leaves the '
        'queue alone', (tester) async {
      final h = await _open(tester);
      h.plugin.onMix = (_) =>
          const MixBatch(mixId: 'm1', title: 'Chill', tracks: []);
      await h.play(tester, [summary('x')]);

      await _openMenu(tester, 'Chill');
      await tester.tap(find.widgetWithText(MenuItemButton, 'Mix play'));
      await _playSettled(tester);

      expect(h.plugin.mixQueries, hasLength(1));
      expect(h.controller.queue.mode, QueueMode.queue);
      expect(h.controller.queue.entries.single.track.sourceId, 'x');
      expect(find.textContaining('Not found'), findsWidgets);
      // 提示的計時器在樹拆掉前走完。
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Mix play is disabled with the reason when the source is '
        'not installed', (tester) async {
      await _open(tester, source: _Source.gone);

      await _openMenu(tester, 'Chill');

      expect(_item(tester, 'Mix play ($_notInstalled)').onPressed, isNull);
    });

    testWidgets('Mix play is disabled when the source has no Mix', (
      tester,
    ) async {
      await _open(tester, source: _Source.noMix);

      await _openMenu(tester, 'Chill');

      expect(_item(tester, 'Mix play ($_noMix)').onPressed, isNull);
    });
  });

  group('the details', () {
    testWidgets('list no songs, show the kind, the source and the seed', (
      tester,
    ) async {
      final h = await _open(tester);

      await _openDetail(tester, h);

      expect(find.byType(LibraryPage).hitTestable(), findsNothing);
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Mix'), findsOneWidget);
      expect(find.text('Test Source'), findsOneWidget);
      expect(find.text('Seed song'), findsOneWidget);
      expect(find.text('Seed uploader'), findsOneWidget);
      expect(find.text('Add all to queue'), findsNothing);
      expect(find.text('Shuffle into queue'), findsNothing);
    });

    testWidgets('a seed that is not in tracks shows its id', (tester) async {
      final h = await _open(tester, seedStored: false);

      await _openDetail(tester, h);

      expect(find.text('seed'), findsOneWidget);
      expect(find.text('Seed song'), findsNothing);
    });

    testWidgets('Mix play starts the mix', (tester) async {
      final h = await _open(tester);
      await _openDetail(tester, h);

      await tester.tap(find.widgetWithText(FilledButton, 'Mix play'));
      await _playSettled(tester);

      expect(h.controller.queue.mode, QueueMode.mix);
      expect((h.plugin.mixQueries.first as MixSeedQuery).sourceId, 'seed');
    });

    // 提示同曲目選單的「開始 Mix」（`startMixFrom`）：網路錯誤照統一字樣。
    testWidgets('a network failure shows the error and leaves the queue '
        'alone', (tester) async {
      final h = await _open(tester);
      h.plugin.onMix = (_) => throw NetworkError();
      await h.play(tester, [summary('x')]);
      await _openDetail(tester, h);

      await tester.tap(find.widgetWithText(FilledButton, 'Mix play'));
      await _playSettled(tester);

      expect(h.controller.queue.mode, QueueMode.queue);
      expect(h.controller.queue.entries.single.track.sourceId, 'x');
      expect(find.textContaining('Network connection failed'), findsWidgets);
      // 提示的計時器在樹拆掉前走完。
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('Mix play is disabled with the reason when the source is '
        'not installed', (tester) async {
      final h = await _open(tester, source: _Source.gone);
      await _openDetail(tester, h);

      expect(_mixPlay(tester).onPressed, isNull);
      expect(find.text(_notInstalled), findsOneWidget);
    });

    testWidgets('Mix play is disabled when the source has no Mix', (
      tester,
    ) async {
      final h = await _open(tester, source: _Source.noMix);
      await _openDetail(tester, h);

      expect(_mixPlay(tester).onPressed, isNull);
      expect(find.text(_noMix), findsOneWidget);
    });

    testWidgets('the menu has Edit and Delete', (tester) async {
      final h = await _open(tester);
      await _openDetail(tester, h);

      await tester.tap(find.byTooltip(_more));
      await tester.pumpAndSettle();

      expect(find.byType(MenuItemButton), findsNWidgets(2));
      expect(find.widgetWithText(MenuItemButton, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(MenuItemButton, 'Delete'), findsOneWidget);
    });

    testWidgets('Delete asks first, then removes it and leaves the page', (
      tester,
    ) async {
      final h = await _open(tester);
      await _openDetail(tester, h);

      await tester.tap(find.byTooltip(_more));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete the playlist?'), findsOneWidget);
      expectDestructiveConfirm(tester, 'Delete');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await _settle(tester, h);

      expect(await _stored(tester, h), isEmpty);
      expect(find.byType(PlaylistDetailPage), findsNothing);
    });
  });

  group('editing', () {
    testWidgets('a Mix playlist has only a name', (tester) async {
      final h = await _open(tester);

      await _openMenu(tester, 'Chill');
      await tester.tap(find.widgetWithText(MenuItemButton, 'Edit'));
      await _settle(tester, h);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Description (optional)'), findsNothing);
      expect(find.text('Cover'), findsNothing);
      expect(find.text('Auto refresh'), findsNothing);
    });

    testWidgets('renaming keeps the seed', (tester) async {
      final h = await _open(tester);

      await _openMenu(tester, 'Chill');
      await tester.tap(find.widgetWithText(MenuItemButton, 'Edit'));
      await _settle(tester, h);
      await tester.enterText(find.byType(TextField), 'Evening');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _settle(tester, h);

      final playlist = (await _stored(tester, h)).single;
      expect(playlist.name, 'Evening');
      expect(playlist.kind, PlaylistKind.mix);
      expect(playlist.mixSeedSourceId, 'seed');
      expect(find.text('Evening'), findsOneWidget);
    });
  });
}
