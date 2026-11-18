import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/playback/backends/hls/hls_playlist.dart';

import '../../support/fragmented_mp4.dart';

void main() {
  group('readSegmentIndex', () {
    test('lists each media segment after the index box', () {
      // B 站的排法：init 0-836，sidx 從 837 開始，媒體緊接在 sidx 後面。
      final box = sidxBox(
        sizes: [1000, 2000, 500],
        durations: [240640, 240640, 125952],
      );
      final segments = readSegmentIndex(box, indexOffset: 837);

      final mediaStart = 837 + box.length;
      expect(segments.map((s) => s.range), [
        ByteRange(mediaStart, mediaStart + 999),
        ByteRange(mediaStart + 1000, mediaStart + 2999),
        ByteRange(mediaStart + 3000, mediaStart + 3499),
      ]);
      expect(segments.map((s) => s.duration.inMicroseconds), [
        5013333,
        5013333,
        2624000,
      ]);
    });

    test('reads version 0 and honours first_offset', () {
      final box = sidxBox(
        version: 0,
        timescale: 1000,
        firstOffset: 16,
        sizes: [10],
        durations: [4000],
      );
      final [segment] = readSegmentIndex(box, indexOffset: 100);
      expect(
        segment.range,
        ByteRange(100 + box.length + 16, 100 + box.length + 25),
      );
      expect(segment.duration, const Duration(seconds: 4));
    });

    for (final (name, bytes) in [
      ('not a sidx box', Uint8List.fromList([0, 0, 0, 8, ...'moov'.codeUnits])),
      ('a truncated box', sidxBox(sizes: [1], durations: [1]).sublist(0, 30)),
      (
        'a hierarchical index',
        sidxBox(sizes: [1], durations: [1], referenceType: 1),
      ),
      ('an empty index', sidxBox(sizes: [], durations: [])),
      ('a zero timescale', sidxBox(timescale: 0, sizes: [1], durations: [1])),
    ]) {
      test('$name is a FormatException', () {
        expect(
          () => readSegmentIndex(bytes, indexOffset: 0),
          throwsFormatException,
        );
      });
    }
  });

  test('reads the index of a file shaped like a Bilibili audio track', () {
    final file = FragmentedMp4(fragments: 30);
    final index = file.segmentBase.index;
    final segments = readSegmentIndex(
      Uint8List.sublistView(file.bytes, index.first, index.last + 1),
      indexOffset: index.first,
    );

    expect(segments, hasLength(30));
    expect(segments.last.range.last, file.bytes.length - 1);
    final total = segments.fold(Duration.zero, (sum, s) => sum + s.duration);
    expect(
      (total - file.duration).abs(),
      lessThan(const Duration(milliseconds: 1)),
    );
  });

  group('hlsPlaylist', () {
    test('describes the file as byte ranges of one URL', () {
      final url = Uri.parse('https://cdn.example.com/a.m4s?deadline=1&sig=x');
      final playlist = hlsPlaylist(
        url: url,
        initialization: const ByteRange(0, 836),
        segments: const [
          MediaSegment(
            ByteRange(9433, 114930),
            Duration(microseconds: 5013333),
          ),
          MediaSegment(
            ByteRange(114931, 204113),
            Duration(microseconds: 2624000),
          ),
        ],
      );

      expect(playlist.split('\n'), [
        '#EXTM3U',
        '#EXT-X-VERSION:7',
        '#EXT-X-TARGETDURATION:5',
        '#EXT-X-PLAYLIST-TYPE:VOD',
        '#EXT-X-INDEPENDENT-SEGMENTS',
        '#EXT-X-MAP:URI="$url",BYTERANGE="837@0"',
        '#EXTINF:5.013333,',
        '#EXT-X-BYTERANGE:105498@9433',
        '$url',
        '#EXTINF:2.624000,',
        '#EXT-X-BYTERANGE:89183@114931',
        '$url',
        '#EXT-X-ENDLIST',
        '',
      ]);
    });

    test('the target duration rounds the longest segment', () {
      // RFC 8216 §4.3.3.1：每段的 EXTINF 四捨五入後不得超過它。
      final playlist = hlsPlaylist(
        url: Uri.parse('https://a.example/x'),
        initialization: const ByteRange(0, 1),
        segments: const [
          MediaSegment(ByteRange(2, 3), Duration(milliseconds: 5600)),
        ],
      );
      expect(playlist, contains('#EXT-X-TARGETDURATION:6\n'));
    });
  });
}
