// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lyrics_title_parse_cache.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLyricsTitleParseCacheCollection on Isar {
  IsarCollection<LyricsTitleParseCache> get lyricsTitleParseCaches =>
      this.collection();
}

const LyricsTitleParseCacheSchema = CollectionSchema(
  name: r'LyricsTitleParseCache',
  id: 2186950417259062788,
  properties: {
    r'confidence': PropertySchema(
      id: 0,
      name: r'confidence',
      type: IsarType.double,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'model': PropertySchema(
      id: 2,
      name: r'model',
      type: IsarType.string,
    ),
    r'parsedArtistName': PropertySchema(
      id: 3,
      name: r'parsedArtistName',
      type: IsarType.string,
    ),
    r'parsedTrackName': PropertySchema(
      id: 4,
      name: r'parsedTrackName',
      type: IsarType.string,
    ),
    r'provider': PropertySchema(
      id: 5,
      name: r'provider',
      type: IsarType.string,
    ),
    r'sourceType': PropertySchema(
      id: 6,
      name: r'sourceType',
      type: IsarType.string,
    ),
    r'trackUniqueKey': PropertySchema(
      id: 7,
      name: r'trackUniqueKey',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 8,
      name: r'updatedAt',
      type: IsarType.dateTime,
    )
  },
  estimateSize: _lyricsTitleParseCacheEstimateSize,
  serialize: _lyricsTitleParseCacheSerialize,
  deserialize: _lyricsTitleParseCacheDeserialize,
  deserializeProp: _lyricsTitleParseCacheDeserializeProp,
  idName: r'id',
  indexes: {
    r'trackUniqueKey': IndexSchema(
      id: -1430557820884415850,
      name: r'trackUniqueKey',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'trackUniqueKey',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _lyricsTitleParseCacheGetId,
  getLinks: _lyricsTitleParseCacheGetLinks,
  attach: _lyricsTitleParseCacheAttach,
  version: '3.1.0+1',
);

int _lyricsTitleParseCacheEstimateSize(
  LyricsTitleParseCache object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.model.length * 3;
  {
    final value = object.parsedArtistName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.parsedTrackName.length * 3;
  bytesCount += 3 + object.provider.length * 3;
  bytesCount += 3 + object.sourceType.length * 3;
  bytesCount += 3 + object.trackUniqueKey.length * 3;
  return bytesCount;
}

void _lyricsTitleParseCacheSerialize(
  LyricsTitleParseCache object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDouble(offsets[0], object.confidence);
  writer.writeDateTime(offsets[1], object.createdAt);
  writer.writeString(offsets[2], object.model);
  writer.writeString(offsets[3], object.parsedArtistName);
  writer.writeString(offsets[4], object.parsedTrackName);
  writer.writeString(offsets[5], object.provider);
  writer.writeString(offsets[6], object.sourceType);
  writer.writeString(offsets[7], object.trackUniqueKey);
  writer.writeDateTime(offsets[8], object.updatedAt);
}

LyricsTitleParseCache _lyricsTitleParseCacheDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LyricsTitleParseCache();
  object.confidence = reader.readDouble(offsets[0]);
  object.createdAt = reader.readDateTime(offsets[1]);
  object.id = id;
  object.model = reader.readString(offsets[2]);
  object.parsedArtistName = reader.readStringOrNull(offsets[3]);
  object.parsedTrackName = reader.readString(offsets[4]);
  object.provider = reader.readString(offsets[5]);
  object.sourceType = reader.readString(offsets[6]);
  object.trackUniqueKey = reader.readString(offsets[7]);
  object.updatedAt = reader.readDateTime(offsets[8]);
  return object;
}

P _lyricsTitleParseCacheDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDouble(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _lyricsTitleParseCacheGetId(LyricsTitleParseCache object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _lyricsTitleParseCacheGetLinks(
    LyricsTitleParseCache object) {
  return [];
}

void _lyricsTitleParseCacheAttach(
    IsarCollection<dynamic> col, Id id, LyricsTitleParseCache object) {
  object.id = id;
}

extension LyricsTitleParseCacheByIndex
    on IsarCollection<LyricsTitleParseCache> {
  Future<LyricsTitleParseCache?> getByTrackUniqueKey(String trackUniqueKey) {
    return getByIndex(r'trackUniqueKey', [trackUniqueKey]);
  }

  LyricsTitleParseCache? getByTrackUniqueKeySync(String trackUniqueKey) {
    return getByIndexSync(r'trackUniqueKey', [trackUniqueKey]);
  }

  Future<bool> deleteByTrackUniqueKey(String trackUniqueKey) {
    return deleteByIndex(r'trackUniqueKey', [trackUniqueKey]);
  }

  bool deleteByTrackUniqueKeySync(String trackUniqueKey) {
    return deleteByIndexSync(r'trackUniqueKey', [trackUniqueKey]);
  }

  Future<List<LyricsTitleParseCache?>> getAllByTrackUniqueKey(
      List<String> trackUniqueKeyValues) {
    final values = trackUniqueKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'trackUniqueKey', values);
  }

  List<LyricsTitleParseCache?> getAllByTrackUniqueKeySync(
      List<String> trackUniqueKeyValues) {
    final values = trackUniqueKeyValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'trackUniqueKey', values);
  }

  Future<int> deleteAllByTrackUniqueKey(List<String> trackUniqueKeyValues) {
    final values = trackUniqueKeyValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'trackUniqueKey', values);
  }

  int deleteAllByTrackUniqueKeySync(List<String> trackUniqueKeyValues) {
    final values = trackUniqueKeyValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'trackUniqueKey', values);
  }

  Future<Id> putByTrackUniqueKey(LyricsTitleParseCache object) {
    return putByIndex(r'trackUniqueKey', object);
  }

  Id putByTrackUniqueKeySync(LyricsTitleParseCache object,
      {bool saveLinks = true}) {
    return putByIndexSync(r'trackUniqueKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByTrackUniqueKey(List<LyricsTitleParseCache> objects) {
    return putAllByIndex(r'trackUniqueKey', objects);
  }

  List<Id> putAllByTrackUniqueKeySync(List<LyricsTitleParseCache> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'trackUniqueKey', objects, saveLinks: saveLinks);
  }
}

extension LyricsTitleParseCacheQueryWhereSort
    on QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QWhere> {
  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterWhere>
      anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension LyricsTitleParseCacheQueryWhere on QueryBuilder<LyricsTitleParseCache,
    LyricsTitleParseCache, QWhereClause> {
  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterWhereClause>
      idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterWhereClause>
      trackUniqueKeyEqualTo(String trackUniqueKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'trackUniqueKey',
        value: [trackUniqueKey],
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterWhereClause>
      trackUniqueKeyNotEqualTo(String trackUniqueKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'trackUniqueKey',
              lower: [],
              upper: [trackUniqueKey],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'trackUniqueKey',
              lower: [trackUniqueKey],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'trackUniqueKey',
              lower: [trackUniqueKey],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'trackUniqueKey',
              lower: [],
              upper: [trackUniqueKey],
              includeUpper: false,
            ));
      }
    });
  }
}

