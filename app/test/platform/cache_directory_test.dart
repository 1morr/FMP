import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/cache_directory/cache_directory.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory platformCache;

  setUp(() {
    platformCache = Directory.systemTemp.createTempSync('fmp_cache_dir_');
    addTearDown(() => platformCache.deleteSync(recursive: true));
  });

  test('resolves to fmp_cache under the platform cache directory', () async {
    final directory = await CacheDirectory(
      applicationCachePath: () async => platformCache.path,
    ).resolve();

    expect(
      p.equals(directory.path, p.join(platformCache.path, 'fmp_cache')),
      isTrue,
    );
    expect(directory.existsSync(), isTrue);
  });

  test(
    'creates the platform cache directory when the system removed it',
    () async {
      // Android 可能整個清掉 getCacheDir()。
      final removed = p.join(platformCache.path, 'gone');

      final directory = await CacheDirectory(
        applicationCachePath: () async => removed,
      ).resolve();

      expect(directory.existsSync(), isTrue);
      expect(p.isWithin(removed, directory.path), isTrue);
    },
  );
}
