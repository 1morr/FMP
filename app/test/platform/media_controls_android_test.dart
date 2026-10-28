import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/media_controls/media_controls_android.dart';

import '../support/pump_until.dart';

NowPlaying nowPlaying({
  MediaPhase phase = MediaPhase.ready,
  bool playing = true,
  List<MediaControl> controls = const [
    MediaControl.previous,
    MediaControl.pause,
    MediaControl.next,
  ],
}) => NowPlaying(
  id: 'fmp-test:a',
  title: 'Song a',
  phase: phase,
  playing: playing,
  position: const Duration(seconds: 12),
  controls: controls,
);

void main() {
  group('the media key fix', () {
    const channel = MethodChannel('fmp/media_keys');
    late Log log;
    late List<String> calls;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
      calls = [];
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void mock(Future<Object?> Function() reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            calls.add(call.method);
            return reply();
          });
    }

    test('install reports what the native side answered', () async {
      mock(() async => true);
      expect(await MediaKeyFix(log).install(), isTrue);
      expect(calls, ['install']);

      mock(() async => false);
      expect(await MediaKeyFix(log).install(), isFalse);
    });

    test('a missing channel or a platform error is swallowed', () async {
      // 沒有登記處理者：MissingPluginException。
      expect(await MediaKeyFix(log).install(), isFalse);

      mock(() async => throw PlatformException(code: 'boom'));
      expect(await MediaKeyFix(log).install(), isFalse);
      expect(log.history.where((r) => r.level == LogLevel.error), isEmpty);
    });

    test('publish installs on a non-idle state and not on idle', () async {
      mock(() async => true);
      final controls = AndroidSystemMediaControls.forTest(
        log,
        MediaKeyFix(log),
      );

      await controls.publish(nowPlaying(phase: MediaPhase.idle));
      await settle();
      expect(calls, isEmpty);

      await controls.publish(nowPlaying());
      await controls.publish(nowPlaying(playing: false));
      await settle();
      expect(calls, ['install', 'install']);
    });

    test('a failing install does not break publish', () async {
      mock(() async => throw PlatformException(code: 'boom'));
      final controls = AndroidSystemMediaControls.forTest(
        log,
        MediaKeyFix(log),
      );

      await expectLater(controls.publish(nowPlaying()), completes);
      await settle();
    });
  });
}
