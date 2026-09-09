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
      final wrongSource = <String>[];

      for (final entry in libSources.entries) {
        final code = stripDartComments(entry.value);
        if (!code.contains('SourceHttpPolicy.createApiDio')) continue;
        clients.add(entry.key);

        expect(
          code,
          contains('SourceIds.'),
          reason:
              '${entry.key} asks the policy for a Dio without naming a '
              'source; the policy cannot pick a UA or a Referer',
        );

        for (final token in _sourceOfPathToken.entries) {
          if (!entry.key.contains(token.key)) continue;
          if (!code.contains(token.value)) {
            wrongSource.add('${entry.key} does not use ${token.value}');
          }
        }
      }

      expect(wrongSource, isEmpty);
      // 三個音源都還在，否則整條規則會安靜地變成空掃描。
      for (final token in _sourceOfPathToken.keys) {
        expect(
          clients.any((path) => path.contains(token)),
          isTrue,
          reason: 'no $token client goes through SourceHttpPolicy any more',
        );
      }
    });

    test('InnerTube request options reuse policy headers', () {
      final source = libSources['lib/data/sources/youtube_source.dart']!;

      expect(source, contains('SourceHttpPolicy.apiHeaders'));
      expect(source, isNot(contains("'Origin': 'https://www.youtube.com'")));
      expect(source, isNot(contains("'Referer': 'https://www.youtube.com/'")));
    });

    test('Netease source does not depend on account service for policy UA', () {
      final source = libSources['lib/data/sources/netease_source.dart']!;

      expect(source, isNot(contains('NeteaseAccountService')));
    });
  });

  group('Bilibili live HTTP policy', () {
    test('the live client owns the live headers', () {
      final source = libSources['lib/data/sources/bilibili_live_client.dart']!;

      expect(source, contains('SourceHttpPolicy.createBilibiliLiveDio'));
      expect(source, contains('SourceHttpPolicy.bilibiliLiveHeaders'));
      expect(source, contains('/room/v1/Room/playUrl'));
      expect(
        source,
        isNot(contains("'Referer': 'https://live.bilibili.com/'")),
      );
    });

    test('sources delegate Bilibili live mechanics to the live client', () {
      final bilibiliSource =
          libSources['lib/data/sources/bilibili_source.dart']!;
      final radioSource = libSources['lib/services/radio/radio_source.dart']!;

      expect(bilibiliSource, contains('BilibiliLiveClient'));
      expect(radioSource, contains('BilibiliLiveClient'));
      expect(bilibiliSource, isNot(contains('/room/v1/Room/playUrl')));
      expect(radioSource, isNot(contains('/room/v1/Room/playUrl')));
    });

    test('radio cover preloader relies on the URL-based header policy', () {
      final source =
          libSources['lib/ui/widgets/panels/track_detail_panel.dart']!;

      // 電台封面不得自帶 headers：ImageLoadingService 會自動套
      // SourceHttpPolicy.imageHeadersForUrl，與其他 RadioCoverImage 呼叫點一致。
      expect(source, isNot(contains('SourceHttpPolicy.bilibiliLiveHeaders')));
      expect(
        source,
        isNot(contains("headers: {'Referer': 'https://www.bilibili.com'}")),
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
  });
}
