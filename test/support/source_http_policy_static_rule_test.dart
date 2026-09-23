/// 每個對音源 API 說話的客戶端都要走 `SourceHttpPolicy`。
///
/// 三份按目錄切的前身（`test/data/sources/`、`test/services/account/`、
/// `test/services/radio/`）各自維護一張路徑表，新的客戶端擺在第四個目錄就三份
/// 都掃不到。這裡改成掃全 `lib/`，規則從路徑本身推導出期望值，不再靠人維護清單。
///
/// 為什麼要有這條：UA、Referer、Origin 與 cookie 的搭配是每個音源各自風控的
/// 條件。自己 `Dio(...)` 一個客戶端出來不會編譯錯誤，也不會在本機失敗 —— 只會
/// 在真的有風控的那一端變成 412 或空結果。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_source.dart';

/// 從路徑推出這個檔案服務哪個音源。
const _sourceOfPathToken = <String, String>{
  'bilibili': 'SourceIds.bilibili',
  'youtube': 'SourceIds.youtube',
  'netease': 'SourceIds.netease',
};

/// 直接生出 HTTP 客戶端 —— 繞過 policy 的唯一方式。
final _rawClientPattern = RegExp(
  r'(?<![A-Za-z0-9_])Dio\s*\(|HttpClientFactory\.create\s*\(',
);

/// policy 自己與它包住的工廠。規則對它們沒有意義。
const _clientFactoryFiles = <String>{
  'lib/data/sources/source_http_policy.dart',
  'lib/core/utils/http_client_factory.dart',
};

/// 這個檔案自己生客戶端、又指名了某個音源，卻沒有經過 policy。
bool buildsARawSourceClient(String path, String source) {
  if (_clientFactoryFiles.contains(path)) return false;
  final code = stripDartComments(source);
  if (!_rawClientPattern.hasMatch(code)) return false;
  if (!RegExp(r'SourceIds\.[a-z]').hasMatch(code)) return false;
  return !code.contains('SourceHttpPolicy.');
}

final _policyApiClientPattern = RegExp(
  r'SourceHttpPolicy\s*\.\s*createApiDio\s*\(',
);

/// 向 policy 要 API 客戶端的檔案，哪裡沒講清楚它替哪個音源說話；不要客戶端
/// 的檔案回 null。
///
/// 沒指名音源，policy 就挑不出 UA 與 Referer；路徑裡有 `netease` 卻只指名
/// bilibili，是複製貼上最常留下的錯。
List<String>? policyClientProblems(String path, String source) {
  final code = stripDartComments(source);
  if (!_policyApiClientPattern.hasMatch(code)) return null;
  return [
    if (!code.contains('SourceIds.')) '$path names no source',
    for (final MapEntry(key: token, value: sourceId)
        in _sourceOfPathToken.entries)
      if (path.contains(token) && !code.contains(sourceId))
        '$path does not use $sourceId',
  ];
}

