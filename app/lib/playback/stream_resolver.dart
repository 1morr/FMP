import 'package:flutter/foundation.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 把曲目解析成串流候選（ADR 0018 §決定 6）。
///
/// M1 直接呼叫插件的 `resolveStream`：沒有本機下載檔，也沒有網址快取
/// （ADR 0016，M1 design 3.6）。丟出的錯誤都是 `AppError`。
final class StreamResolver {
  StreamResolver({required this._plugin, required List<PlayableFormat> formats})
    : _formats = List.unmodifiable([
        for (final format in formats)
          StreamFormat(container: format.container, codec: format.codec),
      ]);

  /// 以插件 id（曲目鍵的第一段）找插件；沒裝就是 `null`。
  final SourcePlugin? Function(String pluginId) _plugin;

  /// 平台可播的格式（`PlaybackSupport.formats`），原樣交給插件挑候選。
  final List<StreamFormat> _formats;

  /// 解析 [track] 的播放串流。音源沒裝是 `Unsupported`。
  Future<ResolvedStream> resolve(TrackKeyParts track) async {
    final plugin =
        _plugin(track.sourceTypeId) ??
        (throw Unsupported(pluginId: track.sourceTypeId));
    final candidates = await plugin.resolveStream(
      StreamRequest(
        sourceId: track.sourceId,
        cid: track.cid,
        formats: _formats,
      ),
    );
    return ResolvedStream(track: track, candidates: candidates);
  }
}

/// 一首曲目解析出的候選，依優先序排好，至少一個。
@immutable
final class ResolvedStream {
  ResolvedStream({required this.track, required this.candidates})
    : assert(candidates.isNotEmpty);

  /// 網址剩下不到這麼久就當成過期：留時間給開流與前瞻的預備。
  static const expiryMargin = Duration(seconds: 30);

  final TrackKeyParts track;
  final List<StreamCandidate> candidates;

  /// 第一個候選（前瞻用它）的網址在 [now] 還能不能用；沒有期限就一直能用。
  bool isFreshAt(DateTime now) => switch (candidates.first.expiresAt) {
    final expiresAt? => now.isBefore(expiresAt.subtract(expiryMargin)),
    null => true,
  };

  /// 第一個候選該重新解析的時間；沒有期限就是 `null`。
  DateTime? get refreshAt => candidates.first.expiresAt?.subtract(expiryMargin);
}
