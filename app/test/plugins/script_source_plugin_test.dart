import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'plugin_harness.dart';

final _formats = [StreamFormat(container: 'mp4', codec: 'aac')];

void main() {
  group('the test plugin', () {
    test('searches with synthetic results', () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      final first = await plugin.search(SearchQuery(keyword: 'hi'));
      final second = await plugin.search(SearchQuery(keyword: 'hi', page: 2));

      expect(first.items.map((t) => t.sourceId), ['tone-220', 'tone-440']);
      expect(first.hasMore, isTrue);
      expect(second.items.map((t) => t.sourceId), ['tone-880']);
      expect(second.hasMore, isFalse);
      final track = first.items.first;
      expect(track.sourceTypeId, 'fmp-test');
      expect(track.cid, isNull);
      expect(track.title, 'Test tone 220 Hz (hi)');
      expect(track.uploader, 'FMP');
      expect(track.duration, const Duration(seconds: 2));
      expect(track.artwork, isEmpty);
    });

    test('reads its own storage while searching', () async {
      final harness = PluginHarness();
      final plugin = await harness.load(testPluginFile.readAsStringSync());
      await harness.storage.write('fmp-test', 'titlePrefix', 'Tone');

      final page = await plugin.search(SearchQuery(keyword: 'x'));

      expect(page.items.first.title, 'Tone 220 Hz (x)');
    });

    test('resolves a stream to the bundled tone', () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      final result = await plugin.resolveStream(
        StreamRequest(sourceId: 'tone-440', formats: _formats),
      );

      expect(result.previewOnly, isFalse);
      final candidate = result.candidates.single;
      expect(
        candidate.url,
        Uri.parse('asset:///test/fixtures/plugins/test_plugin/tone.wav'),
      );
      expect(candidate.container, 'wav');
      expect(candidate.codec, 'pcm_s16le');
      expect(candidate.bitrate, 256000);
      expect(candidate.expiresAt, isNull);
      expect(candidate.headers, isEmpty);
    });

    test('an unknown track is NotFound', () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      await expectLater(
        plugin.resolveStream(
          StreamRequest(sourceId: 'song-1', formats: _formats),
        ),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('exports and capabilities', () {
    test('a declared capability must be exported', () async {
      await expectLater(
        PluginHarness().load(
          pluginSource(
            'export function search() {}',
            capabilities: ['search', 'resolveStream'],
          ),
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('an exported capability must be declared', () async {
      await expectLater(
        PluginHarness().load(
          pluginSource(
            'export function search() {}\nexport function charts() {}',
          ),
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('other exports are allowed', () async {
      final plugin = await PluginHarness().load(
        pluginSource(
          'export function search() {}\n'
          'export function helper() {}\n'
          'export const version = 2;',
        ),
      );

      expect(plugin.manifest.id, 'plugin-a');
    });

    test('calling an undeclared capability is Unsupported', () async {
      final plugin = await PluginHarness().load(
        pluginSource('export function search() {}'),
      );

      expect(
        () => plugin.resolveStream(
          StreamRequest(sourceId: 'a', formats: _formats),
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('the manifest redaction list reaches the log', () async {
      final harness = PluginHarness();
      final source =
          pluginSource(
            "export function search() { fmp.log.info('ticket=FAKE_TICKET_42'); "
            'return { items: [], hasMore: false }; }',
          ).replaceFirst(
            '"allowedHosts"',
            '"redaction": {"keyNames": ["ticket"]},\n  "allowedHosts"',
          );
      final plugin = await harness.load(source);

      await plugin.search(SearchQuery(keyword: 'x'));

      expect(
        harness.records('plugin-a').single.message,
        isNot(contains('FAKE_TICKET_42')),
      );
    });
  });

  group('returned values', () {
    Future<Object> search(String result) async {
      final plugin = await PluginHarness().load(
        pluginSource(
          'export function search() { return $result; }',
          allowedHosts: ['example.test'],
        ),
      );
      return plugin
          .search(SearchQuery(keyword: 'x'))
          .then<Object>((page) => page, onError: (Object error) => error);
    }

    Future<Object> resolve(String result) async {
      final plugin = await PluginHarness().load(
        pluginSource(
          'export function resolveStream() { return $result; }',
          capabilities: ['resolveStream'],
          allowedHosts: ['example.test'],
        ),
      );
      return plugin
          .resolveStream(StreamRequest(sourceId: 'a', formats: _formats))
          .then<Object>((result) => result, onError: (Object error) => error);
    }

    test('the plugin cannot claim another source', () async {
      final page = await search(
        "{ items: [{ sourceId: 'a1', sourceTypeId: 'other', title: 'A' }], "
        'hasMore: false }',
      );

      // sourceTypeId 不是插件的欄位：表外的鍵，整個結果不收。
      expect(page, isA<ParseError>());
    });

    test('artwork on an allowed host is kept', () async {
      final page = await search(
        "{ items: [{ sourceId: 'a1', cid: 7, title: 'A', artwork: "
        "[{ url: 'https://img.example.test/a.jpg', width: 320 }] }], "
        'hasMore: true }',
      );

      page as SearchPage;
      final artwork = page.items.single.artwork.single;
      expect(artwork.url, Uri.parse('https://img.example.test/a.jpg'));
      expect(artwork.width, 320);
      expect(page.items.single.cid, 7);
    });

    for (final (description, result) in [
      ('a missing hasMore', '{ items: [] }'),
      ('an unknown field', '{ items: [], hasMore: false, total: 3 }'),
      (
        'a track without a title',
        "{ items: [{ sourceId: 'a1' }], hasMore: false }",
      ),
      (
        'a source id with a colon',
        "{ items: [{ sourceId: 'a:1', title: 'A' }], hasMore: false }",
      ),
      (
        'a fractional duration',
        "{ items: [{ sourceId: 'a1', title: 'A', durationMs: 1.5 }], "
            'hasMore: false }',
      ),
      (
        'artwork on another host',
        "{ items: [{ sourceId: 'a1', title: 'A', artwork: "
            "[{ url: 'https://evil.test/a.jpg' }] }], hasMore: false }",
      ),
      ('undefined', 'undefined'),
      ('a string', "'a track'"),
    ]) {
      test('search rejects $description as ParseError', () async {
        expect(await search(result), isA<ParseError>());
      });
    }

    test('a stream on an allowed host keeps its fields', () async {
      final candidates = await resolve(
        "{ candidates: [{ url: 'https://cdn.example.test/a.m4a', "
        "headers: { Referer: 'https://example.test/' }, container: 'mp4', "
        "codec: 'aac', bitrate: 192000, expiresAt: 1790000000000 }] }",
      );

      candidates as StreamResult;
      final candidate = candidates.candidates.single;
      expect(candidate.headers, {'Referer': 'https://example.test/'});
      expect(
        candidate.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1790000000000, isUtc: true),
      );
      // previewOnly 是選填，沒給就不是試聽。
      expect(candidates.previewOnly, isFalse);
    });

    test('a preview-only result says so', () async {
      for (final (value, expected) in [
        ('true', true),
        ('false', false),
        ('null', false),
      ]) {
        final result = await resolve(
          "{ candidates: [{ url: 'https://cdn.example.test/a.m4a' }], "
          'previewOnly: $value }',
        );

        expect(
          result,
          isA<StreamResult>().having(
            (r) => r.previewOnly,
            'previewOnly',
            expected,
          ),
          reason: value,
        );
      }
    });

    for (final (description, result) in [
      ('no candidates', '{ candidates: [] }'),
      (
        'a previewOnly that is not a boolean',
        "{ candidates: [{ url: 'https://example.test/a' }], previewOnly: 1 }",
      ),
      ('an http stream', "{ candidates: [{ url: 'http://example.test/a' }] }"),
      (
        'a stream on another host',
        "{ candidates: [{ url: 'https://evil.test/a' }] }",
      ),
      ('a file stream', "{ candidates: [{ url: 'file:///etc/passwd' }] }"),
      (
        'an asset URL with a host',
        "{ candidates: [{ url: 'asset://evil.test/a.wav' }] }",
      ),
      (
        'an expiry DateTime cannot hold',
        "{ candidates: [{ url: 'https://example.test/a', "
            'expiresAt: 9000000000000000 }] }',
      ),
      (
        'headers that are not strings',
        "{ candidates: [{ url: 'https://example.test/a', headers: { a: 1 } }] }",
      ),
    ]) {
      test('resolveStream rejects $description as ParseError', () async {
        expect(await resolve(result), isA<ParseError>());
      });
    }
  });

  group('inputs', () {
    test('what the host sends is checked before the call', () {
      expect(() => SearchQuery(keyword: ' '), throwsArgumentError);
      expect(() => SearchQuery(keyword: 'a', page: 0), throwsRangeError);
      expect(
        () => StreamRequest(sourceId: 'a:1', formats: _formats),
        throwsArgumentError,
      );
      expect(
        () => StreamRequest(sourceId: 'a', formats: const []),
        throwsArgumentError,
      );
    });

    test('the plugin receives the documented JSON', () async {
      final plugin = await PluginHarness().load(
        pluginSource(
          'export function search(query) { return { items: [{ sourceId: '
          "'q', title: JSON.stringify(query) }], hasMore: false }; }\n"
          'export function resolveStream(request) { return { candidates: '
          "[{ url: 'https://example.test/' + encodeURIComponent("
          'JSON.stringify(request)) }] }; }',
          capabilities: ['search', 'resolveStream'],
        ),
      );

      final page = await plugin.search(SearchQuery(keyword: 'k', page: 3));
      final stream = await plugin.resolveStream(
        StreamRequest(sourceId: 'bv1', cid: 9, formats: _formats),
      );

      expect(page.items.single.title, '{"keyword":"k","page":3}');
      expect(
        Uri.decodeComponent(stream.candidates.single.url.pathSegments.single),
        '{"sourceId":"bv1","cid":9,"purpose":"playback",'
        '"formats":[{"container":"mp4","codec":"aac"}]}',
      );
    });
  });
}
