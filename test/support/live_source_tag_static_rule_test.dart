/// 會真的連網的測試必須標 `live`。
///
/// `ci.yml` 用 `--exclude-tags live` 把連網測試排除在 CI 之外，所以一支忘了標的
/// 連網測試不會在 CI 上被排除 —— 它會在一個不相干的 PR 上因為上游 API 變動而紅，
/// 或者在本機因為分流規則而永遠等下去。#56 就是這樣發生的：`setUp` 裡建了一個
/// 真的 `BilibiliSource()`，某條測試 `await` 了它的搜尋。人工修過一次，這裡是
/// 第一次有東西擋回歸。
///
/// 判準是「用預設建構子建出真的音源」：`BilibiliSource()`、`YouTubeSource()`、
/// `NeteaseSource()`、`BilibiliLiveClient()`、`RadioSource()` 沒有注入任何
/// Dio 或 client，就會拿到會連 Bilibili / YouTube / Netease 的實例。有注入的
/// （`BilibiliLiveClient(apiDio: Dio(), liveDio: fake)`）不算。
///
/// 例外清單裡的檔案建了真的音源但只呼叫純函式（URL 解析、建構子副作用），
/// 每一條都寫理由。加例外時先問：這支測試真的沒有 `await` 音源的任何方法嗎。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 預設建構子：類別名後面緊接空括號。
final _realSourcePattern = RegExp(
  r'\b(BilibiliSource|YouTubeSource|NeteaseSource|BilibiliLiveClient|RadioSource)\(\)',
);

final _liveTagPattern = RegExp(r"@Tags\(\[\s*'live'\s*\]\)|tags:\s*'live'");

/// 建了真的音源但只用純函式的測試，附理由。
const _exceptions = <String, String>{
  'test/data/sources/netease_source_test.dart':
      'only exercises parseId / isPlaylistUrl, which never touch the network',
  'test/services/audio/audio_service_dispose_test.dart':
      'NeteaseSource() is handed to a lyrics factory the test never invokes',
  'test/services/audio/audio_controller_handoff_and_errors_test.dart':
      'same lyrics factory shape: NeteaseSource() is constructed, never called',
  'test/services/audio/lyrics_auto_match_coordinator_test.dart':
      'same lyrics factory shape: NeteaseSource() is constructed, never called',
  'test/bilibili_source_test.dart':
      'the group setUp builds a real source; the two tests that reach the '
      'network carry tags: live individually and the rest exercise parsing '
      '(#56, c2a79fbb)',
};

void main() {
  group('live source tag', () {
    test('every test that builds a real source is tagged live or excepted', () {
      final offenders = <String>[];
      for (final path in _testFiles()) {
        if (path.startsWith('test/live/')) continue;
        if (_exceptions.containsKey(path)) continue;
        final source = File(path).readAsStringSync();
        if (!_buildsRealSource(source)) continue;
        if (_liveTagPattern.hasMatch(source)) continue;
        offenders.add(path);
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'These tests construct a real source with its default constructor '
            'and are not tagged live. Inject a fake Dio/client, move the test '
            'under test/live/, or tag it live.',
      );
    });

    test('every excepted file still exists and still builds a real source', () {
      for (final entry in _exceptions.entries) {
        final file = File(entry.key);
        expect(file.existsSync(), isTrue, reason: '${entry.key} is gone');
        expect(
          _buildsRealSource(file.readAsStringSync()),
          isTrue,
          reason: '${entry.key} no longer needs its exception',
        );
      }
    });

    test('the detector catches a synthetic offender', () {
      const offender = '''
void main() {
  test('search', () async {
    final source = BilibiliSource();
    await source.search('x');
  });
}
''';
      expect(_buildsRealSource(offender), isTrue);
      expect(_liveTagPattern.hasMatch(offender), isFalse);
    });

    test('the detector ignores injected clients and commented-out code', () {
      const injected = '''
final client = BilibiliLiveClient(apiDio: Dio(), liveDio: fake);
final source = BilibiliSource(liveClient: client);
// final real = BilibiliSource();
''';
      expect(_buildsRealSource(injected), isFalse);
    });

    test('the tag pattern accepts both file-level and test-level tags', () {
      expect(_liveTagPattern.hasMatch("@Tags(['live'])"), isTrue);
      expect(_liveTagPattern.hasMatch("}, tags: 'live');"), isTrue);
      expect(_liveTagPattern.hasMatch("tags: 'music'"), isFalse);
    });
  });
}

bool _buildsRealSource(String source) {
  final code = source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
  return _realSourcePattern.hasMatch(code);
}

Iterable<String> _testFiles() => Directory('test')
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => f.path.replaceAll(r'\', '/'))
    .where((p) => p.endsWith('_test.dart'))
    // 靜態規則測試會把違規樣本當字串寫在檔內，掃它們只會抓到自己的例子。
    .where((p) => !p.endsWith('_static_rule_test.dart'));
