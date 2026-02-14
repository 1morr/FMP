import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../core/constants/app_constants.dart';
import '../data/models/track.dart';
import '../data/sources/bilibili_source.dart';
import '../data/sources/youtube_source.dart';
import '../services/cache/ranking_cache_service.dart';

/// Bilibili 分区 ID
enum BilibiliCategory {
  all(0, '全站'),
  music(3, '音乐'),
  dance(129, '舞蹈'),
  game(4, '游戏'),
  anime(1, '动画'),
  entertainment(5, '娱乐'),
  tech(188, '科技'),
  life(160, '生活'),
  movie(181, '影视'),
  kichiku(119, '鬼畜');

  final int rid;
  final String label;
  const BilibiliCategory(this.rid, this.label);

  String get displayName {
    switch (this) {
      case BilibiliCategory.all: return t.popularCategory.all;
      case BilibiliCategory.music: return t.popularCategory.music;
      case BilibiliCategory.dance: return t.popularCategory.dance;
      case BilibiliCategory.game: return t.popularCategory.game;
      case BilibiliCategory.anime: return t.popularCategory.anime;
      case BilibiliCategory.entertainment: return t.popularCategory.entertainment;
      case BilibiliCategory.tech: return t.popularCategory.tech;
      case BilibiliCategory.life: return t.popularCategory.life;
      case BilibiliCategory.movie: return t.popularCategory.movie;
      case BilibiliCategory.kichiku: return t.popularCategory.kichiku;
    }
  }
}

// ==================== Bilibili 排行榜 ====================

/// 排行榜视频状态
class RankingState {
  final Map<BilibiliCategory, List<Track>> tracksByCategory;
  final BilibiliCategory selectedCategory;
  final bool isLoading;
  final String? error;

  const RankingState({
    this.tracksByCategory = const {},
    this.selectedCategory = BilibiliCategory.music,
    this.isLoading = false,
    this.error,
  });

  List<Track> get currentTracks => tracksByCategory[selectedCategory] ?? [];

