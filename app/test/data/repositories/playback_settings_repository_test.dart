import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/domain/stream_preferences.dart';

import '../../support/memory_database.dart';

/// 每個欄位都有值。
const _everything = PlaybackSettings(
  audioQuality: AudioQuality.low,
  audioFormatPriority: AudioFormatPriority.aacFirst,
  rememberPosition: false,
  tempPlayRewindSeconds: 3,
  skipPreviewClips: false,
  outputDeviceId: 'wasapi/{device}',
  outputDeviceName: 'Speakers',
  restartRewindSeconds: 15,
  playHistoryLimit: 5000,
  autoScrollToCurrent: true,
);

Future<void> _writeEverything(PlaybackSettingsRepository repository) =>
    repository.write(
      audioQuality: _everything.audioQuality,
      audioFormatPriority: _everything.audioFormatPriority,
      rememberPosition: _everything.rememberPosition,
      tempPlayRewindSeconds: _everything.tempPlayRewindSeconds,
      skipPreviewClips: _everything.skipPreviewClips,
      outputDeviceId: _everything.outputDeviceId,
      outputDeviceName: _everything.outputDeviceName,
      restartRewindSeconds: _everything.restartRewindSeconds,
      playHistoryLimit: _everything.playHistoryLimit,
      autoScrollToCurrent: _everything.autoScrollToCurrent,
    );

void main() {
  test('reads all fields unset before anything is written', () async {
    final repository = PlaybackSettingsRepository(memoryDatabase());

    expect(await repository.read(), PlaybackSettings.empty);
  });

  test('reads back every field that was written', () async {
    final repository = PlaybackSettingsRepository(memoryDatabase());

    await _writeEverything(repository);

    expect(await repository.read(), _everything);
  });

  test('a partial write keeps the other fields', () async {
    final repository = PlaybackSettingsRepository(memoryDatabase());
    await _writeEverything(repository);

    await repository.write(tempPlayRewindSeconds: 30);

    final read = await repository.read();
    expect(read.tempPlayRewindSeconds, 30);
    expect(read.rememberPosition, isFalse);
    expect(read.audioQuality, AudioQuality.low);
    expect(read.playHistoryLimit, 5000);
  });

  test('writing one field leaves the others NULL', () async {
    final database = memoryDatabase();
    final repository = PlaybackSettingsRepository(database);

    await repository.write(rememberPosition: false);

    final row = await database
        .customSelect('SELECT * FROM playback_settings')
        .getSingle();
    expect(row.data, {
      'id': 1,
      'audio_quality': null,
      'audio_format_priority': null,
      'remember_position': 0,
      'temp_play_rewind_seconds': null,
      'skip_preview_clips': null,
      'output_device_id': null,
      'output_device_name': null,
      'restart_rewind_seconds': null,
      'play_history_limit': null,
      'auto_scroll_to_current': null,
    });
  });

  group('clear', () {
    test('stores NULL for the named fields and leaves the rest', () async {
      final database = memoryDatabase();
      final repository = PlaybackSettingsRepository(database);
      await _writeEverything(repository);

      await repository.clear(
        rememberPosition: true,
        tempPlayRewindSeconds: true,
      );

      final row = await database
          .customSelect(
            'SELECT remember_position, temp_play_rewind_seconds, '
            'restart_rewind_seconds FROM playback_settings',
          )
          .getSingle();
      expect(row.data, {
        'remember_position': null,
        'temp_play_rewind_seconds': null,
        'restart_rewind_seconds': 15,
      });
    });

    test('every field can be cleared', () async {
      final repository = PlaybackSettingsRepository(memoryDatabase());
      await _writeEverything(repository);

      await repository.clear(
        audioQuality: true,
        audioFormatPriority: true,
        rememberPosition: true,
        tempPlayRewindSeconds: true,
        skipPreviewClips: true,
        outputDeviceId: true,
        outputDeviceName: true,
        restartRewindSeconds: true,
        playHistoryLimit: true,
        autoScrollToCurrent: true,
      );

      expect(await repository.read(), PlaybackSettings.empty);
    });

    test('with nothing named changes nothing and adds no row', () async {
      final database = memoryDatabase();
      final repository = PlaybackSettingsRepository(database);

      await repository.clear();

      expect(
        await database.customSelect('SELECT * FROM playback_settings').get(),
        isEmpty,
      );
    });
  });

  test('watch emits the current value and every write', () async {
    final repository = PlaybackSettingsRepository(memoryDatabase());
    final events = StreamIterator(repository.watch());
    addTearDown(events.cancel);

    expect(await events.moveNext(), isTrue);
    expect(events.current, PlaybackSettings.empty);

    await repository.write(tempPlayRewindSeconds: 5);
    expect(await events.moveNext(), isTrue);
    expect(events.current, const PlaybackSettings(tempPlayRewindSeconds: 5));
  });

  test(
    'stored format: enums are fixed strings, the rest plain values',
    () async {
      final database = memoryDatabase();
      final repository = PlaybackSettingsRepository(database);

      await _writeEverything(repository);

      final row = await database
          .customSelect('SELECT * FROM playback_settings')
          .getSingle();
      expect(row.data, {
        'id': 1,
        'audio_quality': 'low',
        'audio_format_priority': 'aac,opus',
        'remember_position': 0,
        'temp_play_rewind_seconds': 3,
        'skip_preview_clips': 0,
        'output_device_id': 'wasapi/{device}',
        'output_device_name': 'Speakers',
        'restart_rewind_seconds': 15,
        'play_history_limit': 5000,
        'auto_scroll_to_current': 1,
      });

      // 其餘列舉值的字面值（與舊版 audioFormatPriority 相同，M5 匯入要對得上）。
      for (final (quality, stored) in [
        (AudioQuality.high, 'high'),
        (AudioQuality.medium, 'medium'),
      ]) {
        await repository.write(audioQuality: quality);
        final value = await database
            .customSelect('SELECT audio_quality FROM playback_settings')
            .getSingle();
        expect(value.data['audio_quality'], stored);
      }
      await repository.write(
        audioFormatPriority: AudioFormatPriority.opusFirst,
      );
      final format = await database
          .customSelect('SELECT audio_format_priority FROM playback_settings')
          .getSingle();
      expect(format.data['audio_format_priority'], 'opus,aac');
    },
  );
}
