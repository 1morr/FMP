import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/track.dart';
import '../../data/sources/source_capabilities.dart';
import '../../data/sources/source_provider.dart';
import '../network/connectivity_service.dart';

/// 首頁排行榜緩存服務
///
/// 主動後台刷新模式：
/// - 應用啟動時立即獲取數據
/// - 每小時自動後台刷新
/// - 網絡恢復時自動重新獲取數據
/// - 用戶進入首頁時直接顯示緩存，無需等待
/// - 緩存完整數據，首頁預覽只顯示前 10 首，探索頁使用完整緩存
class RankingCacheState {
  final Map<SourceType, List<Track>> _tracksBySource;
  final Map<SourceType, bool> _loadedBySource;
  final Map<SourceType, String> _errorsBySource;
  final bool isInitialLoading;

  RankingCacheState({
    Map<SourceType, List<Track>> tracksBySource = const {},
    Map<SourceType, bool> loadedBySource = const {},
    Map<SourceType, String> errorsBySource = const {},
    List<Track> bilibiliTracks = const [],
    List<Track> youtubeTracks = const [],
    List<Track> neteaseTracks = const [],
    this.isInitialLoading = true,
    bool bilibiliLoaded = false,
    bool youtubeLoaded = false,
    bool neteaseLoaded = false,
    String? bilibiliError,
    String? youtubeError,
    String? neteaseError,
  })  : _tracksBySource = _buildTracksBySource(
          tracksBySource: tracksBySource,
          bilibiliTracks: bilibiliTracks,
          youtubeTracks: youtubeTracks,
          neteaseTracks: neteaseTracks,
        ),
        _loadedBySource = _buildLoadedBySource(
          loadedBySource: loadedBySource,
          bilibiliLoaded: bilibiliLoaded,
          youtubeLoaded: youtubeLoaded,
          neteaseLoaded: neteaseLoaded,
        ),
        _errorsBySource = _buildErrorsBySource(
          errorsBySource: errorsBySource,
          bilibiliError: bilibiliError,
          youtubeError: youtubeError,
          neteaseError: neteaseError,
        );

  List<Track> tracksFor(SourceType sourceType) {
    return _tracksBySource[sourceType] ?? const [];
  }

  bool isLoaded(SourceType sourceType) {
    return _loadedBySource[sourceType] ?? false;
  }

  String? errorFor(SourceType sourceType) {
    return _errorsBySource[sourceType];
  }

  List<Track> get bilibiliTracks => tracksFor(SourceType.bilibili);
  List<Track> get youtubeTracks => tracksFor(SourceType.youtube);
  List<Track> get neteaseTracks => tracksFor(SourceType.netease);

  bool get bilibiliLoaded => isLoaded(SourceType.bilibili);
  bool get youtubeLoaded => isLoaded(SourceType.youtube);
  bool get neteaseLoaded => isLoaded(SourceType.netease);

  String? get bilibiliError => errorFor(SourceType.bilibili);
  String? get youtubeError => errorFor(SourceType.youtube);
  String? get neteaseError => errorFor(SourceType.netease);

  RankingCacheState copyWith({
    Map<SourceType, List<Track>>? tracksBySource,
    Map<SourceType, bool>? loadedBySource,
    Map<SourceType, String>? errorsBySource,
    List<Track>? bilibiliTracks,
    List<Track>? youtubeTracks,
    List<Track>? neteaseTracks,
    bool? isInitialLoading,
    bool? bilibiliLoaded,
    bool? youtubeLoaded,
    bool? neteaseLoaded,
    String? bilibiliError,
    String? youtubeError,
    String? neteaseError,
    bool clearBilibiliError = false,
    bool clearYoutubeError = false,
    bool clearNeteaseError = false,
  }) {
    return RankingCacheState(
      tracksBySource: _mergeTracksBySource(
        base: _tracksBySource,
        tracksBySource: tracksBySource,
        bilibiliTracks: bilibiliTracks,
        youtubeTracks: youtubeTracks,
        neteaseTracks: neteaseTracks,
      ),
      loadedBySource: _mergeLoadedBySource(
        base: _loadedBySource,
        loadedBySource: loadedBySource,
        bilibiliLoaded: bilibiliLoaded,
        youtubeLoaded: youtubeLoaded,
        neteaseLoaded: neteaseLoaded,
      ),
      errorsBySource: _mergeErrorsBySource(
        base: _errorsBySource,
        errorsBySource: errorsBySource,
        bilibiliError: bilibiliError,
        youtubeError: youtubeError,
        neteaseError: neteaseError,
        clearBilibiliError: clearBilibiliError,
        clearYoutubeError: clearYoutubeError,
        clearNeteaseError: clearNeteaseError,
      ),
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
    );
  }

