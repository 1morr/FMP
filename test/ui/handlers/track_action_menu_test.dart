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
}
