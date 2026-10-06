import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/settings/playback_settings.dart';

import '../support/memory_database.dart';

void main() {
  ProviderContainer containerFor(AppDatabase database) =>
      ProviderContainer.test(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );

  /// 訂閱 [playbackPreferencesProvider]，依序取得它發出的值。
  StreamIterator<PlaybackPreferences> preferences(ProviderContainer container) {
    final controller = StreamController<PlaybackPreferences>();
    container.listen(playbackPreferencesProvider, (_, next) {
      if (next case AsyncData(:final value)) controller.add(value);
    }, fireImmediately: true);
    final iterator = StreamIterator(controller.stream);
    addTearDown(() async {
      await iterator.cancel();
      await controller.close();
    });
    return iterator;
  }

  group('defaults apply only to unset fields (ADR 0011)', () {
    test('a user value survives a change of the program default', () {
      const stored = PlaybackSettings(
        rememberPosition: false,
        tempPlayRewindSeconds: 30,
        skipPreviewClips: false,
      );

      for (final (remember, rewind, skip) in [
        (true, 10, true),
        (false, 0, false),
      ]) {
        final resolved = resolvePlaybackPreferences(
          stored,
          defaultRememberPosition: remember,
          defaultTempPlayRewindSeconds: rewind,
          defaultSkipPreviewClips: skip,
        );
        expect(resolved.rememberPosition, isFalse);
        expect(resolved.tempPlayRewindSeconds, 30);
        expect(resolved.skipPreviewClips, isFalse);
      }
    });

    test('an unset field follows the new default', () {
      for (final (remember, rewind, skip) in [
        (true, 10, true),
        (false, 0, false),
      ]) {
        final resolved = resolvePlaybackPreferences(
          PlaybackSettings.empty,
          defaultRememberPosition: remember,
          defaultTempPlayRewindSeconds: rewind,
          defaultSkipPreviewClips: skip,
        );
        expect(resolved.rememberPosition, remember);
        expect(resolved.tempPlayRewindSeconds, rewind);
        expect(resolved.skipPreviewClips, skip);
      }
    });

    test('nothing is written for fields the user never set', () async {
      final database = memoryDatabase();
      final events = preferences(containerFor(database));
      await events.moveNext();

      expect(
        await database.customSelect('SELECT * FROM playback_settings').get(),
        isEmpty,
      );
    });
  });

  group('PlaybackPreferencesNotifier', () {
    test('unset fields read as remembering the position, 10 s back, '
        'skipping preview clips', () async {
      final events = preferences(containerFor(memoryDatabase()));

      expect(await events.moveNext(), isTrue);
      expect(events.current.rememberPosition, isTrue);
      expect(events.current.tempPlayRewindSeconds, 10);
      expect(events.current.skipPreviewClips, isTrue);
      expect(events.current.stored, PlaybackSettings.empty);
    });

    test('values the user set are read back', () async {
      final container = containerFor(memoryDatabase());
      final events = preferences(container);
      await events.moveNext();
      final notifier = container.read(playbackPreferencesProvider.notifier);

      await notifier.setRememberPosition(false);
      expect(await events.moveNext(), isTrue);
      expect(events.current.rememberPosition, isFalse);

      await notifier.setTempPlayRewindSeconds(3);
      expect(await events.moveNext(), isTrue);
      expect(events.current.tempPlayRewindSeconds, 3);

      await notifier.setSkipPreviewClips(false);
      expect(await events.moveNext(), isTrue);
      expect(events.current.skipPreviewClips, isFalse);
      expect(
        events.current.stored,
        const PlaybackSettings(
          rememberPosition: false,
          tempPlayRewindSeconds: 3,
          skipPreviewClips: false,
        ),
      );
    });

    test('each setter writes only its own field', () async {
      final database = memoryDatabase();
      final container = containerFor(database);
      final events = preferences(container);
      await events.moveNext();

      await container
          .read(playbackPreferencesProvider.notifier)
          .setTempPlayRewindSeconds(15);

      final row = await database
          .customSelect(
            'SELECT remember_position, temp_play_rewind_seconds, '
            'skip_preview_clips FROM playback_settings',
          )
          .getSingle();
      expect(row.data, {
        'remember_position': null,
        'temp_play_rewind_seconds': 15,
        'skip_preview_clips': null,
      });

      await container
          .read(playbackPreferencesProvider.notifier)
          .setSkipPreviewClips(false);
      final after = await database
          .customSelect(
            'SELECT remember_position, temp_play_rewind_seconds, '
            'skip_preview_clips FROM playback_settings',
          )
          .getSingle();
      expect(after.data, {
        'remember_position': null,
        'temp_play_rewind_seconds': 15,
        'skip_preview_clips': 0,
      });
    });

    test('null clears a field back to the default', () async {
      final database = memoryDatabase();
      final container = containerFor(database);
      final events = preferences(container);
      await events.moveNext();
      final notifier = container.read(playbackPreferencesProvider.notifier);
      await notifier.setRememberPosition(false);
      await events.moveNext();
      await notifier.setTempPlayRewindSeconds(0);
      await events.moveNext();

      await notifier.setRememberPosition(null);
      expect(await events.moveNext(), isTrue);
      expect(events.current.rememberPosition, isTrue);
      await notifier.setTempPlayRewindSeconds(null);
      expect(await events.moveNext(), isTrue);
      expect(events.current.tempPlayRewindSeconds, 10);
      await notifier.setSkipPreviewClips(false);
      await events.moveNext();
      await notifier.setSkipPreviewClips(null);
      expect(await events.moveNext(), isTrue);
      expect(events.current.skipPreviewClips, isTrue);
      expect(events.current.stored, PlaybackSettings.empty);

      final row = await database
          .customSelect(
            'SELECT remember_position, temp_play_rewind_seconds, '
            'skip_preview_clips FROM playback_settings',
          )
          .getSingle();
      expect(row.data, {
        'remember_position': null,
        'temp_play_rewind_seconds': null,
        'skip_preview_clips': null,
      });
    });
  });
}