  RankingCacheState updateSource(
    SourceType sourceType, {
    List<Track>? tracks,
    bool? loaded,
    String? error,
    bool clearError = false,
  }) {
    final nextTracks = Map<SourceType, List<Track>>.from(_tracksBySource);
    if (tracks != null) {
      nextTracks[sourceType] = List.unmodifiable(List<Track>.of(tracks));
    }

    final nextLoaded = Map<SourceType, bool>.from(_loadedBySource);
    if (loaded != null) {
      nextLoaded[sourceType] = loaded;
    }

    final nextErrors = Map<SourceType, String>.from(_errorsBySource);
    if (clearError) {
      nextErrors.remove(sourceType);
    } else if (error != null) {
      nextErrors[sourceType] = error;
    }

    return RankingCacheState(
      tracksBySource: nextTracks,
      loadedBySource: nextLoaded,
      errorsBySource: nextErrors,
      isInitialLoading: isInitialLoading,
    );
  }

  static Map<SourceType, List<Track>> _buildTracksBySource({
    required Map<SourceType, List<Track>> tracksBySource,
    required List<Track> bilibiliTracks,
    required List<Track> youtubeTracks,
    required List<Track> neteaseTracks,
  }) {
    final merged = <SourceType, List<Track>>{
      SourceType.bilibili: List.unmodifiable(bilibiliTracks),
      SourceType.youtube: List.unmodifiable(youtubeTracks),
      SourceType.netease: List.unmodifiable(neteaseTracks),
    };
    tracksBySource.forEach((sourceType, tracks) {
      merged[sourceType] = List.unmodifiable(List<Track>.of(tracks));
    });
    return Map.unmodifiable(merged);
  }

  static Map<SourceType, bool> _buildLoadedBySource({
    required Map<SourceType, bool> loadedBySource,
    required bool bilibiliLoaded,
    required bool youtubeLoaded,
    required bool neteaseLoaded,
  }) {
    final merged = <SourceType, bool>{
      SourceType.bilibili: bilibiliLoaded,
      SourceType.youtube: youtubeLoaded,
      SourceType.netease: neteaseLoaded,
    };
    merged.addAll(loadedBySource);
    return Map.unmodifiable(merged);
  }

  static Map<SourceType, String> _buildErrorsBySource({
    required Map<SourceType, String> errorsBySource,
    String? bilibiliError,
    String? youtubeError,
    String? neteaseError,
  }) {
    final merged = <SourceType, String>{
      if (bilibiliError != null) SourceType.bilibili: bilibiliError,
      if (youtubeError != null) SourceType.youtube: youtubeError,
      if (neteaseError != null) SourceType.netease: neteaseError,
    };
    merged.addAll(errorsBySource);
    return Map.unmodifiable(merged);
  }

  static Map<SourceType, List<Track>> _mergeTracksBySource({
    required Map<SourceType, List<Track>> base,
    Map<SourceType, List<Track>>? tracksBySource,
    List<Track>? bilibiliTracks,
    List<Track>? youtubeTracks,
    List<Track>? neteaseTracks,
  }) {
    final merged = Map<SourceType, List<Track>>.from(base);
    if (tracksBySource != null) {
      tracksBySource.forEach((sourceType, tracks) {
        merged[sourceType] = List.unmodifiable(List<Track>.of(tracks));
      });
    }
    if (bilibiliTracks != null) {
      merged[SourceType.bilibili] = List.unmodifiable(bilibiliTracks);
    }
    if (youtubeTracks != null) {
      merged[SourceType.youtube] = List.unmodifiable(youtubeTracks);
    }
    if (neteaseTracks != null) {
      merged[SourceType.netease] = List.unmodifiable(neteaseTracks);
    }
    return Map.unmodifiable(merged);
  }

  static Map<SourceType, bool> _mergeLoadedBySource({
    required Map<SourceType, bool> base,
    Map<SourceType, bool>? loadedBySource,
    bool? bilibiliLoaded,
    bool? youtubeLoaded,
    bool? neteaseLoaded,
  }) {
    final merged = Map<SourceType, bool>.from(base);
    if (loadedBySource != null) merged.addAll(loadedBySource);
    if (bilibiliLoaded != null) merged[SourceType.bilibili] = bilibiliLoaded;
    if (youtubeLoaded != null) merged[SourceType.youtube] = youtubeLoaded;
    if (neteaseLoaded != null) merged[SourceType.netease] = neteaseLoaded;
    return Map.unmodifiable(merged);
  }

