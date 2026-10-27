import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/charts/chart_cache.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/domain/track_info.dart';

import '../data/cache/cache_harness.dart';

// 榜單快取（M4 design §9.1、ADR 0016 §決定 4）：內容、鍵、所屬插件、淘汰與壞檔。以真的快取庫跑。

final _fetchedAt = DateTime.utc(2026, 10, 16, 12, 30, 15, 250);

final _tracks = [
  TrackInfo(
    sourceTypeId: 'fmp-test',
    sourceId: 'tone-440',
    title: 'Hot tone 440 Hz',
    uploader: 'FMP',
    duration: const Duration(seconds: 2),
    viewCount: 46000000,
    artwork: [
      TrackArtwork(url: Uri.parse('https://cdn.example/a.jpg'), width: 300),
      TrackArtwork(url: Uri.parse('https://cdn.example/b.jpg')),
    ],
  ),
  const TrackInfo(
    sourceTypeId: 'fmp-test',
    sourceId: 'BV1',
    cid: 22001,
    title: 'Part one',
    partIndex: 1,
    parentTitle: 'Video',
  ),
];

ChartKey _key(String pluginId, String chartId) =>
    (pluginId: pluginId, chartId: chartId);

void main() {
  Future<(CacheHarness, CacheStore, ChartCache)> open({
    int limitBytes = 1 << 20,
  }) async {
    final harness = CacheHarness();
    final store = await harness.open(limitBytes: limitBytes);
    return (harness, store, ChartCache(store));
  }

  test(
    'what was written is read back with its time and tracks, in order',
    () async {
      final (_, _, cache) = await open();

      await cache.write(
        _key('fmp-test', 'hot'),
        ChartCacheEntry(fetchedAt: _fetchedAt, tracks: _tracks),
      );

      final entry = (await cache.read(_key('fmp-test', 'hot')))!;
      expect(entry.fetchedAt, _fetchedAt);
      expect(entry.fetchedAt.isUtc, isTrue);
      expect(entry.tracks, _tracks);
    },
  );

  test('an empty chart is an entry with no tracks, not a miss', () async {
    final (_, _, cache) = await open();

    await cache.write(
      _key('fmp-test', 'hot'),
      ChartCacheEntry(fetchedAt: _fetchedAt, tracks: const []),
    );

    final entry = await cache.read(_key('fmp-test', 'hot'));
    expect(entry, isNotNull);
    expect(entry!.tracks, isEmpty);
  });

  test('a chart never written is a miss, and charts are told apart', () async {
    final (_, _, cache) = await open();
    await cache.write(
      _key('fmp-test', 'hot'),
      ChartCacheEntry(fetchedAt: _fetchedAt, tracks: _tracks),
    );

    expect(await cache.read(_key('fmp-test', 'new')), isNull);
    expect(await cache.read(_key('other', 'hot')), isNull);
  });

  test('writing again replaces the entry', () async {
    final (_, _, cache) = await open();
    await cache.write(
      _key('fmp-test', 'hot'),
      ChartCacheEntry(fetchedAt: _fetchedAt, tracks: _tracks),
    );

    final later = _fetchedAt.add(const Duration(hours: 1));
    await cache.write(
      _key('fmp-test', 'hot'),
      ChartCacheEntry(fetchedAt: later, tracks: _tracks.take(1).toList()),
    );

    final entry = (await cache.read(_key('fmp-test', 'hot')))!;
    expect(entry.fetchedAt, later);
    expect(entry.tracks, hasLength(1));
  });

  test('remove deletes one chart and keeps the others', () async {
    final (_, _, cache) = await open();
    for (final id in ['hot', 'new']) {
      await cache.write(
        _key('fmp-test', id),
        ChartCacheEntry(fetchedAt: _fetchedAt, tracks: _tracks),
      );
    }

    await cache.remove(_key('fmp-test', 'hot'));

    expect(await cache.read(_key('fmp-test', 'hot')), isNull);
    expect(await cache.read(_key('fmp-test', 'new')), isNotNull);
  });

  test(
    'removePlugin deletes every chart of the plugin, not the others',
    () async {
      final (_, _, cache) = await open();
      for (final (plugin, chart) in [
        ('fmp-test', 'hot'),
        ('fmp-test', 'new'),
        ('other', 'hot'),
      ]) {
        await cache.write(
          _key(plugin, chart),
          ChartCacheEntry(fetchedAt: _fetchedAt, tracks: _tracks),
        );
      }

      await cache.removePlugin('fmp-test');

      expect(await cache.read(_key('fmp-test', 'hot')), isNull);
      expect(await cache.read(_key('fmp-test', 'new')), isNull);
      expect(await cache.read(_key('other', 'hot')), isNotNull);
    },
  );

  test('removing the plugin from the store takes its charts along', () async {
    final (_, store, cache) = await open();
    await cache.write(
      _key('fmp-test', 'hot'),
      ChartCacheEntry(fetchedAt: _fetchedAt, tracks: _tracks),
    );

    await store.removePlugin('fmp-test');

    expect(await cache.read(_key('fmp-test', 'hot')), isNull);
  });

  test('an evicted chart is a miss', () async {
    final (_, _, cache) = await open(limitBytes: 600);
    final entry = ChartCacheEntry(fetchedAt: _fetchedAt, tracks: _tracks);
    await at(1, () => cache.write(_key('fmp-test', 'old'), entry));

    await at(2, () => cache.write(_key('fmp-test', 'new'), entry));

    expect(await cache.read(_key('fmp-test', 'old')), isNull);
    expect(await cache.read(_key('fmp-test', 'new')), isNotNull);
  });

  test('content that cannot be read is a miss, not an error', () async {
    final (_, store, cache) = await open();

    for (final content in [
      'not json',
      '[]',
      '{}',
      '{"fetchedAt": "yesterday", "tracks": []}',
      '{"fetchedAt": 1, "tracks": [{"sourceId": "a"}]}',
    ]) {
      await store.put(
        CacheCategory.chart,
        'fmp-test',
        'chart:fmp-test:hot',
        Uint8List.fromList(utf8.encode(content)),
      );
      expect(
        await cache.read(_key('fmp-test', 'hot')),
        isNull,
        reason: content,
      );
    }
  });

  test('stored format: key, category, plugin and JSON content', () async {
    final (harness, store, cache) = await open();
    await cache.write(
      _key('fmp-test', 'hot'),
      ChartCacheEntry(fetchedAt: _fetchedAt, tracks: _tracks.take(1).toList()),
    );

    final bytes = await store.get(
      CacheCategory.chart,
      'fmp-test',
      'chart:fmp-test:hot',
    );
    final json = jsonDecode(utf8.decode(bytes!)) as Map<String, Object?>;
    expect(json['fetchedAt'], _fetchedAt.millisecondsSinceEpoch);
    final track =
        (json['tracks']! as List<Object?>).single! as Map<String, Object?>;
    expect(track['sourceTypeId'], 'fmp-test');
    expect(track['sourceId'], 'tone-440');
    expect(track['durationMs'], 2000);
    expect(track['cid'], isNull);
    expect(track['viewCount'], 46000000);
    expect(harness.fileNames(), hasLength(1));
  });
}
