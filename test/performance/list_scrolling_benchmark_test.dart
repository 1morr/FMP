import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';

/// Performance benchmark tests for list scrolling and widget rendering.
///
/// These tests measure UI rendering performance with large data sets.
/// Run with: flutter test test/performance/list_scrolling_benchmark_test.dart
void main() {
  group('List Rendering Performance', () {
    /// Generate test tracks for benchmarking
    List<Track> generateTracks(int count) {
      return List.generate(count, (i) {
        return Track()
          ..sourceId = 'BV${i.toString().padLeft(10, '0')}'
          ..sourceType = SourceType.bilibili
          ..title = 'Track $i - Test Song Title'
          ..artist = 'Artist $i'
          ..durationMs = (180 + (i % 300)) * 1000
          ..thumbnailUrl = 'https://example.com/thumb/$i.jpg';
      });
    }

    testWidgets('Render 100 track list items', (tester) async {
      final tracks = generateTracks(100);

      final stopwatch = Stopwatch()..start();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    color: Colors.grey,
                  ),
                  title: Text(track.title ?? ''),
                  subtitle: Text(track.artist ?? ''),
                  trailing: Text(track.formattedDuration),
                );
              },
            ),
          ),
        ),
      );

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('Initial render of 100 items: ${elapsed}ms');

      expect(elapsed, lessThan(5000),
          reason: 'Initial render should be fast');

      // Verify list rendered correctly
      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('Render 500 track list items', (tester) async {
      final tracks = generateTracks(500);

      final stopwatch = Stopwatch()..start();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    color: Colors.grey,
                  ),
                  title: Text(track.title ?? ''),
                  subtitle: Text(track.artist ?? ''),
                );
              },
            ),
          ),
        ),
      );

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('Initial render of 500 items: ${elapsed}ms');

      // ListView.builder should handle large lists efficiently
      expect(elapsed, lessThan(5000),
          reason: 'ListView.builder should virtualize efficiently');
    });

    testWidgets('Scroll performance with 1000 items', (tester) async {
      final tracks = generateTracks(1000);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              key: const Key('track_list'),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return ListTile(
                  key: Key('track_$index'),
                  leading: Container(
                    width: 48,
                    height: 48,
                    color: Colors.grey,
                  ),
                  title: Text(track.title ?? ''),
                  subtitle: Text(track.artist ?? ''),
                );
              },
            ),
          ),
        ),
      );

      // Let initial frame settle
      await tester.pump();

      final stopwatch = Stopwatch()..start();

      // Simulate scrolling
      final listFinder = find.byKey(const Key('track_list'));
      expect(listFinder, findsOneWidget);

      // Scroll down multiple times
      for (var i = 0; i < 10; i++) {
        await tester.drag(listFinder, const Offset(0, -500));
        await tester.pump();
      }

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('10 scroll operations with 1000 items: ${elapsed}ms');
      // ignore: avoid_print
      print('Average: ${elapsed / 10}ms per scroll');

      expect(elapsed, lessThan(5000),
          reason: 'Scrolling should be smooth');
    });

    testWidgets('Complex list item rendering', (tester) async {
      final tracks = generateTracks(100);

      final stopwatch = Stopwatch()..start();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                // Simulate more complex list item (similar to actual app)
                return InkWell(
                  onTap: () {},
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      children: [
                        // Rank number
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        // Thumbnail placeholder
                        Container(
                          width: 64,
                          height: 64,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        // Track info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                track.artist ?? '',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Duration
                        Text(track.formattedDuration),
                        // Menu button
                        IconButton(
                          icon: const Icon(Icons.more_vert),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('Complex list item render (100 items): ${elapsed}ms');

      expect(elapsed, lessThan(5000),
          reason: 'Complex items should still render efficiently');
    });
  });

  group('Widget Build Performance', () {
    testWidgets('Repeated widget rebuilds', (tester) async {
      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              buildCount++;
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: Text('Builds: $buildCount'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      final stopwatch = Stopwatch()..start();

      // Trigger 100 rebuilds
      for (var i = 0; i < 100; i++) {
        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();
      }

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('100 widget rebuilds: ${elapsed}ms');
      // ignore: avoid_print
      print('Average: ${elapsed / 100}ms per rebuild');

      expect(buildCount, equals(101)); // Initial + 100 taps
      expect(elapsed, lessThan(5000),
          reason: 'Rebuilds should be fast');
    });
  });

  group('Data Processing Performance', () {
    test('Track filtering performance', () {
      final tracks = List.generate(10000, (i) {
        return Track()
          ..sourceId = 'BV${i.toString().padLeft(10, '0')}'
          ..sourceType = i % 3 == 0 ? SourceType.bilibili : SourceType.youtube
          ..title = i % 2 == 0 ? 'Even Track $i' : 'Odd Track $i'
          ..artist = 'Artist ${i % 100}'
          ..durationMs = (180 + (i % 300)) * 1000;
      });

      final stopwatch = Stopwatch()..start();

      // Filter by source
      final bilibiliTracks =
          tracks.where((t) => t.sourceType == SourceType.bilibili).toList();
      final youtubeTracks =
          tracks.where((t) => t.sourceType == SourceType.youtube).toList();

      // Filter by title
      final evenTracks =
          tracks.where((t) => t.title?.contains('Even') ?? false).toList();

      // Sort by duration
      final sortedByDuration = List<Track>.from(tracks)
        ..sort((a, b) => (a.durationMs ?? 0).compareTo(b.durationMs ?? 0));

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('Filtered and sorted 10000 tracks in ${elapsed}ms');
      // ignore: avoid_print
      print('Bilibili: ${bilibiliTracks.length}, YouTube: ${youtubeTracks.length}');
      // ignore: avoid_print
      print('Even tracks: ${evenTracks.length}');
      // ignore: avoid_print
      print('Sorted tracks: ${sortedByDuration.length}');

      expect(elapsed, lessThan(1000),
          reason: 'Filtering/sorting should be fast');
    });

    test('Track search/matching performance', () {
      final tracks = List.generate(5000, (i) {
        return Track()
          ..sourceId = 'BV${i.toString().padLeft(10, '0')}'
          ..sourceType = SourceType.bilibili
          ..title = 'Track $i - ${['Rock', 'Pop', 'Jazz', 'Classical'][i % 4]} Music'
          ..artist = 'Artist ${['Alpha', 'Beta', 'Gamma', 'Delta'][i % 4]}';
      });

      final searchTerms = ['Rock', 'Pop', 'Alpha', 'Track 100', 'Music'];

      final stopwatch = Stopwatch()..start();

      for (var iteration = 0; iteration < 100; iteration++) {
        for (final term in searchTerms) {
          final termLower = term.toLowerCase();
          tracks.where((t) {
            final title = t.title?.toLowerCase() ?? '';
            final artist = t.artist?.toLowerCase() ?? '';
            return title.contains(termLower) || artist.contains(termLower);
          }).toList();
        }
      }

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('${100 * searchTerms.length} searches on 5000 tracks: ${elapsed}ms');

      expect(elapsed, lessThan(3000),
          reason: 'Search operations should be efficient');
    });
  });
}