  static Map<SourceType, String> _mergeErrorsBySource({
    required Map<SourceType, String> base,
    Map<SourceType, String>? errorsBySource,
    String? bilibiliError,
    String? youtubeError,
    String? neteaseError,
    bool clearBilibiliError = false,
    bool clearYoutubeError = false,
    bool clearNeteaseError = false,
  }) {
    final merged = Map<SourceType, String>.from(base);
    if (errorsBySource != null) merged.addAll(errorsBySource);

    if (clearBilibiliError) {
      merged.remove(SourceType.bilibili);
    } else if (bilibiliError != null) {
      merged[SourceType.bilibili] = bilibiliError;
    }
    if (clearYoutubeError) {
      merged.remove(SourceType.youtube);
    } else if (youtubeError != null) {
      merged[SourceType.youtube] = youtubeError;
    }
    if (clearNeteaseError) {
      merged.remove(SourceType.netease);
    } else if (neteaseError != null) {
      merged[SourceType.netease] = neteaseError;
    }

    return Map.unmodifiable(merged);
  }
}

class RankingCacheService extends StateNotifier<RankingCacheState> {
  static const _defaultInitialLoadTimeout = Duration(seconds: 5);

  final Map<SourceType, RankingSource> _rankingSourcesByType;
  final Duration _initialLoadTimeout;

  Timer? _refreshTimer;
  StreamSubscription<void>? _networkRecoveredSubscription;
  Duration _refreshInterval = const Duration(hours: 1);

  final Map<SourceType, int> _refreshGenerations = {};
  bool _isDisposed = false;

  RankingCacheService({
    required RankingSource bilibiliRankingSource,
    required RankingSource youtubeRankingSource,
    required RankingSource neteaseRankingSource,
    Duration initialLoadTimeout = _defaultInitialLoadTimeout,
  })  : _rankingSourcesByType = Map.unmodifiable({
          SourceType.bilibili: bilibiliRankingSource,
          SourceType.youtube: youtubeRankingSource,
          SourceType.netease: neteaseRankingSource,
        }),
        _initialLoadTimeout = initialLoadTimeout,
        super(RankingCacheState());

  /// 初始化服務：立即獲取數據並啟動定時刷新
  Future<void> initialize({Duration? refreshInterval}) async {
    if (_isDisposed) return;
    if (refreshInterval != null && _refreshTimer == null) {
      _refreshInterval = refreshInterval;
    }

    // 立即開始獲取數據（並行），設置超時
    await _refreshAll().timeout(
      _initialLoadTimeout,
      onTimeout: () {
        debugPrint('[RankingCache] 初始加載超時（${_initialLoadTimeout.inSeconds}秒）');
        if (_isDisposed) return;
        // 確保結束 loading 狀態
        if (state.isInitialLoading) {
          state = state.copyWith(isInitialLoading: false);
        }
      },
    );

    if (_isDisposed) return;
    _startRefreshTimer();
  }

