import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/settings.dart';
import '../data/repositories/settings_repository.dart';
import 'repository_providers.dart';

/// 音频设置状态
class AudioSettingsState {
  final AudioQualityLevel qualityLevel;
  final List<AudioFormat> formatPriority;
  final List<StreamType> youtubeStreamPriority;
  final List<StreamType> bilibiliStreamPriority;
  final bool isLoading;

  const AudioSettingsState({
    this.qualityLevel = AudioQualityLevel.high,
    this.formatPriority = const [
      AudioFormat.aac,
      AudioFormat.opus,
    ],
    this.youtubeStreamPriority = const [
      StreamType.audioOnly,
      StreamType.muxed,
      StreamType.hls,
    ],
    this.bilibiliStreamPriority = const [
      StreamType.audioOnly,
      StreamType.muxed,
    ],
    this.isLoading = true,
  });

  AudioSettingsState copyWith({
    AudioQualityLevel? qualityLevel,
    List<AudioFormat>? formatPriority,
    List<StreamType>? youtubeStreamPriority,
    List<StreamType>? bilibiliStreamPriority,
    bool? isLoading,
  }) {
    return AudioSettingsState(
      qualityLevel: qualityLevel ?? this.qualityLevel,
      formatPriority: formatPriority ?? this.formatPriority,
      youtubeStreamPriority: youtubeStreamPriority ?? this.youtubeStreamPriority,
      bilibiliStreamPriority: bilibiliStreamPriority ?? this.bilibiliStreamPriority,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 音频设置管理器
class AudioSettingsNotifier extends StateNotifier<AudioSettingsState> {
  final SettingsRepository _settingsRepository;
  Settings? _settings;

  AudioSettingsNotifier(this._settingsRepository) : super(const AudioSettingsState()) {
    _loadSettings();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    _settings = await _settingsRepository.get();
    state = AudioSettingsState(
      qualityLevel: _settings!.audioQualityLevel,
      formatPriority: _settings!.audioFormatPriorityList,
      youtubeStreamPriority: _settings!.youtubeStreamPriorityList,
      bilibiliStreamPriority: _settings!.bilibiliStreamPriorityList,
      isLoading: false,
    );
  }

  /// 设置音质等级
  Future<void> setQualityLevel(AudioQualityLevel level) async {
    if (_settings == null) return;

    _settings!.audioQualityLevel = level;
    await _settingsRepository.save(_settings!);
    state = state.copyWith(qualityLevel: level);
  }

  /// 设置格式优先级
  Future<void> setFormatPriority(List<AudioFormat> priority) async {
    if (_settings == null) return;

    _settings!.audioFormatPriorityList = priority;
    await _settingsRepository.save(_settings!);
    state = state.copyWith(formatPriority: priority);
  }

  /// 设置 YouTube 流优先级
  Future<void> setYoutubeStreamPriority(List<StreamType> priority) async {
    if (_settings == null) return;

    _settings!.youtubeStreamPriorityList = priority;
    await _settingsRepository.save(_settings!);
    state = state.copyWith(youtubeStreamPriority: priority);
  }

  /// 设置 Bilibili 流优先级
  Future<void> setBilibiliStreamPriority(List<StreamType> priority) async {
    if (_settings == null) return;

    _settings!.bilibiliStreamPriorityList = priority;
    await _settingsRepository.save(_settings!);
    state = state.copyWith(bilibiliStreamPriority: priority);
  }
}

/// 音频设置 Provider
final audioSettingsProvider = StateNotifierProvider<AudioSettingsNotifier, AudioSettingsState>((ref) {
  final settingsRepository = ref.watch(settingsRepositoryProvider);
  return AudioSettingsNotifier(settingsRepository);
});

/// 便捷 Provider - 音质等级
final audioQualityLevelProvider = Provider<AudioQualityLevel>((ref) {
  return ref.watch(audioSettingsProvider).qualityLevel;
});

/// 便捷 Provider - 格式优先级
final audioFormatPriorityProvider = Provider<List<AudioFormat>>((ref) {
  return ref.watch(audioSettingsProvider).formatPriority;
});

/// 便捷 Provider - YouTube 流优先级
final youtubeStreamPriorityProvider = Provider<List<StreamType>>((ref) {
  return ref.watch(audioSettingsProvider).youtubeStreamPriority;
});

/// 便捷 Provider - Bilibili 流优先级
final bilibiliStreamPriorityProvider = Provider<List<StreamType>>((ref) {
  return ref.watch(audioSettingsProvider).bilibiliStreamPriority;
});
