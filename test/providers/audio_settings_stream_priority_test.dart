import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/audio/audio_settings_provider.dart';
import '../support/audio_settings_notifier.dart';
import '../support/fakes/fake_isar.dart';
import '../support/fakes/fake_settings_repository.dart';

void main() {
  test(
    'audio settings expose netease stream priority default (D2 broken window)',
    () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final repository = FakeSettingsRepository(Settings());
      final notifier = audioSettingsNotifierFor(repository);
      await Future<void>.delayed(Duration.zero);

      // 預設與 Settings.streamPriorityFor(SourceIds.netease) 預設一致（[audioOnly]）。
      expect(notifier.state.streamPriorityFor(SourceIds.netease), [
        StreamType.audioOnly,
      ]);
    },
  );

  test('setNeteaseStreamPriority updates state and persists', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final repository = FakeSettingsRepository(Settings());
    final notifier = audioSettingsNotifierFor(repository);
    await Future<void>.delayed(Duration.zero);

    const updated = [StreamType.muxed, StreamType.audioOnly];
    await notifier.setStreamPriority(SourceIds.netease, updated);

    expect(notifier.state.streamPriorityFor(SourceIds.netease), updated);
    // 持久化寫回底層 Settings（與 youtube/bilibili setter 同契約）。
    expect(repository.settings.streamPriorityFor(SourceIds.netease), updated);
  });
}
