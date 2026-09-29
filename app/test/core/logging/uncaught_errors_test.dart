import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
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

  test(
    'an uncaught AppError goes through report with its cause, as an error',
    () {
      final dispatcher = PlatformDispatcher.instance;
      final previousFlutterHandler = FlutterError.onError;
      final previousDispatcherHandler = dispatcher.onError;
      final log = Log(redactor: Redactor(), minimumLevel: LogLevel.info);

      try {
        routeUncaughtErrors(log, dispatcher);
        FlutterError.onError!(
          FlutterErrorDetails(
            exception: NetworkError(
              pluginId: 'bilibili',
              networkRecordId: 3,
              cause: StateError('SESSDATA=FAKE_SESSDATA_123'),
              stackTrace: StackTrace.fromString('#0 send (c.dart:3)'),
            ),
          ),
        );
        dispatcher.onError!(
          NotFound(
            cause: StateError('access_key=FAKE_ACCESS_KEY_123'),
            stackTrace: StackTrace.fromString('#0 later (d.dart:4)'),
          ),
          StackTrace.fromString('#0 zone (e.dart:5)'),
        );
      } finally {
        FlutterError.onError = previousFlutterHandler;
        dispatcher.onError = previousDispatcherHandler;
      }

      final [flutter, platform] = log.history;
      // 沒人接的錯誤一律是 error：兩個都是預期內的（處理過時 report 寫
      // warning），未捕捉就代表沒處理。
      expect(flutter.level, LogLevel.error);
      expect(flutter.tag, 'flutter');
      expect(flutter.message, 'Uncaught Flutter error');
      expect(flutter.error, 'Bad state: SESSDATA=***');
      expect(flutter.stackTrace, '#0 send (c.dart:3)');
      expect(flutter.fields, containsPair('type', 'NetworkError'));
      expect(flutter.fields, containsPair('networkRecordId', 3));
      expect(platform.level, LogLevel.error);
      expect(platform.tag, 'platform');
      expect(platform.error, 'Bad state: access_key=***');
      // stackTrace 用 AppError 自己的，不是 zone 回報的那一個。
      expect(platform.stackTrace, '#0 later (d.dart:4)');
      expect(platform.fields, containsPair('type', 'NotFound'));
    },
  );
}
