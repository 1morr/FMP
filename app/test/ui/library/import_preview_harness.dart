import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/library/import_preview_page.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../../library/fake_import_plugin.dart';
import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

// 匯入預覽頁的測試環境（import_preview_test.dart、guidelines_test.dart）：來源是僅元資料的假插件（id
// `fmp-test`，介面上的名稱是 ShellHarness 固定的 `Test Source`），目標是能搜能播的 `video`（沒有名稱，
// 介面上是 id）。

TrackSummary previewOrigin(
  String id,
  String title,
  String artist,
  int seconds,
) => TrackSummary(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  title: title,
  uploader: artist,
  duration: Duration(seconds: seconds),
);

/// 預設的來源歌單：Blue Sky、Green Field、Red Moon。
final previewSongs = [
  previewOrigin('s1', 'Blue Sky', 'Alice', 200),
  previewOrigin('s2', 'Green Field', 'Carol', 180),
  previewOrigin('s3', 'Red Moon', 'Dave', 240),
];

PlaylistPage previewPage(
  List<TrackSummary> songs, {
  String? cursor,
  bool truncated = false,
}) => PlaylistPage(
  playlist: const RemotePlaylist(title: 'Road trip'),
  items: [for (final song in songs) RemotePlaylistItem(track: song)],
  cursor: cursor,
  truncated: truncated,
);

TrackSummary _hit(String id, String title, String uploader, int seconds) =>
    TrackSummary(
      sourceTypeId: 'video',
      sourceId: id,
      title: title,
      uploader: uploader,
      duration: Duration(seconds: seconds),
    );

/// 預設的搜尋：Blue Sky 有兩個候選、Green Field 一個，Red Moon 什麼都沒有（匹配失敗），自訂關鍵字
/// `red moon live` 找得到它。
List<TrackSummary> previewResults(String keyword) => switch (keyword) {
  'Blue Sky Alice' => [
    _hit('v1', 'Blue Sky', 'Alice', 200),
    _hit('v2', 'Blue Sky (Piano)', 'Someone', 201),
  ],
  'Green Field Carol' => [_hit('v3', 'Green Field', 'Carol', 180)],
  'red moon live' => [_hit('v4', 'Red Moon (Live)', 'Dave', 242)],
  _ => const [],
};

final class PreviewHarness {
  PreviewHarness({
    FutureOr<PlaylistPage> Function(PlaylistPageQuery query)? onPage,
    FutureOr<List<TrackSummary>> Function(String keyword)? results,
  }) : source = FakeImportPlugin(
         resolveStream: false,
         onPage: onPage ?? (_) => previewPage(previewSongs),
       ),
       target = FakeSourcePlugin(
         (_) => const [],
         id: 'video',
         onSearch: (query) async => SearchPage(
           items: await (results ?? previewResults)(query.keyword),
           hasMore: false,
         ),
       ) {
    shell = ShellHarness(registryOfSources: true, sources: [source, target]);
  }

  final FakeImportPlugin source;
  final FakeSourcePlugin target;
  late final ShellHarness shell;

  /// 開外殼在音樂庫（面板收起），再在它的巢狀導覽裡開預覽頁並讀完。
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 900),
    Brightness brightness = Brightness.light,
  }) async {
    await shell.pumpShell(
      tester,
      size: size,
      brightness: brightness,
      collapsePanel: true,
      at: ShellDestination.library,
    );
    await settle(tester);
    unawaited(
      openImportPreview(
        tester.element(find.byType(LibraryPage)),
        pluginId: 'fmp-test',
        playlistId: 'remote-1',
      ),
    );
    await settle(tester);
  }

  /// 真的非同步（資料庫、插件）跑一下再重畫，幾輪。[animations] 為假時不等動畫停（有一首正在搜時
  /// 進度圈一直在轉）。
  Future<void> settle(WidgetTester tester, {bool animations = true}) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    if (animations) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> start(WidgetTester tester, {bool animations = true}) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Start matching'));
    await settle(tester, animations: animations);
  }

  Future<List<Playlist>> playlists(WidgetTester tester) async =>
      (await tester.runAsync(
        () => shell
            .container(tester)
            .read(playlistRepositoryProvider)
            .watchAll()
            .first,
      ))!;
}

/// 一首的那一列（原標題所在的 ListTile）。
Finder previewRow(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first;

/// 點一列展開。
Future<void> expandPreviewRow(WidgetTester tester, String title) async {
  await tester.tap(previewRow(title));
  await tester.pumpAndSettle();
}
