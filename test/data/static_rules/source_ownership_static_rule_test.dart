import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/source_ids.dart';

import '../../support/dart_source.dart';

final _importExportUriPattern = RegExp(
  r'''(import|export)\s+['"]([^'"]+)['"]''',
);
final _concreteProviderPattern = RegExp(
  r'\b(?:bilibiliSourceProvider|youtubeSourceProvider|neteaseAudioSourceProvider)\b',
);
final _concreteGetterUsePattern = RegExp(
  r'\.(?:bilibiliSource|youtubeSource|neteaseSource)\b',
);

final _concreteGetterDeclarationPattern = RegExp(
  r'\b(?:BilibiliSource|YouTubeSource|NeteaseSource)\s*\??\s+get\s+'
  r'(?:bilibiliSource|youtubeSource|neteaseSource)\b',
);
final _concreteProviderDeclarationPattern = RegExp(
  r'\b(?:final|var)\b[\s\w<>,?]*\b(?:bilibiliSourceProvider|'
  r'youtubeSourceProvider|neteaseAudioSourceProvider)\b\s*=',
);

/// 非 abstract、名字以 `Source` 或 `Client` 結尾的類別宣告。
final _concreteSourceClassPattern = RegExp(
  r'^(?:final\s+|base\s+)?class\s+(\w+(?:Source|Client))\b',
  multiLine: true,
);

/// 註冊這些實作、並把窄能力發給其他人的地方。
const _sourceManagerFile = 'lib/data/sources/source_provider.dart';

/// 在 `SourceManager` 之外直接拿具體實作的檔案 → 拿了哪個檔案、為什麼。
///
/// 這兩處用的都是 `LiveSource` 沒有的 Bilibili 專屬功能，而直播與勳章牆都刻意只
/// 支援 Bilibili。代價是它們各自建一個 `BilibiliLiveClient`，不經過
/// `SourceManager` 的生命週期；新增一筆之前先問能不能改成向 `SourceManager`
/// 要能力。
const _recordedDirectImports = <String, Map<String, String>>{
  'lib/services/radio/radio_source.dart': {
    'lib/data/sources/bilibili_live_client.dart':
        '電台要解析直播網址、讀高能人數、取電台串流，這些都不在 LiveSource 上',
  },
  'lib/services/account/bilibili_account_service.dart': {
    'lib/data/sources/bilibili_live_client.dart':
        '粉絲勳章牆的直播間清單是帳號功能，只有 Bilibili 有',
  },
};

/// `lib/data/sources/` 頂層宣告了具體音源實作的檔案 → 它宣告的類別名。
///
/// 從目錄推導而不是列舉：以前這裡是寫死的三個 adapter 路徑，
/// `bilibili_live_client.dart` 不在其中，於是兩個 service 直接建它也不會紅。
/// 子目錄（歌單匯入）是另一套登記方式，不在這條規則裡。
Map<String, Set<String>> concreteSourceFiles(
  Map<String, String> sourcesByPath,
) {
  return {
    for (final MapEntry(key: path, value: source) in sourcesByPath.entries)
      if (path.startsWith('lib/data/sources/') &&
          !path.substring('lib/data/sources/'.length).contains('/'))
        if (_concreteSourceClassPattern
                .allMatches(stripDartComments(source))
                .map((match) => match.group(1)!)
                .toSet()
            case final classes when classes.isNotEmpty)
          path: classes,
  };
}

