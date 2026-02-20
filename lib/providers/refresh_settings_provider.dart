import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/settings.dart';
import '../services/cache/ranking_cache_service.dart';
import '../services/radio/radio_refresh_service.dart';
import 'repository_providers.dart';

/// 刷新间隔设置状态
class RefreshSettingsState {
  final int rankingRefreshIntervalMinutes;
  final int radioRefreshIntervalMinutes;
  final bool isLoading;

  const RefreshSettingsState({
    this.rankingRefreshIntervalMinutes = 60,
    this.radioRefreshIntervalMinutes = 5,
    this.isLoading = true,
  });

  RefreshSettingsState copyWith({
    int? rankingRefreshIntervalMinutes,
    int? radioRefreshIntervalMinutes,
    bool? isLoading,
  }) {
    return RefreshSettingsState(
      rankingRefreshIntervalMinutes: rankingRefreshIntervalMinutes ?? this.rankingRefreshIntervalMinutes,
      radioRefreshIntervalMinutes: radioRefreshIntervalMinutes ?? this.radioRefreshIntervalMinutes,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 刷新间隔设置管理器
class RefreshSettingsNotifier extends StateNotifier<RefreshSettingsState> {
  final Ref _ref;
  Settings? _settings;

  RefreshSettingsNotifier(this._ref) : super(const RefreshSettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settingsRepository = _ref.read(settingsRepositoryProvider);
    _settings = await settingsRepository.get();
    final rankingMinutes = _settings!.rankingRefreshIntervalMinutes;
    final radioMinutes = _settings!.radioRefreshIntervalMinutes;

    state = RefreshSettingsState(
      rankingRefreshIntervalMinutes: rankingMinutes,
      radioRefreshIntervalMinutes: radioMinutes,
      isLoading: false,
    );

    // 用用户设置的间隔更新服务定时器
    RankingCacheService.instance.updateRefreshInterval(
      Duration(minutes: rankingMinutes),
    );
    RadioRefreshService.instance.updateRefreshInterval(
      Duration(minutes: radioMinutes),
    );
  }

  Future<void> setRankingRefreshInterval(int minutes) async {
    if (_settings == null) return;

    final settingsRepository = _ref.read(settingsRepositoryProvider);
    await settingsRepository.update((s) => s.rankingRefreshIntervalMinutes = minutes);
    _settings!.rankingRefreshIntervalMinutes = minutes;
    state = state.copyWith(rankingRefreshIntervalMinutes: minutes);

    RankingCacheService.instance.updateRefreshInterval(
      Duration(minutes: minutes),
    );
  }

  Future<void> setRadioRefreshInterval(int minutes) async {
    if (_settings == null) return;

    final settingsRepository = _ref.read(settingsRepositoryProvider);
    await settingsRepository.update((s) => s.radioRefreshIntervalMinutes = minutes);
    _settings!.radioRefreshIntervalMinutes = minutes;
    state = state.copyWith(radioRefreshIntervalMinutes: minutes);

    RadioRefreshService.instance.updateRefreshInterval(
      Duration(minutes: minutes),
    );
  }
}

/// 刷新间隔设置 Provider
final refreshSettingsProvider =
    StateNotifierProvider<RefreshSettingsNotifier, RefreshSettingsState>((ref) {
  return RefreshSettingsNotifier(ref);
});
