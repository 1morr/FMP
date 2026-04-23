import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_history.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/providers/play_history_provider.dart';
import 'package:fmp/providers/repository_providers.dart';
import 'package:isar/isar.dart';

void main() {
  group('Phase 4 Task 4 play history providers', () {
    test('play history providers expose a shared snapshot provider', () {
      final source = playHistorySnapshotProvider;
      expect(source, isA<AutoDisposeStreamProvider<List<PlayHistory>>>());
    });

    test('recent history and stats derive from one shared snapshot stream', () async {
      final repository = _FakePlayHistoryRepository([
        _history(
          id: 1,
          sourceId: 'song-a',
          title: 'Song A latest',
          playedAt: DateTime(2026, 4, 20, 12),
        ),
        _history(
          id: 2,
          sourceId: 'song-a',
          title: 'Song A older',
          playedAt: DateTime(2026, 4, 20, 9),
        ),
        _history(
          id: 3,
          sourceId: 'song-b',
          title: 'Song B',
          playedAt: DateTime(2026, 4, 19, 18),
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          playHistoryRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(playHistorySnapshotProvider.future);
      final recent = container.read(recentPlayHistoryProvider).requireValue;
      final stats = container.read(playHistoryStatsProvider).requireValue;
      final grouped = container.read(groupedPlayHistoryProvider).requireValue;

      expect(repository.snapshotCalls, 1);
      expect(recent.map((e) => e.sourceId).toList(), ['song-a', 'song-b']);
      expect(stats.totalCount, 3);
      expect(grouped.keys, [DateTime(2026, 4, 20), DateTime(2026, 4, 19)]);
    });
  });
}

class _FakePlayHistoryRepository extends PlayHistoryRepository {
  _FakePlayHistoryRepository(this.records) : super(_FakeIsar());

  final List<PlayHistory> records;
  int snapshotCalls = 0;

  @override
  Future<List<PlayHistory>> loadHistorySnapshot({
    Set<SourceType>? sourceTypes,
    DateTime? startDate,
    DateTime? endDate,
    String? searchKeyword,
  }) async {
    snapshotCalls++;
    var filtered = List<PlayHistory>.from(records);

    if (sourceTypes != null && sourceTypes.isNotEmpty) {
      filtered = filtered.where((e) => sourceTypes.contains(e.sourceType)).toList();
    }
    if (startDate != null) {
      filtered = filtered
          .where((e) =>
              e.playedAt.isAfter(startDate) ||
              e.playedAt.isAtSameMomentAs(startDate))
          .toList();
    }
    if (endDate != null) {
      filtered = filtered.where((e) => e.playedAt.isBefore(endDate)).toList();
    }
    if (searchKeyword != null && searchKeyword.isNotEmpty) {
      final lower = searchKeyword.toLowerCase();
      filtered = filtered
          .where((e) =>
              e.title.toLowerCase().contains(lower) ||
              (e.artist?.toLowerCase().contains(lower) ?? false))
          .toList();
    }

    filtered.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return filtered;
  }

  @override
  Stream<void> watchHistory() => const Stream<void>.empty();
}

class _FakeIsar extends Fake implements Isar {}

PlayHistory _history({
  required int id,
  required String sourceId,
  required String title,
  required DateTime playedAt,
}) {
  return PlayHistory()
    ..id = id
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = title
    ..playedAt = playedAt;
}
