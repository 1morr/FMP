import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/empty_state/loading_state.dart';
import 'package:fmp/ui/library/library_state.dart';
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/plugins/source_icon.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// 音樂庫的格狀版面（U PR 13，ADR 0035，R7.5）：所有寬度都是格狀（手機兩欄）、卡片角落的音源圖示
// （沒有圖示是名稱縮寫）、匯入歌單的連結圖示、載入中與讀失敗可重試、選單的刪除項目是 error 色。

/// 外殼開在音樂庫；[local] 張本機歌單，加上一張匯入歌單與一張 Mix 歌單。
Future<ShellHarness> _open(
  WidgetTester tester, {
  required Size size,
  bool installed = true,
  int local = 4,
  bool collapsePanel = true,
  bool registry = true,
  List<Override> overrides = const [],
}) async {
  final h = ShellHarness(
    registryOfSources: registry,
    mix: true,
    extraOverrides: overrides,
    sourceUnavailable: installed ? (ref, id) => null : (ref, id) => 'gone',
  );
  await h.pumpShell(
    tester,
    size: size,
    at: ShellDestination.library,
    collapsePanel: collapsePanel,
  );
  await tester.runAsync(() async {
    final repository = h.container(tester).read(playlistRepositoryProvider);
    for (var i = 0; i < local; i++) {
      await repository.create(name: 'Local $i');
    }
    await repository.createImported(
      pluginId: 'fmp-test',
      remoteId: 'r1',
      info: const RemotePlaylistInfo(name: 'Remote one'),
    );
    await repository.createMix(
      name: 'Chill mix',
      pluginId: 'fmp-test',
      seedSourceId: 'seed',
    );
  });
  for (var i = 0; i < 3; i++) {
    await h.loadSettings(tester);
  }
  await tester.pumpAndSettle();
  return h;
}

/// 畫面上各張封面的左緣（不重複），由左到右：就是欄數與位置。
List<double> _columns(WidgetTester tester) => {
  for (final cover in find.byType(PlaylistCover).evaluate())
    tester.getTopLeft(find.byWidget(cover.widget)).dx,
}.toList()..sort();

void main() {
  group('the grid', () {
    for (final (width, columns) in const [
      (400.0, 2),
      (1000.0, 5),
      (1400.0, 7),
    ]) {
      testWidgets('has $columns columns at $width, each card at most '
          '${AppLayout.playlistCardMaxWidth}dp wide', (tester) async {
        await _open(tester, size: Size(width, 900), local: 10);

        final lefts = _columns(tester);
        expect(lefts, hasLength(columns));
        expect(find.byType(ReorderableListView), findsNothing);
        for (final cover in find.byType(PlaylistCover).evaluate()) {
          final size = tester.getSize(find.byWidget(cover.widget));
          expect(
            size.width,
            lessThanOrEqualTo(AppLayout.playlistCardMaxWidth),
            reason: 'a card at $width',
          );
          expect(size.width, size.height);
        }
      });
    }
  });

  group('the source icon', () {
    testWidgets('an imported card and a Mix card show the source, a local card '
        'none; the name is the abbreviation without a manifest icon', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _open(tester, size: const Size(400, 900));

      // 「Test Source」→ TS：匯入歌單與 Mix 歌單各一個，本機歌單沒有。
      expect(find.byType(SourceIcon), findsNWidgets(2));
      expect(find.text('TS'), findsNWidgets(2));
      // 圖示本身是裝飾，語意名稱是音源名稱（併進卡片的語意節點）。
      expect(find.bySemanticsLabel(RegExp('Test Source')), findsWidgets);
      handle.dispose();
    });

    testWidgets('a source that is not installed falls back to its id', (
      tester,
    ) async {
      await _open(tester, size: const Size(400, 900), installed: false);

      // 沒有插件清單：名稱退回插件 id（fmp-test → FT）。
      expect(find.text('FT'), findsNWidgets(2));
    });

    testWidgets('an imported card has a link icon before its subtitle', (
      tester,
    ) async {
      await _open(tester, size: const Size(400, 900));

      final subtitle = find.text('Imported · 0 songs');
      expect(subtitle, findsOneWidget);
      final row = find.ancestor(of: subtitle, matching: find.byType(Row)).first;
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.link)),
        findsOneWidget,
      );
      expect(find.text('Local · 0 songs'), findsNWidgets(4));
      // 匯入鈕也是連結圖示（不再是下載箭頭）。
      expect(
        find.descendant(
          of: find.byTooltip('Import a playlist'),
          matching: find.byIcon(Icons.link),
        ),
        findsOneWidget,
      );
    });
  });

  group('loading and failing', () {
    testWidgets('loading shows a spinner with a line, not a blank page', (
      tester,
    ) async {
      final never = Completer<List<PlaylistOverview>>();
      final h = ShellHarness(
        extraOverrides: [
          playlistOverviewsProvider.overrideWith(
            (ref) => Stream.fromFuture(never.future),
          ),
        ],
      );
      await h.pumpShell(tester, at: ShellDestination.library);
      await tester.pump();

      expect(find.byType(LoadingState), findsOneWidget);
      expect(find.text('Loading playlists'), findsOneWidget);
    });

    testWidgets('a failed read is an error state with Retry that reads '
        'again', (tester) async {
      var reads = 0;
      final h = ShellHarness(
        extraOverrides: [
          playlistOverviewsProvider.overrideWith((ref) {
            reads++;
            return Stream.error(StateError('playlists'));
          }),
        ],
      );
      await h.pumpShell(tester, at: ShellDestination.library);
      await tester.pumpAndSettle();

      expect(reads, 1);
      final error = find.byType(EmptyState);
      expect(error, findsOneWidget);
      expect(tester.widget<EmptyState>(error).error, isTrue);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(reads, 2);
    });
  });

  testWidgets('Delete in the card menu is the error color, the others are '
      'not', (tester) async {
    await _open(tester, size: const Size(400, 900));
    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('Local 0'),
              matching: find.byType(InkWell),
            ),
            matching: find.byTooltip('More options'),
          )
          .first,
    );
    await tester.pumpAndSettle();

    final scheme = Theme.of(tester.element(find.text('Delete'))).colorScheme;
    Color? colorOf(String label) => tester
        .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, label))
        .style
        ?.foregroundColor
        ?.resolve(const {});
    expect(colorOf('Delete'), scheme.error);
    expect(colorOf('Edit'), isNull);
  });
}
