import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/download_task.dart';
import 'package:fmp/services/download/download_service.dart';

void main() {
  group('DownloadProgressEvent', () {
    test('creates event with all required fields', () {
      final event = DownloadProgressEvent(
        taskId: 1,
        trackId: 100,
        progress: 0.5,
        downloadedBytes: 1024 * 1024,
        totalBytes: 2 * 1024 * 1024,
      );

      expect(event.taskId, equals(1));
      expect(event.trackId, equals(100));
      expect(event.progress, equals(0.5));
      expect(event.downloadedBytes, equals(1024 * 1024));
      expect(event.totalBytes, equals(2 * 1024 * 1024));
    });

    test('allows null totalBytes', () {
      final event = DownloadProgressEvent(
        taskId: 1,
        trackId: 100,
        progress: 0.0,
        downloadedBytes: 0,
      );

      expect(event.totalBytes, isNull);
    });
  });

  group('DownloadTask status checks', () {
    test('isCompleted returns true for completed status', () {
      final task = DownloadTask()
        ..trackId = 1
        ..status = DownloadStatus.completed
        ..createdAt = DateTime.now();

      expect(task.isCompleted, isTrue);
    });

    test('isFailed returns true for failed status', () {
      final task = DownloadTask()
        ..trackId = 1
        ..status = DownloadStatus.failed
        ..createdAt = DateTime.now();

      expect(task.isFailed, isTrue);
    });

    test('isDownloading returns true for downloading status', () {
      final task = DownloadTask()
        ..trackId = 1
        ..status = DownloadStatus.downloading
        ..createdAt = DateTime.now();

      expect(task.isDownloading, isTrue);
    });

    test('isPending returns true for pending status', () {
      final task = DownloadTask()
        ..trackId = 1
        ..status = DownloadStatus.pending
        ..createdAt = DateTime.now();

      expect(task.isPending, isTrue);
    });

    test('isPaused returns true for paused status', () {
      final task = DownloadTask()
        ..trackId = 1
        ..status = DownloadStatus.paused
        ..createdAt = DateTime.now();

      expect(task.isPaused, isTrue);
    });
  });

  group('DownloadTask progress tracking', () {
    test('calculates progress percentage correctly', () {
      final task = DownloadTask()
        ..trackId = 1
        ..status = DownloadStatus.downloading
        ..progress = 0.75
        ..downloadedBytes = 7500000
        ..totalBytes = 10000000
        ..createdAt = DateTime.now();

      expect(task.progress, equals(0.75));
      expect(task.downloadedBytes, equals(7500000));
      expect(task.totalBytes, equals(10000000));
    });

    test('handles zero progress', () {
      final task = DownloadTask()
        ..trackId = 1
        ..status = DownloadStatus.pending
        ..progress = 0.0
        ..downloadedBytes = 0
        ..createdAt = DateTime.now();

      expect(task.progress, equals(0.0));
      expect(task.downloadedBytes, equals(0));
    });
  });
}
