import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'plugin_harness.dart';

// `mix` 能力（ADR 0028 §決定 4）：唯一的匯出叫 `mix`（和能力同名，不像 `live` 有四個）、
// 兩種輸入的 JSON、回傳值的驗證、宣告與匯出的一致，以及 fmp-test 的三批曲目。

const _mixExport = '''
export function mix(query) {
  return {
    mixId: 'm1',
    title: 'Mix',
    tracks: [{ sourceId: 'a', title: JSON.stringify(query) }],
    cursor: 'next',
  };
}
''';

Future<ScriptSourcePlugin> _load(
  String body, {
  List<String> capabilities = const ['mix'],
}) => PluginHarness().load(
  pluginSource(
    body,
    capabilities: capabilities,
    allowedHosts: ['example.test'],
  ),
);

void main() {
  group('exports and capabilities', () {
    test('a mix plugin exports one function named mix', () async {
      final plugin = await _load(_mixExport);

      expect(plugin.manifest.requiredExports, {'mix'});
    });

    test('declaring mix without exporting it is Unsupported', () {
      expect(_load('export function search() {}'), throwsA(isA<Unsupported>()));
    });

    test('exporting mix without declaring it is Unsupported', () {
      expect(
        _load(
          'export function search() {}\nexport function mix() {}',
          capabilities: ['search'],
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('calling mix without the capability is Unsupported', () async {
      final plugin = await _load(
        'export function search() {}',
        capabilities: ['search'],
      );

      expect(
        () => plugin.mix(MixSeedQuery(sourceId: 'a')),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  group('calls', () {
    test('a seed and a continuation reach the plugin as documented', () async {
      final plugin = await _load(_mixExport);

      final seeded = await plugin.mix(MixSeedQuery(sourceId: 'a'));
      final seededPart = await plugin.mix(MixSeedQuery(sourceId: 'a', cid: 2));
      final continued = await plugin.mix(
        MixContinueQuery(mixId: 'm0', cursor: 'c1'),
      );

      expect(seeded.tracks.single.title, '{"seed":{"sourceId":"a"}}');
      // 沒給 cid 就不送這個欄位。
      expect(
        seededPart.tracks.single.title,
        '{"seed":{"sourceId":"a","cid":2}}',
      );
      expect(continued.tracks.single.title, '{"mixId":"m0","cursor":"c1"}');
    });

    test('the batch decodes, and the host fills the source id', () async {
      final plugin = await _load(_mixExport);

      final batch = await plugin.mix(MixSeedQuery(sourceId: 'a'));

      expect(batch.mixId, 'm1');
      expect(batch.title, 'Mix');
      expect(batch.cursor, 'next');
      expect(batch.tracks.single.sourceTypeId, 'plugin-a');
      expect(batch.tracks.single.toTrackInfo().sourceTypeId, 'plugin-a');
    });

    test('a batch without a cursor means there is no more', () async {
      final plugin = await _load('''
export function mix() { return { mixId: 'm', title: 'T', tracks: [] }; }
''');

      final batch = await plugin.mix(MixSeedQuery(sourceId: 'a'));

      expect(batch.cursor, isNull);
      expect(batch.tracks, isEmpty);
    });

    test('a null cursor reads the same as a missing one', () async {
      final plugin = await _load('''
export function mix() { return { mixId: 'm', title: 'T', tracks: [], cursor: null }; }
''');

      expect((await plugin.mix(MixSeedQuery(sourceId: 'a'))).cursor, isNull);
    });

    test('inputs are checked before the call', () {
      expect(() => MixSeedQuery(sourceId: ' '), throwsArgumentError);
      expect(
        () => MixContinueQuery(mixId: '', cursor: 'c'),
        throwsArgumentError,
      );
      expect(
        () => MixContinueQuery(mixId: 'm', cursor: ''),
        throwsArgumentError,
      );
    });
  });

  group('returned values', () {
    Future<Object> mix(String result) async {
      final plugin = await _load('export function mix() { return $result; }');
      return plugin
          .mix(MixSeedQuery(sourceId: 'a'))
          .then<Object>((batch) => batch, onError: (Object error) => error);
    }

    for (final (description, result) in [
      ('a missing mixId', "{ title: 'T', tracks: [] }"),
      ('an empty mixId', "{ mixId: '', title: 'T', tracks: [] }"),
      ('a missing title', "{ mixId: 'm', tracks: [] }"),
      ('missing tracks', "{ mixId: 'm', title: 'T' }"),
      ('an empty cursor', "{ mixId: 'm', title: 'T', tracks: [], cursor: '' }"),
      (
        'a cursor that is not a string',
        "{ mixId: 'm', title: 'T', tracks: [], cursor: 3 }",
      ),
      ('an unknown field', "{ mixId: 'm', title: 'T', tracks: [], total: 1 }"),
      (
        'a track without a title',
        "{ mixId: 'm', title: 'T', tracks: [{ sourceId: 'a' }] }",
      ),
      ('a string', "'m'"),
      ('undefined', 'undefined'),
    ]) {
      test('mix rejects $description as ParseError', () async {
        expect(await mix(result), isA<ParseError>());
      });
    }

    test('a track on another artwork host is rejected', () async {
      expect(
        await mix(
          "{ mixId: 'm', title: 'T', tracks: [{ sourceId: 'a', title: 'T', "
          "artwork: [{ url: 'https://evil.test/a.jpg' }] }] }",
        ),
        isA<ParseError>(),
      );
    });

    test('an error thrown by the plugin keeps its type', () async {
      final plugin = await _load('''
export function mix() { throw { fmpError: 'RateLimited' }; }
''');

      await expectLater(
        plugin.mix(MixSeedQuery(sourceId: 'a')),
        throwsA(isA<RateLimited>()),
      );
    });
  });

  group('fmp-test', () {
    Future<ScriptSourcePlugin> load() =>
        PluginHarness().load(testPluginFile.readAsStringSync());

    test('every batch has five tracks and the third ends the mix', () async {
      final plugin = await load();

      final first = await plugin.mix(MixSeedQuery(sourceId: 'tone-440'));
      final second = await plugin.mix(
        MixContinueQuery(mixId: first.mixId, cursor: first.cursor!),
      );
      final third = await plugin.mix(
        MixContinueQuery(mixId: first.mixId, cursor: second.cursor!),
      );

      expect([first, second, third].map((batch) => batch.tracks.length), [
        5,
        5,
        5,
      ]);
      expect(first.cursor, isNotNull);
      expect(second.cursor, isNotNull);
      expect(third.cursor, isNull);
      expect({first.mixId, second.mixId, third.mixId}, {first.mixId});
    });

    test('the second batch repeats one track of the first', () async {
      final plugin = await load();

      final first = await plugin.mix(MixSeedQuery(sourceId: 'tone-440'));
      final second = await plugin.mix(
        MixContinueQuery(mixId: first.mixId, cursor: first.cursor!),
      );
      final keys = {for (final track in first.tracks) track.sourceId};
      final repeated = second.tracks.where(
        (track) => keys.contains(track.sourceId),
      );

      expect(repeated, hasLength(1));
      expect(first.tracks.first.sourceId, 'mix-${first.mixId}-1');
    });

    test('a new seed is a new mix with other track keys', () async {
      final plugin = await load();

      final first = await plugin.mix(MixSeedQuery(sourceId: 'tone-440'));
      final again = await plugin.mix(MixSeedQuery(sourceId: 'tone-440'));

      expect(again.mixId, isNot(first.mixId));
      expect(
        {for (final track in first.tracks) track.sourceId}
            .intersection({for (final track in again.tracks) track.sourceId}),
        isEmpty,
      );
    });

    test('a cursor it does not know is NotFound', () async {
      final plugin = await load();

      await expectLater(
        plugin.mix(MixContinueQuery(mixId: 'm', cursor: 'nonsense')),
        throwsA(isA<NotFound>()),
      );
    });

    test('its mix tracks play the bundled tone', () async {
      final plugin = await load();
      final batch = await plugin.mix(MixSeedQuery(sourceId: 'tone-440'));

      final stream = await plugin.resolveStream(
        StreamRequest(
          sourceId: batch.tracks.first.sourceId,
          formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
        ),
      );

      expect(stream.candidates.first.url.scheme, 'asset');
    });
  });
}
