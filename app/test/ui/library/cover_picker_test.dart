import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/library/cover_picker.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_artwork.dart';
import '../support/shell_harness.dart';

// 「從歌曲封面選」（U PR 13，ADR 0035，R7.7）：歌單內不重複的曲目封面排成格狀，選一張就是自訂封面
// （之後的檢查與儲存同貼上網址）。

TrackInfo _song(String id, {String? cover, int? width = 300}) => TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  title: 'Song $id',
  artwork: [
    if (cover != null) TrackArtwork(url: Uri.parse(cover), width: width),
  ],
);

PlaylistEntry _entry(int id, TrackInfo track) =>
    PlaylistEntry(id: id, position: id, track: track);

void main() {
  group('distinctTrackCovers', () {
    test('keeps the first of each cover, in playlist order', () {
      final covers = distinctTrackCovers([
        _entry(1, _song('a', cover: 'https://cdn.example/1.jpg')),
        _entry(2, _song('b', cover: 'https://cdn.example/2.jpg')),
        _entry(3, _song('c', cover: 'https://cdn.example/1.jpg')),
      ]);

      expect(
        [for (final c in covers) '${c.artwork.url}'],
        ['https://cdn.example/1.jpg', 'https://cdn.example/2.jpg'],
      );
      expect(covers.first.pluginId, 'fmp-test');
    });

    test('skips songs without a cover', () {
      final covers = distinctTrackCovers([
        _entry(1, _song('a')),
        _entry(2, _song('b', cover: 'https://cdn.example/2.jpg')),
      ]);

      expect(covers, hasLength(1));
    });

    test('takes the larger image of a song that has several', () {
      final covers = distinctTrackCovers([
        _entry(
          1,
          TrackInfo(
            sourceTypeId: 'fmp-test',
            sourceId: 'a',
            title: 'A',
            artwork: [
              TrackArtwork(
                url: Uri.parse('https://cdn.example/s.jpg'),
                width: 64,
              ),
              TrackArtwork(
                url: Uri.parse('https://cdn.example/l.jpg'),
                width: 640,
              ),
            ],
          ),
        ),
      ]);

      expect('${covers.single.artwork.url}', 'https://cdn.example/l.jpg');
    });

    test('an empty playlist has none', () {
      expect(distinctTrackCovers(const []), isEmpty);
    });
  });

  group('editing a playlist', () {
    Future<(ShellHarness, int)> open(
      WidgetTester tester,
      List<TrackInfo> tracks,
    ) async {
      final h = ShellHarness(
        artworkManager: FakeArtworkManager(),
        registryOfSources: true,
      );
      await h.pumpShell(
        tester,
        size: const Size(400, 900),
        at: ShellDestination.library,
      );
      final id = (await tester.runAsync(() async {
        final repository = h.container(tester).read(playlistRepositoryProvider);
        final id = await repository.create(name: 'Road');
        await repository.addTracks(id, tracks);
        return id;
      }))!;
      for (var i = 0; i < 3; i++) {
        await h.loadSettings(tester);
      }
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('Road'),
                matching: find.byType(InkWell),
              ),
              matching: find.byTooltip('More options'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      return (h, id);
    }

    testWidgets('picking a cover makes it the custom cover and saving '
        'stores it', (tester) async {
      final (h, id) = await open(tester, [
        _song('a', cover: 'https://cdn.example/1.jpg'),
        _song('b', cover: 'https://cdn.example/2.jpg'),
        _song('c', cover: 'https://cdn.example/1.jpg'),
      ]);

      await tester.tap(find.text('Pick from song covers'));
      await tester.pumpAndSettle();
      // 三首、兩張不同的封面。
      final tiles = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label?.startsWith('Cover ') ?? false),
      );
      expect(tiles, findsNWidgets(2));

      await tester.tap(tiles.last);
      await tester.pumpAndSettle();

      expect(find.text('Choose a cover'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Image URL'))
            .controller!
            .text,
        'https://cdn.example/2.jpg',
      );
      expect(find.text('A custom image'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      for (var i = 0; i < 3; i++) {
        await h.loadSettings(tester);
      }
      await tester.pumpAndSettle();
      final stored = (await tester.runAsync(
        () => h.container(tester).read(playlistRepositoryProvider).find(id),
      ))!;
      expect(
        [for (final a in stored.artwork) '${a.url}'],
        ['https://cdn.example/2.jpg'],
      );
    });

    testWidgets('cancelling the picker leaves the cover as it was', (
      tester,
    ) async {
      await open(tester, [_song('a', cover: 'https://cdn.example/1.jpg')]);

      await tester.tap(find.text('Pick from song covers'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();

      expect(find.text('A custom image'), findsNothing);
      expect(find.text('Edit playlist'), findsOneWidget);
    });

    testWidgets('a playlist whose songs have no covers says so', (
      tester,
    ) async {
      await open(tester, [_song('a')]);

      await tester.tap(find.text('Pick from song covers'));
      await tester.pumpAndSettle();

      expect(
        find.text('None of the songs in this playlist has a cover'),
        findsOneWidget,
      );
    });

    testWidgets('creating a playlist has no picker (no songs yet)', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.library);
      await tester.tap(find.byTooltip('New playlist'));
      await tester.pumpAndSettle();

      expect(find.text('Pick from song covers'), findsNothing);
    });
  });
}
