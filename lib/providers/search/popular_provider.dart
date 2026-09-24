import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/cache/ranking_cache_service.dart';

/// 首頁排行預覽：某個音源快取排行的前幾首。以音源 id 為參數，新音源只要有
/// 排行快取就會出現在首頁，不必再多寫一個 provider。
final homeRankingPreviewProvider = Provider.family<List<Track>, String>((
  ref,
  sourceType,
) {
  final tracks = ref.watch(
    rankingCacheServiceProvider.select((state) => state.tracksFor(sourceType)),
  );
  return List.unmodifiable(tracks.take(AppConstants.rankingPreviewCount));
});

/// 探索頁用的完整快取排行。
final cachedRankingProvider = Provider.family<List<Track>, String>((
  ref,
  sourceType,
) {
  final tracks = ref.watch(
    rankingCacheServiceProvider.select((state) => state.tracksFor(sourceType)),
  );
  return List.unmodifiable(tracks);
});
