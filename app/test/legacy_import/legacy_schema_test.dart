import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/legacy_import/isar/schema_description.dart';
import 'package:fmp/legacy_import/isar/schemas.dart';

/// 凍結閘門：提交的 `lib/legacy_import/isar/*.g.dart` 與舊專案的 schema 一致。
///
/// 舊庫是別人機器上的檔案，Isar 以 collection／property 的 id 與型別讀它；
/// 重新產生或改模型而 id、型別變了，讀出來就是錯的值而不是錯誤。fixture 由舊專案
/// 的 `*.g.dart` 產生一次（`lib/legacy_import/isar/README.md`），不再重產。
void main() {
  final fixtureFile = File('test/legacy_import/fixtures/legacy_schema.json');

  Map<String, Object?> frozen() =>
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, Object?>;

  /// 目前提交的 schema 的描述，經 JSON 往返成純值（可以放心修改的複本）。
  Map<String, Object?> committed() =>
      jsonDecode(jsonEncode(describeLegacySchemas(legacyIsarSchemas)))
          as Map<String, Object?>;

  List<Map<String, Object?>> collectionsOf(Map<String, Object?> description) =>
      (description['collections'] as List).cast<Map<String, Object?>>();

  test('the committed schemas equal the frozen fixture', () {
    expect(committed(), equals(frozen()));
  });

  test('the fixture covers the 11 collections and 2 embedded objects', () {
    final collections = collectionsOf(frozen());
    expect(collections.map((c) => c['name']), [
      'Account',
      'DownloadTask',
      'LyricsMatch',
      'LyricsTitleParseCache',
      'PlayHistory',
      'PlayQueue',
      'Playlist',
      'RadioStation',
      'SearchHistory',
      'Settings',
      'Track',
    ]);
    final embedded = {
      for (final c in collections)
        for (final e in (c['embedded'] as List).cast<Map<String, Object?>>())
          e['name'],
    };
    expect(embedded, {'PlaylistDownloadInfo', 'SourceSettingsEntry'});
  });

  group('mutations', () {
    test('renaming a property is caught', () {
      final changed = committed();
      final first = collectionsOf(changed).first;
      final property = (first['properties'] as List).first as Map;
      property['name'] = '${property['name']}Renamed';
      expect(changed, isNot(equals(frozen())));
    });

    test('changing a property type is caught', () {
      final changed = committed();
      final first = collectionsOf(changed).first;
      final property = (first['properties'] as List).first as Map;
      property['type'] = property['type'] == 'Long' ? 'String' : 'Long';
      expect(changed, isNot(equals(frozen())));
    });

    test('changing a schema id is caught', () {
      final changed = committed();
      final first = collectionsOf(changed).first;
      first['id'] = (first['id'] as int) + 1;
      expect(changed, isNot(equals(frozen())));
    });

    test('changing an index is caught', () {
      final changed = committed();
      final track = collectionsOf(changed)
          .firstWhere((c) => c['name'] == 'Track');
      (track['indexes'] as List).removeLast();
      expect(changed, isNot(equals(frozen())));
    });

    test('opening with a collection missing is caught', () {
      final partial = describeLegacySchemas(legacyIsarSchemas.skip(1).toList());
      expect(
        jsonDecode(jsonEncode(partial)) as Map<String, Object?>,
        isNot(equals(frozen())),
      );
    });

    test('reordering keys or reformatting the JSON is not', () {
      // 鍵順序與縮排都換掉，內容不變。
      Object? reverseKeys(Object? value) {
        if (value is Map) {
          return {
            for (final key in value.keys.toList().reversed)
              key: reverseKeys(value[key]),
          };
        }
        if (value is List) return [for (final item in value) reverseKeys(item)];
        return value;
      }

      final reformatted =
          jsonDecode(jsonEncode(reverseKeys(frozen()))) as Map<String, Object?>;
      expect(committed(), equals(reformatted));
    });

    test('the order the schemas are listed in is not', () {
      final reversed = describeLegacySchemas(
        legacyIsarSchemas.reversed.toList(),
      );
      expect(
        jsonDecode(jsonEncode(reversed)) as Map<String, Object?>,
        equals(frozen()),
      );
    });
  });
}
