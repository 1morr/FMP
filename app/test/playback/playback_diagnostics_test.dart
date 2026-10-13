import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/playback/playback_diagnostics.dart';
import 'package:fmp/playback/playback_state.dart';

// 播放狀態快照（M3 PR 14a，ADR 0025 §決定 5）。取欄位的案例在
// `playback_controller_test.dart` 的 `diagnostics` 群組（要真的控制器與 session）。

PlaybackDiagnostics snapshot({
  PlaybackState state = const Playing(),
  DateTime? since,
  StreamDiagnostics? stream,
  OutputDevice? outputDevice,
  String backend = 'media_kit',
}) => PlaybackDiagnostics(
  backend: backend,
  state: state,
  stateSince: since ?? DateTime.utc(2026, 10, 14, 12),
  trackKey: 'fmp-test:a',
  pluginId: 'fmp-test',
  stream: stream,
  outputDevice: outputDevice,
  progress: const PlaybackProgress(
    position: Duration(seconds: 5),
    duration: Duration(minutes: 3),
  ),
  queue: const QueueDiagnostics(
    total: 1,
    currentIndex: 0,
    before: [],
    after: [],
    shuffle: false,
    loopMode: LoopMode.off,
    temporary: false,
  ),
);

void main() {
  group('toJson', () {
    test('masks the signed parts of the stream URL and plain tokens', () {
      final json = jsonEncode(
        snapshot(
          stream: StreamDiagnostics(
            url: Uri.parse(
              'https://upos-sz-mirror.bilivideo.com/x/a.m4s'
              '?upsig=FAKE_UPSIG_VALUE&token=FAKE_TOKEN_VALUE&deadline=1790000000',
            ),
            candidate: 0,
            candidateCount: 2,
            container: 'mp4',
            codec: 'aac',
            bitrate: 64000,
          ),
        ).toJson(Redactor()),
      );

      expect(json, isNot(contains('FAKE_UPSIG_VALUE')));
      expect(json, isNot(contains('FAKE_TOKEN_VALUE')));
      // 沒有簽名的部分照留，快照才有用。
      expect(json, contains('upos-sz-mirror.bilivideo.com'));
      expect(json, contains('"container":"mp4"'));
    });

    test('masks a registered secret anywhere in a string field', () {
      final redactor = Redactor()..registerSecret('FAKE_SECRET_VALUE');
      final json = jsonEncode(
        snapshot(
          outputDevice: const OutputDevice(
            id: 'wasapi/x',
            name: 'Speakers FAKE_SECRET_VALUE',
          ),
          backend: 'media_kit FAKE_SECRET_VALUE',
        ).toJson(redactor),
      );

      expect(json, isNot(contains('FAKE_SECRET_VALUE')));
      expect(json, contains(redactedValue));
    });

    test('has the error type but not the underlying error', () {
      final error = UnexpectedError(
        pluginId: 'fmp-test',
        cause: StateError('FAKE_SECRET_VALUE'),
        stackTrace: StackTrace.current,
      );
      final json = jsonEncode(
        snapshot(state: Failed(error)).toJson(Redactor()),
      );

      expect(json, contains('UnexpectedError'));
      expect(json, isNot(contains('FAKE_SECRET_VALUE')));
    });

    test('reports the next retry time, but not while waiting for network', () {
      final since = DateTime.utc(2026, 10, 14, 12);
      final error = NetworkError(pluginId: 'fmp-test');
      final counting = snapshot(
        state: Retrying(
          error: error,
          attempt: 2,
          delay: const Duration(seconds: 3),
        ),
        since: since,
      );
      expect(counting.nextRetryAt, DateTime.utc(2026, 10, 14, 12, 0, 3));
      expect(
        counting.toJson(Redactor())['nextRetryAt'],
        '2026-10-14T12:00:03.000Z',
      );

      final waiting = snapshot(
        state: Retrying(error: error, attempt: 0, delay: null),
      );
      expect(waiting.nextRetryAt, isNull);
      expect(waiting.toJson(Redactor()).containsKey('nextRetryAt'), isFalse);
      expect(waiting.toJson(Redactor())['state'], 'waitingForNetwork');
    });
  });

  test('an asset URL is reported as an asset source', () {
    final stream = StreamDiagnostics(
      url: Uri.parse('asset:///assets/test.m4a'),
      candidate: 0,
      candidateCount: 1,
    );
    expect(stream.sourceType, 'asset');
  });
}
