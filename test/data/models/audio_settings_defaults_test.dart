import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/providers/audio_settings_provider.dart';
import 'package:fmp/services/backup/backup_data.dart';

void main() {
  group('Audio settings defaults', () {
    test('enable all direct audio sources by default', () {
      final settings = Settings();

      expect(settings.enabledSources, ['bilibili', 'youtube', 'netease']);
      expect(settings.enabledSourceTypes, {
        SourceType.bilibili,
        SourceType.youtube,
        SourceType.netease,
      });
      expect(SettingsBackup().enabledSources, [
        'bilibili',
        'youtube',
        'netease',
      ]);
      expect(SettingsBackup.fromJson({}).enabledSources, [
        'bilibili',
        'youtube',
        'netease',
      ]);
    });

    test('prefer Opus before AAC by default', () {
      final settings = Settings();

      expect(settings.audioFormatPriority, 'opus,aac');
      expect(settings.audioFormatPriorityList, [
        AudioFormat.opus,
        AudioFormat.aac,
      ]);

      settings.audioFormatPriority = '';
      expect(settings.audioFormatPriorityList, [
        AudioFormat.opus,
        AudioFormat.aac,
      ]);

      const state = AudioSettingsState();
      expect(state.formatPriority, [
        AudioFormat.opus,
        AudioFormat.aac,
      ]);

      expect(AudioStreamConfig.defaultConfig.formatPriority, [
        AudioFormat.opus,
        AudioFormat.aac,
      ]);
      expect(SettingsBackup().audioFormatPriority, 'opus,aac');
      expect(SettingsBackup.fromJson({}).audioFormatPriority, 'opus,aac');
    });

    test('keeps default stream priority order per source', () {
      final settings = Settings();
      const state = AudioSettingsState();

      expect(settings.youtubeStreamPriority, 'audioOnly,muxed,hls');
      expect(settings.youtubeStreamPriorityList, [
        StreamType.audioOnly,
        StreamType.muxed,
        StreamType.hls,
      ]);
      expect(state.youtubeStreamPriority, [
        StreamType.audioOnly,
        StreamType.muxed,
        StreamType.hls,
      ]);
      expect(AudioStreamConfig.defaultConfig.streamPriority, [
        StreamType.audioOnly,
        StreamType.muxed,
        StreamType.hls,
      ]);

      expect(settings.bilibiliStreamPriority, 'audioOnly,muxed');
      expect(settings.bilibiliStreamPriorityList, [
        StreamType.audioOnly,
        StreamType.muxed,
      ]);
      expect(state.bilibiliStreamPriority, [
        StreamType.audioOnly,
        StreamType.muxed,
      ]);
    });

    test('HLS descriptions mark the stream as not recommended', () {
      final expectedDescriptions = {
        'zh-CN': '分段流，不推荐',
        'zh-TW': '分段串流，不推薦',
        'en': 'Segmented stream, not recommended',
      };

      for (final entry in expectedDescriptions.entries) {
        final file = File('lib/i18n/${entry.key}/audioSettings.i18n.json');
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final streamPriority = json['streamPriority'] as Map<String, dynamic>;

        expect(
          streamPriority['hlsDescription'],
          entry.value,
          reason: 'locale ${entry.key}',
        );
      }
    });
  });
}
