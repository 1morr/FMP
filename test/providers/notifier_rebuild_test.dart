import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/download/file_exists_cache.dart';
import 'package:fmp/providers/lyrics/lyrics_provider.dart';
import 'package:fmp/services/audio/queue_state.dart';

/// Riverpod 3 的 `Notifier` 與被它取代的 `StateNotifier` 有一個靜默的語意差：
/// `build()` 重跑時**實例會被保留**（`notifier/orphan.dart` 明文），而
/// `StateNotifierProvider((ref) => X(ref.watch(y)))` 是整個重建。所以每一批
/// 改寫都要有一條「重建之後狀態與副作用都還對」的測試，否則漏改只會表現成
/// 洩漏或殘留，不會有錯誤訊息。
void main() {
  group('state providers rewritten as Notifier', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('queueStateProvider starts empty and takes a published projection',
        () {
      expect(container.read(queueStateProvider), const QueueState());

      final projection = QueueState(
        queue: [Track()..title = 'one'],
        queueVersion: 1,
      );
      container.read(queueStateProvider.notifier).publish(projection);
      expect(container.read(queueStateProvider), same(projection));

      // 重建回到初始值 —— 投影的唯一真相在 AudioController，provider 不留舊值。
      container.invalidate(queueStateProvider);
      expect(container.read(queueStateProvider), const QueueState());
    });

    test('lyricsAutoMatchingProvider flips through its named setter', () {
      expect(container.read(lyricsAutoMatchingProvider), isFalse);

      container.read(lyricsAutoMatchingProvider.notifier).setMatching(true);
      expect(container.read(lyricsAutoMatchingProvider), isTrue);

      container.invalidate(lyricsAutoMatchingProvider);
      expect(container.read(lyricsAutoMatchingProvider), isFalse);
    });

    test('fileExistsCacheEpochProvider mirrors the cache epoch', () {
      expect(container.read(fileExistsCacheEpochProvider), 0);

      container.read(fileExistsCacheEpochProvider.notifier).set(7);
      expect(container.read(fileExistsCacheEpochProvider), 7);

      container.invalidate(fileExistsCacheEpochProvider);
      expect(container.read(fileExistsCacheEpochProvider), 0);
    });
  });
}
