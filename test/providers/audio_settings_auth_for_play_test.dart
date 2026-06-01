import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/providers/audio/audio_settings_provider.dart';
import 'package:isar/isar.dart';

void main() {
  test('audio settings expose auth-for-play defaults', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final repository = _FakeSettingsRepository(Settings());
    final notifier = AudioSettingsNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.useBilibiliAuthForPlay, isFalse);
    expect(notifier.state.useYoutubeAuthForPlay, isFalse);
    expect(notifier.state.useNeteaseAuthForPlay, isTrue);
  });

  test('audio settings update auth-for-play per source', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final repository = _FakeSettingsRepository(Settings());
    final notifier = AudioSettingsNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    await notifier.setAuthForPlay(SourceType.youtube, true);
    await notifier.setAuthForPlay(SourceType.netease, false);

    expect(notifier.state.useYoutubeAuthForPlay, isTrue);
    expect(notifier.state.useNeteaseAuthForPlay, isFalse);
    expect(repository.settings.useYoutubeAuthForPlay, isTrue);
    expect(repository.settings.useNeteaseAuthForPlay, isFalse);
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
