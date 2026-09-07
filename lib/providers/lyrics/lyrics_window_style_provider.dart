import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/settings.dart';
import '../../data/repositories/settings_repository.dart';
import '../../services/lyrics/lyrics_window_style.dart';
import '../database/repository_providers.dart';

class LyricsWindowStyleNotifier extends Notifier<LyricsWindowStyle> {
  late SettingsRepository _settingsRepository;
  Settings? _settings;

  @override
  LyricsWindowStyle build() {
    _settingsRepository = ref.watch(settingsRepositoryProvider);
    _loadSettings();
    return LyricsWindowStyle.defaults;
  }

  Future<void> _loadSettings() async {
    _settings = await _settingsRepository.get();
    if (!ref.mounted) return;
    state = LyricsWindowStyle.fromSettings(_settings!);
  }

  Future<void> setStyle(LyricsWindowStyle style) async {
    final updated = await _settingsRepository.update(style.applyToSettings);
    _settings = updated;
    if (!ref.mounted) return;
    state = LyricsWindowStyle.fromSettings(updated);
  }

  Future<void> resetStyle() async {
    final updated =
        await _settingsRepository.update(LyricsWindowStyle.resetSettings);
    _settings = updated;
    if (!ref.mounted) return;
    state = LyricsWindowStyle.fromSettings(updated);
  }
}

final lyricsWindowStyleProvider =
    NotifierProvider<LyricsWindowStyleNotifier, LyricsWindowStyle>(
        LyricsWindowStyleNotifier.new);
