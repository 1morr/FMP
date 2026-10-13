import 'package:flutter/foundation.dart';

import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';

/// 目前開著的串流（[PlaybackSession] 的來源）：選中候選的容器、編碼、位元率與來源
/// 類型。給 Debug 頁的播放狀態看（ADR 0025 §決定 5），唯讀。
@immutable
final class StreamDiagnostics {
  const StreamDiagnostics({
    required this.url,
    required this.candidate,
    required this.candidateCount,
    this.container,
    this.codec,
    this.bitrate,
  });

  final Uri url;

  /// 開的是第幾個候選（從 0 起）與總共有幾個。
  final int candidate;
  final int candidateCount;
  final String? container;
  final String? codec;
  final int? bitrate;

  /// `asset`：App 內附的測試曲目（`asset:///…`）；其他都是網路。
  String get sourceType => url.scheme == 'asset' ? 'asset' : 'network';
}

/// 佇列在 Debug 頁看的摘要：總數、目前位置、前後各 [window] 首的曲目鍵。
@immutable
final class QueueDiagnostics {
  const QueueDiagnostics({
    required this.total,
    required this.currentIndex,
    required this.before,
    required this.after,
    required this.shuffle,
    required this.loopMode,
    required this.temporary,
  });

  /// 目前這首前後各列幾首。
  static const window = 5;

  factory QueueDiagnostics.of(QueueState queue) {
    final index = queue.currentIndex;
    final keys = [for (final entry in queue.entries) '${entry.track.key}'];
    return QueueDiagnostics(
      total: keys.length,
      currentIndex: index,
      before: index == null
          ? const []
          : keys.sublist((index - window).clamp(0, index), index),
      after: index == null
          ? const []
          : keys.sublist(
              index + 1,
              (index + 1 + window).clamp(index + 1, keys.length),
            ),
      shuffle: queue.shuffleEnabled,
      loopMode: queue.loopMode,
      temporary: queue.temporary != null,
    );
  }

  final int total;
  final int? currentIndex;

  /// 依佇列在畫面上的順序（不是隨機的播放順序）。
  final List<String> before;
  final List<String> after;
  final bool shuffle;
  final LoopMode loopMode;

  /// 現在是臨時播放：[currentIndex] 是回到佇列時的那一首。
  final bool temporary;
}

/// 播放狀態的唯讀快照（ADR 0025 §決定 5、M3 design §12.3）：控制器既有的狀態與佇列，
/// 加上 session 的串流資訊與後端。不改 sealed [PlaybackState] 的形狀，也不放控制。
@immutable
final class PlaybackDiagnostics {
  const PlaybackDiagnostics({
    required this.backend,
    required this.state,
    required this.stateSince,
    required this.queue,
    this.trackKey,
    this.pluginId,
    this.stream,
    this.outputDevice,
    this.progress,
  });

  /// 後端名稱，例如 `just_audio`、`media_kit`。
  final String backend;
  final PlaybackState state;

  /// [state] 開始的時間。
  final DateTime stateSince;

  /// 正在播（或要播）的曲目鍵與它的插件 id；沒有曲目時為 `null`。
  final String? trackKey;
  final String? pluginId;
  final StreamDiagnostics? stream;

  /// 後端目前選的輸出裝置；後端不能選（Android）、或選的是系統預設時為 `null`。
  final OutputDevice? outputDevice;
  final PlaybackProgress? progress;
  final QueueDiagnostics queue;

  /// [Retrying] 倒數中的下次重試時間；其他狀態與等網路時為 `null`。
  DateTime? get nextRetryAt => switch (state) {
    Retrying(:final delay?) => stateSince.add(delay),
    _ => null,
  };

  static String stateName(PlaybackState state) => switch (state) {
    Idle() => 'idle',
    Loading() => 'loading',
    Playing() => 'playing',
    Paused() => 'paused',
    Buffering() => 'buffering',
    Retrying(waitingForNetwork: true) => 'waitingForNetwork',
    Retrying() => 'retrying',
    Failed() => 'failed',
  };

  /// 「複製快照」的內容：全部字串（含串流網址）都經 [redactor]。不含曲目標題、
  /// 標頭與引擎給的原始錯誤。
  Map<String, Object?> toJson(Redactor redactor) {
    String redact(String value) => redactor.redact(value);
    String? redactOptional(String? value) =>
        value == null ? null : redact(value);
    final state = this.state;
    final stream = this.stream;
    final progress = this.progress;
    return {
      'backend': redact(backend),
      'state': stateName(state),
      'stateSince': stateSince.toUtc().toIso8601String(),
      if (state case Retrying(:final attempt)) 'retryAttempt': attempt,
      if (nextRetryAt case final at?)
        'nextRetryAt': at.toUtc().toIso8601String(),
      if (state case Retrying(:final error) || Failed(:final error)) ...{
        'error': error.typeName,
        'errorPluginId': redactOptional(error.pluginId),
      },
      'pluginId': redactOptional(pluginId),
      'trackKey': redactOptional(trackKey),
      if (stream != null)
        'stream': {
          'url': redact('${stream.url}'),
          'sourceType': stream.sourceType,
          'candidate': stream.candidate,
          'candidateCount': stream.candidateCount,
          'container': redactOptional(stream.container),
          'codec': redactOptional(stream.codec),
          'bitrate': stream.bitrate,
        },
      'outputDevice': redactOptional(outputDevice?.name),
      if (progress != null)
        'position': {
          'positionMs': progress.position.inMilliseconds,
          'durationMs': progress.duration?.inMilliseconds,
        },
      'queue': {
        'total': queue.total,
        'currentIndex': queue.currentIndex,
        'before': [for (final key in queue.before) redact(key)],
        'after': [for (final key in queue.after) redact(key)],
        'shuffle': queue.shuffle,
        'loopMode': queue.loopMode.name,
        'temporary': queue.temporary,
      },
    };
  }
}
