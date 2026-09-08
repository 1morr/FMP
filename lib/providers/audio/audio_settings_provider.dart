import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/services/lyrics/lyrics_ai_config_service.dart';
import 'package:fmp/providers/database/repository_providers.dart';

/// 音频设置状态
class AudioSettingsState {
  final AudioQualityLevel qualityLevel;
  final List<AudioFormat> formatPriority;

  /// 每個音源的串流優先序，key 是 [SourceIds] 的音源 id。
  final Map<String, List<StreamType>> streamPriority;
  final bool autoMatchLyrics;
  final List<String> lyricsSourceOrder;
  final Set<String> disabledLyricsSources;
  final LyricsAiTitleParsingMode lyricsAiTitleParsingMode;
  final bool allowPlainLyricsAutoMatch;
  final String lyricsAiEndpoint;
  final String lyricsAiModel;
  final int lyricsAiTimeoutSeconds;
  final bool lyricsAiApiKeyConfigured;

  /// 每個音源是否在播放時帶上登入狀態，key 是 [SourceIds] 的音源 id。
  final Map<String, bool> useAuthForPlay;
  final bool isLoading;

  const AudioSettingsState({
    this.qualityLevel = AudioQualityLevel.high,
    this.formatPriority = const [AudioFormat.opus, AudioFormat.aac],
    this.streamPriority = const {},
    this.autoMatchLyrics = true,
    this.lyricsSourceOrder = const ['netease', 'qqmusic', 'lrclib'],
    this.disabledLyricsSources = const {'lrclib'},
    this.lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.off,
    this.allowPlainLyricsAutoMatch = false,
    this.lyricsAiEndpoint = '',
    this.lyricsAiModel = '',
    this.lyricsAiTimeoutSeconds = AppConstants.lyricsAiDefaultTimeoutSeconds,
    this.lyricsAiApiKeyConfigured = false,
    this.useAuthForPlay = const {},
    this.isLoading = true,
  });

  /// 指定音源的串流優先序；還沒載入完成時回傳該音源的預設。
  List<StreamType> streamPriorityFor(String sourceId) =>
      streamPriority[sourceId] ?? defaultStreamPriorityFor(sourceId);

  /// 指定音源是否帶上登入狀態；還沒載入完成時回傳該音源的預設。
  bool authForPlay(String sourceId) =>
      useAuthForPlay[sourceId] ?? defaultUseAuthForPlayFor(sourceId);

  /// 获取启用的歌词源（按优先级排序，排除禁用的）
  List<String> get enabledLyricsSourceOrder => lyricsSourceOrder
      .where((s) => !disabledLyricsSources.contains(s))
      .toList();

