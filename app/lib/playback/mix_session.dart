import 'dart:async';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/domain/mix_identity.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';

/// Mix 的開始與補歌（ADR 0031 §決定 9–10）。補歌是播放核心的事件，不經排程器
/// （ADR 0017 只管週期工作）；請求經插件，和 `resolveStream` 一樣。
///
/// - **何時補**：每首開始時（[trackStarted]），之後只剩 [refillThreshold] 首以下就以
///   `{mixId, cursor}` 續取；`cursor` 是空的就改以佇列最後一首當 `seed` 開新的一批，
///   Mix 身分換成回傳的 `mixId`。
/// - **合併**：回來的曲目以曲目鍵去重（已在佇列的丟掉）後附加（[QueueModel.extendMix]）。
///   標題只在 `mixId` 換了時跟著換：續取的批次插件不一定給得出原本的標題（重啟後
///   沒有地方記），照原本的。
/// - **並行**：同時只有一個補歌；補到之前 Mix 被換掉或退出（身分不同）就丟掉結果。
/// - **失敗**或去重後一首都沒有：只記進錯誤歷史，不提示；同一首（佇列項目）內不重試，
///   到下一首開始時再試。插件被停用或移除時不補。
/// - 佇列播到底而補歌還在跑時，控制器等 [whenIdle] 再決定往下播或停。
final class MixSession {
  MixSession({
    required this._queue,
    required this._fetch,
    required this._hasPlugin,
    required this._log,
    required this._onChanged,
  });

  /// 目前這首之後剩這麼多首（含）以下就補歌。
  static const refillThreshold = 1;

  static const _tag = 'mix';

  final QueueModel _queue;
  final Future<MixBatch> Function(String pluginId, MixQuery query) _fetch;
  final bool Function(String pluginId) _hasPlugin;
  final Log _log;

  /// 佇列因補歌改變之後呼叫（控制器發出新的佇列、前瞻改指新的下一首）。
  final void Function() _onChanged;

  /// 進行中的補歌；永遠不會以錯誤結束。
  Future<void>? _inFlight;

  /// 已經為它試過補歌的佇列項目（同一首內不重試）。
  QueueEntry? _attemptedFor;

  /// 補歌正在進行。
  bool get refilling => _inFlight != null;

  /// 進行中的補歌結束時完成；沒有補歌時馬上完成。
  Future<void> get whenIdle => _inFlight ?? Future<void>.value();

  /// 以 [seed] 開始一個 Mix：成功時 [QueueModel.startMix] 已取代整個佇列。插件的錯誤
  /// 原樣丟出（`AppError`）；插件沒給任何曲目是 `NotFound`。
  Future<void> start(TrackInfo seed) async {
    final batch = await _fetch(
      seed.sourceTypeId,
      MixSeedQuery(sourceId: seed.sourceId, cid: seed.cid),
    );
    final seen = <String>{};
    final tracks = [
      for (final summary in batch.tracks)
        if (seen.add('${summary.toTrackInfo().key}')) summary.toTrackInfo(),
    ];
    if (tracks.isEmpty) {
      throw NotFound(
        pluginId: seed.sourceTypeId,
        cause: StateError('The mix has no track'),
      );
    }
    _queue.startMix(
      MixIdentity(
        pluginId: seed.sourceTypeId,
        mixId: batch.mixId,
        title: batch.title,
        cursor: batch.cursor,
      ),
      tracks,
    );
    _log.info(
      'Mix started',
      tag: _tag,
      fields: {
        'plugin': seed.sourceTypeId,
        'mixId': batch.mixId,
        'tracks': tracks.length,
        'more': batch.cursor != null,
      },
    );
  }

  /// 目前這首開始了（換歌、前瞻接上、重啟後第一次播放）：該補歌就補。臨時播放與
  /// 直播中不補，結束回到 Mix 佇列的那首再算。
  void trackStarted() {
    final state = _queue.state;
    final mix = state.mix;
    final index = state.currentIndex;
    if (mix == null || index == null || state.mode != QueueMode.mix) return;
    if (_inFlight != null) return;
    final entry = state.entries[index];
    if (identical(_attemptedFor, entry)) return;
    if (state.entries.length - 1 - index > refillThreshold) return;
    _attemptedFor = entry;
    _inFlight = _refill(mix, state.entries.last.track).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _refill(MixIdentity mix, TrackInfo last) async {
    if (!_hasPlugin(mix.pluginId)) {
      _log.info(
        'Mix refill skipped: the source is unavailable',
        tag: _tag,
        fields: {'plugin': mix.pluginId},
      );
      return;
    }
    final cursor = mix.cursor;
    final MixQuery query = cursor == null
        ? MixSeedQuery(sourceId: last.sourceId, cid: last.cid)
        : MixContinueQuery(mixId: mix.mixId, cursor: cursor);
    _log.info(
      'Mix refill',
      tag: _tag,
      fields: {
        'plugin': mix.pluginId,
        'mixId': mix.mixId,
        'by': cursor == null ? 'seed' : 'cursor',
      },
    );
    final MixBatch batch;
    try {
      batch = await _fetch(mix.pluginId, query);
    } on Object catch (error, stackTrace) {
      _log.report(
        'Mix refill failed',
        AppError.wrap(error, stackTrace),
        tag: _tag,
      );
      return;
    }
    // 補歌期間 Mix 被換掉、退出或補過了：結果不屬於現在的佇列。
    if (_queue.state.mix != mix) {
      _log.info('Mix refill dropped: the mix changed', tag: _tag);
      return;
    }
    final added = _queue.extendMix(
      MixIdentity(
        pluginId: mix.pluginId,
        mixId: batch.mixId,
        title: batch.mixId == mix.mixId ? mix.title : batch.title,
        cursor: batch.cursor,
      ),
      [for (final summary in batch.tracks) summary.toTrackInfo()],
    );
    _onChanged();
    _log.info(
      'Mix refilled',
      tag: _tag,
      fields: {
        'mixId': batch.mixId,
        'returned': batch.tracks.length,
        'added': added,
        'more': batch.cursor != null,
      },
    );
    if (added == 0) {
      _log.report(
        'Mix refill added no track',
        NotFound(
          pluginId: mix.pluginId,
          cause: StateError('Every returned track was already queued'),
        ),
        tag: _tag,
      );
    }
  }
}
