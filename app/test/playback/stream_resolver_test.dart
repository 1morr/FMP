import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/playback/stream_resolver.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'fake_source_plugin.dart';

/// 平台的順序：AAC 在前（和 Android、Windows 的宣告一樣），其他編碼在後。
const formats = [
  PlayableFormat('mp4', 'aac'),
  PlayableFormat('webm', 'opus'),
  PlayableFormat('mp3', 'mp3'),
];

const highOpusFirst = (
  quality: AudioQuality.high,
  formatPriority: AudioFormatPriority.opusFirst,
);

TrackKeyParts track(String id, {int? cid}) =>
    TrackKeyParts(sourceTypeId: 'fmp-test', sourceId: id, cid: cid);

/// [preferences] 每次解析時讀一次（和 App 的組裝點一樣）。
StreamResolver resolverFor(
  FakeSourcePlugin plugin, {
  StreamPreferences Function()? preferences,
}) => StreamResolver(
  plugin: (id) => id == plugin.manifest.id ? plugin : null,
  formats: formats,
  preferences: preferences ?? () => highOpusFirst,
  log: Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
);

List<String> codecs(StreamRequest request) => [
  for (final format in request.formats) format.codec,
];

/// 以可調的 `clock` 跑 [body]：改 [FakeTime.now] 就是時間前進，不真的等。
Future<void> withFakeTime(Future<void> Function(FakeTime time) body) {
  final time = FakeTime();
  return withClock(Clock(() => time.now), () => body(time));
}

final class FakeTime {
  DateTime now = DateTime.utc(2026, 10, 2, 12);

  void elapse(Duration duration) => now = now.add(duration);
}

