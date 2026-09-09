import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/lyrics_window_service.dart';
import 'package:fmp/services/lyrics/lyrics_window_style.dart';

/// P0-4：子視窗只看得到「沒有行」，分不出「還在抓」和「這首沒有歌詞」。
/// 這兩條守住那個差別是怎麼被送過去的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('syncLyrics tells the window whether the search has settled', () async {
    final payloads = <String, Map<String, dynamic>>{};
    final service = await _openService(payloads);

    await service.syncLyrics(
      lyrics: null,
      currentLineIndex: -1,
      positionMs: 0,
      offsetMs: 0,
      trackTitle: 'A track with no lyrics',
      trackArtist: 'Someone',
      trackUniqueKey: 'bilibili:BV1',
      lyricsSettled: true,
    );

    expect(payloads['updateLyrics']!['lyricsSettled'], isTrue);

    await service.syncLyrics(
      lyrics: null,
      currentLineIndex: -1,
      positionMs: 0,
      offsetMs: 0,
      trackTitle: 'Still looking',
      trackArtist: 'Someone',
      trackUniqueKey: 'bilibili:BV2',
      lyricsSettled: false,
    );

    expect(payloads['updateLyrics']!['lyricsSettled'], isFalse);

    await service.destroy();
  });

  test('every string the window reads is actually pushed to it', () async {
    // 子視窗是獨立的 runApp 進入點，拿不到主 isolate 的 slang 實例，所以它自帶
    // 一份簡體預設值當 fallback。漏推一個鍵不會壞掉 —— 使用者只會看到一句
    // 沒翻譯的簡體中文。這條測試就是那個漏推的守門。
    final payloads = <String, Map<String, dynamic>>{};
    final service = await _openService(payloads);

    await service.syncTheme(
      themeMode: ThemeMode.dark,
      primaryColor: null,
      fontFamily: null,
      lyricsWindowStyle: LyricsWindowStyle.defaults,
    );

    final pushed = (payloads['updateTheme']!['strings'] as Map).keys.toSet();

    final windowSource = File(
      'lib/ui/windows/lyrics_window.dart',
    ).readAsStringSync();
    // 只認 `_LyricsWindowStrings.updateFrom` 的那個形狀
    // （`field = map['key'] as String? ?? field;`）—— 歌詞行本身也從 map 讀
    // String，不是翻譯字串。
    final consumed = RegExp(
      r"(\w+) = map\['(\w+)'\] as String\? \?\? \1;",
    ).allMatches(windowSource).map((m) => m.group(2)!).toSet();

    expect(consumed, isNotEmpty, reason: 'the key scan must find something');
    expect(
      consumed.difference(pushed),
      isEmpty,
      reason: 'these keys fall back to the hardcoded simplified defaults',
    );

    await service.destroy();
  });
}

Future<LyricsWindowService> _openService(
  Map<String, Map<String, dynamic>> payloads,
) async {
  final windowsChanged = StreamController<void>.broadcast();
  addTearDown(windowsChanged.close);
  final created = <_FakeWindowController>[];

  final service = LyricsWindowService.forTesting(
    _FakePlatform(
      windowsChanged: windowsChanged.stream,
      getAllWindows: () async =>
          List<LyricsWindowControllerHandle>.from(created),
      createWindow: (configuration) async {
        final controller = _FakeWindowController(
          (created.length + 1).toString(),
        );
        created.add(controller);
        return controller;
      },
      invokeMethod: (method, arguments) async {
        if (arguments.isNotEmpty && arguments.startsWith('{')) {
          payloads[method] = jsonDecode(arguments) as Map<String, dynamic>;
        }
        return 'ok';
      },
      setMethodCallHandler: (_) async {},
    ),
  );

  await service.open();
  return service;
}

class _FakePlatform implements LyricsWindowPlatform {
  _FakePlatform({
    required Future<LyricsWindowControllerHandle> Function(
      WindowConfiguration configuration,
    )
    createWindow,
    required Future<List<LyricsWindowControllerHandle>> Function()
    getAllWindows,
    required this.windowsChanged,
    required Future<dynamic> Function(String method, String arguments)
    invokeMethod,
    required Future<void> Function(
      Future<dynamic> Function(MethodCall call)? handler,
    )
    setMethodCallHandler,
  }) : _createWindow = createWindow,
       _getAllWindows = getAllWindows,
       _invokeMethod = invokeMethod,
       _setMethodCallHandler = setMethodCallHandler;

  @override
  bool get isWindows => true;

  final Future<LyricsWindowControllerHandle> Function(
    WindowConfiguration configuration,
  )
  _createWindow;
  final Future<List<LyricsWindowControllerHandle>> Function() _getAllWindows;
  final Future<dynamic> Function(String method, String arguments) _invokeMethod;
  final Future<void> Function(
    Future<dynamic> Function(MethodCall call)? handler,
  )
  _setMethodCallHandler;

  @override
  final Stream<void> windowsChanged;

  @override
  Future<LyricsWindowControllerHandle> createWindow(
    WindowConfiguration configuration,
  ) => _createWindow(configuration);

  @override
  Future<List<LyricsWindowControllerHandle>> getAllWindows() =>
      _getAllWindows();

  @override
  Future<dynamic> invokeMethod(String method, String arguments) =>
      _invokeMethod(method, arguments);

  @override
  Future<void> setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) => _setMethodCallHandler(handler);
}

class _FakeWindowController implements LyricsWindowControllerHandle {
  _FakeWindowController(this.windowId);

  @override
  final String windowId;

  @override
  Future<void> show() async {}

  @override
  Future<void> hide() async {}
}
