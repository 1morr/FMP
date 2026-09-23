import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/lyrics_window_service.dart';
import 'package:fmp/services/lyrics/lyrics_window_style.dart';

import '../../support/dart_source.dart';

/// 歌詞子視窗讀的翻譯字串，每一個都要有人推過去。
///
/// `lyricsSettled`（「還在抓」與「這首沒有歌詞」的差別）怎麼送過去，是行為，
/// 在 `test/services/lyrics/lyrics_window_service_test.dart`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    final consumed = consumedStringKeys(
      File('lib/ui/windows/lyrics_window.dart').readAsStringSync(),
    );

    expect(consumed, isNotEmpty, reason: 'the key scan must find something');
    expect(
      consumed,
      equals(pushed),
      reason:
          'A key the window reads but nobody pushes falls back to the '
          'hardcoded simplified default; a key pushed but never read is dead.',
    );

    await service.destroy();
  });

  group('the consumed-key parser', () {
    test('reads every key in updateFrom, however it is written', () {
      const window = '''
class _LyricsWindowStrings {
  void updateFrom(Map<String, dynamic> map) {
    play = map['play'] as String? ?? play;
    displayPreferTranslated =
        map["displayPreferTranslated"] as String? ?? displayPreferTranslated;
    pause = map[ 'pause' ] as String? ?? pause;
  }
}
''';

      expect(consumedStringKeys(window), {
        'play',
        'displayPreferTranslated',
        'pause',
      });
    });

    test('lyric rows and comments outside updateFrom are not keys', () {
      const window = '''
class _LyricsWindowStrings {
  void updateFrom(Map<String, dynamic> map) {
    // next = map['next'] as String? ?? next; 已經拿掉。
    play = map['play'] as String? ?? play;
  }
}

LyricsLine _line(Map<String, dynamic> map) =>
    LyricsLine(text: map['text'] as String, subText: map['subText'] as String?);
''';

      expect(consumedStringKeys(window), {'play'});
    });
  });
}

/// 子視窗 `updateFrom` 從推過去的 map 讀的鍵。
///
/// 只看 `updateFrom` 本體 —— 歌詞行本身也從 map 讀 String，不是翻譯字串。
Set<String> consumedStringKeys(String windowSource) {
  final code = stripDartComments(windowSource);
  final header = RegExp(
    r'\bvoid\s+updateFrom\s*\([^)]*\)\s*\{',
  ).firstMatch(code);
  if (header == null) throw StateError('updateFrom not found');

  var depth = 1;
  var end = header.end;
  while (end < code.length && depth > 0) {
    if (code[end] == '{') depth++;
    if (code[end] == '}') depth--;
    end++;
  }

  return {
    for (final match in RegExp(
      r'''\bmap\s*\[\s*(['"])(\w+)\1\s*\]''',
    ).allMatches(code.substring(header.end, end)))
      match.group(2)!,
  };
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
