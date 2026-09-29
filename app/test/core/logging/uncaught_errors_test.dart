import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/logging/uncaught_errors.dart';
import 'package:fmp/core/redaction/redactor.dart';

void main() {
  test('uncaught errors are written through the facade as errors', () {
    // 用真正的 PlatformDispatcher：flutter_test 的 TestPlatformDispatcher 的
    // onError setter 不會寫入（flutter_test window.dart 的 `set onError`）。
    final dispatcher = PlatformDispatcher.instance;
    final previousFlutterHandler = FlutterError.onError;
    final previousDispatcherHandler = dispatcher.onError;
    final log = Log(redactor: Redactor(), minimumLevel: LogLevel.info);

    final bool handled;
    try {
      routeUncaughtErrors(log, dispatcher);
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('SESSDATA=FAKE_SESSDATA_123'),
          stack: StackTrace.fromString('#0 build (a.dart:1)'),
          library: 'widgets library',
        ),
      );
      handled = dispatcher.onError!(
        Exception('async failure'),
        StackTrace.fromString('#0 later (b.dart:2)'),
      );
    } finally {
      FlutterError.onError = previousFlutterHandler;
      dispatcher.onError = previousDispatcherHandler;
    }

    expect(handled, isTrue);
    final [flutter, platform] = log.history;
    expect(flutter.level, LogLevel.error);
    expect(flutter.tag, 'flutter');
    expect(flutter.error, 'Bad state: SESSDATA=***');
    expect(flutter.stackTrace, '#0 build (a.dart:1)');
    expect(flutter.fields, {'library': 'widgets library'});
    expect(platform.level, LogLevel.error);
    expect(platform.tag, 'platform');
    expect(platform.error, 'Exception: async failure');
    expect(platform.stackTrace, '#0 later (b.dart:2)');
  });
}
