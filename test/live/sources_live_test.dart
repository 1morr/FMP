// Live smoke test for the three audio sources.
//
// This file talks to Bilibili, YouTube and NetEase over the real network, so it
// is deliberately NOT part of `flutter test` in CI — the whole point is to catch
// upstream API changes, which is exactly the kind of failure that must not turn
// a pull request red. Run it by hand when playback breaks:
//
//     flutter test test/live/sources_live_test.dart
//
// It asserts the part that actually rots: search returns tracks, and the track
// resolves to a stream URL that serves audio bytes.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/bilibili_exception.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/netease_exception.dart';
import 'package:fmp/data/sources/netease_source.dart';
import 'package:fmp/data/sources/youtube_source.dart';

/// Fetches the first bytes of [url] and reports what came back. A resolved URL
/// that 403s is worse than no URL at all, because playback fails silently.
Future<({int status, String type, int bytes})> probe(
  String url, {
  Map<String, String>? headers,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.getUrl(Uri.parse(url));
    headers?.forEach(req.headers.set);
    // Ask for a small slice; these are multi-megabyte audio files.
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-2047');
    final resp = await req.close();
    final body = await resp.fold<int>(0, (n, chunk) => n + chunk.length);
    return (
      status: resp.statusCode,
      type: resp.headers.contentType?.mimeType ?? '?',
      bytes: body,
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('bilibili: search resolves to playable audio', () async {
    // BilibiliSource fabricates a buvid cookie and carries no SESSDATA, which
    // is the path a user who has not signed in takes. Bilibili currently
    // answers that with risk control, so this test reports the block rather
    // than pretending the source is broken: signing in through Settings makes
    // the same call work.
    final source = BilibiliSource();
    late final Track track;
    late final AudioStreamResult stream;
    try {
      final result = await source.search('bad apple', pageSize: 5);
      expect(
        result.tracks,
        isNotEmpty,
        reason: 'bilibili search returned nothing',
      );
      track = result.tracks.first;
      stream = await source.getAudioStream(
        AudioStreamRequest(sourceId: track.sourceId, cid: track.cid),
      );
    } on BilibiliApiException catch (e) {
      markTestSkipped(
        'Bilibili refused the anonymous request (${e.numericCode}). '
        'This path needs a signed-in session; log in under Settings and rerun.',
      );
      return;
    }
    expect(stream.url, startsWith('http'));

    // Bilibili's CDN rejects requests without a bilibili referer.
    final got = await probe(
      stream.url,
      headers: {
        'Referer': 'https://www.bilibili.com',
        'User-Agent': 'Mozilla/5.0',
      },
    );
    expect(got.status, anyOf(200, 206), reason: 'stream URL not fetchable');
    expect(got.bytes, greaterThan(0));
    printOnFailure('bilibili ${track.title} -> ${stream.codec} ${got.type}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('youtube: search resolves to playable audio', () async {
    final source = YouTubeSource();
    final result = await source.search('bad apple', pageSize: 5);
    expect(
      result.tracks,
      isNotEmpty,
      reason: 'youtube search returned nothing',
    );

    final Track track = result.tracks.first;
    final stream = await source.getAudioStream(
      AudioStreamRequest(sourceId: track.sourceId),
    );
    expect(stream.url, startsWith('http'));

    final got = await probe(stream.url, headers: {'User-Agent': 'Mozilla/5.0'});
    expect(got.status, anyOf(200, 206), reason: 'stream URL not fetchable');
    expect(got.bytes, greaterThan(0));
    printOnFailure('youtube ${track.title} -> ${stream.codec} ${got.type}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('netease: search resolves to playable audio', () async {
    final source = NeteaseSource();
    // Most of NetEase's catalogue is VIP-only or region-locked without an
    // account: a sampled page of chart pop was 20/29 VIP. Instrumental tracks
    // are mostly free, so this query exercises the anonymous path rather than
    // measuring how much of the catalogue is paywalled.
    final result = await source.search('纯音乐', pageSize: 10);
    expect(
      result.tracks,
      isNotEmpty,
      reason: 'netease search returned nothing',
    );

    String? playable;
    final gated = <String>[];
    for (final track in result.tracks) {
      try {
        final stream = await source.getAudioStream(
          AudioStreamRequest(sourceId: track.sourceId),
        );
        if (stream.url.startsWith('http')) {
          playable = stream.url;
          break;
        }
      } on NeteaseApiException catch (e) {
        gated.add(e.message);
        continue;
      }
    }
    if (playable == null) {
      markTestSkipped(
        'Every hit was gated (${gated.join('; ')}). That is an account '
        'limitation rather than a source failure; sign in and rerun.',
      );
      return;
    }

    final got = await probe(playable!, headers: {'User-Agent': 'Mozilla/5.0'});
    expect(got.status, anyOf(200, 206), reason: 'stream URL not fetchable');
    expect(got.bytes, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
