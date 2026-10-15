import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_providers.dart';

final playlistServiceProvider = Provider<PlaylistService>(
  (ref) => PlaylistService(
    repository: ref.watch(playlistRepositoryProvider),
    controller: ref.watch(playbackControllerProvider),
  ),
);

/// 本機歌單的操作（ADR 0033 §決定 8、9，M4 design §10.3–§10.6）：建立、編輯、刪除、排序、
/// 把整張歌單加入佇列，與本機歌單的曲目增刪、重排。匯入、刷新與 Mix 歌單在之後的 PR。
final class PlaylistService {
  PlaylistService({
    required this._repository,
    required this._controller,
    Random? random,
  }) : _random = random ?? Random();

  final PlaylistRepository _repository;
  final PlaybackController _controller;
  final Random _random;

  /// 建一張本機歌單，加在清單最後；名稱與描述去掉頭尾空白，描述是空的就不存。[artwork] 是
  /// 自訂封面（空＝第一首的封面）。回傳 id。
  Future<int> create({
    required String name,
    String? description,
    List<TrackArtwork> artwork = const [],
  }) => _repository.create(
    name: name.trim(),
    description: _optional(description),
    artwork: artwork,
  );

  /// 改名稱、描述與封面（[artwork] 空＝清回第一首的封面）。
  Future<void> edit(
    Playlist playlist, {
    required String name,
    String? description,
    required List<TrackArtwork> artwork,
  }) => _repository.update(
    playlist.id,
    name: name.trim(),
    description: _optional(description),
    artwork: artwork,
  );

  /// 刪歌單與它的項目（呼叫端先確認）。
  Future<void> delete(int id) => _repository.delete(id);

  /// 依 [ids] 的順序重寫整份清單的順序。
  Future<void> reorder(List<int> ids) => _repository.reorder(ids);

  /// 把歌單的全部曲目接在佇列最後（ADR 0018 的 D2：只加入、不取代）；[shuffle] 時先打亂
  /// （design §17 第 14 條的「隨機加入」）。會超過佇列上限就整批不加：控制器發 `QueueFull`，
  /// 外殼提示（ADR 0018 §決定 4）。Mix 中控制器拒絕、不發事件（入口停用）。回傳加入了幾首，
  /// 沒加入是 `null`。
  Future<int?> addToQueue(int playlistId, {bool shuffle = false}) async {
    final tracks = [
      for (final entry in await _repository.entries(playlistId)) entry.track,
    ];
    if (shuffle) tracks.shuffle(_random);
    return _controller.addToQueue(tracks) ? tracks.length : null;
  }

  /// 把 [tracks] 依序接在每一張 [playlistIds] 的尾端（「加入歌單…」，design §10.6）；同一首
  /// 可以重複加入。只收本機歌單：匯入歌單的曲目不能在本地增刪（ADR 0019 §決定 4），遇到時
  /// 什麼都不加、丟 [StateError]。
  Future<void> addTracks(List<int> playlistIds, List<TrackInfo> tracks) async {
    for (final id in playlistIds) {
      await _requireLocal(id);
    }
    for (final id in playlistIds) {
      await _repository.addTracks(id, tracks);
    }
  }

  /// 從本機歌單 [playlistId] 刪掉 [entryIds] 的項目。不是本機歌單丟 [StateError]。
  Future<void> removeEntries(int playlistId, List<int> entryIds) async {
    await _requireLocal(playlistId);
    await _repository.removeEntries(playlistId, entryIds);
  }

  /// 依 [entryIds] 的順序重寫本機歌單 [playlistId] 的曲目順序。不是本機歌單丟
  /// [StateError]。
  Future<void> moveEntries(int playlistId, List<int> entryIds) async {
    await _requireLocal(playlistId);
    await _repository.moveEntries(playlistId, entryIds);
  }

  Future<void> _requireLocal(int playlistId) async {
    final playlist = await _repository.find(playlistId);
    if (playlist == null || playlist.kind != PlaylistKind.local) {
      throw StateError('Playlist $playlistId is not a local playlist');
    }
  }

  static String? _optional(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
