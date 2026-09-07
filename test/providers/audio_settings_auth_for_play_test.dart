import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/providers/audio/audio_settings_provider.dart';
import 'package:isar_community/isar.dart';
import '../support/audio_settings_notifier.dart';

void main() {
  test('audio settings expose auth-for-play defaults', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final repository = _FakeSettingsRepository(Settings());
    final notifier = audioSettingsNotifierFor(repository);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.authForPlay(SourceIds.bilibili), isFalse);
    expect(notifier.state.authForPlay(SourceIds.youtube), isFalse);
    expect(notifier.state.authForPlay(SourceIds.netease), isTrue);
  });

  test('audio settings update auth-for-play per source', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final repository = _FakeSettingsRepository(Settings());
    final notifier = audioSettingsNotifierFor(repository);
    await Future<void>.delayed(Duration.zero);

    await notifier.setAuthForPlay(SourceIds.youtube, true);
    await notifier.setAuthForPlay(SourceIds.netease, false);

    expect(notifier.state.authForPlay(SourceIds.youtube), isTrue);
    expect(notifier.state.authForPlay(SourceIds.netease), isFalse);
    expect(repository.settings.useAuthForPlay(SourceIds.youtube), isTrue);
    expect(repository.settings.useAuthForPlay(SourceIds.netease), isFalse);
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
