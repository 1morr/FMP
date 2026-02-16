import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/track.dart';
import '../../data/sources/bilibili_source.dart';
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
class RankingCacheService {
  static const _initialLoadTimeout = Duration(seconds: 5); // 初始加載超時時間

  /// 全局單例實例，在 main.dart 中初始化
  static late final RankingCacheService instance;

  final BilibiliSource _bilibiliSource;
  final YouTubeSource _youtubeSource;

  Timer? _refreshTimer;
  StreamSubscription<void>? _networkRecoveredSubscription;

  // 緩存數據
  List<Track> _bilibiliTracks = [];
  List<Track> _youtubeTracks = [];

  // 加載狀態（僅用於首次加載）
  bool _isInitialLoading = true;
  bool _bilibiliLoaded = false;
  bool _youtubeLoaded = false;

  // 狀態變更通知
  final _stateController = StreamController<void>.broadcast();

  // 是否已設置網絡監聽
  bool _networkMonitoringSetup = false;

  RankingCacheService({
    BilibiliSource? bilibiliSource,
    YouTubeSource? youtubeSource,
  })  : _bilibiliSource = bilibiliSource ?? BilibiliSource(),
        _youtubeSource = youtubeSource ?? YouTubeSource();

  /// 緩存的 Bilibili 音樂排行
  List<Track> get bilibiliTracks => _bilibiliTracks;

  /// 緩存的 YouTube 音樂排行
  List<Track> get youtubeTracks => _youtubeTracks;

  /// 是否正在首次加載（用於顯示初始 loading）
  bool get isInitialLoading => _isInitialLoading;

  /// 狀態變更流
  Stream<void> get stateChanges => _stateController.stream;

  /// 初始化服務：立即獲取數據並啟動定時刷新
  Future<void> initialize() async {
    // 立即開始獲取數據（並行），設置超時
    await _refreshAll().timeout(
      _initialLoadTimeout,
      onTimeout: () {
        debugPrint('[RankingCache] 初始加載超時（${_initialLoadTimeout.inSeconds}秒）');
        // 確保結束 loading 狀態
        if (_isInitialLoading) {
          _isInitialLoading = false;
          _notifyStateChange();
        }
      },
    );

    // 啟動定時器，每小時刷新
    _refreshTimer = Timer.periodic(AppConstants.rankingCacheRefreshInterval, (_) {
      _refreshAll();
    });
  }

  /// 設置網絡恢復監聽（需要 Provider 可用後調用）
  void setupNetworkMonitoring(ConnectivityNotifier connectivityNotifier) {
    if (_networkMonitoringSetup) return;
    _networkMonitoringSetup = true;

    _networkRecoveredSubscription = connectivityNotifier.onNetworkRecovered.listen((_) {
      debugPrint('[RankingCache] 網絡恢復，重新獲取排行榜緩存');
      _refreshAll();
    });

    debugPrint('[RankingCache] 網絡恢復監聽已設置');
  }

  /// 刷新所有數據
  Future<void> _refreshAll() async {
    // 並行獲取兩個數據源，使用 ignoreErrors 確保失敗不會中斷
    await Future.wait([
      refreshBilibili().catchError((_) => {}),
      refreshYouTube().catchError((_) => {}),
    ]);

    // 首次加載完成（無論成功或失敗都結束 loading）
    if (_isInitialLoading) {
      _isInitialLoading = false;
      _notifyStateChange();
      debugPrint('[RankingCache] 初始加載完成（Bilibili: $_bilibiliLoaded, YouTube: $_youtubeLoaded）');
    }
  }

  /// 刷新 Bilibili 數據（使用 rid=1003 音樂區排行榜）
  Future<void> refreshBilibili() async {
    try {
      // rid=1003 是音樂區排行榜的正確 ID（網頁 /v/popular/rank/music 使用此 ID）
      final tracks = await _bilibiliSource.getRankingVideos(rid: 1003);
      _bilibiliTracks = tracks; // 緩存完整數據
      _bilibiliLoaded = true;
      _notifyStateChange();
      debugPrint('[RankingCache] Bilibili 音樂排行榜緩存已刷新: ${_bilibiliTracks.length} 首');
    } catch (e) {
      debugPrint('[RankingCache] Bilibili 刷新失敗: $e');
      // 失敗時保留舊緩存
    }
  }

  /// 刷新 YouTube 數據
  Future<void> refreshYouTube() async {
    try {
      final tracks = await _youtubeSource.getTrendingVideos(category: 'music');
      // 按播放數降序排序
      tracks.sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
      _youtubeTracks = tracks; // 緩存完整數據
      _youtubeLoaded = true;
      _notifyStateChange();
      debugPrint('[RankingCache] YouTube 緩存已刷新: ${_youtubeTracks.length} 首');
    } catch (e) {
      debugPrint('[RankingCache] YouTube 刷新失敗: $e');
      // 失敗時保留舊緩存
    }
  }

  void _notifyStateChange() {
    if (!_stateController.isClosed) {
      _stateController.add(null);
    }
  }

  /// 釋放資源
  void dispose() {
    _refreshTimer?.cancel();
    _networkRecoveredSubscription?.cancel();
    _stateController.close();
  }
}

/// RankingCacheService Provider（負責設置網絡監聽）
final rankingCacheServiceProvider = Provider<RankingCacheService>((ref) {
  final service = RankingCacheService.instance;

  // 設置網絡恢復監聽
  final connectivityNotifier = ref.read(connectivityProvider.notifier);
  service.setupNetworkMonitoring(connectivityNotifier);

  // 當 provider 被銷毀時取消訂閱
  ref.onDispose(() {
    // 不銷毀全局單例，只取消網絡監聽
    service._networkRecoveredSubscription?.cancel();
    service._networkRecoveredSubscription = null;
    service._networkMonitoringSetup = false;
  });

  return service;
});
