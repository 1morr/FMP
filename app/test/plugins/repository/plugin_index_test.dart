import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/repository/plugin_index.dart';

Map<String, Object?> entry([Map<String, Object?> extra = const {}]) => {
  'id': 'youtube',
  'name': 'YouTube',
  'author': '1morr',
  'description': 'Search and play',
  'version': '1.0.0',
  'apiVersion': 1,
  'capabilities': ['search', 'resolveStream'],
  'allowedHosts': ['youtube.com', 'googlevideo.com'],
  'url': 'https://raw.example.test/youtube/youtube.js',
  'sha256': 'a' * 64,
  ...extra,
};

String index({
  Object? version = 1,
  List<Object?>? plugins,
  Map<String, Object?> extra = const {},
}) => jsonEncode({
  'indexVersion': version,
  'plugins': plugins ?? [entry()],
  ...extra,
});

/// 解析出 index；不是 [IndexRead] 就讓測試失敗。
PluginIndex parseIndex(String text) =>
    (PluginIndex.parse(text) as IndexRead).index;

void main() {
  test('parses an index', () {
    final parsed = parseIndex(
      index(
        plugins: [
          entry({
            'checksUrl': 'https://raw.example.test/youtube/checks.json',
            'checksSha256': 'b' * 64,
          }),
        ],
      ),
    );

    final plugin = parsed.plugins.single;
    expect(plugin.id, 'youtube');
    expect(plugin.capabilities, {
      PluginCapability.search,
      PluginCapability.resolveStream,
    });
    expect(plugin.url.host, 'raw.example.test');
    expect(plugin.checksSha256, 'b' * 64);
    expect(plugin.isCompatible, isTrue);
  });

  test('an unknown field is refused, in the index and in an entry', () {
    expect(
      () => PluginIndex.parse(index(extra: {'extra': 1})),
      throwsA(isA<ParseError>()),
    );
    expect(
      () => PluginIndex.parse(
        index(
          plugins: [
            entry({'homepage': 'x'}),
          ],
        ),
      ),
      throwsA(isA<ParseError>()),
    );
  });

  test('an indexVersion other than 1 is refused as needing a newer app', () {
    for (final version in [0, 2]) {
      expect(
        PluginIndex.parse(index(version: version)),
        isA<IndexRejected>().having(
          (e) => e.reason,
          'reason',
          PluginRejection.appUpdateRequired,
        ),
      );
    }
    // 新版 index 多出來的欄位不比版本號先被當成格式錯誤。
    expect(
      PluginIndex.parse(index(version: 2, extra: {'new': true})),
      isA<IndexRejected>(),
    );
  });

  test('malformed entries are a ParseError', () {
    final bad = <String, Map<String, Object?>>{
      'bad id': {'id': 'Bad Id'},
      'bad version': {'version': 'one'},
      'bad sha': {'sha256': 'XYZ'},
      'http url': {'url': 'http://raw.example.test/a.js'},
      'unknown capability': {
        'capabilities': ['search', 'teleport'],
      },
      'checksUrl without sha': {'checksUrl': 'https://raw.example.test/c.json'},
    };
    for (final MapEntry(:key, :value) in bad.entries) {
      expect(
        () => PluginIndex.parse(index(plugins: [entry(value)])),
        throwsA(isA<ParseError>()),
        reason: key,
      );
    }
    expect(
      () => PluginIndex.parse(index(plugins: [entry(), entry()])),
      throwsA(isA<ParseError>()),
    );
    expect(() => PluginIndex.parse('not json'), throwsA(isA<ParseError>()));
    expect(() => PluginIndex.parse('[]'), throwsA(isA<ParseError>()));
  });

  test('a plugin with another apiVersion parses but is not compatible', () {
    final parsed = parseIndex(
      index(
        plugins: [
          entry({'apiVersion': 2}),
        ],
      ),
    );

    expect(parsed.plugins.single.isCompatible, isFalse);
  });
}