  RankingState copyWith({
    Map<BilibiliCategory, List<Track>>? tracksByCategory,
    BilibiliCategory? selectedCategory,
    bool? isLoading,
    String? error,
  }) {
    return RankingState(
      tracksByCategory: tracksByCategory ?? this.tracksByCategory,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 排行榜 Provider
final rankingVideosProvider =
    StateNotifierProvider<RankingVideosNotifier, RankingState>((ref) {
  return RankingVideosNotifier(BilibiliSource());
});

class RankingVideosNotifier extends StateNotifier<RankingState> {
  final BilibiliSource _source;

  RankingVideosNotifier(this._source) : super(const RankingState());

  /// 加载指定分区的排行榜
  Future<void> loadCategory(BilibiliCategory category) async {
    // 如果已经加载过，直接切换
    if (state.tracksByCategory.containsKey(category)) {
      state = state.copyWith(selectedCategory: category);
      return;
    }

    state = state.copyWith(isLoading: true, selectedCategory: category, error: null);

    try {
      final tracks = await _source.getRankingVideos(rid: category.rid);
      state = state.copyWith(
        tracksByCategory: {...state.tracksByCategory, category: tracks},
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 刷新当前分区
  Future<void> refresh() async {
    final category = state.selectedCategory;
    state = state.copyWith(
      tracksByCategory: Map.from(state.tracksByCategory)..remove(category),
    );
    await loadCategory(category);
  }
}

/// 首頁 Bilibili 音樂排行預覽 Provider（使用緩存服務）
final homeBilibiliMusicRankingProvider = StreamProvider<List<Track>>((ref) async* {
  final service = ref.watch(rankingCacheServiceProvider);

  // 發送當前緩存的前 10 首（如果有）
  if (service.bilibiliTracks.isNotEmpty) {
    yield service.bilibiliTracks.take(AppConstants.rankingPreviewCount).toList();
  }

  // 監聽後續更新
  await for (final _ in service.stateChanges) {
    yield service.bilibiliTracks.take(AppConstants.rankingPreviewCount).toList();
  }
});

// ==================== YouTube 熱門 ====================

/// YouTube 熱門分類（目前只使用 music）
enum YouTubeCategory {
  music('music', '音樂');

  final String id;
  final String label;
  const YouTubeCategory(this.id, this.label);

  String get displayName => t.popularCategory.ytMusic;
}

/// YouTube 熱門視頻狀態
class YouTubeTrendingState {
  final Map<YouTubeCategory, List<Track>> tracksByCategory;
  final YouTubeCategory selectedCategory;
  final bool isLoading;
  final String? error;

  const YouTubeTrendingState({
    this.tracksByCategory = const {},
    this.selectedCategory = YouTubeCategory.music,
    this.isLoading = false,
    this.error,
  });

  List<Track> get currentTracks => tracksByCategory[selectedCategory] ?? [];

  YouTubeTrendingState copyWith({
    Map<YouTubeCategory, List<Track>>? tracksByCategory,
    YouTubeCategory? selectedCategory,
    bool? isLoading,
    String? error,
  }) {
    return YouTubeTrendingState(
      tracksByCategory: tracksByCategory ?? this.tracksByCategory,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// YouTube 熱門 Provider
final youtubeTrendingProvider =
    StateNotifierProvider<YouTubeTrendingNotifier, YouTubeTrendingState>((ref) {
  return YouTubeTrendingNotifier(YouTubeSource());
});

class YouTubeTrendingNotifier extends StateNotifier<YouTubeTrendingState> {
  final YouTubeSource _source;

  YouTubeTrendingNotifier(this._source) : super(const YouTubeTrendingState());

  /// 加載指定分類的熱門視頻
  Future<void> loadCategory(YouTubeCategory category) async {
    // 如果已經加載過，直接切換
    if (state.tracksByCategory.containsKey(category)) {
      state = state.copyWith(selectedCategory: category);
      return;
    }

    state = state.copyWith(isLoading: true, selectedCategory: category, error: null);

    try {
      final tracks = await _source.getTrendingVideos(category: category.id);
      state = state.copyWith(
        tracksByCategory: {...state.tracksByCategory, category: tracks},
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 刷新當前分類
  Future<void> refresh() async {
    final category = state.selectedCategory;
    state = state.copyWith(
      tracksByCategory: Map.from(state.tracksByCategory)..remove(category),
    );
    await loadCategory(category);
  }
}

/// 首頁 YouTube 音樂排行預覽 Provider（使用緩存服務）
final homeYouTubeMusicRankingProvider = StreamProvider<List<Track>>((ref) async* {
  final service = ref.watch(rankingCacheServiceProvider);

  // 發送當前緩存的前 10 首（如果有）
  if (service.youtubeTracks.isNotEmpty) {
    yield service.youtubeTracks.take(AppConstants.rankingPreviewCount).toList();
  }

  // 監聯後續更新
  await for (final _ in service.stateChanges) {
    yield service.youtubeTracks.take(AppConstants.rankingPreviewCount).toList();
  }
});

// ==================== 緩存排行榜（探索頁使用） ====================

/// Bilibili 完整緩存排行榜 Provider（探索頁使用）
final cachedBilibiliRankingProvider = StreamProvider<List<Track>>((ref) async* {
  final service = ref.watch(rankingCacheServiceProvider);

  // 發送當前完整緩存（如果有）
  if (service.bilibiliTracks.isNotEmpty) {
    yield service.bilibiliTracks;
  }

  // 監聽後續更新
  await for (final _ in service.stateChanges) {
    yield service.bilibiliTracks;
  }
});

/// YouTube 完整緩存排行榜 Provider（探索頁使用）
final cachedYouTubeRankingProvider = StreamProvider<List<Track>>((ref) async* {
  final service = ref.watch(rankingCacheServiceProvider);

  // 發送當前完整緩存（如果有）
  if (service.youtubeTracks.isNotEmpty) {
    yield service.youtubeTracks;
  }

  // 監聽後續更新
  await for (final _ in service.stateChanges) {
    yield service.youtubeTracks;
  }
});
