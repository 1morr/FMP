import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 分 P 取得到哪一步。
enum PartsPhase { loading, loaded, failed }

/// 一支影片的分 P 狀態（搜尋結果列的展開、影片選單共用）。
@immutable
final class VideoPartsEntry {
  const VideoPartsEntry({
    required this.phase,
    this.parts = const [],
    this.expanded = false,
  });

  final PartsPhase phase;
  final List<MultiPart> parts;

  /// 列下面是不是展開了分 P 清單。
  final bool expanded;

  /// 取過了而且只有一個分 P：確定是單 P，展開鈕不再顯示。
  bool get isSingle => phase == PartsPhase.loaded && parts.length <= 1;

  VideoPartsEntry copyWith({PartsPhase? phase, bool? expanded}) =>
      VideoPartsEntry(
        phase: phase ?? this.phase,
        parts: parts,
        expanded: expanded ?? this.expanded,
      );
}

/// 搜尋結果的影片是否展開與取回的分 P，鍵是 `TrackKey.formatGroup`（音源與影片 id）。
/// 在記憶體，不持久化；分 P 不會變，取過就不再取（失敗的才重取）。
final videoPartsProvider =
    NotifierProvider<VideoParts, Map<String, VideoPartsEntry>>(VideoParts.new);

final class VideoParts extends Notifier<Map<String, VideoPartsEntry>> {
  final _inFlight = <String, Future<List<MultiPart>>>{};

  @override
  Map<String, VideoPartsEntry> build() => const {};

  static String keyOf(String pluginId, String sourceId) =>
      TrackKey.formatGroup(pluginId, sourceId);

  void _put(String key, VideoPartsEntry entry) =>
      state = {...state, key: entry};

  /// [sourceId] 的分 P：取過的直接回，進行中的接同一個請求。失敗拋 [AppError]，
  /// 狀態記為 [PartsPhase.failed]（再呼叫會重取）。
  Future<List<MultiPart>> load(SourcePlugin plugin, String sourceId) {
    final key = keyOf(plugin.manifest.id, sourceId);
    final entry = state[key];
    if (entry != null && entry.phase == PartsPhase.loaded) {
      return Future.value(entry.parts);
    }
    return _inFlight[key] ??= _fetch(plugin, sourceId, key);
  }

  Future<List<MultiPart>> _fetch(
    SourcePlugin plugin,
    String sourceId,
    String key,
  ) async {
    final expanded = state[key]?.expanded ?? false;
    _put(key, VideoPartsEntry(phase: PartsPhase.loading, expanded: expanded));
    try {
      final result = await plugin.multiPart(MultiPartQuery(sourceId: sourceId));
      // 只有一個分 P：展開鈕之後不再顯示（isSingle），列也就不會展開。
      _put(
        key,
        VideoPartsEntry(
          phase: PartsPhase.loaded,
          parts: result.parts,
          expanded: state[key]?.expanded ?? expanded,
        ),
      );
      return result.parts;
    } on Object catch (error, stackTrace) {
      _put(
        key,
        VideoPartsEntry(
          phase: PartsPhase.failed,
          expanded: state[key]?.expanded ?? expanded,
        ),
      );
      throw AppError.wrap(error, stackTrace);
    } finally {
      unawaited(_inFlight.remove(key));
    }
  }

  /// 新的搜尋開始時收起所有影片（取過的分 P 留著，不再取）：展開是對著一份結果的，
  /// 同一支影片出現在下一次搜尋裡時從收起開始（舊版的展開也是列自己的狀態）。
  void collapseAll() {
    if (!state.values.any((entry) => entry.expanded)) return;
    state = {
      for (final MapEntry(:key, :value) in state.entries)
        key: value.copyWith(expanded: false),
    };
  }

  /// 展開（取分 P）或收起。取分 P 失敗時留在展開，列下面顯示重試；錯誤以回傳的
  /// [AppError] 交給呼叫端顯示。
  Future<AppError?> toggle(SourcePlugin plugin, String sourceId) async {
    final key = keyOf(plugin.manifest.id, sourceId);
    final entry = state[key];
    if (entry != null && entry.expanded && entry.phase != PartsPhase.failed) {
      _put(key, entry.copyWith(expanded: false));
      return null;
    }
    if (entry != null && entry.phase == PartsPhase.loaded) {
      _put(key, entry.copyWith(expanded: true));
      return null;
    }
    _put(
      key,
      (entry ?? const VideoPartsEntry(phase: PartsPhase.loading)).copyWith(
        phase: PartsPhase.loading,
        expanded: true,
      ),
    );
    try {
      await load(plugin, sourceId);
      return null;
    } on AppError catch (error) {
      return error;
    }
  }
}

/// [plugin] 宣告了 `multiPart`（外觀與選單都先看這個）。
bool declaresMultiPart(SourcePlugin? plugin) =>
    plugin?.manifest.capabilities.contains(PluginCapability.multiPart) ?? false;

/// 這個影片的列要不要有展開鈕：插件宣告 `multiPart`，而且 [partCount] 不是確定的 1、
/// 也沒有取過只有一個分 P（[entry]）。[partCount] 空是不知道，照樣顯示。
bool showsExpandButton({
  required SourcePlugin? plugin,
  required int? partCount,
  required VideoPartsEntry? entry,
}) =>
    declaresMultiPart(plugin) &&
    (partCount == null || partCount > 1) &&
    !(entry?.isSingle ?? false);
