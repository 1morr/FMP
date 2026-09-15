import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/cache/ranking_cache_service.dart';

/// 首頁 Bilibili 音樂排行預覽 Provider（使用緩存服務）
final homeBilibiliMusicRankingProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(
    rankingCacheServiceProvider.select(
      (state) => state.tracksFor(SourceIds.bilibili),
    ),
  );
  return List.unmodifiable(tracks.take(AppConstants.rankingPreviewCount));
});

// ==================== YouTube 熱門 ====================

/// 首頁 YouTube 音樂排行預覽 Provider（使用緩存服務）
final homeYouTubeMusicRankingProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(
    rankingCacheServiceProvider.select(
      (state) => state.tracksFor(SourceIds.youtube),
    ),
  );
  return List.unmodifiable(tracks.take(AppConstants.rankingPreviewCount));
});

// ==================== Netease 熱歌榜 ====================

/// 首頁 Netease 熱歌榜預覽 Provider（使用緩存服務）
final homeNeteaseHotRankingProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(
    rankingCacheServiceProvider.select(
      (state) => state.tracksFor(SourceIds.netease),
    ),
  );
  return List.unmodifiable(tracks.take(AppConstants.rankingPreviewCount));
});

// ==================== 緩存排行榜（探索頁使用） ====================

/// Bilibili 完整緩存排行榜 Provider（探索頁使用）
final cachedBilibiliRankingProvider = Provider<List<Track>>((ref) {
  return ref.watch(
    rankingCacheServiceProvider.select(
      (state) => state.tracksFor(SourceIds.bilibili),
    ),
  );
});

/// YouTube 完整緩存排行榜 Provider（探索頁使用）
final cachedYouTubeRankingProvider = Provider<List<Track>>((ref) {
  return ref.watch(
    rankingCacheServiceProvider.select(
      (state) => state.tracksFor(SourceIds.youtube),
    ),
  );
});

/// Netease 完整緩存排行榜 Provider（探索頁使用）
final cachedNeteaseRankingProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(
    rankingCacheServiceProvider.select(
      (state) => state.tracksFor(SourceIds.netease),
    ),
  );
  return List.unmodifiable(tracks);
});
