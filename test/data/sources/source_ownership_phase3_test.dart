import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _importExportUriPattern = RegExp(
  r'''(?:import|export)\s+['"]([^'"]+)['"]''',
);
final _concreteBilibiliYoutubeClassPattern = RegExp(
  r'\b(?:BilibiliSource|YouTubeSource)\b',
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

const _dataSourceAdapterPaths = {
  'lib/data/sources/bilibili_source.dart',
  'lib/data/sources/youtube_source.dart',
  'lib/data/sources/netease_source.dart',
};

void main() {
  group('Source ownership', () {
    test('runtime code does not construct ad-hoc YouTubeSource instances', () {
      const checkedFiles = [
        'lib/services/audio/audio_provider.dart',
        'lib/providers/library/playlist_provider.dart',
        'lib/providers/search/popular_provider.dart',
        'lib/services/import/import_service.dart',
        'lib/services/cache/ranking_cache_service.dart',
      ];

      final offenders = <String>[];
      for (final path in checkedFiles) {
        final source = File(path).readAsStringSync();
        if (source.contains('YouTubeSource(')) {
          offenders.add(path);
        }
      }

      expect(offenders, isEmpty);
    });

    test('runtime code does not use RankingCacheService singleton', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }

        final source = entity.readAsStringSync();
        if (source.contains('RankingCacheService.instance')) {
          offenders.add(entity.path);
        }
      }

      expect(offenders, isEmpty);
    });

    test('runtime library parsers do not import concrete source adapters', () {
      final source = File(
        'lib/services/library/remote_playlist_id_parser.dart',
      ).readAsStringSync();

      expect(source, isNot(contains("data/sources/bilibili_source.dart")));
      expect(source, isNot(contains('BilibiliSource.')));
    });

    test('runtime code does not use concrete data source access', () {
      const allowedFiles = {
        'lib/data/sources/source_provider.dart',
        'lib/data/sources/bilibili_source.dart',
        'lib/data/sources/youtube_source.dart',
        'lib/data/sources/netease_source.dart',
      };

      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (allowedFiles.contains(path)) continue;

        final source = entity.readAsStringSync();
        offenders.addAll(_runtimeConcreteSourceOffenders(path, source));
      }

      expect(offenders, isEmpty);
    });

    test('source provider does not expose concrete source accessors', () {
      final source =
          File('lib/data/sources/source_provider.dart').readAsStringSync();

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
          _runtimeConcreteSourceOffenders(
            'lib/services/example.dart',
            entry.value,
          ),
          contains(contains('imports concrete data source adapter')),
          reason: entry.key,
        );
      }
    });

    test('runtime guard detects concrete Bilibili and YouTube class references',
        () {
      const cases = {
        'constructor': 'final source = YouTubeSource();',
        'cast': 'final source = value as BilibiliSource;',
        'whereType': 'manager.sources.whereType<BilibiliSource>();',
      };

      for (final entry in cases.entries) {
        expect(
          _runtimeConcreteSourceOffenders(
            'lib/services/example.dart',
            entry.value,
          ),
          contains(contains('concrete source class')),
          reason: entry.key,
        );
      }
    });

    test(
        'runtime guard allows lyrics NeteaseSource without data adapter import',
        () {
      const source = '''
import 'package:fmp/services/lyrics/netease_source.dart';

final netease = NeteaseSource();
''';

      expect(
        _runtimeConcreteSourceOffenders(
          'lib/services/lyrics/example.dart',
          source,
        ),
        isEmpty,
      );
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

List<String> _runtimeConcreteSourceOffenders(String path, String source) {
  return [
    for (final importUri in _importedUris(source))
      if (_isDataSourceAdapterImport(path, importUri))
        '$path imports concrete data source adapter: $importUri',
    if (_concreteBilibiliYoutubeClassPattern.hasMatch(source))
      '$path references concrete source class',
    if (_concreteProviderPattern.hasMatch(source))
      '$path references concrete source provider',
    if (_concreteGetterUsePattern.hasMatch(source))
      '$path references concrete source getter',
  ];
}

List<String> _sourceProviderConcreteAccessors(String source) {
  return [
    if (_concreteGetterDeclarationPattern.hasMatch(source))
      'source_provider.dart declares concrete source getter',
    if (_concreteProviderDeclarationPattern.hasMatch(source))
      'source_provider.dart declares concrete source provider',
  ];
}

Iterable<String> _importedUris(String source) {
  return _importExportUriPattern
      .allMatches(source)
      .map((match) => match.group(1)!)
      .where((uri) {
    return uri.endsWith('bilibili_source.dart') ||
        uri.endsWith('youtube_source.dart') ||
        uri.endsWith('netease_source.dart');
  });
}

bool _isDataSourceAdapterImport(String importerPath, String importUri) {
  final importedPath = _normalizedLibImportPath(importerPath, importUri);
  return importedPath != null && _dataSourceAdapterPaths.contains(importedPath);
}

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
