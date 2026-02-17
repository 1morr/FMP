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
  final bool autoMatchLyrics;
  final List<String> lyricsSourceOrder;
  final Set<String> disabledLyricsSources;
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
    this.autoMatchLyrics = true,
    this.lyricsSourceOrder = const ['netease', 'qqmusic', 'lrclib'],
    this.disabledLyricsSources = const {'lrclib'},
    this.isLoading = true,
  });

  /// 获取启用的歌词源（按优先级排序，排除禁用的）
  List<String> get enabledLyricsSourceOrder =>
      lyricsSourceOrder.where((s) => !disabledLyricsSources.contains(s)).toList();

  AudioSettingsState copyWith({
    AudioQualityLevel? qualityLevel,
    List<AudioFormat>? formatPriority,
    List<StreamType>? youtubeStreamPriority,
    List<StreamType>? bilibiliStreamPriority,
    bool? autoMatchLyrics,
    List<String>? lyricsSourceOrder,
    Set<String>? disabledLyricsSources,
    bool? isLoading,
  }) {
    return AudioSettingsState(
      qualityLevel: qualityLevel ?? this.qualityLevel,
      formatPriority: formatPriority ?? this.formatPriority,
      youtubeStreamPriority: youtubeStreamPriority ?? this.youtubeStreamPriority,
      bilibiliStreamPriority: bilibiliStreamPriority ?? this.bilibiliStreamPriority,
      autoMatchLyrics: autoMatchLyrics ?? this.autoMatchLyrics,
      lyricsSourceOrder: lyricsSourceOrder ?? this.lyricsSourceOrder,
      disabledLyricsSources: disabledLyricsSources ?? this.disabledLyricsSources,
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
      autoMatchLyrics: _settings!.autoMatchLyrics,
      lyricsSourceOrder: _settings!.lyricsSourcePriorityList,
      disabledLyricsSources: _settings!.disabledLyricsSourcesSet,
      isLoading: false,
    );
  }

  /// 设置音质等级
  Future<void> setQualityLevel(AudioQualityLevel level) async {
    if (_settings == null) return;

    await _settingsRepository.update((s) => s.audioQualityLevel = level);
    _settings!.audioQualityLevel = level;
    state = state.copyWith(qualityLevel: level);
  }

  /// 设置格式优先级
  Future<void> setFormatPriority(List<AudioFormat> priority) async {
    if (_settings == null) return;

    await _settingsRepository.update((s) => s.audioFormatPriorityList = priority);
    _settings!.audioFormatPriorityList = priority;
    state = state.copyWith(formatPriority: priority);
  }

  /// 设置 YouTube 流优先级
  Future<void> setYoutubeStreamPriority(List<StreamType> priority) async {
    if (_settings == null) return;

    await _settingsRepository.update((s) => s.youtubeStreamPriorityList = priority);
    _settings!.youtubeStreamPriorityList = priority;
    state = state.copyWith(youtubeStreamPriority: priority);
  }

  /// 设置 Bilibili 流优先级
  Future<void> setBilibiliStreamPriority(List<StreamType> priority) async {
    if (_settings == null) return;

    await _settingsRepository.update((s) => s.bilibiliStreamPriorityList = priority);
    _settings!.bilibiliStreamPriorityList = priority;
    state = state.copyWith(bilibiliStreamPriority: priority);
  }

  /// 设置自动匹配歌词
  Future<void> setAutoMatchLyrics(bool enabled) async {
    if (_settings == null) return;

    await _settingsRepository.update((s) => s.autoMatchLyrics = enabled);
    _settings!.autoMatchLyrics = enabled;
    state = state.copyWith(autoMatchLyrics: enabled);
  }

  /// 设置歌词匹配源优先级顺序
  Future<void> setLyricsSourceOrder(List<String> order) async {
    if (_settings == null) return;

    await _settingsRepository.update((s) => s.lyricsSourcePriorityList = order);
    _settings!.lyricsSourcePriorityList = order;
    state = state.copyWith(lyricsSourceOrder: order);
  }

  /// 切换歌词源的启用/禁用状态
  Future<void> toggleLyricsSource(String source, bool enabled) async {
    if (_settings == null) return;

    final disabled = Set<String>.from(state.disabledLyricsSources);
    if (enabled) {
      disabled.remove(source);
    } else {
      disabled.add(source);
    }

    await _settingsRepository.update((s) => s.disabledLyricsSourcesSet = disabled);
    _settings!.disabledLyricsSourcesSet = disabled;
    state = state.copyWith(disabledLyricsSources: disabled);
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

/// 便捷 Provider - 歌词源优先级顺序
final lyricsSourceOrderProvider = Provider<List<String>>((ref) {
  return ref.watch(audioSettingsProvider).lyricsSourceOrder;
});

/// 便捷 Provider - 禁用的歌词源
final disabledLyricsSourcesProvider = Provider<Set<String>>((ref) {
  return ref.watch(audioSettingsProvider).disabledLyricsSources;
});

/// 便捷 Provider - 启用的歌词源（按优先级排序）
final enabledLyricsSourceOrderProvider = Provider<List<String>>((ref) {
  return ref.watch(audioSettingsProvider).enabledLyricsSourceOrder;
});
