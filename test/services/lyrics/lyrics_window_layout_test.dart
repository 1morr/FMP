import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/lyrics_window_style.dart';

void main() {
  group('LyricsWindowLayout', () {
    test('minimum window width leaves room for title bar controls', () {
      expect(LyricsWindowLayout.minWindowWidth, greaterThanOrEqualTo(400));
    });
  });
}
