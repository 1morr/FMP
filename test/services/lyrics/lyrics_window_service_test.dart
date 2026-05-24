import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/lyrics_window_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent open calls create at most one lyrics child window',
      () async {
    final windowsChanged = StreamController<void>.broadcast();
    final createdWindows = <_FakeWindowController>[];
    Future<dynamic> Function(MethodCall call)? handler;

    final service = LyricsWindowService.forTesting(
      _FakeLyricsWindowPlatform(
        windowsChanged: windowsChanged.stream,
        getAllWindows: () async => List<LyricsWindowControllerHandle>.from(
          createdWindows,
        ),
        createWindow: (WindowConfiguration configuration) async {
          expect(configuration.arguments, contains('lyrics'));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          final controller =
              _FakeWindowController((createdWindows.length + 1).toString());
          createdWindows.add(controller);
          return controller;
        },
        invokeMethod: (method, arguments) async => 'ok',
        setMethodCallHandler: (newHandler) async {
          handler = newHandler;
        },
      ),
    );

    await Future.wait([service.open(), service.open()]);

    expect(createdWindows, hasLength(1));
    expect(service.isOpen, isTrue);
    expect(handler, isNotNull);

    await service.destroy();
    await windowsChanged.close();
  });

  test('open during opening restores a hidden lyrics child window', () async {
    final windowsChanged = StreamController<void>.broadcast();
    final createdWindows = <_FakeWindowController>[];
    final createCompleter = Completer<void>();
    final pingCompleter = Completer<void>();

    final service = LyricsWindowService.forTesting(
      _FakeLyricsWindowPlatform(
        windowsChanged: windowsChanged.stream,
        getAllWindows: () async => List<LyricsWindowControllerHandle>.from(
          createdWindows,
        ),
        createWindow: (WindowConfiguration configuration) async {
          final controller =
              _FakeWindowController((createdWindows.length + 1).toString());
          createdWindows.add(controller);
          createCompleter.complete();
          return controller;
        },
        invokeMethod: (method, arguments) async {
          if (method == 'ping') await pingCompleter.future;
          return 'ok';
        },
        setMethodCallHandler: (_) async {},
      ),
    );

    final opening = service.open();
    await createCompleter.future;
    await _waitUntil(() async => service.isOpen);
    await service.close();
    final reopen = service.open();

    pingCompleter.complete();
    await Future.wait([opening, reopen]);

    expect(createdWindows, hasLength(1));
    expect(createdWindows.single.hideCount, 1);
    expect(createdWindows.single.showCount, 1);
    expect(service.isOpen, isTrue);

    await service.destroy();
    await windowsChanged.close();
  });
}

class _FakeLyricsWindowPlatform implements LyricsWindowPlatform {
  _FakeLyricsWindowPlatform({
    required Future<LyricsWindowControllerHandle> Function(
      WindowConfiguration configuration,
    ) createWindow,
    required Future<List<LyricsWindowControllerHandle>> Function()
        getAllWindows,
    required this.windowsChanged,
    required Future<dynamic> Function(String method, String arguments)
        invokeMethod,
    required Future<void> Function(
      Future<dynamic> Function(MethodCall call)? handler,
    ) setMethodCallHandler,
  })  : _createWindow = createWindow,
        _getAllWindows = getAllWindows,
        _invokeMethod = invokeMethod,
        _setMethodCallHandler = setMethodCallHandler;

  @override
  bool get isWindows => true;

  final Future<LyricsWindowControllerHandle> Function(
    WindowConfiguration configuration,
  ) _createWindow;

  final Future<List<LyricsWindowControllerHandle>> Function() _getAllWindows;

  @override
  final Stream<void> windowsChanged;

  final Future<dynamic> Function(String method, String arguments) _invokeMethod;

  final Future<void> Function(
    Future<dynamic> Function(MethodCall call)? handler,
  ) _setMethodCallHandler;

  @override
  Future<LyricsWindowControllerHandle> createWindow(
    WindowConfiguration configuration,
  ) {
    return _createWindow(configuration);
  }

  @override
  Future<List<LyricsWindowControllerHandle>> getAllWindows() {
    return _getAllWindows();
  }

  @override
  Future<dynamic> invokeMethod(String method, String arguments) {
    return _invokeMethod(method, arguments);
  }

  @override
  Future<void> setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) {
    return _setMethodCallHandler(handler);
  }
}

class _FakeWindowController implements LyricsWindowControllerHandle {
  _FakeWindowController(this.windowId);

  @override
  final String windowId;

  var showCount = 0;
  var hideCount = 0;

  @override
  Future<void> show() async {
    showCount++;
  }

  @override
  Future<void> hide() async {
    hideCount++;
  }
}

Future<void> _waitUntil(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not met before timeout');
}
