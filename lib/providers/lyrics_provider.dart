import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/lyrics_match.dart';
import '../data/repositories/lyrics_repository.dart';
import '../services/audio/audio_provider.dart';
import '../services/lyrics/lrclib_source.dart';
import '../services/lyrics/title_parser.dart';
import 'repository_providers.dart';

// ---------------------------------------------------------------------------
// Singleton providers
// ---------------------------------------------------------------------------

/// LrclibSource 单例
final lrclibSourceProvider = Provider<LrclibSource>((ref) => LrclibSource());

/// TitleParser 单例
final titleParserProvider = Provider<TitleParser>((ref) => RegexTitleParser());

// ---------------------------------------------------------------------------
// 当前播放歌曲的歌词匹配
// ---------------------------------------------------------------------------

/// 当前播放歌曲的歌词匹配信息
final currentLyricsMatchProvider =
    FutureProvider.autoDispose<LyricsMatch?>((ref) {
  final currentTrack = ref.watch(currentTrackProvider);
  if (currentTrack == null) return null;
  final repo = ref.watch(lyricsRepositoryProvider);
  return repo.getByTrackKey(currentTrack.uniqueKey);
});

/// 当前播放歌曲的歌词内容（在线获取）
final currentLyricsContentProvider =
    FutureProvider.autoDispose<LrclibResult?>((ref) {
  final match = ref.watch(currentLyricsMatchProvider).valueOrNull;
  if (match == null) return null;
  final lrclib = ref.watch(lrclibSourceProvider);
  return lrclib.getById(match.externalId);
});

// ---------------------------------------------------------------------------
// 歌词搜索
// ---------------------------------------------------------------------------

/// 歌词搜索状态
class LyricsSearchState {
  final bool isLoading;
  final List<LrclibResult> results;
  final String? error;

  const LyricsSearchState({
    this.isLoading = false,
    this.results = const [],
    this.error,
  });

  LyricsSearchState copyWith({
    bool? isLoading,
    List<LrclibResult>? results,
    String? error,
  }) {
    return LyricsSearchState(
      isLoading: isLoading ?? this.isLoading,
      results: results ?? this.results,
      error: error,
    );
  }
}

/// 歌词搜索 Notifier
class LyricsSearchNotifier extends StateNotifier<LyricsSearchState> {
  final LrclibSource _lrclib;
  final LyricsRepository _repo;

  LyricsSearchNotifier(this._lrclib, this._repo)
      : super(const LyricsSearchState());

  /// 搜索歌词
  Future<void> search({String? query, String? trackName, String? artistName}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final results = await _lrclib.search(
        q: query,
        trackName: trackName,
        artistName: artistName,
      );
      if (!mounted) return;
      state = state.copyWith(isLoading: false, results: results);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 保存匹配
  Future<void> saveMatch({
    required String trackUniqueKey,
    required LrclibResult result,
  }) async {
    final match = LyricsMatch()
      ..trackUniqueKey = trackUniqueKey
      ..lyricsSource = 'lrclib'
      ..externalId = result.id
      ..offsetMs = 0
      ..matchedAt = DateTime.now();
    await _repo.save(match);
  }

  /// 删除匹配
  Future<void> removeMatch(String trackUniqueKey) async {
    await _repo.delete(trackUniqueKey);
  }

  /// 更新偏移
  Future<void> updateOffset(String trackUniqueKey, int offsetMs) async {
    await _repo.updateOffset(trackUniqueKey, offsetMs);
  }

  /// 重置搜索状态
  void reset() {
    state = const LyricsSearchState();
  }
}

/// 歌词搜索 Provider
final lyricsSearchProvider =
    StateNotifierProvider.autoDispose<LyricsSearchNotifier, LyricsSearchState>(
        (ref) {
  final lrclib = ref.watch(lrclibSourceProvider);
  final repo = ref.watch(lyricsRepositoryProvider);
  return LyricsSearchNotifier(lrclib, repo);
});

/// 查询指定 track 的歌词匹配（用于菜单显示"已匹配"状态）
final lyricsMatchForTrackProvider =
    FutureProvider.autoDispose.family<LyricsMatch?, String>((ref, trackKey) {
  final repo = ref.watch(lyricsRepositoryProvider);
  return repo.getByTrackKey(trackKey);
});
