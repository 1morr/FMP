import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/network_image_cache_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('NetworkImageCacheFileStore', () {
    late Directory tempDir;
    late NetworkImageCacheFileStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fmp_image_cache_test_');
      store = NetworkImageCacheFileStore.forTesting(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<File> writeFile(String name, int byteCount) {
      return File(p.join(tempDir.path, name))
          .writeAsBytes(List<int>.filled(byteCount, 1));
    }

    test('scan returns total size sorted by oldest first', () async {
      final oldFile = await writeFile('old.bin', 10);
      final newFile = await writeFile('new.bin', 20);
      await oldFile.setLastModified(DateTime(2024));
      await newFile.setLastModified(DateTime(2025));

      final scan = await store.scan();

      expect(scan.totalSize, 30);
      expect(scan.files.map((f) => f.path), [oldFile.path, newFile.path]);
    });

    test('deleteOldestToFit removes oldest files until under max size',
        () async {
      final oldest = await writeFile('oldest.bin', 10);
      final middle = await writeFile('middle.bin', 20);
      final newest = await writeFile('newest.bin', 30);
      await oldest.setLastModified(DateTime(2023));
      await middle.setLastModified(DateTime(2024));
      await newest.setLastModified(DateTime(2025));

      final remainingSize = await store.deleteOldestToFit(35);

      expect(await oldest.exists(), isFalse);
      expect(await middle.exists(), isFalse);
      expect(await newest.exists(), isTrue);
      expect(remainingSize, 30);
    });

    test('clear deletes files recursively', () async {
      await writeFile('root.bin', 10);
      final nested = Directory(p.join(tempDir.path, 'nested'));
      await nested.create();
      await File(p.join(nested.path, 'nested.bin'))
          .writeAsBytes(List<int>.filled(10, 1));

      await store.clear();

      expect(await tempDir.exists(), isTrue);
      expect(
        await tempDir
            .list(recursive: true)
            .where((entity) => entity is File)
            .isEmpty,
        isTrue,
      );
    });
  });
}
