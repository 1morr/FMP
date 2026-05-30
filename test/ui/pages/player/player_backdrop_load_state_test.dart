import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/pages/player/player_page.dart';

void main() {
  group('PlayerBackdropLoadState', () {
    test('keeps failed requests marked until the source key changes', () {
      final state = PlayerBackdropLoadState();

      state.updateDesiredKey('network:bad-cover');
      expect(
        state.shouldRequest(
          'network:bad-cover',
          hasCandidates: true,
        ),
        isTrue,
      );

      final generation = state.markRequested('network:bad-cover');
      expect(
        state.shouldRequest(
          'network:bad-cover',
          hasCandidates: true,
        ),
        isFalse,
      );

      state.markFailed('network:bad-cover', generation);
      expect(state.requestedKey, 'network:bad-cover');
      expect(
        state.shouldRequest(
          'network:bad-cover',
          hasCandidates: true,
        ),
        isFalse,
      );

      state.updateDesiredKey('network:next-cover');
      expect(state.requestedKey, isNull);
      expect(
        state.shouldRequest(
          'network:next-cover',
          hasCandidates: true,
        ),
        isTrue,
      );
    });
  });
}
