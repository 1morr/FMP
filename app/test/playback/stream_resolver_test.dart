import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/playback/stream_resolver.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'fake_source_plugin.dart';

void main() {
  const formats = [
    PlayableFormat('mp4', 'aac'),
    PlayableFormat('webm', 'opus'),
  ];

  test('asks the plugin for playback with the platform formats', () async {
    final plugin = FakeSourcePlugin((_) => [candidate('a.m4a')]);
    final resolver = StreamResolver(
      plugin: (id) => id == 'fmp-test' ? plugin : null,
      formats: formats,
    );

    final stream = await resolver.resolve(
      const TrackKeyParts(sourceTypeId: 'fmp-test', sourceId: 'BV1', cid: 7),
    );

    expect(stream.candidates.single.url.path, '/a.m4a');
    final request = plugin.requests.single;
    expect(request.toJson(), {
      'sourceId': 'BV1',
      'cid': 7,
      'purpose': 'playback',
      'formats': [
        {'container': 'mp4', 'codec': 'aac'},
        {'container': 'webm', 'codec': 'opus'},
      ],
    });
    expect(request.purpose, StreamPurpose.playback);
  });

  test('a source without an installed plugin is Unsupported', () async {
    final resolver = StreamResolver(plugin: (_) => null, formats: formats);
    await expectLater(
      resolver.resolve(
        const TrackKeyParts(sourceTypeId: 'missing', sourceId: 'x'),
      ),
      throwsA(
        isA<Unsupported>().having((e) => e.pluginId, 'pluginId', 'missing'),
      ),
    );
  });

  test('plugin errors pass through unchanged', () async {
    final error = NotFound(pluginId: 'fmp-test');
    final plugin = FakeSourcePlugin((_) => throw error);
    final resolver = StreamResolver(plugin: (_) => plugin, formats: formats);
    await expectLater(
      resolver.resolve(
        const TrackKeyParts(sourceTypeId: 'fmp-test', sourceId: 'x'),
      ),
      throwsA(same(error)),
    );
  });

  group('ResolvedStream freshness', () {
    final now = DateTime.utc(2026, 9, 30, 12);
    ResolvedStream expiring(DateTime? expiresAt) => ResolvedStream(
      track: const TrackKeyParts(sourceTypeId: 'fmp-test', sourceId: 'x'),
      candidates: [candidate('a', expiresAt: expiresAt)],
    );

    test('without an expiry it is always fresh', () {
      expect(expiring(null).isFreshAt(now), isTrue);
      expect(expiring(null).refreshAt, isNull);
    });

    test('is stale within the margin before expiry', () {
      final margin = ResolvedStream.expiryMargin;
      final stream = expiring(now.add(margin + const Duration(seconds: 1)));
      expect(stream.isFreshAt(now), isTrue);
      expect(stream.isFreshAt(now.add(const Duration(seconds: 1))), isFalse);
      expect(stream.refreshAt, now.add(const Duration(seconds: 1)));
    });
  });
}
