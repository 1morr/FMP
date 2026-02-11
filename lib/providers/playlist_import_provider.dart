import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/track.dart';
import '../data/sources/playlist_import/playlist_import_source.dart';
import '../data/sources/source_provider.dart';
import '../services/import/playlist_import_service.dart';

/// 导入状态
class PlaylistImportState {
  final bool isLoading;
  final ImportPhase phase;
  final ImportProgress progress;
  final ImportedPlaylist? playlist;
  final List<MatchedTrack> matchedTracks;
  final String? errorMessage;
  final SearchSourceConfig searchSource;

  const PlaylistImportState({
    this.isLoading = false,
    this.phase = ImportPhase.idle,
    this.progress = const ImportProgress(),
    this.playlist,
    this.matchedTracks = const [],
    this.errorMessage,
    this.searchSource = SearchSourceConfig.all,
  });

  PlaylistImportState copyWith({
    bool? isLoading,
    ImportPhase? phase,
    ImportProgress? progress,
    ImportedPlaylist? playlist,
    List<MatchedTrack>? matchedTracks,
    String? errorMessage,
    SearchSourceConfig? searchSource,
  }) {
    return PlaylistImportState(
      isLoading: isLoading ?? this.isLoading,
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      playlist: playlist ?? this.playlist,
      matchedTracks: matchedTracks ?? this.matchedTracks,
      errorMessage: errorMessage,
      searchSource: searchSource ?? this.searchSource,
    );
  }

  /// 获取已匹配的歌曲数量
  int get matchedCount => matchedTracks
      .where((t) => t.status == MatchStatus.matched || t.status == MatchStatus.userSelected)
      .length;

  /// 获取未匹配的歌曲数量
  int get unmatchedCount => matchedTracks
      .where((t) => t.status == MatchStatus.noResult)
      .length;

  /// 获取已选中的歌曲（用于创建歌单）
  List<Track> get selectedTracks => matchedTracks
      .where((t) => t.isIncluded && t.selectedTrack != null)
      .map((t) => t.selectedTrack!)
      .toList();

  /// 获取未匹配的原始歌曲（包括用户手动选择的）
  List<ImportedTrack> get unmatchedOriginalTracks => matchedTracks
      .where((t) => t.status == MatchStatus.noResult || t.status == MatchStatus.userSelected)
      .map((t) => t.original)
      .toList();

  /// 获取未匹配的 MatchedTrack（包括用户手动选择的，用于 UI 显示选中状态）
  List<MatchedTrack> get unmatchedMatchedTracks => matchedTracks
      .where((t) => t.status == MatchStatus.noResult || t.status == MatchStatus.userSelected)
      .toList();
}

/// 歌单导入状态管理
class PlaylistImportNotifier extends StateNotifier<PlaylistImportState> {
  final PlaylistImportService _service;
  StreamSubscription<ImportProgress>? _progressSubscription;
  bool _importCancelled = false;

  PlaylistImportNotifier(this._service) : super(const PlaylistImportState()) {
    _progressSubscription = _service.progressStream.listen((progress) {
      if (!_importCancelled) {
        state = state.copyWith(
          progress: progress,
          phase: progress.phase,
        );
      }
    });
  }

  /// 取消当前导入
  void cancelImport() {
    _importCancelled = true;
    _service.cancelImport();
    state = const PlaylistImportState();
  }

  /// 设置搜索来源
  void setSearchSource(SearchSourceConfig source) {
    state = state.copyWith(searchSource: source);
  }

  /// 检测链接对应的平台
  PlaylistSource? detectSource(String url) {
    return _service.detectSource(url);
  }