void main() {
  group('Source ownership', () {
    test('runtime code does not use concrete data source access', () {
      final sources = <String, String>{
        for (final entity in Directory('lib').listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.dart'))
            entity.path.replaceAll('\\', '/'): entity.readAsStringSync(),
      };
      final concrete = concreteSourceFiles(sources);
      // 推導本身要有作用：每個內建音源至少有一個實作檔。
      expect(concrete.length, greaterThanOrEqualTo(SourceIds.values.length));

      final offenders = <String>[
        for (final MapEntry(key: path, value: source) in sources.entries)
          ...runtimeConcreteSourceOffenders(path, source, concrete),
      ];

      expect(offenders, isEmpty);
    });

    test('every recorded direct import still exists', () {
      for (final MapEntry(key: importer, value: imported)
          in _recordedDirectImports.entries) {
        final source = File(importer).readAsStringSync();
        for (final target in imported.keys) {
          expect(
            _importedLibPaths(importer, source),
            contains(target),
            reason: '$importer no longer imports $target; drop the exception',
          );
        }
      }
    });

    test('a new adapter file is covered without being listed', () {
      final concrete = concreteSourceFiles(const {
        'lib/data/sources/soundcloud_source.dart':
            'final class SoundCloudSource implements SearchSource {}',
        'lib/data/sources/soundcloud_client.dart':
            '// class NotAClient\nclass SoundCloudClient with Logging {}',
        'lib/data/sources/source_capabilities.dart':
            'abstract interface class SearchSource {}',
        'lib/data/sources/playlist_import/x_source.dart':
            'class XPlaylistSource implements PlaylistImportSource {}',
      });

      expect(concrete, {
        'lib/data/sources/soundcloud_source.dart': {'SoundCloudSource'},
        'lib/data/sources/soundcloud_client.dart': {'SoundCloudClient'},
      });
    });

    test('a direct import of a live client is caught unless recorded', () {
      const concrete = {
        'lib/data/sources/bilibili_live_client.dart': {'BilibiliLiveClient'},
      };
      const importsClient =
          "import 'package:fmp/data/sources/bilibili_live_client.dart';";

      expect(
        runtimeConcreteSourceOffenders(
          'lib/services/example.dart',
          importsClient,
          concrete,
        ),
        [
          'lib/services/example.dart imports concrete data source: '
              'lib/data/sources/bilibili_live_client.dart',
        ],
      );
      expect(
        runtimeConcreteSourceOffenders(
          'lib/services/radio/radio_source.dart',
          importsClient,
          concrete,
        ),
        isEmpty,
      );
      // 名字相近、但不是實作檔的 import 不算。
      expect(
        runtimeConcreteSourceOffenders(
          'lib/services/example.dart',
          "import 'package:fmp/data/sources/bilibili_live_client_types.dart';",
          concrete,
        ),
        isEmpty,
      );
    });

    test('source provider does not expose concrete source accessors', () {
      final source = File(
        'lib/data/sources/source_provider.dart',
      ).readAsStringSync();

      expect(_sourceProviderConcreteAccessors(source), isEmpty);
    });

    test('runtime guard detects concrete adapter imports broadly', () {
      const cases = {
        'package import':
            'import "package:fmp/data/sources/youtube_source.dart";',
        'relative import with alias':
            "import '../data/sources/bilibili_source.dart' as bilibili;",
        'export': 'export "../data/sources/netease_source.dart";',
      };

      for (final entry in cases.entries) {
        expect(
          runtimeConcreteSourceOffenders(
            'lib/services/example.dart',
            entry.value,
            _builtInAdapters,
          ),
          contains(contains('concrete data source')),
          reason: entry.key,
        );
      }
    });

    test('the source manager may import an adapter but not re-export it', () {
      expect(
        runtimeConcreteSourceOffenders(
          _sourceManagerFile,
          "import 'package:fmp/data/sources/bilibili_source.dart';",
          _builtInAdapters,
        ),
        isEmpty,
      );
      // 轉出去之後，任何 import source_provider 的檔案都拿得到具體類別。
      expect(
        runtimeConcreteSourceOffenders(
          _sourceManagerFile,
          "export 'bilibili_source.dart';",
          _builtInAdapters,
        ),
        [
          '$_sourceManagerFile exports concrete data source: '
              'lib/data/sources/bilibili_source.dart',
        ],
      );
    });

    test(
      'runtime guard allows lyrics NeteaseSource without data adapter import',
      () {
        const source = '''
import 'package:fmp/services/lyrics/netease_source.dart';

final netease = NeteaseSource();
''';

        expect(
          runtimeConcreteSourceOffenders(
            'lib/services/lyrics/example.dart',
            source,
            _builtInAdapters,
          ),
          isEmpty,
        );
      },
    );

    test('runtime guard ignores comments and look-alike names', () {
      const source = '''
// 以前這裡是 YouTubeSource()，改走 SourceManager 的窄能力。
/* final s = ref.watch(bilibiliSourceProvider); */
import 'package:fmp/data/sources/source_provider.dart';

final type = manager.bilibiliSourceType;
final ids = BilibiliSourceIds.all;
''';

      expect(
        runtimeConcreteSourceOffenders(
          'lib/services/example.dart',
          source,
          _builtInAdapters,
        ),
        isEmpty,
      );
    });

    test('source provider guard ignores narrow capabilities and comments', () {
      const source = '''
// BilibiliSource? get bilibiliSource => null;  （已移除）
SearchCapability get search => _search;
final sourceManagerProvider = Provider<SourceManager>((ref) => SourceManager());
''';

      expect(_sourceProviderConcreteAccessors(source), isEmpty);
    });

    test('source provider guard detects reformatted concrete accessors', () {
      const source = '''
BilibiliSource?
get
bilibiliSource => null;

final
youtubeSourceProvider
= Provider<YouTubeSource>((ref) => throw UnimplementedError());
''';

      expect(
        _sourceProviderConcreteAccessors(source),
        containsAll([
          contains('concrete source getter'),
          contains('concrete source provider'),
        ]),
      );
    });
  });
}

/// 範例用的內建 adapter；真正的清單由 [concreteSourceFiles] 從目錄推導。
const _builtInAdapters = {
  'lib/data/sources/bilibili_source.dart': {'BilibiliSource'},
  'lib/data/sources/youtube_source.dart': {'YouTubeSource'},
  'lib/data/sources/netease_source.dart': {'NeteaseSource'},
};

/// [path] 在 `SourceManager` 之外拿具體實作的地方。
///
/// 看的是 import / export，不看類別名：歌詞層也有一個 `NeteaseSource`，只比對
/// 名字會把它誤判成 adapter。實作檔之間互相 import、`SourceManager` import
/// 它們都是本來就該有的；但它們一旦 export 出去，拿到的人就繞過了這條規則。
List<String> runtimeConcreteSourceOffenders(
  String path,
  String raw,
  Map<String, Set<String>> concrete,
) {
  final source = stripDartComments(raw);
  final insideSourceLayer =
      path == _sourceManagerFile || concrete.containsKey(path);
  final recorded = _recordedDirectImports[path] ?? const {};
  return [
    for (final (:keyword, :target) in _libDirectives(path, source))
      if (concrete.containsKey(target) &&
          !recorded.containsKey(target) &&
          (keyword == 'export' || !insideSourceLayer))
        '$path ${keyword}s concrete data source: $target',
    if (!insideSourceLayer && _concreteProviderPattern.hasMatch(source))
      '$path references concrete source provider',
    if (!insideSourceLayer && _concreteGetterUsePattern.hasMatch(source))
      '$path references concrete source getter',
  ];
}

List<String> _sourceProviderConcreteAccessors(String raw) {
  final source = stripDartComments(raw);
  return [
    if (_concreteGetterDeclarationPattern.hasMatch(source))
      'source_provider.dart declares concrete source getter',
    if (_concreteProviderDeclarationPattern.hasMatch(source))
      'source_provider.dart declares concrete source provider',
  ];
}

/// 指向 `lib/` 內檔案的 import / export，路徑已正規化。
Iterable<({String keyword, String target})> _libDirectives(
  String path,
  String source,
) sync* {
  for (final match in _importExportUriPattern.allMatches(source)) {
    final target = _normalizedLibImportPath(path, match.group(2)!);
    if (target != null) yield (keyword: match.group(1)!, target: target);
  }
}

Set<String> _importedLibPaths(String path, String raw) => {
  for (final (:keyword, :target) in _libDirectives(
    path,
    stripDartComments(raw),
  ))
    if (keyword == 'import') target,
};

String? _normalizedLibImportPath(String importerPath, String importUri) {
  const packagePrefix = 'package:fmp/';
  if (importUri.startsWith(packagePrefix)) {
    return _normalizePath('lib/${importUri.substring(packagePrefix.length)}');
  }

  if (importUri.contains(':')) return null;

  final importerParts = importerPath.replaceAll('\\', '/').split('/');
  final baseParts = importerParts.take(importerParts.length - 1).join('/');
  return _normalizePath('$baseParts/$importUri');
}

String _normalizePath(String path) {
  final parts = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return parts.join('/');
}
