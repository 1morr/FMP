import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 把曲目解析成串流候選（ADR 0018 §決定 6）。丟出的錯誤都是 `AppError`。
///
/// 解析結果放在記憶體網址快取（ADR 0016 §決定 5）：前瞻與播放共用同一份，
/// 同一首在網址到期前不再問插件。
/// - 鍵是曲目鍵（含分 P）加上送給插件的偏好，以及解析它的插件實例
///   （[_CacheKey]）；
/// - 最多 [capacity] 筆，淘汰最久沒用的；
/// - 有效到第一個候選的 `expiresAt` 減 [ResolvedStream.expiryMargin]；沒有期限
///   的在解析後 [unknownExpiryLifetime] 內有效；
/// - 播放失敗由 `PlaybackSession` 以 [invalidate] 作廢那一筆；
/// - 同一個鍵正在解析時，之後的呼叫拿同一個 `Future`；解析失敗不留下。
///
/// 只放記憶體（B6），時間經 `clock`，不開計時器：過期的在下次查詢時才丟掉。
/// M2 沒有本機下載檔（M6）。
final class StreamResolver {
  StreamResolver({
    required this._plugin,
    required List<PlayableFormat> formats,
    required this._log,
  }) : _formats = List.unmodifiable([
         for (final format in formats)
           StreamFormat(container: format.container, codec: format.codec),
       ]),
       _formatsKey = [
         for (final format in formats) '${format.container}/${format.codec}',
       ].join(',');

  /// 快取的筆數上限。
  static const capacity = 64;

  /// 插件沒給 `expiresAt` 時，解析結果在快取裡有效多久。
  static const unknownExpiryLifetime = Duration(minutes: 5);

  static const _tag = 'playback';

  /// 以插件 id（曲目鍵的第一段）找插件；沒裝就是 `null`。
  final SourcePlugin? Function(String pluginId) _plugin;

  /// 平台可播的格式（`PlaybackSupport.formats`），原樣交給插件挑候選。
  final List<StreamFormat> _formats;

  /// [_formats] 的順序，快取鍵的格式偏好。
  final String _formatsKey;

  final Log _log;

  /// 由最久沒用到最近用過（Map 字面值保留插入順序）。
  final _cache = <_CacheKey, _CachedStream>{};
  final _pending = <_CacheKey, Future<ResolvedStream>>{};

  /// 解析 [track] 的播放串流：快取裡還有效的直接回傳，正在解析的共用同一個
  /// 請求。音源沒裝是 `Unsupported`。
  Future<ResolvedStream> resolve(TrackKeyParts track) {
    final plugin = _plugin(track.sourceTypeId);
    if (plugin == null) {
      return Future.error(Unsupported(pluginId: track.sourceTypeId));
    }
    final key = (plugin: plugin, track: track, formats: _formatsKey);
    if (_cache.remove(key) case final cached?
        when clock.now().isBefore(cached.validUntil)) {
      // 重新放進去：成為最近用過的。
      _cache[key] = cached;
      _logReused(track, 'cache');
      return Future.value(cached.stream);
    }
    if (_pending[key] case final pending?) {
      _logReused(track, 'pending');
      return pending;
    }
    _log.info('Resolving stream', tag: _tag, fields: {'track': '$track'});
    // whenComplete 至少晚一個微任務才跑，所以一定在登記之後才移除。回呼不能
    // 回傳 remove 的結果：那就是這個 Future 自己，會等自己而永遠不完成。
    return _pending[key] = _fetch(plugin, track)
        .then((stream) => _remember(key, stream))
        .whenComplete(() {
          _pending.remove(key);
        });
  }

  /// 播放 [stream] 失敗（開不起來、中斷、被拒）：作廢快取裡的那一筆，下次要這
  /// 首時重新解析。那一筆已經被較新的解析結果取代時不動。
  void invalidate(ResolvedStream stream) {
    final before = _cache.length;
    _cache.removeWhere((_, cached) => identical(cached.stream, stream));
    if (_cache.length == before) return;
    _log.info(
      'Stream URL invalidated',
      tag: _tag,
      fields: {'track': '${stream.track}'},
    );
  }

  Future<ResolvedStream> _fetch(
    SourcePlugin plugin,
    TrackKeyParts track,
  ) async {
    final candidates = await plugin.resolveStream(
      StreamRequest(
        sourceId: track.sourceId,
        cid: track.cid,
        formats: _formats,
      ),
    );
    return ResolvedStream(track: track, candidates: candidates);
  }

  ResolvedStream _remember(_CacheKey key, ResolvedStream stream) {
    final validUntil =
        stream.candidates.first.expiresAt?.subtract(
          ResolvedStream.expiryMargin,
        ) ??
        clock.now().add(unknownExpiryLifetime);
    _cache.remove(key);
    // 一回來就在餘裕內的不放：只會擠掉有用的。
    if (clock.now().isBefore(validUntil)) {
      _cache[key] = _CachedStream(stream: stream, validUntil: validUntil);
      if (_cache.length > capacity) _cache.remove(_cache.keys.first);
    }
    return stream;
  }

  void _logReused(TrackKeyParts track, String from) => _log.info(
    'Stream URL reused',
    tag: _tag,
    fields: {'track': '$track', 'from': from},
  );
}

/// 快取鍵：曲目鍵（含分 P）＋送給插件的偏好。M2 PR 8 前偏好只有平台格式的
/// 順序（固定），音質與使用者的格式偏好在 PR 8 加進來。
///
/// [plugin] 以實例比對：插件更新後是新的實例，舊實例的結果（以舊 manifest 的
/// 網域檢查過）與還在進行的請求都不再給出，留在快取裡等 LRU 淘汰。
typedef _CacheKey = ({
  SourcePlugin plugin,
  TrackKeyParts track,
  String formats,
});

final class _CachedStream {
  _CachedStream({required this.stream, required this.validUntil});

  final ResolvedStream stream;

  /// 這個時間（含）之後不再用。
  final DateTime validUntil;
}

/// 一首曲目解析出的候選，依優先序排好，至少一個。
@immutable
final class ResolvedStream {
  ResolvedStream({required this.track, required this.candidates})
    : assert(candidates.isNotEmpty);

  /// 網址剩下不到這麼久就當成過期，前瞻的重新解析、交接前的檢查與網址快取
  /// 共用（ADR 0016 §決定 5）：要撐得過開流與接下來的播放，Android 只緩衝
  /// 10–20 秒，太短的餘裕會讓剛接上的那首播到一半就過期。
  static const expiryMargin = Duration(minutes: 5);

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
