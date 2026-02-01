import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/download/download_scanner.dart';
import 'dart:io';

/// Performance benchmark tests for startup and initialization operations.
///
/// These tests measure execution time of critical operations.
/// Run with: flutter test test/performance/startup_benchmark_test.dart
void main() {
  group('Startup Performance Benchmarks', () {
    test('Track model creation performance', () async {
      final stopwatch = Stopwatch()..start();

      // Create 1000 tracks to measure model creation overhead
      final tracks = List.generate(1000, (i) {
        return Track()
          ..sourceId = 'BV${i.toString().padLeft(10, '0')}'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track $i - A Long Title That Might Be Common'
          ..artist = 'Test Artist $i'
          ..durationMs = Duration(minutes: 3, seconds: 30).inMilliseconds
          ..thumbnailUrl = 'https://example.com/thumb/$i.jpg'
          ..audioUrl = 'https://example.com/audio/$i.m4a'
          ..createdAt = DateTime.now()
          ..updatedAt = DateTime.now();
      });

      stopwatch.stop();

      // Log performance results
      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('Created ${tracks.length} Track models in ${elapsed}ms');
      // ignore: avoid_print
      print('Average: ${elapsed / tracks.length}ms per track');

      // Assert reasonable performance (should be < 100ms for 1000 tracks)
      expect(elapsed, lessThan(1000),
          reason: 'Track creation should complete in under 1 second');
    });

    test('Display name extraction performance', () async {
      final testCases = [
        'Artist Name - Song Title',
        '【Original Song】Artist - Title【MV】',
        '[Cover] Someone - Some Song',
        'Plain Title Without Delimiter',
        '超长的标题可能包含很多字符和特殊符号《》【】',
      ];

      final stopwatch = Stopwatch()..start();

      // Run extraction 10000 times
      for (var i = 0; i < 10000; i++) {
        for (final testCase in testCases) {
          DownloadScanner.extractDisplayName(testCase);
        }
      }

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      final totalOperations = 10000 * testCases.length;
      // ignore: avoid_print
      print('Extracted display names $totalOperations times in ${elapsed}ms');
      // ignore: avoid_print
      print(
          'Average: ${(elapsed * 1000 / totalOperations).toStringAsFixed(3)}μs per extraction');

      // Assert reasonable performance
      expect(elapsed, lessThan(5000),
          reason: 'Display name extraction should be fast');
    });

    test('DateTime parsing and formatting performance', () async {
      final now = DateTime.now();
      final timestamps = List.generate(1000, (i) {
        return now.subtract(Duration(days: i, hours: i % 24, minutes: i % 60));
      });

      final stopwatch = Stopwatch()..start();

      // Simulate common date operations
      for (var i = 0; i < 100; i++) {
        for (final timestamp in timestamps) {
          // Common operations in the app
          timestamp.toIso8601String();
          timestamp.difference(now).inDays;
          timestamp.millisecondsSinceEpoch;
        }
      }

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('Performed ${100 * timestamps.length * 3} date operations in ${elapsed}ms');

      expect(elapsed, lessThan(2000),
          reason: 'Date operations should be fast');
    });

    test('String operations performance (title truncation, etc)', () async {
      final titles = List.generate(500, (i) {
        return 'This is a very long track title that might need to be truncated for display purposes - Track Number $i with extra text';
      });

      final stopwatch = Stopwatch()..start();

      for (var iteration = 0; iteration < 1000; iteration++) {
        for (final title in titles) {
          // Common string operations
          if (title.length > 50) {
            title.substring(0, 50);
          }
          title.toLowerCase();
          title.contains('track');
          title.split(' ');
        }
      }

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print(
          'Performed ${1000 * titles.length * 4} string operations in ${elapsed}ms');

      expect(elapsed, lessThan(3000),
          reason: 'String operations should be fast');
    });
  });

  group('File System Performance Benchmarks', () {
    test('Directory existence check performance', () async {
      final tempDir = Directory.systemTemp;
      final testPaths = List.generate(100, (i) {
        return Directory('${tempDir.path}/nonexistent_$i');
      });

      final stopwatch = Stopwatch()..start();

      for (var i = 0; i < 100; i++) {
        for (final dir in testPaths) {
          await dir.exists();
        }
      }

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('Checked ${100 * testPaths.length} directory existence in ${elapsed}ms');

      // File system operations are inherently slower
      expect(elapsed, lessThan(10000),
          reason: 'Directory checks should complete reasonably');
    });

    test('Path manipulation performance', () async {
      final basePath = Directory.systemTemp.path;
      final segments = ['music', 'downloads', 'artist', 'album', 'track.mp3'];

      final stopwatch = Stopwatch()..start();

      for (var i = 0; i < 100000; i++) {
        // Path joining
        segments.join(Platform.pathSeparator);
        // Path parsing
        '$basePath${Platform.pathSeparator}${segments.join(Platform.pathSeparator)}'
            .split(Platform.pathSeparator);
      }

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // ignore: avoid_print
      print('Performed ${100000 * 2} path operations in ${elapsed}ms');

      expect(elapsed, lessThan(2000),
          reason: 'Path operations should be very fast');
    });
  });
}
