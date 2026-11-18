import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/uncaught_errors.dart';
import 'package:fmp/core/log/log.dart';

/// 沒有人接住的錯誤寫進 log（brief〈錯誤、log 與診斷〉）：框架回報的
/// （`FlutterError.onError`）與非同步的（`PlatformDispatcher.onError`）。
void main() {
  late Directory logDir;
  late Log log;
  late FlutterExceptionHandler? flutterBefore;
  late ErrorCallback? platformBefore;

  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_uncaught_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    flutterBefore = FlutterError.onError;
    platformBefore = PlatformDispatcher.instance.onError;
  });
  tearDown(() {
    FlutterError.onError = flutterBefore;
    PlatformDispatcher.instance.onError = platformBefore;
    logDir.deleteSync(recursive: true);
  });

  Future<String> closeAndReadLog() async {
    await log.close();
    return File('${logDir.path}/${Log.fileName}').readAsStringSync();
  }

  test('an error the framework reports is logged, and still reaches the '
      'previous handler', () async {
    final previous = <FlutterErrorDetails>[];
    FlutterError.onError = previous.add;
    logUncaughtErrors(log);

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('build broke'),
        stack: StackTrace.current,
        library: 'widgets library',
      ),
    );

    expect(previous, hasLength(1));
    final text = await closeAndReadLog();
    expect(text, contains('ERROR Uncaught error (widgets library)'));
    expect(text, contains('Bad state: build broke'));
    expect(text, contains('uncaught_errors_test.dart'));
  });

  test('an uncaught asynchronous error is logged and marked handled', () async {
    logUncaughtErrors(log);

    final handled = PlatformDispatcher.instance.onError!(
      StateError('async broke'),
      StackTrace.current,
    );

    expect(handled, isTrue);
    final text = await closeAndReadLog();
    expect(text, contains('ERROR Uncaught asynchronous error'));
    expect(text, contains('Bad state: async broke'));
  });
}
