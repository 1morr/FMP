import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/lyrics_provider.dart';
import 'package:fmp/services/lyrics/lrc_parser.dart';

void main() {
  group('current lyrics line index provider support', () {
    test('calculateCurrentLyricsLineIndex changes only at lyric boundaries',
        () {
      final lyrics = ParsedLyrics(
        isSynced: true,
        lines: const [
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
      final lyrics = ParsedLyrics(
        isSynced: true,
        lines: const [
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

    test('LyricsDisplay consumes line index provider instead of raw position',
        () {
      final source =
          File('lib/ui/widgets/lyrics_display.dart').readAsStringSync();

      expect(source, contains('currentLyricsLineIndexProvider'));
      expect(
        source,
        isNot(contains('audioControllerProvider.select((s) => s.position)')),
      );
    });
  });
}
