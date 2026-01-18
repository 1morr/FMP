import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/track.dart';
import '../data/sources/bilibili_source.dart';
import '../data/sources/youtube_source.dart';

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
}

/// 热门视频状态
class PopularState {
  final List<Track> tracks;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final bool hasMore;

  const PopularState({
    this.tracks = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.hasMore = true,
  });

  PopularState copyWith({
    List<Track>? tracks,
    bool? isLoading,
    String? error,
    int? currentPage,
    bool? hasMore,
  }) {
    return PopularState(
      tracks: tracks ?? this.tracks,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

/// 热门视频 Provider
final popularVideosProvider =
    StateNotifierProvider<PopularVideosNotifier, PopularState>((ref) {
  return PopularVideosNotifier(BilibiliSource());
});

class PopularVideosNotifier extends StateNotifier<PopularState> {
  final BilibiliSource _source;

  PopularVideosNotifier(this._source) : super(const PopularState());

  /// 加载热门视频
  Future<void> load() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final tracks = await _source.getPopularVideos(page: 1, pageSize: 20);
      state = state.copyWith(
        tracks: tracks,
        isLoading: false,
        currentPage: 1,
        hasMore: tracks.length >= 20,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 加载更多
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final nextPage = state.currentPage + 1;
      final tracks = await _source.getPopularVideos(page: nextPage, pageSize: 20);
      state = state.copyWith(
        tracks: [...state.tracks, ...tracks],
        isLoading: false,
        currentPage: nextPage,
        hasMore: tracks.length >= 20,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 刷新
  Future<void> refresh() async {
    state = const PopularState();
    await load();
  }
}

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

/// 首页热门预览 Provider（只加载少量数据）
final homePopularPreviewProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  final source = BilibiliSource();
  return source.getPopularVideos(page: 1, pageSize: 10);
});

/// 首页音乐排行预览 Provider
final homeMusicRankingPreviewProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  final source = BilibiliSource();
  return source.getRankingVideos(rid: BilibiliCategory.music.rid);
});

// ==================== YouTube 熱門 ====================

/// YouTube 熱門分類
enum YouTubeCategory {
  now('now', '熱門'),
  music('music', '音樂'),
  gaming('gaming', '遊戲'),
  movies('movies', '電影');

  final String id;
  final String label;
  const YouTubeCategory(this.id, this.label);
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

/// 首頁 YouTube 熱門預覽 Provider
final homeYouTubeTrendingPreviewProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  final source = YouTubeSource();
  try {
    final tracks = await source.getTrendingVideos(category: 'music');
    return tracks.take(10).toList();
  } catch (e) {
    // 如果 YouTube API 失敗，返回空列表
    return [];
  }
});
