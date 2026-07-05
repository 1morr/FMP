import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/providers/audio/audio_settings_provider.dart';
import 'package:isar/isar.dart';

void main() {
  test('audio settings expose netease stream priority default (D2 broken window)',
      () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final repository = _FakeSettingsRepository(Settings());
    final notifier = AudioSettingsNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    // 預設與 Settings.neteaseStreamPriorityList 預設一致（[audioOnly]）。
    expect(notifier.state.neteaseStreamPriority, [StreamType.audioOnly]);
  });

  test('setNeteaseStreamPriority updates state and persists', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final repository = _FakeSettingsRepository(Settings());
    final notifier = AudioSettingsNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    const updated = [StreamType.muxed, StreamType.audioOnly];
    await notifier.setNeteaseStreamPriority(updated);

    expect(notifier.state.neteaseStreamPriority, updated);
    // 持久化寫回底層 Settings（與 youtube/bilibili setter 同契約）。
    expect(repository.settings.neteaseStreamPriorityList, updated);
  });
}

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository(this.settings) : super(_FakeIsar());

  final Settings settings;

  @override
  Future<Settings> get() async => settings;

  @override
  Future<Settings> update(void Function(Settings settings) mutate) async {
    mutate(settings);
    return settings;
  }
}

class _FakeIsar extends Fake implements Isar {}
