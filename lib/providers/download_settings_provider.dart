import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/network_image_cache_service.dart';
import '../data/models/settings.dart';
import '../data/repositories/settings_repository.dart';
import 'repository_providers.dart';

/// 下载设置状态
class DownloadSettingsState {
  final int maxConcurrentDownloads;
  final DownloadImageOption downloadImageOption;
  final int maxCacheSizeMB;
  final bool isLoading;

  const DownloadSettingsState({
    this.maxConcurrentDownloads = 3,
    this.downloadImageOption = DownloadImageOption.coverOnly,
    this.maxCacheSizeMB = 200,
    this.isLoading = true,
  });

  DownloadSettingsState copyWith({
    int? maxConcurrentDownloads,
    DownloadImageOption? downloadImageOption,
    int? maxCacheSizeMB,
    bool? isLoading,
  }) {
    return DownloadSettingsState(
      maxConcurrentDownloads: maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      downloadImageOption: downloadImageOption ?? this.downloadImageOption,
      maxCacheSizeMB: maxCacheSizeMB ?? this.maxCacheSizeMB,
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
      maxCacheSizeMB: _settings!.maxCacheSizeMB,
      isLoading: false,
    );

    // 同步缓存大小限制到 NetworkImageCacheService
    NetworkImageCacheService.setMaxCacheSizeMB(_settings!.maxCacheSizeMB);

    // 启动时检查并清理超出限制的缓存，并初始化缓存大小估算值
    await NetworkImageCacheService.trimCacheIfNeeded(_settings!.maxCacheSizeMB);
    await NetworkImageCacheService.initializeCacheSizeEstimate();
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

  /// 设置图片缓存大小上限（MB）
  Future<void> setMaxCacheSizeMB(int value) async {
    if (_settings == null) return;
    if (value < 50) return; // 最小 50MB

    _settings!.maxCacheSizeMB = value;
    await _settingsRepository.save(_settings!);
    state = state.copyWith(maxCacheSizeMB: value);

    // 同步缓存大小限制到 NetworkImageCacheService
    NetworkImageCacheService.setMaxCacheSizeMB(value);

    // 检查并清理超出限制的缓存
    await NetworkImageCacheService.trimCacheIfNeeded(value);
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
