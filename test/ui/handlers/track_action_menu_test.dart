import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/handlers/track_action_handler.dart';
import 'package:fmp/ui/handlers/track_action_menu.dart';

void main() {
  group('buildCommonTrackActionMenuItems', () {
    test('single track menu exposes all common actions in stable order', () {
      final items = buildCommonTrackActionMenuItems(
        translations: AppLocale.en.translations,
      );

      expect(
        items.map((item) => item.id),
        [
          playTrackActionId,
          playNextTrackActionId,
          addToQueueTrackActionId,
          addToPlaylistTrackActionId,
          matchLyricsTrackActionId,
          addToRemoteTrackActionId,
        ],
      );
      expect(items.first.icon, Icons.play_arrow);
      expect(items.first.trackAction, TrackAction.play);
    });

    test('multi track menu omits single-only play and lyrics actions', () {
      final items = buildCommonTrackActionMenuItems(
        translations: AppLocale.en.translations,
        scope: TrackActionMenuScope.multi,
      );

      expect(
        items.map((item) => item.id),
        [
          playNextTrackActionId,
          addToQueueTrackActionId,
          addToPlaylistTrackActionId,
          addToRemoteTrackActionId,
        ],
      );
      expect(items.any((item) => item.id == playTrackActionId), isFalse);
      expect(items.any((item) => item.id == matchLyricsTrackActionId), isFalse);
    });

    test('options can hide lyrics while preserving other group actions', () {
      final items = buildCommonTrackActionMenuItems(
        translations: AppLocale.en.translations,
        options: const TrackActionMenuOptions(
          includeMatchLyrics: false,
        ),
      );

      expect(
        items.map((item) => item.id),
        [
          playTrackActionId,
          playNextTrackActionId,
          addToQueueTrackActionId,
          addToPlaylistTrackActionId,
          addToRemoteTrackActionId,
        ],
      );
      expect(items.any((item) => item.id == matchLyricsTrackActionId), isFalse);
    });
  });

  group('buildTrackActionListTiles', () {
    TrackActionMenuItem findItem(String id) =>
        buildCommonTrackActionMenuItems(
          translations: AppLocale.en.translations,
        ).firstWhere((item) => item.id == id);

    testWidgets('tapping a tile pops the sheet and dispatches the item',
        (tester) async {
      TrackActionMenuItem? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheetContext) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: buildTrackActionListTiles(
                      sheetContext,
                      [findItem(addToQueueTrackActionId)],
                      (item) => selected = item,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final label = findItem(addToQueueTrackActionId).label;
      expect(find.text(label), findsOneWidget);

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(selected?.id, addToQueueTrackActionId);
      expect(find.text(label), findsNothing);
    });

    testWidgets('destructive item uses destructiveColor', (tester) async {
      const destructiveItem = TrackActionMenuItem(
        id: 'delete',
        label: 'Delete',
        icon: Icons.delete,
        trackAction: TrackAction.addToQueue,
        destructive: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: buildTrackActionListTiles(
                  context,
                  [destructiveItem],
                  (_) {},
                  destructiveColor: Colors.red,
                ),
              ),
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.delete));
      expect(icon.color, Colors.red);
      final text = tester.widget<Text>(find.text('Delete'));
      expect(text.style?.color, Colors.red);
    });

    testWidgets('disabled item has no onTap', (tester) async {
      const disabledItem = TrackActionMenuItem(
        id: 'play',
        label: 'Play',
        icon: Icons.play_arrow,
        trackAction: TrackAction.play,
        enabled: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: buildTrackActionListTiles(
                  context,
                  [disabledItem],
                  (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    });
  });
}