/// 自己寫 `Referer` / `Origin` / `User-Agent` 標頭字面值的檔案 → 寫了哪幾個，
/// 以及為什麼不走 policy。
///
/// 手寫一份標頭不會編譯錯誤，也不會在本機失敗；它只是和 policy 那一份各自
/// 演化，直到某一端的風控開始只認其中一份。新的檔案要寫標頭，先問能不能改用
/// `SourceHttpPolicy`；真的不能就加在這裡，寫明理由。已經在名單上的檔案多寫
/// 一個標頭也會紅 —— 下載服務的預設標頭曾經綁著 Bilibili 的 Referer。
const _headerLiteralOwners = <String, ({Set<String> headers, String why})>{
  'lib/data/sources/source_http_policy.dart': (
    headers: {'origin', 'referer', 'user-agent'},
    why: '標頭政策本身',
  ),
  'lib/core/utils/http_client_factory.dart': (
    headers: {'user-agent'},
    why: '所有客戶端的預設 User-Agent',
  ),
  'lib/services/download/download_service.dart': (
    headers: {'user-agent'},
    why: '下載用的 Dio 只帶 policy 的 mediaUserAgent；各音源的 Referer 由媒體請求自己帶',
  ),
  'lib/services/lyrics/lrclib_source.dart': (
    headers: {'user-agent'},
    why: '歌詞音源不屬於播放音源，policy 不涵蓋；LRCLIB 要求可辨識的 UA',
  ),
  'lib/services/lyrics/netease_source.dart': (
    headers: {'origin', 'referer', 'user-agent'},
    why: '歌詞音源，policy 不涵蓋',
  ),
  'lib/services/lyrics/qqmusic_source.dart': (
    headers: {'user-agent'},
    why: '歌詞音源，policy 不涵蓋',
  ),
  'lib/data/sources/playlist_import/qq_music_playlist_source.dart': (
    headers: {'referer', 'user-agent'},
    why: '歌單匯入音源，policy 不涵蓋；API 要行動版 UA 與 y.qq.com 的 Referer',
  ),
  'lib/data/sources/playlist_import/spotify_playlist_source.dart': (
    headers: {'user-agent'},
    why: '歌單匯入讀的是嵌入頁，要桌面瀏覽器的 UA 才拿得到 __NEXT_DATA__',
  ),
  'lib/services/account/netease_account_service.dart': (
    headers: {'origin', 'referer', 'user-agent'},
    why: '帶 Cookie 的帳號請求，標頭要和登入時的 Cookie 一起組',
  ),
  'lib/services/account/netease_playlist_service.dart': (
    headers: {'referer', 'user-agent'},
    why: '走 Linux API（eparams），要配 os=linux 的 Cookie 與對應的 UA',
  ),
};

final _headerLiteral = RegExp(
  r'''(?:(['"])(referer|origin|user-agent)\1\s*:|\[\s*(['"])(referer|origin|user-agent)\3\s*\])''',
  caseSensitive: false,
);

/// 在註解之外寫了標頭字面值（map 鍵或 `headers['...']`）的檔案 → 寫了哪幾個
/// 標頭（小寫）。
Map<String, Set<String>> headerLiterals(Map<String, String> sourcesByPath) => {
  for (final MapEntry(key: path, value: source) in sourcesByPath.entries)
    if (_headerLiteral.allMatches(stripDartComments(source)) case final matches
        when matches.isNotEmpty)
      path: {
        for (final m in matches) (m.group(2) ?? m.group(4))!.toLowerCase(),
      },
};

Map<String, String> _libSources() {
  final sources = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    sources[path] = entity.readAsStringSync();
  }
  return sources;
}

