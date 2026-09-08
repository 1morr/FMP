import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/user_message.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/playlist_import/playlist_import_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/import/playlist_import_service.dart';

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
      .where(
        (t) =>
            t.status == MatchStatus.matched ||
            t.status == MatchStatus.userSelected,
      )
      .length;

  /// 获取未匹配的歌曲数量
  int get unmatchedCount =>
      matchedTracks.where((t) => t.status == MatchStatus.noResult).length;

  /// 获取已选中的歌曲（用于创建歌单）
  List<Track> get selectedTracks => matchedTracks
      .where((t) => t.isIncluded && t.selectedTrack != null)
      .map((t) {
        final track = t.selectedTrack!.copy();
        if (t.original.sourceId != null) {
          track.originalSongId = t.original.sourceId;
          track.originalSource = _mapSourceToString(t.original.source);
        }
        return track;
      })
      .toList();

  /// 获取未匹配的原始歌曲（包括用户手动选择的）
  List<ImportedTrack> get unmatchedOriginalTracks => matchedTracks
      .where(
        (t) =>
            t.status == MatchStatus.noResult ||
            t.status == MatchStatus.userSelected,
      )
      .map((t) => t.original)
      .toList();

  /// 获取未匹配的 MatchedTrack（包括用户手动选择的，用于 UI 显示选中状态）
  List<MatchedTrack> get unmatchedMatchedTracks => matchedTracks
      .where(
        (t) =>
            t.status == MatchStatus.noResult ||
            t.status == MatchStatus.userSelected,
      )
      .toList();

  /// PlaylistSource → 歌词系统兼容的字符串
  static String? _mapSourceToString(PlaylistSource? source) {
    switch (source) {
      case PlaylistSource.netease:
        return 'netease';
      case PlaylistSource.qqMusic:
        return 'qqmusic';
      case PlaylistSource.spotify:
        return 'spotify';
      case null:
        return null;
    }
  }
}

/// 歌单导入状态管理
class PlaylistImportNotifier extends Notifier<PlaylistImportState> {
  late PlaylistImportService _service;
  StreamSubscription<ImportProgress>? _progressSubscription;
  int _importOperationId = 0;
  int? _activeImportOperationId;
  int _manualSearchOperationId = 0;
  final Map<int, int> _manualSearchOperations = {};

  @override
  PlaylistImportState build() {
    _service = ref.watch(playlistImportServiceProvider);
    _progressSubscription = _service.progressStream.listen((progress) {
      if (_activeImportOperationId != null && ref.mounted) {
        state = state.copyWith(progress: progress, phase: progress.phase);
      }
    });
    // 這條訂閱以前開在建構子、關在 `dispose()`。`ref.onDispose` 在 provider
    // 即將 rebuild 時也會跑，所以每一次 build 開的訂閱都成對關掉 —— 漏了這行
    // 就是每次 rebuild 洩一條，而且不會有任何錯誤訊息。
    ref.onDispose(_teardown);
    return const PlaylistImportState();
  }

  /// 取消当前导入
  void cancelImport() {
    _importOperationId++;
    _activeImportOperationId = null;
    _manualSearchOperations.clear();
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
    final operationId = ++_importOperationId;
    _activeImportOperationId = operationId;
    _manualSearchOperations.clear();
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

      if (!_isImportOperationCurrent(operationId)) return;

      state = state.copyWith(
        isLoading: false,
        phase: ImportPhase.completed,
        playlist: result.playlist,
        matchedTracks: result.matchedTracks,
      );
      _activeImportOperationId = null;
    } on ImportCancelledException {
      // 用户取消，不设置错误状态
      if (_isImportOperationCurrent(operationId)) {
        _activeImportOperationId = null;
      }
      return;
    } catch (e, stack) {
      if (!_isImportOperationCurrent(operationId)) return;

      state = state.copyWith(
        isLoading: false,
        phase: ImportPhase.error,
        errorMessage: failureMessage(
          e,
          stack,
          'Playlist import failed',
          tag: 'Import',
        ),
      );
      _activeImportOperationId = null;
    }
  }

  bool _isImportOperationCurrent(int operationId) {
    return ref.mounted && _activeImportOperationId == operationId;
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

    final operationId = ++_manualSearchOperationId;
    _manualSearchOperations[index] = operationId;
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

      if (!_isManualSearchCurrent(index, operationId)) return;
      final latestTracks = List<MatchedTrack>.from(state.matchedTracks);
      if (index < 0 || index >= latestTracks.length) {
        _manualSearchOperations.remove(index);
        return;
      }
      latestTracks[index] = latestTracks[index].copyWith(
        searchResults: results,
        selectedTrack: results.isNotEmpty ? results.first : null,
        status: results.isNotEmpty ? MatchStatus.matched : MatchStatus.noResult,
      );

      state = state.copyWith(matchedTracks: latestTracks);
      _manualSearchOperations.remove(index);
    } catch (e) {
      if (!_isManualSearchCurrent(index, operationId)) return;
      final latestTracks = List<MatchedTrack>.from(state.matchedTracks);
      if (index < 0 || index >= latestTracks.length) {
        _manualSearchOperations.remove(index);
        return;
      }
      latestTracks[index] = latestTracks[index].copyWith(
        status: MatchStatus.noResult,
      );
      state = state.copyWith(matchedTracks: latestTracks);
      _manualSearchOperations.remove(index);
    }
  }

  bool _isManualSearchCurrent(int index, int operationId) {
    return ref.mounted && _manualSearchOperations[index] == operationId;
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
  void updateWithManualMatch(
    int index,
    Track selectedTrack,
    List<Track> searchResults,
  ) {
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
    _importOperationId++;
    _activeImportOperationId = null;
    _manualSearchOperations.clear();
    _service.cancelImport();
    state = const PlaylistImportState();
  }

  void _teardown() {
    _importOperationId++;
    _activeImportOperationId = null;
    _manualSearchOperations.clear();
    _progressSubscription?.cancel();
    _service.dispose();
  }
}

/// Provider
final playlistImportServiceProvider = Provider<PlaylistImportService>((ref) {
  final sourceManager = ref.watch(sourceManagerProvider);
  return PlaylistImportService(sourceManager: sourceManager);
});

final playlistImportProvider =
    NotifierProvider<PlaylistImportNotifier, PlaylistImportState>(
      PlaylistImportNotifier.new,
    );
