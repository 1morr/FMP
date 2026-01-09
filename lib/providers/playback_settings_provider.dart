import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/settings.dart';
import 'theme_provider.dart';

/// 播放设置状态
class PlaybackSettingsState {
  final bool autoScrollToCurrentTrack;
  final bool isLoading;

  const PlaybackSettingsState({
    this.autoScrollToCurrentTrack = false,
    this.isLoading = true,
  });

  PlaybackSettingsState copyWith({
    bool? autoScrollToCurrentTrack,
    bool? isLoading,
  }) {
    return PlaybackSettingsState(
      autoScrollToCurrentTrack: autoScrollToCurrentTrack ?? this.autoScrollToCurrentTrack,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 播放设置管理器
class PlaybackSettingsNotifier extends StateNotifier<PlaybackSettingsState> {
  final Ref _ref;
  Settings? _settings;

  PlaybackSettingsNotifier(this._ref) : super(const PlaybackSettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settingsRepository = _ref.read(settingsRepositoryProvider);
    _settings = await settingsRepository.get();
    state = PlaybackSettingsState(
      autoScrollToCurrentTrack: _settings!.autoScrollToCurrentTrack,
      isLoading: false,
    );
  }

  Future<void> setAutoScrollToCurrentTrack(bool value) async {
    if (_settings == null) return;

    _settings!.autoScrollToCurrentTrack = value;
    final settingsRepository = _ref.read(settingsRepositoryProvider);
    await settingsRepository.save(_settings!);
    state = state.copyWith(autoScrollToCurrentTrack: value);
  }
}

/// 播放设置 Provider
final playbackSettingsProvider =
    StateNotifierProvider<PlaybackSettingsNotifier, PlaybackSettingsState>((ref) {
  return PlaybackSettingsNotifier(ref);
});

/// 便捷 Provider - 是否自动跳转到当前播放
final autoScrollToCurrentTrackProvider = Provider<bool>((ref) {
  return ref.watch(playbackSettingsProvider).autoScrollToCurrentTrack;
});