void main() {
  late Map<String, String> libSources;

  setUpAll(() {
    libSources = _libSources();
    // 掃描本身要有作用 —— 路徑寫錯時每一條斷言也都會是空的。
    expect(libSources.length, greaterThan(100));
  });

  group('source HTTP policy usage', () {
    test('no source client builds its own HTTP client', () {
      final offenders = <String>[
        for (final entry in libSources.entries)
          if (buildsARawSourceClient(entry.key, entry.value)) entry.key,
      ];

      expect(offenders, isEmpty);
    });

    test('every policy client identifies the source it speaks for', () {
      final clients = <String>[];
      final problems = <String>[];

      for (final entry in libSources.entries) {
        final found = policyClientProblems(entry.key, entry.value);
        if (found == null) continue;
        clients.add(entry.key);
        problems.addAll(found);
      }

      expect(problems, isEmpty);
      // 三個音源都還在，否則整條規則會安靜地變成空掃描。
      for (final token in _sourceOfPathToken.keys) {
        expect(
          clients.any((path) => path.contains(token)),
          isTrue,
          reason: 'no $token client goes through SourceHttpPolicy any more',
        );
      }
    });

    test('only the listed files write header literals', () {
      expect(
        headerLiterals(libSources),
        equals({
          for (final MapEntry(key: path, value: owner)
              in _headerLiteralOwners.entries)
            path: owner.headers,
        }),
        reason:
            'A file started or stopped writing Referer / Origin / User-Agent '
            'by hand. Use SourceHttpPolicy, or update _headerLiteralOwners in '
            'this file and say why the policy does not fit.',
      );
    });
  });

  group('the raw-client detector', () {
    test('catches a synthesised offender', () {
      const offender = '''
class RogueSource {
  RogueSource() : _dio = Dio(BaseOptions(baseUrl: 'https://api.bilibili.com'));
  final Dio _dio;
  String get id => SourceIds.bilibili;
}
''';

      expect(
        buildsARawSourceClient('lib/data/sources/rogue_source.dart', offender),
        isTrue,
      );
    });

    test('does not count a violation written in a comment', () {
      const commented = '''
class PolicySource {
  // 不要寫成 Dio(BaseOptions(...))，SourceIds.bilibili 的 UA 會掉。
  PolicySource() : _dio = SourceHttpPolicy.createApiDio(SourceIds.bilibili);
  final Dio _dio;
}
''';

      expect(
        buildsARawSourceClient(
          'lib/data/sources/policy_source.dart',
          commented,
        ),
        isFalse,
      );
    });

    test('a client that names no source or the wrong one is caught', () {
      const unnamed = '''
final _dio = SourceHttpPolicy.createApiDio(sourceType);
''';
      const wrongSource = '''
final _dio = SourceHttpPolicy.createApiDio(SourceIds.bilibili);
''';

      expect(policyClientProblems('lib/data/sources/netease_x.dart', unnamed), [
        'lib/data/sources/netease_x.dart names no source',
        'lib/data/sources/netease_x.dart does not use SourceIds.netease',
      ]);
      expect(
        policyClientProblems('lib/data/sources/netease_x.dart', wrongSource),
        ['lib/data/sources/netease_x.dart does not use SourceIds.netease'],
      );
    });

    test('line breaks and comments do not change the client verdict', () {
      const reformatted = '''
// 以前寫成 SourceHttpPolicy.createApiDio(SourceIds.bilibili)，註解不算。
final _renamedClient = SourceHttpPolicy
    .createApiDio(
  SourceIds.netease,
);
''';
      const noClient = '''
// final _dio = SourceHttpPolicy.createApiDio(SourceIds.bilibili);
final id = SourceIds.netease;
''';

      expect(
        policyClientProblems('lib/data/sources/netease_x.dart', reformatted),
        isEmpty,
      );
      expect(
        policyClientProblems('lib/data/sources/netease_x.dart', noClient),
        isNull,
      );
    });
  });

  group('the header-literal detector', () {
    test('a hand-written header in any spelling turns the rule red', () {
      const sources = {
        'lib/ui/a.dart': '''
final headers = {'Referer': 'https://www.bilibili.com'};
''',
        'lib/ui/b.dart': '''
options.headers["origin"] = 'https://www.youtube.com';
''',
        'lib/ui/c.dart': '''
final headers = {
  'user-agent'
      : 'Mozilla/5.0',
};
''',
      };

      expect(headerLiterals(sources), {
        'lib/ui/a.dart': {'referer'},
        'lib/ui/b.dart': {'origin'},
        'lib/ui/c.dart': {'user-agent'},
      });

      // 已經在名單上的檔案多寫一個標頭，也和名單不一樣了。
      expect(
        headerLiterals({
          'lib/services/download/download_service.dart': '''
headers: {
  'User-Agent': SourceHttpPolicy.mediaUserAgent,
  'Referer': 'https://www.bilibili.com',
},
''',
        }),
        {
          'lib/services/download/download_service.dart': {
            'user-agent',
            'referer',
          },
        },
      );
    });

    test('policy calls, comments and other headers do not', () {
      const sources = {
        'lib/ui/a.dart': '''
// 以前寫成 {'Referer': 'https://www.bilibili.com'}，改走 policy。
final headers = SourceHttpPolicy.imageHeadersForUrl(url);
final other = {'Cookie': cookie, 'Accept-Language': 'en'};
const hint = 'set the Referer: header yourself';
''',
      };

      expect(headerLiterals(sources), isEmpty);
    });
  });
}
