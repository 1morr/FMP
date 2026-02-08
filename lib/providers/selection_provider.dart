import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/track.dart';

/// 選擇項的唯一標識
/// 使用 sourceId + pageNum 組合來唯一標識一首歌曲
class SelectionKey {
  final String sourceId;
  final int? pageNum;

  const SelectionKey({required this.sourceId, this.pageNum});

  factory SelectionKey.fromTrack(Track track) {
    return SelectionKey(sourceId: track.sourceId, pageNum: track.pageNum);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SelectionKey &&
        other.sourceId == sourceId &&
        other.pageNum == pageNum;
  }

  @override
  int get hashCode => Object.hash(sourceId, pageNum);

  @override
  String toString() => 'SelectionKey($sourceId, p$pageNum)';
}

/// 多選模式狀態
class SelectionState {
  /// 是否處於多選模式
  final bool isSelectionMode;

  /// 已選擇的項目 keys
  final Set<SelectionKey> selectedKeys;

  /// 已選擇的 tracks（用於執行操作）
  final List<Track> selectedTracks;

  const SelectionState({
    this.isSelectionMode = false,
    this.selectedKeys = const {},
    this.selectedTracks = const [],
  });

  /// 選擇數量
  int get selectedCount => selectedKeys.length;

  /// 是否有選擇
  bool get hasSelection => selectedKeys.isNotEmpty;

  /// 檢查某個 track 是否被選中
  bool isSelected(Track track) {
    return selectedKeys.contains(SelectionKey.fromTrack(track));
  }

  /// 檢查某個 key 是否被選中
  bool isKeySelected(SelectionKey key) {
    return selectedKeys.contains(key);
  }

  SelectionState copyWith({
    bool? isSelectionMode,
    Set<SelectionKey>? selectedKeys,
    List<Track>? selectedTracks,
  }) {
    return SelectionState(
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      selectedKeys: selectedKeys ?? this.selectedKeys,
      selectedTracks: selectedTracks ?? this.selectedTracks,
    );
  }
}

/// 多選模式控制器
class SelectionNotifier extends StateNotifier<SelectionState> {
  SelectionNotifier() : super(const SelectionState());

  /// 進入多選模式，並選中初始項目
  void enterSelectionMode(Track initialTrack) {
    final key = SelectionKey.fromTrack(initialTrack);
    state = SelectionState(
      isSelectionMode: true,
      selectedKeys: {key},
      selectedTracks: [initialTrack],
    );
  }

  /// 進入多選模式，並選中多個初始項目（用於選擇組）
  void enterSelectionModeWithTracks(List<Track> initialTracks) {
    final keys = initialTracks.map((t) => SelectionKey.fromTrack(t)).toSet();
    state = SelectionState(
      isSelectionMode: true,
      selectedKeys: keys,
      selectedTracks: List.from(initialTracks),
    );
  }

  /// 退出多選模式
  void exitSelectionMode() {
    state = const SelectionState();
  }

  /// 切換單個項目的選中狀態
  void toggleSelection(Track track) {
    if (!state.isSelectionMode) return;

    final key = SelectionKey.fromTrack(track);
    final newKeys = Set<SelectionKey>.from(state.selectedKeys);
    final newTracks = List<Track>.from(state.selectedTracks);

    if (newKeys.contains(key)) {
      newKeys.remove(key);
      newTracks.removeWhere(
        (t) => t.sourceId == track.sourceId && t.pageNum == track.pageNum,
      );
    } else {
      newKeys.add(key);
      newTracks.add(track);
    }

    state = state.copyWith(
      selectedKeys: newKeys,
      selectedTracks: newTracks,
    );
  }

  /// 切換多個項目的選中狀態（用於組操作）
  void toggleGroupSelection(List<Track> tracks) {
    if (!state.isSelectionMode) return;

    final groupKeys = tracks.map((t) => SelectionKey.fromTrack(t)).toSet();
    final allSelected = groupKeys.every((k) => state.selectedKeys.contains(k));

    final newKeys = Set<SelectionKey>.from(state.selectedKeys);
    final newTracks = List<Track>.from(state.selectedTracks);

    if (allSelected) {
      // 全部已選中，則取消選中
      for (final key in groupKeys) {
        newKeys.remove(key);
      }
      for (final track in tracks) {
        newTracks.removeWhere(
          (t) => t.sourceId == track.sourceId && t.pageNum == track.pageNum,
        );
      }
    } else {
      // 部分或全部未選中，則全部選中
      for (final key in groupKeys) {
        if (!newKeys.contains(key)) {
          newKeys.add(key);
        }
      }
      for (final track in tracks) {
        final exists = newTracks.any(
          (t) => t.sourceId == track.sourceId && t.pageNum == track.pageNum,
        );
        if (!exists) {
          newTracks.add(track);
        }
      }
    }

    state = state.copyWith(
      selectedKeys: newKeys,
      selectedTracks: newTracks,
    );
  }

  /// 選中單個項目（不切換）
  void select(Track track) {
    if (!state.isSelectionMode) return;

    final key = SelectionKey.fromTrack(track);
    if (state.selectedKeys.contains(key)) return;

    final newKeys = Set<SelectionKey>.from(state.selectedKeys)..add(key);
    final newTracks = List<Track>.from(state.selectedTracks)..add(track);

    state = state.copyWith(
      selectedKeys: newKeys,
      selectedTracks: newTracks,
    );
  }

  /// 取消選中單個項目
  void deselect(Track track) {
    if (!state.isSelectionMode) return;

    final key = SelectionKey.fromTrack(track);
    if (!state.selectedKeys.contains(key)) return;

    final newKeys = Set<SelectionKey>.from(state.selectedKeys)..remove(key);
    final newTracks = List<Track>.from(state.selectedTracks)
      ..removeWhere(
        (t) => t.sourceId == track.sourceId && t.pageNum == track.pageNum,
      );

    state = state.copyWith(
      selectedKeys: newKeys,
      selectedTracks: newTracks,
    );
  }

  /// 全選
  void selectAll(List<Track> allTracks) {
    if (!state.isSelectionMode) return;

    final keys = allTracks.map((t) => SelectionKey.fromTrack(t)).toSet();
    state = state.copyWith(
      selectedKeys: keys,
      selectedTracks: List.from(allTracks),
    );
  }

  /// 取消全選
  void deselectAll() {
    if (!state.isSelectionMode) return;

    state = state.copyWith(
      selectedKeys: {},
      selectedTracks: [],
    );
  }

  /// 檢查組是否全部選中
  bool isGroupFullySelected(List<Track> tracks) {
    return tracks.every((t) => state.isSelected(t));
  }

  /// 檢查組是否部分選中
  bool isGroupPartiallySelected(List<Track> tracks) {
    final selectedCount = tracks.where((t) => state.isSelected(t)).length;
    return selectedCount > 0 && selectedCount < tracks.length;
  }
}

/// 歌單詳情頁的多選狀態 Provider
final playlistDetailSelectionProvider =
    StateNotifierProvider.autoDispose<SelectionNotifier, SelectionState>((ref) {
  return SelectionNotifier();
});

/// 探索頁的多選狀態 Provider
final exploreSelectionProvider =
    StateNotifierProvider.autoDispose<SelectionNotifier, SelectionState>((ref) {
  return SelectionNotifier();
});

/// 搜索頁的多選狀態 Provider
final searchSelectionProvider =
    StateNotifierProvider.autoDispose<SelectionNotifier, SelectionState>((ref) {
  return SelectionNotifier();
});
