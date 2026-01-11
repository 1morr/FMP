import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/settings.dart';
import '../data/repositories/settings_repository.dart';
import 'repository_providers.dart';

/// 下载设置状态
class DownloadSettingsState {
  final int maxConcurrentDownloads;
  final DownloadImageOption downloadImageOption;
  final bool isLoading;

  const DownloadSettingsState({
    this.maxConcurrentDownloads = 3,
    this.downloadImageOption = DownloadImageOption.coverOnly,
    this.isLoading = true,
  });

  DownloadSettingsState copyWith({
    int? maxConcurrentDownloads,
    DownloadImageOption? downloadImageOption,
    bool? isLoading,
  }) {
    return DownloadSettingsState(
      maxConcurrentDownloads: maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      downloadImageOption: downloadImageOption ?? this.downloadImageOption,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 下载设置管理器
class DownloadSettingsNotifier extends StateNotifier<DownloadSettingsState> {
  final SettingsRepository _settingsRepository;
  Settings? _settings;

  DownloadSettingsNotifier(this._settingsRepository) : super(const DownloadSettingsState()) {
    _loadSettings();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    _settings = await _settingsRepository.get();
    state = DownloadSettingsState(
      maxConcurrentDownloads: _settings!.maxConcurrentDownloads,
      downloadImageOption: _settings!.downloadImageOption,
      isLoading: false,
    );
  }

  /// 设置最大并发下载数
  Future<void> setMaxConcurrentDownloads(int value) async {
    if (_settings == null) return;
    if (value < 1 || value > 5) return;

    _settings!.maxConcurrentDownloads = value;
    await _settingsRepository.save(_settings!);
    state = state.copyWith(maxConcurrentDownloads: value);
  }

  /// 设置下载图片选项
  Future<void> setDownloadImageOption(DownloadImageOption option) async {
    if (_settings == null) return;

    _settings!.downloadImageOption = option;
    await _settingsRepository.save(_settings!);
    state = state.copyWith(downloadImageOption: option);
  }
}

/// 下载设置 Provider
final downloadSettingsProvider = StateNotifierProvider<DownloadSettingsNotifier, DownloadSettingsState>((ref) {
  final settingsRepository = ref.watch(settingsRepositoryProvider);
  return DownloadSettingsNotifier(settingsRepository);
});

/// 便捷 Provider - 最大并发下载数
final maxConcurrentDownloadsProvider = Provider<int>((ref) {
  return ref.watch(downloadSettingsProvider).maxConcurrentDownloads;
});

/// 便捷 Provider - 下载图片选项
final downloadImageOptionProvider = Provider<DownloadImageOption>((ref) {
  return ref.watch(downloadSettingsProvider).downloadImageOption;
});
