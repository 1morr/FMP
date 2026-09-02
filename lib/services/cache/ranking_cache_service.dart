import 'dart:async';

import 'package:flutter_riverpod/legacy.dart';

import '../../core/logger.dart';
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
///
/// 本服務對音源種類完全不知情：要刷新哪些榜單由 `SourceManager` 註冊的
/// `RankingSource` 決定，每個榜單的請求參數與名稱由 adapter 自己提供。
class RankingCacheState {
  final Map<SourceType, List<Track>> _tracksBySource;
  final Map<SourceType, bool> _loadedBySource;
  final Map<SourceType, String> _errorsBySource;
  final bool isInitialLoading;

  RankingCacheState({
    Map<SourceType, List<Track>> tracksBySource = const {},
    Map<SourceType, bool> loadedBySource = const {},
    Map<SourceType, String> errorsBySource = const {},
    this.isInitialLoading = true,
  })  : _tracksBySource = _freezeTracks(tracksBySource),
        _loadedBySource = Map.unmodifiable(loadedBySource),
        _errorsBySource = Map.unmodifiable(errorsBySource);

  List<Track> tracksFor(SourceType sourceType) {
    return _tracksBySource[sourceType] ?? const [];
  }

  bool isLoaded(SourceType sourceType) {
    return _loadedBySource[sourceType] ?? false;
  }

  String? errorFor(SourceType sourceType) {
    return _errorsBySource[sourceType];
  }

  RankingCacheState copyWith({
    Map<SourceType, List<Track>>? tracksBySource,
    Map<SourceType, bool>? loadedBySource,
    Map<SourceType, String>? errorsBySource,
    bool? isInitialLoading,
  }) {
    return RankingCacheState(
      tracksBySource: tracksBySource ?? _tracksBySource,
      loadedBySource: loadedBySource ?? _loadedBySource,
      errorsBySource: errorsBySource ?? _errorsBySource,
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
      nextTracks[sourceType] = List<Track>.unmodifiable(tracks);
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

  static Map<SourceType, List<Track>> _freezeTracks(
    Map<SourceType, List<Track>> tracksBySource,
  ) {
    // 型別參數必須寫出來：在 map literal 裡 `List.unmodifiable(...)` 沒有向下
    // 推導的目標型別，會推成 `List<dynamic>`，之後讀取時才炸。
    final frozen = <SourceType, List<Track>>{
      for (final entry in tracksBySource.entries)
        entry.key: List<Track>.unmodifiable(entry.value),
    };
    return Map<SourceType, List<Track>>.unmodifiable(frozen);
  }
}

class RankingCacheService extends StateNotifier<RankingCacheState>
    with Logging {
  static const _defaultInitialLoadTimeout = Duration(seconds: 5);

  final Map<SourceType, RankingSource> _rankingSourcesByType;
  final Duration _initialLoadTimeout;

  Timer? _refreshTimer;
  StreamSubscription<void>? _networkRecoveredSubscription;
  Duration _refreshInterval = const Duration(hours: 1);

  final Map<SourceType, int> _refreshGenerations = {};
  bool _isDisposed = false;

  RankingCacheService({
    required Map<SourceType, RankingSource> rankingSources,
    Duration initialLoadTimeout = _defaultInitialLoadTimeout,
  })  : _rankingSourcesByType = Map.unmodifiable(rankingSources),
        _initialLoadTimeout = initialLoadTimeout,
        super(RankingCacheState());

  /// 目前會被刷新的音源類型。
  Iterable<SourceType> get rankedSourceTypes => _rankingSourcesByType.keys;

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
        logWarning('[RankingCache] 初始加載超時（${_initialLoadTimeout.inSeconds}秒）');
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
      logInfo('[RankingCache] 網絡恢復，重新獲取排行榜緩存');
      _refreshAll();
    });

    logDebug('[RankingCache] 網絡恢復監聽已設置');
  }

  /// 刷新所有數據
  Future<void> _refreshAll() async {
    if (_isDisposed) return;

    // 並行獲取所有已註冊榜單，使用 catchError 確保單一失敗不會中斷其他來源
    await Future.wait(
      _rankingSourcesByType.keys.map(
        (sourceType) => refreshSource(sourceType).catchError((e) {
          logWarning(
            '[RankingCache] ${sourceType.name} 刷新異常（未預期）: $e',
          );
        }),
      ),
    );

    if (_isDisposed) return;

    // 首次加載完成（無論成功或失敗都結束 loading）
    if (state.isInitialLoading) {
      state = state.copyWith(isInitialLoading: false);
      final summary = _rankingSourcesByType.keys
          .map((type) => '${type.name}: ${state.isLoaded(type)}')
          .join(', ');
      logDebug('[RankingCache] 初始加載完成（$summary）');
    }
  }

  Future<void> refreshSource(SourceType sourceType) async {
    if (_isDisposed) return;
    final source = _rankingSourcesByType[sourceType];
    if (source == null) {
      throw StateError('Ranking source not registered: ${sourceType.name}');
    }

    final generation = _nextRefreshGeneration(sourceType);
    try {
      final tracks =
          await source.getRankingTracks(source.defaultRankingRequest);
      if (_isDisposed || generation != _refreshGenerations[sourceType]) return;

      state = state.updateSource(
        sourceType,
        tracks: tracks,
        loaded: true,
        clearError: true,
      );
      logDebug(
          '[RankingCache] ${source.rankingLabel} 緩存已刷新: ${state.tracksFor(sourceType).length} 首');
    } catch (e) {
      if (_isDisposed || generation != _refreshGenerations[sourceType]) return;
      state = state.updateSource(sourceType, error: e.toString());
      logWarning('[RankingCache] ${source.rankingLabel} 刷新失敗: $e');
      // 失敗時保留舊緩存
    }
  }

  int _nextRefreshGeneration(SourceType sourceType) {
    final next = (_refreshGenerations[sourceType] ?? 0) + 1;
    _refreshGenerations[sourceType] = next;
    return next;
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
  final rankingSources = <SourceType, RankingSource>{
    for (final sourceType in manager.registeredSourceTypes)
      sourceType: ?manager.rankingSource(sourceType),
  };
  if (rankingSources.isEmpty) {
    throw StateError('No ranking source registered');
  }

  final service = RankingCacheService(rankingSources: rankingSources);

  Future.microtask(() => service.initialize());

  // 設置網絡恢復監聽
  final connectivityNotifier = ref.read(connectivityProvider.notifier);
  service.setupNetworkMonitoring(connectivityNotifier);

  return service;
});