  AudioSettingsState copyWith({
    AudioQualityLevel? qualityLevel,
    List<AudioFormat>? formatPriority,
    Map<String, List<StreamType>>? streamPriority,
    bool? autoMatchLyrics,
    List<String>? lyricsSourceOrder,
    Set<String>? disabledLyricsSources,
    LyricsAiTitleParsingMode? lyricsAiTitleParsingMode,
    bool? allowPlainLyricsAutoMatch,
    String? lyricsAiEndpoint,
    String? lyricsAiModel,
    int? lyricsAiTimeoutSeconds,
    bool? lyricsAiApiKeyConfigured,
    Map<String, bool>? useAuthForPlay,
    bool? isLoading,
  }) {
    return AudioSettingsState(
      qualityLevel: qualityLevel ?? this.qualityLevel,
      formatPriority: formatPriority ?? this.formatPriority,
      streamPriority: streamPriority ?? this.streamPriority,
      autoMatchLyrics: autoMatchLyrics ?? this.autoMatchLyrics,
      lyricsSourceOrder: lyricsSourceOrder ?? this.lyricsSourceOrder,
      disabledLyricsSources:
          disabledLyricsSources ?? this.disabledLyricsSources,
      lyricsAiTitleParsingMode:
          lyricsAiTitleParsingMode ?? this.lyricsAiTitleParsingMode,
      allowPlainLyricsAutoMatch:
          allowPlainLyricsAutoMatch ?? this.allowPlainLyricsAutoMatch,
      lyricsAiEndpoint: lyricsAiEndpoint ?? this.lyricsAiEndpoint,
      lyricsAiModel: lyricsAiModel ?? this.lyricsAiModel,
      lyricsAiTimeoutSeconds:
          lyricsAiTimeoutSeconds ?? this.lyricsAiTimeoutSeconds,
      lyricsAiApiKeyConfigured:
          lyricsAiApiKeyConfigured ?? this.lyricsAiApiKeyConfigured,
      useAuthForPlay: useAuthForPlay ?? this.useAuthForPlay,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 音频设置管理器
class AudioSettingsNotifier extends Notifier<AudioSettingsState> {
  late SettingsRepository _settingsRepository;
  // `late`，不是 `late final`：`build()` 會重跑，而重跑時實例是同一個。
  late LyricsAiConfigService _lyricsAiConfigService;
  Settings? _settings;

  @override
  AudioSettingsState build() {
    _settingsRepository = ref.watch(settingsRepositoryProvider);
    _lyricsAiConfigService = LyricsAiConfigService(
      loadSettings: _settingsRepository.get,
    );
    _loadSettings();
    return const AudioSettingsState();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    _settings = await _settingsRepository.get();
    final lyricsAiApiKey = await _lyricsAiConfigService.readApiKey();
    state = AudioSettingsState(
      qualityLevel: _settings!.audioQualityLevel,
      formatPriority: _settings!.audioFormatPriorityList,
      streamPriority: {
        for (final sourceId in SourceIds.values)
          sourceId: _settings!.streamPriorityFor(sourceId),
      },
      autoMatchLyrics: _settings!.autoMatchLyrics,
      lyricsSourceOrder: _settings!.lyricsSourcePriorityList,
      disabledLyricsSources: _settings!.disabledLyricsSourcesSet,
      lyricsAiTitleParsingMode: _settings!.lyricsAiTitleParsingMode,
      allowPlainLyricsAutoMatch: _settings!.allowPlainLyricsAutoMatch,
      lyricsAiEndpoint: _settings!.lyricsAiEndpoint.trim(),
      lyricsAiModel: _settings!.lyricsAiModel.trim(),
      lyricsAiTimeoutSeconds: _settings!.lyricsAiTimeoutSeconds < 1
          ? AppConstants.lyricsAiDefaultTimeoutSeconds
          : _settings!.lyricsAiTimeoutSeconds,
      lyricsAiApiKeyConfigured: lyricsAiApiKey.isNotEmpty,
      useAuthForPlay: {
        for (final sourceId in SourceIds.values)
          sourceId: _settings!.useAuthForPlay(sourceId),
      },
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

    final previous = state.formatPriority;
    state = state.copyWith(formatPriority: priority);

    try {
      await _settingsRepository.update(
        (s) => s.audioFormatPriorityList = priority,
      );
      _settings!.audioFormatPriorityList = priority;
    } catch (_) {
      state = state.copyWith(formatPriority: previous);
    }
  }

  /// 设置指定音源的流优先级
  Future<void> setStreamPriority(
    String sourceId,
    List<StreamType> priority,
  ) async {
    if (_settings == null) return;

    final previous = state.streamPriority;
    state = state.copyWith(streamPriority: {...previous, sourceId: priority});

    try {
      await _settingsRepository.update(
        (s) => s.setStreamPriorityFor(sourceId, priority),
      );
      _settings!.setStreamPriorityFor(sourceId, priority);
    } catch (_) {
      state = state.copyWith(streamPriority: previous);
    }
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

  /// 设置 AI 标题解析模式
  Future<void> setLyricsAiTitleParsingMode(
    LyricsAiTitleParsingMode mode,
  ) async {
    if (_settings == null) return;

    await _settingsRepository.update((s) => s.lyricsAiTitleParsingMode = mode);
    _settings!.lyricsAiTitleParsingMode = mode;
    state = state.copyWith(lyricsAiTitleParsingMode: mode);
  }

  /// 设置是否允许纯文本歌词自动匹配
  Future<void> setAllowPlainLyricsAutoMatch(bool enabled) async {
    if (_settings == null) return;

    await _settingsRepository.update(
      (s) => s.allowPlainLyricsAutoMatch = enabled,
    );
    _settings!.allowPlainLyricsAutoMatch = enabled;
    state = state.copyWith(allowPlainLyricsAutoMatch: enabled);
  }

  /// 设置 AI 标题解析 API 端点
  Future<void> setLyricsAiEndpoint(String endpoint) async {
    if (_settings == null) return;

    final trimmed = endpoint.trim();
    await _settingsRepository.update((s) => s.lyricsAiEndpoint = trimmed);
    _settings!.lyricsAiEndpoint = trimmed;
    state = state.copyWith(lyricsAiEndpoint: trimmed);
  }

  /// 设置 AI 标题解析模型
  Future<void> setLyricsAiModel(String model) async {
    if (_settings == null) return;

    final trimmed = model.trim();
    await _settingsRepository.update((s) => s.lyricsAiModel = trimmed);
    _settings!.lyricsAiModel = trimmed;
    state = state.copyWith(lyricsAiModel: trimmed);
  }

  /// 设置 AI 标题解析超时时间
  Future<void> setLyricsAiTimeoutSeconds(int seconds) async {
    if (_settings == null) return;

    final normalized = seconds < 1
        ? AppConstants.lyricsAiDefaultTimeoutSeconds
        : seconds;
    await _settingsRepository.update(
      (s) => s.lyricsAiTimeoutSeconds = normalized,
    );
    _settings!.lyricsAiTimeoutSeconds = normalized;
    state = state.copyWith(lyricsAiTimeoutSeconds: normalized);
  }

  /// 设置 AI 标题解析 API Key
  Future<void> setLyricsAiApiKey(String apiKey) async {
    if (_settings == null) return;

    await _lyricsAiConfigService.saveApiKey(apiKey);
    state = state.copyWith(lyricsAiApiKeyConfigured: apiKey.trim().isNotEmpty);
  }

  /// 设置播放时是否使用指定音源的登录凭证
  Future<void> setAuthForPlay(String sourceType, bool enabled) async {
    if (_settings == null) return;

    final previous = state;
    state = state.copyWith(
      useAuthForPlay: {...state.useAuthForPlay, sourceType: enabled},
    );

    try {
      await _settingsRepository.update(
        (settings) => settings.setUseAuthForPlay(sourceType, enabled),
      );
      _settings!.setUseAuthForPlay(sourceType, enabled);
    } catch (_) {
      state = previous;
    }
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

    await _settingsRepository.update(
      (s) => s.disabledLyricsSourcesSet = disabled,
    );
    _settings!.disabledLyricsSourcesSet = disabled;
    state = state.copyWith(disabledLyricsSources: disabled);
  }
}

/// 音频设置 Provider
final audioSettingsProvider =
    NotifierProvider<AudioSettingsNotifier, AudioSettingsState>(
      AudioSettingsNotifier.new,
    );

/// 便捷 Provider - 音质等级
final audioQualityLevelProvider = Provider<AudioQualityLevel>((ref) {
  return ref.watch(audioSettingsProvider).qualityLevel;
});

/// 便捷 Provider - 格式优先级
final audioFormatPriorityProvider = Provider<List<AudioFormat>>((ref) {
  return ref.watch(audioSettingsProvider).formatPriority;
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
