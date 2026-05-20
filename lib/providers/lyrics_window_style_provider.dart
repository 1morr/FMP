import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/settings.dart';
import '../data/repositories/settings_repository.dart';
import '../services/lyrics/lyrics_window_style.dart';
import 'repository_providers.dart';

class LyricsWindowStyleNotifier extends StateNotifier<LyricsWindowStyle> {
  final SettingsRepository _settingsRepository;
  Settings? _settings;

  LyricsWindowStyleNotifier(this._settingsRepository)
      : super(LyricsWindowStyle.defaults) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _settings = await _settingsRepository.get();
    if (!mounted) return;
    state = LyricsWindowStyle.fromSettings(_settings!);
  }

  Future<void> setStyle(LyricsWindowStyle style) async {
    final updated = await _settingsRepository.update(style.applyToSettings);
    _settings = updated;
    if (!mounted) return;
    state = LyricsWindowStyle.fromSettings(updated);
  }

  Future<void> resetStyle() async {
    final updated =
        await _settingsRepository.update(LyricsWindowStyle.resetSettings);
    _settings = updated;
    if (!mounted) return;
    state = LyricsWindowStyle.fromSettings(updated);
  }
}

final lyricsWindowStyleProvider =
    StateNotifierProvider<LyricsWindowStyleNotifier, LyricsWindowStyle>((ref) {
  final settingsRepository = ref.watch(settingsRepositoryProvider);
  return LyricsWindowStyleNotifier(settingsRepository);
});