extension LyricsTitleParseCacheQueryFilter on QueryBuilder<
    LyricsTitleParseCache, LyricsTitleParseCache, QFilterCondition> {
  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> confidenceEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'confidence',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> confidenceGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'confidence',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> confidenceLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'confidence',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> confidenceBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'confidence',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> modelEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> modelGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> modelLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> modelBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'model',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> modelStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> modelEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      modelContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      modelMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'model',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> modelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'model',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> modelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'model',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedArtistNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'parsedArtistName',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedArtistNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'parsedArtistName',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedArtistNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'parsedArtistName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedArtistNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'parsedArtistName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedArtistNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'parsedArtistName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedArtistNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'parsedArtistName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedArtistNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'parsedArtistName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedArtistNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'parsedArtistName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      parsedArtistNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'parsedArtistName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      parsedArtistNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'parsedArtistName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedArtistNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'parsedArtistName',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedArtistNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'parsedArtistName',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedTrackNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'parsedTrackName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedTrackNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'parsedTrackName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedTrackNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'parsedTrackName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedTrackNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'parsedTrackName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedTrackNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'parsedTrackName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedTrackNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'parsedTrackName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      parsedTrackNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'parsedTrackName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      parsedTrackNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'parsedTrackName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedTrackNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'parsedTrackName',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> parsedTrackNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'parsedTrackName',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> providerEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'provider',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> providerGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'provider',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> providerLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'provider',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> providerBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'provider',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> providerStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'provider',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> providerEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'provider',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      providerContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'provider',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      providerMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'provider',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> providerIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'provider',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> providerIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'provider',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> sourceTypeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> sourceTypeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sourceType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> sourceTypeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sourceType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> sourceTypeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sourceType',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> sourceTypeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sourceType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> sourceTypeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sourceType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      sourceTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sourceType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      sourceTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sourceType',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> sourceTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sourceType',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> sourceTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sourceType',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> trackUniqueKeyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'trackUniqueKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> trackUniqueKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'trackUniqueKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> trackUniqueKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'trackUniqueKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> trackUniqueKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'trackUniqueKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> trackUniqueKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'trackUniqueKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> trackUniqueKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'trackUniqueKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      trackUniqueKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'trackUniqueKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
          QAfterFilterCondition>
      trackUniqueKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'trackUniqueKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> trackUniqueKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'trackUniqueKey',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> trackUniqueKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'trackUniqueKey',
        value: '',
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> updatedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> updatedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache,
      QAfterFilterCondition> updatedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension LyricsTitleParseCacheQueryObject on QueryBuilder<
    LyricsTitleParseCache, LyricsTitleParseCache, QFilterCondition> {}

extension LyricsTitleParseCacheQueryLinks on QueryBuilder<LyricsTitleParseCache,
    LyricsTitleParseCache, QFilterCondition> {}

extension LyricsTitleParseCacheQuerySortBy
    on QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QSortBy> {
  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByConfidence() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confidence', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByConfidenceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confidence', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByModel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'model', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByModelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'model', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByParsedArtistName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parsedArtistName', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByParsedArtistNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parsedArtistName', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByParsedTrackName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parsedTrackName', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByParsedTrackNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parsedTrackName', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByProvider() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'provider', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByProviderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'provider', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortBySourceType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceType', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortBySourceTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceType', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByTrackUniqueKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackUniqueKey', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByTrackUniqueKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackUniqueKey', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension LyricsTitleParseCacheQuerySortThenBy
    on QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QSortThenBy> {
  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByConfidence() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confidence', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByConfidenceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confidence', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByModel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'model', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByModelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'model', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByParsedArtistName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parsedArtistName', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByParsedArtistNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parsedArtistName', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByParsedTrackName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parsedTrackName', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByParsedTrackNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parsedTrackName', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByProvider() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'provider', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByProviderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'provider', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenBySourceType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceType', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenBySourceTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceType', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByTrackUniqueKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackUniqueKey', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByTrackUniqueKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackUniqueKey', Sort.desc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension LyricsTitleParseCacheQueryWhereDistinct
    on QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QDistinct> {
  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QDistinct>
      distinctByConfidence() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'confidence');
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QDistinct>
      distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QDistinct>
      distinctByModel({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'model', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QDistinct>
      distinctByParsedArtistName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'parsedArtistName',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QDistinct>
      distinctByParsedTrackName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'parsedTrackName',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QDistinct>
      distinctByProvider({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'provider', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QDistinct>
      distinctBySourceType({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sourceType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QDistinct>
      distinctByTrackUniqueKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'trackUniqueKey',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LyricsTitleParseCache, LyricsTitleParseCache, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension LyricsTitleParseCacheQueryProperty on QueryBuilder<
    LyricsTitleParseCache, LyricsTitleParseCache, QQueryProperty> {
  QueryBuilder<LyricsTitleParseCache, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<LyricsTitleParseCache, double, QQueryOperations>
      confidenceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'confidence');
    });
  }

  QueryBuilder<LyricsTitleParseCache, DateTime, QQueryOperations>
      createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<LyricsTitleParseCache, String, QQueryOperations>
      modelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'model');
    });
  }

  QueryBuilder<LyricsTitleParseCache, String?, QQueryOperations>
      parsedArtistNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'parsedArtistName');
    });
  }

  QueryBuilder<LyricsTitleParseCache, String, QQueryOperations>
      parsedTrackNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'parsedTrackName');
    });
  }

  QueryBuilder<LyricsTitleParseCache, String, QQueryOperations>
      providerProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'provider');
    });
  }

  QueryBuilder<LyricsTitleParseCache, String, QQueryOperations>
      sourceTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourceType');
    });
  }

  QueryBuilder<LyricsTitleParseCache, String, QQueryOperations>
      trackUniqueKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'trackUniqueKey');
    });
  }

  QueryBuilder<LyricsTitleParseCache, DateTime, QQueryOperations>
      updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