  /// 导入并匹配歌单
  Future<void> importAndMatch(String url) async {
    _importCancelled = false;
    state = state.copyWith(
      isLoading: true,
      phase: ImportPhase.fetching,
      errorMessage: null,
    );

    try {
      final result = await _service.importAndMatch(
        url,
        searchSource: state.searchSource,
      );

      if (_importCancelled) return;

      state = state.copyWith(
        isLoading: false,
        phase: ImportPhase.completed,
        playlist: result.playlist,
        matchedTracks: result.matchedTracks,
      );
    } on ImportCancelledException {
      // 用户取消，不设置错误状态
      return;
    } catch (e) {
      if (_importCancelled) return;

      state = state.copyWith(
        isLoading: false,
        phase: ImportPhase.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 更新匹配结果（用户选择其他搜索结果）
  void selectAlternative(int index, Track track) {
    if (index < 0 || index >= state.matchedTracks.length) return;

    final updatedTracks = List<MatchedTrack>.from(state.matchedTracks);
    final current = updatedTracks[index];
    updatedTracks[index] = current.copyWith(
      selectedTrack: track,
      // Keep matched status if already matched; only use userSelected for originally unmatched tracks
      status: current.status == MatchStatus.matched
          ? MatchStatus.matched
          : MatchStatus.userSelected,
    );

    state = state.copyWith(matchedTracks: updatedTracks);
  }

  /// 切换是否包含某首歌曲
  void toggleInclude(int index, bool isIncluded) {
    if (index < 0 || index >= state.matchedTracks.length) return;

    final updatedTracks = List<MatchedTrack>.from(state.matchedTracks);
    updatedTracks[index] = updatedTracks[index].copyWith(
      isIncluded: isIncluded,
    );

    state = state.copyWith(matchedTracks: updatedTracks);
  }

  /// 手动搜索并更新匹配结果
  Future<void> manualSearch(int index, String query) async {
    if (index < 0 || index >= state.matchedTracks.length) return;

    final updatedTracks = List<MatchedTrack>.from(state.matchedTracks);
    updatedTracks[index] = updatedTracks[index].copyWith(
      status: MatchStatus.searching,
    );
    state = state.copyWith(matchedTracks: updatedTracks);

    try {
      final results = await _service.searchForTrack(
        query,
        searchSource: state.searchSource,
      );

      updatedTracks[index] = updatedTracks[index].copyWith(
        searchResults: results,
        selectedTrack: results.isNotEmpty ? results.first : null,
        status: results.isNotEmpty ? MatchStatus.matched : MatchStatus.noResult,
      );

      state = state.copyWith(matchedTracks: updatedTracks);
    } catch (e) {
      updatedTracks[index] = updatedTracks[index].copyWith(
        status: MatchStatus.noResult,
      );
      state = state.copyWith(matchedTracks: updatedTracks);
    }
  }

  /// 为未匹配歌曲搜索（仅返回结果，不更新状态）
  Future<List<Track>> searchForUnmatched(String query) async {
    return await _service.searchForTrack(
      query,
      searchSource: state.searchSource,
      maxResults: 5,
    );
  }

  /// 用手动搜索结果更新未匹配歌曲（保留在未匹配区域，使用 userSelected 状态）
  void updateWithManualMatch(int index, Track selectedTrack, List<Track> searchResults) {
    if (index < 0 || index >= state.matchedTracks.length) return;

    final updatedTracks = List<MatchedTrack>.from(state.matchedTracks);
    updatedTracks[index] = updatedTracks[index].copyWith(
      searchResults: searchResults,
      selectedTrack: selectedTrack,
      status: MatchStatus.userSelected,
      isIncluded: true,
    );

    state = state.copyWith(matchedTracks: updatedTracks);
  }

  /// 重置状态
  void reset() {
    state = const PlaylistImportState();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _service.dispose();
    super.dispose();
  }
}

/// Provider
final playlistImportServiceProvider = Provider<PlaylistImportService>((ref) {
  final sourceManager = ref.watch(sourceManagerProvider);
  return PlaylistImportService(sourceManager: sourceManager);
});

final playlistImportProvider =
    StateNotifierProvider<PlaylistImportNotifier, PlaylistImportState>((ref) {
  final service = ref.watch(playlistImportServiceProvider);
  return PlaylistImportNotifier(service);
});
