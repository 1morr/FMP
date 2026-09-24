/// 會真的連網的測試必須標 `live`。
///
/// `ci.yml` 用 `--exclude-tags live` 把連網測試排除在 CI 之外，所以一支忘了標的
/// 連網測試不會在 CI 上被排除 —— 它會在一個不相干的 PR 上因為上游 API 變動而紅，
/// 或者在本機因為分流規則而永遠等下去。#56 就是這樣發生的：`setUp` 裡建了一個
/// 真的 `BilibiliSource()`，某條測試 `await` 了它的搜尋。人工修過一次，這裡是
/// 第一次有東西擋回歸。
///
/// 判準是「用預設建構子建出真的音源」：沒有注入任何 Dio 或 client 的建構子，就會
/// 拿到會連 Bilibili / YouTube / Netease / QQ 音樂 / lrclib / Spotify 的實例。有注入的
/// （`BilibiliLiveClient(apiDio: Dio(), liveDio: fake)`）不算。涵蓋哪些類別見
/// [_guardedClasses]。
///
/// 例外清單裡的檔案建了真的音源但只呼叫純函式（URL 解析、建構子副作用），
/// 每一條都寫理由。加例外時先問：這支測試真的沒有 `await` 音源的任何方法嗎。
///
/// 例外清單的說法是「沒被呼叫」，那是個關於行為的斷言，不是關於程式碼形狀的，
/// 所以量過：2026-09-23 在 `HttpClientFactory.create` 加一個印出並拒絕每個請求的
/// interceptor，只跑例外清單裡的檔案（`--exclude-tags live`），攔到的請求全部打向
/// `localhost` 的假伺服器，沒有一個打到真實主機。加例外之後照這個方法再量一次。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_source.dart';

/// 判準涵蓋的音源類別，也是 [_realSourcePattern] 唯一的真相來源。
///
/// 這裡曾經是寫死在正則裡的字串，於是漂移了：樹裡有九個預設建構子會連網的音源
/// 類別，判準只有五個，歌詞與歌單匯入的四個用預設建構子建出實例卻不被看見。
/// 例外清單剛好蓋住那四個檔案，所以漂移沒有任何症狀 —— 一條瞎掉的規則不會紅。
///
/// 新增音源時加在這裡；`the detector catches a synthetic offender for every`
/// `guarded class` 會逐一驗證每個名字真的被認出來。
const _guardedClasses = <String>[
  'BilibiliSource',
  'YouTubeSource',
  'NeteaseSource',
  'BilibiliLiveClient',
  'RadioSource',
  'QQMusicSource',
  'LrclibSource',
  'QQMusicPlaylistSource',
  'SpotifyPlaylistSource',
];

/// 預設建構子：類別名後面緊接空括號。
final _realSourcePattern = RegExp(
  r'\b(' + _guardedClasses.join('|') + r')\(\)',
);

final _liveTagPattern = RegExp(r"@Tags\(\[\s*'live'\s*\]\)|tags:\s*'live'");

/// 建了真的音源但只用純函式的測試，附理由。
const _exceptions = <String, String>{
  'test/data/sources/source_url_policy_test.dart':
      'only calls canHandle on the playlist import sources, which parses the '
      'URL and never touches the Dio',
  'test/data/sources/netease_source_test.dart':
      'only exercises parseId / isPlaylistUrl, which never touch the network',
  'test/services/audio/audio_service_dispose_test.dart':
      'NeteaseSource(), LrclibSource() and QQMusicSource() are handed to a '
      'lyrics factory the test never invokes',
  'test/services/audio/audio_controller_handoff_and_errors_test.dart':
      'same lyrics factory shape: NeteaseSource(), LrclibSource() and '
      'QQMusicSource() are constructed, never called',
  'test/services/audio/lyrics_auto_match_coordinator_test.dart':
      'same lyrics factory shape: NeteaseSource(), LrclibSource() and '
      'QQMusicSource() are constructed, never called',
  'test/services/audio/audio_controller_lyrics_auto_match_track_test.dart':
      'same lyrics factory shape: the subclass overrides tryAutoMatch, so '
      'NeteaseSource(), LrclibSource() and QQMusicSource() are constructed '
      'and never called',
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
        // 已經有 live 標籤的檔案本來就會過，例外只會讓它的理由變成沒人驗的敘述。
        expect(
          _liveTagPattern.hasMatch(stripDartComments(file.readAsStringSync())),
          isFalse,
          reason: '${entry.key} is tagged live already; drop the exception',
        );
      }
    });

    test(
      'the detector catches a synthetic offender for every guarded class',
      () {
        // 逐一走過判準裡的每個類別名。少一個名字在這裡就會紅 —— 這正是這條測試
        // 存在的理由：上一次漏掉兩個的時候，沒有任何東西會發現。
        for (final name in _guardedClasses) {
          final offender =
              '''
void main() {
  test('lyrics', () async {
    final source = $name();
    await source.search('x');
  });
}
''';
          expect(_buildsRealSource(offender), isTrue, reason: name);
          expect(_liveTagPattern.hasMatch(offender), isFalse, reason: name);
        }
      },
    );

    test('the detector ignores injected clients and commented-out code', () {
      const injected = '''
final client = BilibiliLiveClient(apiDio: Dio(), liveDio: fake);
final source = BilibiliSource(liveClient: client);
// final real = BilibiliSource();
''';
      expect(_buildsRealSource(injected), isFalse);
    });

    test('the detector ignores an injected Dio for the lyric sources', () {
      // 反方向：判準認的是「類別名後面緊接空括號」，不是類別名本身。
      // `QQMusicSource(dio: dio)` 在測試裡是常態寫法，不能被判成連網。
      const injected = '''
final lrclib = LrclibSource(dio: dio);
final qqmusic = QQMusicSource(dio: dio);
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

bool _buildsRealSource(String source) =>
    _realSourcePattern.hasMatch(stripDartComments(source));

Iterable<String> _testFiles() => Directory('test')
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => f.path.replaceAll(r'\', '/'))
    .where((p) => p.endsWith('_test.dart'))
    // 靜態規則測試會把違規樣本當字串寫在檔內，掃它們只會抓到自己的例子。
    .where((p) => !p.endsWith('_static_rule_test.dart'));
