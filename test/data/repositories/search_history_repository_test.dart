import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/data/models/search_history.dart';
import 'package:fmp/data/repositories/search_history_repository.dart';

/// 真實 Isar 整合測試——驗證 SearchHistoryRepository 的去重、修剪、上限淘汰、
/// 排序、刪除、清空與前綴建議邏輯（C10 從 SearchService 搬過來的業務規則）。
/// 先前的 Fake-based 測試完全跳過這段邏輯；這是第一個真正覆蓋它的測試。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchHistoryRepository', () {
    late Directory tempDir;
    late Isar isar;
    late SearchHistoryRepository repo;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('search_history_');
      isar = await Isar.open(
        [SearchHistorySchema],
        directory: tempDir.path,
        name: 'search_history_test',
      );
      repo = SearchHistoryRepository(isar);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('saveQuery trims whitespace; empty/whitespace-only ignored', () async {
      await repo.saveQuery('   ');
      expect(await repo.getRecent(), isEmpty);

      await repo.saveQuery('  hello  ');
      final recent = await repo.getRecent();
      expect(recent.length, 1);
      expect(recent.first.query, 'hello');
    });

    test('saveQuery dedups by query (re-saving moves entry to most recent)',
        () async {
      await repo.saveQuery('foo');
      await Future.delayed(const Duration(milliseconds: 2));
      await repo.saveQuery('bar');
      await Future.delayed(const Duration(milliseconds: 2));
      await repo.saveQuery('foo'); // 重新儲存已存在查詢 → 去重後成為最新

      final recent = await repo.getRecent();
      expect(recent.length, 2);
      expect(recent.first.query, 'foo'); // 最新
      expect(recent.map((h) => h.query).toSet(), {'foo', 'bar'});
    });

    test('getRecent returns newest-first and respects limit', () async {
      for (final q in ['a', 'b', 'c', 'd']) {
        await repo.saveQuery(q);
        await Future.delayed(const Duration(milliseconds: 2));
      }
      final recent = await repo.getRecent(limit: 3);
      expect(recent.map((h) => h.query).toList(), ['d', 'c', 'b']);
    });

    test('saveQuery caps history to maxSearchHistoryCount (evicts oldest)',
        () async {
      final cap = AppConstants.maxSearchHistoryCount;
      // 存入 cap + 5 個相異查詢，時間戳嚴格遞增（2ms 間隔）。
      for (var i = 0; i < cap + 5; i++) {
        await repo.saveQuery('query-$i');
        await Future.delayed(const Duration(milliseconds: 2));
      }

      final all = await repo.getRecent(limit: 1000);
      expect(all.length, cap);
      // 最近的保留、最舊的被淘汰。
      expect(all.any((h) => h.query == 'query-${cap + 4}'), isTrue);
      expect(all.any((h) => h.query == 'query-0'), isFalse);
    });

    test('deleteById removes a single entry', () async {
      await repo.saveQuery('keep');
      await repo.saveQuery('delete-me');
      final before = await repo.getRecent();
      final target = before.firstWhere((h) => h.query == 'delete-me');
      await repo.deleteById(target.id);
      final after = await repo.getRecent();
      expect(after.length, 1);
      expect(after.first.query, 'keep');
    });

    test('clear removes everything', () async {
      await repo.saveQuery('a');
      await repo.saveQuery('b');
      await repo.clear();
      expect(await repo.getRecent(), isEmpty);
      expect(await isar.searchHistorys.count(), 0);
    });

    test(
        'searchByPrefix: empty prefix returns recent 5; otherwise case-insensitive contains',
        () async {
      for (final q in ['apple', 'Application', 'banana', 'apricot', 'cherry']) {
        await repo.saveQuery(q);
        await Future.delayed(const Duration(milliseconds: 2));
      }

      // 空前綴 → 最近 5 筆查詢（最新在前）。
      final empty = await repo.searchByPrefix('');
      expect(empty.length, 5);
      expect(empty.first, 'cherry');

      // 'ap' 比對 apple、Application（不分大小寫）、apricot。
      final ap = await repo.searchByPrefix('ap');
      expect(ap.toSet(), {'apricot', 'Application', 'apple'});
      // 'AP' 不分大小寫 → 同一組。
      final upper = await repo.searchByPrefix('AP');
      expect(upper.toSet(), {'apricot', 'Application', 'apple'});
    });
  });
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') {
      continue;
    }
    final packageDir = Directory(
      packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