void main() {
  test('asks the plugin for playback with the platform formats and the '
      'preferences', () async {
    final plugin = FakeSourcePlugin((_) => [candidate('a.m4a')]);

    final stream = await resolverFor(plugin).resolve(track('BV1', cid: 7));

    expect(stream.candidates.single.url.path, '/a.m4a');
    final request = plugin.requests.single;
    expect(request.toJson(), {
      'sourceId': 'BV1',
      'cid': 7,
      'purpose': 'playback',
      'formats': [
        {'container': 'webm', 'codec': 'opus'},
        {'container': 'mp4', 'codec': 'aac'},
        {'container': 'mp3', 'codec': 'mp3'},
      ],
      'quality': 'high',
    });
    expect(request.purpose, StreamPurpose.playback);
  });

  group('preferences', () {
    test('the format priority puts that codec first and keeps the rest in '
        'the platform order', () async {
      var priority = AudioFormatPriority.opusFirst;
      final plugin = FakeSourcePlugin((_) => [candidate('a.m4a')]);
      final resolver = resolverFor(
        plugin,
        preferences: () =>
            (quality: AudioQuality.high, formatPriority: priority),
      );

      await resolver.resolve(track('a'));
      priority = AudioFormatPriority.aacFirst;
      await resolver.resolve(track('b'));

      expect(plugin.requests.map(codecs), [
        ['opus', 'aac', 'mp3'],
        ['aac', 'opus', 'mp3'],
      ]);
    });

    test('a codec the platform cannot play is not added', () async {
      final plugin = FakeSourcePlugin((_) => [candidate('a.m4a')]);
      final resolver = StreamResolver(
        plugin: (_) => plugin,
        formats: const [PlayableFormat('wav', 'pcm_s16le')],
        preferences: () => highOpusFirst,
        log: Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
      );

      await resolver.resolve(track('a'));

      expect(codecs(plugin.requests.single), ['pcm_s16le']);
    });

    test('each quality goes to the plugin by its wire name', () async {
      var quality = AudioQuality.high;
      final plugin = FakeSourcePlugin((_) => [candidate('a.m4a')]);
      final resolver = resolverFor(
        plugin,
        preferences: () =>
            (quality: quality, formatPriority: AudioFormatPriority.opusFirst),
      );

      for (final (index, value) in AudioQuality.values.indexed) {
        quality = value;
        await resolver.resolve(track('t$index'));
      }

      expect(
        [for (final request in plugin.requests) request.toJson()['quality']],
        ['high', 'medium', 'low'],
      );
    });

    test('changing a preference resolves the track again; changing it back '
        'uses the stream cached for it', () async {
      var preferences = highOpusFirst;
      final plugin = FakeSourcePlugin(
        (request) => [
          candidate(
            '${request.toJson()['quality']}-${request.formats.first.codec}.m4a',
          ),
        ],
      );
      final resolver = resolverFor(plugin, preferences: () => preferences);
      final high = await resolver.resolve(track('a'));

      preferences = (
        quality: AudioQuality.low,
        formatPriority: AudioFormatPriority.opusFirst,
      );
      final low = await resolver.resolve(track('a'));
      preferences = (
        quality: AudioQuality.low,
        formatPriority: AudioFormatPriority.aacFirst,
      );
      final lowAac = await resolver.resolve(track('a'));

      expect(high.candidates.single.url.path, '/high-opus.m4a');
      expect(low.candidates.single.url.path, '/low-opus.m4a');
      expect(lowAac.candidates.single.url.path, '/low-aac.m4a');
      expect(plugin.resolvedCount('a'), 3);

      preferences = highOpusFirst;
      expect(await resolver.resolve(track('a')), same(high));
      expect(plugin.resolvedCount('a'), 3);
    });
  });

  test('a source without an installed plugin is Unsupported', () async {
    final resolver = StreamResolver(
      plugin: (_) => null,
      formats: formats,
      preferences: () => highOpusFirst,
      log: Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
    );
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
    await expectLater(
      resolverFor(plugin).resolve(track('x')),
      throwsA(same(error)),
    );
  });

  group('stream URL cache', () {
    test('a stream is valid until five minutes before it expires', () {
      return withFakeTime((time) async {
        final plugin = FakeSourcePlugin(
          (_) => [
            candidate(
              'a.m4a',
              expiresAt: time.now.add(const Duration(minutes: 10)),
            ),
          ],
        );
        final resolver = resolverFor(plugin);
        final first = await resolver.resolve(track('a'));

        time.elapse(
          const Duration(minutes: 5) - const Duration(milliseconds: 1),
        );
        expect(await resolver.resolve(track('a')), same(first));
        expect(plugin.resolvedCount('a'), 1);

        time.elapse(const Duration(milliseconds: 1));
        expect(await resolver.resolve(track('a')), isNot(same(first)));
        expect(plugin.resolvedCount('a'), 2);
      });
    });

    test('without expiresAt a stream is valid for five minutes', () {
      return withFakeTime((time) async {
        final plugin = FakeSourcePlugin((_) => [candidate('a.m4a')]);
        final resolver = resolverFor(plugin);
        await resolver.resolve(track('a'));

        time.elapse(
          const Duration(minutes: 5) - const Duration(milliseconds: 1),
        );
        await resolver.resolve(track('a'));
        expect(plugin.resolvedCount('a'), 1);

        time.elapse(const Duration(milliseconds: 1));
        await resolver.resolve(track('a'));
        expect(plugin.resolvedCount('a'), 2);
      });
    });

    test('a stream already inside the margin is not kept', () {
      return withFakeTime((time) async {
        final plugin = FakeSourcePlugin(
          (_) => [
            candidate(
              'a.m4a',
              expiresAt: time.now.add(const Duration(minutes: 5)),
            ),
          ],
        );
        final resolver = resolverFor(plugin);
        await resolver.resolve(track('a'));
        await resolver.resolve(track('a'));
        expect(plugin.resolvedCount('a'), 2);
      });
    });

    test('the key is the whole track key, part included', () async {
      final plugin = FakeSourcePlugin(
        (request) => [candidate('${request.sourceId}-${request.cid}.m4a')],
      );
      final resolver = resolverFor(plugin);
      final part1 = await resolver.resolve(track('a', cid: 1));
      final part2 = await resolver.resolve(track('a', cid: 2));

      expect(part1.candidates.single.url.path, '/a-1.m4a');
      expect(part2.candidates.single.url.path, '/a-2.m4a');
      expect(await resolver.resolve(track('a', cid: 1)), same(part1));
      expect(plugin.requests, hasLength(2));
    });

    test('an invalidated stream is resolved again', () async {
      final plugin = FakeSourcePlugin((_) => [candidate('a.m4a')]);
      final resolver = resolverFor(plugin);
      final first = await resolver.resolve(track('a'));

      resolver.invalidate(first);
      final second = await resolver.resolve(track('a'));
      expect(second, isNot(same(first)));
      expect(plugin.resolvedCount('a'), 2);

      // 作廢已經被取代的舊結果不動到新的那一筆。
      resolver.invalidate(first);
      expect(await resolver.resolve(track('a')), same(second));
      expect(plugin.resolvedCount('a'), 2);
    });

    test('keeps the 64 most recently used streams', () async {
      final plugin = FakeSourcePlugin(
        (request) => [candidate('${request.sourceId}.m4a')],
      );
      final resolver = resolverFor(plugin);
      for (var i = 0; i < StreamResolver.capacity; i++) {
        await resolver.resolve(track('t$i'));
      }
      expect(StreamResolver.capacity, 64);
      // 用過 t0：最久沒用的變成 t1。
      await resolver.resolve(track('t0'));
      await resolver.resolve(track('new'));

      await resolver.resolve(track('t0'));
      await resolver.resolve(track('t2'));
      expect(plugin.resolvedCount('t0'), 1);
      expect(plugin.resolvedCount('t2'), 1);
      await resolver.resolve(track('t1'));
      expect(plugin.resolvedCount('t1'), 2);
    });

    test('concurrent calls for the same track share one request', () async {
      final gate = Completer<void>();
      final plugin = FakeSourcePlugin((_) async {
        await gate.future;
        return [candidate('a.m4a')];
      });
      final resolver = resolverFor(plugin);

      final first = resolver.resolve(track('a'));
      final second = resolver.resolve(track('a'));
      expect(second, same(first));
      gate.complete();

      expect(await second, same(await first));
      expect(plugin.resolvedCount('a'), 1);
    });

    test('a replaced plugin is asked again, even while the old one is '
        'resolving', () async {
      // 更新插件換成新的實例：舊實例的結果（以舊 manifest 的網域檢查過）與
      // 還在進行的請求都不給新的呼叫。
      final gate = Completer<void>();
      final old = FakeSourcePlugin((request) async {
        if (request.sourceId == 'b') await gate.future;
        return [candidate('old-${request.sourceId}.m4a')];
      });
      final updated = FakeSourcePlugin(
        (request) => [candidate('new-${request.sourceId}.m4a')],
      );
      var current = old;
      final resolver = StreamResolver(
        plugin: (id) => id == current.manifest.id ? current : null,
        formats: formats,
        preferences: () => highOpusFirst,
        log: Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
      );
      await resolver.resolve(track('a'));
      final pendingOnOld = resolver.resolve(track('b'));

      current = updated;
      final a = await resolver.resolve(track('a'));
      expect(a.candidates.single.url.path, '/new-a.m4a');
      final b = resolver.resolve(track('b'));
      expect(b, isNot(same(pendingOnOld)));
      expect((await b).candidates.single.url.path, '/new-b.m4a');

      gate.complete();
      await pendingOnOld;
      expect(updated.requests, hasLength(2));
    });

    test('a failed resolution is shared, then not kept', () async {
      var fail = true;
      final gate = Completer<void>();
      final plugin = FakeSourcePlugin((_) async {
        await gate.future;
        if (fail) throw NetworkError(pluginId: 'fmp-test');
        return [candidate('a.m4a')];
      });
      final resolver = resolverFor(plugin);

      final first = resolver.resolve(track('a'));
      final second = resolver.resolve(track('a'));
      gate.complete();
      await expectLater(first, throwsA(isA<NetworkError>()));
      await expectLater(second, throwsA(isA<NetworkError>()));
      expect(plugin.resolvedCount('a'), 1);

      fail = false;
      await resolver.resolve(track('a'));
      expect(plugin.resolvedCount('a'), 2);
    });
  });

  group('ResolvedStream freshness', () {
    final now = DateTime.utc(2026, 9, 30, 12);
    ResolvedStream expiring(DateTime? expiresAt) => ResolvedStream(
      track: track('x'),
      candidates: [candidate('a', expiresAt: expiresAt)],
    );

    test('the margin is five minutes', () {
      expect(ResolvedStream.expiryMargin, const Duration(minutes: 5));
    });

    test('without an expiry it is always fresh', () {
      expect(expiring(null).isFreshAt(now), isTrue);
      expect(expiring(null).refreshAt, isNull);
    });

    test('is stale within the margin before expiry', () {
      const margin = ResolvedStream.expiryMargin;
      final stream = expiring(now.add(margin + const Duration(seconds: 1)));
      expect(stream.isFreshAt(now), isTrue);
      expect(stream.isFreshAt(now.add(const Duration(seconds: 1))), isFalse);
      expect(stream.refreshAt, now.add(const Duration(seconds: 1)));
    });
  });
}
