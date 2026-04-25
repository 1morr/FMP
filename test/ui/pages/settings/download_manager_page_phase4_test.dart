import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 4 Task 2 download manager page', () {
    late String repoRoot;

    setUp(() {
      repoRoot = Directory.current.path;
    });

    test('download manager tile uses nullable task-scoped progress fallback',
        () {
      final source = File(
        '$repoRoot/lib/ui/pages/settings/download_manager_page.dart',
      ).readAsStringSync();

      expect(
          source, contains('ref.watch(downloadTaskProgressProvider(task.id))'));
      expect(
          source, isNot(contains('ref.watch(downloadProgressStateProvider)')));
      expect(source, contains('memProgress ??'));
      expect(source, contains('task.progress'));
      expect(source, contains('task.downloadedBytes'));
      expect(source, contains('task.totalBytes'));
      expect(
        source,
        isNot(
          contains(
            r'memProgress.$1 > 0 || memProgress.$2 > 0 || memProgress.$3 != null',
          ),
        ),
      );
    });

    test('download manager uses flattened builder rows for task sections', () {
      final source = File(
        '$repoRoot/lib/ui/pages/settings/download_manager_page.dart',
      ).readAsStringSync();

      expect(source, contains('class _DownloadListRow'));
      expect(source, contains('ListView.builder'));
      expect(source, contains('_buildRows('));
      expect(source, contains('_DownloadListRow.header'));
      expect(source, contains('_DownloadListRow.fixedDownloadingSection'));
      expect(source, contains('_DownloadListRow.task'));
      expect(
          source, isNot(contains('return ListView(\n            children:')));
      expect(source, isNot(contains('...pending.map')));
      expect(source, isNot(contains('...paused.map')));
      expect(source, isNot(contains('...failed.map')));
      expect(source, isNot(contains('...completed.map')));
    });
  });
}
