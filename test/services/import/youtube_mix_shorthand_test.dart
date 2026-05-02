import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/import/youtube_mix_shorthand.dart';

void main() {
  group('YouTube Mix shorthand', () {
    test('parses lowercase, uppercase, and whitespace padded shorthand', () {
      expect(parseYouTubeMixShorthandSeedId('mix:dvgZkm1xWPE'), 'dvgZkm1xWPE');
      expect(parseYouTubeMixShorthandSeedId('MIX:dvgZkm1xWPE'), 'dvgZkm1xWPE');
      expect(parseYouTubeMixShorthandSeedId('  mix:dvgZkm1xWPE  '), 'dvgZkm1xWPE');
      expect(parseYouTubeMixShorthandSeedId('mix: dvgZkm1xWPE'), 'dvgZkm1xWPE');
    });

    test('rejects empty, invalid character, and overly long seeds', () {
      expect(looksLikeYouTubeMixShorthand('mix:'), isTrue);
      expect(parseYouTubeMixShorthandSeedId('mix:'), isNull);
      expect(parseYouTubeMixShorthandSeedId('mix:dvgZkm1xWPE!'), isNull);
      expect(parseYouTubeMixShorthandSeedId('mix:${'a' * 65}'), isNull);
      expect(parseYouTubeMixShorthandSeedId('https://www.youtube.com/watch?v=dvgZkm1xWPE'), isNull);
    });

    test('normalizes valid shorthand to a YouTube Mix URL', () {
      expect(
        normalizeYouTubeMixShorthandUrl(' MIX:dvgZkm1xWPE '),
        'https://www.youtube.com/watch?v=dvgZkm1xWPE&list=RDdvgZkm1xWPE',
      );
      expect(normalizeYouTubeMixShorthandUrl('mix:dvgZkm1xWPE!'), isNull);
    });
  });
}
