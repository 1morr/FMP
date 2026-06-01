import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/lyrics/lyrics_provider.dart';
import 'package:fmp/services/lyrics/lrc_parser.dart';

void main() {
  group('current lyrics line index provider support', () {
    test('calculateCurrentLyricsLineIndex changes only at lyric boundaries',
        () {
      const lyrics = ParsedLyrics(
        isSynced: true,
        lines: [
          LyricsLine(timestamp: Duration(seconds: 1), text: 'first'),
          LyricsLine(timestamp: Duration(seconds: 5), text: 'second'),
          LyricsLine(timestamp: Duration(seconds: 9), text: 'third'),
        ],
      );

      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: const Duration(milliseconds: 500),
          offsetMs: 0,
        ),
        -1,
      );
      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: const Duration(seconds: 2),
          offsetMs: 0,
        ),
        0,
      );
      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: const Duration(seconds: 4),
          offsetMs: 0,
        ),
        0,
      );
      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: const Duration(seconds: 5),
          offsetMs: 0,
        ),
        1,
      );
    });

    test('calculateCurrentLyricsLineIndex applies offset', () {
      const lyrics = ParsedLyrics(
        isSynced: true,
        lines: [
          LyricsLine(timestamp: Duration(seconds: 3), text: 'line'),
        ],
      );

      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: const Duration(seconds: 2),
          offsetMs: 1000,
        ),
        0,
      );
    });

    test('calculateOffsetForLine aligns clicked line start to current position',
        () {
      const line = LyricsLine(
        timestamp: Duration(seconds: 5),
        text: 'clicked',
      );

      expect(
        LrcParser.calculateOffsetForLine(
          line,
          const Duration(milliseconds: 7250),
        ),
        -2250,
      );
    });

    test('calculated offset selects clicked previous or next lyric line', () {
      const lyrics = ParsedLyrics(
        isSynced: true,
        lines: [
          LyricsLine(timestamp: Duration(seconds: 1), text: 'first'),
          LyricsLine(timestamp: Duration(seconds: 5), text: 'second'),
          LyricsLine(timestamp: Duration(seconds: 9), text: 'third'),
        ],
      );
      const position = Duration(milliseconds: 7250);

      final previousOffset = LrcParser.calculateOffsetForLine(
        lyrics.lines[1],
        position,
      );
      expect(previousOffset, -2250);
      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: position,
          offsetMs: previousOffset,
        ),
        1,
      );

      final nextOffset = LrcParser.calculateOffsetForLine(
        lyrics.lines[2],
        position,
      );
      expect(nextOffset, 1750);
      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: position,
          offsetMs: nextOffset,
        ),
        2,
      );
    });

    test('LyricsDisplay consumes line index provider instead of raw position',
        () {
      final source =
          File('lib/ui/widgets/lyrics/lyrics_display.dart').readAsStringSync();

      expect(source, contains('currentLyricsLineIndexProvider'));
      expect(
        source,
        isNot(contains('audioControllerProvider.select((s) => s.position)')),
      );
    });
  });
}
