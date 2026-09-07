import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/providers/audio/audio_settings_provider.dart';
import 'package:fmp/providers/database/repository_providers.dart';

/// `AudioSettingsNotifier` 以前吃一個 `SettingsRepository` 建構子參數；
/// `Notifier.new` 不吃參數，而 `Notifier` 需要一個 provider element 才能碰
/// `state`，所以測試改成從 container 取實例。
AudioSettingsNotifier audioSettingsNotifierFor(SettingsRepository repository) {
  final container = ProviderContainer(overrides: [
    settingsRepositoryProvider.overrideWith((ref) => repository),
  ]);
  addTearDown(container.dispose);
  return container.read(audioSettingsProvider.notifier);
}
