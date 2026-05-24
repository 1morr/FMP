import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/track.dart';
import '../../data/sources/bilibili_source.dart';
import '../../data/sources/netease_source.dart';
import '../../data/sources/source_provider.dart';
import '../../data/sources/youtube_source.dart';
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
  final List<Track> bilibiliTracks;
  final List<Track> youtubeTracks;
  final List<Track> neteaseTracks;
  final bool isInitialLoading;
  final bool bilibiliLoaded;
  final bool youtubeLoaded;
  final bool neteaseLoaded;
  final String? bilibiliError;
  final String? youtubeError;
  final String? neteaseError;

  RankingCacheState({
    List<Track> bilibiliTracks = const [],
    List<Track> youtubeTracks = const [],
    List<Track> neteaseTracks = const [],
    this.isInitialLoading = true,
    this.bilibiliLoaded = false,
    this.youtubeLoaded = false,
    this.neteaseLoaded = false,
    this.bilibiliError,
    this.youtubeError,
    this.neteaseError,
  })  : bilibiliTracks = List.unmodifiable(bilibiliTracks),
        youtubeTracks = List.unmodifiable(youtubeTracks),
        neteaseTracks = List.unmodifiable(neteaseTracks);

  RankingCacheState copyWith({
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
      bilibiliTracks: List.unmodifiable(bilibiliTracks ?? this.bilibiliTracks),
      youtubeTracks: List.unmodifiable(youtubeTracks ?? this.youtubeTracks),
      neteaseTracks: List.unmodifiable(neteaseTracks ?? this.neteaseTracks),
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      bilibiliLoaded: bilibiliLoaded ?? this.bilibiliLoaded,
      youtubeLoaded: youtubeLoaded ?? this.youtubeLoaded,
      neteaseLoaded: neteaseLoaded ?? this.neteaseLoaded,
      bilibiliError:
          clearBilibiliError ? null : bilibiliError ?? this.bilibiliError,
      youtubeError:
          clearYoutubeError ? null : youtubeError ?? this.youtubeError,
      neteaseError:
          clearNeteaseError ? null : neteaseError ?? this.neteaseError,
    );
  }
}

class RankingCacheService extends StateNotifier<RankingCacheState> {
  static const _defaultInitialLoadTimeout = Duration(seconds: 5);

  final BilibiliSource _bilibiliSource;
  final YouTubeSource _youtubeSource;
  final NeteaseSource _neteaseSource;
  final Duration _initialLoadTimeout;

  Timer? _refreshTimer;
  StreamSubscription<void>? _networkRecoveredSubscription;
  Duration _refreshInterval = const Duration(hours: 1);

  int _bilibiliRefreshGeneration = 0;
  int _youtubeRefreshGeneration = 0;
  int _neteaseRefreshGeneration = 0;
  bool _isDisposed = false;

  RankingCacheService({
    required BilibiliSource bilibiliSource,
    required YouTubeSource youtubeSource,
    required NeteaseSource neteaseSource,
    Duration initialLoadTimeout = _defaultInitialLoadTimeout,
  })  : _bilibiliSource = bilibiliSource,
        _youtubeSource = youtubeSource,
        _neteaseSource = neteaseSource,
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
    await Future.wait([
      refreshBilibili().catchError((e) {
        debugPrint('[RankingCache] Bilibili 刷新異常（未預期）: $e');
      }),
      refreshYouTube().catchError((e) {
        debugPrint('[RankingCache] YouTube 刷新異常（未預期）: $e');
      }),
      refreshNetease().catchError((e) {
        debugPrint('[RankingCache] Netease 刷新異常（未預期）: $e');
      }),
    ]);

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
    if (_isDisposed) return;
    final generation = ++_bilibiliRefreshGeneration;
    try {
      // rid=1003 是音樂區排行榜的正確 ID（網頁 /v/popular/rank/music 使用此 ID）
      final tracks = await _bilibiliSource.getRankingVideos(rid: 1003);
      if (_isDisposed || generation != _bilibiliRefreshGeneration) return;
      state = state.copyWith(
        bilibiliTracks: tracks,
        bilibiliLoaded: true,
        clearBilibiliError: true,
      );
      debugPrint(
          '[RankingCache] Bilibili 音樂排行榜緩存已刷新: ${state.bilibiliTracks.length} 首');
    } catch (e) {
      if (_isDisposed || generation != _bilibiliRefreshGeneration) return;
      state = state.copyWith(bilibiliError: e.toString());
      debugPrint('[RankingCache] Bilibili 刷新失敗: $e');
      // 失敗時保留舊緩存
    }
  }

  /// 刷新 YouTube 數據
  Future<void> refreshYouTube() async {
    if (_isDisposed) return;
    final generation = ++_youtubeRefreshGeneration;
    try {
      final tracks = await _youtubeSource.getTrendingVideos(category: 'music');
      if (_isDisposed || generation != _youtubeRefreshGeneration) return;
      // 按播放數降序排序
      final sortedTracks = List<Track>.of(tracks)
        ..sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
      state = state.copyWith(
        youtubeTracks: sortedTracks,
        youtubeLoaded: true,
        clearYoutubeError: true,
      );
      debugPrint(
          '[RankingCache] YouTube 緩存已刷新: ${state.youtubeTracks.length} 首');
    } catch (e) {
      if (_isDisposed || generation != _youtubeRefreshGeneration) return;
      state = state.copyWith(youtubeError: e.toString());
      debugPrint('[RankingCache] YouTube 刷新失敗: $e');
      // 失敗時保留舊緩存
    }
  }

  /// 刷新 Netease 熱歌榜數據
  Future<void> refreshNetease() async {
    if (_isDisposed) return;
    final generation = ++_neteaseRefreshGeneration;
    try {
      final tracks = await _neteaseSource.getHotRankingTracks();
      if (_isDisposed || generation != _neteaseRefreshGeneration) return;
      state = state.copyWith(
        neteaseTracks: tracks,
        neteaseLoaded: true,
        clearNeteaseError: true,
      );
      debugPrint(
          '[RankingCache] Netease 熱歌榜緩存已刷新: ${state.neteaseTracks.length} 首');
    } catch (e) {
      if (_isDisposed || generation != _neteaseRefreshGeneration) return;
      state = state.copyWith(neteaseError: e.toString());
      debugPrint('[RankingCache] Netease 刷新失敗: $e');
      // 失敗時保留舊緩存
    }
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
  final service = RankingCacheService(
    bilibiliSource: ref.watch(bilibiliSourceProvider),
    youtubeSource: ref.watch(youtubeSourceProvider),
    neteaseSource: ref.watch(neteaseAudioSourceProvider),
  );

  Future.microtask(() => service.initialize());

  // 設置網絡恢復監聽
  final connectivityNotifier = ref.read(connectivityProvider.notifier);
  service.setupNetworkMonitoring(connectivityNotifier);

  return service;
});
