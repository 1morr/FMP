import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/settings.dart';
import 'repository_providers.dart';

/// 播放设置状态
class PlaybackSettingsState {
  final bool autoScrollToCurrentTrack;
  final bool rememberPlaybackPosition;
  final int restartRewindSeconds;
  final int tempPlayRewindSeconds;
  final bool isLoading;

  const PlaybackSettingsState({
    this.autoScrollToCurrentTrack = false,
    this.rememberPlaybackPosition = true,
    this.restartRewindSeconds = 0,
    this.tempPlayRewindSeconds = 10,
    this.isLoading = true,
  });

  PlaybackSettingsState copyWith({
    bool? autoScrollToCurrentTrack,
    bool? rememberPlaybackPosition,
    int? restartRewindSeconds,
    int? tempPlayRewindSeconds,
    bool? isLoading,
  }) {
    return PlaybackSettingsState(
      autoScrollToCurrentTrack: autoScrollToCurrentTrack ?? this.autoScrollToCurrentTrack,
      rememberPlaybackPosition: rememberPlaybackPosition ?? this.rememberPlaybackPosition,
      restartRewindSeconds: restartRewindSeconds ?? this.restartRewindSeconds,
      tempPlayRewindSeconds: tempPlayRewindSeconds ?? this.tempPlayRewindSeconds,
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
      rememberPlaybackPosition: _settings!.rememberPlaybackPosition,
      restartRewindSeconds: _settings!.restartRewindSeconds,
      tempPlayRewindSeconds: _settings!.tempPlayRewindSeconds,
      isLoading: false,
    );
  }

  Future<void> setAutoScrollToCurrentTrack(bool value) async {
    if (_settings == null) return;

    final settingsRepository = _ref.read(settingsRepositoryProvider);
    await settingsRepository.update((s) => s.autoScrollToCurrentTrack = value);
    _settings!.autoScrollToCurrentTrack = value;
    state = state.copyWith(autoScrollToCurrentTrack: value);
  }

  Future<void> setRememberPlaybackPosition(bool value) async {
    if (_settings == null) return;

    final settingsRepository = _ref.read(settingsRepositoryProvider);
    await settingsRepository.update((s) => s.rememberPlaybackPosition = value);
    _settings!.rememberPlaybackPosition = value;
    state = state.copyWith(rememberPlaybackPosition: value);
  }

  Future<void> setRestartRewindSeconds(int value) async {
    if (_settings == null) return;

    final settingsRepository = _ref.read(settingsRepositoryProvider);
    await settingsRepository.update((s) => s.restartRewindSeconds = value);
    _settings!.restartRewindSeconds = value;
    state = state.copyWith(restartRewindSeconds: value);
  }

  Future<void> setTempPlayRewindSeconds(int value) async {
    if (_settings == null) return;

    final settingsRepository = _ref.read(settingsRepositoryProvider);
    await settingsRepository.update((s) => s.tempPlayRewindSeconds = value);
    _settings!.tempPlayRewindSeconds = value;
    state = state.copyWith(tempPlayRewindSeconds: value);
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

/// 便捷 Provider - 是否记住播放位置
final rememberPlaybackPositionProvider = Provider<bool>((ref) {
  return ref.watch(playbackSettingsProvider).rememberPlaybackPosition;
});
