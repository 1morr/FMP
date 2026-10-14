import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/playback_diagnostics.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/ui/debug/debug_log_state.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// Debug 頁的「播放狀態」（ADR 0025 §決定 5）：唯讀，不放任何播放控制（控制只經
/// `PlaybackController`）。內容來自 [playbackDiagnosticsProvider]；位置隨進度 stream 每秒
/// 更新，這個 widget 不開計時器。
class DebugPlayback extends ConsumerWidget {
  const DebugPlayback({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).debug;
    final diagnostics = ref.watch(playbackDiagnosticsProvider);
    // 畫面上的字串與「複製快照」一樣經遮蔽函式（曲目鍵、容器與編碼是插件給的）。
    final redact = ref.watch(redactorProvider).redact;
    final spacing = AppTokens.of(context).spacing;
    final theme = Theme.of(context);
    if (diagnostics.state is Idle &&
        diagnostics.trackKey == null &&
        diagnostics.queue.total == 0) {
      return EmptyState(
        icon: Icons.graphic_eq,
        title: t.pbEmpty,
        body: t.pbEmptyHint,
      );
    }
    final queue = diagnostics.queue;
    final stream = diagnostics.stream;
    final progress = diagnostics.progress;
    final state = diagnostics.state;
    Widget fact(String label, String value) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(value),
    );
    String keys(List<String> keys) =>
        keys.isEmpty ? t.pbNone : keys.map(redact).join('\n');
    return ListView(
      padding: EdgeInsets.all(spacing.x4),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(t.pbCopy),
            onPressed: () => unawaited(_copy(ref, diagnostics)),
          ),
        ),
        SizedBox(height: spacing.x2),
        fact(t.pbState, _stateText(t, state)),
        if (state case Retrying(:final attempt, delay: != null))
          fact(t.pbRetryAttempt, '$attempt'),
        if (diagnostics.nextRetryAt case final at?)
          fact(t.pbNextRetry, formatLogTime(at)),
        if (state case Retrying(:final error) || Failed(:final error))
          fact(t.pbError, error.typeName),
        // 收聽直播時 `trackKey` 是直播間（`插件:房間`）。
        if (queue.live) Text(t.pbLive, style: theme.textTheme.titleSmall),
        fact(
          queue.live ? t.pbLiveRoom : t.pbTrack,
          _or(diagnostics.trackKey, redact, t.pbUnknown),
        ),
        fact(t.pbPlugin, _or(diagnostics.pluginId, redact, t.pbUnknown)),
        fact(t.pbBackend, diagnostics.backend),
        fact(
          t.pbOutputDevice,
          _or(diagnostics.outputDevice?.name, redact, t.pbOutputDefault),
        ),
        fact(
          t.pbStream,
          stream == null ? t.pbUnknown : _streamText(t, stream, redact),
        ),
        fact(
          t.pbPosition,
          progress == null
              ? t.pbUnknown
              : '${formatDuration(progress.position)} / '
                    '${progress.duration == null ? t.pbUnknown : formatDuration(progress.duration!)}',
        ),
        const Divider(),
        Text(t.pbQueue, style: theme.textTheme.titleMedium),
        if (queue.total == 0)
          Text(t.pbQueueEmpty)
        else ...[
          fact(
            t.pbQueue,
            queue.currentIndex == null
                ? '${queue.total}'
                : t.pbQueueSummary(
                    total: queue.total,
                    index: queue.currentIndex! + 1,
                  ),
          ),
          fact(t.pbBefore, keys(queue.before)),
          fact(t.pbAfter, keys(queue.after)),
          fact(t.pbShuffle, queue.shuffle ? t.yes : t.no),
          fact(t.pbLoop, _loopText(t, queue.loopMode)),
          if (queue.temporary) Text(t.pbTemporary),
          if (queue.mix case final mix?)
            fact(t.pbMix, redact('${mix.pluginId}:${mix.mixId}')),
        ],
      ],
    );
  }

  Future<void> _copy(WidgetRef ref, PlaybackDiagnostics diagnostics) async {
    final t = ref.read(translationsProvider).debug;
    final toaster = ref.read(toasterProvider);
    final json = diagnostics.toJson(ref.read(redactorProvider));
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(json)),
    );
    toaster.info(t.pbCopied);
  }
}

String _stateText(Translations$debug$zh_TW t, PlaybackState state) =>
    switch (state) {
      Idle() => t.pbStateIdle,
      Loading() => t.pbStateLoading,
      Playing() => t.pbStatePlaying,
      Paused() => t.pbStatePaused,
      Buffering() => t.pbStateBuffering,
      Retrying(waitingForNetwork: true) => t.pbStateWaitingNetwork,
      Retrying() => t.pbStateRetrying,
      Failed() => t.pbStateFailed,
    };

String _loopText(Translations$debug$zh_TW t, LoopMode mode) => switch (mode) {
  LoopMode.off => t.pbLoopOff,
  LoopMode.all => t.pbLoopAll,
  LoopMode.one => t.pbLoopOne,
};

/// 容器 · 編碼 · 位元率 · 來源類型 · 第幾個候選。網址不顯示（簽名網址很長，而且是複製
/// 快照時才經遮蔽輸出的東西）。
String _streamText(
  Translations$debug$zh_TW t,
  StreamDiagnostics stream,
  String Function(String) redact,
) => [
  _or(stream.container, redact, t.pbUnknown),
  _or(stream.codec, redact, t.pbUnknown),
  if (stream.bitrate case final bitrate?) '$bitrate bps' else t.pbUnknown,
  stream.sourceType == 'asset' ? t.pbSourceAsset : t.pbSourceNetwork,
  t.pbCandidate(index: stream.candidate + 1, count: stream.candidateCount),
].join(' · ');

/// [value] 經 [redact]；沒有值時是 [fallback]（介面字串，不遮）。
String _or(String? value, String Function(String) redact, String fallback) =>
    value == null ? fallback : redact(value);