  /// 更新刷新間隔（重啟定時器）
  void updateRefreshInterval(Duration interval) {
    if (_isDisposed) return;
    _refreshInterval = interval;
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    if (_isDisposed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (_isDisposed) return;
      _refreshAll();
    });
  }

  /// 設置網絡恢復監聽（需要 Provider 可用後調用）
  void setupNetworkMonitoring(ConnectivityNotifier connectivityNotifier) {
    if (_isDisposed) return;

    _networkRecoveredSubscription?.cancel();
    _networkRecoveredSubscription =
        connectivityNotifier.onNetworkRecovered.listen((_) {
      if (_isDisposed) return;
      debugPrint('[RankingCache] 網絡恢復，重新獲取排行榜緩存');
      _refreshAll();
    });

    debugPrint('[RankingCache] 網絡恢復監聽已設置');
  }

  /// 刷新所有數據
  Future<void> _refreshAll() async {
    if (_isDisposed) return;

    // 並行獲取三個數據源，使用 catchError 確保失敗不會中斷
    await Future.wait(
      _rankingSourcesByType.keys.map(
        (sourceType) => refreshSource(sourceType).catchError((e) {
          debugPrint(
            '[RankingCache] ${sourceType.name} 刷新異常（未預期）: $e',
          );
        }),
      ),
    );

    if (_isDisposed) return;

    // 首次加載完成（無論成功或失敗都結束 loading）
    if (state.isInitialLoading) {
      state = state.copyWith(isInitialLoading: false);
      debugPrint(
          '[RankingCache] 初始加載完成（Bilibili: ${state.bilibiliLoaded}, YouTube: ${state.youtubeLoaded}, Netease: ${state.neteaseLoaded}）');
    }
  }

  /// 刷新 Bilibili 數據（使用 rid=1003 音樂區排行榜）
  Future<void> refreshBilibili() async {
    return refreshSource(SourceType.bilibili);
  }

  /// 刷新 YouTube 數據
  Future<void> refreshYouTube() async {
    return refreshSource(SourceType.youtube);
  }

  /// 刷新 Netease 熱歌榜數據
  Future<void> refreshNetease() async {
    return refreshSource(SourceType.netease);
  }

  Future<void> refreshSource(SourceType sourceType) async {
    if (_isDisposed) return;
    final source = _rankingSourcesByType[sourceType];
    if (source == null) {
      throw StateError('Ranking source not registered: ${sourceType.name}');
    }

    final generation = _nextRefreshGeneration(sourceType);
    try {
      final tracks = await source.getRankingTracks(
        _rankingRequestFor(sourceType),
      );
      if (_isDisposed || generation != _refreshGenerations[sourceType]) return;

      final normalizedTracks = _normalizeRankingTracks(sourceType, tracks);
      state = state.updateSource(
        sourceType,
        tracks: normalizedTracks,
        loaded: true,
        clearError: true,
      );
      debugPrint(
          '[RankingCache] ${_sourceLabel(sourceType)} 緩存已刷新: ${state.tracksFor(sourceType).length} 首');
    } catch (e) {
      if (_isDisposed || generation != _refreshGenerations[sourceType]) return;
      state = state.updateSource(sourceType, error: e.toString());
      debugPrint('[RankingCache] ${_sourceLabel(sourceType)} 刷新失敗: $e');
      // 失敗時保留舊緩存
    }
  }

  int _nextRefreshGeneration(SourceType sourceType) {
    final next = (_refreshGenerations[sourceType] ?? 0) + 1;
    _refreshGenerations[sourceType] = next;
    return next;
  }

  SourceRankingRequest _rankingRequestFor(SourceType sourceType) {
    return switch (sourceType) {
      // rid=1003 是音樂區排行榜的正確 ID（網頁 /v/popular/rank/music 使用此 ID）
      SourceType.bilibili => const SourceRankingRequest(regionId: 1003),
      SourceType.youtube => const SourceRankingRequest(category: 'music'),
      SourceType.netease => const SourceRankingRequest(limit: 50),
    };
  }

  List<Track> _normalizeRankingTracks(
    SourceType sourceType,
    List<Track> tracks,
  ) {
    if (sourceType != SourceType.youtube) {
      return List.unmodifiable(tracks);
    }

    // 按播放數降序排序
    return List.unmodifiable(
      List<Track>.of(tracks)
        ..sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0)),
    );
  }

  String _sourceLabel(SourceType sourceType) {
    return switch (sourceType) {
      SourceType.bilibili => 'Bilibili 音樂排行榜',
      SourceType.youtube => 'YouTube',
      SourceType.netease => 'Netease 熱歌榜',
    };
  }

  void clearNetworkMonitoring() {
    _networkRecoveredSubscription?.cancel();
    _networkRecoveredSubscription = null;
  }

  /// 釋放資源
  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    clearNetworkMonitoring();
    super.dispose();
  }
}

/// RankingCacheService Provider（負責設置網絡監聽）
final rankingCacheServiceProvider =
    StateNotifierProvider<RankingCacheService, RankingCacheState>((ref) {
  final manager = ref.watch(sourceManagerProvider);
  final bilibiliRankingSource = manager.rankingSource(SourceType.bilibili);
  final youtubeRankingSource = manager.rankingSource(SourceType.youtube);
  final neteaseRankingSource = manager.rankingSource(SourceType.netease);
  final missingRankingSources = [
    if (bilibiliRankingSource == null) SourceType.bilibili.name,
    if (youtubeRankingSource == null) SourceType.youtube.name,
    if (neteaseRankingSource == null) SourceType.netease.name,
  ];
  if (missingRankingSources.isNotEmpty) {
    throw StateError(
      'Ranking source not registered: ${missingRankingSources.join(', ')}',
    );
  }

  final service = RankingCacheService(
    bilibiliRankingSource: bilibiliRankingSource!,
    youtubeRankingSource: youtubeRankingSource!,
    neteaseRankingSource: neteaseRankingSource!,
  );

  Future.microtask(() => service.initialize());

  // 設置網絡恢復監聽
  final connectivityNotifier = ref.read(connectivityProvider.notifier);
  service.setupNetworkMonitoring(connectivityNotifier);

  return service;
});
