import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/audio/audio_provider.dart';

void main() {
  group('MixSessionStateHelper Task 3 regression', () {
    test('start sets current session and clear removes active ownership', () {
      final helper = MixSessionStateTestHarness();

      final firstSession = helper.start(
        playlistId: 'RDmix-1',
        seedVideoId: 'seed-1',
        title: 'First Mix',
      );

      expect(helper.current, isNotNull);
      expect(helper.current?.playlistId, 'RDmix-1');
      expect(helper.current?.seedVideoId, 'seed-1');
      expect(helper.current?.title, 'First Mix');
      expect(helper.current?.isLoadingMore, isFalse);
      expect(helper.isCurrent(firstSession), isTrue);

      helper.clear();

      expect(helper.current, isNull);
      expect(helper.isCurrent(firstSession), isFalse);
    });

    test('markLoading only activates current session and rejects stale or already-loading sessions', () {
      final helper = MixSessionStateTestHarness();

      final staleSession = helper.start(
        playlistId: 'RDmix-stale',
        seedVideoId: 'seed-stale',
        title: 'Stale Mix',
      );
      final activeSession = helper.start(
        playlistId: 'RDmix-active',
        seedVideoId: 'seed-active',
        title: 'Active Mix',
      );

      expect(helper.isCurrent(staleSession), isFalse);
      expect(helper.isCurrent(activeSession), isTrue);
      expect(helper.sessionOf(staleSession)?.isLoadingMore, isFalse);
      expect(helper.sessionOf(activeSession)?.isLoadingMore, isFalse);

      expect(helper.markLoading(staleSession), isFalse);
      expect(helper.sessionOf(staleSession)?.isLoadingMore, isFalse);
      expect(helper.current?.isLoadingMore, isFalse);

      expect(helper.markLoading(activeSession), isTrue);
      expect(helper.sessionOf(activeSession)?.isLoadingMore, isTrue);
      expect(helper.current?.isLoadingMore, isTrue);

      expect(helper.markLoading(activeSession), isFalse);
      expect(helper.sessionOf(activeSession)?.isLoadingMore, isTrue);
    });

    test('stale loading session cannot affect ownership or loading after clear and replacement', () {
      final helper = MixSessionStateTestHarness();

      final staleSession = helper.start(
        playlistId: 'RDmix-old',
        seedVideoId: 'seed-old',
        title: 'Old Mix',
      );

      expect(helper.markLoading(staleSession), isTrue);
      expect(helper.isCurrent(staleSession), isTrue);
      expect(helper.current?.playlistId, 'RDmix-old');
      expect(helper.current?.isLoadingMore, isTrue);

      helper.clear();

      expect(helper.current, isNull);
      expect(helper.isCurrent(staleSession), isFalse);
      expect(helper.markLoading(staleSession), isFalse);
      expect(helper.sessionOf(staleSession)?.isLoadingMore, isTrue);

      final activeSession = helper.start(
        playlistId: 'RDmix-new',
        seedVideoId: 'seed-new',
        title: 'New Mix',
      );

      expect(helper.isCurrent(staleSession), isFalse);
      expect(helper.isCurrent(activeSession), isTrue);
      expect(helper.current?.playlistId, 'RDmix-new');
      expect(helper.current?.isLoadingMore, isFalse);

      expect(helper.markLoading(staleSession), isFalse);
      expect(helper.current?.playlistId, 'RDmix-new');
      expect(helper.current?.isLoadingMore, isFalse);

      expect(helper.markLoading(activeSession), isTrue);
      expect(helper.current?.playlistId, 'RDmix-new');
      expect(helper.current?.isLoadingMore, isTrue);
    });
  });
}
