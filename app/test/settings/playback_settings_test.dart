import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/domain/stream_preferences.dart';
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
        audioQuality: AudioQuality.medium,
        audioFormatPriority: AudioFormatPriority.aacFirst,
        rememberPosition: false,
        tempPlayRewindSeconds: 30,
        skipPreviewClips: false,
      );

      for (final (quality, format, remember, rewind, skip) in [
        (AudioQuality.high, AudioFormatPriority.opusFirst, true, 10, true),
        (AudioQuality.low, AudioFormatPriority.aacFirst, false, 0, false),
      ]) {
        final resolved = resolvePlaybackPreferences(
          stored,
          defaultAudioQuality: quality,
          defaultAudioFormatPriority: format,
          defaultRememberPosition: remember,
          defaultTempPlayRewindSeconds: rewind,
          defaultSkipPreviewClips: skip,
        );
        expect(resolved.audioQuality, AudioQuality.medium);
        expect(resolved.audioFormatPriority, AudioFormatPriority.aacFirst);
        expect(resolved.rememberPosition, isFalse);
        expect(resolved.tempPlayRewindSeconds, 30);
        expect(resolved.skipPreviewClips, isFalse);
      }
    });

    test('an unset field follows the new default', () {
      for (final (quality, format, remember, rewind, skip) in [
        (AudioQuality.high, AudioFormatPriority.opusFirst, true, 10, true),
        (AudioQuality.low, AudioFormatPriority.aacFirst, false, 0, false),
      ]) {
        final resolved = resolvePlaybackPreferences(
          PlaybackSettings.empty,
          defaultAudioQuality: quality,
          defaultAudioFormatPriority: format,
          defaultRememberPosition: remember,
          defaultTempPlayRewindSeconds: rewind,
          defaultSkipPreviewClips: skip,
        );
        expect(resolved.audioQuality, quality);
        expect(resolved.audioFormatPriority, format);
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
    test('unset fields read as high quality, Opus first, remembering the '
        'position, 10 s back, skipping preview clips', () async {
      final events = preferences(containerFor(memoryDatabase()));

      expect(await events.moveNext(), isTrue);
      expect(events.current.audioQuality, AudioQuality.high);
      expect(events.current.audioFormatPriority, AudioFormatPriority.opusFirst);
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

      await notifier.setAudioQuality(AudioQuality.low);
      expect(await events.moveNext(), isTrue);
      expect(events.current.audioQuality, AudioQuality.low);

      await notifier.setAudioFormatPriority(AudioFormatPriority.aacFirst);
      expect(await events.moveNext(), isTrue);
      expect(events.current.audioFormatPriority, AudioFormatPriority.aacFirst);

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
          audioQuality: AudioQuality.low,
          audioFormatPriority: AudioFormatPriority.aacFirst,
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

      Future<Map<String, Object?>> row() async =>
          (await database
                  .customSelect(
                    'SELECT audio_quality, audio_format_priority, '
                    'remember_position, temp_play_rewind_seconds, '
                    'skip_preview_clips FROM playback_settings',
                  )
                  .getSingle())
              .data;
      expect(await row(), {
        'audio_quality': null,
        'audio_format_priority': null,
        'remember_position': null,
        'temp_play_rewind_seconds': 15,
        'skip_preview_clips': null,
      });

      final notifier = container.read(playbackPreferencesProvider.notifier);
      await notifier.setAudioQuality(AudioQuality.medium);
      expect(await row(), {
        'audio_quality': 'medium',
        'audio_format_priority': null,
        'remember_position': null,
        'temp_play_rewind_seconds': 15,
        'skip_preview_clips': null,
      });
      await notifier.setAudioFormatPriority(AudioFormatPriority.aacFirst);
      expect(await row(), {
        'audio_quality': 'medium',
        'audio_format_priority': 'aac,opus',
        'remember_position': null,
        'temp_play_rewind_seconds': 15,
        'skip_preview_clips': null,
      });
      await notifier.setAudioQuality(null);
      await notifier.setAudioFormatPriority(null);

      await container
          .read(playbackPreferencesProvider.notifier)
          .setSkipPreviewClips(false);
      expect(await row(), {
        'audio_quality': null,
        'audio_format_priority': null,
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
      await notifier.setAudioQuality(AudioQuality.low);
      await events.moveNext();
      await notifier.setAudioQuality(null);
      expect(await events.moveNext(), isTrue);
      expect(events.current.audioQuality, AudioQuality.high);
      await notifier.setAudioFormatPriority(AudioFormatPriority.aacFirst);
      await events.moveNext();
      await notifier.setAudioFormatPriority(null);
      expect(await events.moveNext(), isTrue);
      expect(events.current.audioFormatPriority, AudioFormatPriority.opusFirst);
      expect(events.current.stored, PlaybackSettings.empty);

      final row = await database
          .customSelect(
            'SELECT audio_quality, audio_format_priority, '
            'remember_position, temp_play_rewind_seconds, '
            'skip_preview_clips FROM playback_settings',
          )
          .getSingle();
      expect(row.data, {
        'audio_quality': null,
        'audio_format_priority': null,
        'remember_position': null,
        'temp_play_rewind_seconds': null,
        'skip_preview_clips': null,
      });
    });
    // design §7.6：輸出裝置的 id 與顯示名稱一起寫、一起清；沒有預設（沒設定
    // 過就是系統預設）。
    test('the output device is written as a pair, read back and cleared '
        'as a pair', () async {
      final database = memoryDatabase();
      final container = containerFor(database);
      final events = preferences(container);
      expect(await events.moveNext(), isTrue);
      expect(events.current.outputDevice, isNull);
      final notifier = container.read(playbackPreferencesProvider.notifier);
      await notifier.setTempPlayRewindSeconds(5);
      await events.moveNext();

      const device = OutputDevice(
        id: 'wasapi/{2698a574}',
        name: 'Speakers (Realtek(R) Audio)',
      );
      await notifier.setOutputDevice(device);
      expect(await events.moveNext(), isTrue);
      expect(events.current.outputDevice, device);

      Future<Map<String, Object?>> row() async =>
          (await database
                  .customSelect(
                    'SELECT output_device_id, output_device_name, '
                    'temp_play_rewind_seconds FROM playback_settings',
                  )
                  .getSingle())
              .data;
      expect(await row(), {
        'output_device_id': 'wasapi/{2698a574}',
        'output_device_name': 'Speakers (Realtek(R) Audio)',
        'temp_play_rewind_seconds': 5,
      });

      await notifier.setOutputDevice(null);
      expect(await events.moveNext(), isTrue);
      expect(events.current.outputDevice, isNull);
      expect(await row(), {
        'output_device_id': null,
        'output_device_name': null,
        'temp_play_rewind_seconds': 5,
      });
    });

    test('a stored id without a name shows the id', () {
      final resolved = PlaybackPreferencesNotifier.resolve(
        const PlaybackSettings(outputDeviceId: 'wasapi/{a}'),
      );
      expect(
        resolved.outputDevice,
        const OutputDevice(id: 'wasapi/{a}', name: 'wasapi/{a}'),
      );
    });
  });
}
