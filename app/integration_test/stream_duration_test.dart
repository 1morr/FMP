import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/platform/audio_backend.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/backends/hls/hls_packager.dart' show FetchRange;
import 'package:integration_test/integration_test.dart';

import '../test/support/fragmented_mp4.dart';
import '../test/support/local_audio_server.dart';
import '../test/support/no_network.dart';

/// 這個平台的音訊後端回報的長度與 seek（票 06b）。零聯網：音訊由本機的
/// [LocalAudioServer] 提供。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();

  late Log log;
  late AudioBackend backend;
  final servers = <LocalAudioServer>[];

  Future<void> setUpBackend({FetchRange? fetchRange}) async {
    final dir = Directory.systemTemp.createTempSync('fmp_it_duration_');
    log = await Log.open(dir, minimumLevel: LogLevel.debug);
    backend = createAudioBackend(log, fetchRange: fetchRange);
  }

  tearDown(() async {
    await backend.dispose();
    for (final s in servers) {
      await s.close();
    }
    servers.clear();
    await log.close();
  });

  Future<void> until(
    bool Function(AudioBackendState) done, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (done(backend.state)) return;
    try {
      await backend.states.firstWhere(done).timeout(timeout);
    } on TimeoutException {
      fail('timed out after $timeout at ${backend.state}');
    }
  }

  bool playingPast(AudioBackendState s, Duration position) =>
      s.status == AudioBackendStatus.ready && s.position > position;

  testWidgets('loading the next stream never reports the previous length', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await setUpBackend();
      final short = await LocalAudioServer.start(
        length: const Duration(seconds: 20),
      );
      final long = await LocalAudioServer.start(
        length: const Duration(seconds: 45),
      );
      servers.addAll([short, long]);

      await backend.load(AudioStream(url: short.url()));
      await backend.play();
      await until((s) => playingPast(s, const Duration(milliseconds: 500)));
      final seen = <AudioBackendState>[];
      final subscription = backend.states.listen(seen.add);
      final loading = backend.load(AudioStream(url: long.url()));
      seen.add(backend.state);
      await loading;
      await backend.play();
      await until((s) => playingPast(s, const Duration(milliseconds: 500)));
      await subscription.cancel();

      expect(
        seen.where((s) => s.duration?.inSeconds == 20),
        isEmpty,
        reason: seen.join('\n'),
      );
      expect(backend.state.duration?.inSeconds, 45);
    });
  });

  testWidgets('a CDN that drops long responses midway cuts neither the length '
      'nor playback', (tester) async {
    await tester.runAsync(() async {
      // 1 小時、約 8 MB 的單檔 fragmented MP4，像 B 站的音訊軌。CDN 每個回應
      // 傳 256 KB 就斷線：AVPlayer 直接播會把長度截在幾分鐘、播到那裡就結束
      // （事實 M14），走 HLS 包裝就不會（ADR 0040）。
      final file = FragmentedMp4(fragments: 720);
      final cdn = await LocalAudioServer.start(
        body: file.bytes,
        contentType: ContentType('video', 'mp4'),
        name: 'audio.m4s',
        requiredHeaders: {'Referer': 'https://www.example.com'},
        cutAfterBytes: 256 * 1024,
      );
      servers.add(cdn);
      // 索引的那一小段由測試直接給（Dart 的連線在測試裡被擋）；片段照樣由
      // 原生播放器向假 CDN 要。
      await setUpBackend(
        fetchRange: (url, headers, range) async =>
            Uint8List.sublistView(file.bytes, range.first, range.last + 1),
      );

      await backend.load(
        AudioStream(
          url: cdn.url(),
          headers: const {'Referer': 'https://www.example.com'},
          segmentBase: file.segmentBase,
        ),
      );
      // 載入完就知道長度。
      expect(
        (backend.state.duration! - file.duration).abs(),
        lessThan(const Duration(seconds: 2)),
        reason: '${backend.state}',
      );
      await backend.play();
      await until((s) => playingPast(s, const Duration(milliseconds: 500)));

      const target = Duration(minutes: 50);
      await backend.seek(target);
      await until(
        (s) => playingPast(s, target + const Duration(seconds: 2)),
        timeout: const Duration(seconds: 30),
      );
      expect(backend.state.status, isNot(AudioBackendStatus.completed));
    });
  });
}
