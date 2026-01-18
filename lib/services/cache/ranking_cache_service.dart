import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/track.dart';
import '../../data/sources/bilibili_source.dart';
import '../../data/sources/youtube_source.dart';

/// 首頁排行榜緩存服務
///
/// 主動後台刷新模式：
/// - 應用啟動時立即獲取數據
/// - 每小時自動後台刷新
/// - 用戶進入首頁時直接顯示緩存，無需等待
/// - 緩存完整數據，首頁預覽只顯示前 10 首，探索頁使用完整緩存
class RankingCacheService {
  static const _refreshInterval = Duration(hours: 1);

  /// 全局單例實例，在 main.dart 中初始化
  static late final RankingCacheService instance;

  final BilibiliSource _bilibiliSource;
  final YouTubeSource _youtubeSource;

  Timer? _refreshTimer;

  // 緩存數據
  List<Track> _bilibiliTracks = [];
  List<Track> _youtubeTracks = [];

  // 加載狀態（僅用於首次加載）
  bool _isInitialLoading = true;
  bool _bilibiliLoaded = false;
  bool _youtubeLoaded = false;

  // 狀態變更通知
  final _stateController = StreamController<void>.broadcast();

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
    // 立即開始獲取數據（並行）
    await _refreshAll();

    // 啟動定時器，每小時刷新
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      _refreshAll();
    });
  }

  /// 刷新所有數據
  Future<void> _refreshAll() async {
    // 並行獲取兩個數據源
    await Future.wait([
      refreshBilibili(),
      refreshYouTube(),
    ]);

    // 首次加載完成
    if (_isInitialLoading && (_bilibiliLoaded || _youtubeLoaded)) {
      _isInitialLoading = false;
      _notifyStateChange();
    }
  }

  /// 刷新 Bilibili 數據
  Future<void> refreshBilibili() async {
    try {
      final tracks = await _bilibiliSource.getRankingVideos(rid: 3); // 音樂分區
      _bilibiliTracks = tracks; // 緩存完整數據
      _bilibiliLoaded = true;
      _notifyStateChange();
      debugPrint('[RankingCache] Bilibili 緩存已刷新: ${_bilibiliTracks.length} 首');
    } catch (e) {
      debugPrint('[RankingCache] Bilibili 刷新失敗: $e');
      // 失敗時保留舊緩存
    }
  }

  /// 刷新 YouTube 數據
  Future<void> refreshYouTube() async {
    try {
      final tracks = await _youtubeSource.getTrendingVideos(category: 'music');
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
    _stateController.close();
  }
}

/// RankingCacheService Provider
final rankingCacheServiceProvider = Provider<RankingCacheService>((ref) {
  // 使用全局單例，確保在 main.dart 中已初始化
  return RankingCacheService.instance;
});
