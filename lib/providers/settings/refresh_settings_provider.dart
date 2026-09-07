import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/settings.dart';
import '../../services/cache/ranking_cache_service.dart';
import '../../services/radio/radio_refresh_service.dart';
import '../database/repository_providers.dart';

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
      rankingRefreshIntervalMinutes:
          rankingRefreshIntervalMinutes ?? this.rankingRefreshIntervalMinutes,
      radioRefreshIntervalMinutes:
          radioRefreshIntervalMinutes ?? this.radioRefreshIntervalMinutes,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 刷新间隔设置管理器
class RefreshSettingsNotifier extends Notifier<RefreshSettingsState> {
  Settings? _settings;

  @override
  RefreshSettingsState build() {
    _loadSettings();
    return const RefreshSettingsState();
  }

  Future<void> _loadSettings() async {
    final settingsRepository = ref.read(settingsRepositoryProvider);
    _settings = await settingsRepository.get();
    // Riverpod 3 對 dispose 之後的 Ref 會拋 UnmountedRefException，
    // 而 Notifier 對 dispose 之後的 state 賦值本來就會拋。
    if (!ref.mounted) return;
    final rankingMinutes = _settings!.rankingRefreshIntervalMinutes;
    final radioMinutes = _settings!.radioRefreshIntervalMinutes;

    state = RefreshSettingsState(
      rankingRefreshIntervalMinutes: rankingMinutes,
      radioRefreshIntervalMinutes: radioMinutes,
      isLoading: false,
    );

    // 用用户设置的间隔更新服务定时器
    ref.read(rankingCacheServiceProvider.notifier).updateRefreshInterval(
          Duration(minutes: rankingMinutes),
        );
    RadioRefreshService.instance.updateRefreshInterval(
      Duration(minutes: radioMinutes),
    );
  }

  Future<void> setRankingRefreshInterval(int minutes) async {
    if (_settings == null) return;

    final settingsRepository = ref.read(settingsRepositoryProvider);
    await settingsRepository
        .update((s) => s.rankingRefreshIntervalMinutes = minutes);
    if (!ref.mounted) return;
    _settings!.rankingRefreshIntervalMinutes = minutes;
    state = state.copyWith(rankingRefreshIntervalMinutes: minutes);

    ref.read(rankingCacheServiceProvider.notifier).updateRefreshInterval(
          Duration(minutes: minutes),
        );
  }

  Future<void> setRadioRefreshInterval(int minutes) async {
    if (_settings == null) return;

    final settingsRepository = ref.read(settingsRepositoryProvider);
    await settingsRepository
        .update((s) => s.radioRefreshIntervalMinutes = minutes);
    if (!ref.mounted) return;
    _settings!.radioRefreshIntervalMinutes = minutes;
    state = state.copyWith(radioRefreshIntervalMinutes: minutes);

    RadioRefreshService.instance.updateRefreshInterval(
      Duration(minutes: minutes),
    );
  }
}

/// 刷新间隔设置 Provider
final refreshSettingsProvider =
    NotifierProvider<RefreshSettingsNotifier, RefreshSettingsState>(
        RefreshSettingsNotifier.new);
