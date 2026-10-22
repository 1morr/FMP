import 'package:isar_community/isar.dart';

/// 把一組 Isar schema 描述成可比對的 JSON 值（collection 名、schema id、每個
/// property 的 id／名稱／型別、index、link、embedded）。
///
/// 凍結閘門（`test/legacy_import/legacy_schema_test.dart`）用它比對提交的
/// `*.g.dart` 與 `test/legacy_import/fixtures/legacy_schema.json`；那份 fixture
/// 是用同一個函式在舊專案的 `*.g.dart` 上產生一次（做法見 `README.md`）。
/// 輸出的 collection、property、index 都依名稱排序，所以比對不受宣告順序影響。
Map<String, Object?> describeLegacySchemas(
  List<CollectionSchema<dynamic>> schemas,
) {
  final sorted = [...schemas]..sort((a, b) => a.name.compareTo(b.name));
  return {
    'collections': [for (final schema in sorted) _collection(schema)],
  };
}

Map<String, Object?> _collection(CollectionSchema<dynamic> schema) {
  final indexes = schema.indexes.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final links = schema.links.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final embedded = schema.embeddedSchemas.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return {
    ..._object(schema),
    'idName': schema.idName,
    'indexes': [
      for (final index in indexes)
        {
          'id': index.id,
          'name': index.name,
          'unique': index.unique,
          'replace': index.replace,
          'properties': [
            for (final property in index.properties)
              {
                'name': property.name,
                'type': property.type.name,
                'caseSensitive': property.caseSensitive,
              },
          ],
        },
    ],
    'links': [
      for (final link in links)
        {
          'id': link.id,
          'name': link.name,
          'target': link.target,
          'single': link.single,
          'linkName': link.linkName,
        },
    ],
    'embedded': [for (final object in embedded) _object(object)],
  };
}

Map<String, Object?> _object(Schema<dynamic> schema) {
  final properties = schema.properties.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return {
    'name': schema.name,
    'id': schema.id,
    'properties': [
      for (final property in properties)
        {
          'id': property.id,
          'name': property.name,
          'type': property.type.schemaName,
          if (property.target != null) 'target': property.target,
          if (property.enumMap != null) 'enumMap': property.enumMap,
        },
    ],
  };
}
